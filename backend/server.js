const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const security = require('./security');
const driveService = require('./driveService');
const ocrService = require('./ocrService');
const whatsappService = require('./whatsappService');
const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL || 'https://45-137-192-195.sslip.io').replace(/\/+$/, '');
let admin;
try {
  admin = require('firebase-admin');
} catch (e) {
  admin = null;
}

const app = express();
const PORT = process.env.PORT || 3000;
const DB_FILE = path.join(__dirname, 'data.json');

// Data source: production (Render sets RENDER=true, or NODE_ENV=production) reads and writes
// Firebase Firestore; local development always uses backend/data.json so it never touches
// production data. DATA_SOURCE=firestore|local overrides the automatic choice.
let firestore = null;
const isProduction = process.env.NODE_ENV === 'production' || !!process.env.RENDER;
const dataSource = String(
  process.env.DATA_SOURCE || (process.env.USE_LOCAL_DB === 'true' ? 'local' : (isProduction ? 'firestore' : 'local'))
).toLowerCase();
const forceLocalDb = dataSource !== 'firestore';
console.log(`ℹ️ Entorno: ${isProduction ? 'PRODUCCIÓN' : 'LOCAL'} • Fuente de datos: ${forceLocalDb ? 'data.json local' : 'Firebase Firestore'}`);

if (!forceLocalDb) {
  try {
    let serviceAccount = null;
    if (process.env.FIREBASE_SERVICE_ACCOUNT) {
      serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    } else {
      const keyPath = path.join(__dirname, 'serviceAccountKey.json');
      if (fs.existsSync(keyPath)) {
        serviceAccount = require(keyPath);
      }
    }

    if (serviceAccount && admin) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
      });
      firestore = admin.firestore();
      console.log('✅ Conectado exitosamente a Google Cloud Firestore (100% Gratis)');
    } else {
      console.log('ℹ️ Firebase no configurado. Usando almacenamiento local data.json');
    }
  } catch (err) {
    console.warn('⚠️ No se pudo conectar a Firebase, usando data.json local:', err.message);
  }
} else {
  console.log('ℹ️ Usando almacenamiento local data.json (Firestore desactivado en este entorno)');
}

// ---------------------------------------------------------------------------
// Firestore storage: the database is saved as serialized JSON split into chunk
// documents plus a manifest. Firestore rejects arrays inside arrays and documents
// over 1 MiB; storing text chunks avoids both limits.
// ---------------------------------------------------------------------------
const FIRESTORE_COLLECTION = 'rifaapp';
const FIRESTORE_MANIFEST = 'database';
const FIRESTORE_CHUNKED_FORMAT = 'rifamaster-chunked';
// Firestore limits documents to 1 MiB in UTF-8 bytes; a character can take up to 3 bytes (á, ñ, €),
// so 300k characters stay under ~900 KB in the worst case.
const FIRESTORE_CHUNK_CHARS = 300000;

async function readFirestoreDb(doc, name = FIRESTORE_MANIFEST) {
  const manifest = doc.data();
  if (!manifest || manifest.format !== FIRESTORE_CHUNKED_FORMAT) return manifest; // legacy single document
  const col = firestore.collection(FIRESTORE_COLLECTION);
  const parts = [];
  for (let i = 0; i < manifest.chunks; i++) {
    const chunk = await col.doc(`${name}_${manifest.version}_${i}`).get();
    if (!chunk.exists) throw new Error(`Falta el fragmento ${i} de la versión ${manifest.version}`);
    parts.push(chunk.data().data);
  }
  return JSON.parse(parts.join(''));
}

// Version of the Firestore database this server last read or wrote. During a deploy the old
// and new servers run at the same time; a server whose version is outdated must not overwrite.
let firestoreVersion = null;
class FirestoreConflictError extends Error {}

// Versions written by this server. A request may read the manifest right after this server switched
// it but before firestoreVersion is updated: that version is ours, not another server's, and must
// not trigger a reload (a reload would drop changes still waiting to be written).
const ownFirestoreVersions = new Set();
function rememberOwnVersion(version) {
  ownFirestoreVersions.add(version);
  if (ownFirestoreVersions.size > 50) ownFirestoreVersions.delete(ownFirestoreVersions.values().next().value);
}

async function writeFirestoreDb(stored, name = FIRESTORE_MANIFEST) {
  const col = firestore.collection(FIRESTORE_COLLECTION);
  const json = JSON.stringify(stored);
  const version = String(Date.now());
  const chunks = [];
  for (let i = 0; i < json.length; i += FIRESTORE_CHUNK_CHARS) chunks.push(json.slice(i, i + FIRESTORE_CHUNK_CHARS));

  const previous = await col.doc(name).get();
  const previousManifest = previous.exists ? previous.data() : null;
  if (name === FIRESTORE_MANIFEST && firestoreVersion !== null) {
    const currentVersion = previousManifest ? (previousManifest.version || 'legacy') : 'none';
    if (currentVersion !== firestoreVersion) {
      throw new FirestoreConflictError(
        `Otro servidor guardó datos más recientes (versión ${currentVersion}, este servidor tenía ${firestoreVersion}).`
      );
    }
  }

  // 1) new chunks, 2) switch the manifest (readers see either the old or the new version), 3) remove old chunks
  for (let i = 0; i < chunks.length; i++) {
    await col.doc(`${name}_${version}_${i}`).set({ data: chunks[i] });
  }
  if (name === FIRESTORE_MANIFEST) rememberOwnVersion(version);
  await col.doc(name).set({
    format: FIRESTORE_CHUNKED_FORMAT,
    version,
    chunks: chunks.length,
    bytes: json.length,
    updatedAt: new Date().toISOString()
  });
  if (name === FIRESTORE_MANIFEST) firestoreVersion = version;
  if (previousManifest && previousManifest.format === FIRESTORE_CHUNKED_FORMAT) {
    for (let i = 0; i < previousManifest.chunks; i++) {
      await col.doc(`${name}_${previousManifest.version}_${i}`).delete().catch(() => {});
    }
  }
}

// Saves are serialized and coalesced: only the latest state is written. A failed write is
// retried with increasing waits (the data stays in memory and in data.json meanwhile) and the
// status is exposed in /api/backup so a failure is never silent.
const storageStatus = { lastSavedAt: null, lastError: null, lastErrorAt: null, retrying: false };
const RETRY_DELAYS_MS = [2000, 5000, 15000, 30000, 60000];
let firestoreWriting = false;
let firestorePending = null;
function queueFirestoreSave(stored) {
  firestorePending = stored;
  if (firestoreWriting) return;
  firestoreWriting = true;
  (async () => {
    let attempt = 0;
    while (firestorePending) {
      const next = firestorePending;
      firestorePending = null;
      try {
        await writeFirestoreDb(next);
        if (attempt > 0) console.log(`✅ Datos guardados en Cloud Firestore tras ${attempt} reintento(s).`);
        storageStatus.lastSavedAt = new Date().toISOString();
        storageStatus.lastError = null;
        storageStatus.retrying = false;
        attempt = 0;
      } catch (err) {
        if (err instanceof FirestoreConflictError) {
          // Never overwrite newer data written by another server: take the newer data instead
          console.error(`⚠️ CONFLICTO: ${err.message} No se sobrescribe; se recargan los datos de Firestore.`);
          storageStatus.lastError = err.message;
          storageStatus.lastErrorAt = new Date().toISOString();
          storageStatus.retrying = false;
          firestorePending = null;
          await reloadFromFirestoreOnce().catch(e => console.error('Error recargando desde Firestore:', e.message));
          continue;
        }
        storageStatus.lastError = err.message;
        storageStatus.lastErrorAt = new Date().toISOString();
        storageStatus.retrying = true;
        const delay = RETRY_DELAYS_MS[Math.min(attempt, RETRY_DELAYS_MS.length - 1)];
        attempt++;
        console.error(`❌ Error guardando en Cloud Firestore (reintento ${attempt} en ${delay / 1000}s):`, err.message);
        await new Promise(r => setTimeout(r, delay));
        // Retry this state unless a newer one arrived meanwhile
        if (!firestorePending) firestorePending = next;
      }
    }
    firestoreWriting = false;
  })();
}

app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With', 'Accept', 'Origin']
}));
app.options('*', cors());
// Las fotos de soportes viajan en base64 dentro del JSON: 10 MB se quedaba corto con capturas pesadas (nginx admite 50 MB)
app.use(express.json({ limit: '25mb' }));
app.set('trust proxy', true);
// Errores al leer el cuerpo de la petición: respuesta clara en JSON (antes salía una página de error genérica)
app.use((err, req, res, next) => {
  if (err && (err.type === 'entity.too.large' || err.name === 'PayloadTooLargeError')) {
    return res.status(413).json({ error: 'La imagen es demasiado pesada. Tome una captura de pantalla del comprobante o reduzca la foto e intente de nuevo.', code: 'PAYLOAD_TOO_LARGE' });
  }
  if (err && err.type === 'entity.parse.failed') return res.status(400).json({ error: 'La solicitud no es válida.' });
  next(err);
});

// Never send password hashes or credentials to clients
app.use('/api', (req, res, next) => {
  const originalJson = res.json.bind(res);
  res.json = (body) => originalJson(security.stripSecrets(body));
  next();
});

// ---------------------------------------------------------------------------
// Ticket authenticity: every sold ticket gets a verification code signed with a secret
// kept in the database (db.settings.verificationSecret). The receipt's QR opens
// /verificar/<code>, a public page that confirms the ticket against the live data.
// The code changes when a sale is voided/resold, so old printed receipts stop validating.
// ---------------------------------------------------------------------------
function ensureVerificationSecret(target) {
  if (!target.settings || typeof target.settings !== 'object') target.settings = {};
  if (target.settings.verificationSecret) return false;
  target.settings.verificationSecret = require('crypto').randomBytes(32).toString('base64');
  return true;
}

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I to avoid reading mistakes
// El código se calcula con HMAC (≈9 µs). En la lista de 5000 boletas eso eran ~45 ms por consulta y bloqueaba el servidor para todos:
// se guarda por boleta junto con los datos de los que depende, así que cambia solo si cambian.
const verificationCodeCache = new Map();

function ticketVerificationCode(ticket) {
  if (!ticket || ticket.status === 'DISPONIBLE' || !db.settings || !db.settings.verificationSecret) return null;
  const secret = db.settings.verificationSecret;
  const input = `${ticket.id}|${ticket.raffleId}|${ticket.assignedDate || ''}|${(ticket.annulments || []).length}`;
  const cached = verificationCodeCache.get(ticket.id);
  if (cached && cached.input === input && cached.secret === secret) return cached.code;
  const mac = require('crypto').createHmac('sha256', secret).update(input).digest();
  let code = '';
  for (let i = 0; i < 10; i++) code += CODE_ALPHABET[mac[i] % CODE_ALPHABET.length];
  code = `${code.slice(0, 5)}-${code.slice(5)}`;
  verificationCodeCache.set(ticket.id, { input, secret, code });
  return code;
}

function withVerification(ticket) {
  const code = ticketVerificationCode(ticket);
  return code ? { ...ticket, verificationCode: code } : ticket;
}

function escapeHtml(value) {
  return String(value == null ? '' : value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

/** "Jhon Pancho Pérez" -> "Jh** Pa**** Pé***" (enough to recognize it, without exposing it). */
function maskName(name) {
  return String(name || '').trim().split(/\s+/).filter(Boolean).map(w => w.slice(0, 2) + '*'.repeat(Math.max(1, w.length - 2))).join(' ');
}

const verifyHits = new Map();
function verifyRateLimited(ip) {
  const now = Date.now();
  const entry = verifyHits.get(ip) || { count: 0, since: now };
  if (now - entry.since > 60000) { entry.count = 0; entry.since = now; }
  entry.count++;
  verifyHits.set(ip, entry);
  return entry.count > 30;
}

// ---------------------------------------------------------------------------
// Terms and conditions: each company's admin edits a template (company.termsTemplate);
// {placeholders} are filled with each raffle's data. Shown on the verification page.
// ---------------------------------------------------------------------------
const DEFAULT_TERMS_TEMPLATE = `1. La rifa "{rifa}" es organizada por {empresa}.
2. El sorteo principal se realiza el {fecha_sorteo} con {loteria}.
3. Gana la boleta cuyo número coincida con {cifras_ganadoras} del resultado oficial de la lotería.
4. Valor de cada boleta: {precio}. Total de boletas: {total_boletas} ({numeros_por_boleta} número(s) por boleta).
5. Para participar la boleta debe estar pagada en su totalidad antes del sorteo, salvo que la organización indique otra condición.
6. Sorteos semanales: {sorteos_semanales}.
7. El premio se entrega al titular registrado de la boleta, presentando este comprobante y su documento de identidad. El código de verificación debe aparecer como válido en esta página.
8. El ganador tiene 30 días calendario desde el sorteo para reclamar el premio.
9. Las boletas anuladas, modificadas o no pagadas no participan.
10. Al comprar la boleta, el participante acepta estos términos y condiciones.`;

const TERMS_PLACEHOLDERS = [
  ['empresa', 'Nombre de la empresa'],
  ['rifa', 'Nombre de la rifa'],
  ['descripcion', 'Descripción de la rifa'],
  ['fecha_sorteo', 'Fecha del sorteo principal'],
  ['loteria', 'Lotería del sorteo principal'],
  ['loteria_semanal', 'Lotería de los sorteos semanales'],
  ['cifras_ganadoras', 'Cifras que deciden el ganador (ej: las 2 últimas cifras)'],
  ['precio', 'Valor de la boleta'],
  ['total_boletas', 'Cantidad de boletas'],
  ['numeros_por_boleta', 'Números (oportunidades) por boleta'],
  ['sorteos_semanales', 'Día, lotería y abono mínimo de los sorteos semanales, o "no aplica"'],
  ['abono_minimo', 'Abono mínimo para participar en sorteos semanales']
];

/** Lottery of the main draw (older raffles only had the weekly one, lotteryName). */
function mainLotteryOf(raffle) {
  return String(raffle.mainLotteryName || raffle.lotteryName || '').trim();
}

/** "la Lotería de Boyacá"; names that are not "Lotería ..." are used as they are. */
function lotteryPhrase(name) {
  if (!name) return 'la lotería anunciada';
  return /^loter[ií]a/i.test(name) ? `la ${name}` : name;
}

function winningRuleText(raffle) {
  const digits = raffle.digits || 4;
  if (digits >= 4) return raffle.allowCombined ? 'el número completo o combinado' : 'el número completo';
  const pos = raffle.winningDigitsPosition || 'ULTIMAS';
  const base = pos === 'MEDIO' ? `las ${digits} cifras del medio` : `las ${digits} ${pos === 'PRIMERAS' ? 'primeras' : 'últimas'} cifras`;
  return raffle.allowCombined ? `${base} (también combinado)` : base;
}

function formatRaffleDate(dateStr, longFormat = true) {
  if (!dateStr) return 'la fecha anunciada';
  const str = String(dateStr).trim();
  const m = str.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) {
    const year = m[1];
    const monthNum = parseInt(m[2], 10);
    const dayNum = parseInt(m[3], 10);
    const day = String(dayNum).padStart(2, '0');
    if (!longFormat) return `${day}/${String(monthNum).padStart(2, '0')}/${year}`;
    const months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    const month = months[monthNum - 1] || '';
    return `${day} de ${month} de ${year}`;
  }
  try {
    const d = new Date(str);
    if (isNaN(d.getTime())) return 'la fecha anunciada';
    return d.toLocaleDateString('es-CO', longFormat ? { day: '2-digit', month: 'long', year: 'numeric' } : {});
  } catch (_) {
    return 'la fecha anunciada';
  }
}

/** Convierte cualquier enlace de Drive (uc?export=view, /file/d/ID/view, open?id=) al enlace directo de imagen. */
function normalizeDriveImageUrl(url) {
  const u = String(url || '').trim();
  if (!u || !/(drive|docs)\.google\.com/i.test(u)) return u;
  const m = u.match(/\/d\/([A-Za-z0-9_-]{10,})/) || u.match(/[?&]id=([A-Za-z0-9_-]{10,})/);
  return m ? `https://lh3.googleusercontent.com/d/${m[1]}=s1600` : u;
}

function parseDrawDate(value) {
  const s = String(value || '').trim();
  const dmy = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  const d = dmy ? new Date(Number(dmy[3]), Number(dmy[2]) - 1, Number(dmy[1])) : new Date(s);
  return isNaN(d.getTime()) ? null : d;
}

/** Abono mínimo para participar en un sorteo semanal: el del propio sorteo (cada uno tiene el suyo) o, si no lo define, el de la rifa. */
function weeklyMinAbonoOf(raffle, prize) {
  const price = Number(raffle.ticketPrice) || 0;
  const hasOwn = prize && prize.minAbonoType && prize.minAbonoValue !== undefined && prize.minAbonoValue !== null;
  const type = hasOwn ? prize.minAbonoType : (raffle.weeklyMinAbonoType || 'PORCENTAJE');
  const value = hasOwn ? Number(prize.minAbonoValue) : (Number.isFinite(Number(raffle.weeklyMinAbonoValue)) && raffle.weeklyMinAbonoValue !== null && raffle.weeklyMinAbonoValue !== undefined ? Number(raffle.weeklyMinAbonoValue) : 50);
  return type === 'PORCENTAJE' ? price * value / 100 : value;
}

/** Próximo sorteo semanal (el primero que aún no se juega; si todos pasaron, el último). */
function nextWeeklyPrize(raffle) {
  const prizes = Array.isArray(raffle.weeklyPrizes) ? raffle.weeklyPrizes : [];
  if (prizes.length === 0) return null;
  const from = new Date(Date.now() - 24 * 3600 * 1000);
  const dated = prizes.map(p => ({ p, d: parseDrawDate(p.drawDate) })).filter(x => x.d).sort((a, b) => a.d - b.d);
  if (dated.length === 0) return prizes[0];
  return (dated.find(x => x.d >= from) || dated[dated.length - 1]).p;
}

/** Sorteo semanal que se está registrando: por nombre, luego por valor del premio, y si no, el próximo. */
function weeklyPrizeForDraw(raffle, drawName, prizeAmount) {
  const prizes = Array.isArray(raffle.weeklyPrizes) ? raffle.weeklyPrizes : [];
  const name = String(drawName || '').trim().toLowerCase();
  return (name && prizes.find(p => String(p.name || '').trim().toLowerCase() === name))
    || (Number(prizeAmount) > 0 && prizes.find(p => Number(p.amount) === Number(prizeAmount)))
    || nextWeeklyPrize(raffle);
}

function renderTerms(template, raffle, company) {
  const money = v => `$${Math.round(Number(v) || 0).toLocaleString('es-CO')}`;
  const date = formatRaffleDate(raffle.mainDrawDate, true);
  const minAbono = weeklyMinAbonoOf(raffle, nextWeeklyPrize(raffle));
  const lottery = lotteryPhrase(mainLotteryOf(raffle));
  const weeklyLottery = lotteryPhrase(String(raffle.lotteryName || '').trim() || mainLotteryOf(raffle));
  const values = {
    empresa: company.name || 'la organización',
    rifa: raffle.title || '',
    descripcion: raffle.description || '',
    fecha_sorteo: date,
    loteria: lottery,
    loteria_semanal: weeklyLottery,
    cifras_ganadoras: winningRuleText(raffle),
    precio: money(raffle.ticketPrice),
    total_boletas: String(raffle.totalTickets || ''),
    numeros_por_boleta: String(raffle.opportunitiesPerTicket || 1),
    abono_minimo: money(minAbono),
    sorteos_semanales: raffle.hasWeeklyDraws === false
      ? 'no aplica para esta rifa'
      : `cada ${raffle.weeklyDrawDay || 'semana'} con ${weeklyLottery}; participan las boletas con un abono mínimo de ${money(minAbono)}`
  };
  return String(template || DEFAULT_TERMS_TEMPLATE).replace(/\{([a-z_]+)\}/g, (m, key) => (key in values ? values[key] : m));
}

function verificationPage({ ok, title, rows = [], note = '', color, terms = '' }) {
  const accent = color || (ok ? '#059669' : '#DC2626');
  const rowsHtml = rows.map(([k, v]) => `<div class="row"><span>${escapeHtml(k)}</span><b>${escapeHtml(v)}</b></div>`).join('');
  return `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Verificación de boleta - Rifa Master</title><meta name="robots" content="noindex">
<style>
body{margin:0;font-family:Roboto,"Segoe UI",system-ui,sans-serif;background:#0F172A;color:#0F172A;display:flex;min-height:100vh;align-items:center;justify-content:center;padding:16px;box-sizing:border-box}
.card{background:#fff;border-radius:20px;max-width:420px;width:100%;overflow:hidden;box-shadow:0 20px 50px rgba(0,0,0,.4)}
.head{background:${accent};color:#fff;padding:22px;text-align:center}.icon{font-size:46px;line-height:1}.head h1{margin:8px 0 0;font-size:20px}
.body{padding:18px 20px}.row{display:flex;justify-content:space-between;gap:12px;padding:9px 0;border-bottom:1px solid #E2E8F0;font-size:14px}.row span{color:#64748B}.row b{text-align:right}
.note{font-size:12px;color:#64748B;margin-top:14px;line-height:1.45}
.terms{margin-top:14px;border:1px solid #E2E8F0;border-radius:12px;padding:10px 12px;font-size:12.5px}.terms summary{font-weight:700;cursor:pointer}.terms div{white-space:pre-wrap;line-height:1.5;margin-top:8px;color:#334155}.brand{text-align:center;font-size:11px;color:#94A3B8;padding:0 0 16px;letter-spacing:1px}
</style></head><body><div class="card"><div class="head"><div class="icon">${ok ? '✔' : '✖'}</div><h1>${escapeHtml(title)}</h1></div>
<div class="body">${rowsHtml}${note ? `<div class="note">${escapeHtml(note)}</div>` : ''}${terms ? `<details class="terms"><summary>Términos y condiciones</summary><div>${escapeHtml(terms)}</div></details>` : ''}</div><div class="brand">VERIFICADO POR RIFA MASTER</div></div></body></html>`;
}

// ---------------------------------------------------------------------------
// Legal pages (public, required by Google Play): privacy policy, terms of service and account /
// data deletion request. The platform's legal data is set by the SuperAdmin (db.settings.legal).
// ---------------------------------------------------------------------------
const DEFAULT_LEGAL = {
  brandName: 'RifaMaster',
  legalName: '',
  nit: '',
  contactEmail: '',
  contactPhone: '',
  address: '',
  city: 'Colombia',
  updatedOn: '2026-10-06'
};

function legalSettings() {
  return { ...DEFAULT_LEGAL, ...((db.settings || {}).legal || {}) };
}

function legalPage(title, bodyHtml) {
  const l = legalSettings();
  return `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(title)} - ${escapeHtml(l.brandName)}</title>
<style>
body{margin:0;font-family:Roboto,"Segoe UI",system-ui,sans-serif;background:#F1F5F9;color:#0F172A;line-height:1.6}
header{background:#0F172A;color:#fff;padding:18px 16px;text-align:center}header b{font-size:18px}header div{font-size:12px;color:#94A3B8}
main{max-width:820px;margin:0 auto;padding:20px 16px 40px}article{background:#fff;border-radius:16px;padding:20px 22px;box-shadow:0 4px 20px rgba(15,23,42,.08)}
h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:22px 0 6px;color:#1E3A8A}p,li{font-size:14.5px}.muted{color:#64748B;font-size:13px}
nav{text-align:center;margin-top:18px;font-size:13px}nav a{color:#2563EB;margin:0 8px}
label{display:block;font-weight:600;margin:12px 0 4px;font-size:14px}input,textarea,select{width:100%;box-sizing:border-box;padding:10px;border:1px solid #CBD5E1;border-radius:10px;font:inherit}
button{margin-top:16px;background:#DC2626;color:#fff;border:0;border-radius:10px;padding:12px 18px;font-weight:700;font-size:15px;cursor:pointer}
.ok{background:#ECFDF5;border:1px solid #6EE7B7;border-radius:12px;padding:14px}.warn{background:#FFFBEB;border:1px solid #FCD34D;border-radius:12px;padding:12px;font-size:13.5px}
</style></head><body><header><b>${escapeHtml(l.brandName)}</b><div>Plataforma de administración de rifas</div></header>
<main><article>${bodyHtml}</article><nav><a href="/terminos">Términos y condiciones</a>·<a href="/privacidad">Política de privacidad</a>·<a href="/eliminar-cuenta">Eliminar cuenta</a></nav></main></body></html>`;
}

/** Responsible party line, with the data the SuperAdmin filled in. */
function legalOwner() {
  const l = legalSettings();
  const parts = [
    l.legalName ? `<b>${escapeHtml(l.legalName)}</b>` : `<b>${escapeHtml(l.brandName)}</b>`,
    l.nit ? `NIT ${escapeHtml(l.nit)}` : '',
    l.address ? escapeHtml(l.address) : '',
    l.city ? escapeHtml(l.city) : ''
  ].filter(Boolean).join(', ');
  const contact = [l.contactEmail ? `correo <a href="mailto:${escapeHtml(l.contactEmail)}">${escapeHtml(l.contactEmail)}</a>` : '',
    l.contactPhone ? `teléfono ${escapeHtml(l.contactPhone)}` : ''].filter(Boolean).join(' y ');
  return { parts, contact: contact || 'los canales de contacto publicados en la aplicación', l };
}

app.get('/privacidad', (req, res) => {
  const { parts, contact, l } = legalOwner();
  const b = escapeHtml(l.brandName);
  res.send(legalPage('Política de privacidad', `
<h1>Política de privacidad y tratamiento de datos personales</h1>
<p class="muted">Última actualización: ${escapeHtml(l.updatedOn)}. Aplica a la aplicación ${b} (Android, iOS, Windows y web).</p>
<h2>1. Responsable</h2>
<p>${parts}. Contacto para asuntos de datos personales: ${contact}. Esta política se rige por la Ley 1581 de 2012, el Decreto 1377 de 2013 y demás normas colombianas de protección de datos.</p>
<h2>2. Qué es ${b} y roles en el tratamiento</h2>
<p>${b} es una herramienta para que empresas organizadoras administren sus rifas: boletas, compradores, pagos, asesores y sorteos. La aplicación <b>no vende boletas al público ni procesa pagos</b>: las empresas registran las ventas y los pagos que reciben por sus propios medios.</p>
<p>Respecto de los datos de los <b>compradores</b> que cada empresa registra, la empresa organizadora es la <b>Responsable</b> del tratamiento y ${b} actúa como <b>Encargado</b>, tratándolos solo para prestar el servicio. Respecto de los datos de las cuentas de usuario (administradores y asesores), ${b} es Responsable.</p>
<h2>3. Datos que se tratan</h2>
<ul>
<li><b>Cuentas de usuario:</b> nombre, correo electrónico, usuario, teléfono, cédula (asesores), contraseña (guardada cifrada con un algoritmo irreversible) y registros de actividad.</li>
<li><b>Compradores registrados por las empresas:</b> nombre, teléfono, cédula (opcional), números de boleta, abonos y pagos, medio de venta y, cuando hay transferencias, fecha, banco, número de aprobación y la imagen del soporte.</li>
<li><b>Datos técnicos:</b> dirección IP y datos del dispositivo necesarios para la seguridad (por ejemplo, limitar intentos de inicio de sesión) y, en el plan gratuito, identificadores de publicidad usados por Google para mostrar anuncios.</li>
</ul>
<p>La aplicación no accede a la ubicación, contactos, cámara ni micrófono del dispositivo. Las imágenes de soportes solo se cargan cuando el usuario las selecciona.</p>
<h2>4. Finalidades</h2>
<ul><li>Prestar el servicio: administrar rifas, ventas, pagos, caja, ganadores y comprobantes verificables.</li>
<li>Seguridad de las cuentas y prevención de fraude (por ejemplo, detectar números de aprobación de transferencias repetidos).</li>
<li>Enviar, a solicitud del usuario, mensajes por WhatsApp con comprobantes o recordatorios (la app solo abre WhatsApp con el mensaje; el envío lo hace el usuario).</li>
<li>Facturar y gestionar los planes de suscripción de las empresas.</li>
<li>Mostrar publicidad en el plan gratuito.</li></ul>
<h2>5. Con quién se comparten</h2>
<p>Los datos no se venden. Se usan proveedores tecnológicos que los procesan por cuenta de ${b}: <b>Google Cloud / Firebase</b> (almacenamiento de la base de datos), <b>Google Drive</b> (imágenes de soportes y copias de seguridad), <b>Render</b> (servidor) y, en el plan gratuito, <b>Google AdMob / AdSense</b> (publicidad). Estos proveedores pueden almacenar información fuera de Colombia, con medidas de seguridad adecuadas. Los datos también podrán entregarse a autoridades cuando la ley lo exija.</p>
<h2>6. Seguridad</h2>
<p>Las comunicaciones viajan cifradas (HTTPS), las contraseñas se guardan con hash y la base de datos se almacena cifrada. Cada empresa solo accede a sus propios datos.</p>
<h2>7. Conservación y eliminación</h2>
<ul><li>Cuando una empresa cierra una rifa, sus datos (boletas, compradores, pagos, ganadores y soportes) se eliminan automáticamente <b>45 días después</b> del cierre.</li>
<li>Las cuentas de usuario se conservan mientras estén activas o hasta que se solicite su eliminación.</li>
<li>Las copias de seguridad se renuevan periódicamente y se eliminan con el tiempo; pueden conservar datos por un período adicional limitado.</li>
<li>Algunos datos pueden conservarse cuando una obligación legal o contable lo exija.</li></ul>
<h2>8. Derechos de los titulares</h2>
<p>Usted puede conocer, actualizar, rectificar y solicitar la supresión de sus datos, revocar la autorización y presentar quejas ante la Superintendencia de Industria y Comercio. Escríbanos a ${contact}. Si usted es comprador de una rifa, también puede dirigirse a la empresa organizadora. Responderemos en los plazos de ley (consultas: 10 días hábiles; reclamos: 15 días hábiles).</p>
<p>Para eliminar una cuenta de usuario y sus datos use <a href="/eliminar-cuenta">esta página</a> o la opción "Solicitar eliminación de mi cuenta" dentro de la aplicación.</p>
<h2>9. Menores de edad</h2>
<p>La aplicación está dirigida a mayores de 18 años y no recolecta intencionalmente datos de menores.</p>
<h2>10. Cambios</h2>
<p>Esta política puede actualizarse; la fecha de la última actualización se indica al inicio.</p>`));
});

app.get('/terminos', (req, res) => {
  const { parts, contact, l } = legalOwner();
  const b = escapeHtml(l.brandName);
  res.send(legalPage('Términos y condiciones', `
<h1>Términos y condiciones de uso</h1>
<p class="muted">Última actualización: ${escapeHtml(l.updatedOn)}. Prestador del servicio: ${parts}.</p>
<h2>1. El servicio</h2>
<p>${b} es un software de administración para empresas que organizan rifas: registro de boletas y compradores, pagos, asesores, caja, sorteos, ganadores, comprobantes verificables y reportes. ${b} <b>no organiza rifas, no vende boletas al público, no recibe dineros de los compradores ni procesa pagos</b>; tampoco garantiza premios.</p>
<h2>2. Responsabilidad de la empresa organizadora</h2>
<ul><li>Cada empresa es la única responsable de sus rifas: obtener las autorizaciones que exija la ley (en Colombia, las rifas son juegos de suerte y azar regulados por la Ley 643 de 2001 y requieren autorización de la autoridad competente, como Coljuegos o la entidad territorial), cumplir sus condiciones, entregar los premios y atender a sus compradores.</li>
<li>Es responsable de los datos personales de sus compradores y de contar con su autorización para tratarlos, conforme a la Ley 1581 de 2012.</li>
<li>Debe registrar información veraz y no usar la plataforma para actividades ilegales, fraude o lavado de activos.</li></ul>
<h2>3. Cuentas</h2>
<p>Las cuentas son personales. El usuario debe guardar su contraseña y avisar de inmediato cualquier uso no autorizado. La empresa responde por las acciones de sus administradores y asesores.</p>
<h2>4. Planes, pagos y publicidad</h2>
<p>El plan Gratis incluye publicidad. El plan PRO se paga por períodos (1, 3, 6 o 12 meses) según los precios publicados en la aplicación; al vencer sin renovación, la cuenta vuelve al plan Gratis. Los pagos de los planes no son reembolsables, salvo que la ley disponga lo contrario.</p>
<h2>5. Datos y eliminación</h2>
<p>El tratamiento de datos se rige por la <a href="/privacidad">Política de privacidad</a>. Al cerrar una rifa, sus datos se eliminan 45 días después; la empresa debe descargar antes la información que necesite conservar.</p>
<h2>6. Disponibilidad y responsabilidad</h2>
<p>El servicio se presta "tal como está". Se hacen copias de seguridad periódicas, pero ${b} no responde por pérdidas derivadas de un uso indebido, de información incorrecta registrada por los usuarios, ni de las relaciones entre las empresas y sus compradores. En lo permitido por la ley, la responsabilidad de ${b} se limita al valor pagado por el plan en los últimos 3 meses.</p>
<h2>7. Suspensión y terminación</h2>
<p>${b} puede suspender cuentas que incumplan estos términos o la ley. El usuario puede dejar de usar el servicio y solicitar la eliminación de su cuenta en cualquier momento.</p>
<h2>8. Ley aplicable y contacto</h2>
<p>Estos términos se rigen por las leyes de la República de Colombia. Contacto: ${contact}.</p>`));
});

const deletionHits = new Map();
app.get('/eliminar-cuenta', (req, res) => {
  const { contact, l } = legalOwner();
  res.send(legalPage('Eliminar cuenta', `
<h1>Solicitar la eliminación de una cuenta</h1>
<p>Puede pedir que se elimine su cuenta de ${escapeHtml(l.brandName)} (administrador o asesor) y los datos asociados. También puede hacerlo dentro de la aplicación: toque su nombre (arriba) → <b>Solicitar eliminación de mi cuenta</b>.</p>
<h2>Qué se elimina</h2>
<ul><li>Su cuenta de usuario: nombre, correo, usuario, teléfono, cédula y contraseña.</li>
<li>Si es el administrador de una empresa: la empresa, sus rifas, boletas, compradores, pagos, soportes y asesores.</li></ul>
<h2>Qué se conserva y por cuánto</h2>
<p>Los registros que la ley obligue a conservar (por ejemplo, contables) y la información incluida en copias de seguridad, que se renuevan y eliminan periódicamente. La solicitud se atiende en un máximo de 15 días hábiles.</p>
<div class="warn">Si usted es comprador de una rifa (no tiene cuenta), pida la eliminación de sus datos a la empresa organizadora o escríbanos a ${contact}.</div>
<form method="post" action="/eliminar-cuenta">
<label>Nombre completo *</label><input name="name" required maxlength="100">
<label>Usuario, correo o cédula con que ingresa *</label><input name="identifier" required maxlength="100">
<label>Empresa</label><input name="company" maxlength="100">
<label>Correo o teléfono para responderle *</label><input name="contact" required maxlength="100">
<label>Motivo (opcional)</label><textarea name="reason" rows="3" maxlength="500"></textarea>
<button type="submit">Enviar solicitud de eliminación</button>
</form>`));
});

app.post('/eliminar-cuenta', express.urlencoded({ extended: false, limit: '10kb' }), (req, res) => {
  const ip = req.ip || '';
  const now = Date.now();
  const hit = deletionHits.get(ip) || { count: 0, since: now };
  if (now - hit.since > 3600000) { hit.count = 0; hit.since = now; }
  hit.count++;
  deletionHits.set(ip, hit);
  if (hit.count > 5) return res.status(429).send(legalPage('Eliminar cuenta', '<p>Demasiadas solicitudes. Intente más tarde.</p>'));
  const clean = v => String(v || '').trim().slice(0, 500);
  const body = req.body || {};
  if (!clean(body.name) || !clean(body.identifier) || !clean(body.contact)) {
    return res.status(400).send(legalPage('Eliminar cuenta', '<p>Faltan datos. <a href="/eliminar-cuenta">Volver</a></p>'));
  }
  db.deletionRequests.unshift({
    id: `del-${now}`, source: 'web', name: clean(body.name), identifier: clean(body.identifier), company: clean(body.company),
    contact: clean(body.contact), reason: clean(body.reason), status: 'PENDIENTE', createdAt: new Date(now).toISOString()
  });
  saveDB();
  res.send(legalPage('Solicitud recibida', '<div class="ok"><b>Recibimos su solicitud.</b><br>Verificaremos su identidad y la atenderemos en un máximo de 15 días hábiles. Le responderemos al contacto que indicó.</div>'));
});

function renderBuyerPortalHtml({ ticket, raffle, company, ticketsList = [], error = null, phone = '', baseUrl = '' }) {
  const companyName = company ? (company.name || company.companyName || 'Rifa Master') : 'Rifa Master';
  const companyPhone = company ? (company.phone || company.code || '') : '';
  const waContact = whatsappService.formatPhoneNumber(companyPhone) || '573212300050';

  // Si no hay boleta seleccionada, mostrar buscador con estética oficial RifaApp
  if (!ticket) {
    return `<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Consultar Boleta - ${escapeHtml(companyName)}</title>
  <link rel="manifest" href="/manifest.json">
  <meta name="theme-color" content="#0F172A">
  <link rel="icon" type="image/png" href="/favicon.png">
  <link rel="apple-touch-icon" href="/icons/apple-touch-icon.png">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Plus Jakarta Sans', sans-serif; }
    body { background-color: #F8FAFC; color: #0F172A; min-height: 100vh; display: flex; flex-direction: column; }
    header { background: #0F172A; color: #FFFFFF; padding: 14px 20px; display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #1E293B; }
    .brand { display: flex; align-items: center; gap: 10px; }
    .brand-badge { background: #F59E0B; color: #000000; font-weight: 900; font-size: 11px; padding: 4px 8px; border-radius: 6px; letter-spacing: 0.5px; }
    .company-badge { color: #FFFFFF; font-weight: 700; font-size: 14px; }
    .portal-badge { background: #1E293B; color: #10B981; font-weight: 700; font-size: 11.5px; padding: 4px 10px; border-radius: 20px; border: 1px solid rgba(16,185,129,.3); }

    .app-download-bar { background: linear-gradient(90deg, #0F172A, #1E293B); border-bottom: 1px solid #334155; padding: 10px 16px; color: #F8FAFC; }
    .app-download-content { max-width: 480px; margin: 0 auto; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px; font-size: 12.5px; }
    .app-download-btns { display: flex; gap: 8px; align-items: center; }
    .btn-app-apk { background: #10B981; color: #FFFFFF !important; text-decoration: none; padding: 6px 12px; border-radius: 8px; font-size: 11.5px; font-weight: 800; display: inline-flex; align-items: center; gap: 4px; box-shadow: 0 2px 6px rgba(16,185,129,.35); transition: transform .15s; }
    .btn-app-apk:hover { transform: translateY(-1px); }
    .btn-app-pwa { background: #3B82F6; color: #FFFFFF; border: none; cursor: pointer; padding: 6px 12px; border-radius: 8px; font-size: 11.5px; font-weight: 800; display: inline-flex; align-items: center; gap: 4px; box-shadow: 0 2px 6px rgba(59,130,246,.35); }

    main { flex: 1; max-width: 480px; width: 100%; margin: 0 auto; padding: 24px 16px; }
    .subhead { font-size: 11px; font-weight: 800; color: #64748B; letter-spacing: 1.5px; text-transform: uppercase; margin-bottom: 6px; }
    h1 { font-size: 26px; font-weight: 800; letter-spacing: -0.5px; margin-bottom: 18px; color: #0F172A; }
    .banner { background: #0F172A; color: #FFFFFF; border-radius: 16px; padding: 18px; margin-bottom: 24px; display: flex; gap: 14px; align-items: flex-start; border: 1px solid #1E293B; box-shadow: 0 4px 20px rgba(15,23,42,.08); }
    .badge-icon { background: #10B981; color: #FFFFFF; width: 26px; height: 26px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-weight: 800; font-size: 14px; flex-shrink: 0; margin-top: 2px; }
    .banner-text b { font-size: 11px; letter-spacing: 1px; color: #10B981; text-transform: uppercase; display: block; margin-bottom: 4px; }
    .banner-text p { font-size: 13.5px; line-height: 1.45; color: #E2E8F0; }
    .form-group { margin-bottom: 18px; }
    label { display: block; font-size: 13.5px; font-weight: 700; margin-bottom: 8px; color: #1E293B; }
    .phone-input-row { display: flex; gap: 8px; }
    .country-box { background: #FFFFFF; border: 1.5px solid #CBD5E1; border-radius: 12px; padding: 12px 14px; font-size: 14px; font-weight: 600; display: flex; align-items: center; gap: 6px; width: 105px; flex-shrink: 0; }
    .input-box { flex: 1; background: #FFFFFF; border: 1.5px solid #CBD5E1; border-radius: 12px; padding: 12px 16px; font-size: 15px; font-weight: 600; color: #0F172A; outline: none; transition: all .2s; }
    .input-box:focus { border-color: #10B981; box-shadow: 0 0 0 3px rgba(16,185,129,.15); }
    .hint { font-size: 12px; color: #64748B; margin-top: 6px; }
    .btn-submit { width: 100%; background: #10B981; color: #FFFFFF; font-size: 15px; font-weight: 800; padding: 15px; border: none; border-radius: 14px; cursor: pointer; transition: all .2s; margin-top: 14px; display: flex; align-items: center; justify-content: center; gap: 8px; box-shadow: 0 4px 14px rgba(16,185,129,.35); }
    .btn-submit:hover { background: #059669; transform: translateY(-1px); }
    .error-card { background: #FEF2F2; border: 1px solid #FECACA; color: #DC2626; padding: 14px 16px; border-radius: 12px; font-size: 13px; margin-bottom: 20px; line-height: 1.4; }
    .wa-float { position: fixed; bottom: 24px; right: 24px; background: #25D366; color: #FFFFFF; width: 54px; height: 54px; border-radius: 50%; display: flex; align-items: center; justify-content: center; box-shadow: 0 10px 25px rgba(37,211,102,.4); text-decoration: none; z-index: 99; transition: transform .2s; }
    .wa-float:hover { transform: scale(1.08); }
  </style>
</head>
<body>
  <header>
    <div class="brand">
      <span class="brand-badge">🎟️ RIFA MASTER</span>
      <span class="company-badge">${escapeHtml(companyName)}</span>
    </div>
    <div class="portal-badge">Consulta Oficial</div>
  </header>
  <main>
    <div class="subhead">PORTAL DEL COMPRADOR</div>
    <h1>Encontremos tu boleta</h1>

    <div class="banner">
      <div class="badge-icon">✓</div>
      <div class="banner-text">
        <b>CONSULTA RÁPIDA</b>
        <p>Escribe tu número de celular / WhatsApp o el número de tu boleta para ver tu estado de pago y respaldo digital oficial.</p>
      </div>
    </div>

    ${error ? `<div class="error-card">${escapeHtml(error)}</div>` : ''}

    <form method="GET" action="/boleta">
      <div class="form-group">
        <label>¿Cuál es tu número de teléfono / WhatsApp?</label>
        <div class="phone-input-row">
          <div class="country-box">🇨🇴 +57</div>
          <input type="tel" name="phone" id="phoneInput" class="input-box" placeholder="3212300050" value="${escapeHtml(phone)}" required autofocus>
        </div>
        <div class="hint">Ingresa tus 10 dígitos (ej: 3107334957) o busca directamente por número de boleta.</div>
      </div>

      <button type="submit" id="btnSubmit" class="btn-submit">
        <span>Ver mi boleta</span>
        <span>→</span>
      </button>
    </form>
  </main>

  <a href="https://wa.me/${waContact}?text=${encodeURIComponent('Hola, necesito ayuda para consultar mi boleta en ' + companyName)}" class="wa-float" target="_blank" title="Contactar por WhatsApp">
    <svg width="28" height="28" viewBox="0 0 24 24" fill="currentColor"><path d="M12.031 6.172c-3.181 0-5.767 2.586-5.768 5.766-.001 1.298.38 2.27 1.019 3.287l-.582 2.128 2.182-.573c.978.58 1.911.928 3.145.929 3.178 0 5.767-2.587 5.768-5.766.001-3.187-2.575-5.77-5.764-5.771zm3.392 8.244c-.144.405-.837.774-1.17.824-.299.045-.677.063-1.092-.069-.252-.08-.575-.187-.988-.365-1.739-.751-2.874-2.502-2.961-2.617-.087-.116-.708-.94-.708-1.793s.448-1.273.607-1.446c.159-.173.346-.217.462-.217l.332.006c.106.005.249-.04.39.298.144.347.491 1.2.534 1.287.043.087.072.188.014.304-.058.116-.087.188-.173.289l-.26.304c-.087.086-.177.18-.076.354.101.174.449.741.964 1.201.662.591 1.221.774 1.394.86.174.086.275.072.376-.044.101-.116.433-.506.549-.68.116-.173.231-.145.39-.087s1.011.477 1.184.564.289.13.332.202c.045.072.045.419-.1.824zm-3.423-14.416c-6.627 0-12 5.373-12 12 0 2.159.57 4.186 1.564 5.938l-1.564 5.822 6.041-1.586c1.706.945 3.666 1.488 5.761 1.488 6.627 0 12-5.373 12-12 0-6.627-5.373-12-12-12z"/></svg>
  </a>

  <script>
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(function(){});
    }
    window.deferredPWAInstallPrompt = null;
    window.addEventListener('beforeinstallprompt', function(e) {
      e.preventDefault();
      window.deferredPWAInstallPrompt = e;
    });
    function promptPWAInstall() {
      if (window.deferredPWAInstallPrompt) {
        window.deferredPWAInstallPrompt.prompt();
      } else {
        alert('Para instalar la Web App en tu pantalla de inicio, abre el menú de tu navegador y pulsa "Agregar a la pantalla de inicio" o "Instalar aplicación".');
      }
    }
  </script>
</body>
</html>`;
  }

  // Si se encontró boleta(s):
  const isPaid = ticket.status === 'PAGADA' || ticket.status === 'CONFIRMADA';
  const drawDate = formatRaffleDate(raffle.mainDrawDate, false);
  const opportunities = Array.isArray(ticket.numbers) ? ticket.numbers : [String(ticket.ticketNumber || '')];
  const opportunitiesText = opportunities.join('  •  ');
  
  // Galería de fotos del premio
  let images = [];
  if (Array.isArray(raffle.prizeImages) && raffle.prizeImages.length > 0) {
    images = raffle.prizeImages;
  } else if (raffle.aficheUrl) {
    images = [raffle.aficheUrl];
  } else if (raffle.fondoBoletaUrl) {
    images = [raffle.fondoBoletaUrl];
  } else {
    images = ['https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=1200&q=80'];
  }

  const maskedDoc = ticket.buyerDocument ? `••• ${ticket.buyerDocument.slice(-3)}` : '••••••';
  const displayCity = ticket.buyerCity || company.city || 'San Martín';
  const displayCountry = ticket.buyerCountry || 'Colombia';
  const emailMasked = ticket.buyerEmail 
    ? ticket.buyerEmail.replace(/^(.{2})(.*)(@.*)$/, '$1•••$3') 
    : (ticket.buyerPhone ? `${ticket.buyerPhone.slice(0, 3)}•••@rifamaster.com` : 'No registrado');

  const ticketPrice = Number(ticket.price || raffle.ticketPrice || 0);
  const totalPaid = Number(ticket.totalPaid || 0);
  const balancePending = Number(ticket.balancePending !== undefined ? ticket.balancePending : Math.max(0, ticketPrice - totalPaid));
  const verifyHash = `RM-VAL-${(ticket.id || '000000').slice(-8).toUpperCase()}`;

  return `<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Boleta Nº ${escapeHtml(opportunitiesText)} - ${escapeHtml(raffle.title || companyName)}</title>
  <meta property="og:type" content="website">
  <meta property="og:title" content="${escapeHtml(`${raffle.title || companyName} - Boleta ${opportunitiesText}`)}">
  <meta property="og:description" content="${escapeHtml(`Consulta el estado de tu boleta con ${companyName}`)}">
  ${(() => { const pic = images.map(normalizeDriveImageUrl).find(u => /^https:\/\//i.test(u) && !/\.(mp4|mov|webm)(\?|$)/i.test(u)); return pic ? `<meta property="og:image" content="${escapeHtml(pic)}">` : ''; })()}
  <link rel="manifest" href="/manifest.json">
  <meta name="theme-color" content="#0F172A">
  <link rel="icon" type="image/png" href="/favicon.png">
  <link rel="apple-touch-icon" href="/icons/apple-touch-icon.png">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800;900&display=swap" rel="stylesheet">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Plus Jakarta Sans', sans-serif; }
    body { background-color: #0F172A; color: #0F172A; min-height: 100vh; display: flex; flex-direction: column; }
    
    /* Top Header */
    header { background: #0F172A; color: #FFFFFF; padding: 14px 20px; display: flex; align-items: center; justify-content: space-between; position: sticky; top: 0; z-index: 50; border-bottom: 1px solid #1E293B; }
    .header-left { display: flex; align-items: center; gap: 12px; }
    .back-btn { background: #1E293B; color: #FFFFFF; border: 1px solid #334155; width: 36px; height: 36px; border-radius: 10px; display: flex; align-items: center; justify-content: center; text-decoration: none; font-size: 16px; font-weight: 800; transition: all .2s; }
    .back-btn:hover { background: #334155; }
    .header-brand { display: flex; flex-direction: column; }
    .brand-title { font-size: 14px; font-weight: 800; color: #F8FAFC; letter-spacing: -0.3px; }
    .brand-sub { font-size: 11px; color: #94A3B8; font-weight: 600; }
    .cert-pill { background: rgba(16,185,129,.15); color: #10B981; border: 1px solid rgba(16,185,129,.35); padding: 4px 10px; border-radius: 20px; font-size: 11px; font-weight: 800; display: flex; align-items: center; gap: 5px; }

    .app-download-bar { background: linear-gradient(90deg, #1E293B, #0F172A); border-bottom: 1px solid #334155; padding: 10px 16px; color: #F8FAFC; }
    .app-download-content { max-width: 540px; margin: 0 auto; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px; font-size: 12.5px; }
    .app-download-btns { display: flex; gap: 8px; align-items: center; }
    .btn-app-apk { background: #10B981; color: #FFFFFF !important; text-decoration: none; padding: 6px 12px; border-radius: 8px; font-size: 11.5px; font-weight: 800; display: inline-flex; align-items: center; gap: 4px; box-shadow: 0 2px 6px rgba(16,185,129,.35); transition: transform .15s; }
    .btn-app-apk:hover { transform: translateY(-1px); }
    .btn-app-pwa { background: #3B82F6; color: #FFFFFF; border: none; cursor: pointer; padding: 6px 12px; border-radius: 8px; font-size: 11.5px; font-weight: 800; display: inline-flex; align-items: center; gap: 4px; box-shadow: 0 2px 6px rgba(59,130,246,.35); }

    main { flex: 1; max-width: 540px; width: 100%; margin: 0 auto; padding: 18px 14px 60px; }

    /* Digital Ticket Container */
    .ticket-wrapper { background: #FFFFFF; border-radius: 24px; overflow: hidden; box-shadow: 0 20px 40px rgba(0,0,0,.35); margin-bottom: 20px; border: 1px solid #CBD5E1; position: relative; }
    
    /* Ticket Top Header */
    .ticket-head { background: linear-gradient(135deg, #0F172A 0%, #1E293B 100%); color: #FFFFFF; padding: 22px 20px 18px; text-align: center; position: relative; border-bottom: 2px dashed #E2E8F0; }
    .ticket-badge { background: #F59E0B; color: #000000; font-weight: 900; font-size: 11px; padding: 4px 10px; border-radius: 6px; letter-spacing: 0.8px; text-transform: uppercase; display: inline-block; margin-bottom: 8px; }
    .ticket-title { font-size: 22px; font-weight: 900; letter-spacing: -0.5px; color: #FFFFFF; margin-bottom: 4px; }
    .ticket-serial { font-size: 13px; color: #94A3B8; font-weight: 600; }
    
    /* Ticket Perforations */
    .cutout-left, .cutout-right { position: absolute; width: 22px; height: 22px; background: #0F172A; border-radius: 50%; bottom: -11px; z-index: 5; }
    .cutout-left { left: -11px; }
    .cutout-right { right: -11px; }

    /* Numbers Highlight Section */
    .numbers-section { padding: 24px 20px 18px; text-align: center; background: #F8FAFC; border-bottom: 1px solid #E2E8F0; }
    .numbers-label { font-size: 11.5px; font-weight: 800; color: #64748B; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 12px; }
    .numbers-grid { display: flex; justify-content: center; gap: 12px; flex-wrap: wrap; margin-bottom: 10px; }
    .number-chip { background: #0F172A; color: #F59E0B; border: 2px solid #F59E0B; border-radius: 16px; padding: 10px 22px; font-size: 26px; font-weight: 900; letter-spacing: 2px; box-shadow: 0 6px 16px rgba(245,158,11,.15); }
    .opportunities-hint { font-size: 12px; color: #64748B; font-weight: 600; }

    /* Status Pill Banner */
    .status-banner { padding: 14px 20px; display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid #F1F5F9; }
    .status-pill-paid { background: #ECFDF5; color: #059669; border: 1px solid #A7F3D0; padding: 6px 14px; border-radius: 20px; font-size: 13px; font-weight: 800; display: inline-flex; align-items: center; gap: 6px; }
    .status-pill-pending { background: #FFFBEB; color: #D97706; border: 1px solid #FDE68A; padding: 6px 14px; border-radius: 20px; font-size: 13px; font-weight: 800; display: inline-flex; align-items: center; gap: 6px; }
    .ticket-price-badge { font-size: 14px; font-weight: 800; color: #0F172A; }

    /* Carrusel de fotos */
    .carousel-container { position: relative; width: 100%; height: 240px; background: #000000; overflow: hidden; }
    .carousel-slide { width: 100%; height: 100%; object-fit: cover; display: none; }
    .carousel-slide.active { display: block; }
    .carousel-counter { position: absolute; top: 12px; right: 12px; background: rgba(0,0,0,.65); color: #fff; padding: 4px 10px; border-radius: 14px; font-size: 11px; font-weight: 800; backdrop-filter: blur(4px); }
    .carousel-caption { position: absolute; bottom: 12px; left: 12px; right: 12px; background: rgba(0,0,0,.7); color: #fff; padding: 6px 12px; border-radius: 12px; font-size: 12px; font-weight: 600; backdrop-filter: blur(4px); }
    .carousel-nav-btn { position: absolute; top: 50%; transform: translateY(-50%); background: rgba(255,255,255,.85); border: none; width: 32px; height: 32px; border-radius: 50%; font-size: 15px; font-weight: 900; color: #000; cursor: pointer; display: flex; align-items: center; justify-content: center; }
    .carousel-nav-btn.prev { left: 10px; }
    .carousel-nav-btn.next { right: 10px; }

    /* Sections Inside Ticket */
    .ticket-body { padding: 20px; }
    .section-title { font-size: 14.5px; font-weight: 800; color: #0F172A; margin-bottom: 14px; display: flex; align-items: center; gap: 8px; border-bottom: 1px solid #F1F5F9; padding-bottom: 8px; }
    .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-bottom: 12px; }
    .data-box { background: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 12px; padding: 10px 12px; }
    .data-lbl { font-size: 10.5px; font-weight: 800; color: #64748B; text-transform: uppercase; letter-spacing: 0.6px; margin-bottom: 3px; }
    .data-txt { font-size: 14px; font-weight: 700; color: #0F172A; word-break: break-word; }

    /* Accordion Details */
    details { background: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 12px; margin-bottom: 10px; padding: 12px 14px; }
    summary { font-size: 13.5px; font-weight: 700; color: #0F172A; cursor: pointer; list-style: none; display: flex; align-items: center; justify-content: space-between; }
    summary::-webkit-details-marker { display: none; }
    summary::after { content: '⌄'; font-size: 18px; font-weight: 800; color: #64748B; transition: transform .2s; }
    details[open] summary::after { transform: rotate(180deg); }
    .details-inner { padding-top: 10px; font-size: 13px; color: #475569; line-height: 1.5; border-top: 1px solid #E2E8F0; margin-top: 8px; }

    /* Verification Box */
    .verify-box { background: #F0FDF4; border: 1.5px solid #BBF7D0; border-radius: 14px; padding: 14px; margin-top: 16px; text-align: center; }
    .verify-seal { font-size: 11.5px; font-weight: 800; color: #166534; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px; display: flex; align-items: center; justify-content: center; gap: 6px; }
    .verify-hash { font-family: monospace; font-size: 13px; font-weight: 700; color: #15803D; background: #DCFCE7; padding: 4px 10px; border-radius: 6px; display: inline-block; margin-top: 4px; }
    .verify-note { font-size: 11.5px; color: #166534; margin-top: 6px; line-height: 1.4; }

    /* Action Buttons */
    .actions-row { display: flex; flex-direction: column; gap: 10px; margin-top: 16px; }
    .btn-whatsapp { background: #25D366; color: #FFFFFF; font-size: 14.5px; font-weight: 800; padding: 14px; border: none; border-radius: 14px; cursor: pointer; display: flex; align-items: center; justify-content: center; gap: 8px; text-decoration: none; box-shadow: 0 4px 14px rgba(37,211,102,.3); transition: all .2s; }
    .btn-whatsapp:hover { transform: translateY(-1px); background: #20BD5A; }
    .btn-print { background: #1E293B; color: #FFFFFF; font-size: 14px; font-weight: 700; padding: 12px; border: 1px solid #334155; border-radius: 14px; cursor: pointer; display: flex; align-items: center; justify-content: center; gap: 8px; }
    .btn-print:hover { background: #334155; }

    .other-tickets-box { background: #1E293B; border-radius: 16px; padding: 16px; margin-top: 16px; color: #FFFFFF; }
    .other-tickets-title { font-size: 13px; font-weight: 800; color: #94A3B8; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 10px; }
    .other-item { display: flex; justify-content: space-between; align-items: center; padding: 8px 0; border-bottom: 1px solid #334155; }
    .other-item:last-child { border-bottom: none; }
    .other-link { color: #10B981; font-weight: 800; text-decoration: none; font-size: 13px; }

    .footer-disclaimer { text-align: center; font-size: 11px; color: #64748B; margin-top: 24px; line-height: 1.5; padding: 0 10px; }
    .wa-float { position: fixed; bottom: 24px; right: 24px; background: #25D366; color: #FFFFFF; width: 54px; height: 54px; border-radius: 50%; display: flex; align-items: center; justify-content: center; box-shadow: 0 10px 25px rgba(37,211,102,.4); text-decoration: none; z-index: 99; }
    
    @media print {
      body { background: #FFF !important; color: #000 !important; }
      header, .actions-row, .wa-float, .other-tickets-box, .back-btn { display: none !important; }
      .ticket-wrapper { box-shadow: none !important; border: 1px solid #000 !important; }
    }
  </style>
</head>
<body>
  <header>
    <div class="header-left">
      <a href="/boleta" class="back-btn" title="Buscar otra boleta">‹</a>
      <div class="header-brand">
        <span class="brand-title">${escapeHtml(companyName)}</span>
        <span class="brand-sub">Soporte Digital Oficial</span>
      </div>
    </div>
    <div class="cert-pill">
      <span>🛡️</span>
      <span>100% Verificada</span>
    </div>
  </header>


  <main>
    <div class="ticket-wrapper">
      <!-- Cabecera estilo billete oficial -->
      <div class="ticket-head">
        <div class="cutout-left"></div>
        <div class="cutout-right"></div>
        <div class="ticket-badge">🎟️ COMPROBANTE OFICIAL DE RESERVA</div>
        <h1 class="ticket-title">${escapeHtml(raffle.title || 'Gran Sorteo')}</h1>
        <div class="ticket-serial">Boleta Oficial #${ticket.ticketNumber || ticket.id.slice(-6)}</div>
      </div>

      <!-- Números que juega -->
      <div class="numbers-section">
        <div class="numbers-label">Tus números oficiales (${raffle.digits || 4} cifras)</div>
        <div class="numbers-grid">
          ${opportunities.map(num => `<div class="number-chip">${escapeHtml(num)}</div>`).join('')}
        </div>
        <div class="opportunities-hint">Juegas con ${opportunities.length} ${opportunities.length === 1 ? 'oportunidad' : 'oportunidades'} por boleta</div>
      </div>

      <!-- Banner de estado de pago -->
      <div class="status-banner">
        <div>
          ${isPaid 
            ? '<div class="status-pill-paid">✓ 100% PAGADA • PARTICIPANDO</div>' 
            : '<div class="status-pill-pending">⏳ RESERVADA • PENDIENTE DE PAGO</div>'}
        </div>
        <div class="ticket-price-badge">
          Valor: $${ticketPrice.toLocaleString('es-CO')} COP
        </div>
      </div>

      <!-- Ver la boleta con su diseño oficial -->
      <details class="bp-details" id="boletaView">
        <summary>🎟️ Ver mi boleta</summary>
        <style id="bpStyles">
          .bp-card { display:flex; border:2px solid #93C5FD; border-radius:16px; background:#FFFFFF; overflow:hidden; color:#0F172A; font-family:'Inter','Segoe UI',Arial,sans-serif; text-align:left; }
          .bp-stub { width:34%; background:#F1F5F9; padding:14px; border-right:2px dashed #94A3B8; font-size:12px; }
          .bp-stub .bp-tag { display:inline-block; background:#DBEAFE; color:#1D4ED8; font-size:10px; font-weight:800; padding:2px 8px; border-radius:6px; letter-spacing:.4px; }
          .bp-stub .bp-num { color:#1D4ED8; font-weight:800; font-size:15px; margin:8px 0; }
          .bp-lbl { color:#64748B; font-size:11px; margin-top:8px; }
          .bp-val { font-weight:700; font-size:13px; }
          .bp-main { flex:1; padding:16px; }
          .bp-title { color:#1D4ED8; font-weight:800; font-size:18px; text-transform:uppercase; }
          .bp-sub { color:#475569; font-size:11px; margin-top:2px; }
          .bp-draw { color:#1D4ED8; font-weight:700; font-size:11px; margin-top:4px; text-transform:uppercase; }
          .bp-chips { display:flex; flex-wrap:wrap; gap:8px; margin:10px 0 12px; }
          .bp-chip { border:2px solid #93C5FD; background:#EFF6FF; color:#1D4ED8; border-radius:10px; padding:6px 14px; font-size:20px; font-weight:800; letter-spacing:1px; }
          .bp-money { display:flex; justify-content:space-between; gap:8px; border-top:1px solid #E2E8F0; padding-top:10px; font-size:12px; flex-wrap:wrap; }
          .bp-money b { display:block; font-size:15px; }
          .bp-foot { display:flex; justify-content:space-between; align-items:center; border-top:1px solid #E2E8F0; margin-top:10px; padding-top:8px; font-size:11px; gap:8px; flex-wrap:wrap; }
          .bp-code { font-family:monospace; font-weight:800; color:#15803D; background:#DCFCE7; padding:2px 8px; border-radius:6px; }
          @media (max-width:560px) { .bp-card { flex-direction:column; } .bp-stub { width:auto; border-right:0; border-bottom:2px dashed #94A3B8; } }
        </style>
        <div class="bp-card" id="boletaPrint">
          <div class="bp-stub">
            <span class="bp-tag">TALONARIO DE CONTROL</span>
            <div class="bp-num">BOLETA N° ${escapeHtml(opportunities.join(' - '))}</div>
            <div class="bp-lbl">Comprador:</div><div class="bp-val">${escapeHtml(ticket.buyerName || 'Pendiente')}</div>
            <div class="bp-lbl">Teléfono:</div><div class="bp-val">${ticket.buyerPhone ? '••••••' + escapeHtml(String(ticket.buyerPhone).slice(-4)) : 'N/A'}</div>
            <div class="bp-lbl">Cédula / NIT:</div><div class="bp-val">${escapeHtml(maskedDoc)}</div>
            <div class="bp-lbl">Vendedor / Asesor:</div><div class="bp-val">${escapeHtml(ticket.advisorName || 'Oficina')}</div>
            <div class="bp-lbl">Monto abonado:</div><div class="bp-val" style="color:#16A34A;">$${totalPaid.toLocaleString('es-CO')}</div>
          </div>
          <div class="bp-main">
            <div class="bp-title">${escapeHtml(raffle.title || 'Gran Sorteo')}</div>
            <div class="bp-sub">Comprobante oficial de boleta • ${escapeHtml(companyName)}</div>
            <div class="bp-draw">Juega el ${escapeHtml(drawDate)}${(raffle.mainLotteryName || raffle.lotteryName) ? ' con la ' + escapeHtml(raffle.mainLotteryName || raffle.lotteryName) : ''}</div>
            <div class="bp-lbl" style="margin-top:12px;">NÚMEROS DE OPORTUNIDAD (${opportunities.length} ${opportunities.length === 1 ? 'NÚMERO' : 'NÚMEROS'}):</div>
            <div class="bp-chips">${opportunities.map(num => `<div class="bp-chip">${escapeHtml(num)}</div>`).join('')}</div>
            <div class="bp-money">
              <div>Valor boleta<b>$${ticketPrice.toLocaleString('es-CO')}</b></div>
              <div>Total abonado<b style="color:#16A34A;">$${totalPaid.toLocaleString('es-CO')}</b></div>
              <div>Saldo pendiente<b style="color:${balancePending > 0 ? '#DC2626' : '#16A34A'};">$${balancePending.toLocaleString('es-CO')}</b></div>
            </div>
            <div class="bp-foot">
              <span>${isPaid ? '✅ PAGADA' : '⏳ ' + escapeHtml(String(ticket.status || '').replace('_', ' '))}</span>
              <span>Código: <span class="bp-code">${escapeHtml(ticket.verificationCode || verifyHash)}</span></span>
            </div>
          </div>
        </div>
        <div style="text-align:center;margin-top:12px;">
          <button type="button" class="bp-print-btn" onclick="printBoleta()">🖨️ Imprimir / Guardar PDF</button>
        </div>
      </details>
      <style>
        .bp-details { margin:14px 16px 4px; }
        .bp-details > summary { cursor:pointer; list-style:none; text-align:center; background:#2563EB; color:#FFFFFF; font-weight:800; font-size:14px; padding:11px 14px; border-radius:12px; box-shadow:0 4px 12px rgba(37,99,235,.35); }
        .bp-details > summary::-webkit-details-marker { display:none; }
        .bp-details[open] > summary { background:#1E40AF; margin-bottom:12px; }
        .bp-print-btn { background:#0F172A; color:#FFFFFF; border:none; border-radius:10px; padding:10px 18px; font-weight:700; font-size:13px; cursor:pointer; }
      </style>
      <script>
        function printBoleta() {
          var card = document.getElementById('boletaPrint');
          var styles = document.getElementById('bpStyles');
          var w = window.open('', '_blank');
          if (!w || !card) { window.print(); return; }
          w.document.write('<!doctype html><html><head><meta charset="utf-8"><title>Boleta</title><style>body{margin:16px;font-family:Arial,sans-serif}' + styles.textContent + '</style></head><body>' + card.outerHTML + '</body></html>');
          w.document.close();
          w.focus();
          setTimeout(function () { w.print(); }, 400);
        }
      </script>

      <!-- Carrusel de fotos y videos del premio -->
      <div class="carousel-container">
        ${images.map((mediaUrl, i) => {
          const isVid = /\.(mp4|mov|webm)(\?.*)?$/i.test(mediaUrl) || mediaUrl.includes('video');
          if (isVid) {
            return `<video src="${escapeHtml(mediaUrl)}" class="carousel-slide ${i === 0 ? 'active' : ''}" controls playsinline preload="metadata"></video>`;
          }
          return `<img src="${escapeHtml(mediaUrl)}" class="carousel-slide ${i === 0 ? 'active' : ''}" alt="Premio">`;
        }).join('')}
        <div class="carousel-counter" id="carouselBadge">1 / ${images.length}</div>
        ${images.length > 1 ? `
          <button class="carousel-nav-btn prev" onclick="prevSlide()">‹</button>
          <button class="carousel-nav-btn next" onclick="nextSlide()">›</button>
        ` : ''}
        <div class="carousel-caption">${escapeHtml(raffle.description ? raffle.description.substring(0, 50) + '...' : 'Premio Mayor Oficial')}</div>
      </div>

      <!-- Cuerpo del soporte digital -->
      <div class="ticket-body">
        
        <!-- Titular y datos fiscales para soporte -->
        <div class="section-title">
          <span>👤</span>
          <span>Titular de la boleta y soporte de compra</span>
        </div>

        <div class="grid-2">
          <div class="data-box">
            <div class="data-lbl">Nombre / Razón Social</div>
            <div class="data-txt">${escapeHtml(ticket.buyerName || 'Sin asignar')}</div>
          </div>
          <div class="data-box">
            <div class="data-lbl">Cédula de Ciudadanía / NIT</div>
            <div class="data-txt">${escapeHtml(maskedDoc)}</div>
          </div>
          <div class="data-box">
            <div class="data-lbl">Teléfono / WhatsApp</div>
            <div class="data-txt">${escapeHtml(ticket.buyerPhone || '—')}</div>
          </div>
          <div class="data-box">
            <div class="data-lbl">Ciudad y País</div>
            <div class="data-txt">${escapeHtml(displayCity)}, ${escapeHtml(displayCountry)}</div>
          </div>
        </div>

        <div class="data-box" style="margin-bottom: 16px;">
          <div class="data-lbl">Correo Electrónico</div>
          <div class="data-txt">${escapeHtml(emailMasked)}</div>
        </div>

        ${ticket.advisorName ? `
          <div class="data-box" style="margin-bottom: 16px; background: #F0FDF4; border-color: #DCFCE7;">
            <div class="data-lbl" style="color: #166534;">Asesor Autorizado</div>
            <div class="data-txt" style="color: #15803D;">${escapeHtml(ticket.advisorName)}</div>
          </div>
        ` : ''}

        <!-- Estado financiero de la boleta -->
        <div class="section-title">
          <span>💳</span>
          <span>Detalle de pago y abonos</span>
        </div>

        <div class="grid-2">
          <div class="data-box">
            <div class="data-lbl">Total Abonado</div>
            <div class="data-txt" style="color: #059669;">$${totalPaid.toLocaleString('es-CO')} COP</div>
          </div>
          <div class="data-box">
            <div class="data-lbl">Saldo Pendiente</div>
            <div class="data-txt" style="color: ${balancePending > 0 ? '#D97706' : '#059669'};">
              $${balancePending.toLocaleString('es-CO')} COP
            </div>
          </div>
        </div>

        ${ticket.abonos && ticket.abonos.length > 0 ? `
          <details>
            <summary>Ver historial de abonos realizados (${ticket.abonos.length})</summary>
            <div class="details-inner">
              ${ticket.abonos.map((a, idx) => `
                <div style="display:flex; justify-content:space-between; padding: 6px 0; border-bottom: 1px dashed #E2E8F0;">
                  <span>${idx + 1}. ${a.date ? a.date.substring(0, 10) : 'Abono'} (${escapeHtml(a.metodoPago || 'Transferencia')})</span>
                  <b>$${Number(a.amount || 0).toLocaleString('es-CO')} COP</b>
                </div>
              `).join('')}
            </div>
          </details>
        ` : ''}

        <!-- Condiciones del sorteo y cronograma de abonos mínimos (Estilo Imagen 4) -->
        <div class="section-title" style="margin-top: 16px;">
          <span>📋</span>
          <span>Condiciones para ganar y abonos mínimos</span>
        </div>

        <details open>
          <summary>🏆 Ver condiciones y cronograma de abonos</summary>
          <div class="details-inner">
            <p>• <b>Premio mayor:</b> ${escapeHtml(raffle.description || raffle.title)}</p>
            <p>• <b>Fecha del sorteo mayor:</b> ${escapeHtml(drawDate)} • <b>Lotería:</b> ${escapeHtml(raffle.mainLotteryName || raffle.lotteryName || 'Lotería Oficial')}.</p>
            <p>• <b>Modalidad:</b> Juega con las ${raffle.winningDigitsPosition === 'PRIMERAS' ? 'primeras' : 'últimas'} ${raffle.digits || 4} cifras del premio mayor.</p>
            <p>• <b>Boleta completamente pagada:</b> $${ticketPrice.toLocaleString('es-CO')} COP</p>

            ${raffle.weeklyPrizes && raffle.weeklyPrizes.length > 0 ? `
              <div style="margin-top: 14px;">
                <b style="color: #0F172A; font-size: 13.5px;">Cronograma de abonos mínimos para participar:</b>
                <div style="overflow-x: auto; margin-top: 8px;">
                  <table style="width: 100%; border-collapse: collapse; font-size: 12px;">
                    <thead>
                      <tr style="background: #F1F5F9; text-align: left; border-bottom: 2px solid #CBD5E1;">
                        <th style="padding: 8px 6px;">Fecha del sorteo</th>
                        <th style="padding: 8px 6px;">Total abonado mínimo</th>
                        <th style="padding: 8px 6px;">Premio</th>
                        <th style="padding: 8px 6px; text-align: center;">Tu Estado</th>
                      </tr>
                    </thead>
                    <tbody>
                      ${raffle.weeklyPrizes.map(p => {
                        const reqAbono = p.minAbonoType === 'PORCENTAJE' 
                          ? (ticketPrice * (p.minAbonoValue || 50) / 100) 
                          : (p.minAbonoValue || 0);
                        const qualifies = totalPaid >= reqAbono;
                        return `
                          <tr style="border-bottom: 1px solid #E2E8F0;">
                            <td style="padding: 8px 6px; font-weight: 700;">${escapeHtml(p.drawDate ? (p.drawDate.substring(0, 10)) : 'Programado')}</td>
                            <td style="padding: 8px 6px; font-weight: 800; color: #0F172A;">$${Number(reqAbono).toLocaleString('es-CO')}</td>
                            <td style="padding: 8px 6px; color: #475569;">${escapeHtml(p.name || 'Sorteo')} ($${Number(p.amount || 0).toLocaleString('es-CO')})</td>
                            <td style="padding: 8px 6px; text-align: center;">
                              ${qualifies 
                                ? '<span style="background: #ECFDF5; color: #059669; font-weight: 800; padding: 2px 8px; border-radius: 12px; font-size: 11px;">✓ Califica</span>' 
                                : `<span style="background: #FEF2F2; color: #DC2626; font-weight: 700; padding: 2px 8px; border-radius: 12px; font-size: 11px;">Faltan $${Number(reqAbono - totalPaid).toLocaleString('es-CO')}</span>`}
                            </td>
                          </tr>
                        `;
                      }).join('')}
                      <tr style="background: #FFFBEB; font-weight: 800; border-top: 2px solid #FDE68A;">
                        <td style="padding: 8px 6px;">${escapeHtml(drawDate)} (Gran Sorteo)</td>
                        <td style="padding: 8px 6px;">$${ticketPrice.toLocaleString('es-CO')} (100%)</td>
                        <td style="padding: 8px 6px;">Premio Mayor</td>
                        <td style="padding: 8px 6px; text-align: center;">
                          ${isPaid 
                            ? '<span style="background: #ECFDF5; color: #059669; font-weight: 800; padding: 2px 8px; border-radius: 12px; font-size: 11px;">✓ 100% Pagada</span>' 
                            : `<span style="background: #FFFBEB; color: #D97706; font-weight: 700; padding: 2px 8px; border-radius: 12px; font-size: 11px;">Faltan $${balancePending.toLocaleString('es-CO')}</span>`}
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            ` : ''}

            <p style="margin-top: 12px; font-size: 12px; color: #64748B; line-height: 1.5;">
              ${escapeHtml(raffle.customPolicies || company.termsConditions || 'Para participar en cada sorteo semanal o anticipado, la boleta debe contar con el abono mínimo acumulado requerido a la fecha del sorteo. Para el premio mayor, debe estar 100% cancelada.')}
            </p>
          </div>
        </details>

        <!-- Sello de verificación digital -->
        <div class="verify-box">
          <div class="verify-seal">
            <span>🛡️</span>
            <span>SOPORTE DIGITAL DE COMPRA OFICIAL</span>
          </div>
          <div class="verify-note">
            Emitido por <b>${escapeHtml(companyName)}</b> con serial de seguridad registrado.
          </div>
          <div class="verify-hash">${verifyHash}</div>
          <div class="verify-note" style="font-size: 11px; color: #166534; margin-top: 6px;">
            Este soporte digital certifica la titularidad y reserva del número en el sistema. Presenta este comprobante junto con tu documento original para reclamar el premio.
          </div>
        </div>

        <!-- Acciones -->
        <div class="actions-row">
          <a href="https://api.whatsapp.com/send?text=${encodeURIComponent('🎟️ ¡Hola! Mira mi boleta oficial para la rifa ' + raffle.title + ' con los números ' + opportunitiesText + ': ' + baseUrl + '/boleta?phone=' + ticket.buyerPhone)}" class="btn-whatsapp" target="_blank">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M12.031 6.172c-3.181 0-5.767 2.586-5.768 5.766-.001 1.298.38 2.27 1.019 3.287l-.582 2.128 2.182-.573c.978.58 1.911.928 3.145.929 3.178 0 5.767-2.587 5.768-5.766.001-3.187-2.575-5.77-5.764-5.771zm3.392 8.244c-.144.405-.837.774-1.17.824-.299.045-.677.063-1.092-.069-.252-.08-.575-.187-.988-.365-1.739-.751-2.874-2.502-2.961-2.617-.087-.116-.708-.94-.708-1.793s.448-1.273.607-1.446c.159-.173.346-.217.462-.217l.332.006c.106.005.249-.04.39.298.144.347.491 1.2.534 1.287.043.087.072.188.014.304-.058.116-.087.188-.173.289l-.26.304c-.087.086-.177.18-.076.354.101.174.449.741.964 1.201.662.591 1.221.774 1.394.86.174.086.275.072.376-.044.101-.116.433-.506.549-.68.116-.173.231-.145.39-.087s1.011.477 1.184.564.289.13.332.202c.045.072.045.419-.1.824zm-3.423-14.416c-6.627 0-12 5.373-12 12 0 2.159.57 4.186 1.564 5.938l-1.564 5.822 6.041-1.586c1.706.945 3.666 1.488 5.761 1.488 6.627 0 12-5.373 12-12 0-6.627-5.373-12-12-12z"/></svg>
            <span>Compartir por WhatsApp</span>
          </a>

          <button onclick="window.print()" class="btn-print">
            <span>🖨️</span>
            <span>Imprimir / Guardar Soporte PDF</span>
          </button>
        </div>

      </div>
    </div>

    ${ticketsList.length > 1 ? `
      <div class="other-tickets-box">
        <div class="other-tickets-title">Tus otras boletas registradas (${ticketsList.length - 1})</div>
        ${ticketsList.filter(t => t.id !== ticket.id).map(t => `
          <div class="other-item">
            <span>Boleta: <b>${escapeHtml((t.numbers || []).join(' • '))}</b></span>
            <a href="/boleta?phone=${encodeURIComponent(phone)}&ticketId=${t.id}" class="other-link">Ver soporte →</a>
          </div>
        `).join('')}
      </div>
    ` : ''}

    <div class="footer-disclaimer">
      Documento y soporte oficial emitido por <b>${escapeHtml(companyName)}</b> • NIT ${escapeHtml(company.nit || 'Oficial')}.<br>
      Sistema de gestión y emisión respaldado por Rifa Master SSL.<br>
      Aplican términos y condiciones del sorteo.
    </div>
  </main>

  <a href="https://wa.me/${waContact}?text=${encodeURIComponent('Hola, tengo una consulta sobre mi boleta ' + opportunitiesText)}" class="wa-float" target="_blank" title="Contactar por WhatsApp">
    <svg width="28" height="28" viewBox="0 0 24 24" fill="currentColor"><path d="M12.031 6.172c-3.181 0-5.767 2.586-5.768 5.766-.001 1.298.38 2.27 1.019 3.287l-.582 2.128 2.182-.573c.978.58 1.911.928 3.145.929 3.178 0 5.767-2.587 5.768-5.766.001-3.187-2.575-5.77-5.764-5.771zm3.392 8.244c-.144.405-.837.774-1.17.824-.299.045-.677.063-1.092-.069-.252-.08-.575-.187-.988-.365-1.739-.751-2.874-2.502-2.961-2.617-.087-.116-.708-.94-.708-1.793s.448-1.273.607-1.446c.159-.173.346-.217.462-.217l.332.006c.106.005.249-.04.39.298.144.347.491 1.2.534 1.287.043.087.072.188.014.304-.058.116-.087.188-.173.289l-.26.304c-.087.086-.177.18-.076.354.101.174.449.741.964 1.201.662.591 1.221.774 1.394.86.174.086.275.072.376-.044.101-.116.433-.506.549-.68.116-.173.231-.145.39-.087s1.011.477 1.184.564.289.13.332.202c.045.072.045.419-.1.824zm-3.423-14.416c-6.627 0-12 5.373-12 12 0 2.159.57 4.186 1.564 5.938l-1.564 5.822 6.041-1.586c1.706.945 3.666 1.488 5.761 1.488 6.627 0 12-5.373 12-12 0-6.627-5.373-12-12-12z"/></svg>
  </a>

  <script>
    let currentSlide = 0;
    const slides = document.querySelectorAll('.carousel-slide');
    const badge = document.getElementById('carouselBadge');

    function showSlide(idx) {
      if (!slides.length) return;
      slides.forEach(s => s.classList.remove('active'));
      currentSlide = (idx + slides.length) % slides.length;
      slides[currentSlide].classList.add('active');
      if (badge) badge.innerText = (currentSlide + 1) + ' / ' + slides.length;
    }

    function prevSlide() { showSlide(currentSlide - 1); }
    function nextSlide() { showSlide(currentSlide + 1); }

    // Touch swipe en móviles
    let touchStartX = 0;
    const track = document.querySelector('.carousel-container');
    if (track) {
      track.addEventListener('touchstart', e => { touchStartX = e.changedTouches[0].screenX; }, { passive: true });
      track.addEventListener('touchend', e => {
        const touchEndX = e.changedTouches[0].screenX;
        if (touchStartX - touchEndX > 40) nextSlide();
        if (touchEndX - touchStartX > 40) prevSlide();
      }, { passive: true });
    }

    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(function(){});
    }
    window.deferredPWAInstallPrompt = null;
    window.addEventListener('beforeinstallprompt', function(e) {
      e.preventDefault();
      window.deferredPWAInstallPrompt = e;
    });
    function promptPWAInstall() {
      if (window.deferredPWAInstallPrompt) {
        window.deferredPWAInstallPrompt.prompt();
      } else {
        alert('Para instalar la Web App en tu pantalla de inicio, abre el menú de tu navegador y pulsa "Agregar a la pantalla de inicio" o "Instalar aplicación".');
      }
    }
  </script>
</body>
</html>`;
}

// ---------------------------------------------------------------------------
// PORTAL PÚBLICO DEL COMPRADOR (Estética Oficial RifaApp: consulta por teléfono o boleta)
// ---------------------------------------------------------------------------
app.get(['/boleta', '/consulta'], (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  const rawQuery = String(req.query.phone || req.query.q || req.query.numero || '').trim();
  const ticketId = String(req.query.ticketId || '').trim();
  const cleanDigits = rawQuery.replace(/[^0-9]/g, '');

  const mainComp = (db.companies || [])[0] || {};

  if (!cleanDigits && !ticketId) {
    return res.send(renderBuyerPortalHtml({ company: mainComp }));
  }

  // Buscar boletas que coincidan con el teléfono (10 dígitos finales o completo) O por oportunidad/boleta
  const tickets = (db.tickets || []).filter(t => {
    if (t.status === 'DISPONIBLE') return false;
    if (ticketId && t.id === ticketId) return true;
    if (cleanDigits) {
      // 1. Búsqueda por número de teléfono (7 a 13 dígitos)
      if (cleanDigits.length >= 7) {
        const tPhone = String(t.buyerPhone || '').replace(/[^0-9]/g, '');
        if (tPhone) {
          const s10 = cleanDigits.slice(-10);
          const t10 = tPhone.slice(-10);
          if (s10 && t10 && s10 === t10) return true;
          if (tPhone === cleanDigits || tPhone.endsWith(cleanDigits) || cleanDigits.endsWith(tPhone)) return true;
        }
      }
      // 2. Búsqueda por oportunidad o serial de boleta (1 a 5 dígitos, ej: 3567 o boleta #1)
      if (cleanDigits.length <= 5) {
        if (String(t.ticketNumber) === cleanDigits) return true;
        if (Array.isArray(t.numbers) && (t.numbers.includes(cleanDigits) || t.numbers.includes(cleanDigits.padStart(4, '0')))) return true;
      }
    }
    return false;
  });

  if (tickets.length === 0) {
    return res.send(renderBuyerPortalHtml({
      company: mainComp,
      error: `No encontramos ninguna boleta activa registrada con "${rawQuery}". Verifica que esté bien escrito o comunícate con nosotros por WhatsApp.`,
      phone: rawQuery
    }));
  }

  // Seleccionar la boleta especificada o la más reciente
  const selectedTicket = ticketId ? (tickets.find(t => t.id === ticketId) || tickets[0]) : tickets[0];
  const raffle = (db.raffles || []).find(r => r.id === selectedTicket.raffleId) || {};
  const company = (db.companies || []).find(c => c.id === raffle.companyId) || mainComp;
  const baseUrl = `${req.protocol}://${req.get('host')}`;

  res.send(renderBuyerPortalHtml({
    ticket: selectedTicket,
    raffle,
    company,
    ticketsList: tickets,
    phone: rawQuery,
    baseUrl
  }));
});

// Ruta corta de verificación /v/:code
app.get('/v/:code', (req, res) => {
  res.redirect(`/verificar/${encodeURIComponent(req.params.code)}`);
});

// Ruta corta de consulta de boletas /b
app.get('/b', (req, res) => {
  const query = req.url.includes('?') ? req.url.substring(req.url.indexOf('?')) : '';
  res.redirect(`/boleta${query}`);
});

// Verificación por código QR /verificar/:code (muestra el portal completo del comprador)
app.get('/verificar/:code', (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  if (verifyRateLimited(req.ip || '')) {
    return res.status(429).send(renderBuyerPortalHtml({ error: 'Demasiadas consultas. Intente de nuevo en un minuto.' }));
  }
  const code = String(req.params.code || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  const formatted = code.length === 10 ? `${code.slice(0, 5)}-${code.slice(5)}` : null;
  const ticket = formatted ? (db.tickets || []).find(t => t.status !== 'DISPONIBLE' && ticketVerificationCode(t) === formatted) : null;
  
  if (!ticket) {
    return res.status(404).send(renderBuyerPortalHtml({
      error: `El código consultado (${formatted || req.params.code}) no corresponde a ninguna boleta vigente. Puede ser falso o haber sido anulado.`
    }));
  }

  const raffle = (db.raffles || []).find(r => r.id === ticket.raffleId) || {};
  const company = (db.companies || []).find(c => c.id === raffle.companyId) || {};
  const baseUrl = `${req.protocol}://${req.get('host')}`;

  res.send(renderBuyerPortalHtml({
    ticket,
    raffle,
    company,
    ticketsList: [ticket],
    baseUrl
  }));
});

// Serve static Flutter Web SPA if present
const publicDir = path.join(__dirname, 'public');
const webDir = path.join(__dirname, '../build/web');
const staticDir = fs.existsSync(publicDir) ? publicDir : (fs.existsSync(webDir) ? webDir : null);

/** AdSense publisher id as Google expects it ("ca-pub-…"), or '' when not configured. */
function adsenseClientId() {
  const client = String(monetizationSettings().adsenseClient || '').trim();
  return /^(ca-)?pub-\d+$/.test(client) ? (client.startsWith('ca-') ? client : `ca-${client}`) : '';
}

// AdSense checks the site's root for ads.txt and for its script in the page head before approving it
app.get('/ads.txt', (req, res) => {
  const client = adsenseClientId();
  res.type('text/plain');
  if (!client) return res.status(404).send('# AdSense no configurado\n');
  res.send(`google.com, ${client.replace(/^ca-/, '')}, DIRECT, f08c47fec0942fa0\n`);
});

function sendIndexHtml(res) {
  res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
  const file = path.join(staticDir, 'index.html');
  const client = adsenseClientId();
  if (!client) return res.sendFile(file);
  const html = fs.readFileSync(file, 'utf8');
  const tag = `<meta name="google-adsense-account" content="${client}">\n` +
    `<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${client}" crossorigin="anonymous" data-adsense="1"></script>\n`;
  res.type('html').send(html.replace('</head>', `${tag}</head>`));
}

// Endpoint to download the Android APK directly
app.get(['/descargar-apk', '/descargar', '/rifamaster.apk', '/app.apk'], (req, res) => {
  const possiblePaths = [
    path.join(__dirname, 'public', 'rifamaster.apk'),
    path.join(__dirname, 'public', 'app.apk'),
    path.join(__dirname, '../build/app/outputs/flutter-apk/app-release.apk')
  ];
  const found = possiblePaths.find(p => fs.existsSync(p));
  if (found) {
    res.setHeader('Content-Type', 'application/vnd.android.package-archive');
    // Mismo nombre que el de GitHub (rifa-master.apk) para que el archivo se llame igual venga de donde venga
    res.setHeader('Content-Disposition', 'attachment; filename="rifa-master.apk"');
    res.setHeader('Cache-Control', 'no-cache');
    return res.sendFile(path.resolve(found));
  }
  return res.status(404).send('APK en proceso de compilación o no disponible.');
});

// ---------------------------------------------------------------------------
// Enlace público del soporte de un pago (para quien recibe el Excel de AGIL): /soporte/<ticket~abono>.<firma>
// La firma (HMAC con el secreto de la base de datos) impide adivinar enlaces de otros pagos.
// ---------------------------------------------------------------------------
function soporteSignature(ticketId, abonoId) {
  const secret = (db.settings || {}).verificationSecret;
  if (!secret) return null;
  return require('crypto').createHmac('sha256', secret).update(`soporte:${ticketId}~${abonoId}`).digest('hex').slice(0, 24);
}

function soporteLinkFor(ticketId, abonoId) {
  const sig = soporteSignature(ticketId, abonoId);
  return sig ? `${PUBLIC_BASE_URL}/soporte/${ticketId}~${abonoId}.${sig}` : '';
}

app.get('/soporte/:token', async (req, res) => {
  try {
    const token = String(req.params.token || '');
    const dot = token.lastIndexOf('.');
    const [ticketId, abonoId] = token.slice(0, dot).split('~');
    const sig = token.slice(dot + 1);
    const expected = dot > 0 && ticketId && abonoId ? soporteSignature(ticketId, abonoId) : null;
    const okSig = expected && sig.length === expected.length && require('crypto').timingSafeEqual(Buffer.from(sig), Buffer.from(expected));
    const ticket = okSig ? (db.tickets || []).find(t => t.id === ticketId) : null;
    const abono = ticket && [...(ticket.abonos || []), ...(ticket.voidedAbonos || [])].find(a => a.id === abonoId);
    if (!abono) return res.status(404).send('Soporte no encontrado.');
    res.setHeader('X-Robots-Tag', 'noindex, nofollow');
    if (abono.soporteDriveId) {
      const file = await driveService.downloadDriveFile(abono.soporteDriveId);
      res.setHeader('Content-Type', file.mimeType || 'image/jpeg');
      res.setHeader('Cache-Control', 'private, max-age=3600');
      return res.send(file.buffer);
    }
    const link = abono.soporteWebViewUrl || abono.soporteUrl;
    return link ? res.redirect(302, link) : res.status(404).send('Este pago no tiene soporte.');
  } catch (err) {
    console.error('⚠️ Error sirviendo soporte:', err.message);
    res.status(502).send('No se pudo cargar el soporte. Intente de nuevo.');
  }
});

if (staticDir) {
  app.get(['/', '/index.html'], (req, res) => sendIndexHtml(res));
  app.use(express.static(staticDir, {
    setHeaders: (res, filePath) => {
      // main.dart.js pesa ~1,9 MB comprimido: con revalidación (ETag → 304) un usuario que ya lo tiene no lo vuelve a bajar, pero siempre recibe la versión nueva
      if (filePath.endsWith('main.dart.js')) {
        res.setHeader('Cache-Control', 'no-cache');
      } else if (filePath.endsWith('.html') || filePath.endsWith('flutter_bootstrap.js') ||
          filePath.endsWith('flutter_service_worker.js') || filePath.endsWith('/sw.js') || filePath.endsWith('build.json') || filePath.endsWith('version.json')) {
        res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
        res.setHeader('Pragma', 'no-cache');
        res.setHeader('Expires', '0');
      }
    }
  }));
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api')) return next();
    sendIndexHtml(res);
  });
}

// Initial Database structure
let db = {
  auditLogs: [],
  raffles: [
    {
      id: 'raf-1',
      title: 'Gran Rifa Casa Campestre & Auto Okm',
      description: 'Sorteo Principal de Fin de Año con Premios Semanales de $1.000.000 COP',
      mainDrawDate: '2026-12-31T20:00:00.000Z',
      weeklyPrizesStartDate: '2026-10-01T00:00:00.000Z',
      digits: 4,
      totalTickets: 2500,
      totalNumbers: 10000,
      opportunitiesPerTicket: 4,
      ticketPrice: 50000,
      weeklyPrizes: [
        { id: 'wp-1', name: 'Sorteo Semanal 1', amount: 1000000, drawDate: '2026-10-15' },
        { id: 'wp-2', name: 'Sorteo Semanal 2', amount: 1000000, drawDate: '2026-10-22' }
      ],
      commissionType: 'PORCENTAJE',
      commissionValue: 10,
      status: 'ACTIVA',
      createdAt: new Date().toISOString()
    }
  ],
  advisors: [
    {
      id: 'adv-1',
      name: 'Carlos Mendoza',
      email: 'carlos@rifas.com',
      username: 'ADV01',
      password: '123',
      status: 'ACTIVO',
      phone: '3001234567',
      code: 'ADV01',
      mode: 'POOL_GENERAL', // or 'ASSIGNED'
      assignedTicketRanges: ['1-500'],
      createdAt: new Date().toISOString()
    },
    {
      id: 'adv-2',
      name: 'Maria Fernanda Gomez',
      email: 'maria@rifas.com',
      username: 'ADV02',
      password: '123',
      status: 'ACTIVO',
      phone: '3159876543',
      code: 'ADV02',
      mode: 'ASSIGNED',
      assignedTicketRanges: ['501-1000'],
      createdAt: new Date().toISOString()
    }
  ],
  tickets: [],
  winners: [],
  commissionPayouts: []
};

// Auto generate 2500 tickets with 4 opportunities each for initial raffle
function generateInitialTickets() {
  if (db.tickets.length > 0) return;
  const raffle = db.raffles[0];
  const totalNumbers = raffle.totalNumbers; // 10000 (0000 to 9999)
  const opps = raffle.opportunitiesPerTicket; // 4
  const numTickets = raffle.totalTickets; // 2500

  for (let i = 1; i <= numTickets; i++) {
    // Opportunities formula: e.g. ticket 1 -> 0000, 2500, 5000, 7500
    const series = [];
    for (let k = 0; k < opps; k++) {
      const numVal = (i - 1) + (k * numTickets);
      series.push(numVal.toString().padStart(raffle.digits, '0'));
    }

    // Demo status for first few tickets
    let status = 'DISPONIBLE';
    let buyerName = '';
    let buyerPhone = '';
    let advisorId = '';
    let advisorName = '';
    let totalPaid = 0;
    let abonos = [];
    let confirmedByAdmin = false;

    if (i === 1) {
      status = 'PAGADA';
      buyerName = 'Juan Pérez';
      buyerPhone = '3114445566';
      advisorId = 'adv-1';
      advisorName = 'Carlos Mendoza';
      totalPaid = 50000;
      confirmedByAdmin = true;
      abonos = [
        { id: 'ab-1', amount: 50000, date: new Date().toISOString(), sellerId: 'adv-1', sellerName: 'Carlos Mendoza', note: 'Pago Total Efectivo' }
      ];
    } else if (i === 2) {
      status = 'ABONO_PARCIAL';
      buyerName = 'Laura Restrepo';
      buyerPhone = '3128889900';
      advisorId = 'adv-1';
      advisorName = 'Carlos Mendoza';
      totalPaid = 20000;
      confirmedByAdmin = false;
      abonos = [
        { id: 'ab-2', amount: 20000, date: new Date().toISOString(), sellerId: 'adv-1', sellerName: 'Carlos Mendoza', note: 'Abono Inicial' }
      ];
    }

    db.tickets.push({
      id: `tkt-${i}`,
      raffleId: raffle.id,
      ticketNumber: i,
      numbers: series,
      price: raffle.ticketPrice,
      status, // DISPONIBLE, RESERVADA, ABONO_PARCIAL, PAGADA
      advisorId,
      advisorName,
      buyerName,
      buyerPhone,
      totalPaid,
      balancePending: raffle.ticketPrice - totalPaid,
      confirmedByAdmin,
      assignedDate: status !== 'DISPONIBLE' ? new Date().toISOString() : null,
      abonos
    });
  }
}

// File persistence helpers
// Encryption at rest: with a master key (DATA_ENCRYPTION_KEY or secrets/data.key) the
// database is stored encrypted (AES-256-GCM) in data.json and in Firestore.
function initEncryptionKey() {
  // A key file is only generated for local storage, where secrets/ is persisted.
  // With Firestore the key must come from DATA_ENCRYPTION_KEY, otherwise a new key per
  // container restart would make the stored data unreadable.
  security.loadMasterKey({ allowCreate: !firestore });
  if (!security.hasMasterKey()) {
    console.warn('⚠️ DATA_ENCRYPTION_KEY no configurada: los datos se guardarán SIN cifrar en Firestore.');
  }
}

function fatal(message) {
  console.error(`❌ ${message}`);
  console.error('   El servidor se detiene para no sobrescribir ni dañar los datos existentes.');
  process.exit(1);
}

function decodeStoredDb(raw, source) {
  if (!security.isEncryptedEnvelope(raw)) return raw;
  if (!security.hasMasterKey()) {
    fatal(`Los datos de ${source} están cifrados pero no se encontró la llave (${security.KEY_FILE} o DATA_ENCRYPTION_KEY).`);
  }
  try {
    return security.decryptObject(raw);
  } catch (e) {
    fatal(`No se pudieron descifrar los datos de ${source}: la llave de cifrado no corresponde.`);
  }
}

// ---------------------------------------------------------------------------
// Automatic safety copies ("snapshots"): taken before a restore or reset and once a day.
// Local: backups/ folder (last 30 files). Firestore: one copy per reason (snapshot_<reason>).
// They use the same (encrypted) format as a downloaded backup, so they restore the same way.
// ---------------------------------------------------------------------------
const SNAPSHOT_DIR = process.env.SNAPSHOT_DIR || path.join(__dirname, 'backups');
const MAX_LOCAL_SNAPSHOTS = 30;
const SNAPSHOT_REASONS = ['before_restore', 'before_reset', 'daily'];
const DAILY_SNAPSHOT_MS = 24 * 60 * 60 * 1000;
let lastDailySnapshotAt = 0;

// ---------------------------------------------------------------------------
// Raffle templates (poster and printed ticket images) live OUTSIDE the database:
// Firestore documents template_<raffle>_<type> (chunked) in production, backend/assets/
// locally. The raffle only keeps metadata (raffle.templates[type]), so loading raffles
// no longer downloads megabytes of images.
// ---------------------------------------------------------------------------
const TEMPLATE_TYPES = ['poster', 'ticket'];
const ASSETS_DIR = process.env.ASSETS_DIR || path.join(__dirname, 'assets');
const MAX_TEMPLATE_BYTES = 8 * 1024 * 1024; // data URI length accepted per image

function templateKey(raffleId, type) {
  const safeId = String(raffleId).replace(/[^A-Za-z0-9_-]/g, '');
  if (!safeId || !TEMPLATE_TYPES.includes(type)) throw new Error('Plantilla no válida');
  return `template_${safeId}_${type}`;
}

function isImageDataUri(value) {
  return typeof value === 'string' && /^data:image\/(png|jpe?g|webp);base64,[A-Za-z0-9+/=]+$/.test(value);
}

async function writeTemplate(raffleId, type, dataUri) {
  const key = templateKey(raffleId, type);
  const payload = security.hasMasterKey() ? security.encryptObject({ dataUri }) : { dataUri };
  if (firestore) {
    await writeFirestoreDb(payload, key);
  } else {
    fs.mkdirSync(ASSETS_DIR, { recursive: true, mode: 0o700 });
    fs.writeFileSync(path.join(ASSETS_DIR, `${key}.json`), JSON.stringify(payload), { mode: 0o600 });
  }
}

async function readTemplate(raffleId, type) {
  const key = templateKey(raffleId, type);
  let payload = null;
  if (firestore) {
    const doc = await firestore.collection(FIRESTORE_COLLECTION).doc(key).get();
    if (!doc.exists) return null;
    payload = await readFirestoreDb(doc, key);
  } else {
    const file = path.join(ASSETS_DIR, `${key}.json`);
    if (!fs.existsSync(file)) return null;
    payload = JSON.parse(fs.readFileSync(file, 'utf8'));
  }
  const data = security.isEncryptedEnvelope(payload) ? security.decryptObject(payload) : payload;
  return data && data.dataUri ? data.dataUri : null;
}

async function deleteTemplate(raffleId, type) {
  const key = templateKey(raffleId, type);
  if (firestore) {
    const col = firestore.collection(FIRESTORE_COLLECTION);
    const doc = await col.doc(key).get();
    if (doc.exists) {
      const m = doc.data();
      for (let i = 0; i < (m.chunks || 0); i++) await col.doc(`${key}_${m.version}_${i}`).delete().catch(() => {});
      await col.doc(key).delete();
    }
  } else {
    const file = path.join(ASSETS_DIR, `${key}.json`);
    if (fs.existsSync(file)) fs.unlinkSync(file);
  }
}

/** Stores the image and records its metadata on the raffle (does not save the database). */
async function storeRaffleTemplate(raffle, type, dataUri) {
  await writeTemplate(raffle.id, type, dataUri);
  if (!raffle.templates || typeof raffle.templates !== 'object') raffle.templates = {};
  raffle.templates[type] = {
    version: String(Date.now()),
    mime: dataUri.slice(5, dataUri.indexOf(';')),
    bytes: dataUri.length,
    updatedAt: new Date().toISOString()
  };
}

/**
 * Moves images still embedded in raffles (templateConfig.templateImageBase64, from older
 * versions or old backups) to the template store. The image is removed from the raffle
 * only after it was stored successfully. Returns true if something moved.
 */
async function extractEmbeddedTemplates(target) {
  let moved = false;
  for (const raffle of target.raffles || []) {
    const cfg = raffle.templateConfig;
    if (cfg && isImageDataUri(cfg.templateImageBase64)) {
      try {
        await storeRaffleTemplate(raffle, 'poster', cfg.templateImageBase64);
        delete cfg.templateImageBase64;
        moved = true;
        console.log(`🖼️ Plantilla del afiche de "${raffle.title}" movida al almacén de plantillas.`);
      } catch (err) {
        console.error(`⚠️ No se pudo mover la plantilla de "${raffle.title}" (se conserva donde estaba):`, err.message);
      }
    } else if (cfg && 'templateImageBase64' in cfg && !cfg.templateImageBase64) {
      delete cfg.templateImageBase64;
    }
  }
  return moved;
}

/** Every stored template of the current raffles, for backups and safety copies. */
async function collectTemplates() {
  const out = {};
  for (const raffle of db.raffles || []) {
    for (const type of Object.keys(raffle.templates || {})) {
      try {
        const dataUri = await readTemplate(raffle.id, type);
        if (dataUri) (out[raffle.id] = out[raffle.id] || {})[type] = dataUri;
      } catch (err) {
        console.error(`⚠️ No se pudo leer la plantilla ${type} de ${raffle.id}:`, err.message);
      }
    }
  }
  return out;
}

/** Full export: database plus templates (used by backup downloads and safety copies). */
async function buildFullExport() {
  return { ...db, templateAssets: await collectTemplates() };
}

async function snapshotPayloadWithTemplates() {
  const full = await buildFullExport();
  return security.hasMasterKey() ? security.encryptObject(full, security.BACKUP_FORMAT) : full;
}

function snapshotPayload() {
  return security.hasMasterKey() ? security.encryptObject(db, security.BACKUP_FORMAT) : db;
}

function listLocalSnapshots() {
  try {
    return fs.readdirSync(SNAPSHOT_DIR)
      .filter(f => /^snapshot_[a-z_]+_.+\.json$/.test(f))
      .map(f => {
        const st = fs.statSync(path.join(SNAPSHOT_DIR, f));
        return { id: `local:${f}`, reason: f.replace(/^snapshot_/, '').replace(/_\d{4}-.*$/, ''), createdAt: st.mtime.toISOString(), bytes: st.size, location: 'local' };
      })
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  } catch (_) {
    return [];
  }
}

/** Saves a copy of the current database. Throws if no copy could be written anywhere. */
async function createSnapshot(reason) {
  const payload = await snapshotPayloadWithTemplates();
  const stamp = new Date().toISOString();
  let written = 0;
  const errors = [];

  try {
    fs.mkdirSync(SNAPSHOT_DIR, { recursive: true, mode: 0o700 });
    fs.writeFileSync(path.join(SNAPSHOT_DIR, `snapshot_${reason}_${stamp.replace(/[:.]/g, '-')}.json`), JSON.stringify(payload), { mode: 0o600 });
    written++;
    listLocalSnapshots().slice(MAX_LOCAL_SNAPSHOTS).forEach(s => {
      try { fs.unlinkSync(path.join(SNAPSHOT_DIR, s.id.slice('local:'.length))); } catch (_) {}
    });
  } catch (err) {
    errors.push(`local: ${err.message}`);
  }

  // Backup automático en Google Drive
  try {
    const backupsFolderId = await driveService.getBackupsFolder();
    const filename = `backup_rifamaster_${reason}_${stamp.replace(/[:.]/g, '-')}.json`;
    const jsonStr = JSON.stringify(payload);
    await driveService.uploadFileToDrive({
      buffer: Buffer.from(jsonStr, 'utf8'),
      filename,
      mimeType: 'application/json',
      parentFolderId: backupsFolderId
    });
    written++;
    console.log(`☁️ Copia de seguridad guardada exitosamente en Google Drive (${filename}).`);
  } catch (err) {
    errors.push(`Google Drive: ${err.message}`);
  }

  if (firestore) {
    try {
      await writeFirestoreDb(payload, `snapshot_${reason}`);
      written++;
    } catch (err) {
      errors.push(`Firestore: ${err.message}`);
    }
  }

  if (reason === 'daily' || reason === 'programado_12h') lastDailySnapshotAt = Date.now();
  if (written === 0) throw new Error(`No se pudo crear la copia de seguridad automática (${errors.join('; ')})`);
  console.log(`🗂️ Copia automática "${reason}" creada${errors.length ? ` (con advertencias: ${errors.join('; ')})` : ''}.`);
}

const TWICE_DAILY_SNAPSHOT_MS = 12 * 60 * 60 * 1000; // 12 horas (2 veces al día)

function maybeDailySnapshot() {
  if (Date.now() - lastDailySnapshotAt < TWICE_DAILY_SNAPSHOT_MS) return;
  lastDailySnapshotAt = Date.now();
  createSnapshot('programado_12h').catch(err => console.error('⚠️ Error en copia programada 12h:', err.message));
}

// Verificación periódica cada 15 minutos para asegurar backups 2 veces al día
setInterval(maybeDailySnapshot, 15 * 60 * 1000);

/** Every known collection exists; unknown sections from backups are kept untouched. */
function ensureDbShape(target) {
  for (const key of ['companies', 'raffles', 'tickets', 'advisors', 'winners', 'cashTransactions', 'logs', 'auditLogs', 'commissionPayouts', 'cashDeliveries', 'subscriptionPayments', 'deletionRequests', 'independentDeliveries', 'cashMovements']) {
    if (!Array.isArray(target[key])) target[key] = [];
  }
  return target;
}

function emptyDb() {
  return {
    companies: [],
    raffles: [],
    tickets: [],
    advisors: [],
    winners: [],
    cashTransactions: [],
    logs: [],
    independentDeliveries: []
  };
}

/** Hashes any remaining plain-text password and ensures the SuperAdmin account exists. */
function migrateCredentials() {
  let changed = false;
  (db.companies || []).forEach(c => {
    if (c.adminPassword && !security.isPasswordHash(c.adminPassword)) {
      // Weak legacy passwords (e.g. 1234) must be replaced on next login
      if (security.validatePasswordPolicy(String(c.adminPassword))) c.adminMustChangePassword = true;
      c.adminPassword = security.hashPassword(c.adminPassword);
      changed = true;
    }
  });
  (db.advisors || []).forEach(a => {
    if (a.password && !security.isPasswordHash(a.password)) {
      if (security.validatePasswordPolicy(String(a.password))) a.mustChangePassword = true;
      a.password = security.hashPassword(a.password);
      changed = true;
    }
  });
  if (!db.superAdmin || !db.superAdmin.passwordHash) {
    const initialPassword = process.env.SUPERADMIN_PASSWORD || '1234';
    db.superAdmin = {
      username: 'superadmin',
      email: 'superadmin@rifamaster.com',
      name: 'SuperAdministrador Master',
      passwordHash: security.hashPassword(initialPassword),
      // The default password must be replaced on first login
      mustChangePassword: !process.env.SUPERADMIN_PASSWORD,
      createdAt: new Date().toISOString()
    };
    changed = true;
  }
  return changed;
}

// ---------------------------------------------------------------------------
// Demo Account Management & 48-Hour Auto-Reset
// ---------------------------------------------------------------------------
const DEMO_COMPANY_ID = 'comp-demo';
const DEMO_RESET_INTERVAL_MS = 48 * 60 * 60 * 1000; // 48 horas

function resetDemoAccountData() {
  console.log('🔄 Restableciendo datos de la cuenta DEMO (reset cada 48h)...');
  if (!Array.isArray(db.companies)) db.companies = [];

  let demoComp = db.companies.find(c => c.id === DEMO_COMPANY_ID || c.isDemo);
  if (!demoComp) {
    demoComp = {
      id: DEMO_COMPANY_ID,
      name: 'Empresa Demo (Pruebas)',
      adminName: 'Administrador Demo',
      adminEmail: 'demo@rifaapp.com',
      adminUsername: 'demo_admin',
      adminPassword: security.hashPassword('demo123'),
      status: 'ACTIVA',
      isDemo: true,
      tier: 'FREE',
      createdAt: new Date().toISOString()
    };
    db.companies.push(demoComp);
  } else {
    demoComp.isDemo = true;
    demoComp.tier = 'FREE';
    demoComp.adminPassword = security.hashPassword('demo123');
  }

  // Restablecer sólo los datos del entorno DEMO
  db.raffles = (db.raffles || []).filter(r => r.companyId !== DEMO_COMPANY_ID && r.id !== 'raf-demo');
  db.advisors = (db.advisors || []).filter(a => a.companyId !== DEMO_COMPANY_ID && a.id !== 'adv-demo-1' && a.id !== 'adv-demo-2');
  db.tickets = (db.tickets || []).filter(t => t.companyId !== DEMO_COMPANY_ID && !t.id.startsWith('tkt-demo-'));
  db.winners = (db.winners || []).filter(w => w.companyId !== DEMO_COMPANY_ID);
  db.commissionPayouts = (db.commissionPayouts || []).filter(p => p.companyId !== DEMO_COMPANY_ID);
  db.auditLogs = (db.auditLogs || []).filter(l => l.companyId !== DEMO_COMPANY_ID);

  const demoRaffle = {
    id: 'raf-demo',
    companyId: DEMO_COMPANY_ID,
    title: 'Rifa Demo de Prueba - Smartphone & $1.000.000 COP',
    description: 'Rifa de demostración con reset automático cada 48 horas para pruebas de administración.',
    mainDrawDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
    weeklyPrizesStartDate: new Date().toISOString(),
    digits: 4,
    totalTickets: 100,
    totalNumbers: 400,
    opportunitiesPerTicket: 4,
    ticketPrice: 20000,
    weeklyPrizes: [
      { id: 'wp-demo-1', name: 'Sorteo Semanal Demo', amount: 200000, drawDate: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString().split('T')[0] }
    ],
    commissionType: 'PORCENTAJE',
    commissionValue: 10,
    status: 'ACTIVA',
    createdAt: new Date().toISOString()
  };
  db.raffles.push(demoRaffle);

  const adv1 = {
    id: 'adv-demo-1',
    companyId: DEMO_COMPANY_ID,
    name: 'Asesor Demo 1',
    email: 'asesor1@demo.com',
    username: 'ADV_DEMO1',
    password: security.hashPassword('123'),
    status: 'ACTIVO',
    phone: '3000000001',
    code: 'ADV_DEMO1',
    mode: 'POOL_GENERAL',
    assignedTicketRanges: ['1-50'],
    createdAt: new Date().toISOString()
  };
  const adv2 = {
    id: 'adv-demo-2',
    companyId: DEMO_COMPANY_ID,
    name: 'Asesor Demo 2',
    email: 'asesor2@demo.com',
    username: 'ADV_DEMO2',
    password: security.hashPassword('123'),
    status: 'ACTIVO',
    phone: '3000000002',
    code: 'ADV_DEMO2',
    mode: 'ASSIGNED',
    assignedTicketRanges: ['51-100'],
    createdAt: new Date().toISOString()
  };
  db.advisors.push(adv1, adv2);

  for (let i = 1; i <= 100; i++) {
    const series = [];
    for (let k = 0; k < 4; k++) {
      const numVal = (i - 1) + (k * 100);
      series.push(numVal.toString().padStart(4, '0'));
    }

    let status = 'DISPONIBLE';
    let buyerName = '';
    let buyerPhone = '';
    let advisorId = '';
    let advisorName = '';
    let totalPaid = 0;
    let abonos = [];
    let confirmedByAdmin = false;

    if (i === 1) {
      status = 'PAGADA';
      buyerName = 'Cliente Demo Pagado';
      buyerPhone = '3001112233';
      advisorId = adv1.id;
      advisorName = adv1.name;
      totalPaid = 20000;
      confirmedByAdmin = true;
      abonos = [{ id: 'ab-demo-1', amount: 20000, date: new Date().toISOString(), sellerId: adv1.id, sellerName: adv1.name, note: 'Pago Total' }];
    } else if (i === 2) {
      status = 'ABONO_PARCIAL';
      buyerName = 'Cliente Demo Abono';
      buyerPhone = '3004445566';
      advisorId = adv2.id;
      advisorName = adv2.name;
      totalPaid = 10000;
      confirmedByAdmin = false;
      abonos = [{ id: 'ab-demo-2', amount: 10000, date: new Date().toISOString(), sellerId: adv2.id, sellerName: adv2.name, note: 'Abono 50%' }];
    }

    db.tickets.push({
      id: `tkt-demo-${i}`,
      companyId: DEMO_COMPANY_ID,
      raffleId: demoRaffle.id,
      ticketNumber: i,
      numbers: series,
      price: demoRaffle.ticketPrice,
      status,
      advisorId,
      advisorName,
      buyerName,
      buyerPhone,
      totalPaid,
      balancePending: demoRaffle.ticketPrice - totalPaid,
      confirmedByAdmin,
      assignedDate: status !== 'DISPONIBLE' ? new Date().toISOString() : null,
      abonos
    });
  }

  db.lastDemoReset = new Date().toISOString();
  console.log('✅ Auto-reset de la cuenta DEMO completado exitosamente.');
}

// ---------------------------------------------------------------------------
// Plans: each company is FREE (with ads) or PRO (no ads), optionally until a date (proUntil,
// "YYYY-MM-DD", Colombian calendar; after that day the company is FREE again). The SuperAdmin
// manages the plans, the demo mode and the text of the "upgrade to PRO" banner.
// ---------------------------------------------------------------------------
const DEFAULT_MONETIZATION = {
  demoEnabled: true,
  adTitle: 'Publicidad • Versión Gratuita',
  adText: 'Pasa a la versión PRO para eliminar anuncios y desbloquear rifas ilimitadas.',
  upgradeTitle: 'Actualizar a RifaApp PRO',
  upgradeText: 'Sin anuncios publicitarios, rifas y boletas ilimitadas, logo propio en las boletas, reportes y asesores ilimitados.',
  priceText: '',
  contactWhatsApp: '',
  contactUrl: '',
  // Where the Android app is downloaded from (GitHub release of the latest version; later, Google Play)
  androidApkUrl: 'https://github.com/oesantama/rifaapp/releases/latest/download/rifa-master.apk',
  monthlyPrice: 0,
  quarterlyPrice: 0, // 3 months
  semiannualPrice: 0, // 6 months
  yearlyPrice: 0,
  // Google ads for FREE companies (empty = only the platform's own "upgrade to PRO" banner)
  adsEnabled: false,
  admobAndroidBannerId: '',
  admobIosBannerId: '',
  adsenseClient: '',
  adsenseSlot: ''
};

function monetizationSettings() {
  return { ...DEFAULT_MONETIZATION, ...((db.settings || {}).monetization || {}) };
}

function todayColombia() {
  return new Date(Date.now() - 5 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

/** Plan in force: a PRO whose date has passed counts as FREE. */
function effectiveTier(company) {
  if (!company || company.tier !== 'PRO') return 'FREE';
  if (company.proUntil && company.proUntil < todayColombia()) return 'FREE';
  return 'PRO';
}

/** Companies created before plans existed keep working without ads (once, on first start). */
function ensureCompanyPlans(target) {
  if (!target.settings || typeof target.settings !== 'object') target.settings = {};
  if (target.settings.plansMigrated) return false;
  for (const c of target.companies || []) {
    if (!c.tier && !c.isDemo) c.tier = 'PRO';
  }
  target.settings.plansMigrated = new Date().toISOString();
  return true;
}

/** Validates a plan change sent by the SuperAdmin; returns { error } or the fields to apply. */
function planFields(body) {
  const out = {};
  if (body.tier !== undefined) {
    if (!['FREE', 'PRO'].includes(body.tier)) return { error: 'Plan no válido (FREE o PRO).' };
    out.tier = body.tier;
  }
  if (body.proUntil !== undefined) {
    const v = String(body.proUntil || '').trim();
    if (v && !/^\d{4}-\d{2}-\d{2}$/.test(v)) return { error: 'Fecha de vencimiento no válida.' };
    out.proUntil = v || null;
  }
  if (out.tier === 'FREE') out.proUntil = null;
  if (body.maxActiveRaffles !== undefined) {
    const n = parseInt(body.maxActiveRaffles, 10);
    out.maxActiveRaffles = isNaN(n) || n < 0 ? 0 : n;
  }
  return { fields: out };
}

function checkAndResetDemo() {
  if (!monetizationSettings().demoEnabled) return false;
  if (!db.lastDemoReset) {
    resetDemoAccountData();
    return true;
  }
  const elapsed = Date.now() - new Date(db.lastDemoReset).getTime();
  if (elapsed >= DEMO_RESET_INTERVAL_MS) {
    resetDemoAccountData();
    return true;
  }
  return false;
}

setInterval(() => {
  if (isDbLoaded && checkAndResetDemo()) {
    saveDB();
  }
}, 60 * 60 * 1000);


let isDbLoaded = false;
let loadedEncrypted = false;

async function loadDB() {
  initEncryptionKey();
  let loadedFromFirestore = false;
  if (firestore) {
    // Production source of truth. If it cannot be read the server must NOT continue with an
    // older local copy: the next save would overwrite the real data in Firestore.
    let doc = null;
    for (let attempt = 1; attempt <= 5; attempt++) {
      try {
        doc = await firestore.collection(FIRESTORE_COLLECTION).doc(FIRESTORE_MANIFEST).get();
        break;
      } catch (e) {
        console.error(`Error leyendo Firestore (intento ${attempt}/5):`, e.message);
        if (attempt === 5) fatal('No se pudo leer la base de datos de Firestore.');
        await new Promise(r => setTimeout(r, attempt * 3000));
      }
    }
    if (doc.exists) {
      let docData;
      try {
        docData = await readFirestoreDb(doc);
        firestoreVersion = doc.data().version || 'legacy';
      } catch (e) {
        fatal(`Los datos de Firestore están incompletos o dañados (${e.message}).`);
      }
      // decodeStoredDb stops the server if the data is encrypted and the key is missing or wrong
      loadedEncrypted = security.isEncryptedEnvelope(docData);
      db = decodeStoredDb(docData, 'Firestore');
      loadedFromFirestore = true;
      isDbLoaded = true;
      console.log('✅ Datos cargados exitosamente desde Google Cloud Firestore');
    } else {
      console.log('ℹ️ No hay datos previos en Firestore, buscando en almacenamiento local...');
    }
  }

  if (!loadedFromFirestore && fs.existsSync(DB_FILE)) {
    let parsed;
    try {
      parsed = JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
    } catch (err) {
      // Never replace a file that exists but cannot be read
      fatal(`El archivo ${DB_FILE} no se pudo leer (${err.message}).`);
    }
    loadedEncrypted = security.isEncryptedEnvelope(parsed);
    db = decodeStoredDb(parsed, 'data.json');
    isDbLoaded = true;
    console.log(`✅ Datos cargados exitosamente desde data.json local${security.isEncryptedEnvelope(parsed) ? ' (cifrado)' : ''}`);
  }

  if (!isDbLoaded) {
    // Only when there is truly no data anywhere (first installation)
    db = emptyDb();
    isDbLoaded = true;
  }

  // Ensure DB arrays exist (unknown sections are kept as they are)
  ensureDbShape(db);

  db.raffles.forEach(r => {
    if (!r.companyId) r.companyId = 'comp-1';
  });

  db.advisors.forEach(a => {
    if (!a.companyId) a.companyId = 'comp-1';
  });

  // Note: demo tickets are never generated on startup: it would crash without raffles and
  // would inject fake sales into a real raffle that has no tickets yet.

  const templatesMoved = await extractEmbeddedTemplates(db);
  const channelsSeeded = ensureSaleChannels(db);
  // Las boletas del bot quedaban con el medio "Bot WhatsApp" (que no existe en la lista): ahora es "WhatsApp"
  let botChannelFixed = false;
  (db.tickets || []).forEach(t => { if (t.saleChannel === 'Bot WhatsApp') { t.saleChannel = 'WhatsApp'; t.soldByBot = true; botChannelFixed = true; } });
  // Boletas disponibles con un saldo pendiente guardado distinto al precio (quedó de un precio anterior): el saldo es el precio completo
  (db.tickets || []).forEach(t => {
    if (t.status === 'DISPONIBLE' && !(t.totalPaid > 0) && t.price > 0 && t.balancePending !== t.price) { t.balancePending = t.price; botChannelFixed = true; }
  });
  if (botChannelFixed) saveDB();
  const plansMigrated = ensureCompanyPlans(db);
  const cashMigrated = ensureCashMigration(db);
  const banksSeeded = ensureBanks(db);
  const lotteriesSeeded = ensureLotteries(db);
  const verificationSeeded = ensureVerificationSecret(db);
  const credentialsChanged = migrateCredentials();
  if (credentialsChanged) {
    console.log('🔐 Contraseñas protegidas con hash (scrypt) y cuenta SuperAdmin verificada.');
  }
  // Rewrite only when needed (new hashes, encryption or old storage format). Saving on every
  // startup would overwrite changes made on the previous server during a deploy.
  const needsRewrite =
    templatesMoved ||
    channelsSeeded ||
    plansMigrated ||
    cashMigrated ||
    banksSeeded ||
    lotteriesSeeded ||
    verificationSeeded ||
    credentialsChanged ||
    (security.hasMasterKey() && !loadedEncrypted) ||
    (firestore && (!loadedFromFirestore || firestoreVersion === 'legacy'));
  if (needsRewrite) {
    if (firestore && !loadedFromFirestore) firestoreVersion = 'none';
    saveDB();
  } else {
    maybeDailySnapshot();
  }
}

/** Replaces the in-memory data with the newest copy in Firestore (after a write conflict). */
// Requests arriving together share one reload: a second reload finishing later would replace the
// data again and drop a change applied in between.
let reloadInFlight = null;
function reloadFromFirestoreOnce() {
  if (!reloadInFlight) reloadInFlight = reloadFromFirestore().finally(() => { reloadInFlight = null; });
  return reloadInFlight;
}

async function reloadFromFirestore() {
  const doc = await firestore.collection(FIRESTORE_COLLECTION).doc(FIRESTORE_MANIFEST).get();
  if (!doc.exists) return;
  const data = decodeStoredDb(await readFirestoreDb(doc), 'Firestore');
  db = ensureDbShape(data);
  firestoreVersion = doc.data().version || 'legacy';
  console.log(`🔄 Datos recargados desde Firestore (versión ${firestoreVersion}).`);
  // Data written by an older server may lack what this version seeds at startup (sale channels,
  // receipt signing secret): seed it again so sales and QR receipts keep working
  const seededChannels = ensureSaleChannels(db);
  if (ensureCompanyPlans(db) | ensureCashMigration(db)) saveDB();
  const seededBanks = ensureBanks(db);
  const seededLotteries = ensureLotteries(db);
  const seededSecret = ensureVerificationSecret(db);
  if (seededChannels || seededBanks || seededLotteries || seededSecret) saveDB();
}

// Cambia con cada guardado: sirve para saber si lo que se calculó de la base de datos sigue vigente.
let dbVersion = 0;

function saveDB() {
  if (!isDbLoaded) {
    console.warn('⚠️ saveDB ignorado: La base de datos aún no ha sido cargada.');
    return;
  }
  dbVersion++;
  const stored = security.hasMasterKey() ? security.encryptObject(db) : db;
  try {
    // Written in place (data.json is a bind-mounted file, so it cannot be replaced by rename)
    fs.writeFileSync(DB_FILE, JSON.stringify(stored), { encoding: 'utf8', mode: 0o600 });
  } catch (err) {
    console.error('Error saving local DB:', err);
  }

  if (firestore) {
    queueFirestoreSave(stored);
  }
  maybeDailySnapshot();
}

// API Routes

// Health check
// Release version (backend/package.json) and deployed commit (Render sets RENDER_GIT_COMMIT)
const APP_VERSION = require('./package.json').version;
const DEPLOYED_COMMIT = (process.env.RENDER_GIT_COMMIT || '').slice(0, 7) || null;
const STARTED_AT = new Date().toISOString();

// Identificador de la compilación de la web que se está sirviendo (public/build.json, lo escribe scripts/build-web.sh)
let buildCache = { mtime: 0, value: '' };
function currentBuildId() {
  try {
    if (!staticDir) return '';
    const file = path.join(staticDir, 'build.json');
    const stat = fs.statSync(file);
    if (stat.mtimeMs !== buildCache.mtime) buildCache = { mtime: stat.mtimeMs, value: String(JSON.parse(fs.readFileSync(file, 'utf8')).build || '') };
    return buildCache.value;
  } catch (_) {
    return '';
  }
}

app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    version: APP_VERSION,
    build: currentBuildId(),
    commit: DEPLOYED_COMMIT,
    startedAt: STARTED_AT,
    timestamp: new Date().toISOString(),
    companiesCount: (db.companies || []).length,
    rafflesCount: db.raffles.length,
    ticketsCount: db.tickets.length
  });
});

// ---------------------------------------------------------------------------
// Authentication: credentials are always validated here, never in the client
// ---------------------------------------------------------------------------
function normalize(value) {
  return String(value || '').trim().toLowerCase();
}

function passwordHashOf(kind, record) {
  if (kind === 'superadmin') return record.passwordHash;
  if (kind === 'admin') return record.adminPassword;
  return record.password;
}

function sessionUser(kind, record) {
  if (kind === 'superadmin') {
    return {
      role: 'superadmin',
      id: 'superadmin',
      name: record.name || 'SuperAdministrador Master',
      email: record.email || '',
      username: record.username,
      companyId: null,
      companyName: '',
      mustChangePassword: !!record.mustChangePassword
    };
  }
  if (kind === 'admin') {
    const tier = effectiveTier(record);
    const isDemo = !!record.isDemo;
    const isIndependent = !!record.isIndependent;
    return {
      role: 'admin',
      id: record.id,
      name: record.adminName || (isIndependent ? record.name : 'Administrador'),
      email: record.adminEmail || '',
      username: record.adminUsername,
      companyId: record.id,
      companyName: record.name,
      tier,
      proUntil: record.proUntil || null,
      isDemo,
      isIndependent,
      accountType: record.accountType || (isIndependent ? 'INDEPENDENT' : 'COMPANY'),
      phone: record.phone || '',
      showAds: tier !== 'PRO',
      mustChangePassword: !!record.adminMustChangePassword
    };
  }
  const company = (db.companies || []).find(c => c.id === record.companyId);
  const companyTier = effectiveTier(company);
  const isCompanyDemo = company ? !!company.isDemo : false;
  return {
    role: 'asesor',
    id: record.id,
    name: record.name,
    email: record.email || '',
    username: record.username || record.code,
    companyId: record.companyId || null,
    companyName: company ? company.name : '',
    tier: companyTier,
    isDemo: isCompanyDemo,
    showAds: companyTier !== 'PRO',
    mustChangePassword: !!record.mustChangePassword,
    advisor: record
  };
}

function issueSession(kind, record) {
  const pv = security.passwordVersion(passwordHashOf(kind, record));
  const subject = kind === 'superadmin' ? 'superadmin' : record.id;
  const { token, expiresAt } = security.signToken({ sub: subject, role: kind, pv });
  return { token, expiresAt, user: sessionUser(kind, record) };
}

/** Resolves the account behind a token; null if it no longer exists, is disabled or changed password. */
function resolveAccount(payload) {
  let record = null;
  if (payload.role === 'superadmin') record = db.superAdmin;
  if (payload.role === 'admin') record = (db.companies || []).find(c => c.id === payload.sub);
  if (payload.role === 'asesor') record = (db.advisors || []).find(a => a.id === payload.sub);
  if (!record) return null;
  if (security.passwordVersion(passwordHashOf(payload.role, record)) !== payload.pv) return null;
  if (payload.role === 'admin' && record.status === 'INACTIVA') return null;
  // Demo mode switched off by the SuperAdmin: demo sessions end
  if (!monetizationSettings().demoEnabled) {
    const company = payload.role === 'admin' ? record : (payload.role === 'asesor' ? (db.companies || []).find(c => c.id === record.companyId) : null);
    if (company && company.isDemo) return null;
  }
  if (payload.role === 'asesor' && record.status === 'INHABILITADO') return null;
  return { kind: payload.role, record };
}

// Public: what the login screen and the ads banner need (no secrets)
app.get('/api/public/app-config', (req, res) => {
  const m = monetizationSettings();
  // Sin un enlace propio configurado, el APK se descarga de ESTE servidor (siempre la versión publicada aquí y conectada a estos datos);
  // el enlace por defecto de GitHub trae un APK que puede apuntar a otro servidor.
  const ownApkUrl = `${req.protocol}://${req.get('host')}/descargar-apk`;
  const configuredApk = String(m.androidApkUrl || '');
  res.json({
    demoEnabled: !!m.demoEnabled,
    androidApkUrl: !configuredApk || /github\.com\/oesantama\//i.test(configuredApk) ? ownApkUrl : configuredApk,
    ad: {
      title: m.adTitle, text: m.adText, upgradeTitle: m.upgradeTitle, upgradeText: m.upgradeText,
      priceText: m.priceText, contactWhatsApp: m.contactWhatsApp, contactUrl: m.contactUrl
    },
    googleAds: m.adsEnabled ? {
      admobAndroidBannerId: m.admobAndroidBannerId, admobIosBannerId: m.admobIosBannerId,
      adsenseClient: adsenseClientId(), adsenseSlot: m.adsenseSlot
    } : null
  });
});

app.post('/api/auth/demo-login', (req, res) => {
  if (!monetizationSettings().demoEnabled) return res.status(403).json({ error: 'El modo demo no está disponible.' });
  checkAndResetDemo();
  let demoCompany = (db.companies || []).find(c => c.isDemo || c.id === 'comp-demo');
  if (!demoCompany) {
    return res.status(500).json({ error: 'No se pudo inicializar la cuenta Demo.' });
  }
  res.json(issueSession('admin', demoCompany));
});

// ---------------------------------------------------------------------------
// Password recovery by e-mail: a 6-digit code (15 minutes, 5 attempts) is sent to the account's
// e-mail. Needs SMTP_USER / SMTP_PASS (e.g. Gmail with an app password) in the environment.
// Answers never reveal whether an account exists.
// ---------------------------------------------------------------------------
const RESET_CODE_MS = 15 * 60 * 1000;
const resetCodes = new Map(); // "kind:id" -> { hash, expires, attempts }
const resetRequestsByIp = new Map();

function mailTransport() {
  if (process.env.MAIL_TEST === '1') return require('nodemailer').createTransport({ jsonTransport: true });
  if (!process.env.SMTP_USER || !process.env.SMTP_PASS) return null;
  return require('nodemailer').createTransport({
    host: process.env.SMTP_HOST || 'smtp.gmail.com',
    port: Number(process.env.SMTP_PORT || 465),
    secure: Number(process.env.SMTP_PORT || 465) === 465,
    auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }
  });
}

/** Account (any role) for a username / e-mail / ID number, with the e-mail to send the code to. */
function findAccountForReset(identifier) {
  const id = normalize(identifier);
  if (!id) return null;
  const sa = db.superAdmin;
  if (sa && [sa.username, sa.email].some(v => v && normalize(v) === id)) return { kind: 'superadmin', record: sa, email: sa.email };
  const company = (db.companies || []).find(c => !c.isDemo && [c.adminUsername, c.adminEmail].some(v => v && normalize(v) === id));
  if (company) return { kind: 'admin', record: company, email: company.adminEmail };
  const advisor = (db.advisors || []).find(a => [a.username, a.code, a.email, a.phone].some(v => v && normalize(v) === id));
  if (advisor) {
    const company = (db.companies || []).find(c => c.id === advisor.companyId);
    if (company && company.isDemo) return null;
    return { kind: 'asesor', record: advisor, email: advisor.email };
  }
  return null;
}

function resetHash(code) {
  return require('crypto').createHmac('sha256', (db.settings || {}).verificationSecret || 'reset').update(String(code)).digest('hex');
}

app.post('/api/auth/forgot-password', async (req, res) => {
  const transport = mailTransport();
  if (!transport) {
    return res.status(503).json({ error: 'La recuperación por correo aún no está configurada. Pida a su administrador que le asigne una nueva contraseña.' });
  }
  const ip = req.ip || '';
  const now = Date.now();
  const hits = (resetRequestsByIp.get(ip) || []).filter(t => now - t < 3600000);
  if (hits.length >= 5) return res.status(429).json({ error: 'Demasiadas solicitudes. Intente de nuevo en una hora.' });
  resetRequestsByIp.set(ip, [...hits, now]);
  const generic = {
    message: 'Si el usuario existe y tiene un correo registrado, le enviamos un código de 6 dígitos. Revise su correo (también la carpeta de spam). '
      + 'Si no tiene correo registrado, pida a su administrador que le asigne una nueva contraseña.'
  };
  const account = findAccountForReset((req.body || {}).identifier);
  if (!account || !account.email || !/@/.test(account.email)) return res.json(generic);
  const code = String(require('crypto').randomInt(0, 1000000)).padStart(6, '0');
  resetCodes.set(`${account.kind}:${account.record.id || 'superadmin'}`, { hash: resetHash(code), expires: now + RESET_CODE_MS, attempts: 0 });
  const brand = legalSettings().brandName;
  try {
    const info = await transport.sendMail({
      from: process.env.MAIL_FROM || `${brand} <${process.env.SMTP_USER}>`,
      to: account.email,
      subject: `${brand}: código para restablecer su contraseña`,
      text: `Su código para restablecer la contraseña de ${brand} es: ${code}\nVence en 15 minutos. Si usted no lo pidió, ignore este correo.`,
      html: `<div style="font-family:Arial,sans-serif;max-width:480px"><h2 style="color:#1E3A8A">${escapeHtml(brand)}</h2>
<p>Recibimos una solicitud para restablecer su contraseña.</p><p style="font-size:30px;font-weight:bold;letter-spacing:6px">${code}</p>
<p>Escríbalo en la aplicación. Vence en <b>15 minutos</b>.</p><p style="color:#64748B;font-size:12px">Si usted no lo pidió, ignore este correo: su contraseña no cambia.</p></div>`
    });
    if (process.env.MAIL_TEST === '1') console.log('MAIL_TEST código', account.email, code, info.messageId ? '' : '');
  } catch (err) {
    console.error('⚠️ No se pudo enviar el correo de recuperación:', err.message);
    return res.status(502).json({ error: 'No se pudo enviar el correo en este momento. Intente más tarde.' });
  }
  res.json(generic);
});

app.post('/api/auth/reset-password', (req, res) => {
  const { identifier, code, newPassword } = req.body || {};
  const account = findAccountForReset(identifier);
  const key = account ? `${account.kind}:${account.record.id || 'superadmin'}` : null;
  const entry = key ? resetCodes.get(key) : null;
  const invalid = () => res.status(400).json({ error: 'El código no es válido o ya venció. Solicite uno nuevo.' });
  if (!entry || Date.now() > entry.expires) return invalid();
  entry.attempts++;
  if (entry.attempts > 5) {
    resetCodes.delete(key);
    return res.status(429).json({ error: 'Demasiados intentos con este código. Solicite uno nuevo.' });
  }
  if (resetHash(String(code || '').trim()) !== entry.hash) return invalid();
  const policyError = security.validatePasswordPolicy(newPassword);
  if (policyError) return res.status(400).json({ error: policyError });
  const hash = security.hashPassword(newPassword);
  if (account.kind === 'superadmin') { account.record.passwordHash = hash; account.record.mustChangePassword = false; }
  else if (account.kind === 'admin') { account.record.adminPassword = hash; account.record.adminMustChangePassword = false; }
  else { account.record.password = hash; account.record.mustChangePassword = false; }
  resetCodes.delete(key);
  security.clearFailures(req.ip || '', normalize(identifier));
  saveDB();
  res.json({ message: 'Contraseña actualizada. Ya puede iniciar sesión con la nueva contraseña.' });
});

app.post('/api/auth/login', (req, res) => {
  const { role, username, password, selectedAdvisorId } = req.body || {};
  const identifier = normalize(username);
  const pass = typeof password === 'string' ? password : '';
  if (!identifier || !pass) {
    return res.status(400).json({ error: 'Ingrese usuario y contraseña.' });
  }

  const ip = req.ip || '';
  const lockedMs = security.isLocked(ip, identifier);
  if (lockedMs > 0) {
    return res.status(429).json({ error: `Demasiados intentos fallidos. Intente de nuevo en ${Math.ceil(lockedMs / 60000)} minuto(s).` });
  }

  let kind = null;
  let record = null;
  if (role === 'asesor') {
    const matchingAdvisors = (db.advisors || []).filter(a => [a.code, a.username, a.email, a.phone].some(v => v && normalize(v) === identifier));
    const matchingIndependents = (db.companies || []).filter(c => (c.isIndependent || c.accountType === 'INDEPENDENT') && [c.adminUsername, c.code, c.adminEmail, c.phone].some(v => v && normalize(v) === identifier));

    if (selectedAdvisorId) {
      if (selectedAdvisorId.startsWith('ind:')) {
        const compId = selectedAdvisorId.replace('ind:', '');
        record = matchingIndependents.find(c => c.id === compId);
        kind = record ? 'admin' : null;
      } else {
        record = matchingAdvisors.find(a => a.id === selectedAdvisorId);
        kind = record ? 'asesor' : null;
      }
    } else {
      const validAdvisors = matchingAdvisors.filter(a => security.verifyPassword(pass, passwordHashOf('asesor', a)));
      const validIndependents = matchingIndependents.filter(c => security.verifyPassword(pass, passwordHashOf('admin', c)));

      const totalValid = validAdvisors.length + validIndependents.length;
      if (totalValid > 1) {
        security.clearFailures(ip, identifier);
        const options = [
          ...validAdvisors.map(a => {
            const comp = (db.companies || []).find(c => c.id === a.companyId);
            const compRaffles = (db.raffles || []).filter(r => (!r.companyId || r.companyId === a.companyId) && r.status !== 'INACTIVA');
            return {
              advisorId: a.id,
              companyId: a.companyId,
              companyName: comp ? comp.name : 'Empresa sin nombre',
              advisorName: a.name,
              code: a.code,
              raffles: compRaffles.map(r => ({ id: r.id, title: r.title, drawDate: r.drawDate }))
            };
          }),
          ...validIndependents.map(c => {
            const indRaffles = (db.raffles || []).filter(r => r.companyId === c.id && r.status !== 'INACTIVA');
            return {
              advisorId: `ind:${c.id}`,
              companyId: c.id,
              companyName: `👤 Vendedor Independiente (${c.name})`,
              advisorName: c.adminName || c.name,
              code: c.code,
              raffles: indRaffles.map(r => ({ id: r.id, title: r.title, drawDate: r.drawDate }))
            };
          })
        ];
        return res.json({
          requireSelection: true,
          message: 'Su cuenta está asociada a múltiples empresas o roles. Seleccione a cuál desea ingresar:',
          options
        });
      } else if (validIndependents.length === 1) {
        record = validIndependents[0];
        kind = 'admin';
      } else if (validAdvisors.length === 1) {
        record = validAdvisors[0];
        kind = 'asesor';
      } else {
        kind = (matchingAdvisors.length > 0 || matchingIndependents.length > 0) ? 'asesor' : null;
      }
    }
  } else {
    const sa = db.superAdmin;
    if (sa && (normalize(sa.username) === identifier || normalize(sa.email) === identifier)) {
      kind = 'superadmin';
      record = sa;
    } else {
      record = (db.companies || []).find(c => [c.adminUsername, c.adminEmail, c.code, c.phone].some(v => v && normalize(v) === identifier));
      kind = record ? 'admin' : null;
    }
  }

  let valid = false;
  if (record) {
    valid = security.verifyPassword(pass, passwordHashOf(kind, record));
  } else {
    security.burnPasswordCheck(pass);
  }

  if (!valid) {
    const remaining = security.registerFailure(ip, identifier);
    return res.status(401).json({
      error: remaining > 0
        ? 'Usuario o contraseña incorrectos.'
        : 'Demasiados intentos fallidos. El acceso quedó bloqueado por 15 minutos.'
    });
  }

  // Account state is only revealed after a correct password
  if (kind === 'admin' && record.status === 'INACTIVA') {
    return res.status(403).json({ error: `Su empresa "${record.name}" se encuentra INACTIVA. Contacte al superadministrador.` });
  }
  if (kind === 'asesor' && record.status === 'INHABILITADO') {
    return res.status(403).json({ error: 'Su cuenta de asesor se encuentra INHABILITADA por la administración.' });
  }
  const demoCompany = kind === 'admin' ? record : (kind === 'asesor' ? (db.companies || []).find(c => c.id === record.companyId) : null);
  if (demoCompany && demoCompany.isDemo && !monetizationSettings().demoEnabled) {
    return res.status(403).json({ error: 'El modo demo no está disponible en este momento.' });
  }

  security.clearFailures(ip, identifier);
  res.json(issueSession(kind, record));
});

app.get('/api/drive/status', async (req, res) => {
  try {
    const status = await driveService.testDriveConnection();
    res.json({ success: true, status });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Every other API route requires a valid session
app.use('/api', (req, res, next) => {
  if (req.path === '/auth/login' || req.path === '/auth/demo-login' || req.path === '/auth/forgot-password' ||
      req.path === '/auth/reset-password' || req.path === '/health' || req.path.startsWith('/public/') ||
      req.path === '/whatsapp/webhook') {
    return next();
  }
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  const payload = token ? security.verifyToken(token) : null;
  const account = payload ? resolveAccount(payload) : null;
  if (!account) {
    return res.status(401).json({ error: 'Sesión no válida o expirada. Inicie sesión nuevamente.' });
  }
  req.auth = { role: account.kind, record: account.record };
  next();
});

function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.auth || !roles.includes(req.auth.role)) {
      return res.status(403).json({ error: 'No tiene permisos para realizar esta acción.' });
    }
    next();
  };
}
const adminOnly = requireRole('admin', 'superadmin');
const superAdminOnly = requireRole('superadmin');

// Before any change, make sure this server has the newest data: during a deploy another server
// may have saved in the meantime. Changes are applied on top of the newest data, so none is lost.
app.use('/api', async (req, res, next) => {
  if (!firestore || req.method === 'GET' || firestoreVersion === null) return next();
  try {
    const doc = await firestore.collection(FIRESTORE_COLLECTION).doc(FIRESTORE_MANIFEST).get();
    const current = doc.exists ? (doc.data().version || 'legacy') : 'none';
    if (current !== firestoreVersion && !ownFirestoreVersions.has(current)) {
      console.log(`🔄 Datos más recientes en Firestore (${current}); se cargan antes de aplicar el cambio.`);
      await reloadFromFirestoreOnce();
    }
    next();
  } catch (err) {
    // Without knowing the latest data, applying the change could overwrite someone else's work
    res.status(503).json({ error: 'No fue posible verificar los datos más recientes. Intente de nuevo en unos segundos.' });
  }
});

app.get('/api/auth/me', (req, res) => {
  res.json({ user: sessionUser(req.auth.role, req.auth.record) });
});

// -------------------------------------------------------------
// WHATSAPP BOT ENDPOINTS (SuperAdmin, Empresa, Asesor)
// -------------------------------------------------------------
// -------------------------------------------------------------
// PAGOS AGIL: consulta, Excel, envío programado por WhatsApp y Excel devuelto (SUBIDO)
// -------------------------------------------------------------
const agilService = require('./agilService')({
  getDb: () => db,
  saveDB: () => saveDB(),
  isReady: () => isDbLoaded,
  whatsappService,
  isAbonoSettled: a => isAbonoSettled(a),
  abonoCashState: a => abonoCashState(a),
  soporteLinkFor: (ticketId, abonoId) => soporteLinkFor(ticketId, abonoId),
  actorName: req => actorName(req),
  colombiaDay: ms => colombiaDay(ms),
  colombiaOffsetMs: () => COLOMBIA_OFFSET_MS,
  baseUrl: () => PUBLIC_BASE_URL,
  getInstanceName: auth => whatsappService.getInstanceName(auth),
  accountLabel: account => transferAccountLabel(account),
  uploadProof: (buffer, filename, mimeType) => driveService.uploadFileToDrive({ buffer, filename, mimeType }),
  auditPush: entry => {
    if (!db.auditLogs) db.auditLogs = [];
    db.auditLogs.push({ id: `audit-${Date.now()}-${Math.random().toString(36).slice(2, 5)}`, date: new Date().toISOString(), ...entry });
  }
});
agilService.registerRoutes(app, { adminOnly, targetCompanyOf });

// Alertas y notificaciones push: sorteo a 3 días con boletas sin completar y efectivo sin legalizar por 7 días o más
const alertService = require('./alertService')({
  getDb: () => db,
  saveDB: () => saveDB(),
  weeklyMinAbonoOf,
  whatsappService
});
alertService.registerRoutes(app, { adminOnly });
whatsappService.setDocumentHandler(agilService.handleIncomingDocument);
agilService.start();

// -------------------------------------------------------------
// ENTRENAR BOT: respuestas personalizadas, preguntas sin respuesta y chats por pasar a un asesor
// -------------------------------------------------------------
const botBrain = require('./botBrain');

function botCompany(req, res) {
  const company = targetCompanyOf(req);
  if (!company) res.status(400).json({ error: 'Seleccione la empresa.' });
  return company;
}

app.get('/api/bot/config', adminOnly, (req, res) => {
  const company = botCompany(req, res);
  if (!company) return;
  const raffleIds = new Set((db.raffles || []).filter(r => r.companyId === company.id).map(r => r.id));
  const howHeardStats = {};
  (db.tickets || []).forEach(t => {
    if (raffleIds.has(t.raffleId) && t.howHeard) howHeardStats[t.howHeard] = (howHeardStats[t.howHeard] || 0) + 1;
  });
  res.json({
    config: botBrain.getBotConfig(company),
    pendingHandoffs: (db.botHandoffs || []).filter(h => h.companyId === company.id && h.status === 'PENDIENTE').length,
    unanswered: (db.botUnanswered || []).filter(u => u.companyId === company.id).length,
    howHeardStats
  });
});

app.put('/api/bot/config', adminOnly, (req, res) => {
  const company = botCompany(req, res);
  if (!company) return;
  const checked = botBrain.sanitizeConfig(req.body && req.body.config, company.botConfig);
  if (checked.error) return res.status(400).json({ error: checked.error });
  company.botConfig = checked.config;
  company.botConfigUpdatedAt = new Date().toISOString();
  saveDB();
  res.json({ message: 'Configuración del bot guardada.', config: checked.config });
});

// Simula qué respondería el bot a un mensaje (sin enviar nada)
app.post('/api/bot/test', adminOnly, (req, res) => {
  const company = botCompany(req, res);
  if (!company) return;
  const text = String((req.body && req.body.text) || '').slice(0, 500);
  const cfg = botBrain.getBotConfig(company);
  const raffle = (db.raffles || []).find(r => r.companyId === company.id && r.status !== 'INACTIVA' && r.active !== false);
  const vars = {
    empresa: company.name || company.companyName || 'Empresa',
    rifa: raffle ? raffle.title : '',
    precio: raffle ? `$${Number(raffle.ticketPrice || 0).toLocaleString('es-CO')}` : '',
    fecha: raffle && raffle.mainDrawDate ? raffle.mainDrawDate.substring(0, 10).split('-').reverse().join('/') : ''
  };
  const faq = botBrain.matchFaq(cfg, text);
  if (faq) return res.json({ type: 'faq', title: faq.title, answer: botBrain.fillPlaceholders(faq.answer, vars) });
  if (botBrain.isHandoffRequest(cfg, text)) return res.json({ type: 'handoff', answer: 'El bot pasaría este chat a un asesor y avisaría al administrador.' });
  if (botBrain.isGreeting(text)) return res.json({ type: 'greeting', answer: 'El bot mostraría el menú principal.' });
  res.json({ type: 'none', answer: 'El bot no tiene una respuesta personalizada para esto: usaría sus respuestas por defecto (menú, números, pagos) o lo registraría como "sin respuesta".' });
});

app.get('/api/bot/unanswered', adminOnly, (req, res) => {
  const company = botCompany(req, res);
  if (!company) return;
  const list = (db.botUnanswered || [])
    .filter(u => u.companyId === company.id)
    .sort((a, b) => String(b.lastAt).localeCompare(String(a.lastAt)))
    .slice(0, 100);
  res.json({ unanswered: list });
});

app.delete('/api/bot/unanswered/:id', adminOnly, (req, res) => {
  const company = botCompany(req, res);
  if (!company) return;
  const before = (db.botUnanswered || []).length;
  db.botUnanswered = (db.botUnanswered || []).filter(u => !(u.id === req.params.id && u.companyId === company.id));
  if (db.botUnanswered.length !== before) saveDB();
  res.json({ ok: true });
});

// Convierte una pregunta sin respuesta en una respuesta del bot
app.post('/api/bot/unanswered/:id/faq', adminOnly, (req, res) => {
  const company = botCompany(req, res);
  if (!company) return;
  const item = (db.botUnanswered || []).find(u => u.id === req.params.id && u.companyId === company.id);
  if (!item) return res.status(404).json({ error: 'Pregunta no encontrada.' });
  const current = botBrain.getBotConfig(company);
  const { title, keywords, answer } = req.body || {};
  const checked = botBrain.sanitizeConfig({
    faqs: [...current.faqs, { title: title || item.text, keywords: keywords && keywords.length ? keywords : [item.text], answer, active: true }]
  }, company.botConfig);
  if (checked.error) return res.status(400).json({ error: checked.error });
  company.botConfig = checked.config;
  db.botUnanswered = db.botUnanswered.filter(u => u.id !== item.id);
  saveDB();
  res.json({ message: 'Respuesta creada.', config: checked.config });
});

app.get('/api/bot/handoffs', adminOnly, (req, res) => {
  const company = botCompany(req, res);
  if (!company) return;
  const list = (db.botHandoffs || [])
    .filter(h => h.companyId === company.id)
    .sort((a, b) => (a.status === b.status ? String(b.updatedAt).localeCompare(String(a.updatedAt)) : (a.status === 'PENDIENTE' ? -1 : 1)))
    .slice(0, 100);
  res.json({ handoffs: list });
});

// Marca el chat como atendido y devuelve el control al bot
app.post('/api/bot/handoffs/:id/resolve', adminOnly, (req, res) => {
  const company = botCompany(req, res);
  if (!company) return;
  const rec = (db.botHandoffs || []).find(h => h.id === req.params.id && h.companyId === company.id);
  if (!rec) return res.status(404).json({ error: 'Chat no encontrado.' });
  rec.status = 'ATENDIDO';
  rec.resolvedAt = new Date().toISOString();
  rec.resolvedBy = actorName(req);
  const key = whatsappService.formatPhoneNumber(rec.phone);
  if (db.whatsappSessions && db.whatsappSessions[key]) db.whatsappSessions[key].humanAssisted = false;
  saveDB();
  res.json({ ok: true });
});

// Salud del bot: estado de la conexión de WhatsApp de la empresa y su actividad reciente (el registro sobrevive a los reinicios)
app.get('/api/bot/health', adminOnly, (req, res) => {
  const instanceName = whatsappService.getInstanceName(req.auth);
  const company = targetCompanyOf(req);
  res.json({ instanceName, salesEnabled: !(company && company.botSalesEnabled === false), health: whatsappService.getHealth(instanceName), log: whatsappService.getBotLog(instanceName, 40) });
});

// Pausar / reanudar las respuestas automáticas de ventas SIN desconectar WhatsApp (alertas, avisos y AGIL siguen funcionando)
app.put('/api/bot/sales-enabled', adminOnly, (req, res) => {
  const company = botCompany(req, res);
  if (!company) return;
  const enabled = !!(req.body && req.body.enabled);
  company.botSalesEnabled = enabled;
  company.botSalesEnabledAt = new Date().toISOString();
  saveDB();
  whatsappService.botLog({ kind: 'pausa', instance: whatsappService.getInstanceName(req.auth), enabled, by: actorName(req) });
  res.json({ salesEnabled: enabled, message: enabled ? 'Respuestas automáticas activadas.' : 'Respuestas automáticas en pausa: el bot no contestará hasta que lo active.' });
});

// Historial del bot (60 días): ?kind=envio|mensaje|conexion|reinicio &phone=últimos dígitos &days=n &limit=n (máx. 1000)
app.get('/api/bot/log', adminOnly, (req, res) => {
  const instanceName = whatsappService.getInstanceName(req.auth);
  const limit = Math.min(1000, Math.max(1, parseInt(req.query.limit, 10) || 200));
  res.json({ instanceName, retentionDays: Number(process.env.BOT_LOG_RETENTION_DAYS) || 60, log: whatsappService.getBotLog(instanceName, limit, { kind: req.query.kind, phone: req.query.phone, days: req.query.days }) });
});

app.get('/api/whatsapp/status', async (req, res) => {
  try {
    const instanceName = whatsappService.getInstanceName(req.auth);
    const status = await whatsappService.getStatus(instanceName);
    res.json({ success: true, instanceName, ...status });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/api/whatsapp/connect', async (req, res) => {
  try {
    const instanceName = whatsappService.getInstanceName(req.auth);
    const phoneNumber = req.body?.phoneNumber || null;
    const result = await whatsappService.connectInstance(instanceName, phoneNumber);
    res.json({ success: true, instanceName, ...result });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/api/whatsapp/disconnect', async (req, res) => {
  try {
    const instanceName = whatsappService.getInstanceName(req.auth);
    const result = await whatsappService.disconnectInstance(instanceName);
    res.json({ ...result, success: result.ok === true });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/api/whatsapp/test-message', async (req, res) => {
  try {
    const instanceName = whatsappService.getInstanceName(req.auth);
    const { phoneNumber, message } = req.body;
    if (!phoneNumber) return res.status(400).json({ error: 'Número de teléfono requerido' });
    const result = await whatsappService.sendTextMessage(
      instanceName,
      phoneNumber,
      message || '👋 Mensaje de prueba exitoso desde Rifa Master WhatsApp Bot 🚀'
    );
    res.json({ success: true, result });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/api/whatsapp/webhook', async (req, res) => {
  try {
    const result = await whatsappService.handleWebhookEvent(req.body, db, (raffleId) => {
      saveDB();
      notifyRaffleChanged(raffleId);
    });
    res.json({ success: true, result });
  } catch (err) {
    console.error('Error procesando webhook de WhatsApp:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

app.post('/api/auth/change-password', (req, res) => {
  const { currentPassword, newPassword } = req.body || {};
  const { role, record } = req.auth;
  if (!security.verifyPassword(String(currentPassword || ''), passwordHashOf(role, record))) {
    return res.status(400).json({ error: 'La contraseña actual no es correcta.' });
  }
  const policyError = security.validatePasswordPolicy(newPassword);
  if (policyError) return res.status(400).json({ error: policyError });
  if (security.verifyPassword(newPassword, passwordHashOf(role, record))) {
    return res.status(400).json({ error: 'La nueva contraseña debe ser diferente a la actual.' });
  }

  const hash = security.hashPassword(newPassword);
  if (role === 'superadmin') {
    record.passwordHash = hash;
    record.mustChangePassword = false;
  } else if (role === 'admin') {
    record.adminPassword = hash;
    record.adminMustChangePassword = false;
  } else {
    record.password = hash;
    record.mustChangePassword = false;
  }
  record.passwordChangedAt = new Date().toISOString();
  saveDB();
  // Other sessions of this user become invalid; this one gets a fresh token
  res.json({ message: 'Contraseña actualizada correctamente.', ...issueSession(role, record) });
});

app.put('/api/auth/profile', (req, res) => {
  const { name, email, username } = req.body || {};
  const { role, record } = req.auth;

  if (role === 'superadmin') {
    if (name !== undefined && name.trim()) record.name = name.trim();
    if (email !== undefined) record.email = email.trim();
    if (username !== undefined && username.trim()) {
      if (normalize(username) !== normalize(record.username) && isUsernameTaken(username)) {
        return res.status(409).json({ error: 'Ese nombre de usuario ya está en uso.' });
      }
      record.username = username.trim();
    }
  } else if (role === 'admin') {
    if (name !== undefined && name.trim()) record.adminName = name.trim();
    if (email !== undefined) record.adminEmail = email.trim();
    if (username !== undefined && username.trim()) {
      if (normalize(username) !== normalize(record.adminUsername) && isUsernameTaken(username)) {
        return res.status(409).json({ error: 'Ese nombre de usuario ya está en uso.' });
      }
      record.adminUsername = username.trim();
    }
  } else if (role === 'asesor') {
    if (name !== undefined && name.trim()) record.name = name.trim();
    if (email !== undefined) record.email = email.trim();
  }

  saveDB();
  res.json({ message: 'Perfil actualizado correctamente', user: sessionUser(role, record) });
});

function isUsernameTaken(username) {
  const u = normalize(username);
  if (db.superAdmin && (normalize(db.superAdmin.username) === u || normalize(db.superAdmin.email) === u)) return true;
  return (db.companies || []).some(c => normalize(c.adminUsername) === u);
}

// GET Companies (SuperAdmin) - Enriched with Admins, Raffles and Advisors stats
app.get('/api/companies', (req, res) => {
  // SuperAdmin sees every company; other users only their own
  const ownCompanyId = req.auth.role === 'admin' ? req.auth.record.id : req.auth.record.companyId;
  const companiesList = (db.companies || []).filter(c => req.auth.role === 'superadmin' || c.id === ownCompanyId);
  const enriched = companiesList.map(comp => {
    // Company Raffles
    const raffles = (db.raffles || []).filter(r => !r.companyId || r.companyId === comp.id);
    // Company Advisors
    const advisors = (db.advisors || []).filter(a => !a.companyId || a.companyId === comp.id);
    // Company Admins
    const admins = [
      {
        name: comp.adminName || 'Administrador General',
        username: comp.adminUsername || 'ADMIN',
        email: comp.adminEmail || 'admin@empresa.com',
        status: 'ACTIVO'
      }
    ];

    return {
      ...comp,
      tier: comp.tier || 'FREE',
      effectiveTier: effectiveTier(comp),
      adminsCount: admins.length,
      admins: admins,
      rafflesCount: raffles.length,
      raffles: raffles.map(r => ({
        id: r.id,
        title: r.title,
        status: r.status,
        totalTickets: r.totalTickets,
        ticketPrice: r.ticketPrice,
        mainDrawDate: r.mainDrawDate
      })),
      advisorsCount: advisors.length,
      advisors: advisors.map(a => ({
        id: a.id,
        name: a.name,
        code: a.code,
        phone: a.phone,
        mode: a.mode,
        totalSold: a.totalSold || 0,
        totalTicketsCount: a.totalTicketsCount || 0
      }))
    };
  });
  res.json(enriched);
});

// POST Create Company
app.post('/api/companies', superAdminOnly, (req, res) => {
  const { name, code, adminUsername, adminPassword, adminName, adminEmail, accountType, isIndependent, phone } = req.body;
  if (!name) {
    return res.status(400).json({ error: 'El nombre es obligatorio' });
  }
  const policyError = security.validatePasswordPolicy(adminPassword);
  if (policyError) return res.status(400).json({ error: `Contraseña: ${policyError}` });
  if (adminUsername && isUsernameTaken(adminUsername)) {
    return res.status(409).json({ error: 'Ese usuario ya existe.' });
  }

  const isInd = isIndependent === true || accountType === 'INDEPENDENT';
  const newCompany = {
    id: `comp-${Date.now()}`,
    name: name.trim(),
    code: code ? code.trim().toUpperCase() : (isInd ? `IND${(db.companies || []).length + 1}` : `EMP${(db.companies || []).length + 1}`),
    status: 'ACTIVA',
    accountType: isInd ? 'INDEPENDENT' : 'COMPANY',
    isIndependent: isInd,
    phone: phone ? String(phone).trim() : '',
    adminUsername: adminUsername ? adminUsername.trim() : `user_${Date.now().toString().slice(-4)}`,
    adminPassword: security.hashPassword(adminPassword),
    adminMustChangePassword: true,
    adminName: adminName || (isInd ? name.trim() : 'Admin Empresa'),
    adminEmail: adminEmail || '',
    tier: req.body.tier || 'FREE',
    proUntil: null,
    maxActiveRaffles: 0,
    createdAt: new Date().toISOString()
  };
  const plan = planFields(req.body);
  if (plan.error) return res.status(400).json({ error: plan.error });
  Object.assign(newCompany, plan.fields);

  if (!db.companies) db.companies = [];
  db.companies.push(newCompany);
  saveDB();
  res.status(201).json(newCompany);
});

// PUT Update Company
app.put('/api/companies/:id', superAdminOnly, (req, res) => {
  const { id } = req.params;
  const company = (db.companies || []).find(c => c.id === id);
  if (!company) {
    return res.status(404).json({ error: 'Empresa no encontrada' });
  }

  const plan = planFields(req.body);
  if (plan.error) return res.status(400).json({ error: plan.error });

  if (req.body.name !== undefined) company.name = req.body.name;
  if (req.body.code !== undefined) company.code = req.body.code;
  if (req.body.status !== undefined) company.status = req.body.status;
  if (req.body.accountType !== undefined) company.accountType = req.body.accountType;
  if (req.body.isIndependent !== undefined) company.isIndependent = !!req.body.isIndependent;
  if (req.body.phone !== undefined) company.phone = String(req.body.phone).trim();
  Object.assign(company, plan.fields);
  if (req.body.adminUsername !== undefined) {
    if (normalize(req.body.adminUsername) !== normalize(company.adminUsername) && isUsernameTaken(req.body.adminUsername)) {
      return res.status(409).json({ error: 'Ese usuario ya existe.' });
    }
    company.adminUsername = req.body.adminUsername;
  }
  // Password only changes when a new one is sent (it is never read back)
  if (typeof req.body.adminPassword === 'string' && req.body.adminPassword.trim() !== '') {
    const policyError = security.validatePasswordPolicy(req.body.adminPassword);
    if (policyError) return res.status(400).json({ error: `Contraseña: ${policyError}` });
    company.adminPassword = security.hashPassword(req.body.adminPassword);
    company.adminMustChangePassword = true;
  }
  if (req.body.adminName !== undefined) company.adminName = req.body.adminName;
  if (req.body.adminEmail !== undefined) company.adminEmail = req.body.adminEmail;
  saveDB();
  res.json(company);
});

// ---------------------------------------------------------------------------
// VENDEDORES INDEPENDIENTES: Auto-Conciliación de Entregas y Liquidación
// ---------------------------------------------------------------------------

// GET Entregas registradas por el vendedor independiente
app.get('/api/independent/deliveries', (req, res) => {
  const targetCompanyId = req.auth.role === 'admin' ? req.auth.record.id : (req.auth.role === 'superadmin' ? req.query.companyId : null);
  if (!targetCompanyId) return res.status(400).json({ error: 'Identificador de cuenta requerido.' });
  const deliveries = (db.independentDeliveries || []).filter(d => d.companyId === targetCompanyId);
  res.json(deliveries);
});

// POST Registrar nueva entrega/consignación a dueño de rifa
app.post('/api/independent/deliveries', (req, res) => {
  if (req.auth.role !== 'admin' && req.auth.role !== 'superadmin') {
    return res.status(403).json({ error: 'Solo administradores o vendedores independientes pueden registrar entregas.' });
  }
  const companyId = req.auth.role === 'admin' ? req.auth.record.id : (req.body.companyId || 'comp-1');
  const { raffleId, raffleTitle, ownerName, amount, paymentMethod, reference, notes, date } = req.body || {};
  const numAmount = parseFloat(amount);
  if (isNaN(numAmount) || numAmount <= 0) {
    return res.status(400).json({ error: 'El monto entregado debe ser mayor a 0.' });
  }

  const newDelivery = {
    id: `deliv-${Date.now()}`,
    companyId,
    raffleId: raffleId || '',
    raffleTitle: raffleTitle || 'Sorteo',
    ownerName: ownerName ? String(ownerName).trim() : 'Dueño de Rifa',
    amount: numAmount,
    paymentMethod: paymentMethod || 'EFECTIVO',
    reference: reference ? String(reference).trim() : '',
    notes: notes ? String(notes).trim() : '',
    date: date || new Date().toISOString(),
    createdAt: new Date().toISOString()
  };

  if (!db.independentDeliveries) db.independentDeliveries = [];
  db.independentDeliveries.unshift(newDelivery);
  saveDB();
  res.status(201).json(newDelivery);
});

// DELETE Eliminar registro de entrega
app.delete('/api/independent/deliveries/:id', (req, res) => {
  const { id } = req.params;
  const targetCompanyId = req.auth.role === 'admin' ? req.auth.record.id : null;
  const idx = (db.independentDeliveries || []).findIndex(d => d.id === id && (req.auth.role === 'superadmin' || d.companyId === targetCompanyId));
  if (idx === -1) return res.status(404).json({ error: 'Registro de entrega no encontrado.' });
  const removed = db.independentDeliveries.splice(idx, 1)[0];
  saveDB();
  res.json({ message: 'Entrega eliminada correctamente.', delivery: removed });
});

// GET Resumen de Liquidación / Auto-Conciliación para Vendedor Independiente
app.get('/api/independent/summary', (req, res) => {
  const companyId = req.auth.role === 'admin' ? req.auth.record.id : (req.query.companyId || (db.companies || [])[0]?.id);
  if (!companyId) return res.status(400).json({ error: 'Cuenta no identificada.' });

  const company = (db.companies || []).find(c => c.id === companyId);
  const compRaffles = (db.raffles || []).filter(r => !r.companyId || r.companyId === companyId);
  const compDeliveries = (db.independentDeliveries || []).filter(d => d.companyId === companyId);

  const summary = compRaffles.map(r => {
    const rTickets = (db.tickets || []).filter(t => t.raffleId === r.id);
    const soldTickets = rTickets.filter(t => t.status === 'PAGADA');
    const partialTickets = rTickets.filter(t => t.status === 'ABONO_PARCIAL');
    const totalCollected = rTickets.reduce((sum, t) => sum + (t.totalPaid || 0), 0);
    const raffleDeliveries = compDeliveries.filter(d => d.raffleId === r.id || (d.ownerName && r.ownerName && normalize(d.ownerName) === normalize(r.ownerName)));
    const totalDelivered = raffleDeliveries.reduce((sum, d) => sum + (d.amount || 0), 0);
    const commissionPercent = parseFloat(r.commissionPercent || (r.commissionType === 'PORCENTAJE' ? r.commissionValue : 0)) || 0;
    const commissionEarned = commissionPercent > 0 ? (totalCollected * (commissionPercent / 100)) : 0;
    const dueToOwner = Math.max(0, totalCollected - commissionEarned - totalDelivered);

    return {
      raffleId: r.id,
      raffleTitle: r.title,
      ownerName: r.ownerName || r.description || 'Organizador',
      mainDrawDate: r.mainDrawDate,
      ticketPrice: r.ticketPrice || 0,
      totalTickets: rTickets.length,
      soldCount: soldTickets.length,
      partialCount: partialTickets.length,
      availableCount: Math.max(0, rTickets.length - soldTickets.length - partialTickets.length),
      totalCollected,
      commissionPercent,
      commissionEarned,
      totalDelivered,
      dueToOwner,
      deliveries: raffleDeliveries
    };
  });

  const totals = summary.reduce((acc, curr) => ({
    totalCollected: acc.totalCollected + curr.totalCollected,
    totalDelivered: acc.totalDelivered + curr.totalDelivered,
    commissionEarned: acc.commissionEarned + curr.commissionEarned,
    dueToOwner: acc.dueToOwner + curr.dueToOwner
  }), { totalCollected: 0, totalDelivered: 0, commissionEarned: 0, dueToOwner: 0 });

  res.json({
    companyId,
    sellerName: company ? company.name : 'Vendedor',
    totals,
    raffles: summary
  });
});

// Account deletion requested from inside the app
app.post('/api/account/deletion-request', (req, res) => {
  if (req.auth.role === 'superadmin') return res.status(400).json({ error: 'La cuenta SuperAdmin no se elimina desde aquí.' });
  const r = req.auth.record;
  const isAdmin = req.auth.role === 'admin';
  const already = (db.deletionRequests || []).find(d => d.accountId === r.id && d.status === 'PENDIENTE');
  if (already) return res.json({ message: 'Ya tiene una solicitud pendiente.', request: already });
  const request = {
    id: `del-${Date.now()}`, source: 'app', accountType: req.auth.role, accountId: r.id,
    name: isAdmin ? (r.adminName || '') : (r.name || ''), identifier: isAdmin ? r.adminUsername : (r.username || r.code),
    company: isAdmin ? r.name : (((db.companies || []).find(c => c.id === r.companyId)) || {}).name || '',
    contact: isAdmin ? (r.adminEmail || '') : (r.email || r.phone || ''), reason: String((req.body || {}).reason || '').trim().slice(0, 500),
    status: 'PENDIENTE', createdAt: new Date().toISOString()
  };
  db.deletionRequests.unshift(request);
  saveDB();
  res.status(201).json({ message: 'Solicitud enviada. Se atenderá en un máximo de 15 días hábiles.', request });
});

app.get('/api/deletion-requests', superAdminOnly, (req, res) => res.json(db.deletionRequests || []));

app.put('/api/deletion-requests/:id', superAdminOnly, (req, res) => {
  const request = (db.deletionRequests || []).find(d => d.id === req.params.id);
  if (!request) return res.status(404).json({ error: 'Solicitud no encontrada.' });
  const status = (req.body || {}).status;
  if (!['ATENDIDA', 'RECHAZADA', 'PENDIENTE'].includes(status)) return res.status(400).json({ error: 'Estado no válido.' });
  request.status = status;
  request.note = String((req.body || {}).note || '').trim().slice(0, 300);
  request.resolvedBy = actorName(req);
  request.resolvedAt = new Date().toISOString();
  saveDB();
  res.json(request);
});

app.get('/api/legal', superAdminOnly, (req, res) => res.json(legalSettings()));

app.put('/api/legal', superAdminOnly, (req, res) => {
  const next = { ...legalSettings() };
  for (const key of Object.keys(DEFAULT_LEGAL)) {
    if ((req.body || {})[key] !== undefined) next[key] = String(req.body[key] || '').trim().slice(0, 200);
  }
  next.updatedOn = colombiaDay(Date.now());
  if (!db.settings) db.settings = {};
  db.settings.legal = next;
  saveDB();
  res.json(next);
});

app.get('/api/monetization', superAdminOnly, (req, res) => {
  res.json({ ...monetizationSettings(), lastDemoReset: db.lastDemoReset || null, defaults: DEFAULT_MONETIZATION });
});

app.put('/api/monetization', superAdminOnly, (req, res) => {
  const body = req.body || {};
  const current = monetizationSettings();
  const next = { ...current };
  if (body.demoEnabled !== undefined) next.demoEnabled = body.demoEnabled === true;
  if (body.androidApkUrl !== undefined) {
    const url = String(body.androidApkUrl || '').trim().slice(0, 300);
    if (url && !/^https:\/\//i.test(url)) return res.status(400).json({ error: 'El enlace de descarga debe empezar por https://' });
    next.androidApkUrl = url || DEFAULT_MONETIZATION.androidApkUrl;
  }
  for (const key of ['adTitle', 'adText', 'upgradeTitle', 'upgradeText', 'priceText', 'contactUrl']) {
    if (body[key] !== undefined) next[key] = String(body[key] || '').trim().slice(0, key.endsWith('Text') ? 500 : 120);
  }
  if (body.contactWhatsApp !== undefined) next.contactWhatsApp = String(body.contactWhatsApp || '').replace(/[^\d+]/g, '').slice(0, 15);
  for (const key of ['monthlyPrice', 'quarterlyPrice', 'semiannualPrice', 'yearlyPrice']) {
    if (body[key] !== undefined) next[key] = Math.max(0, Math.round(Number(body[key]) || 0));
  }
  if (body.adsEnabled !== undefined) next.adsEnabled = body.adsEnabled === true;
  for (const key of ['admobAndroidBannerId', 'admobIosBannerId', 'adsenseClient', 'adsenseSlot']) {
    if (body[key] !== undefined) next[key] = String(body[key] || '').trim().replace(/[^\w\-\/~.]/g, '').slice(0, 80);
  }
  // People paste the AdSense id as "pub-…"; the ad script needs "ca-pub-…"
  if (/^pub-\d+$/.test(next.adsenseClient || '')) next.adsenseClient = `ca-${next.adsenseClient}`;
  if (next.contactUrl && !/^https?:\/\//i.test(next.contactUrl)) {
    return res.status(400).json({ error: 'El enlace de contacto debe empezar por http:// o https://' });
  }
  for (const key of ['adTitle', 'adText', 'upgradeTitle']) if (!next[key]) next[key] = DEFAULT_MONETIZATION[key];
  if (!db.settings) db.settings = {};
  db.settings.monetization = next;
  saveDB();
  res.json({ ...next, lastDemoReset: db.lastDemoReset || null, defaults: DEFAULT_MONETIZATION });
});

// ── Subscriptions: payments of each company for its PRO plan ──
function addMonthsToDay(day, months) {
  const [y, m, d] = day.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1 + months, d));
  // Same day next period minus one: 05/10 + 1 month = until 04/11
  date.setUTCDate(date.getUTCDate() - 1);
  return date.toISOString().slice(0, 10);
}

function nextDay(day) {
  const [y, m, d] = day.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10);
}

function planStatus(company) {
  if (company.isDemo) return 'DEMO';
  if (effectiveTier(company) !== 'PRO') return company.tier === 'PRO' ? 'VENCIDO' : 'GRATIS';
  if (!company.proUntil) return 'PRO';
  const days = Math.round((Date.parse(company.proUntil) - Date.parse(todayColombia())) / 86400000);
  return days <= 7 ? 'POR_VENCER' : 'PRO';
}

app.get('/api/monetization/payments', superAdminOnly, (req, res) => {
  let list = db.subscriptionPayments || [];
  if (req.query.companyId) list = list.filter(p => p.companyId === req.query.companyId);
  res.json(list.slice().sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt))));
});

app.post('/api/monetization/payments', superAdminOnly, (req, res) => {
  const body = req.body || {};
  const company = (db.companies || []).find(c => c.id === body.companyId && !c.isDemo);
  if (!company) return res.status(404).json({ error: 'Empresa no encontrada.' });
  const amount = Math.round(Number(body.amount) || 0);
  if (amount <= 0) return res.status(400).json({ error: 'Indique el valor pagado.' });
  const months = parseInt(body.months, 10);
  if (!months || months < 1 || months > 36) return res.status(400).json({ error: 'Indique cuántos meses paga (1 a 36).' });
  const paidOn = String(body.paidOn || todayColombia());
  if (!/^\d{4}-\d{2}-\d{2}$/.test(paidOn) || paidOn > todayColombia()) return res.status(400).json({ error: 'Fecha de pago no válida.' });
  // The new period starts when the current PRO ends (renewal in advance) or today
  const today = todayColombia();
  const current = effectiveTier(company) === 'PRO' && company.proUntil ? company.proUntil : null;
  const start = current && current >= today ? nextDay(current) : today;
  const until = addMonthsToDay(start, months);
  const payment = {
    id: `pay-${Date.now()}`,
    companyId: company.id,
    companyName: company.name,
    amount,
    months,
    method: String(body.method || 'Transferencia').trim().slice(0, 40),
    reference: String(body.reference || '').trim().slice(0, 60),
    paidOn,
    periodStart: start,
    periodEnd: until,
    proUntilBefore: company.tier === 'PRO' ? (company.proUntil || null) : 'FREE',
    note: String(body.note || '').trim().slice(0, 300),
    registeredBy: actorName(req),
    createdAt: new Date().toISOString()
  };
  company.tier = 'PRO';
  company.proUntil = until;
  db.subscriptionPayments.unshift(payment);
  saveDB();
  res.status(201).json({ payment, company: { id: company.id, tier: company.tier, proUntil: company.proUntil } });
});

// Voids a payment registered by mistake; if it was the latest one, the plan goes back to its previous end
app.post('/api/monetization/payments/:id/void', superAdminOnly, (req, res) => {
  const payment = (db.subscriptionPayments || []).find(p => p.id === req.params.id);
  if (!payment || payment.voided) return res.status(404).json({ error: 'Pago no encontrado.' });
  const reason = String((req.body || {}).reason || '').trim();
  if (reason.length < 5) return res.status(400).json({ error: 'Explique por qué anula el pago.' });
  const company = (db.companies || []).find(c => c.id === payment.companyId);
  const latest = (db.subscriptionPayments || []).find(p => p.companyId === payment.companyId && !p.voided);
  if (company && latest && latest.id === payment.id && company.proUntil === payment.periodEnd) {
    if (payment.proUntilBefore === 'FREE') { company.tier = 'FREE'; company.proUntil = null; } else company.proUntil = payment.proUntilBefore;
  }
  payment.voided = { by: actorName(req), at: new Date().toISOString(), reason };
  saveDB();
  res.json(payment);
});

app.get('/api/monetization/summary', superAdminOnly, (req, res) => {
  const payments = (db.subscriptionPayments || []).filter(p => !p.voided);
  const byMonth = {};
  for (const p of payments) byMonth[p.paidOn.slice(0, 7)] = (byMonth[p.paidOn.slice(0, 7)] || 0) + p.amount;
  const months = [];
  const [ty, tm] = todayColombia().split('-').map(Number);
  for (let i = 11; i >= 0; i--) {
    const d = new Date(Date.UTC(ty, tm - 1 - i, 1));
    const key = d.toISOString().slice(0, 7);
    months.push({ month: key, total: byMonth[key] || 0 });
  }
  const companies = (db.companies || []).map(c => {
    const last = payments.find(p => p.companyId === c.id);
    return {
      id: c.id, name: c.name, status: planStatus(c), tier: c.tier || 'FREE', proUntil: c.proUntil || null,
      lastPayment: last ? { amount: last.amount, months: last.months, paidOn: last.paidOn } : null,
      totalPaid: payments.filter(p => p.companyId === c.id).reduce((s, p) => s + p.amount, 0)
    };
  });
  const count = st => companies.filter(c => c.status === st).length;
  // Monthly recurring revenue: each active PRO's last payment spread over its months
  const mrr = companies.filter(c => ['PRO', 'POR_VENCER'].includes(c.status) && c.lastPayment)
    .reduce((s, c) => s + c.lastPayment.amount / c.lastPayment.months, 0);
  res.json({
    thisMonth: months[months.length - 1].total,
    total: payments.reduce((s, p) => s + p.amount, 0),
    mrr: Math.round(mrr),
    months,
    counts: { pro: count('PRO'), porVencer: count('POR_VENCER'), vencido: count('VENCIDO'), gratis: count('GRATIS'), demo: count('DEMO') },
    companies
  });
});

// Company admin: its own plan and payments
app.get('/api/my-plan', adminOnly, (req, res) => {
  const company = req.auth.role === 'admin' ? req.auth.record : (db.companies || []).find(c => c.id === req.query.companyId);
  if (!company) return res.status(400).json({ error: 'Seleccione la empresa.' });
  const m = monetizationSettings();
  res.json({
    tier: effectiveTier(company),
    status: planStatus(company),
    proUntil: company.proUntil || null,
    maxActiveRaffles: typeof company.maxActiveRaffles === 'number' ? company.maxActiveRaffles : 0,
    activeRafflesCount: (db.raffles || []).filter(r => r.companyId === company.id && r.status === 'ACTIVA' && !r.scheduledDeletionAt).length,
    isDemo: !!company.isDemo,
    monthlyPrice: m.monthlyPrice,
    quarterlyPrice: m.quarterlyPrice,
    semiannualPrice: m.semiannualPrice,
    yearlyPrice: m.yearlyPrice,
    contactWhatsApp: m.contactWhatsApp,
    contactUrl: m.contactUrl,
    payments: (db.subscriptionPayments || []).filter(p => p.companyId === company.id && !p.voided)
      .map(p => ({ id: p.id, amount: p.amount, months: p.months, method: p.method, reference: p.reference, paidOn: p.paidOn, periodStart: p.periodStart, periodEnd: p.periodEnd }))
  });
});

app.post('/api/monetization/demo-reset', superAdminOnly, (req, res) => {
  resetDemoAccountData();
  saveDB();
  res.json({ message: 'Demo reiniciada con datos de ejemplo.', lastDemoReset: db.lastDemoReset });
});

// DELETE Company (Cascade deletes all company raffles, tickets, advisors, winners, and cash records)
app.delete('/api/companies/:id', superAdminOnly, (req, res) => {
  const { id } = req.params;
  const index = (db.companies || []).findIndex(c => c.id === id);
  if (index === -1) {
    return res.status(404).json({ error: 'Empresa no encontrada' });
  }

  const deletedCompany = db.companies[index];
  db.companies.splice(index, 1);

  // Collect all raffle IDs for this company
  const companyRaffleIds = new Set((db.raffles || []).filter(r => r.companyId === id).map(r => r.id));
  for (const raffle of (db.raffles || []).filter(r => companyRaffleIds.has(r.id))) {
    for (const type of Object.keys(raffle.templates || {})) {
      deleteTemplate(raffle.id, type).catch(err => console.error('⚠️ No se pudo borrar la plantilla:', err.message));
    }
  }
  // Remove company raffles
  db.raffles = (db.raffles || []).filter(r => r.companyId !== id && !companyRaffleIds.has(r.id));

  // Remove tickets belonging to company raffles or company
  db.tickets = (db.tickets || []).filter(t => !companyRaffleIds.has(t.raffleId) && t.companyId !== id);

  // Collect all advisor IDs for this company
  const companyAdvisorIds = new Set((db.advisors || []).filter(a => a.companyId === id).map(a => a.id));
  // Remove company advisors
  db.advisors = (db.advisors || []).filter(a => a.companyId !== id && !companyAdvisorIds.has(a.id));

  // Remove winners
  db.winners = (db.winners || []).filter(w => !companyRaffleIds.has(w.raffleId) && w.companyId !== id);

  // Remove cash transactions
  db.cashTransactions = (db.cashTransactions || []).filter(ct => !companyRaffleIds.has(ct.raffleId) && ct.companyId !== id);
  db.cashDeliveries = (db.cashDeliveries || []).filter(d => d.companyId !== id);

  // Remove commission payouts
  db.commissionPayouts = (db.commissionPayouts || []).filter(cp => !companyAdvisorIds.has(cp.advisorId) && !companyRaffleIds.has(cp.raffleId));
  db.expenses = (db.expenses || []).filter(e => e.companyId !== id);
  db.cashMovements = (db.cashMovements || []).filter(m => m.companyId !== id);
  db.agilBatches = (db.agilBatches || []).filter(b => b.companyId !== id);

  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({
    id: `audit-${Date.now()}`,
    type: 'DELETE_COMPANY',
    targetId: id,
    targetName: deletedCompany.name,
    date: new Date().toISOString()
  });

  saveDB();
  res.json({ message: `Empresa "${deletedCompany.name}" y todos sus datos asociados fueron eliminados correctamente.` });
});

// Backup & Database Management Routes (SuperAdmin)
app.get('/api/backup', superAdminOnly, (req, res) => {
  let stats = {};
  try {
    if (fs.existsSync(DB_FILE)) {
      const fileStat = fs.statSync(DB_FILE);
      stats = {
        fileSizeBytes: fileStat.size,
        lastModified: fileStat.mtime.toISOString(),
      };
    }
  } catch (_) {}

  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    stats: {
      companiesCount: (db.companies || []).length,
      rafflesCount: (db.raffles || []).length,
      ticketsCount: (db.tickets || []).length,
      advisorsCount: (db.advisors || []).length,
      winnersCount: (db.winners || []).length,
      auditLogsCount: (db.auditLogs || []).length,
      cashTransactionsCount: (db.cashTransactions || []).length,
      ...stats
    },
    encrypted: security.hasMasterKey(),
    dataSource: firestore ? 'firestore' : 'local',
    storage: storageStatus
  });
});

// Automatic safety copies: list and download (downloaded files restore like any backup)
app.get('/api/backup/snapshots', superAdminOnly, async (req, res) => {
  const list = listLocalSnapshots();
  try {
    const driveSnapshots = await driveService.listDriveBackups();
    list.push(...driveSnapshots);
  } catch (err) {
    console.warn('⚠️ No se pudieron incluir copias de Google Drive:', err.message);
  }
  if (firestore) {
    for (const reason of SNAPSHOT_REASONS) {
      try {
        const doc = await firestore.collection(FIRESTORE_COLLECTION).doc(`snapshot_${reason}`).get();
        if (doc.exists) {
          const m = doc.data();
          list.push({ id: `firestore:${reason}`, reason, createdAt: m.updatedAt, bytes: m.bytes, location: 'firestore' });
        }
      } catch (_) {}
    }
  }
  list.sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
  res.json(list);
});

app.get('/api/backup/snapshots/:id/download', superAdminOnly, async (req, res) => {
  const id = String(req.params.id || '');
  let payload = null;
  try {
    if (id.startsWith('local:')) {
      const file = path.basename(id.slice('local:'.length));
      if (!/^snapshot_[a-z_]+_.+\.json$/.test(file)) return res.status(400).json({ error: 'Copia no válida.' });
      payload = fs.readFileSync(path.join(SNAPSHOT_DIR, file), 'utf8');
    } else if (id.startsWith('drive:')) {
      const fileId = id.slice('drive:'.length);
      payload = await driveService.downloadDriveBackup(fileId);
    } else if (id.startsWith('firestore:') && firestore) {
      const reason = id.slice('firestore:'.length);
      if (!SNAPSHOT_REASONS.includes(reason)) return res.status(400).json({ error: 'Copia no válida.' });
      const doc = await firestore.collection(FIRESTORE_COLLECTION).doc(`snapshot_${reason}`).get();
      if (!doc.exists) return res.status(404).json({ error: 'Copia no encontrada.' });
      payload = JSON.stringify(await readFirestoreDb(doc, `snapshot_${reason}`));
    } else {
      return res.status(404).json({ error: 'Copia no encontrada.' });
    }
  } catch (err) {
    return res.status(404).json({ error: `No se pudo leer la copia: ${err.message}` });
  }
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Content-Disposition', `attachment; filename=copia_automatica_${Date.now()}.json`);
  res.send(payload);
});

app.post('/api/backup/snapshot-now', superAdminOnly, async (req, res) => {
  try {
    await createSnapshot('manual');
    res.json({ success: true, message: 'Copia de seguridad guardada exitosamente en Google Drive y localmente.' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/backup/download', superAdminOnly, async (req, res) => {
  // Includes the raffle templates; encrypted with the server key when one is configured
  const full = await buildFullExport();
  const payload = security.hasMasterKey() ? security.encryptObject(full, security.BACKUP_FORMAT) : full;
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Content-Disposition', `attachment; filename=backup_rifamaster_${Date.now()}.json`);
  res.send(JSON.stringify(payload));
});

const KNOWN_SECTIONS = ['companies', 'raffles', 'tickets', 'advisors', 'winners', 'cashTransactions', 'logs', 'auditLogs', 'commissionPayouts', 'cashDeliveries', 'subscriptionPayments', 'deletionRequests'];

/** Decodes an uploaded or stored backup; returns { data } or { error } without touching the database. */
function decodeBackup(backupData) {
  if (security.isEncryptedEnvelope(backupData)) {
    if (!security.hasMasterKey()) {
      return { error: 'La copia está cifrada y este servidor no tiene la llave de cifrado configurada.' };
    }
    try {
      backupData = security.decryptObject(backupData);
    } catch (_) {
      return { error: 'No se pudo descifrar la copia: fue creada con otra llave de cifrado o está dañada.' };
    }
  }
  if (!backupData || typeof backupData !== 'object' || Array.isArray(backupData)) {
    return { error: 'Formato de copia de seguridad inválido.' };
  }
  // A wrong JSON file must never replace the database with nothing
  const present = KNOWN_SECTIONS.filter(k => Array.isArray(backupData[k]));
  if (present.length < 3) {
    return { error: 'El archivo no parece una copia de seguridad de Rifa Master (faltan secciones de datos). No se modificó nada.' };
  }
  return { data: backupData };
}

app.post('/api/backup/restore', superAdminOnly, async (req, res) => {
  const { data, error } = decodeBackup(req.body);
  if (error) return res.status(400).json({ error });

  try {
    // Copy of the current data first: if this fails, nothing is restored
    await createSnapshot('before_restore');
  } catch (err) {
    return res.status(500).json({ error: `${err.message}. Por seguridad no se restauró la copia.` });
  }

  try {
    // Every section of the backup is kept (including cash transactions, logs and any future data);
    // only the SuperAdmin account stays the current one so nobody is locked out.
    const { superAdmin: _ignored, templateAssets, ...sections } = data;
    const restored = ensureDbShape({ ...sections, superAdmin: db.superAdmin });

    // Templates from the backup (new format) or embedded in raffles (old backups)
    if (templateAssets && typeof templateAssets === 'object') {
      for (const raffle of restored.raffles) {
        for (const type of TEMPLATE_TYPES) {
          const dataUri = templateAssets[raffle.id] && templateAssets[raffle.id][type];
          if (isImageDataUri(dataUri)) await storeRaffleTemplate(raffle, type, dataUri);
        }
      }
    }
    await extractEmbeddedTemplates(restored);
    // Older backups have no channel list: keep the current one
    if (!Array.isArray(restored.saleChannels) || !restored.saleChannels.length) restored.saleChannels = db.saleChannels;
    ensureSaleChannels(restored);
    if (!Array.isArray(restored.banks) || !restored.banks.length) restored.banks = db.banks;
    ensureBanks(restored);
    if (!Array.isArray(restored.lotteries) || !restored.lotteries.length) restored.lotteries = db.lotteries;
    ensureLotteries(restored);
    // Keep the current signing secret so receipts printed before the restore still verify
    restored.settings = { ...(restored.settings || {}), verificationSecret: (db.settings || {}).verificationSecret || (restored.settings || {}).verificationSecret };
    ensureVerificationSecret(restored);
    db = restored;

    migrateCredentials();
    saveDB();
    res.json({
      message: 'Base de datos restaurada exitosamente. Se guardó una copia automática de los datos anteriores.',
      timestamp: new Date().toISOString(),
      stats: {
        companiesCount: db.companies.length,
        rafflesCount: db.raffles.length,
        ticketsCount: db.tickets.length,
        advisorsCount: db.advisors.length,
        winnersCount: db.winners.length,
        cashTransactionsCount: db.cashTransactions.length
      }
    });
  } catch (err) {
    res.status(500).json({ error: `Error al restaurar base de datos: ${err.message}` });
  }
});

app.post('/api/backup/reset', superAdminOnly, async (req, res) => {
  try {
    await createSnapshot('before_reset');
  } catch (err) {
    return res.status(500).json({ error: `${err.message}. Por seguridad no se limpió la base.` });
  }
  const currentSuperAdmin = db.superAdmin;
  db = {
    companies: [],
    raffles: [],
    tickets: [],
    advisors: [],
    winners: [],
    cashTransactions: [],
    logs: [],
    auditLogs: [],
    commissionPayouts: [],
    superAdmin: currentSuperAdmin
  };
  saveDB();
  res.json({
    message: 'Base de datos limpiada por completo. Sólo SuperAdmin activo. Se guardó una copia automática antes de limpiar.',
    timestamp: new Date().toISOString(),
    stats: { companiesCount: 0, rafflesCount: 0, ticketsCount: 0, advisorsCount: 0 }
  });
});

// GET Raffles (Multi-tenant isolated)
app.get('/api/raffles', (req, res) => {
  const { advisorId, role, companyId } = req.query;
  let raffles = db.raffles || [];

  // Multi-tenant company filtering from session auth context
  // Admins and advisors only ever see their own company; the SuperAdmin may pick one with ?companyId=
  let targetCompanyId = companyId;
  if (req.auth && req.auth.role === 'admin') targetCompanyId = req.auth.record.id;
  if (req.auth && req.auth.role === 'asesor') targetCompanyId = req.auth.record.companyId;

  if (targetCompanyId) {
    raffles = raffles.filter(r => !r.companyId || r.companyId === targetCompanyId);
  }

  if ((role === 'asesor' || (req.auth && req.auth.role === 'asesor'))) {
    const advId = req.auth && req.auth.role === 'asesor' ? req.auth.record.id : advisorId;
    if (advId) {
      raffles = raffles.filter(r => r.status === 'ACTIVA' && (!r.assignedAdvisorIds || r.assignedAdvisorIds.length === 0 || r.assignedAdvisorIds.includes(advId)));
      // The advisor sees whether they can sell, not the admin's lock settings
      raffles = raffles.map(r => {
        const { salesLock, ...rest } = r;
        return { ...rest, advisorSalesBlock: advisorSaleBlock(r, advId) };
      });
    }
  }
  res.json(raffles);
});

// PUT Update Raffle
/** Un asesor solo puede vender y estar autorizado en rifas de SU empresa: cada asesor pertenece a una única empresa. */
function advisorBelongsToCompany(advisorId, companyId) {
  const advisor = (db.advisors || []).find(a => a.id === advisorId);
  return !!advisor && !!companyId && advisor.companyId === companyId;
}

// Rifas en las que está autorizado un asesor. raffle.assignedAdvisorIds vacío = todos los asesores de la empresa;
// NO_ADVISORS marca "ninguno" (una lista vacía no puede significar las dos cosas).
const NO_ADVISORS = '__ninguno__';

function advisorAuthorizedInRaffle(raffle, advisorId) {
  const list = raffle.assignedAdvisorIds;
  return !Array.isArray(list) || list.length === 0 || list.includes(advisorId);
}

/** Lista de autorizados de una rifa a partir de los ids elegidos (solo asesores de su empresa; vacío = ninguno). */
function normalizeRaffleAdvisorIds(raffle, ids) {
  const valid = (Array.isArray(ids) ? ids : []).filter(id => id !== NO_ADVISORS && (!raffle.companyId || advisorBelongsToCompany(id, raffle.companyId)));
  if (valid.length > 0) return [...new Set(valid)];
  const companyHasAdvisors = (db.advisors || []).some(a => a.companyId === raffle.companyId);
  return companyHasAdvisors ? [NO_ADVISORS] : [];
}

/** Deja al asesor autorizado exactamente en las rifas indicadas (de su empresa); no toca a los demás asesores. */
function setAdvisorRaffles(advisor, raffleIds) {
  const wanted = new Set(Array.isArray(raffleIds) ? raffleIds : []);
  const companyAdvisorIds = (db.advisors || []).filter(a => a.companyId === advisor.companyId).map(a => a.id);
  for (const raffle of db.raffles || []) {
    if (raffle.companyId !== advisor.companyId) continue;
    const authorized = advisorAuthorizedInRaffle(raffle, advisor.id);
    const current = Array.isArray(raffle.assignedAdvisorIds) && raffle.assignedAdvisorIds.length > 0 ? raffle.assignedAdvisorIds : null;
    if (wanted.has(raffle.id) && !authorized) {
      raffle.assignedAdvisorIds = [...(current || []).filter(id => id !== NO_ADVISORS), advisor.id];
    } else if (!wanted.has(raffle.id) && authorized) {
      const rest = (current || companyAdvisorIds).filter(id => id !== advisor.id && id !== NO_ADVISORS);
      raffle.assignedAdvisorIds = rest.length > 0 ? rest : [NO_ADVISORS];
    }
  }
}

function canAccessRaffle(req, raffle) {
  if (req.auth.role === 'superadmin') return true;
  const companyId = req.auth.role === 'admin' ? req.auth.record.id : req.auth.record.companyId;
  return !raffle.companyId || raffle.companyId === companyId;
}

/** Company the request works on: the admin's own; the SuperAdmin passes ?companyId=. */
function targetCompanyOf(req) {
  if (req.auth.role === 'admin') return req.auth.record;
  if (req.auth.role === 'superadmin') return (db.companies || []).find(c => c.id === req.query.companyId) || null;
  return null;
}

app.get('/api/terms', adminOnly, (req, res) => {
  const company = targetCompanyOf(req);
  if (!company) return res.status(400).json({ error: 'Seleccione la empresa.' });
  const raffles = (db.raffles || []).filter(r => r.companyId === company.id);
  const raffle = raffles.find(r => r.id === req.query.raffleId) || raffles[0];
  const template = company.termsTemplate || DEFAULT_TERMS_TEMPLATE;
  res.json({
    template,
    isDefault: !company.termsTemplate,
    defaultTemplate: DEFAULT_TERMS_TEMPLATE,
    placeholders: TERMS_PLACEHOLDERS.map(([key, description]) => ({ key, description })),
    preview: raffle ? renderTerms(template, raffle, company) : null,
    previewRaffle: raffle ? raffle.title : null
  });
});

// Renders a template with a raffle's data without saving it (live preview in the editor)
app.post('/api/terms/preview', adminOnly, (req, res) => {
  const company = targetCompanyOf(req);
  if (!company) return res.status(400).json({ error: 'Seleccione la empresa.' });
  const raffles = (db.raffles || []).filter(r => r.companyId === company.id);
  const raffle = raffles.find(r => r.id === (req.body || {}).raffleId) || raffles[0];
  if (!raffle) return res.json({ preview: null });
  const template = String((req.body || {}).template || '').slice(0, 8000) || DEFAULT_TERMS_TEMPLATE;
  res.json({ preview: renderTerms(template, raffle, company), previewRaffle: raffle.title });
});

app.put('/api/terms', adminOnly, (req, res) => {
  const company = targetCompanyOf(req);
  if (!company) return res.status(400).json({ error: 'Seleccione la empresa.' });
  const template = typeof (req.body || {}).template === 'string' ? req.body.template.trim() : '';
  if (template.length > 8000) return res.status(400).json({ error: 'El texto es demasiado largo (máximo 8.000 caracteres).' });
  // Empty text goes back to the generic template
  if (template) company.termsTemplate = template; else delete company.termsTemplate;
  company.termsUpdatedAt = new Date().toISOString();
  saveDB();
  res.json({ message: template ? 'Términos y condiciones guardados.' : 'Se restauró la plantilla genérica.', isDefault: !template });
});

// ---------------------------------------------------------------------------
// WhatsApp messages: each company edits one template per situation (company.messageTemplates).
// They are filled on the server from the SAVED ticket, so a buyer never gets data that was only
// typed in a form. Placeholders that give the buyer confidence cannot be removed.
// ---------------------------------------------------------------------------
const SEP = '━━━━━━━━━━━━━━━━━━';
const MESSAGE_TYPES = {
  reservada: {
    label: 'Boleta apartada (sin pago)',
    description: 'Se envía al apartar o fiar una boleta sin abono.',
    required: ['empresa', 'rifa', 'numeros', 'comprador', 'valor', 'debe', 'fecha_sorteo', 'loteria', 'enlace_verificacion'],
    template: `🎟️ *BOLETA APARTADA* - {rifa}
${SEP}
Hola *{comprador}* 👋
Tu boleta quedó apartada a tu nombre con *{empresa}*.

🔢 *Número(s):* {numeros}
💰 *Valor boleta:* {valor}
🔴 *Pendiente por pagar:* {debe}
👤 *Asesor(a):* {asesor}
${SEP}
📅 *Juega el:* {fecha_sorteo} con {loteria}
🏆 *Gana con:* {cifras_ganadoras}
⚠️ *Importante:* la boleta debe estar pagada en su totalidad antes del sorteo; si no, *no juega*.
${SEP}
💵 *Cómo pagar:* en efectivo con tu asesor(a) o por transferencia a:
{cuentas}
${SEP}
🔐 *Verifica tu boleta en línea:*
{enlace_verificacion}
¡Gracias por tu confianza! 🍀`
  },
  abono: {
    label: 'Abono registrado (pago parcial)',
    description: 'Se envía al registrar un abono que no completa el valor de la boleta.',
    required: ['empresa', 'rifa', 'numeros', 'comprador', 'abonado', 'debe', 'fecha_sorteo', 'loteria', 'enlace_verificacion'],
    template: `💵 *ABONO RECIBIDO* - {rifa}
${SEP}
Hola *{comprador}* 👋
*{empresa}* confirma que recibimos tu abono. ¡Gracias!

🔢 *Número(s):* {numeros}
💵 *Último abono:* {ultimo_abono} ({fecha_ultimo_abono})
✅ *Total abonado:* {abonado} de {valor}
🔴 *Saldo pendiente:* {debe}
👤 *Asesor(a):* {asesor}
${SEP}
📅 *Juega el:* {fecha_sorteo} con {loteria}
🏆 *Gana con:* {cifras_ganadoras}
⚠️ *Recuerda:* completa el pago antes del sorteo; la boleta que no esté pagada en su totalidad *no juega*.
🗓️ *Sorteos semanales:* {sorteos_semanales}
${SEP}
💵 *Para completar el pago:* en efectivo con tu asesor(a) o por transferencia a:
{cuentas}
${SEP}
🔐 *Verifica tu boleta en línea:*
{enlace_verificacion}
¡Mucha suerte! 🍀`
  },
  pagada: {
    label: 'Pago completo',
    description: 'Se envía cuando la boleta queda pagada en su totalidad.',
    required: ['empresa', 'rifa', 'numeros', 'comprador', 'valor', 'fecha_sorteo', 'loteria', 'enlace_verificacion'],
    template: `🎉 *¡BOLETA PAGADA!* - {rifa}
${SEP}
Hola *{comprador}* 👋
*{empresa}* confirma el pago completo de tu boleta. ¡Ya estás participando!

🔢 *Número(s):* {numeros}
💰 *Valor pagado:* {valor}
✅ *Estado:* PAGADA
👤 *Asesor(a):* {asesor}
${SEP}
📅 *Juega el:* {fecha_sorteo} con {loteria}
🏆 *Gana con:* {cifras_ganadoras}
🗓️ *Sorteos semanales:* {sorteos_semanales}
${SEP}
🔐 *Verifica tu boleta en línea:*
{enlace_verificacion}
🔑 *Código de verificación:* {codigo_verificacion}
Guarda este mensaje: es tu comprobante. ¡Mucha suerte! 🍀`
  },
  recordatorio: {
    label: 'Recordatorio de pago',
    description: 'Se envía desde la campana de la boleta para cobrar una boleta apartada o con abono.',
    required: ['empresa', 'rifa', 'numeros', 'comprador', 'debe', 'fecha_sorteo', 'loteria', 'cuentas'],
    template: `🔔 *RECORDATORIO DE PAGO* - {rifa}
${SEP}
Hola *{comprador}* 👋
Te escribimos de *{empresa}* para recordarte que tu boleta aún tiene saldo pendiente:

🔢 *Número(s):* {numeros}
💰 *Valor boleta:* {valor}
✅ *Abonado:* {abonado}
🔴 *Debes:* {debe}
${SEP}
📅 La rifa juega el *{fecha_sorteo}* con {loteria}.
⚠️ *Recuerda: la boleta que no esté pagada en su totalidad NO juega.*
${SEP}
💵 Puedes pagar en *efectivo* con tu asesor(a) {asesor} o por *transferencia* a:
{cuentas}
📲 Si pagas por transferencia, envíanos el comprobante por este medio.
${SEP}
🔐 *Verifica tu boleta:*
{enlace_verificacion}
¡Gracias y muchos éxitos en el sorteo! 🍀`
  }
};

const MESSAGE_PLACEHOLDERS = [
  ['empresa', 'Nombre de la empresa'],
  ['rifa', 'Nombre de la rifa'],
  ['descripcion', 'Descripción de la rifa'],
  ['comprador', 'Nombre del comprador'],
  ['celular', 'Celular del comprador'],
  ['numeros', 'Número(s) de la boleta'],
  ['valor', 'Valor de la boleta'],
  ['abonado', 'Total abonado'],
  ['debe', 'Saldo pendiente'],
  ['ultimo_abono', 'Valor del último abono'],
  ['fecha_ultimo_abono', 'Fecha del último abono'],
  ['estado', 'Estado de la boleta'],
  ['asesor', 'Asesor(a) que vendió la boleta'],
  ['fecha_sorteo', 'Fecha del sorteo principal (ej: sábado 03 de octubre de 2026)'],
  ['loteria', 'Lotería del sorteo principal'],
  ['cifras_ganadoras', 'Cifras que deciden el ganador'],
  ['sorteos_semanales', 'Sorteos semanales: día, lotería y abono mínimo, o "no aplica"'],
  ['cuentas', 'Cuentas de transferencia de la rifa (una por línea)'],
  ['enlace_verificacion', 'Enlace para verificar la boleta en línea'],
  ['codigo_verificacion', 'Código de verificación de la boleta']
];

const WEEKDAYS_ES = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
const MONTHS_ES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

/** "sábado 03 de octubre de 2026" in Colombian time. Plain dates ("2026-10-03") are taken as they are. */
function colombiaLongDate(value) {
  const str = String(value || '').trim();
  let y, m, d;
  const plain = /^(\d{4})-(\d{2})-(\d{2})$/.exec(str);
  if (plain) { y = +plain[1]; m = +plain[2]; d = +plain[3]; } else {
    const ms = Date.parse(str);
    if (isNaN(ms)) return 'la fecha anunciada';
    const col = new Date(ms - COLOMBIA_OFFSET_MS);
    y = col.getUTCFullYear(); m = col.getUTCMonth() + 1; d = col.getUTCDate();
  }
  const weekday = WEEKDAYS_ES[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
  return `${weekday} ${String(d).padStart(2, '0')} de ${MONTHS_ES[m - 1]} de ${y}`;
}

/** Type of the message that confirms a saved ticket. */
function receiptTypeOf(ticket) {
  if ((ticket.totalPaid || 0) <= 0) return 'reservada';
  const hasUnvalidatedTransfer = (ticket.abonos || []).some(a => isTransferAbono(a) && (!a.verification || a.verification.status !== 'VALIDADA'));
  if (hasUnvalidatedTransfer && !ticket.confirmedByAdmin) {
    return 'abono';
  }
  return (ticket.totalPaid || 0) >= (ticket.price || 0) ? 'pagada' : 'abono';
}

function messageTemplateOf(company, type) {
  const custom = company && company.messageTemplates && company.messageTemplates[type];
  return custom || MESSAGE_TYPES[type].template;
}

function renderMessage(template, { ticket, raffle, company, baseUrl }) {
  const money = v => `$${Math.round(Number(v) || 0).toLocaleString('es-CO')}`;
  const price = Number(ticket.price) || 0;
  const paid = Number(ticket.totalPaid) || 0;
  const payments = (ticket.abonos || []).filter(a => (a.amount || 0) > 0);
  const last = payments[payments.length - 1];
  const minAbono = weeklyMinAbonoOf(raffle, nextWeeklyPrize(raffle));
  const weeklyLottery = lotteryPhrase(String(raffle.lotteryName || '').trim() || mainLotteryOf(raffle));
  const owes = paid < price;
  // One field per line and a blank line between accounts; a paid ticket does not need them
  const accounts = (raffle.transferAccounts || []).map(a => [
    a.bank && `🏦 *Banco:* ${a.bank}`,
    a.accountNumber && `🔢 *Número:* ${a.accountNumber}`,
    a.accountType && `📋 *Tipo:* ${a.accountType}`,
    a.key && `🔑 *Llave:* ${a.key}`,
    a.holder && `👤 *Titular:* ${a.holder}`
  ].filter(Boolean).join('\n'));
  const code = ticketVerificationCode(ticket);
  const statusLabel = { RESERVADA: 'APARTADA', ABONO_PARCIAL: 'ABONO PARCIAL', PAGADA: 'PAGADA', CONFIRMADA: 'PAGADA Y CONFIRMADA' }[ticket.status] || ticket.status;
  const values = {
    empresa: company.name || 'la organización',
    rifa: raffle.title || '',
    descripcion: raffle.description || '',
    comprador: ticket.buyerName || 'cliente',
    celular: ticket.buyerPhone || 'no registrado',
    numeros: (ticket.numbers || []).join(' - ') || String(ticket.ticketNumber || ''),
    valor: money(price),
    abonado: money(paid),
    debe: money(Math.max(0, price - paid)),
    ultimo_abono: last ? money(last.amount) : money(0),
    fecha_ultimo_abono: last ? colombiaLongDate(last.date) : 'sin abonos',
    estado: statusLabel,
    asesor: ticket.advisorName || company.name || 'de la rifa',
    fecha_sorteo: colombiaLongDate(raffle.mainDrawDate),
    loteria: lotteryPhrase(mainLotteryOf(raffle)),
    cifras_ganadoras: winningRuleText(raffle),
    sorteos_semanales: raffle.hasWeeklyDraws === false
      ? 'no aplica para esta rifa'
      : `cada ${raffle.weeklyDrawDay || 'semana'} con ${weeklyLottery}; participan las boletas con un abono mínimo de ${money(minAbono)}`,
    cuentas: !owes ? '' : (accounts.length ? accounts.join('\n\n') : 'Consulta las cuentas con tu asesor(a).'),
    enlace_verificacion: code ? `${baseUrl}/verificar/${code}` : '(disponible cuando la boleta esté registrada)',
    codigo_verificacion: code || '—'
  };
  let cleanTpl = String(template || '')
    .replace(/([^\n\r])\s*\{enlace_verificacion\}/g, '$1\n{enlace_verificacion}')
    .replace(/\{enlace_verificacion\}\s*([^\n\r])/g, '{enlace_verificacion}\n$1');
  const lines = cleanTpl.split('\n');
  return lines
    .filter(line => !(line.trim() === '{cuentas}' && !values.cuentas))
    .join('\n')
    .replace(/\{([a-z_]+)\}/g, (m, key) => (key in values ? values[key] : m));
}

function publicBaseUrl(req) {
  return `${req.protocol}://${req.get('host')}`;
}

function messageTypesResponse(company) {
  return Object.entries(MESSAGE_TYPES).map(([type, def]) => ({
    type,
    label: def.label,
    description: def.description,
    required: def.required,
    template: messageTemplateOf(company, type),
    isDefault: !(company && company.messageTemplates && company.messageTemplates[type]),
    defaultTemplate: def.template
  }));
}

app.get('/api/message-templates', adminOnly, (req, res) => {
  const company = targetCompanyOf(req);
  if (!company) return res.status(400).json({ error: 'Seleccione la empresa.' });
  res.json({
    types: messageTypesResponse(company),
    placeholders: MESSAGE_PLACEHOLDERS.map(([key, description]) => ({ key, description }))
  });
});

app.put('/api/message-templates', adminOnly, (req, res) => {
  const company = targetCompanyOf(req);
  if (!company) return res.status(400).json({ error: 'Seleccione la empresa.' });
  const { type } = req.body || {};
  const def = MESSAGE_TYPES[type];
  if (!def) return res.status(400).json({ error: 'Tipo de mensaje no válido.' });
  const template = typeof req.body.template === 'string' ? req.body.template.trim() : '';
  if (template.length > 4000) return res.status(400).json({ error: 'El mensaje es demasiado largo (máximo 4.000 caracteres).' });
  if (template) {
    // The data that gives the buyer confidence cannot be left out
    const missing = def.required.filter(key => !template.includes(`{${key}}`));
    if (missing.length) {
      return res.status(400).json({ error: `El mensaje debe incluir: ${missing.map(k => `{${k}}`).join(', ')}.`, missing });
    }
    company.messageTemplates = { ...(company.messageTemplates || {}), [type]: template };
  } else if (company.messageTemplates) {
    delete company.messageTemplates[type]; // empty text goes back to the default message
  }
  company.messageTemplatesUpdatedAt = new Date().toISOString();
  saveDB();
  res.json({ message: template ? 'Mensaje guardado.' : 'Se restauró el mensaje predeterminado.', types: messageTypesResponse(company) });
});

// Preview with a real ticket of the company (or a sample when there is none)
app.post('/api/message-templates/preview', adminOnly, (req, res) => {
  const company = targetCompanyOf(req);
  if (!company) return res.status(400).json({ error: 'Seleccione la empresa.' });
  const { type, raffleId } = req.body || {};
  if (!MESSAGE_TYPES[type]) return res.status(400).json({ error: 'Tipo de mensaje no válido.' });
  const raffles = (db.raffles || []).filter(r => r.companyId === company.id);
  const raffle = raffles.find(r => r.id === raffleId) || raffles[0];
  if (!raffle) return res.json({ preview: null });
  const wanted = { reservada: ['RESERVADA'], abono: ['ABONO_PARCIAL'], pagada: ['PAGADA', 'CONFIRMADA'], recordatorio: ['ABONO_PARCIAL', 'RESERVADA'] }[type];
  const real = (db.tickets || []).find(t => t.raffleId === raffle.id && wanted.includes(t.status));
  const price = Number(raffle.ticketPrice) || 50000;
  const samplePaid = { reservada: 0, abono: Math.round(price / 2), pagada: price, recordatorio: Math.round(price / 2) }[type];
  const ticket = real || {
    id: 'muestra', raffleId: raffle.id, numbers: ['07'], status: wanted[0], price, totalPaid: samplePaid,
    buyerName: 'Nombre del comprador', buyerPhone: '3000000000', advisorName: 'Nombre del asesor',
    abonos: samplePaid ? [{ amount: samplePaid, date: new Date().toISOString() }] : []
  };
  const template = String(req.body.template || '').slice(0, 4000) || messageTemplateOf(company, type);
  res.json({ preview: renderMessage(template, { ticket, raffle, company, baseUrl: publicBaseUrl(req) }), previewRaffle: raffle.title, sample: !real });
});

// Message for a saved ticket: kind "receipt" (by its status) or "reminder"
app.get('/api/tickets/:id/whatsapp-message', (req, res) => {
  const ticket = (db.tickets || []).find(t => t.id === req.params.id);
  const raffle = ticket && (db.raffles || []).find(r => r.id === ticket.raffleId);
  if (!ticket || !raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Boleta no encontrada' });
  if (ticket.status === 'DISPONIBLE') return res.status(400).json({ error: 'La boleta está disponible: no tiene comprador para enviarle un mensaje.' });
  const company = (db.companies || []).find(c => c.id === raffle.companyId) || {};
  const type = req.query.kind === 'reminder' ? 'recordatorio' : receiptTypeOf(ticket);
  if (type === 'recordatorio' && receiptTypeOf(ticket) === 'pagada') {
    return res.status(400).json({ error: 'La boleta ya está pagada: no hay saldo que recordar.' });
  }
  res.json({
    type,
    phone: ticket.buyerPhone || '',
    message: renderMessage(messageTemplateOf(company, type), { ticket, raffle, company, baseUrl: publicBaseUrl(req) })
  });
});

// History of voided sales and voided payments (admins: own company; SuperAdmin: all or ?companyId=)
app.get('/api/audit/voids', adminOnly, (req, res) => {
  const companyId = req.auth.role === 'admin' ? req.auth.record.id : req.query.companyId;
  const raffles = (db.raffles || []).filter(r => !companyId || r.companyId === companyId);
  const raffleById = Object.fromEntries(raffles.map(r => [r.id, r]));
  const entries = [];
  for (const t of db.tickets || []) {
    const raffle = raffleById[t.raffleId];
    if (!raffle || (req.query.raffleId && t.raffleId !== req.query.raffleId)) continue;
    for (const a of t.annulments || []) {
      const p = a.previous || {};
      entries.push({
        type: 'VENTA', date: a.date, by: a.by, reason: a.reason,
        raffleId: raffle.id, raffleTitle: raffle.title, ticketId: t.id, numbers: t.numbers,
        buyerName: p.buyerName || '', buyerPhone: p.buyerPhone || '', buyerDocument: p.buyerDocument || '', advisorName: p.advisorName || '',
        saleChannel: p.saleChannel || '', amount: p.totalPaid || 0, previousStatus: p.status || ''
      });
    }
    // Voided payments of the current sale and of sales voided later
    const voided = [
      ...(t.voidedAbonos || []).map(v => [v, t]),
      ...(t.annulments || []).flatMap(a => ((a.previous || {}).voidedAbonos || []).map(v => [v, a.previous]))
    ];
    for (const [v, owner] of voided) {
      entries.push({
        type: 'ABONO', date: v.voidedAt, by: v.voidedBy, reason: v.voidReason,
        raffleId: raffle.id, raffleTitle: raffle.title, ticketId: t.id, numbers: t.numbers,
        buyerName: v.buyerName || owner.buyerName || '', buyerPhone: v.buyerPhone || owner.buyerPhone || '',
        buyerDocument: v.buyerDocument || owner.buyerDocument || '',
        advisorName: v.sellerName || '', saleChannel: owner.saleChannel || '', amount: v.amount || 0, paymentDate: v.date
      });
    }
  }
  entries.sort((a, b) => String(b.date).localeCompare(String(a.date)));
  res.json(entries);
});

// Raffle templates: the image is downloaded only when the poster or ticket print is opened
app.get('/api/raffles/:id/templates/:type', async (req, res) => {
  const raffle = (db.raffles || []).find(r => r.id === req.params.id);
  if (!raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Sorteo no encontrado.' });
  if (!TEMPLATE_TYPES.includes(req.params.type)) return res.status(400).json({ error: 'Tipo de plantilla no válido.' });
  const meta = (raffle.templates || {})[req.params.type];
  if (!meta) return res.status(404).json({ error: 'Este sorteo no tiene esa plantilla.' });
  if (req.headers['if-none-match'] === meta.version) return res.status(304).end();
  try {
    const dataUri = await readTemplate(raffle.id, req.params.type);
    if (!dataUri) return res.status(404).json({ error: 'No se encontró la imagen de la plantilla.' });
    res.setHeader('ETag', meta.version);
    res.json({ type: req.params.type, version: meta.version, dataUri });
  } catch (err) {
    res.status(500).json({ error: `No se pudo leer la plantilla: ${err.message}` });
  }
});

app.put('/api/raffles/:id/templates/:type', adminOnly, async (req, res) => {
  const raffle = (db.raffles || []).find(r => r.id === req.params.id);
  if (!raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Sorteo no encontrado.' });
  if (!TEMPLATE_TYPES.includes(req.params.type)) return res.status(400).json({ error: 'Tipo de plantilla no válido.' });
  const { dataUri } = req.body || {};
  if (!isImageDataUri(dataUri)) return res.status(400).json({ error: 'La plantilla debe ser una imagen PNG, JPG o WEBP.' });
  if (dataUri.length > MAX_TEMPLATE_BYTES) return res.status(413).json({ error: 'La imagen es demasiado grande (máximo ~6 MB).' });
  try {
    await storeRaffleTemplate(raffle, req.params.type, dataUri);
    saveDB();
    res.json({ message: 'Plantilla guardada.', template: raffle.templates[req.params.type] });
  } catch (err) {
    res.status(500).json({ error: `No se pudo guardar la plantilla: ${err.message}` });
  }
});

app.delete('/api/raffles/:id/templates/:type', adminOnly, async (req, res) => {
  const raffle = (db.raffles || []).find(r => r.id === req.params.id);
  if (!raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Sorteo no encontrado.' });
  if (!TEMPLATE_TYPES.includes(req.params.type)) return res.status(400).json({ error: 'Tipo de plantilla no válido.' });
  try {
    await deleteTemplate(raffle.id, req.params.type);
    if (raffle.templates) delete raffle.templates[req.params.type];
    saveDB();
    res.json({ message: 'Plantilla eliminada.' });
  } catch (err) {
    res.status(500).json({ error: `No se pudo eliminar la plantilla: ${err.message}` });
  }
});

app.put('/api/raffles/:id', adminOnly, async (req, res) => {
  const { id } = req.params;
  const raffle = db.raffles.find(r => r.id === id);
  if (!raffle) {
    return res.status(404).json({ error: 'Sorteo no encontrado' });
  }
  let mainLotteryName = null;
  if (req.body.mainLotteryName !== undefined) {
    const checked = checkRaffleLottery(req.body.mainLotteryName, raffle.mainLotteryName, 'lotería del sorteo principal');
    if (checked.error) return res.status(400).json({ error: checked.error });
    mainLotteryName = checked.name;
  }
  let weeklyLotteryName = null;
  if (req.body.lotteryName !== undefined && String(req.body.lotteryName).trim() !== '') {
    const checked = checkRaffleLottery(req.body.lotteryName, raffle.lotteryName, 'lotería de los sorteos semanales');
    if (checked.error) return res.status(400).json({ error: checked.error });
    weeklyLotteryName = checked.name;
  }
  let transferAccounts = null;
  if (req.body.transferAccounts !== undefined) {
    const checked = normalizeTransferAccounts(req.body.transferAccounts, raffle.transferAccounts || []);
    if (checked.error) return res.status(400).json({ error: checked.error });
    transferAccounts = checked.accounts;
  }

  if (req.body.status !== undefined) {
    const before = raffle.status;
    raffle.status = req.body.status;
    // Inactivar una rifa cierra las ventas de todos los asesores; al reactivarla se pregunta a quiénes se les reactivan
    if (raffle.status === 'INACTIVA' && before !== 'INACTIVA') lockAdvisorSales(raffle, actorName(req), 'Rifa inactivada');
    else if (raffle.status === 'ACTIVA' && before === 'INACTIVA') applyReactivationLock(raffle, req);
  }
  if (req.body.title !== undefined) {
    const oldTitle = raffle.title;
    const newTitle = String(req.body.title).trim();
    raffle.title = newTitle;
    if (oldTitle !== newTitle && (raffle.driveFolderId || raffle.id)) {
      const company = (db.companies || []).find(c => c.id === raffle.companyId);
      const companyName = company ? (company.name || company.companyName || 'Empresa') : 'Empresa General';
      driveService.getRaffleFolders(companyName, raffle.companyId, newTitle, raffle.id, raffle.driveFolderId)
        .then(folders => { raffle.driveFolderId = folders.raffleFolderId; saveDB(); })
        .catch(err => console.error('⚠️ Error actualizando nombre de carpeta en Drive:', err.message));
    }
  }
  if (req.body.ticketPrice !== undefined) {
    const newPrice = Math.round(Number(req.body.ticketPrice));
    if (!Number.isFinite(newPrice) || newPrice <= 0) return res.status(400).json({ error: 'El valor de la boleta debe ser mayor a 0.' });
    const oldPrice = raffle.ticketPrice;
    raffle.ticketPrice = newPrice;
    // Se aplica a TODAS las boletas (disponibles, apartadas, fiadas y con abono parcial) y se recalcula su saldo.
    // Solo se respetan las que ya tienen pagado un valor igual o mayor al nuevo precio (o al anterior): cambiarles el precio
    // dejaría el saldo/estado inconsistente (pagada con deuda, o con excedente sin transferir).
    let updated = 0, kept = 0;
    (db.tickets || []).forEach(t => {
      if (t.raffleId !== raffle.id || Number(t.price) === newPrice) return;
      const paid = Number(t.totalPaid) || 0;
      if (paid > 0 && paid >= Math.min(Number(t.price) || 0, newPrice)) { kept++; return; }
      t.price = newPrice;
      if (t.balancePending !== undefined) t.balancePending = Math.max(0, newPrice - paid);
      updated++;
    });
    if (oldPrice !== newPrice || updated > 0) {
      if (!db.auditLogs) db.auditLogs = [];
      db.auditLogs.push({
        id: `audit-${Date.now()}`, type: 'TICKET_PRICE', companyId: raffle.companyId, targetId: raffle.id, targetName: raffle.title,
        detail: `Valor de boleta ${oldPrice} → ${newPrice} (${updated} boletas actualizadas; ${kept} ya pagadas conservan su valor)`,
        by: actorName(req), date: new Date().toISOString()
      });
    }
  }
  if (req.body.description !== undefined) raffle.description = req.body.description;
  if (Array.isArray(req.body.prizeImages)) raffle.prizeImages = req.body.prizeImages.map(normalizeDriveImageUrl);
  if (req.body.mainDrawDate !== undefined) raffle.mainDrawDate = req.body.mainDrawDate;
  if (req.body.weeklyPrizesStartDate !== undefined) raffle.weeklyPrizesStartDate = req.body.weeklyPrizesStartDate;
  if (req.body.assignedAdvisorIds !== undefined) {
    // Solo asesores de la empresa dueña de la rifa (los de otra empresa se descartan); sin ninguno = nadie autorizado
    raffle.assignedAdvisorIds = raffle.companyId ? normalizeRaffleAdvisorIds(raffle, req.body.assignedAdvisorIds) : (Array.isArray(req.body.assignedAdvisorIds) ? req.body.assignedAdvisorIds : []);
  }
  if (req.body.commissionType !== undefined) raffle.commissionType = req.body.commissionType;
  if (req.body.commissionValue !== undefined) raffle.commissionValue = parseFloat(req.body.commissionValue) || 0;
  if (req.body.commissionTiers !== undefined) raffle.commissionTiers = Array.isArray(req.body.commissionTiers) ? req.body.commissionTiers : [];
  if (req.body.templateConfig !== undefined && req.body.templateConfig !== null && typeof req.body.templateConfig === 'object') {
    const { templateImageBase64, ...settings } = req.body.templateConfig;
    // An image sent inside the settings (older app versions) goes to the template store
    if (isImageDataUri(templateImageBase64)) {
      try {
        await storeRaffleTemplate(raffle, 'poster', templateImageBase64);
      } catch (err) {
        return res.status(500).json({ error: `No se pudo guardar la plantilla: ${err.message}` });
      }
    }
    raffle.templateConfig = settings;
  }
  if (transferAccounts) raffle.transferAccounts = transferAccounts;
  Object.assign(raffle, normalizeWinningConfig(req.body, raffle.digits));
  // Weekly draw settings (previously ignored, so they reverted after every reload)
  if (req.body.hasWeeklyDraws !== undefined) raffle.hasWeeklyDraws = req.body.hasWeeklyDraws === true || req.body.hasWeeklyDraws === 'true';
  if (req.body.weeklyDrawDay !== undefined) raffle.weeklyDrawDay = String(req.body.weeklyDrawDay);
  if (mainLotteryName) raffle.mainLotteryName = mainLotteryName;
  if (weeklyLotteryName) raffle.lotteryName = weeklyLotteryName;
  if (['PORCENTAJE', 'VALOR_FIJO'].includes(req.body.weeklyMinAbonoType)) raffle.weeklyMinAbonoType = req.body.weeklyMinAbonoType;
  if (req.body.weeklyMinAbonoValue !== undefined) raffle.weeklyMinAbonoValue = parseFloat(req.body.weeklyMinAbonoValue) || 0;
  if (req.body.isWeeklyPrizeAccumulative !== undefined) raffle.isWeeklyPrizeAccumulative = req.body.isWeeklyPrizeAccumulative === true || req.body.isWeeklyPrizeAccumulative === 'true';
  if (Array.isArray(req.body.weeklyPrizes)) raffle.weeklyPrizes = req.body.weeklyPrizes;

  saveDB();
  res.json(raffle);
});

// DELETE Raffle
app.delete('/api/raffles/:id', adminOnly, (req, res) => {
  const { id } = req.params;
  const index = (db.raffles || []).findIndex(r => r.id === id);
  if (index === -1) {
    return res.status(404).json({ error: 'Sorteo no encontrado' });
  }

  const raffle = db.raffles[index];
  if (req.auth.role === 'admin' && raffle.companyId !== req.auth.record.id) {
    return res.status(403).json({ error: 'No tiene permisos para eliminar rifas de otra empresa.' });
  }

  // Elimina TODO: la rifa, sus boletas, pagos, ganadores y entregas de la base de datos, y su carpeta de Google Drive (a la papelera de Drive).
  // Antes se guarda una copia de seguridad de la base de datos por si fue un error.
  createSnapshot('antes_de_eliminar_rifa_manual').catch(() => {});
  purgeRaffle(raffle, `Eliminada manualmente por ${actorName(req)}`);

  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({
    id: `audit-${Date.now()}`,
    type: 'DELETE_RAFFLE',
    targetId: id,
    targetName: raffle.title,
    date: new Date().toISOString()
  });

  saveDB();
  res.json({ message: `Sorteo "${raffle.title}" y sus boletas asociadas fueron eliminados exitosamente.` });
});

// ---------------------------------------------------------------------------
// Ciclo de vida de rifas:
// 1) A los 30 días del sorteo: se inhabilita la rifa (status INACTIVA) y se eliminan
//    los soportes de Google Drive para liberar espacio en la nube (la rifa queda en base de datos).
// 2) A los 6 meses (180 días) del sorteo: se elimina por completo de la base de datos
//    (con copia de seguridad de respaldo previa).
// ---------------------------------------------------------------------------
const CLOSE_GRACE_DAYS = 45;   // una rifa cerrada queda 45 días disponible para consultar/descargar y luego se elimina todo
const DRIVE_CLEANUP_DAYS = 45; // 45 días después del sorteo (rifas que nadie cerró) -> Borrar soportes en Drive e inhabilitar
const DB_PURGE_DAYS = 180;     // 6 meses (180 días) después del sorteo -> Eliminar de la base de datos

function drawDayOf(raffle) {
  const raw = String(raffle.mainDrawDate || '');
  if (/^\d{4}-\d{2}-\d{2}T12:00:00/.test(raw) || /^\d{4}-\d{2}-\d{2}$/.test(raw)) return raw.slice(0, 10);
  const ms = Date.parse(raw);
  return isNaN(ms) ? null : colombiaDay(ms);
}

// ---------------------------------------------------------------------------
// Advisor sales lock: the admin stops advisors from selling new tickets of a raffle, for all of them or
// advisor by advisor, right away or automatically from a time on the main draw day. Admins keep selling,
// and advisors can still register payments of tickets they already sold.
// ---------------------------------------------------------------------------
function salesLockOf(raffle) {
  const l = (raffle && raffle.salesLock) || {};
  return {
    locked: l.locked === true,
    reason: String(l.reason || ''),
    lockedBy: l.lockedBy || null,
    lockedAt: l.lockedAt || null,
    autoLockTime: /^([01]\d|2[0-3]):[0-5]\d$/.test(l.autoLockTime || '') ? l.autoLockTime : '',
    advisors: l.advisors && typeof l.advisors === 'object' ? l.advisors : {}
  };
}

/** Moment the automatic lock starts (main draw day at autoLockTime, Colombian time), or null when off. */
function autoLockAtMs(raffle, lock) {
  const day = drawDayOf(raffle);
  if (!lock.autoLockTime || !day) return null;
  return Date.parse(`${day}T${lock.autoLockTime}:00Z`) + COLOMBIA_OFFSET_MS;
}

function hour12(hhmm) {
  const [h, m] = hhmm.split(':').map(Number);
  return `${((h + 11) % 12) + 1}:${String(m).padStart(2, '0')} ${h < 12 ? 'a. m.' : 'p. m.'}`;
}

/**
 * Por qué una rifa ya no vende boletas nuevas (a nadie: ni asesores ni administrador), o null si puede vender:
 cerrada, inactiva o con la fecha del sorteo final ya pasada (calendario de Colombia).
 */
function salesBlockReason(raffle, now = Date.now()) {
  if (!raffle) return null;
  if (raffle.scheduledDeletionAt) return 'La rifa está CERRADA: ya no se pueden vender boletas.';
  if (raffle.status === 'INACTIVA') return 'La rifa está INACTIVA: ya no se pueden vender boletas. El administrador debe reactivarla.';
  const day = drawDayOf(raffle);
  if (day && day < colombiaDay(now)) {
    const [y, m, d] = day.split('-');
    return `La fecha del sorteo final (${d}/${m}/${y}) ya pasó: ya no se pueden vender boletas.`;
  }
  return null;
}
const raffleSalesClosed = raffle => !!salesBlockReason(raffle);

/** Cierra las ventas de TODOS los asesores de la rifa (se hace sola al cerrarla o inactivarla). */
function lockAdvisorSales(raffle, by, reason) {
  raffle.salesLock = { ...salesLockOf(raffle), locked: true, reason, lockedBy: by, lockedAt: new Date().toISOString(), advisors: {} };
}

/**
 * Al reactivar una rifa se decide a quién se le reactivan las ventas: advisorMode ALL (todos), SOME (solo advisorIds)
 * o sin indicar (los asesores siguen bloqueados y el administrador los habilita después).
 */
function applyReactivationLock(raffle, req) {
  const body = req.body || {};
  const mode = String(body.advisorMode || '');
  const lock = salesLockOf(raffle);
  const companyAdvisors = (db.advisors || []).filter(a => a.companyId === raffle.companyId);
  let detail = 'ventas de asesores siguen bloqueadas';
  if (mode === 'ALL') {
    raffle.salesLock = { ...lock, locked: false, reason: '', lockedBy: null, lockedAt: null, advisors: {} };
    detail = 'ventas reactivadas para todos los asesores';
  } else if (mode === 'SOME') {
    const allowed = new Set(Array.isArray(body.advisorIds) ? body.advisorIds : []);
    const advisors = {};
    for (const a of companyAdvisors) {
      if (!allowed.has(a.id)) advisors[a.id] = { reason: 'No reactivado al reabrir la rifa', by: actorName(req), at: new Date().toISOString() };
    }
    raffle.salesLock = { ...lock, locked: false, reason: '', lockedBy: null, lockedAt: null, advisors };
    detail = `ventas reactivadas solo para ${allowed.size} asesor(es)`;
  }
  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({ id: `audit-${Date.now()}`, type: 'REOPEN_RAFFLE', companyId: raffle.companyId, targetId: raffle.id, targetName: raffle.title, detail: `Rifa reactivada: ${detail}`, by: actorName(req), date: new Date().toISOString() });
}

/** Why this advisor cannot sell new tickets of the raffle right now, or null. */
function advisorSaleBlock(raffle, advisorId, now = Date.now()) {
  if (!raffle) return null;
  const lock = salesLockOf(raffle);
  const withReason = reason => (reason ? `: ${reason.replace(/[.\s]+$/, '')}.` : '.');
  const own = lock.advisors[advisorId];
  if (own) return `El administrador bloqueó sus ventas en esta rifa${withReason(own.reason)}`;
  if (lock.locked) return `El administrador cerró las ventas de asesores en esta rifa${withReason(lock.reason)}`;
  const at = autoLockAtMs(raffle, lock);
  if (at !== null && now >= at) {
    return `Las ventas de asesores se cerraron el día del sorteo a las ${hour12(lock.autoLockTime)}`;
  }
  return null;
}

/** Lock settings plus, per advisor, whether they can sell and how many of their numbers are still unsold. */
function salesLockView(raffle) {
  const lock = salesLockOf(raffle);
  const tickets = (db.tickets || []).filter(t => t.raffleId === raffle.id);
  const available = tickets.filter(t => t.status === 'DISPONIBLE');
  const at = autoLockAtMs(raffle, lock);
  const advisors = (db.advisors || [])
    .filter(a => a.companyId === raffle.companyId && a.status !== 'INHABILITADO')
    .filter(a => !raffle.assignedAdvisorIds || raffle.assignedAdvisorIds.length === 0 || raffle.assignedAdvisorIds.includes(a.id))
    .map(a => {
      const assigned = a.mode === 'ASSIGNED' && (a.assignedTicketRanges || []).length > 0;
      const own = lock.advisors[a.id] || null;
      return {
        advisorId: a.id,
        name: a.name,
        code: a.code,
        assignedRanges: assigned ? a.assignedTicketRanges : [],
        availableInRanges: assigned && raffle.isIndependentBook ? available.filter(t => ticketInAdvisorRanges(t, a, raffle)).length : null,
        sold: tickets.filter(t => t.advisorId === a.id && t.status !== 'DISPONIBLE').length,
        locked: !!own,
        reason: own ? own.reason || '' : '',
        lockedBy: own ? own.by || null : null,
        lockedAt: own ? own.at || null : null,
        blockedNow: advisorSaleBlock(raffle, a.id)
      };
    });
  return {
    raffleId: raffle.id,
    locked: lock.locked,
    reason: lock.reason,
    lockedBy: lock.lockedBy,
    lockedAt: lock.lockedAt,
    autoLockTime: lock.autoLockTime,
    autoLockAt: at !== null ? new Date(at).toISOString() : null,
    autoLockActive: at !== null && Date.now() >= at,
    drawDay: drawDayOf(raffle),
    totalAvailable: available.length,
    totalTickets: tickets.length,
    advisors
  };
}

function lockedRaffle(req, res) {
  const raffle = (db.raffles || []).find(r => r.id === req.params.id);
  if (!raffle || !canAccessRaffle(req, raffle)) {
    res.status(404).json({ error: 'Rifa no encontrada.' });
    return null;
  }
  return raffle;
}

app.get('/api/raffles/:id/sales-lock', adminOnly, (req, res) => {
  const raffle = lockedRaffle(req, res);
  if (raffle) res.json(salesLockView(raffle));
});

// General lock (all advisors) and the automatic time on the draw day
app.put('/api/raffles/:id/sales-lock', adminOnly, (req, res) => {
  const raffle = lockedRaffle(req, res);
  if (!raffle) return;
  const lock = salesLockOf(raffle);
  if (req.body.autoLockTime !== undefined) {
    const time = String(req.body.autoLockTime || '').trim();
    if (time && !/^([01]\d|2[0-3]):[0-5]\d$/.test(time)) return res.status(400).json({ error: 'Hora inválida. Use el formato HH:MM (24 horas).' });
    lock.autoLockTime = time;
  }
  if (req.body.locked !== undefined) {
    const locked = req.body.locked === true;
    if (locked !== lock.locked) {
      lock.locked = locked;
      lock.reason = locked ? String(req.body.reason || '').trim().slice(0, 200) : '';
      lock.lockedBy = locked ? actorName(req) : null;
      lock.lockedAt = locked ? new Date().toISOString() : null;
    } else if (locked && req.body.reason !== undefined) {
      lock.reason = String(req.body.reason || '').trim().slice(0, 200);
    }
  }
  raffle.salesLock = lock;
  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({
    id: `audit-${Date.now()}`, type: 'SALES_LOCK', companyId: raffle.companyId, targetId: raffle.id, targetName: raffle.title,
    detail: `Ventas de asesores ${lock.locked ? 'bloqueadas' : 'abiertas'}${lock.autoLockTime ? `; cierre automático ${lock.autoLockTime}` : ''}`,
    by: actorName(req), date: new Date().toISOString()
  });
  saveDB();
  res.json(salesLockView(raffle));
});

// One advisor: lock or unlock their sales in this raffle
app.put('/api/raffles/:id/sales-lock/advisors/:advisorId', adminOnly, (req, res) => {
  const raffle = lockedRaffle(req, res);
  if (!raffle) return;
  const advisor = (db.advisors || []).find(a => a.id === req.params.advisorId && a.companyId === raffle.companyId);
  if (!advisor) return res.status(404).json({ error: 'Asesor no encontrado.' });
  const lock = salesLockOf(raffle);
  const advisors = { ...lock.advisors };
  if (req.body.locked === true) {
    advisors[advisor.id] = { reason: String(req.body.reason || '').trim().slice(0, 200), by: actorName(req), at: new Date().toISOString() };
  } else {
    delete advisors[advisor.id];
  }
  raffle.salesLock = { ...lock, advisors };
  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({
    id: `audit-${Date.now()}`, type: 'SALES_LOCK', companyId: raffle.companyId, targetId: raffle.id, targetName: raffle.title,
    detail: `Ventas de ${advisor.name} ${req.body.locked === true ? 'bloqueadas' : 'desbloqueadas'}`,
    by: actorName(req), date: new Date().toISOString()
  });
  saveDB();
  res.json(salesLockView(raffle));
});

app.post('/api/raffles/:id/close', adminOnly, (req, res) => {
  const raffle = (db.raffles || []).find(r => r.id === req.params.id);
  if (!raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Rifa no encontrada.' });
  if (raffle.scheduledDeletionAt) return res.status(400).json({ error: 'La rifa ya está cerrada.' });
  const day = drawDayOf(raffle);
  if (day && day >= colombiaDay(Date.now())) {
    return res.status(400).json({ error: 'La rifa solo se puede cerrar después de la fecha del sorteo principal.' });
  }
  const now = Date.now();
  const drawMs = day ? Date.parse(day) : now;
  raffle.statusBeforeClose = raffle.status || 'ACTIVA';
  raffle.status = 'INACTIVA';
  raffle.closedAt = new Date(now).toISOString();
  raffle.closedBy = actorName(req);
  // Eliminación definitiva 45 días después del cierre (hasta entonces se puede consultar y descargar la información)
  raffle.scheduledDeletionAt = new Date(now + CLOSE_GRACE_DAYS * 86400000).toISOString();
  // Al cerrar la rifa se inhabilitan las ventas de todos los asesores
  lockAdvisorSales(raffle, actorName(req), 'Rifa cerrada');
  saveDB();
  res.json(raffle);
});

// Re-organiza al azar los números (oportunidades) de las boletas. Solo si TODAS siguen disponibles
// (ninguna vendida, apartada, con abonos ni comprador) y la boleta tiene 2 o más oportunidades.
app.post('/api/raffles/:id/reshuffle-numbers', adminOnly, (req, res) => {
  const raffle = (db.raffles || []).find(r => r.id === req.params.id);
  if (!raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Rifa no encontrada.' });
  if (raffle.scheduledDeletionAt) return res.status(400).json({ error: 'La rifa está cerrada.' });
  const tickets = (db.tickets || []).filter(t => t.raffleId === raffle.id);
  if (tickets.length === 0) return res.status(400).json({ error: 'La rifa no tiene boletas.' });
  const untouched = t => t.status === 'DISPONIBLE' && !t.buyerName && !t.buyerPhone && !(t.totalPaid > 0) && !(Array.isArray(t.abonos) && t.abonos.length);
  if (!tickets.every(untouched)) {
    return res.status(409).json({ error: 'Ya hay boletas vendidas, apartadas o con abonos. Solo se puede reorganizar mientras todas estén disponibles.' });
  }
  if (!tickets.some(t => Array.isArray(t.numbers) && t.numbers.length >= 2)) {
    return res.status(400).json({ error: 'La reorganización aplica solo cuando cada boleta tiene 2 o más oportunidades.' });
  }
  // Se reparte el mismo conjunto de números, en orden aleatorio (Fisher-Yates con crypto)
  const crypto = require('crypto');
  const pool = tickets.flatMap(t => t.numbers || []);
  for (let i = pool.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }
  let idx = 0;
  tickets.forEach(t => {
    const n = (t.numbers || []).length;
    t.numbers = pool.slice(idx, idx + n);
    idx += n;
  });
  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({
    id: `audit-${Date.now()}`, type: 'RESHUFFLE_NUMBERS', companyId: raffle.companyId, targetId: raffle.id, targetName: raffle.title,
    detail: `Números reorganizados al azar en ${tickets.length} boletas (todas disponibles)`,
    by: actorName(req), date: new Date().toISOString()
  });
  saveDB();
  res.json({ message: 'Números reorganizados al azar.', tickets: tickets.length });
});

app.post('/api/raffles/:id/reopen', adminOnly, (req, res) => {
  const raffle = (db.raffles || []).find(r => r.id === req.params.id);
  if (!raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Rifa no encontrada.' });
  if (!raffle.scheduledDeletionAt) return res.status(400).json({ error: 'La rifa no está cerrada.' });

  if (raffle.driveCleanedAt) {
    return res.status(400).json({ 
      error: 'No se puede reabrir esta rifa: ya pasaron más de 30 días desde el sorteo y sus soportes en Google Drive fueron eliminados.' 
    });
  }

  const targetCompany = (db.companies || []).find(c => c.id === raffle.companyId);
  const maxActive = targetCompany && typeof targetCompany.maxActiveRaffles === 'number' ? targetCompany.maxActiveRaffles : 0;
  if (maxActive > 0) {
    const activeCount = (db.raffles || []).filter(r => 
      r.companyId === raffle.companyId && 
      r.id !== raffle.id &&
      r.status === 'ACTIVA' && 
      !r.scheduledDeletionAt
    ).length;
    if (activeCount >= maxActive) {
      return res.status(403).json({ 
        error: `No se puede reabrir la rifa: ya tiene ${activeCount} rifa(s) activa(s), que es el límite asignado (${maxActive}).` 
      });
    }
  }

  raffle.status = raffle.statusBeforeClose || 'ACTIVA';
  delete raffle.closedAt;
  delete raffle.closedBy;
  delete raffle.scheduledDeletionAt;
  delete raffle.statusBeforeClose;
  applyReactivationLock(raffle, req);
  saveDB();
  res.json(raffle);
});

/** Deletes every record of a raffle (and its Drive folder, sent to the Drive trash). */
function purgeRaffle(raffle, reason) {
  const id = raffle.id;
  const counts = {
    tickets: (db.tickets || []).filter(t => t.raffleId === id).length,
    winners: (db.winners || []).filter(w => w.raffleId === id).length,
    deliveries: (db.cashDeliveries || []).filter(d => d.raffleId === id).length
  };
  db.raffles = (db.raffles || []).filter(r => r.id !== id);
  db.tickets = (db.tickets || []).filter(t => t.raffleId !== id);
  db.winners = (db.winners || []).filter(w => w.raffleId !== id);
  db.cashTransactions = (db.cashTransactions || []).filter(ct => ct.raffleId !== id);
  db.commissionPayouts = (db.commissionPayouts || []).filter(cp => cp.raffleId !== id);
  db.cashDeliveries = (db.cashDeliveries || []).filter(d => d.raffleId !== id);
  for (const type of Object.keys(raffle.templates || {})) {
    deleteTemplate(id, type).catch(err => console.error('⚠️ No se pudo borrar la plantilla:', err.message));
  }
  if (raffle.driveFolderId) {
    driveService.trashDriveFile(raffle.driveFolderId).catch(err => console.error('⚠️ No se pudo enviar a la papelera la carpeta de Drive:', err.message));
  }
  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({
    id: `audit-${Date.now()}-${id}`, type: 'PURGE_RAFFLE', targetId: id, targetName: raffle.title,
    companyId: raffle.companyId, reason, counts, closedAt: raffle.closedAt, closedBy: raffle.closedBy, date: new Date().toISOString()
  });
  console.log(`🗑️ Rifa "${raffle.title}" eliminada de la base de datos (${reason}): ${counts.tickets} boletas, ${counts.winners} sorteos.`);
}

let runningLifecycle = false;
async function checkRaffleLifecycle() {
  if (!isDbLoaded || runningLifecycle) return;
  runningLifecycle = true;
  const now = Date.now();
  let dbChanged = false;

  try {
    for (const raffle of (db.raffles || [])) {
      const day = drawDayOf(raffle);
      if (!day) continue;
      const drawMs = Date.parse(day);
      if (isNaN(drawMs)) continue;
      const daysSinceDraw = Math.floor((now - drawMs) / 86400000);

      // ETAPA 1: Pasados 45 días del sorteo -> Inhabilitar y eliminar soportes de Drive
      // (una rifa cerrada a mano conserva sus soportes hasta su fecha de eliminación: 45 días después del cierre)
      const waitingPurge = raffle.scheduledDeletionAt && Date.parse(raffle.scheduledDeletionAt) > now;
      if (daysSinceDraw >= DRIVE_CLEANUP_DAYS && !waitingPurge) {
        if (raffle.status !== 'INACTIVA') {
          raffle.statusBeforeClose = raffle.status || 'ACTIVA';
          raffle.status = 'INACTIVA';
          raffle.closedAt = raffle.closedAt || new Date(now).toISOString();
          raffle.closedBy = raffle.closedBy || 'Sistema (45 días cumplidos del sorteo)';
          lockAdvisorSales(raffle, 'Sistema', 'Rifa cerrada');
          dbChanged = true;
        }

        if (!raffle.driveCleanedAt) {
          if (raffle.driveFolderId) {
            try {
              await driveService.trashDriveFile(raffle.driveFolderId);
              console.log(`🧹 Carpeta de Drive enviada a papelera para rifa "${raffle.title}" tras 30 días del sorteo.`);
            } catch (err) {
              console.error(`⚠️ No se pudo enviar a la papelera la carpeta de Drive (${raffle.id}):`, err.message);
            }
            raffle.driveFolderId = null;
          }

          // Marcar tickets para liberar referencias a Drive
          const tickets = (db.tickets || []).filter(t => t.raffleId === raffle.id);
          for (const t of tickets) {
            if (t.paymentProofDriveId) {
              delete t.paymentProofDriveId;
              t.paymentProofArchived = true;
            }
            if (t.payments && Array.isArray(t.payments)) {
              for (const p of t.payments) {
                if (p.driveFileId) {
                  delete p.driveFileId;
                  p.archivedFromDrive = true;
                }
              }
            }
          }

          raffle.driveCleanedAt = new Date(now).toISOString();
          if (!raffle.scheduledDeletionAt) {
            raffle.scheduledDeletionAt = new Date(now + CLOSE_GRACE_DAYS * 86400000).toISOString();
          }
          dbChanged = true;

          if (!db.auditLogs) db.auditLogs = [];
          db.auditLogs.push({
            id: `audit-${now}-${raffle.id}`,
            type: 'DRIVE_CLEANUP_30_DAYS',
            companyId: raffle.companyId,
            targetId: raffle.id,
            targetName: raffle.title,
            detail: 'Rifa inhabilitada y soportes en Google Drive eliminados cumplidos 30 días del sorteo.',
            by: 'Sistema',
            date: new Date(now).toISOString()
          });
        }
      }
    }

    // ETAPA 2: Pasados 6 meses (180 días) del sorteo -> Eliminar de la base de datos
    const duePurge = (db.raffles || []).filter(r => {
      if (r.scheduledDeletionAt && Date.parse(r.scheduledDeletionAt) <= now) return true;
      const day = drawDayOf(r);
      if (!day) return false;
      const drawMs = Date.parse(day);
      return !isNaN(drawMs) && Math.floor((now - drawMs) / 86400000) >= DB_PURGE_DAYS;
    });

    if (duePurge.length > 0) {
      await createSnapshot('antes_de_eliminar_rifas_6_meses');
      for (const r of duePurge) {
        const current = (db.raffles || []).find(x => x.id === r.id);
        if (current) {
          purgeRaffle(current, 'Cumplidos 6 meses (180 días) desde la fecha del sorteo');
          dbChanged = true;
        }
      }
    }

    if (dbChanged) saveDB();
  } catch (err) {
    console.error('⚠️ Error en checkRaffleLifecycle:', err.message);
  } finally {
    runningLifecycle = false;
  }
}
setInterval(() => checkRaffleLifecycle().catch(() => {}), 60 * 60 * 1000);
setTimeout(() => checkRaffleLifecycle().catch(() => {}), 60 * 1000);

// Everything about a raffle in a ZIP: an Excel workbook and the payment / delivery proof images
app.get('/api/raffles/:id/export', adminOnly, async (req, res) => {
  const raffle = (db.raffles || []).find(r => r.id === req.params.id);
  if (!raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Rifa no encontrada.' });
  const ExcelJS = require('exceljs');
  const archiver = require('archiver');
  const tickets = (db.tickets || []).filter(t => t.raffleId === raffle.id).sort((a, b) => (a.ticketNumber || 0) - (b.ticketNumber || 0));
  const winners = (db.winners || []).filter(w => w.raffleId === raffle.id);
  const deliveries = (db.cashDeliveries || []).filter(d => d.raffleId === raffle.id);
  const company = (db.companies || []).find(c => c.id === raffle.companyId) || {};
  const nums = t => (t.numbers || []).join('-') || String(t.ticketNumber);
  const day = v => (v ? (/^\d{4}-\d{2}-\d{2}$/.test(v) ? v : colombiaDay(Date.parse(v))) : '');
  const safe = v => String(v || '').replace(/[^\w\-]+/g, '_').slice(0, 60);
  const proofs = []; // { name, driveId }

  const wb = new ExcelJS.Workbook();
  wb.creator = 'RifaMaster';
  const sheet = (name, columns, rows) => {
    const ws = wb.addWorksheet(name);
    ws.columns = columns.map(([header, key, width]) => ({ header, key, width: width || 16 }));
    ws.getRow(1).font = { bold: true };
    ws.views = [{ state: 'frozen', ySplit: 1 }];
    rows.forEach(r => ws.addRow(r));
  };
  const sold = tickets.filter(t => t.status !== 'DISPONIBLE');
  sheet('Resumen', [['Dato', 'k', 30], ['Valor', 'v', 50]], [
    { k: 'Empresa', v: company.name }, { k: 'Rifa', v: raffle.title }, { k: 'Descripción', v: raffle.description },
    { k: 'Fecha sorteo principal', v: day(raffle.mainDrawDate) }, { k: 'Lotería', v: mainLotteryOf(raffle) },
    { k: 'Gana con', v: winningRuleText(raffle) }, { k: 'Valor boleta', v: raffle.ticketPrice }, { k: 'Total boletas', v: tickets.length },
    { k: 'Boletas vendidas', v: sold.length }, { k: 'Total recaudado', v: sold.reduce((s, t) => s + (t.totalPaid || 0), 0) },
    { k: 'Cerrada', v: raffle.closedAt ? `${day(raffle.closedAt)} por ${raffle.closedBy}` : 'No' },
    { k: 'Eliminación programada', v: raffle.scheduledDeletionAt ? day(raffle.scheduledDeletionAt) : '' },
    { k: 'Generado', v: new Date().toLocaleString('es-CO', { timeZone: 'America/Bogota' }) }
  ]);
  sheet('Boletas', [['N° boleta', 'n', 18], ['Estado', 'st'], ['Comprador', 'b', 28], ['Teléfono', 'p'], ['Cédula', 'd'], ['Asesor', 'a', 24],
    ['Medio de venta', 'ch'], ['Valor', 'price'], ['Pagado', 'paid'], ['Saldo', 'bal'], ['Confirmada en caja', 'conf'], ['Fecha venta', 'date'], ['Código verificación', 'code', 18]],
  tickets.map(t => ({ n: nums(t), st: t.status, b: t.buyerName, p: t.buyerPhone, d: t.buyerDocument, a: t.advisorName, ch: t.saleChannel,
    price: t.price, paid: t.totalPaid || 0, bal: Math.max(0, (t.price || 0) - (t.totalPaid || 0)), conf: t.confirmedByAdmin ? 'Sí' : 'No',
    date: day(t.assignedDate), code: ticketVerificationCode(t) || '' })));
  const abonoRows = [];
  for (const t of tickets) for (const a of t.abonos || []) {
    let proof = '';
    if (a.soporteDriveId) { proof = `soportes/abonos/${safe(nums(t))}_${safe(a.id)}.jpg`; proofs.push({ name: proof, driveId: a.soporteDriveId }); }
    abonoRows.push({ n: nums(t), b: t.buyerName, date: day(a.date), amount: a.amount, m: a.metodoPago || 'efectivo', by: a.sellerName, note: a.note,
      td: day(a.transferDate), ob: a.originBank, ap: a.approvalNumber, dest: a.cuentaDestino, state: (a.amount || 0) > 0 ? abonoCashState(a) : '', proof });
  }
  sheet('Abonos', [['N° boleta', 'n', 18], ['Comprador', 'b', 26], ['Fecha', 'date'], ['Valor', 'amount'], ['Método', 'm'], ['Registró', 'by', 22], ['Nota', 'note', 26],
    ['Fecha transferencia', 'td'], ['Banco origen', 'ob'], ['N° aprobación', 'ap'], ['Cuenta destino', 'dest', 30], ['Estado en caja', 'state'], ['Soporte', 'proof', 36]], abonoRows);
  const voided = [];
  for (const t of tickets) {
    for (const a of t.voidedAbonos || []) voided.push({ kind: 'Abono anulado', n: nums(t), b: a.buyerName || t.buyerName, amount: a.amount, date: day(a.voidedAt), by: a.voidedBy, reason: a.voidReason });
    for (const an of t.annulments || []) voided.push({ kind: 'Venta anulada', n: nums(t), b: (an.previous || {}).buyerName, amount: (an.previous || {}).totalPaid, date: day(an.date), by: an.by, reason: an.reason });
  }
  sheet('Anulaciones', [['Tipo', 'kind'], ['N° boleta', 'n', 18], ['Comprador', 'b', 26], ['Valor', 'amount'], ['Fecha', 'date'], ['Anuló', 'by', 22], ['Motivo', 'reason', 40]], voided);
  sheet('Ganadores', [['Sorteo', 'name', 24], ['Fecha', 'date'], ['Resultado', 'res'], ['Número', 'num'], ['Ganador', 'w', 26], ['Premio', 'prize', 30], ['Valor', 'amount'],
    ['Sin ganador', 'nw', 30], ['Decisión', 'dec', 26], ['Entregado a', 'to', 26], ['Fecha entrega', 'dd']],
  winners.map(w => ({ name: w.drawName, date: day(w.drawDate), res: w.lotteryResult, num: w.winningNumber, w: w.isWinner && w.winnerDetails ? w.winnerDetails.buyerName : '',
    prize: w.prizeDescription || '', amount: w.totalPrizePaid, nw: w.isWinner ? '' : (w.noWinnerReason || (w.accumulated ? 'Acumulado' : '')),
    dec: w.decision ? `${w.decision.type}${w.decision.newDate ? ' ' + w.decision.newDate : ''} ${w.decision.note || ''}` : '',
    to: w.prizeDelivery ? `${w.prizeDelivery.receivedBy} ${w.prizeDelivery.receivedDocument || ''}` : '', dd: w.prizeDelivery ? w.prizeDelivery.deliveredOn : '' })));
  sheet('Entregas caja', [['Asesor', 'a', 24], ['Reportada', 'date'], ['Método', 'm'], ['Total', 'total'], ['Boletas', 'items', 40], ['Estado', 'st'], ['Revisó', 'rev', 22],
    ['Fecha transferencia', 'td'], ['Banco', 'ob'], ['N° aprobación', 'ap'], ['Soporte', 'proof', 36]],
  deliveries.map(d => {
    let proof = '';
    if (d.soporteDriveId) { proof = `soportes/entregas/${safe(d.advisorName)}_${safe(d.id)}.jpg`; proofs.push({ name: proof, driveId: d.soporteDriveId }); }
    return { a: d.advisorName, date: day(d.reportedAt), m: d.method, total: d.total, items: d.items.map(i => (i.numbers || []).join('-')).join(', '),
      st: d.status, rev: d.reviewedBy || '', td: d.transferDate || '', ob: d.originBank || '', ap: d.approvalNumber || '', proof };
  }));

  const filename = `rifa_${safe(raffle.title)}_${colombiaDay(Date.now())}.zip`;
  res.setHeader('Content-Type', 'application/zip');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  const zip = archiver('zip', { zlib: { level: 6 } });
  zip.on('error', err => { console.error('⚠️ Error creando el ZIP:', err.message); res.destroy(err); });
  zip.pipe(res);
  zip.append(await wb.xlsx.writeBuffer(), { name: `${safe(raffle.title)}.xlsx` });
  const missing = [];
  for (const p of proofs) {
    try {
      const file = await driveService.downloadDriveFile(p.driveId);
      zip.append(file.buffer, { name: p.name });
    } catch (err) {
      missing.push(`${p.name}: ${err.message}`);
    }
  }
  if (missing.length) zip.append(`No se pudieron descargar estos soportes de Google Drive:\n${missing.join('\n')}\n`, { name: 'soportes_faltantes.txt' });
  await zip.finalize();
});

// ---------------------------------------------------------------------------
// GOOGLE DRIVE INTEGRATION ENDPOINTS (Afiche 2D, Fondo Boleta, Soportes)
// ---------------------------------------------------------------------------

app.get('/api/drive/status', async (req, res) => {
  try {
    const status = await driveService.testDriveConnection();
    res.json({ success: true, status });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST Subir / Reemplazar Afiche 2D
app.post('/api/raffles/:id/afiche', adminOnly, async (req, res) => {
  try {
    const { id } = req.params;
    const { imageBase64, mimeType = 'image/jpeg' } = req.body;

    if (!imageBase64) {
      return res.status(400).json({ error: 'Debes proporcionar la imagen en formato Base64 (imageBase64).' });
    }

    const raffle = db.raffles.find(r => r.id === id);
    if (!raffle) {
      return res.status(404).json({ error: 'Rifa no encontrada' });
    }

    // 1. Obtener carpetas de la empresa y rifa en Drive
    const company = (db.companies || []).find(c => c.id === raffle.companyId);
    const companyName = company ? (company.name || company.companyName || 'Empresa') : 'Empresa General';
    const folders = await driveService.getRaffleFolders(companyName, raffle.companyId, raffle.title, raffle.id, raffle.driveFolderId);
    raffle.driveFolderId = folders.raffleFolderId;

    // 2. Eliminar afiche viejo de Drive si existía
    if (raffle.aficheDriveId) {
      await driveService.deleteFileFromDrive(raffle.aficheDriveId);
    }

    // 3. Convertir base64 a Buffer
    const cleanBase64 = imageBase64.replace(/^data:image\/\w+;base64,/, '');
    const buffer = Buffer.from(cleanBase64, 'base64');

    // 4. Subir nuevo archivo a subcarpeta Afiche_2D
    const filename = `afiche_${raffle.id}_${Date.now()}.jpg`;
    const uploadRes = await driveService.uploadFileToDrive({
      buffer,
      filename,
      mimeType,
      parentFolderId: folders.aficheFolderId
    });

    // 5. Actualizar la rifa en BD
    raffle.aficheUrl = uploadRes.directUrl;
    raffle.aficheDriveId = uploadRes.fileId;
    raffle.aficheWebViewUrl = uploadRes.webViewUrl;

    saveDB();

    res.json({
      message: 'Afiche 2D subido y reemplazado exitosamente en Google Drive.',
      aficheUrl: uploadRes.directUrl,
      aficheDriveId: uploadRes.fileId,
      aficheWebViewUrl: uploadRes.webViewUrl,
      raffle
    });
  } catch (error) {
    console.error('⚠️ Error al subir afiche a Google Drive:', error);
    res.status(500).json({ error: `Error al subir afiche: ${error.message}` });
  }
});

// DELETE Eliminar Afiche 2D
app.delete('/api/raffles/:id/afiche', adminOnly, async (req, res) => {
  try {
    const { id } = req.params;
    const raffle = db.raffles.find(r => r.id === id);
    if (!raffle) return res.status(404).json({ error: 'Rifa no encontrada' });

    if (raffle.aficheDriveId) {
      await driveService.deleteFileFromDrive(raffle.aficheDriveId);
    }
    raffle.aficheUrl = null;
    raffle.aficheDriveId = null;
    raffle.aficheWebViewUrl = null;
    saveDB();
    res.json({ message: 'Afiche eliminado exitosamente.', raffle });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// POST Subir / Reemplazar Fondo de Boleta (Diseño general de impresión)
app.post('/api/raffles/:id/fondo-boleta', adminOnly, async (req, res) => {
  try {
    const { id } = req.params;
    const { imageBase64, mimeType = 'image/jpeg' } = req.body;

    if (!imageBase64) {
      return res.status(400).json({ error: 'Debes proporcionar la imagen en formato Base64 (imageBase64).' });
    }

    const raffle = db.raffles.find(r => r.id === id);
    if (!raffle) {
      return res.status(404).json({ error: 'Rifa no encontrada' });
    }

    // 1. Obtener carpetas de la empresa y rifa en Drive
    const company = (db.companies || []).find(c => c.id === raffle.companyId);
    const companyName = company ? (company.name || company.companyName || 'Empresa') : 'Empresa General';
    const folders = await driveService.getRaffleFolders(companyName, raffle.companyId, raffle.title, raffle.id, raffle.driveFolderId);
    raffle.driveFolderId = folders.raffleFolderId;

    // 2. Eliminar fondo de boleta viejo de Drive si existía
    if (raffle.fondoBoletaDriveId) {
      await driveService.deleteFileFromDrive(raffle.fondoBoletaDriveId);
    }

    // 3. Convertir base64 a Buffer
    const cleanBase64 = imageBase64.replace(/^data:image\/\w+;base64,/, '');
    const buffer = Buffer.from(cleanBase64, 'base64');

    // 4. Subir nuevo archivo a subcarpeta Fondo_Boleta
    const filename = `fondo_boleta_${raffle.id}_${Date.now()}.jpg`;
    const uploadRes = await driveService.uploadFileToDrive({
      buffer,
      filename,
      mimeType,
      parentFolderId: folders.fondoBoletaFolderId
    });

    // 5. Actualizar la rifa en BD
    raffle.fondoBoletaUrl = uploadRes.directUrl;
    raffle.fondoBoletaDriveId = uploadRes.fileId;
    raffle.fondoBoletaWebViewUrl = uploadRes.webViewUrl;

    saveDB();

    res.json({
      message: 'Fondo de boleta subido y reemplazado exitosamente en Google Drive.',
      fondoBoletaUrl: uploadRes.directUrl,
      fondoBoletaDriveId: uploadRes.fileId,
      fondoBoletaWebViewUrl: uploadRes.webViewUrl,
      raffle
    });
  } catch (error) {
    console.error('⚠️ Error al subir fondo de boleta a Google Drive:', error);
    res.status(500).json({ error: `Error al subir fondo de boleta: ${error.message}` });
  }
});

// POST Subir Foto o Video del Premio a Google Drive (Galería)
app.post('/api/raffles/:id/prize-media', adminOnly, async (req, res) => {
  try {
    const { id } = req.params;
    const { mediaBase64, filename = 'premio', mimeType = 'image/jpeg' } = req.body;

    if (!mediaBase64) {
      return res.status(400).json({ error: 'Debes proporcionar el archivo en Base64 (mediaBase64).' });
    }

    const raffle = db.raffles.find(r => r.id === id);
    if (!raffle) {
      return res.status(404).json({ error: 'Rifa no encontrada' });
    }

    const company = (db.companies || []).find(c => c.id === raffle.companyId);
    const companyName = company ? (company.name || company.companyName || 'Empresa') : 'Empresa General';
    const folders = await driveService.getRaffleFolders(companyName, raffle.companyId, raffle.title, raffle.id, raffle.driveFolderId);
    raffle.driveFolderId = folders.raffleFolderId;

    const cleanBase64 = mediaBase64.replace(/^data:[^;]+;base64,/, '');
    const buffer = Buffer.from(cleanBase64, 'base64');

    const ext = mimeType.includes('video') ? (mimeType.includes('quicktime') ? 'mov' : 'mp4') : (mimeType.includes('png') ? 'png' : 'jpg');
    const safeFilename = `premio_${raffle.id}_${Date.now()}.${ext}`;

    const uploadRes = await driveService.uploadFileToDrive({
      buffer,
      filename: safeFilename,
      mimeType,
      parentFolderId: folders.galeriaFolderId || folders.raffleFolderId
    });

    raffle.prizeImages = raffle.prizeImages || [];
    if (!raffle.prizeImages.includes(uploadRes.directUrl)) {
      raffle.prizeImages.push(uploadRes.directUrl);
    }

    saveDB();
    notifyRaffleChanged(raffle.id);

    res.json({
      message: 'Foto o video subido exitosamente a Google Drive.',
      url: uploadRes.directUrl,
      webViewUrl: uploadRes.webViewUrl,
      fileId: uploadRes.fileId,
      mimeType,
      prizeImages: raffle.prizeImages,
      raffle
    });
  } catch (error) {
    console.error('⚠️ Error al subir foto/video a Google Drive:', error);
    res.status(500).json({ error: `Error al subir archivo a Drive: ${error.message}` });
  }
});

// DELETE Eliminar Fondo de Boleta
app.delete('/api/raffles/:id/fondo-boleta', adminOnly, async (req, res) => {
  try {
    const { id } = req.params;
    const raffle = db.raffles.find(r => r.id === id);
    if (!raffle) return res.status(404).json({ error: 'Rifa no encontrada' });

    if (raffle.fondoBoletaDriveId) {
      await driveService.deleteFileFromDrive(raffle.fondoBoletaDriveId);
    }
    raffle.fondoBoletaUrl = null;
    raffle.fondoBoletaDriveId = null;
    raffle.fondoBoletaWebViewUrl = null;
    saveDB();
    res.json({ message: 'Fondo de boleta eliminado exitosamente.', raffle });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// POST Create Raffle
app.post('/api/raffles', adminOnly, (req, res) => {
  const { title, description, mainDrawDate, weeklyPrizesStartDate, digits, totalTickets, ticketPrice, weeklyPrizes, generationMode, customNumbers, preSoldTickets, commissionType, commissionValue, companyId } = req.body;
  
  const numDigits = parseInt(digits) || 4;
  const numTickets = parseInt(totalTickets) || 2500;
  const totalNumbers = Math.pow(10, numDigits); // 10^4 = 10000
  const opps = Math.floor(totalNumbers / numTickets); // e.g. 10000 / 2500 = 4

  const targetCompanyId = req.auth && req.auth.role === 'admin' ? req.auth.record.id : (companyId || 'comp-1');

  // Validar cupo de rifas contratadas (0 = ilimitadas / suscripción mensual; > 0 = cupo total contratado)
  const targetCompany = (db.companies || []).find(c => c.id === targetCompanyId);
  const maxAllowed = targetCompany && typeof targetCompany.maxActiveRaffles === 'number' ? targetCompany.maxActiveRaffles : 0;
  if (maxAllowed > 0) {
    const existingCount = (db.raffles || []).filter(r => r.companyId === targetCompanyId).length;
    const currentUsed = Math.max(targetCompany.rafflesCreatedCount || 0, existingCount);
    if (currentUsed >= maxAllowed) {
      return res.status(403).json({ 
        error: `Ha alcanzado el cupo total de ${maxAllowed} rifa(s) contratadas. En la modalidad de pago por rifa, así la rifa anterior se haya cerrado o eliminado, para crear una nueva rifa debe solicitar una recarga de cupo al SuperAdmin o cambiar a suscripción mensual.` 
      });
    }
  }

  const companyAdvisors = (db.advisors || []).filter(a => (!a.companyId || a.companyId === targetCompanyId) && a.status === 'ACTIVO').map(a => a.id);
  const requestedAdvisors = Array.isArray(req.body.assignedAdvisorIds) ? req.body.assignedAdvisorIds.filter(advisorId => advisorBelongsToCompany(advisorId, targetCompanyId)) : [];
  const selectedAdvisors = requestedAdvisors.length > 0 ? requestedAdvisors : companyAdvisors;

  const newRaffle = {
    id: `raf-${Date.now()}`,
    companyId: targetCompanyId,
    title: title || 'Nuevo Sorteo',
    description: description || '',
    mainDrawDate: mainDrawDate || new Date(Date.now() + 90*86400000).toISOString(),
    weeklyPrizesStartDate: weeklyPrizesStartDate || new Date().toISOString(),
    digits: numDigits,
    totalTickets: numTickets,
    totalNumbers,
    opportunitiesPerTicket: opps,
    ticketPrice: parseFloat(ticketPrice) || 50000,
    weeklyPrizes: weeklyPrizes || [],
    assignedAdvisorIds: selectedAdvisors,
    commissionType: commissionType || 'PORCENTAJE',
    commissionValue: parseFloat(commissionValue) || 10,
    commissionTiers: Array.isArray(req.body.commissionTiers) ? req.body.commissionTiers : [],
    // Which lottery digits decide the winner, and whether "combinado" (any order) also wins
    winningDigitsPosition: 'ULTIMAS',
    allowCombined: false,
    ...normalizeWinningConfig(req.body, numDigits),
    // Accounts where buyers pay by bank transfer
    transferAccounts: [],
    ownerName: req.body.ownerName ? String(req.body.ownerName).trim() : '',
    isIndependentBook: !!req.body.isIndependentBook || (targetCompany && !!targetCompany.isIndependent),
    status: 'ACTIVA',
    createdAt: new Date().toISOString()
  };

  if (req.body.transferAccounts !== undefined) {
    const checked = normalizeTransferAccounts(req.body.transferAccounts);
    if (checked.error) return res.status(400).json({ error: checked.error });
    newRaffle.transferAccounts = checked.accounts;
  }
  for (const [field, label] of [['mainLotteryName', 'lotería del sorteo principal'], ['lotteryName', 'lotería de los sorteos semanales']]) {
    if (req.body[field] === undefined || String(req.body[field]).trim() === '') continue;
    const checked = checkRaffleLottery(req.body[field], null, label);
    if (checked.error) return res.status(400).json({ error: checked.error });
    newRaffle[field] = checked.name;
  }

  db.raffles.unshift(newRaffle);
  if (targetCompany) {
    const existingCount = (db.raffles || []).filter(r => r.companyId === targetCompanyId).length;
    targetCompany.rafflesCreatedCount = Math.max((targetCompany.rafflesCreatedCount || 0) + 1, existingCount);
  }

  const isInd = !!req.body.isIndependentBook || (targetCompany && !!targetCompany.isIndependent);
  const customTicketsList = Array.isArray(req.body.customTicketsList) ? req.body.customTicketsList : null;
  let effectiveNumTickets = numTickets;

  // Prepare series numbers based on generationMode or independent ticket list
  let allSeries = [];
  const mode = generationMode || 'SECUENCIAL';

  if (isInd && customTicketsList && customTicketsList.length > 0) {
    effectiveNumTickets = customTicketsList.length;
    newRaffle.totalTickets = effectiveNumTickets;
    newRaffle.isIndependentBook = true;
    allSeries = customTicketsList.map(item => Array.isArray(item) ? item.map(n => String(n).trim()) : [String(item).trim()]);
    const firstTicketSeries = allSeries[0] || [];
    newRaffle.opportunitiesPerTicket = parseInt(req.body.opportunitiesPerTicket) || firstTicketSeries.length || 1;
    newRaffle.totalNumbers = allSeries.reduce((acc, curr) => acc + curr.length, 0);
  } else if (mode === 'ALEATORIO') {
    // Generate pool 0..totalNumbers-1, shuffle and chunk
    const pool = Array.from({ length: totalNumbers }, (_, i) => i);
    for (let i = pool.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [pool[i], pool[j]] = [pool[j], pool[i]];
    }

    for (let i = 0; i < effectiveNumTickets; i++) {
      const tktNumbers = [];
      for (let k = 0; k < opps; k++) {
        const idx = i * opps + k;
        if (idx < pool.length) {
          tktNumbers.push(pool[idx].toString().padStart(numDigits, '0'));
        }
      }
      allSeries.push(tktNumbers);
    }
  } else if (mode === 'EXCEL' && customNumbers && typeof customNumbers === 'object') {
    for (let i = 1; i <= effectiveNumTickets; i++) {
      if (customNumbers[i] && Array.isArray(customNumbers[i])) {
        allSeries.push(customNumbers[i].map(n => n.toString().padStart(numDigits, '0')));
      } else {
        const series = [];
        for (let k = 0; k < opps; k++) {
          const numVal = (i - 1) + (k * effectiveNumTickets);
          series.push(numVal.toString().padStart(numDigits, '0'));
        }
        allSeries.push(series);
      }
    }
  } else {
    // SECUENCIAL
    for (let i = 1; i <= effectiveNumTickets; i++) {
      const series = [];
      for (let k = 0; k < opps; k++) {
        const numVal = (i - 1) + (k * effectiveNumTickets);
        series.push(numVal.toString().padStart(numDigits, '0'));
      }
      allSeries.push(series);
    }
  }

  // Pre-sold tickets lookup
  const preSoldMap = {};
  if (Array.isArray(preSoldTickets)) {
    preSoldTickets.forEach(rec => {
      if (rec.ticketNumber) {
        preSoldMap[rec.ticketNumber] = rec;
      }
    });
  }

  // Generate Tickets for this raffle
  for (let i = 1; i <= effectiveNumTickets; i++) {
    const series = allSeries[i - 1] || [];
    let status = 'DISPONIBLE';
    let buyerName = '';
    let buyerPhone = '';
    let advisorName = '';
    let advisorId = '';
    let totalPaid = 0;
    let abonos = [];

    if (preSoldMap[i]) {
      const rec = preSoldMap[i];
      status = rec.status || 'RESERVADA';
      buyerName = rec.buyerName || '';
      buyerPhone = rec.buyerPhone || '';
      advisorName = rec.sellerName || '';
      advisorId = rec.sellerCode || 'ADV01';
      totalPaid = parseFloat(rec.amountPaid) || 0;
      if (totalPaid > 0) {
        abonos.push({
          id: `ab-${Date.now()}-${i}`,
          amount: totalPaid,
          date: new Date().toISOString(),
          sellerId: advisorId,
          sellerName: advisorName || 'Asesor',
          note: rec.note || 'Importación Inicial CSV'
        });
      }
    }

    db.tickets.push({
      id: `tkt-${newRaffle.id}-${i}`,
      raffleId: newRaffle.id,
      ticketNumber: i,
      numbers: series,
      price: newRaffle.ticketPrice,
      status: status,
      advisorId: advisorId,
      advisorName: advisorName,
      buyerName: buyerName,
      buyerPhone: buyerPhone,
      totalPaid: totalPaid,
      balancePending: newRaffle.ticketPrice - totalPaid,
      confirmedByAdmin: false,
      assignedDate: status !== 'DISPONIBLE' ? new Date().toISOString() : null,
      abonos: abonos
    });
  }

  saveDB();
  res.status(201).json(newRaffle);
});

// POST Bulk Import Tickets
app.post('/api/tickets/import', adminOnly, (req, res) => {
  const { raffleId, records } = req.body;
  if (!raffleId || !Array.isArray(records)) {
    return res.status(400).json({ error: 'Datos de importación inválidos' });
  }

  const importRaffle = (db.raffles || []).find(r => r.id === raffleId);
  if (!importRaffle || !canAccessRaffle(req, importRaffle)) return res.status(404).json({ error: 'Rifa no encontrada' });

  let importedCount = 0;
  records.forEach(rec => {
    const ticket = db.tickets.find(t => t.raffleId === raffleId && t.ticketNumber === parseInt(rec.ticketNumber));
    if (ticket) {
      ticket.buyerName = rec.buyerName || ticket.buyerName;
      ticket.buyerPhone = rec.buyerPhone || ticket.buyerPhone;
      ticket.status = rec.status || ticket.status || 'RESERVADA';
      // El vendedor solo se asigna si es un asesor de la misma empresa de la rifa
      const importSeller = rec.sellerCode ? (db.advisors || []).find(a => a.id === rec.sellerCode || a.code === rec.sellerCode) : null;
      if (!importSeller || !importRaffle.companyId || importSeller.companyId === importRaffle.companyId) {
        ticket.advisorName = rec.sellerName || ticket.advisorName;
        ticket.advisorId = (importSeller ? importSeller.id : rec.sellerCode) || ticket.advisorId;
      }
      
      const amt = parseFloat(rec.amountPaid) || 0;
      if (amt > 0) {
        ticket.totalPaid += amt;
        ticket.balancePending = Math.max(0, ticket.price - ticket.totalPaid);
        ticket.abonos.push({
          id: `ab-${Date.now()}-${importedCount}`,
          amount: amt,
          date: new Date().toISOString(),
          sellerId: ticket.advisorId || 'ADV01',
          sellerName: ticket.advisorName || 'Asesor',
          note: rec.note || 'Abono Importado CSV'
        });
      }
      importedCount++;
    }
  });

  saveDB();
  notifyRaffleChanged(id);
  res.json({ message: `${importedCount} boletas importadas correctamente`, count: importedCount });
});

// ---------------------------------------------------------------------------
// REAL-TIME CONCURRENCY SYSTEM FOR 100+ ADVISORS
// ---------------------------------------------------------------------------
const raffleRevisions = {};

function notifyRaffleChanged(raffleId) {
  if (!raffleId) return;
  raffleRevisions[raffleId] = (raffleRevisions[raffleId] || 1) + 1;
}

function getRaffleRevision(raffleId) {
  return raffleRevisions[raffleId] || 1;
}

// Ultra-fast lightweight revision endpoint: allows 100+ advisors to poll every 3s with <1ms overhead
app.get('/api/raffles/:id/revision', (req, res) => {
  const { id } = req.params;
  res.json({
    raffleId: id,
    revision: getRaffleRevision(id),
    timestamp: Date.now()
  });
});

// GET Tickets (with multi-tenant isolation)
// Lista de boletas ya serializada (≈1,6 MB para 5000 boletas): varios equipos piden la misma lista casi al mismo tiempo
// cuando alguien vende. Se reutiliza mientras no haya cambios guardados (y como máximo 5 s) para no recalcularla para cada uno.
const ticketListCache = new Map();

app.get('/api/tickets', (req, res) => {
  const { raffleId, advisorId, status, search, numberSearch, companyId } = req.query;
  if (raffleId) {
    res.setHeader('X-Raffle-Revision', String(getRaffleRevision(raffleId)));
  }
  const cacheKey = `${req.auth ? req.auth.role + ':' + (req.auth.record.id || '') : ''}|${req.originalUrl}`;
  const hit = ticketListCache.get(cacheKey);
  if (hit && hit.version === dbVersion && Date.now() - hit.at < 5000) {
    return res.type('application/json').send(hit.body);
  }
  
  let targetCompanyId = companyId;
  if (!targetCompanyId && req.auth) {
    if (req.auth.role === 'admin') targetCompanyId = req.auth.record.id;
    if (req.auth.role === 'asesor') targetCompanyId = req.auth.record.companyId;
  }

  let result = db.tickets || [];

  if (targetCompanyId) {
    const companyRaffleIds = new Set((db.raffles || []).filter(r => !r.companyId || r.companyId === targetCompanyId).map(r => r.id));
    result = result.filter(t => companyRaffleIds.has(t.raffleId));
  }

  if (raffleId) {
    result = result.filter(t => t.raffleId === raffleId);
  }

  // Restricción para asesores: si el administrador le quitó el check en una rifa,
  // no podrá ver números disponibles (DISPONIBLE), solo lo que ya vendió.
  if (req.auth && req.auth.role === 'asesor' && !isTicketAssistant(advisorRecordOf(req))) {
    const myAdvId = req.auth.record.id;
    const authorizedByRaffle = new Map((db.raffles || []).map(r => [r.id, !r.assignedAdvisorIds || r.assignedAdvisorIds.length === 0 || r.assignedAdvisorIds.includes(myAdvId)]));
    result = result.filter(t => {
      if (authorizedByRaffle.get(t.raffleId)) return true;
      return t.advisorId === myAdvId || (t.abonos && t.abonos.some(a => a.sellerId === myAdvId));
    });
  }

  if (advisorId) {
    result = result.filter(t => t.advisorId === advisorId);
  }

  if (status) {
    result = result.filter(t => t.status === status);
  }

  if (numberSearch) {
    const target = numberSearch.toString().trim();
    result = result.filter(t => 
      t.ticketNumber.toString() === target || 
      t.numbers.some(n => n.includes(target))
    );
  }

  if (search) {
    const q = search.toLowerCase();
    result = result.filter(t => 
      t.ticketNumber.toString().includes(q) ||
      t.buyerName.toLowerCase().includes(q) ||
      t.buyerPhone.includes(q) ||
      (t.buyerDocument || '').includes(q) ||
      t.numbers.some(n => n.includes(q))
    );
  }

  // Asesor asignado por rango de números: solo se MUESTRA en la respuesta (nunca se guarda en la boleta) y solo con
  // asesores de la MISMA empresa que la rifa. Antes se guardaba en la boleta y, sin empresa en la consulta
  // (SuperAdmin), usaba asesores de todas las empresas: los números de un asesor quedaban marcados en otra empresa.
  const rangeAdvisorsByCompany = new Map();
  for (const a of db.advisors || []) {
    if (a.status !== 'ACTIVO' || a.mode !== 'ASSIGNED' || !a.companyId || !Array.isArray(a.assignedTicketRanges) || a.assignedTicketRanges.length === 0) continue;
    if (!rangeAdvisorsByCompany.has(a.companyId)) rangeAdvisorsByCompany.set(a.companyId, []);
    rangeAdvisorsByCompany.get(a.companyId).push(a);
  }
  if (rangeAdvisorsByCompany.size > 0) {
    const raffleById = new Map((db.raffles || []).map(r => [r.id, r]));
    result = result.map(t => {
      if (t.advisorId && t.advisorName) return t;
      const tr = raffleById.get(t.raffleId);
      // Solo las rifas independientes reparten números por rangos
      if (!tr || !tr.isIndependentBook) return t;
      const candidates = rangeAdvisorsByCompany.get(tr.companyId);
      const matchingAdv = candidates && candidates.find(a => ticketInAdvisorRanges(t, a, tr));
      return matchingAdv ? { ...t, advisorId: matchingAdv.id, advisorName: matchingAdv.name } : t;
    });
  }

  const body = JSON.stringify(result.map(withVerification));
  if (ticketListCache.size > 30) ticketListCache.clear();
  ticketListCache.set(cacheKey, { version: dbVersion, at: Date.now(), body });
  res.type('application/json').send(body);
});

// POST Register Ticket Sale or Abono
// Sale / contact channels are master data managed by the SuperAdmin (db.saleChannels).
// Channels are never deleted (sold tickets keep referencing them); they are deactivated instead.
const DEFAULT_SALE_CHANNELS = [
  { name: 'Facebook', color: '#1877F2', icon: 'facebook' },
  { name: 'WhatsApp', color: '#25D366', icon: 'chat' },
  { name: 'Familiar', color: '#EC4899', icon: 'family' },
  { name: 'Conocido', color: '#8B5CF6', icon: 'handshake' },
  { name: 'Voz a voz', color: '#F59E0B', icon: 'voice' },
  { name: 'Otro', color: '#64748B', icon: 'more' }
];
const CHANNEL_ICONS = ['facebook', 'chat', 'family', 'handshake', 'voice', 'instagram', 'tiktok', 'phone', 'store', 'email', 'web', 'more'];

function ensureSaleChannels(target) {
  if (Array.isArray(target.saleChannels) && target.saleChannels.length) return false;
  const now = new Date().toISOString();
  target.saleChannels = DEFAULT_SALE_CHANNELS.map((c, i) => ({ id: `ch-${i + 1}`, ...c, active: true, order: i, createdAt: now }));
  return true;
}

function isActiveSaleChannel(name) {
  return (db.saleChannels || []).some(c => c.active && c.name === name);
}

function validateChannelInput(body, currentId) {
  const name = typeof body.name === 'string' ? body.name.trim() : undefined;
  if (name !== undefined) {
    if (name.length < 2 || name.length > 30) return 'El nombre debe tener entre 2 y 30 caracteres.';
    const taken = (db.saleChannels || []).some(c => c.id !== currentId && c.name.toLowerCase() === name.toLowerCase());
    if (taken) return 'Ya existe un medio de venta con ese nombre.';
  }
  if (body.color !== undefined && !/^#[0-9A-Fa-f]{6}$/.test(String(body.color))) return 'Color no válido (use #RRGGBB).';
  if (body.icon !== undefined && !CHANNEL_ICONS.includes(body.icon)) return 'Ícono no válido.';
  return null;
}

app.get('/api/sale-channels', (req, res) => {
  if (ensureSaleChannels(db)) saveDB();
  const all = [...(db.saleChannels || [])].sort((a, b) => (a.order || 0) - (b.order || 0));
  // Everyone gets the active ones; the SuperAdmin also sees inactive ones to manage them
  res.json(req.auth.role === 'superadmin' ? all : all.filter(c => c.active));
});

app.post('/api/sale-channels', superAdminOnly, (req, res) => {
  const body = req.body || {};
  if (typeof body.name !== 'string') return res.status(400).json({ error: 'El nombre es obligatorio.' });
  const error = validateChannelInput(body, null);
  if (error) return res.status(400).json({ error });
  const channel = {
    id: `ch-${Date.now()}`,
    name: body.name.trim(),
    color: body.color || '#64748B',
    icon: body.icon || 'more',
    active: body.active !== false,
    order: (db.saleChannels || []).length,
    createdAt: new Date().toISOString()
  };
  db.saleChannels.push(channel);
  saveDB();
  res.status(201).json(channel);
});

app.put('/api/sale-channels/:id', superAdminOnly, (req, res) => {
  const channel = (db.saleChannels || []).find(c => c.id === req.params.id);
  if (!channel) return res.status(404).json({ error: 'Medio de venta no encontrado.' });
  const body = req.body || {};
  const error = validateChannelInput(body, channel.id);
  if (error) return res.status(400).json({ error });
  if (typeof body.name === 'string' && body.name.trim() !== channel.name) {
    const oldName = channel.name;
    channel.name = body.name.trim();
    // Renaming keeps the history consistent: sold tickets point to the new name
    (db.tickets || []).forEach(t => { if (t.saleChannel === oldName) t.saleChannel = channel.name; });
  }
  if (body.color !== undefined) channel.color = body.color;
  if (body.icon !== undefined) channel.icon = body.icon;
  if (typeof body.active === 'boolean') channel.active = body.active;
  if (Number.isInteger(body.order)) channel.order = body.order;
  channel.updatedAt = new Date().toISOString();
  saveDB();
  res.json(channel);
});

// Banks and wallets are master data managed by the SuperAdmin (db.banks). Like channels, they are
// deactivated instead of deleted, because payments and raffle accounts keep their names.
const DEFAULT_BANKS = [
  'Nequi', 'Daviplata', 'Bancolombia', 'Davivienda', 'Banco de Bogotá', 'BBVA', 'Banco de Occidente', 'Banco Popular',
  'Banco AV Villas', 'Scotiabank Colpatria', 'Banco Caja Social', 'Banco Agrario', 'Itaú', 'Banco Falabella',
  'Banco Pichincha', 'Banco GNB Sudameris', 'Bancoomeva', 'Banco W', 'Banco Mundo Mujer', 'Banco Finandina',
  'Banco Serfinanza', 'Lulo Bank', 'Nu Colombia', 'RappiPay', 'Movii', 'Dale!', 'Ualá', 'Confiar'
];

function ensureBanks(target) {
  if (Array.isArray(target.banks) && target.banks.length) return false;
  const now = new Date().toISOString();
  target.banks = DEFAULT_BANKS.map((name, i) => ({ id: `bank-${i + 1}`, name, active: true, order: i, createdAt: now }));
  return true;
}

function isActiveBank(name) {
  if (!name) return false;
  const clean = String(name).trim().toLowerCase();
  return (db.banks || []).some(b => b.active && b.name.trim().toLowerCase() === clean);
}

function validateBankName(body, currentId) {
  if (body.name === undefined) return null;
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  if (name.length < 2 || name.length > 40) return 'El nombre debe tener entre 2 y 40 caracteres.';
  const taken = (db.banks || []).some(b => b.id !== currentId && b.name.toLowerCase() === name.toLowerCase());
  return taken ? 'Ya existe un banco con ese nombre.' : null;
}

app.get('/api/banks', (req, res) => {
  if (ensureBanks(db)) saveDB();
  const all = [...(db.banks || [])].sort((a, b) => a.name.localeCompare(b.name, 'es'));
  // Everyone gets the active ones; the SuperAdmin also sees inactive ones to manage them
  res.json(req.auth.role === 'superadmin' ? all : all.filter(b => b.active));
});

app.post('/api/banks', superAdminOnly, (req, res) => {
  const body = req.body || {};
  if (typeof body.name !== 'string') return res.status(400).json({ error: 'El nombre es obligatorio.' });
  const error = validateBankName(body, null);
  if (error) return res.status(400).json({ error });
  ensureBanks(db);
  const bank = {
    id: `bank-${Date.now()}`,
    name: body.name.trim(),
    active: body.active !== false,
    order: db.banks.length,
    createdAt: new Date().toISOString()
  };
  db.banks.push(bank);
  saveDB();
  res.status(201).json(bank);
});

app.put('/api/banks/:id', superAdminOnly, (req, res) => {
  const bank = (db.banks || []).find(b => b.id === req.params.id);
  if (!bank) return res.status(404).json({ error: 'Banco no encontrado.' });
  const body = req.body || {};
  const error = validateBankName(body, bank.id);
  if (error) return res.status(400).json({ error });
  if (typeof body.name === 'string' && body.name.trim() !== bank.name) {
    const oldName = bank.name;
    bank.name = body.name.trim();
    // Raffle accounts follow the new name; registered payments keep the name they were made with
    (db.raffles || []).forEach(r => (r.transferAccounts || []).forEach(a => { if (a.bank === oldName) a.bank = bank.name; }));
  }
  if (typeof body.active === 'boolean') bank.active = body.active;
  bank.updatedAt = new Date().toISOString();
  saveDB();
  res.json(bank);
});

// Lotteries are master data managed by the SuperAdmin (db.lotteries); raffles pick the lottery of
// their main draw and of their weekly draws from the active ones.
const DEFAULT_LOTTERIES = [
  'Lotería de Bogotá', 'Lotería de Boyacá', 'Lotería del Cauca', 'Lotería de Cundinamarca', 'Lotería de la Cruz Roja',
  'Lotería del Huila', 'Lotería de Manizales', 'Lotería de Medellín', 'Lotería del Meta', 'Lotería del Quindío',
  'Lotería de Risaralda', 'Lotería de Santander', 'Lotería del Tolima', 'Lotería del Valle', 'Extra de Colombia'
];

function ensureLotteries(target) {
  if (Array.isArray(target.lotteries) && target.lotteries.length) return false;
  const now = new Date().toISOString();
  target.lotteries = DEFAULT_LOTTERIES.map((name, i) => ({ id: `lot-${i + 1}`, name, active: true, order: i, createdAt: now }));
  return true;
}

function isActiveLottery(name) {
  const clean = String(name || '').trim().toLowerCase();
  return !!clean && (db.lotteries || []).some(l => l.active && l.name.trim().toLowerCase() === clean);
}

/** A raffle's lottery must be an active one, unless it keeps the value it already had. */
function checkRaffleLottery(value, current, label) {
  const name = String(value || '').trim();
  if (!name) return { error: `Seleccione la ${label}.` };
  if (name !== String(current || '').trim() && !isActiveLottery(name)) {
    return { error: `La lotería "${name}" no está en la lista de loterías activas.` };
  }
  return { name };
}

function validateLotteryName(body, currentId) {
  if (body.name === undefined) return null;
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  if (name.length < 3 || name.length > 50) return 'El nombre debe tener entre 3 y 50 caracteres.';
  const taken = (db.lotteries || []).some(l => l.id !== currentId && l.name.toLowerCase() === name.toLowerCase());
  return taken ? 'Ya existe una lotería con ese nombre.' : null;
}

app.get('/api/lotteries', (req, res) => {
  if (ensureLotteries(db)) saveDB();
  const all = [...(db.lotteries || [])].sort((a, b) => a.name.localeCompare(b.name, 'es'));
  // Everyone gets the active ones; the SuperAdmin also sees inactive ones to manage them
  res.json(req.auth.role === 'superadmin' ? all : all.filter(l => l.active));
});

app.post('/api/lotteries', superAdminOnly, (req, res) => {
  const body = req.body || {};
  if (typeof body.name !== 'string') return res.status(400).json({ error: 'El nombre es obligatorio.' });
  const error = validateLotteryName(body, null);
  if (error) return res.status(400).json({ error });
  ensureLotteries(db);
  const lottery = {
    id: `lot-${Date.now()}`,
    name: body.name.trim(),
    active: body.active !== false,
    order: db.lotteries.length,
    createdAt: new Date().toISOString()
  };
  db.lotteries.push(lottery);
  saveDB();
  res.status(201).json(lottery);
});

app.put('/api/lotteries/:id', superAdminOnly, (req, res) => {
  const lottery = (db.lotteries || []).find(l => l.id === req.params.id);
  if (!lottery) return res.status(404).json({ error: 'Lotería no encontrada.' });
  const body = req.body || {};
  const error = validateLotteryName(body, lottery.id);
  if (error) return res.status(400).json({ error });
  if (typeof body.name === 'string' && body.name.trim() !== lottery.name) {
    const oldName = lottery.name;
    lottery.name = body.name.trim();
    // Raffles follow the new name (messages, terms and printed tickets show it)
    (db.raffles || []).forEach(r => {
      if (r.mainLotteryName === oldName) r.mainLotteryName = lottery.name;
      if (r.lotteryName === oldName) r.lotteryName = lottery.name;
    });
  }
  if (typeof body.active === 'boolean') lottery.active = body.active;
  lottery.updatedAt = new Date().toISOString();
  saveDB();
  res.json(lottery);
});

// Recently seen submission ids (10 minutes) so a repeated request is never applied twice
const recentRequests = new Map();
/** Whether this submission was already applied (does not record it). */
function wasRequestApplied(requestId) {
  if (typeof requestId !== 'string' || requestId.length < 8 || requestId.length > 100) return false;
  const now = Date.now();
  for (const [key, at] of recentRequests) if (now - at > 10 * 60 * 1000) recentRequests.delete(key);
  return recentRequests.has(requestId);
}

/** Records a submission right before applying it, so a repeat of it is ignored. */
function rememberRequest(requestId) {
  if (typeof requestId === 'string' && requestId.length >= 8 && requestId.length <= 100) recentRequests.set(requestId, Date.now());
}

/** Recomputes paid / pending / status from the (non-voided) payments. */
function recalcTicketTotals(ticket) {
  ticket.totalPaid = (ticket.abonos || []).reduce((sum, a) => sum + (a.amount || 0), 0);
  ticket.balancePending = Math.max(0, (ticket.price || 0) - ticket.totalPaid);
  if (ticket.balancePending <= 0 && ticket.totalPaid > 0) {
    ticket.status = ticket.confirmedByAdmin ? 'CONFIRMADA' : 'PAGADA';
  } else if (ticket.totalPaid > 0) {
    ticket.status = 'ABONO_PARCIAL';
  } else if (ticket.buyerName) {
    ticket.status = 'RESERVADA';
  }
}

// POST Void one payment (admins): it leaves the totals but stays in ticket.voidedAbonos with who/when/why.
// Used to fix payments registered twice or by mistake.
app.post('/api/tickets/:id/abonos/:abonoId/void', adminOnly, (req, res) => {
  const ticket = (db.tickets || []).find(t => t.id === req.params.id);
  if (!ticket) return res.status(404).json({ error: 'Boleta no encontrada' });
  const raffle = (db.raffles || []).find(r => r.id === ticket.raffleId);
  if (raffle && !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Boleta no encontrada' });
  const index = (ticket.abonos || []).findIndex(a => a.id === req.params.abonoId);
  if (index === -1) return res.status(404).json({ error: 'Abono no encontrado.' });
  const blocker = abonoVoidBlocker(ticket.abonos[index]);
  if (blocker) return res.status(409).json({ error: blocker });

  const reason = String((req.body || {}).reason || '').trim();
  if (reason.length < 10) {
    return res.status(400).json({ error: 'Escriba una observación que explique la anulación del abono (mínimo 10 caracteres).' });
  }
  const { role, record } = req.auth;
  const byName = role === 'superadmin' ? (record.name || 'SuperAdministrador') : (record.adminName || 'Administrador');
  const [abono] = ticket.abonos.splice(index, 1);
  if (!Array.isArray(ticket.voidedAbonos)) ticket.voidedAbonos = [];
  ticket.voidedAbonos.push({
    ...abono,
    voidedAt: new Date().toISOString(),
    voidedBy: byName,
    voidReason: reason,
    // Who the ticket belonged to when the payment was voided (the ticket may be resold later)
    buyerName: ticket.buyerName || '',
    buyerPhone: ticket.buyerPhone || '',
    buyerDocument: ticket.buyerDocument || ''
  });
  recalcTicketTotals(ticket);
  if (ticket.totalPaid > 0) recalcCashConfirmation(ticket);

  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({
    id: `audit-${Date.now()}`,
    type: 'VOID_ABONO',
    targetId: ticket.id,
    raffleId: ticket.raffleId,
    numbers: ticket.numbers,
    amount: abono.amount,
    abonoDate: abono.date,
    reason,
    by: byName,
    date: new Date().toISOString()
  });
  saveDB();
  notifyRaffleChanged(ticket.raffleId);
  res.json(ticket);
});

// ── Bank transfers ──
// Colombia has no daylight saving time: always UTC-5.
const COLOMBIA_OFFSET_MS = 5 * 60 * 60 * 1000;
const TRANSFER_MAX_AGE_DAYS = 15;
// Risk alert: this many transfers by the same person inside this window
const RISK_BURST_COUNT = 5;
const RISK_BURST_MINUTES = 60;

/** Calendar day in Colombia ("YYYY-MM-DD") of an instant. */
function colombiaDay(ms) {
  return new Date(ms - COLOMBIA_OFFSET_MS).toISOString().slice(0, 10);
}

/** Approval numbers are compared without spaces, dashes or case. */
function approvalKey(value) {
  return String(value || '').toUpperCase().replace(/[^0-9A-Z]/g, '');
}

function transferAccountLabel(account) {
  return [account.bank, account.accountType, account.accountNumber, account.key ? `llave ${account.key}` : '', account.holder]
    .filter(Boolean).join(' • ');
}

/** Accounts where a raffle receives transfers (configured in the raffle settings). */
function normalizeTransferAccounts(list, current = []) {
  if (!Array.isArray(list)) return { error: 'Las cuentas de transferencia deben ser una lista.' };
  const clean = s => String(s || '').trim().slice(0, 80);
  const accounts = [];
  for (const raw of list.slice(0, 10)) {
    if (!raw || typeof raw !== 'object') continue;
    const account = {
      id: clean(raw.id) || `cta-${Date.now()}-${accounts.length}`,
      bank: clean(raw.bank),
      accountType: clean(raw.accountType),
      accountNumber: clean(raw.accountNumber),
      holder: clean(raw.holder),
      key: clean(raw.key)
    };
    if (!account.bank) return { error: 'Cada cuenta de transferencia necesita el banco.' };
    const matchingBank = (db.banks || []).find(b => b.active && b.name.trim().toLowerCase() === account.bank.toLowerCase());
    if (matchingBank) {
      account.bank = matchingBank.name;
    } else if (!current.some(a => a.bank.trim().toLowerCase() === account.bank.toLowerCase())) {
      return { error: `El banco "${account.bank}" no está en la lista de bancos activos.` };
    }
    if (!account.accountNumber && !account.key) {
      return { error: `La cuenta de ${account.bank} necesita el número de cuenta o la llave.` };
    }
    accounts.push(account);
  }
  return { accounts };
}

/** Checks the transfer data sent with a payment; returns { error } or { transfer }. */
function validateTransfer(body, raffle) {
  // Only the date matters ("YYYY-MM-DD", Colombian calendar); a full timestamp is also accepted
  const raw = String(body.transferDate || '').trim();
  let transferDay = /^\d{4}-\d{2}-\d{2}$/.test(raw) ? raw : null;
  if (!transferDay && !isNaN(Date.parse(raw))) transferDay = colombiaDay(Date.parse(raw));
  if (!transferDay) return { error: 'Indique la fecha de la transferencia.' };
  const now = Date.now();
  if (transferDay > colombiaDay(now)) {
    return { error: 'La fecha de la transferencia no puede ser posterior a hoy (hora de Colombia).' };
  }
  if (transferDay < colombiaDay(now - TRANSFER_MAX_AGE_DAYS * 24 * 60 * 60 * 1000)) {
    return { error: `La transferencia no puede tener más de ${TRANSFER_MAX_AGE_DAYS} días de antigüedad.` };
  }
  const approvalNumber = String(body.approvalNumber || '').trim().slice(0, 40);
  if (approvalKey(approvalNumber).length < 3) return { error: 'Ingrese el número de aprobación de la transferencia.' };
  // El banco de origen es opcional: lo toma el lector del comprobante y, si no se reconoce o no es un banco activo, queda vacío
  const bankRaw = String(body.originBank || '').trim().slice(0, 60);
  const originBank = bankRaw && isActiveBank(bankRaw) ? bankRaw : '';

  const accounts = (raffle && raffle.transferAccounts) || [];
  let cuentaDestino = String(body.cuentaDestino || '').trim().slice(0, 200);
  let transferAccountId = null;
  if (accounts.length) {
    const account = accounts.find(a => a.id === body.transferAccountId);
    if (!account) return { error: 'Seleccione la cuenta de la rifa a la que se hizo la transferencia.' };
    transferAccountId = account.id;
    cuentaDestino = transferAccountLabel(account);
  }
  return {
    transfer: {
      transferDate: transferDay,
      approvalNumber,
      originBank,
      cuentaDestino,
      transferAccountId
    }
  };
}

/**
 * Every payment of the company registered with this approval number: current payments,
 * voided payments and payments of voided sales, so the user can judge whether it is a repeat.
 */
/**
 * Corrige los números de aprobación que el lector de comprobantes tomó mal: antes de la 3.4.18 leía la fecha y la hora
 * ("10 nov 2026 - 2:54 p.m." daba "20262"). Vuelve a leer el soporte guardado en Drive y, si encuentra la referencia real,
 * la cambia (se conserva la anterior y queda en la auditoría). Si no la encuentra, no toca nada.
 */
async function repairMisreadApprovals() {
  if (!ocrService.available()) return;
  const suspects = [];
  for (const t of db.tickets || []) {
    for (const a of t.abonos || []) {
      if (a.metodoPago !== 'transferencia' || !a.soporteDriveId || a.approvalRereadTried) continue;
      if (/^20[2-3]\d\d{1,2}$/.test(approvalKey(a.approvalNumber))) suspects.push({ t, a });
    }
  }
  if (!suspects.length) return;
  let fixed = 0;
  for (const { t, a } of suspects.slice(0, 40)) {
    try {
      const file = await driveService.downloadDriveFile(a.soporteDriveId);
      const proof = await ocrService.readProof(file.buffer);
      const current = (db.tickets || []).find(x => x.id === t.id);
      const ab = current && (current.abonos || []).find(x => x.id === a.id);
      if (!ab) continue;
      ab.approvalRereadTried = true;
      const oldKey = approvalKey(ab.approvalNumber);
      const refs = proof.readable ? (proof.references || []).filter(r => approvalKey(r) !== oldKey) : [];
      if (!refs.length) continue;
      const raffle = (db.raffles || []).find(r => r.id === current.raffleId);
      ab.approvalNumberPrevious = ab.approvalNumber;
      ab.approvalNumber = refs[0];
      ab.approvalCorrectedAt = new Date().toISOString();
      const others = findApprovalMatches(approvalKey(refs[0]), raffle && raffle.companyId, false).filter(m => !(m.ticketId === current.id && m.registeredAt === ab.date));
      if (others.length) {
        ab.riskFlags = [...(ab.riskFlags || []), { code: 'APROBACION_REPETIDA', level: 'MEDIA', detail: `Tras releer el comprobante, la referencia ${refs[0]} ya estaba en ${others.length} pago(s). Compare los soportes.` }];
        ab.riskReview = { status: 'PENDIENTE' };
      }
      if (!db.auditLogs) db.auditLogs = [];
      db.auditLogs.push({
        id: `audit-${Date.now()}-${fixed}`, type: 'APPROVAL_FIX', companyId: raffle ? raffle.companyId : '', targetId: current.id, targetName: raffle ? raffle.title : '',
        detail: `Referencia de la boleta ${(current.numbers || []).join('-')} corregida al releer el comprobante: ${ab.approvalNumberPrevious} → ${ab.approvalNumber}`, by: 'Sistema', date: new Date().toISOString()
      });
      fixed++;
    } catch (err) {
      console.warn('⚠️ No se pudo releer un comprobante:', err.message);
    }
  }
  if (suspects.length) {
    console.log(`🛠️ Referencias revisadas: ${suspects.length}, corregidas: ${fixed}.`);
    saveDB();
  }
}

function findApprovalMatches(key, companyId, maskContact) {
  if (!key) return [];
  return findPaymentMatches(ab => approvalKey(ab.approvalNumber) === key, companyId, maskContact);
}

/** Same idea with any test over the payment: used for the approval number and for the proof image hash. */
function findPaymentMatches(test, companyId, maskContact) {
  const raffles = new Map((db.raffles || []).filter(r => !companyId || r.companyId === companyId).map(r => [r.id, r]));
  const mask = value => {
    const text = String(value || '');
    return maskContact && text.length > 3 ? `${'•'.repeat(text.length - 3)}${text.slice(-3)}` : text;
  };
  const matches = [];
  const collect = (ticket, raffle, abono, state, sale, extra = {}) => {
    if (!test(abono)) return;
    matches.push({
      state,
      raffleTitle: raffle.title,
      ticketId: ticket.id,
      numbers: ticket.numbers || [],
      buyerName: sale.buyerName || '',
      buyerPhone: mask(sale.buyerPhone),
      buyerDocument: mask(sale.buyerDocument),
      advisorName: sale.advisorName || '',
      amount: abono.amount || 0,
      proofTotal: abono.proofTotal || null,
      registeredAt: abono.date || null,
      registeredBy: abono.sellerName || '',
      transferDate: abono.transferDate || null,
      approvalNumber: abono.approvalNumber,
      originBank: abono.originBank || '',
      cuentaDestino: abono.cuentaDestino || '',
      soporteWebViewUrl: abono.soporteWebViewUrl || null,
      ...extra
    });
  };
  for (const ticket of db.tickets || []) {
    const raffle = raffles.get(ticket.raffleId);
    if (!raffle) continue;
    for (const ab of ticket.abonos || []) collect(ticket, raffle, ab, 'VIGENTE', ticket);
    for (const ab of ticket.voidedAbonos || []) {
      collect(ticket, raffle, ab, 'ABONO ANULADO', ticket, { voidReason: ab.voidReason || ab.reason || '', voidedAt: ab.voidedAt || null });
    }
    for (const annulment of ticket.annulments || []) {
      const prev = annulment.previous || {};
      const extra = { voidReason: annulment.reason || '', voidedAt: annulment.date || null };
      for (const ab of prev.abonos || []) collect(ticket, raffle, ab, 'VENTA ANULADA', prev, extra);
      for (const ab of prev.voidedAbonos || []) collect(ticket, raffle, ab, 'VENTA ANULADA', prev, extra);
    }
  }
  return matches.sort((a, b) => String(b.registeredAt).localeCompare(String(a.registeredAt)));
}

/**
 * Un número de aprobación repetido es legítimo cuando UNA transferencia paga varias boletas (ej.: $180.000 repartidos en
 * 4 abonos). Se valida contra el valor TOTAL de la transferencia:
 *  • total conocido (leído del comprobante, o guardado en un pago anterior con esa aprobación): se descuenta lo ya aplicado
 *    y solo se permite abonar hasta lo que queda; si el abono es mayor que lo que queda (por ejemplo, escribir otra vez el
 *    valor completo), se bloquea.
 *  • total desconocido (comprobante ilegible): regla anterior: si lo ya registrado es igual o menor al valor de una boleta,
 *    no pudo alcanzar para otra y se bloquea.
 * Tampoco se puede usar dos veces en la misma boleta. Los pagos anulados no cuentan.
 * opts = { amount: abono que se quiere registrar, proofTotal: valor total leído del comprobante }
 */
function approvalRepeatRule(matches, ticket, raffle, opts = {}) {
  const live = (matches || []).filter(m => m.state === 'VIGENTE');
  if (!live.length) return { blocked: false, registered: 0, price: 0, total: 0, remaining: 0, reason: '', note: '' };
  const price = Number((ticket && ticket.price) || (raffle && raffle.ticketPrice) || 0);
  const registered = live.reduce((sum, m) => sum + (Number(m.amount) || 0), 0);
  const money = n => `$${Math.round(n).toLocaleString('es-CO')}`;
  if (ticket && live.some(m => m.ticketId === ticket.id)) {
    return { blocked: true, registered, price, total: 0, remaining: 0, note: '', reason: 'Este número de aprobación ya está registrado en esta misma boleta: no se puede usar dos veces.' };
  }
  const stored = Math.max(0, ...live.map(m => Number(m.proofTotal) || 0));
  const read = Number(opts.proofTotal) || 0;
  const total = read > 0 ? read : stored;
  const amount = Number(opts.amount) || 0;
  // Lo que esta boleta todavía debe: el abono nunca puede pasarse de ahí, venga de la transferencia que venga
  const ticketPending = ticket ? Math.max(0, Math.round((Number(ticket.price) || price) - (Number(ticket.totalPaid) || 0))) : 0;
  if (total > 0) {
    const remaining = Math.round(total - registered);
    const used = `${money(registered)} en ${live.length} pago${live.length === 1 ? '' : 's'}`;
    // Máximo que se puede registrar en ESTA boleta con esta transferencia: lo que queda de la transferencia y lo que debe la boleta
    const maxAllowed = ticket ? Math.min(Math.max(remaining, 0), ticketPending) : Math.max(remaining, 0);
    if (remaining <= 0) {
      return { blocked: true, registered, price, total, remaining: 0, note: '', reason: `Esta transferencia fue por ${money(total)} y ya se aplicó completa (${used}). No queda saldo para otra boleta: revise el número.` };
    }
    if (amount > remaining + 0.5) {
      const boletaLimit = ticket && ticketPending < remaining ? ` (y esta boleta solo debe ${money(ticketPending)})` : '';
      return {
        blocked: true, registered, price, total, remaining, maxAllowed, note: '',
        reason: `Esta transferencia fue por ${money(total)}; ya se aplicaron ${used} y solo quedan ${money(remaining)}. Este abono de ${money(amount)} la excede: registre como máximo ${money(maxAllowed)}${boletaLimit}.`
      };
    }
    if (ticket && amount > ticketPending + 0.5) {
      return {
        blocked: true, registered, price, total, remaining, maxAllowed, note: '',
        reason: `Este abono de ${money(amount)} supera lo que debe esta boleta (${money(ticketPending)}). De la transferencia quedan ${money(remaining)} para otras boletas: registre como máximo ${money(maxAllowed)} aquí.`
      };
    }
    const left = amount > 0 ? `con este abono quedarían ${money(remaining - amount)} disponibles` : `quedan ${money(remaining)} disponibles para otras boletas`;
    const cap = ticket && maxAllowed < remaining && amount <= 0 ? ` En esta boleta puede abonar como máximo ${money(maxAllowed)}.` : '';
    return { blocked: false, registered, price, total, remaining, maxAllowed, reason: '', note: `Esta transferencia fue por ${money(total)}; ya se aplicaron ${used}; ${left}.${cap}` };
  }
  if (registered <= price) {
    return {
      blocked: true, registered, price, total: 0, remaining: 0, note: '',
      reason: `Este número de aprobación ya está registrado por ${money(registered)}, un valor igual o menor al de una boleta (${money(price)}). No pude leer el valor total de la transferencia en el comprobante: adjunte una imagen legible para validar si alcanza para otra boleta.`
    };
  }
  return { blocked: false, registered, price, total: 0, remaining: 0, reason: '', note: '' };
}

/** Valor total de la transferencia según el comprobante: el mayor valor en pesos que se lee en la imagen. */
function proofTotalOf(read) {
  const amounts = (read && Array.isArray(read.amounts) ? read.amounts : []).filter(v => Number.isFinite(v) && v > 0);
  return amounts.length ? Math.max(...amounts) : 0;
}

// Checks an approval number before saving (the app asks when the user leaves the field)
app.get('/api/transfers/check', (req, res) => {
  const raffle = (db.raffles || []).find(r => r.id === req.query.raffleId);
  if (!raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Rifa no encontrada' });
  const key = approvalKey(req.query.approvalNumber);
  if (key.length < 3) return res.json({ matches: [] });
  const matches = findApprovalMatches(key, raffle.companyId, req.auth.role === 'asesor');
  const ticket = req.query.ticketId ? (db.tickets || []).find(t => t.id === req.query.ticketId && t.raffleId === raffle.id) : null;
  const rule = approvalRepeatRule(matches, ticket, raffle, { amount: Number(req.query.amount) || 0, proofTotal: Number(req.query.proofAmount) || 0 });
  res.json({ matches, blocked: rule.blocked, blockReason: rule.reason, note: rule.note, registeredTotal: rule.registered, ticketPrice: rule.price, transferTotal: rule.total, remaining: rule.remaining });
});

// Lee el comprobante (OCR en el servidor, sin costo): referencia, valor y banco. Para prellenar y validar el formulario.
const readProofHits = new Map(); // quien -> instantes de sus últimas lecturas
app.post('/api/transfers/read-proof', async (req, res) => {
  const who = `${req.auth.role}:${(req.auth.record && req.auth.record.id) || ''}`;
  const now = Date.now();
  const recent = (readProofHits.get(who) || []).filter(t => now - t < 60000);
  if (recent.length >= 10) return res.status(429).json({ error: 'Demasiadas lecturas seguidas. Espere un momento.' });
  readProofHits.set(who, [...recent, now]);
  const raw = req.body && req.body.imageBase64;
  if (typeof raw !== 'string' || raw.length < 100 || raw.length > 24 * 1024 * 1024) return res.status(400).json({ error: 'La imagen es demasiado pesada. Tome una captura de pantalla del comprobante o reduzca la foto.' });
  const buffer = Buffer.from(raw.replace(/^data:image\/\w+;base64,/, ''), 'base64');
  if (buffer.length < 2000) return res.status(400).json({ error: 'La imagen es demasiado pequeña.' });
  const read = await ocrService.readProof(buffer);
  res.json({ available: read.available, readable: read.readable, references: read.references, referenceGuesses: read.referenceGuesses || [], amounts: read.amounts, bank: read.bank, date: read.date || '', accountNumbers: read.accountNumbers || [] });
});

// Administrador: corrige si una venta de un asesor INTEGRAL fue en oficina o en calle (cambia su comisión)
app.put('/api/tickets/:id/sale-zone', adminOnly, (req, res) => {
  const ticket = (db.tickets || []).find(t => t.id === req.params.id);
  const raffle = ticket && (db.raffles || []).find(r => r.id === ticket.raffleId);
  if (!ticket || !raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Boleta no encontrada.' });
  const zone = String((req.body || {}).saleZone || '');
  if (!SALE_ZONES.includes(zone)) return res.status(400).json({ error: 'La venta debe ser OFICINA o CALLE.' });
  const advisor = (db.advisors || []).find(a => a.id === ticket.advisorId);
  if (!advisor) return res.status(400).json({ error: 'Esta boleta no tiene asesor: las ventas directas son siempre de oficina.' });
  if (advisorTypeOf(advisor) !== 'INTEGRAL') {
    return res.status(400).json({ error: `El tipo de venta de un asesor ${advisorTypeOf(advisor) === 'PUNTO' ? 'de punto' : 'de calle'} es fijo; solo los asesores integrales lo eligen en cada venta.` });
  }
  const previous = ticket.saleZone || '(sin definir)';
  ticket.saleZone = zone;
  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({
    id: `audit-${Date.now()}`, type: 'SALE_ZONE', companyId: raffle.companyId, targetId: ticket.id, targetName: raffle.title,
    detail: `Venta de ${advisor.name} (boleta ${(ticket.numbers || []).join('-')}): ${previous} → ${zone}`, by: actorName(req), date: new Date().toISOString()
  });
  saveDB();
  notifyRaffleChanged(ticket.raffleId);
  res.json(ticket);
});

app.post('/api/tickets/:id/abono', async (req, res) => {
  const { id } = req.params;
  const { amount, buyerName, buyerPhone, buyerDocument, buyerEmail, buyerCity, buyerCountry, sellerId, sellerName, note, saleChannel, requestId, metodoPago, soporteImageBase64, soporteBase64 } = req.body;

  const found = db.tickets.find(t => t.id === id);
  if (!found) {
    return res.status(404).json({ error: 'Boleta no encontrada' });
  }
  // La boleta debe ser de la empresa de quien opera (antes cualquier usuario autenticado podía registrar pagos en boletas de otra empresa)
  const saleRaffle = (db.raffles || []).find(r => r.id === found.raffleId);
  if (!saleRaffle || !canAccessRaffle(req, saleRaffle)) return res.status(404).json({ error: 'Boleta no encontrada' });
  if (sellerId && sellerId !== 'admin' && !String(sellerId).startsWith('ind_')) {
    if (req.auth.role === 'asesor') {
      if (sellerId !== req.auth.record.id) return res.status(403).json({ error: 'Un asesor solo puede registrar ventas a su nombre.' });
    } else if (saleRaffle.companyId && !advisorBelongsToCompany(sellerId, saleRaffle.companyId)) {
      return res.status(400).json({ error: 'Ese asesor no pertenece a la empresa de esta rifa.', code: 'ADVISOR_OTHER_COMPANY' });
    }
  }
  if (wasRequestApplied(requestId)) return res.json(withVerification(found));

  // Transfer data is checked before uploading anything
  const isTransfer = metodoPago === 'transferencia' && (parseFloat(amount) || 0) > 0;
  let transfer = null;
  if (isTransfer) {
    const checked = validateTransfer(req.body, db.raffles.find(r => r.id === found.raffleId));
    if (checked.error) return res.status(400).json({ error: checked.error });
    transfer = checked.transfer;
  }

  // Transfers need the proof image (no agreement with banks/gateways: the proof is what the admin checks).
  // Its hash detects the same image being used again.
  let supportHash = null;
  let referenceFlag = null;
  let proofTotal = 0; // valor total de la transferencia según el comprobante
  if (isTransfer) {
    const proof = req.body.soporteImageBase64 || req.body.soporteBase64;
    if (!proof) {
      return res.status(400).json({ error: 'El soporte (foto o captura del comprobante) es obligatorio en las transferencias.', code: 'SUPPORT_REQUIRED' });
    }
    const proofBuffer = Buffer.from(String(proof).replace(/^data:image\/\w+;base64,/, ''), 'base64');
    if (proofBuffer.length < 2000) return res.status(400).json({ error: 'El soporte adjunto no es una imagen válida. Adjunte de nuevo el comprobante.', code: 'SUPPORT_INVALID' });
    supportHash = require('crypto').createHash('sha256').update(proofBuffer).digest('hex');

    // La referencia escrita debe ser la del comprobante (se lee la imagen en el servidor). Si no coincide, el usuario
    // debe corregirla; si insiste, el pago queda con una alerta ALTA para revisión. Si no se puede leer, no bloquea.
    const proofRead = await ocrService.readProof(proofBuffer);
    proofTotal = proofTotalOf(proofRead);
    const refCheck = ocrService.verifyReference(proofRead, transfer.approvalNumber);
    if (refCheck.status === 'MISMATCH') {
      if (req.body.allowReferenceMismatch !== true) {
        return res.status(409).json({
          error: `La referencia escrita (${transfer.approvalNumber}) no coincide con la del comprobante${refCheck.read.length ? ` (leí: ${refCheck.read.slice(0, 3).join(', ')})` : ''}. Corríjala o confirme que es correcta.`,
          code: 'REFERENCE_MISMATCH',
          read: refCheck.read,
          typed: transfer.approvalNumber
        });
      }
      referenceFlag = { code: 'REFERENCIA_NO_COINCIDE', level: 'ALTA', detail: `La referencia escrita (${transfer.approvalNumber}) no coincide con la del comprobante${refCheck.read.length ? ` (leí: ${refCheck.read.slice(0, 3).join(', ')})` : ''}. Compare el soporte.` };
    } else if (refCheck.status === 'UNREADABLE' && proofRead.available) {
      referenceFlag = { code: 'COMPROBANTE_ILEGIBLE', level: 'MEDIA', detail: 'No se pudo leer la referencia del comprobante: compárela a mano con el soporte.' };
    }
  }

  // The payment proof goes to Google Drive first. Nothing below waits, so the checks and the
  // changes happen on the same, current data (no other request or reload can run in between).
  let soporte = { soporteUrl: null, soporteDriveId: null, soporteWebViewUrl: null };
  const rawBase64 = soporteImageBase64 || soporteBase64;
  if (rawBase64) {
    try {
      const raffle = db.raffles.find(r => r.id === found.raffleId);
      const company = raffle ? (db.companies || []).find(c => c.id === raffle.companyId) : null;
      const companyName = company ? (company.name || company.companyName || 'Empresa') : 'Empresa General';
      const folders = await driveService.getRaffleFolders(
        companyName,
        raffle ? raffle.companyId : 'comp_1',
        raffle ? raffle.title : 'Rifa',
        found.raffleId,
        raffle ? raffle.driveFolderId : null
      );
      const current = db.raffles.find(r => r.id === found.raffleId);
      if (current) current.driveFolderId = folders.raffleFolderId;
      const cleanBase64 = rawBase64.replace(/^data:image\/\w+;base64,/, '');
      const uploadRes = await driveService.uploadFileToDrive({
        buffer: Buffer.from(cleanBase64, 'base64'),
        filename: `soporte_boleta_${found.ticketNumber || found.id}_${Date.now()}.jpg`,
        mimeType: 'image/jpeg',
        parentFolderId: folders.soportesFolderId
      });
      soporte = { soporteUrl: uploadRes.directUrl, soporteDriveId: uploadRes.fileId, soporteWebViewUrl: uploadRes.webViewUrl };
    } catch (err) {
      console.error('⚠️ Error al subir soporte de transferencia a Google Drive:', err);
      return res.status(502).json({ error: 'No se pudo subir el soporte a Google Drive. Intente de nuevo o registre el pago sin el soporte.' });
    }
  }

  // Data may have been reloaded while uploading: work on the current ticket
  const ticket = db.tickets.find(t => t.id === id);
  if (!ticket) {
    return res.status(404).json({ error: 'Boleta no encontrada' });
  }
  // Same submission received again (double tap, slow network retry): it was already applied
  if (wasRequestApplied(requestId)) {
    return res.json(withVerification(ticket));
  }

  // Control de concurrencia atómica para 100+ asesores simultáneos:
  const expectedStatus = req.body.expectedStatus;
  if (expectedStatus === 'DISPONIBLE' && ticket.status !== 'DISPONIBLE') {
    const holder = ticket.advisorName ? `por ${ticket.advisorName}` : 'por otro usuario';
    return res.status(409).json({
      error: `¡Atención! La boleta #${ticket.ticketNumber || ticket.id} ya no está disponible. Acaba de ser apartada/vendida ${holder}. Por favor elija otra boleta.`,
      code: 'TICKET_ALREADY_TAKEN',
      currentStatus: ticket.status
    });
  }

  // Si la boleta ya pertenece a otro asesor, un asesor distinto no puede modificarla
  // El ayudante del administrador (oficina/integral con permiso) puede recibir pagos de boletas de otros asesores: la boleta y su comisión
  // siguen con quien la vendió; el pago (y el efectivo) queda a nombre de quien lo recibe
  const assistantAdv = req.auth.role === 'asesor' && isTicketAssistant(advisorRecordOf(req)) ? advisorRecordOf(req) : null;
  const keepOwner = !!assistantAdv && ticket.status !== 'DISPONIBLE' && ticket.advisorId !== assistantAdv.id;
  if (req.auth.role === 'asesor' && !keepOwner && ticket.status !== 'DISPONIBLE' && ticket.advisorId && ticket.advisorId !== req.auth.record.id) {
    return res.status(403).json({
      error: `Esta boleta pertenece a otro asesor (${ticket.advisorName || ticket.advisorId}) y no puede ser modificada.`,
      code: 'TICKET_OWNED_BY_ANOTHER'
    });
  }
  const ticketRaffle = (db.raffles || []).find(r => r.id === ticket.raffleId);
  const saleBlockReason = ticket.status === 'DISPONIBLE' ? salesBlockReason(ticketRaffle) : null;
  if (saleBlockReason) {
    return res.status(400).json({ error: saleBlockReason, code: 'RAFFLE_CLOSED' });
  }
  // The admin may have stopped advisors from selling new tickets (payments of sold tickets are still allowed)
  if (req.auth.role === 'asesor' && ticket.status === 'DISPONIBLE') {
    const block = advisorSaleBlock(ticketRaffle, req.auth.record.id);
    if (block) return res.status(403).json({ error: `${block} Comuníquese con el administrador.`, code: 'SALES_LOCKED' });
  }
  // An advisor working with assigned numbers can only sell inside them (solo en rifas independientes)
  if (req.auth.role === 'asesor' && ticket.status === 'DISPONIBLE' && !ticketInAdvisorRanges(ticket, req.auth.record, ticketRaffle)) {
    return res.status(403).json({ error: 'Esta boleta no está en sus números asignados. Solicite más boletas al administrador.' });
  }

  const abonoAmount = parseFloat(amount) || 0;
  if (isNaN(abonoAmount) || abonoAmount < 0) {
    return res.status(400).json({ error: 'Monto de abono inválido' });
  }
  const pendingBefore = Math.max(0, (ticket.price || 0) - (ticket.totalPaid || 0));
  if (abonoAmount > pendingBefore) {
    return res.status(400).json({
      error: pendingBefore > 0
        ? `El abono ($${abonoAmount.toLocaleString('es-CO')}) supera el saldo pendiente ($${pendingBefore.toLocaleString('es-CO')}).`
        : 'Esta boleta ya está pagada por completo; no se puede registrar otro abono.'
    });
  }

  // Risk signals of the transfer. Repeated approval / proof are allowed when the user confirms them
  // (one transfer can pay several tickets) but they are flagged so the admin reviews them in Caja.
  const riskFlags = [];
  if (referenceFlag) riskFlags.push(referenceFlag);
  if (transfer) {
    const raffle = db.raffles.find(r => r.id === ticket.raffleId);
    const companyId = raffle && raffle.companyId;
    const maskContact = req.auth.role === 'asesor';

    const approvalMatches = findApprovalMatches(approvalKey(transfer.approvalNumber), companyId, maskContact);
    if (approvalMatches.length) {
      // Imposible de repetir: no se puede continuar ni confirmando
      const repeatRule = approvalRepeatRule(approvalMatches, ticket, raffle, { amount: abonoAmount, proofTotal });
      if (repeatRule.blocked) {
        return res.status(409).json({ error: repeatRule.reason, code: 'DUPLICATE_APPROVAL_BLOCKED', matches: approvalMatches });
      }
      if (req.body.allowDuplicateApproval !== true) {
        return res.status(409).json({
          error: `El número de aprobación ${transfer.approvalNumber} ya está registrado. Revise antes de continuar.`,
          code: 'DUPLICATE_APPROVAL',
          matches: approvalMatches
        });
      }
      riskFlags.push({ code: 'APROBACION_REPETIDA', level: 'MEDIA', detail: `El número de aprobación ya estaba en ${approvalMatches.length} pago(s).` });
    }

    const supportMatches = supportHash ? findPaymentMatches(ab => ab.soporteHash === supportHash, companyId, maskContact) : [];
    if (supportMatches.length) {
      const sameApproval = supportMatches.every(m => approvalKey(m.approvalNumber) === approvalKey(transfer.approvalNumber));
      const usedTotal = supportMatches.filter(m => m.state === 'VIGENTE').reduce((sum, m) => sum + (m.amount || 0), 0);
      if (req.body.allowDuplicateSupport !== true) {
        return res.status(409).json({
          error: 'Este soporte (comprobante) ya fue usado en otro pago. Revise antes de continuar.',
          code: 'DUPLICATE_SUPPORT',
          matches: supportMatches,
          sameApproval,
          usedTotal,
          thisAmount: abonoAmount
        });
      }
      riskFlags.push({
        code: 'SOPORTE_REPETIDO',
        level: sameApproval ? 'MEDIA' : 'ALTA',
        detail: sameApproval
          ? `Mismo soporte y misma aprobación en ${supportMatches.length} pago(s) ya registrados ($${Math.round(usedTotal).toLocaleString('es-CO')}): verifique que el valor de la transferencia cubra la suma.`
          : `El mismo soporte se usó con OTRO número de aprobación en ${supportMatches.length} pago(s).`
      });
    }

    // Many transfers registered by the same person in a short time
    const sellerKey = sellerId || (req.auth.record && req.auth.record.id) || '';
    if (sellerKey) {
      const since = Date.now() - RISK_BURST_MINUTES * 60 * 1000;
      let recent = 0;
      for (const t of db.tickets || []) {
        for (const ab of t.abonos || []) {
          if (ab.metodoPago === 'transferencia' && ab.sellerId === sellerKey && Date.parse(ab.date) >= since) recent++;
        }
      }
      if (recent + 1 >= RISK_BURST_COUNT) {
        riskFlags.push({ code: 'RAFAGA_ASESOR', level: 'MEDIA', detail: `${recent + 1} transferencias registradas por la misma persona en los últimos ${RISK_BURST_MINUTES} minutos.` });
      }
    }
  }

  // Tipo de venta (oficina / calle): lo fija el tipo del asesor; el integral lo indica en cada venta
  let saleZone = SALE_ZONES.includes(ticket.saleZone) ? ticket.saleZone : null;
  if (!keepOwner) {
    const isIndependentSale = (req.auth.role === 'admin' && req.auth.record && req.auth.record.isIndependent) || String(sellerId || '').startsWith('ind_');
    const sellerAdvisor = req.auth.role === 'asesor'
      ? req.auth.record
      : (sellerId && sellerId !== 'admin' ? (db.advisors || []).find(a => a.id === sellerId) : null);
    if (sellerAdvisor) {
      const type = advisorTypeOf(sellerAdvisor);
      if (type === 'PUNTO') saleZone = 'OFICINA';
      else if (type === 'CALLE') saleZone = 'CALLE';
      else {
        const wanted = SALE_ZONES.includes(req.body.saleZone) ? req.body.saleZone : null;
        const isNewSale = ticket.status === 'DISPONIBLE';
        const changesSeller = !!ticket.advisorId && ticket.advisorId !== sellerAdvisor.id;
        if (wanted && (req.auth.role !== 'asesor' || isNewSale || !saleZone)) saleZone = wanted;
        else if (isNewSale || changesSeller) {
          return res.status(400).json({ error: 'Indique si la venta es en OFICINA (no comisiona) o en CALLE (comisiona).', code: 'SALE_ZONE_REQUIRED' });
        }
      }
    } else if (!isIndependentSale) {
      saleZone = 'OFICINA'; // venta directa del administrador: sin comisión de asesor
    }
  }

  // Recorded only now: a submission rejected above can be corrected and sent again
  rememberRequest(requestId);

  if (typeof buyerName === 'string' && buyerName.trim().length > 0) ticket.buyerName = buyerName.trim();
  if (typeof buyerPhone === 'string') ticket.buyerPhone = buyerPhone.trim();
  // Optional ID number (cédula); letters/digits only, as typed
  if (typeof buyerDocument === 'string') ticket.buyerDocument = buyerDocument.replace(/[^0-9A-Za-z]/g, '').slice(0, 20);
  if (typeof buyerEmail === 'string') ticket.buyerEmail = buyerEmail.trim().toLowerCase();
  if (typeof buyerCity === 'string') ticket.buyerCity = buyerCity.trim();
  if (typeof buyerCountry === 'string') ticket.buyerCountry = buyerCountry.trim();
  // How the buyer was reached: an active channel from the SuperAdmin's master list
  if (typeof saleChannel === 'string' && (isActiveSaleChannel(saleChannel) || saleChannel === ticket.saleChannel)) {
    ticket.saleChannel = saleChannel;
  }
  if (sellerId && !keepOwner) ticket.advisorId = sellerId;
  if (sellerName && !keepOwner) ticket.advisorName = sellerName;
  if (saleZone && !keepOwner) ticket.saleZone = saleZone;
  if (!ticket.assignedDate) ticket.assignedDate = new Date().toISOString();

  const payMethod = transfer ? 'transferencia' : (metodoPago === 'transferencia' ? 'efectivo' : (metodoPago || 'efectivo'));
  const paymentDetails = {
    metodoPago: payMethod,
    cuentaDestino: transfer ? transfer.cuentaDestino : '',
    ...(transfer ? {
      transferDate: transfer.transferDate,
      approvalNumber: transfer.approvalNumber,
      originBank: transfer.originBank,
      transferAccountId: transfer.transferAccountId,
      ...(req.body.allowDuplicateApproval === true ? { duplicateApprovalConfirmed: true } : {}),
      ...(supportHash ? { soporteHash: supportHash } : {}),
      ...(proofTotal > 0 ? { proofTotal } : {}),
      ...(riskFlags.length ? { riskFlags } : {})
    } : {}),
    ...soporte
  };

  if (abonoAmount > 0) {
    const newAbono = {
      id: `ab-${Date.now()}`,
      amount: abonoAmount,
      date: new Date().toISOString(),
      sellerId: sellerId || 'admin',
      sellerName: sellerName || 'Administrador',
      note: note || 'Abono registrado',
      ...paymentDetails
    };
    // Cash collected or transfer verified directly by admin is immediately settled/legalized
    const isAdminRegistrar = req.auth.role === 'admin' || req.auth.role === 'superadmin' || !sellerId || sellerId === 'admin';
    if (payMethod === 'efectivo' && isAdminRegistrar) {
      newAbono.received = { by: sellerName || 'Administrador', at: newAbono.date, method: 'efectivo', auto: true };
    } else if (payMethod === 'transferencia') {
      if (isAdminRegistrar) {
        // Legalizada directamente en caja por el administrador
        newAbono.verification = {
          status: 'VALIDADA',
          by: actorName(req),
          at: newAbono.date,
          note: 'Legalizada en caja directamente por el administrador'
        };
      } else {
        // Registrada por asesor: queda pendiente de legalizar por el administrador en Caja Admin
        delete newAbono.verification;
      }
    }
    if (newAbono.riskFlags && newAbono.riskFlags.length) {
      // The admin confirmed the warnings while registering; an advisor's payment waits for the admin's review
      newAbono.riskReview = isAdminRegistrar
        ? { status: 'DESCARTADA', by: actorName(req), at: newAbono.date, note: 'Alertas confirmadas por el administrador al registrar el pago' }
        : { status: 'PENDIENTE' };
    }
    ticket.abonos.push(newAbono);
    ticket.totalPaid += abonoAmount;
  } else if (ticket.abonos.length === 0) {
    // Register initial note for reservation if 0 amount
    ticket.abonos.push({
      id: `ab-${Date.now()}`,
      amount: 0,
      date: new Date().toISOString(),
      sellerId: sellerId || 'admin',
      sellerName: sellerName || 'Administrador',
      note: note || 'Boleta apartada / fiada sin abono inicial',
      ...paymentDetails
    });
  }

  ticket.balancePending = Math.max(0, ticket.price - ticket.totalPaid);

  if (ticket.balancePending <= 0 && ticket.totalPaid > 0) {
    ticket.status = ticket.confirmedByAdmin ? 'CONFIRMADA' : 'PAGADA';
  } else if (ticket.totalPaid > 0) {
    ticket.status = 'ABONO_PARCIAL';
  } else {
    ticket.status = 'RESERVADA'; // Apartada / Fiada sin abono ($0)
  }
  // A new payment not yet in the company's hands un-confirms the ticket until it is settled
  if (ticket.totalPaid > 0) recalcCashConfirmation(ticket);

  saveDB();
  notifyRaffleChanged(ticket.raffleId);
  res.json(withVerification(ticket));
});

/** Devuelve la boleta a DISPONIBLE conservando la venta anterior en ticket.annulments (quién, cuándo y por qué). */
function annulTicketSale(ticket, auth, reason, auditType = 'VOID_TICKET') {
  const { role, record } = auth;
  const byName = role === 'superadmin' ? (record.name || 'SuperAdministrador') : role === 'asesor' ? (record.name || 'Asesor') : (record.adminName || 'Administrador');
  const now = new Date().toISOString();
  const previous = {
    status: ticket.status,
    buyerName: ticket.buyerName || '',
    buyerPhone: ticket.buyerPhone || '',
    buyerDocument: ticket.buyerDocument || '',
    advisorId: ticket.advisorId || '',
    advisorName: ticket.advisorName || '',
    saleChannel: ticket.saleChannel || '',
    totalPaid: ticket.totalPaid || 0,
    balancePending: ticket.balancePending,
    confirmedByAdmin: !!ticket.confirmedByAdmin,
    confirmedDate: ticket.confirmedDate || null,
    assignedDate: ticket.assignedDate || null,
    abonos: ticket.abonos || [],
    // Payments voided during this sale stay with it, not with a future sale of the ticket
    voidedAbonos: ticket.voidedAbonos || []
  };

  if (!Array.isArray(ticket.annulments)) ticket.annulments = [];
  ticket.annulments.push({ id: `anul-${Date.now()}`, date: now, by: byName, byRole: role, reason, previous });

  // Back to available: ready to be sold again
  ticket.status = 'DISPONIBLE';
  ticket.buyerName = '';
  ticket.buyerPhone = '';
  ticket.buyerDocument = '';
  ticket.advisorId = '';
  ticket.advisorName = '';
  ticket.saleChannel = '';
  ticket.totalPaid = 0;
  ticket.balancePending = ticket.price;
  ticket.confirmedByAdmin = false;
  ticket.confirmedDate = null;
  ticket.assignedDate = null;
  ticket.abonos = [];
  ticket.voidedAbonos = [];

  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({
    id: `audit-${Date.now()}`,
    type: auditType,
    targetId: ticket.id,
    raffleId: ticket.raffleId,
    numbers: ticket.numbers,
    previousBuyer: previous.buyerName,
    previousAdvisor: previous.advisorName,
    amountVoided: previous.totalPaid,
    reason,
    by: byName,
    date: now
  });

}

// POST Void a sale (admins only): the ticket becomes available again and the whole previous
// sale (buyer, advisor, payments, channel) is kept in ticket.annulments with who/when/why.
app.post('/api/tickets/:id/void', adminOnly, (req, res) => {
  const ticket = (db.tickets || []).find(t => t.id === req.params.id);
  if (!ticket) return res.status(404).json({ error: 'Boleta no encontrada' });
  const raffle = (db.raffles || []).find(r => r.id === ticket.raffleId);
  if (raffle && !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Boleta no encontrada' });
  if (ticket.status === 'DISPONIBLE') return res.status(400).json({ error: 'La boleta ya está disponible; no hay venta que anular.' });
  const locked = (ticket.abonos || []).find(a => abonoVoidBlocker(a));
  if (locked) {
    return res.status(409).json({ error: `No se puede anular la venta: ${abonoVoidBlocker(locked).replace(': no se puede anular.', '').toLowerCase()}.` });
  }

  const reason = String((req.body || {}).reason || '').trim();
  if (reason.length < 10) {
    return res.status(400).json({ error: 'Escriba una observación que explique la anulación (mínimo 10 caracteres).' });
  }

  annulTicketSale(ticket, req.auth, reason);
  saveDB();
  notifyRaffleChanged(ticket.raffleId);
  res.json(ticket);
});

// POST Liberar número: una boleta APARTADA (fiada) que todavía no tiene ningún abono (el total sigue pendiente) vuelve a quedar
// disponible. Lo puede hacer el administrador o el asesor dueño de la boleta; queda en el historial de la boleta.
app.post('/api/tickets/:id/release', (req, res) => {
  const ticket = (db.tickets || []).find(t => t.id === req.params.id);
  if (!ticket) return res.status(404).json({ error: 'Boleta no encontrada' });
  const raffle = (db.raffles || []).find(r => r.id === ticket.raffleId);
  const role = req.auth && req.auth.role;
  if (role === 'asesor') {
    if (!raffle || raffle.companyId !== req.auth.record.companyId) return res.status(404).json({ error: 'Boleta no encontrada' });
    if (ticket.advisorId !== req.auth.record.id) return res.status(403).json({ error: 'Solo puede liberar los números que usted apartó.' });
  } else if (role === 'admin' || role === 'superadmin') {
    if (raffle && !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Boleta no encontrada' });
  } else {
    return res.status(403).json({ error: 'No autorizado' });
  }
  if (ticket.status === 'DISPONIBLE') return res.status(400).json({ error: 'La boleta ya está disponible.' });
  if (ticket.status !== 'RESERVADA') return res.status(400).json({ error: 'Solo se puede liberar un número apartado que aún no tiene abonos.' });
  if ((ticket.totalPaid || 0) > 0 || (ticket.abonos || []).some(a => Number(a.amount) > 0)) {
    return res.status(400).json({ error: 'La boleta ya tiene abonos: no se puede liberar. Un administrador puede anular la venta.' });
  }
  annulTicketSale(ticket, req.auth, String((req.body || {}).reason || '').trim() || 'Número liberado: apartado sin abonos.', 'RELEASE_TICKET');
  saveDB();
  notifyRaffleChanged(ticket.raffleId);
  res.json(ticket);
});

// POST Admin Confirm Ticket Payment Received
// ---------------------------------------------------------------------------
// Cash control. Each payment (abono) is settled when the money is in the company's hands:
//  - transfer from the buyer: the admin validates it (abono.verification)
//  - cash collected by the admin: received at once
//  - cash collected by an advisor: the advisor reports a delivery (db.cashDeliveries: cash or a
//    transfer with its proof, one or several tickets) and the admin confirms or rejects it.
// A ticket is confirmed in cash (confirmedByAdmin) when all its payments are settled.
// ---------------------------------------------------------------------------
function actorName(req) {
  if (req.auth.role === 'superadmin') return 'SuperAdministrador';
  if (req.auth.role === 'admin') return req.auth.record.adminName || 'Administrador';
  return req.auth.record.name || 'Asesor';
}

function isTransferAbono(abono) {
  return abono.metodoPago === 'transferencia';
}

function isAbonoSettled(abono) {
  if ((abono.amount || 0) <= 0) return true;
  if (isTransferAbono(abono)) return !!abono.verification && abono.verification.status === 'VALIDADA';
  return !!abono.received;
}

/**
 * A payment reconciled in cash (transfer validated, advisor delivery confirmed, cash received in
 * hand or confirmed before this control) can no longer be voided: the cash records depend on it.
 * Cash the admin collected himself (recorded automatically at sale time) can still be corrected.
 */
function isAbonoReconciled(abono) {
  if ((abono.amount || 0) <= 0) return false;
  if (isTransferAbono(abono)) return !!abono.verification && abono.verification.status === 'VALIDADA';
  return !!abono.received && !abono.received.auto;
}

/** Why a payment cannot be voided, or null. */
function abonoVoidBlocker(abono) {
  if (isAbonoReconciled(abono)) {
    return isTransferAbono(abono)
      ? 'Esta transferencia ya fue validada en caja: no se puede anular.'
      : 'Este pago ya fue conciliado en caja: no se puede anular.';
  }
  if (abono.deliveryId) return 'Este pago está en una entrega del asesor pendiente: rechace primero la entrega en Caja.';
  return null;
}

/** Cash situation of a payment, as shown in Caja. */
function abonoCashState(abono) {
  if (isTransferAbono(abono)) {
    if (!abono.verification) return 'POR_VALIDAR';
    return abono.verification.status === 'VALIDADA' ? 'VALIDADA' : 'RECHAZADA';
  }
  if (abono.received) return 'RECIBIDO';
  if (abono.deliveryId) return 'EN_ENTREGA';
  return 'EN_PODER_ASESOR';
}

/** Recomputes the ticket's "confirmed in cash" flag and status from its payments. */
function recalcCashConfirmation(ticket) {
  const paying = (ticket.abonos || []).filter(a => (a.amount || 0) > 0);
  const settled = paying.length > 0 && paying.every(isAbonoSettled);
  if (settled && !ticket.confirmedByAdmin) {
    ticket.confirmedByAdmin = true;
    ticket.confirmedDate = new Date().toISOString();
  } else if (!settled && ticket.confirmedByAdmin) {
    ticket.confirmedByAdmin = false;
    ticket.confirmedDate = null;
  }

  ticket.totalPaid = (ticket.abonos || []).reduce((s, a) => s + (a.amount || 0), 0);
  ticket.balancePending = Math.max(0, (ticket.price || 0) - ticket.totalPaid);

  if (ticket.status !== 'DISPONIBLE') {
    if (ticket.totalPaid >= (ticket.price || 0) && ticket.totalPaid > 0) {
      ticket.status = ticket.confirmedByAdmin ? 'CONFIRMADA' : 'PAGADA';
    } else if (ticket.totalPaid > 0) {
      ticket.status = 'ABONO_PARCIAL';
    } else {
      ticket.status = 'RESERVADA';
    }
  }
}

/** Payments confirmed before this cash control existed count as received (once, on first start). */
function ensureCashMigration(target) {
  if (!target.settings || typeof target.settings !== 'object') target.settings = {};
  // Tickets whose payments are all settled are confirmed in cash (and the opposite)
  if (target.settings.cashMigrated && !target.settings.cashRecalculated) {
    for (const t of target.tickets || []) if ((t.totalPaid || 0) > 0) recalcCashConfirmation(t);
    target.settings.cashRecalculated = new Date().toISOString();
    return true;
  }
  if (target.settings.cashMigrated) return false;
  const at = new Date().toISOString();
  for (const t of target.tickets || []) {
    for (const a of t.abonos || []) {
      if ((a.amount || 0) <= 0 || a.received || a.verification) continue;
      if (t.confirmedByAdmin) {
        if (isTransferAbono(a)) a.verification = { status: 'VALIDADA', by: 'Confirmado antes del control de caja', at };
        else a.received = { by: 'Confirmado antes del control de caja', at, method: 'efectivo', legacy: true };
      } else if (!isTransferAbono(a) && (!a.sellerId || a.sellerId === 'admin')) {
        a.received = { by: a.sellerName || 'Administrador', at: a.date || at, method: 'efectivo', auto: true };
      }
    }
  }
  if (!Array.isArray(target.cashDeliveries)) target.cashDeliveries = [];
  for (const t of target.tickets || []) if ((t.totalPaid || 0) > 0) recalcCashConfirmation(t);
  target.settings.cashMigrated = at;
  target.settings.cashRecalculated = at;
  return true;
}

function findTicketAbono(ticketId, abonoId) {
  const ticket = (db.tickets || []).find(t => t.id === ticketId);
  const abono = ticket && (ticket.abonos || []).find(a => a.id === abonoId);
  return { ticket, abono };
}

// Admin "confirm received" of a whole ticket: cash received in hand and transfers validated
app.post('/api/tickets/:id/confirm', adminOnly, (req, res) => {
  const ticket = db.tickets.find(t => t.id === req.params.id);
  if (!ticket) {
    return res.status(404).json({ error: 'Boleta no encontrada' });
  }
  const raffle = (db.raffles || []).find(r => r.id === ticket.raffleId);
  if (raffle && !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Boleta no encontrada' });
  const at = new Date().toISOString();
  const by = actorName(req);
  for (const a of ticket.abonos || []) {
    if ((a.amount || 0) <= 0 || isAbonoSettled(a)) continue;
    if (isTransferAbono(a)) a.verification = { status: 'VALIDADA', by, at, note: 'Confirmado desde Caja' };
    else {
      a.received = { by, at, method: 'efectivo', note: 'Recibido directamente por el administrador' };
      delete a.deliveryId;
    }
  }
  recalcCashConfirmation(ticket);
  saveDB();
  notifyRaffleChanged(ticket.raffleId);

  // Auto-notificar al comprador por WhatsApp si tiene teléfono
  if (ticket.buyerPhone) {
    const company = (db.companies || []).find(c => c.id === raffle?.companyId) || (db.companies || [])[0] || {};
    const instanceName = whatsappService.getInstanceName({ role: 'admin', record: company });
    const totalPaid = (ticket.abonos || []).filter(a => isAbonoSettled(a)).reduce((s, a) => s + (a.amount || 0), 0);
    const confirmMsg = 
`✅ *¡PAGO TOTAL CONFIRMADO Y REGISTRADO EN CAJA!* 🎉

Estimado(a) *${ticket.buyerName || 'Participante'}*, tu boleta ha sido completamente validada y confirmada en caja por la administración.

🔢 *Tus Números:* ${ticket.numbers.join('  •  ')}
💵 *Total Cancelado:* $${totalPaid.toLocaleString('es-CO')} COP
🏆 *Sorteo:* ${raffle?.title || 'Gran Sorteo'}
📌 *Estado:* PAGADA Y ACTIVA PARA EL SORTEO

🌐 *Consulta tu boleta oficial con QR y Soporte Digital aquí:*
${PUBLIC_BASE_URL}/boleta?phone=${ticket.buyerPhone}

¡Muchas gracias y te deseamos muchísima suerte en el sorteo! 🍀✨`;

    whatsappService.sendTextMessage(instanceName, ticket.buyerPhone, confirmMsg, { origin: 'aviso-comprador' }).catch(err => {
      console.warn('⚠️ No se pudo enviar WhatsApp tras confirmación de boleta:', err.message);
    });
  }

  res.json(withVerification(ticket));
});

// ---------------------------------------------------------------------------
// Alertas de riesgo en transferencias (sin convenio con bancos/pasarelas, la validación es humana):
// cada transferencia con señales sospechosas queda marcada y el administrador debe revisarla
// (descartar la alerta o confirmar el fraude) antes de poder validarla en Caja.
// ---------------------------------------------------------------------------
const RISK_REVIEW_STATES = ['PENDIENTE', 'DESCARTADA', 'FRAUDE'];

function abonoNeedsRiskReview(abono) {
  return Array.isArray(abono.riskFlags) && abono.riskFlags.length > 0 && (!abono.riskReview || abono.riskReview.status === 'PENDIENTE');
}

app.get('/api/risk/alerts', adminOnly, (req, res) => {
  const company = targetCompanyOf(req);
  if (!company) return res.status(400).json({ error: 'Seleccione la empresa.' });
  const raffles = new Map((db.raffles || []).filter(r => r.companyId === company.id).map(r => [r.id, r]));
  const alerts = [];
  for (const ticket of db.tickets || []) {
    const raffle = raffles.get(ticket.raffleId);
    if (!raffle) continue;
    for (const abono of ticket.abonos || []) {
      if (!Array.isArray(abono.riskFlags) || abono.riskFlags.length === 0) continue;
      alerts.push({
        ticketId: ticket.id,
        abonoId: abono.id,
        raffleTitle: raffle.title,
        numbers: ticket.numbers || [],
        buyerName: ticket.buyerName || '',
        advisorName: abono.sellerName || ticket.advisorName || '',
        amount: abono.amount || 0,
        date: abono.date,
        approvalNumber: abono.approvalNumber || '',
        originBank: abono.originBank || '',
        soporteWebViewUrl: abono.soporteWebViewUrl || null,
        cashState: abonoCashState(abono),
        flags: abono.riskFlags,
        review: abono.riskReview || { status: 'PENDIENTE' }
      });
    }
  }
  alerts.sort((a, b) => {
    const pa = a.review.status === 'PENDIENTE' ? 0 : 1;
    const pb = b.review.status === 'PENDIENTE' ? 0 : 1;
    return pa !== pb ? pa - pb : String(b.date).localeCompare(String(a.date));
  });
  res.json({ alerts: alerts.slice(0, 200), pending: alerts.filter(a => a.review.status === 'PENDIENTE').length });
});

// Admin decides on an alert: DESCARTADA (it is a legitimate payment) or FRAUDE (the payment is not real)
app.post('/api/risk/alerts/:ticketId/:abonoId/review', adminOnly, (req, res) => {
  const { ticket, abono } = findTicketAbono(req.params.ticketId, req.params.abonoId);
  const raffle = ticket && (db.raffles || []).find(r => r.id === ticket.raffleId);
  if (!abono || !raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Pago no encontrado.' });
  if (!Array.isArray(abono.riskFlags) || abono.riskFlags.length === 0) return res.status(400).json({ error: 'Este pago no tiene alertas de riesgo.' });
  const status = String((req.body || {}).status || '');
  if (!['DESCARTADA', 'FRAUDE'].includes(status)) return res.status(400).json({ error: 'Decisión no válida.' });
  const note = String((req.body || {}).note || '').trim().slice(0, 300);
  if (note.length < 5) return res.status(400).json({ error: 'Explique su decisión (mínimo 5 caracteres).' });
  abono.riskReview = { status, by: actorName(req), at: new Date().toISOString(), note };
  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({
    id: `audit-${Date.now()}`, type: 'RISK_REVIEW', companyId: raffle.companyId, targetId: ticket.id, targetName: raffle.title,
    detail: `Alerta de riesgo ${status === 'FRAUDE' ? 'confirmada como FRAUDE' : 'descartada'} (boleta ${(ticket.numbers || []).join('-')}, $${abono.amount}): ${note}`,
    by: actorName(req), date: new Date().toISOString()
  });
  saveDB();
  notifyRaffleChanged(ticket.raffleId);
  res.json({ ok: true, review: abono.riskReview });
});

// Admin validates or rejects a buyer's transfer (it reached the company's account or not)
app.post('/api/cash/abonos/:ticketId/:abonoId/verify', adminOnly, (req, res) => {
  const { ticket, abono } = findTicketAbono(req.params.ticketId, req.params.abonoId);
  const raffle = ticket && (db.raffles || []).find(r => r.id === ticket.raffleId);
  if (!abono || !raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Pago no encontrado.' });
  if (!isTransferAbono(abono)) return res.status(400).json({ error: 'Este pago fue en efectivo: se confirma con la entrega del asesor.' });
  const action = (req.body || {}).action;
  const note = String((req.body || {}).note || '').trim().slice(0, 300);
  if (action === 'validar' && abonoNeedsRiskReview(abono)) {
    return res.status(409).json({
      error: 'Esta transferencia tiene alertas de riesgo sin revisar. Revísela en "Alertas de riesgo" (descartar o confirmar fraude) antes de validarla.',
      code: 'RISK_REVIEW_REQUIRED'
    });
  }
  if (action === 'validar' && abono.riskReview && abono.riskReview.status === 'FRAUDE') {
    return res.status(409).json({ error: 'Esta transferencia fue marcada como FRAUDE: no se puede validar. Recházela.', code: 'RISK_FRAUD' });
  }
  if (action === 'reset') {
    delete abono.verification;
  } else if (action === 'validar' || action === 'rechazar') {
    if (action === 'rechazar' && note.length < 5) return res.status(400).json({ error: 'Explique por qué rechaza la transferencia.' });
    abono.verification = { status: action === 'validar' ? 'VALIDADA' : 'RECHAZADA', by: actorName(req), at: new Date().toISOString(), note };

    // Auto-notificación inmediata por WhatsApp al comprador
    if (ticket.buyerPhone) {
      const company = (db.companies || []).find(c => c.id === raffle.companyId) || (db.companies || [])[0] || {};
      const instanceName = whatsappService.getInstanceName({ role: 'admin', record: company });
      const approvalTxt = abono.approvalNumber ? `\n🧾 *Comprobante bancario:* #${abono.approvalNumber}` : '';
      const bankTxt = abono.originBank ? `\n🏛️ *Banco / Medio:* ${abono.originBank}` : '';
      const totalPaid = (ticket.abonos || []).filter(a => isAbonoSettled(a)).reduce((s, a) => s + (a.amount || 0), 0);
      const isFull = totalPaid >= Number(raffle.ticketPrice || 0);

      if (action === 'validar') {
        const confirmMsg = 
`✅ *¡PAGO VALIDADO Y CONFIRMADO EN BANCO!* 🎉

Hola *${ticket.buyerName || 'Participante'}*, tu transferencia bancaria ha sido confirmada con éxito por nuestro equipo administrativo.

🔢 *Tus Números:* ${ticket.numbers.join('  •  ')}
💵 *Valor Validado:* $${Number(abono.amount || 0).toLocaleString('es-CO')} COP${approvalTxt}${bankTxt}
🏆 *Sorteo:* ${raffle.title || 'Gran Sorteo'}
📌 *Estado:* ${isFull ? 'PAGADA / CONFIRMADA (Activa para el sorteo)' : `ABONADA ($${totalPaid.toLocaleString('es-CO')} de $${Number(raffle.ticketPrice || 0).toLocaleString('es-CO')})`}

🌐 *Puedes consultar y descargar tu Boleta Oficial con QR y Soporte Digital aquí:*
${PUBLIC_BASE_URL}/boleta?phone=${ticket.buyerPhone}

¡Muchas gracias y te deseamos muchísima suerte en el sorteo! 🍀✨`;

        whatsappService.sendTextMessage(instanceName, ticket.buyerPhone, confirmMsg, { origin: 'aviso-comprador' }).catch(err => {
          console.warn('⚠️ No se pudo enviar WhatsApp de confirmación de pago:', err.message);
        });
      } else if (action === 'rechazar') {
        const rejectMsg = 
`⚠️ *AVISO SOBRE TU TRANSFERENCIA* - ${company.name || 'Rifa Master'}

Hola *${ticket.buyerName || 'Participante'}*, te informamos que tu comprobante de transferencia${abono.approvalNumber ? ` (#${abono.approvalNumber})` : ''} para la boleta *#${ticket.ticketNumber}* (${ticket.numbers.join(' • ')}) no pudo ser validado en nuestra cuenta bancaria.

❌ *Motivo:* ${note}

Por favor verifica la transacción o comunícate con nosotros por este medio para aclararlo y conservar tus números. 📲`;

        whatsappService.sendTextMessage(instanceName, ticket.buyerPhone, rejectMsg, { origin: 'aviso-comprador' }).catch(err => {
          console.warn('⚠️ No se pudo enviar WhatsApp de rechazo de transferencia:', err.message);
        });
      }
    }
  } else {
    return res.status(400).json({ error: 'Acción no válida.' });
  }
  recalcCashConfirmation(ticket);
  saveDB();
  notifyRaffleChanged(ticket.raffleId);

  // Auto-notificar al comprador por WhatsApp si tiene teléfono
  if (ticket.buyerPhone) {
    const company = (db.companies || []).find(c => c.id === raffle?.companyId) || (db.companies || [])[0] || {};
    const instanceName = whatsappService.getInstanceName({ role: 'admin', record: company });
    const totalPaid = (ticket.abonos || []).filter(a => isAbonoSettled(a)).reduce((s, a) => s + (a.amount || 0), 0);
    const confirmMsg = 
`✅ *¡PAGO TOTAL CONFIRMADO Y REGISTRADO EN CAJA!* 🎉

Estimado(a) *${ticket.buyerName || 'Participante'}*, tu boleta ha sido completamente validada y confirmada en caja por la administración.

🔢 *Tus Números:* ${ticket.numbers.join('  •  ')}
💵 *Total Cancelado:* $${totalPaid.toLocaleString('es-CO')} COP
🏆 *Sorteo:* ${raffle?.title || 'Gran Sorteo'}
📌 *Estado:* PAGADA Y ACTIVA PARA EL SORTEO

🌐 *Consulta tu boleta oficial con QR y Soporte Digital aquí:*
${PUBLIC_BASE_URL}/boleta?phone=${ticket.buyerPhone}

¡Muchas gracias y te deseamos muchísima suerte en el sorteo! 🍀✨`;

    whatsappService.sendTextMessage(instanceName, ticket.buyerPhone, confirmMsg, { origin: 'aviso-comprador' }).catch(err => {
      console.warn('⚠️ No se pudo enviar WhatsApp tras confirmación de boleta:', err.message);
    });
  }

  res.json(withVerification(ticket));
});

// Admin distributes a transfer surplus across other tickets or records a justification
app.post('/api/cash/abonos/:ticketId/:abonoId/distribute', adminOnly, (req, res) => {
  const { ticket, abono } = findTicketAbono(req.params.ticketId, req.params.abonoId);
  const raffle = ticket && (db.raffles || []).find(r => r.id === ticket.raffleId);
  if (!abono || !raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Pago no encontrado.' });

  const currentTicketAmount = Number(req.body.currentTicketAmount) || (ticket.price || 0);
  const distributions = Array.isArray(req.body.distributions) ? req.body.distributions : [];
  const justification = String(req.body.justification || '').trim();

  const totalDist = distributions.reduce((sum, d) => sum + (Number(d.amount) || 0), 0);
  const originalAmount = Number(abono.amount) || 0;

  if (currentTicketAmount + totalDist > originalAmount) {
    return res.status(400).json({
      error: `La suma asignada ($${(currentTicketAmount + totalDist).toLocaleString('es-CO')}) excede el valor de la transferencia original ($${originalAmount.toLocaleString('es-CO')}).`
    });
  }

  // 1. Ajustar el abono de la boleta actual
  abono.amount = currentTicketAmount;
  if (justification) {
    abono.surplusJustification = justification;
  }

  const affectedTickets = [ticket];

  // 2. Distribuir a las otras boletas seleccionadas
  for (let i = 0; i < distributions.length; i++) {
    const dist = distributions[i];
    const distAmt = Number(dist.amount) || 0;
    if (distAmt <= 0) continue;

    let target = null;
    if (dist.ticketId) {
      target = (db.tickets || []).find(t => t.id === dist.ticketId && t.raffleId === raffle.id);
    } else if (dist.ticketNumber !== undefined && dist.ticketNumber !== '') {
      target = (db.tickets || []).find(t => t.ticketNumber === Number(dist.ticketNumber) && t.raffleId === raffle.id);
    } else if (dist.opportunity) {
      target = (db.tickets || []).find(t => t.raffleId === raffle.id && Array.isArray(t.numbers) && t.numbers.includes(String(dist.opportunity).trim()));
    }

    if (!target) {
      return res.status(404).json({ error: `Boleta adicional #${dist.ticketNumber || dist.opportunity || dist.ticketId} no encontrada en esta rifa.` });
    }

    // Asignar al mismo comprador si la boleta estaba disponible
    if (target.status === 'DISPONIBLE' || !target.buyerName) {
      target.buyerName = ticket.buyerName;
      target.buyerPhone = ticket.buyerPhone;
      target.buyerDocument = ticket.buyerDocument;
      target.buyerEmail = ticket.buyerEmail;
      target.buyerCity = ticket.buyerCity;
      target.buyerCountry = ticket.buyerCountry;
      target.advisorId = ticket.advisorId;
      target.advisorName = ticket.advisorName;
      target.saleChannel = ticket.saleChannel;
      target.assignedDate = new Date().toISOString();
    }

    target.abonos = target.abonos || [];
    target.abonos.push({
      id: `abn-dist-${Date.now()}-${i}`,
      amount: distAmt,
      metodoPago: 'transferencia',
      date: abono.date,
      sellerId: abono.sellerId,
      sellerName: abono.sellerName,
      note: `Distribuido de Comprobante #${abono.approvalNumber || ''} (Boleta #${ticket.ticketNumber})`,
      approvalNumber: abono.approvalNumber,
      originBank: abono.originBank,
      cuentaDestino: abono.cuentaDestino,
      transferDate: abono.transferDate,
      soporteUrl: abono.soporteUrl,
      soporteDriveId: abono.soporteDriveId,
      soporteWebViewUrl: abono.soporteWebViewUrl,
      ...(abono.verification ? { verification: { ...abono.verification } } : {})
    });

    recalcCashConfirmation(target);
    affectedTickets.push(target);
  }

  recalcCashConfirmation(ticket);
  saveDB();
  notifyRaffleChanged(ticket.raffleId);

  res.json({
    message: 'Transferencia distribuida con éxito entre las boletas seleccionadas.',
    updatedTickets: affectedTickets.map(withVerification)
  });
});

// Admin received a cash payment in hand (without a delivery report from the advisor)
app.post('/api/cash/abonos/:ticketId/:abonoId/receive', adminOnly, (req, res) => {
  const { ticket, abono } = findTicketAbono(req.params.ticketId, req.params.abonoId);
  const raffle = ticket && (db.raffles || []).find(r => r.id === ticket.raffleId);
  if (!abono || !raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Pago no encontrado.' });
  if (isTransferAbono(abono)) return res.status(400).json({ error: 'Es una transferencia: valídela en lugar de recibirla.' });
  if (abono.received) return res.status(400).json({ error: 'Este pago ya fue recibido.' });
  if (abono.deliveryId) return res.status(400).json({ error: 'Este pago está en una entrega del asesor: confírmela o recházela.' });
  abono.received = { by: actorName(req), at: new Date().toISOString(), method: 'efectivo', note: 'Recibido en mano por el administrador' };
  recalcCashConfirmation(ticket);
  saveDB();
  notifyRaffleChanged(ticket.raffleId);

  // Auto-notificar al comprador por WhatsApp si tiene teléfono
  if (ticket.buyerPhone) {
    const company = (db.companies || []).find(c => c.id === raffle?.companyId) || (db.companies || [])[0] || {};
    const instanceName = whatsappService.getInstanceName({ role: 'admin', record: company });
    const totalPaid = (ticket.abonos || []).filter(a => isAbonoSettled(a)).reduce((s, a) => s + (a.amount || 0), 0);
    const confirmMsg = 
`✅ *¡PAGO TOTAL CONFIRMADO Y REGISTRADO EN CAJA!* 🎉

Estimado(a) *${ticket.buyerName || 'Participante'}*, tu boleta ha sido completamente validada y confirmada en caja por la administración.

🔢 *Tus Números:* ${ticket.numbers.join('  •  ')}
💵 *Total Cancelado:* $${totalPaid.toLocaleString('es-CO')} COP
🏆 *Sorteo:* ${raffle?.title || 'Gran Sorteo'}
📌 *Estado:* PAGADA Y ACTIVA PARA EL SORTEO

🌐 *Consulta tu boleta oficial con QR y Soporte Digital aquí:*
${PUBLIC_BASE_URL}/boleta?phone=${ticket.buyerPhone}

¡Muchas gracias y te deseamos muchísima suerte en el sorteo! 🍀✨`;

    whatsappService.sendTextMessage(instanceName, ticket.buyerPhone, confirmMsg, { origin: 'aviso-comprador' }).catch(err => {
      console.warn('⚠️ No se pudo enviar WhatsApp tras confirmación de boleta:', err.message);
    });
  }

  res.json(withVerification(ticket));
});

/** Delivery as returned to the app, with each payment's current state. */
function deliveryView(d) {
  return {
    ...d,
    items: (d.items || []).map(item => {
      const { ticket, abono } = findTicketAbono(item.ticketId, item.abonoId);
      return { ...item, buyerName: ticket ? ticket.buyerName : '', state: abono ? abonoCashState(abono) : 'ANULADO' };
    })
  };
}

app.get('/api/cash/deliveries', (req, res) => {
  const companyId = req.auth.role === 'admin' ? req.auth.record.id : (req.auth.role === 'asesor' ? req.auth.record.companyId : req.query.companyId);
  let list = (db.cashDeliveries || []).filter(d => !companyId || d.companyId === companyId);
  if (req.auth.role === 'asesor') list = list.filter(d => d.advisorId === req.auth.record.id);
  if (req.query.raffleId) list = list.filter(d => d.raffleId === req.query.raffleId);
  res.json(list.slice().sort((a, b) => String(b.reportedAt).localeCompare(String(a.reportedAt))).map(deliveryView));
});

/** Delivery proofs uploaded before the per-advisor folders existed are moved there (once each). */
async function moveDeliveryProofsToAdvisorFolders() {
  const pending = (db.cashDeliveries || []).filter(d => d.soporteDriveId && !d.soporteInAdvisorFolder);
  for (const d of pending) {
    try {
      const raffle = (db.raffles || []).find(r => r.id === d.raffleId) || {};
      const company = (db.companies || []).find(c => c.id === d.companyId) || {};
      const folders = await driveService.getRaffleFolders(company.name || 'Empresa', d.companyId, raffle.title || 'Rifa', raffle.id || 'general', raffle.driveFolderId || null);
      const target = await driveService.getAdvisorDeliveriesFolder(folders.raffleFolderId, d.advisorName);
      await driveService.moveDriveFile(d.soporteDriveId, target);
      const current = (db.cashDeliveries || []).find(x => x.id === d.id);
      if (current) current.soporteInAdvisorFolder = true;
    } catch (err) {
      console.error('⚠️ No se pudo mover el soporte de la entrega', d.id, err.message);
    }
  }
  if (pending.length) saveDB();
}
setTimeout(() => { if (isDbLoaded) moveDeliveryProofsToAdvisorFolders().catch(() => {}); }, 15000);

/** Company that owns a Drive file used as a proof (payment, delivery, raffle images), or null. */
function companyOfDriveFile(fileId) {
  const raffleCompany = id => ((db.raffles || []).find(r => r.id === id) || {}).companyId;
  for (const d of db.cashDeliveries || []) if (d.soporteDriveId === fileId) return d.companyId;
  for (const e of db.expenses || []) if (e.soporteDriveId === fileId) return e.companyId;
  for (const r of db.raffles || []) if (r.aficheDriveId === fileId || r.fondoBoletaDriveId === fileId) return r.companyId;
  for (const t of db.tickets || []) {
    const lists = [t.abonos || [], t.voidedAbonos || [], ...(t.annulments || []).map(a => (a.previous && a.previous.abonos) || [])];
    if (lists.some(list => list.some(a => a.soporteDriveId === fileId))) return raffleCompany(t.raffleId);
  }
  return null;
}

// Proof image from Google Drive, served by this server (the browser cannot load Drive images directly)
app.get('/api/files/:fileId', async (req, res) => {
  const fileId = String(req.params.fileId || '');
  if (!/^[\w-]{10,}$/.test(fileId)) return res.status(400).json({ error: 'Archivo no válido.' });
  const companyId = companyOfDriveFile(fileId);
  const myCompany = req.auth.role === 'admin' ? req.auth.record.id : req.auth.role === 'asesor' ? req.auth.record.companyId : null;
  if (!companyId || (req.auth.role !== 'superadmin' && companyId !== myCompany)) return res.status(404).json({ error: 'Archivo no encontrado.' });
  try {
    const file = await driveService.downloadDriveFile(fileId);
    res.setHeader('Content-Type', file.mimeType);
    res.setHeader('Cache-Control', 'private, max-age=86400');
    res.send(file.buffer);
  } catch (err) {
    console.error('⚠️ No se pudo leer el archivo de Drive:', err.message);
    res.status(502).json({ error: 'No se pudo traer el archivo de Google Drive.' });
  }
});

// The advisor reports that he handed over cash he collected: in cash or by a transfer (with proof)
app.post('/api/cash/deliveries', requireRole('asesor'), async (req, res) => {
  const advisor = req.auth.record;
  const body = req.body || {};
  const method = body.method === 'transferencia' ? 'transferencia' : 'efectivo';
  const refs = Array.isArray(body.items) ? body.items.slice(0, 500) : [];
  if (!refs.length) return res.status(400).json({ error: 'Seleccione las boletas que entrega.' });

  let transfer = null;
  if (method === 'transferencia') {
    const day = String(body.transferDate || '').trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || day > colombiaDay(Date.now())) return res.status(400).json({ error: 'Indique la fecha de la transferencia (no puede ser futura).' });
    const approvalNumber = String(body.approvalNumber || '').trim().slice(0, 40);
    if (approvalKey(approvalNumber).length < 3) return res.status(400).json({ error: 'Ingrese el número de aprobación de la transferencia.' });
    const originBank = String(body.originBank || '').trim().slice(0, 60);
    if (!originBank) return res.status(400).json({ error: 'Indique el banco desde el que transfirió.' });
    if (!body.soporteImageBase64) return res.status(400).json({ error: 'Adjunte el soporte de la transferencia.' });
    transfer = { transferDate: day, approvalNumber, originBank, destination: String(body.destination || '').trim().slice(0, 200) };
  }

  // Proof goes to Google Drive first; checks and changes below run without waiting
  let soporte = {};
  if (transfer) {
    try {
      const raffle = (db.raffles || []).find(r => r.id === body.raffleId) || {};
      const company = (db.companies || []).find(c => c.id === advisor.companyId) || {};
      const folders = await driveService.getRaffleFolders(company.name || 'Empresa', advisor.companyId, raffle.title || 'Rifa', raffle.id || 'general', raffle.driveFolderId || null);
      // [Rifa]/Entregas_Asesores/[Asesor]
      const advisorFolderId = await driveService.getAdvisorDeliveriesFolder(folders.raffleFolderId, advisor.name);
      const up = await driveService.uploadFileToDrive({
        buffer: Buffer.from(String(body.soporteImageBase64).replace(/^data:image\/\w+;base64,/, ''), 'base64'),
        filename: `entrega_${advisor.code || advisor.id}_${Date.now()}.jpg`,
        mimeType: 'image/jpeg',
        parentFolderId: advisorFolderId
      });
      soporte = { soporteUrl: up.directUrl, soporteDriveId: up.fileId, soporteWebViewUrl: up.webViewUrl };
    } catch (err) {
      console.error('⚠️ Error al subir soporte de entrega:', err);
      return res.status(502).json({ error: 'No se pudo subir el soporte a Google Drive. Intente de nuevo.' });
    }
  }

  const me = (db.advisors || []).find(a => a.id === advisor.id) || advisor;
  const items = [];
  for (const ref of refs) {
    const { ticket, abono } = findTicketAbono(ref.ticketId, ref.abonoId);
    if (!abono) return res.status(400).json({ error: 'Una de las boletas seleccionadas ya no existe o cambió. Actualice la lista.' });
    if (abono.sellerId !== me.id) return res.status(403).json({ error: `El pago de la boleta ${(ticket.numbers || []).join('-')} no lo cobró usted.` });
    const state = abonoCashState(abono);
    if (state !== 'EN_PODER_ASESOR') {
      return res.status(400).json({ error: `El pago de la boleta ${(ticket.numbers || []).join('-')} ya ${state === 'EN_ENTREGA' ? 'está en otra entrega' : 'fue recibido o es una transferencia'}.` });
    }
    items.push({ ticketId: ticket.id, abonoId: abono.id, raffleId: ticket.raffleId, numbers: ticket.numbers || [], amount: abono.amount || 0, paymentDate: abono.date });
  }
  const delivery = {
    id: `ent-${Date.now()}`,
    companyId: me.companyId,
    raffleId: body.raffleId || items[0].raffleId,
    advisorId: me.id,
    advisorName: me.name,
    method,
    total: items.reduce((sum, i) => sum + i.amount, 0),
    items,
    ...(transfer || {}),
    ...soporte,
    ...(soporte.soporteDriveId ? { soporteInAdvisorFolder: true } : {}),
    note: String(body.note || '').trim().slice(0, 300),
    status: 'PENDIENTE',
    reportedAt: new Date().toISOString()
  };
  // Gastos en efectivo del asesor aún sin justificar: se descuentan de lo que entrega en mano
  if (method === 'efectivo') {
    const spent = agilService.unappliedCashExpenses(me.id);
    delivery.expensesTotal = spent.reduce((sum, e) => sum + e.amount, 0);
    delivery.expenseIds = spent.map(e => e.id);
    delivery.netToHand = delivery.total - delivery.expensesTotal;
  }
  for (const item of items) findTicketAbono(item.ticketId, item.abonoId).abono.deliveryId = delivery.id;
  db.cashDeliveries.unshift(delivery);
  saveDB();
  res.status(201).json(deliveryView(delivery));
});

// The admin confirms (money received) or rejects a delivery reported by an advisor
app.post('/api/cash/deliveries/:id/:action', adminOnly, (req, res) => {
  const delivery = (db.cashDeliveries || []).find(d => d.id === req.params.id);
  if (!delivery || (req.auth.role === 'admin' && delivery.companyId !== req.auth.record.id)) return res.status(404).json({ error: 'Entrega no encontrada.' });
  if (delivery.status !== 'PENDIENTE') return res.status(400).json({ error: 'Esta entrega ya fue revisada.' });
  const action = req.params.action;
  if (!['confirmar', 'rechazar'].includes(action)) return res.status(400).json({ error: 'Acción no válida.' });
  const reason = String((req.body || {}).reason || '').trim().slice(0, 300);
  if (action === 'rechazar' && reason.length < 5) return res.status(400).json({ error: 'Explique por qué rechaza la entrega.' });
  const at = new Date().toISOString();
  const by = actorName(req);
  for (const item of delivery.items) {
    const { ticket, abono } = findTicketAbono(item.ticketId, item.abonoId);
    if (!abono || abono.deliveryId !== delivery.id) continue;
    if (action === 'confirmar') {
      abono.received = { by, at, method: delivery.method, deliveryId: delivery.id };
    }
    delete abono.deliveryId;
    recalcCashConfirmation(ticket);
  }
  if (action === 'confirmar' && delivery.method === 'efectivo' && (delivery.expenseIds || []).length) {
    agilService.applyExpenses(delivery.expenseIds, { deliveryId: delivery.id, by, at });
  }
  // Entrega por transferencia confirmada: el efectivo del asesor pasa a la cuenta a la que transfirió (traslado Efectivo → cuenta)
  if (action === 'confirmar' && delivery.method === 'transferencia') {
    agilService.recordDeliveryTransfer(delivery, by, at);
  }
  delivery.status = action === 'confirmar' ? 'CONFIRMADA' : 'RECHAZADA';
  delivery.reviewedBy = by;
  delivery.reviewedAt = at;
  if (reason) delivery.reviewNote = reason;
  saveDB();
  res.json(deliveryView(delivery));
});

// ── Assigned number ranges ──
// Ranges refer to the numbers printed on the tickets (opportunities), e.g. "10-20" or "35".
// A ticket belongs to an advisor's ranges when any of its numbers falls inside one of them.
function parseRange(text) {
  const match = /^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$/.exec(String(text || ''));
  if (!match) return null;
  const start = parseInt(match[1], 10);
  const end = match[2] !== undefined ? parseInt(match[2], 10) : start;
  return start <= end ? { start, end } : null;
}

function rangeLabel({ start, end }) {
  return start === end ? String(start) : `${start}-${end}`;
}

function ticketNumbersOf(ticket) {
  const nums = (ticket.numbers || []).map(n => parseInt(n, 10)).filter(n => !isNaN(n));
  return nums.length ? nums : [ticket.ticketNumber];
}

/**
 * Los números asignados (rangos) a un asesor SOLO aplican en rifas independientes (talonarios). En una rifa normal todos los
 * asesores venden cualquier boleta: los rangos de un asesor no se heredan a las rifas nuevas.
 */
function ticketInAdvisorRanges(ticket, advisor, raffle) {
  if (raffle && !raffle.isIndependentBook) return true;
  if (!advisor || advisor.mode !== 'ASSIGNED') return true;
  const ranges = (advisor.assignedTicketRanges || []).map(parseRange).filter(Boolean);
  if (!ranges.length) return true;
  return ticketNumbersOf(ticket).some(n => ranges.some(r => n >= r.start && n <= r.end));
}

// Validates and normalizes a list of ranges; numbers may not be assigned to two advisors of the same company
function normalizeAdvisorRanges(list, advisor) {
  if (!Array.isArray(list)) return { error: 'Los rangos deben ser una lista.' };
  const ranges = [];
  for (const raw of list) {
    if (String(raw || '').trim() === '') continue;
    const range = parseRange(raw);
    if (!range) return { error: `Rango inválido: "${raw}". Use el formato 10-20 o un número solo.` };
    ranges.push(range);
  }
  ranges.sort((a, b) => a.start - b.start);
  for (let i = 1; i < ranges.length; i++) {
    if (ranges[i].start <= ranges[i - 1].end) {
      return { error: `Los rangos ${rangeLabel(ranges[i - 1])} y ${rangeLabel(ranges[i])} se cruzan.` };
    }
  }
  const others = (db.advisors || []).filter(a => a.id !== advisor.id && a.companyId === advisor.companyId && a.mode === 'ASSIGNED');
  for (const other of others) {
    for (const theirs of (other.assignedTicketRanges || []).map(parseRange).filter(Boolean)) {
      const clash = ranges.find(r => r.start <= theirs.end && theirs.start <= r.end);
      if (clash) {
        return { error: `Los números ${rangeLabel(clash)} se cruzan con ${rangeLabel(theirs)}, asignado a ${other.name}.` };
      }
    }
  }
  return { ranges: ranges.map(rangeLabel) };
}

// The advisor asks the admin for more numbers; the admin answers by assigning more or discarding it
app.post('/api/advisors/me/range-request', requireRole('asesor'), (req, res) => {
  const advisor = req.auth.record;
  const quantity = parseInt(req.body.quantity, 10);
  if (!quantity || quantity < 1 || quantity > 10000) {
    return res.status(400).json({ error: 'Indique cuántas boletas necesita.' });
  }
  advisor.rangeRequest = {
    quantity,
    note: String(req.body.note || '').trim().slice(0, 300),
    requestedAt: new Date().toISOString()
  };
  saveDB();
  res.json({ success: true, rangeRequest: advisor.rangeRequest });
});

app.delete('/api/advisors/:id/range-request', adminOnly, (req, res) => {
  const advisor = (db.advisors || []).find(a => a.id === req.params.id);
  if (!advisor) return res.status(404).json({ error: 'Asesor no encontrado' });
  advisor.rangeRequest = null;
  saveDB();
  res.json({ success: true });
});

// GET Advisors (Multi-tenant isolated)
app.get('/api/advisors', (req, res) => {
  // Admins and advisors only ever see their own company; the SuperAdmin may pick one with ?companyId=
  let targetCompanyId = req.query.companyId;
  if (req.auth && req.auth.role === 'admin') targetCompanyId = req.auth.record.id;
  if (req.auth && req.auth.role === 'asesor') targetCompanyId = req.auth.record.companyId;

  let list = db.advisors || [];
  if (targetCompanyId) {
    list = list.filter(a => a.companyId === targetCompanyId);
  }

  const advisorsWithStats = list.map(adv => {
    const advTickets = (db.tickets || []).filter(t => t.advisorId === adv.id);
    const totalSold = advTickets.filter(t => t.status === 'PAGADA' || t.status === 'ABONO_PARCIAL').length;
    const totalCollected = advTickets.reduce((sum, t) => sum + (t.totalPaid || 0), 0);
    const totalConfirmed = advTickets.filter(t => t.confirmedByAdmin).reduce((sum, t) => sum + (t.totalPaid || 0), 0);
    const pendingTurnIn = totalCollected - totalConfirmed;

    return {
      ...adv,
      // Rifas de su empresa en las que está autorizado
      raffleIds: (db.raffles || []).filter(r => r.companyId === adv.companyId && advisorAuthorizedInRaffle(r, adv.id)).map(r => r.id),
      hasPassword: !!adv.password,
      totalTicketsCount: advTickets.length,
      totalSold,
      totalCollected,
      totalConfirmed,
      pendingTurnIn
    };
  });

  res.json(advisorsWithStats);
});

// POST Create Advisor

/** Mensaje de bienvenida del asesor: enlace, usuario, contraseña y un pequeño instructivo. */
function advisorAccessMessage({ advisor, company, password, baseUrl, isReset }) {
  return [
    `🎉 *¡Bienvenido(a) a Rifa Master, ${advisor.name.split(' ')[0]}!*`,
    company && company.name ? `Empresa: *${company.name}*` : '',
    '',
    isReset ? 'Te generamos un acceso nuevo:' : 'Ya tienes tu cuenta de asesor:',
    `🔗 *Ingreso:* ${baseUrl}`,
    `👤 *Usuario:* ${advisor.username}`,
    `🔑 *Contraseña temporal:* ${password}`,
    '(Al entrar por primera vez el sistema te pedirá crear tu propia contraseña.)',
    `📱 *App Android:* ${baseUrl}/descargar-apk`,
    '',
    '📖 *Cómo usar tu cuenta de asesor*',
    '1️⃣ Entra al enlace, escribe tu usuario y contraseña y crea tu nueva clave.',
    '2️⃣ Arriba elige la *rifa* en la que vas a trabajar.',
    '3️⃣ En *Boletas* toca un número disponible: escribe los datos del comprador, el medio de venta y *aparta* la boleta o registra el pago.',
    '4️⃣ Para abonar, abre la boleta apartada y registra el abono en *efectivo* o *transferencia* (adjunta el comprobante).',
    '5️⃣ En *Mi Caja* ves el efectivo que tienes y lo que debes entregar al administrador. Entrégalo pronto: pasados 7 días te avisamos.',
    '6️⃣ En el *Dashboard* ves tus ventas y tus ganancias. La campana 🔔 te avisa de sorteos cercanos y pagos pendientes.',
    '',
    '⚠️ Guarda tu contraseña y no la compartas. ¡Mucho éxito en las ventas! 🍀'
  ].filter(l => l !== null).join('\n');
}

/** Envía el acceso del asesor por el WhatsApp de su empresa. Devuelve { sent, reason }. */
async function sendAdvisorAccess(req, advisor, company, password, isReset) {
  try {
    if (!advisor.phone) return { sent: false, reason: 'El asesor no tiene teléfono.' };
    const instance = whatsappService.getInstanceName({ role: 'admin', record: company || {} });
    const health = whatsappService.getHealth(instance);
    if (!health || health.state !== 'open') return { sent: false, reason: 'El WhatsApp de la empresa no está conectado.' };
    const proto = String(req.headers['x-forwarded-proto'] || req.protocol || 'https').split(',')[0];
    const baseUrl = `${proto}://${req.get('host')}`;
    await whatsappService.sendTextMessage(instance, advisor.phone, advisorAccessMessage({ advisor, company, password, baseUrl, isReset }), { origin: 'acceso-asesor' });
    return { sent: true };
  } catch (err) {
    return { sent: false, reason: `No se pudo enviar por WhatsApp: ${err.message}` };
  }
}

app.post('/api/advisors', adminOnly, async (req, res) => {
  const { name, email, username, password, status, phone, code, mode, assignedTicketRanges, companyId } = req.body;
  const advisorType = req.body.type;
  const policyError = security.validatePasswordPolicy(password);
  if (policyError) return res.status(400).json({ error: `Contraseña del asesor: ${policyError}` });
  const missing = [];
  if (!name || String(name).trim().length < 3) missing.push('nombre completo');
  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(email).trim())) missing.push('correo válido');
  if (!username || String(username).trim().length < 3) missing.push('usuario');
  if (!phone || String(phone).replace(/\D/g, '').length !== 10) missing.push('teléfono de 10 dígitos');
  if (!code || String(code).replace(/\D/g, '').length < 5) missing.push('cédula');
  if (!ADVISOR_TYPES.includes(advisorType)) missing.push('tipo de asesor (de punto, de calle o integral)');
  if (missing.length) return res.status(400).json({ error: `Falta: ${missing.join(', ')}.` });
  let targetCompanyId = req.auth && req.auth.role === 'admin' ? req.auth.record.id : companyId;
  if (!targetCompanyId && (db.companies || []).length > 0) {
    targetCompanyId = db.companies[0].id;
  }
  if (!targetCompanyId) targetCompanyId = 'comp-1';

  // Check if username/cédula is already taken within this specific company, or globally by superadmin/admin
  const advisorInCompanyTaken = v => (db.advisors || []).some(a => a.companyId === targetCompanyId && [a.username, a.code].some(x => x && normalize(x) === normalize(v)));
  if (isUsernameTaken(username) || advisorInCompanyTaken(username)) {
    return res.status(409).json({
      field: 'username',
      error: `El usuario "${String(username).trim()}" ya está registrado en esta empresa o en el sistema. Elija otro usuario.`
    });
  }
  if (advisorInCompanyTaken(code)) {
    return res.status(409).json({
      field: 'code',
      error: `La cédula ${String(code).trim()} ya está registrada para un asesor en esta empresa. Verifique el número.`
    });
  }

  const newAdvisor = {
    id: `adv-${Date.now()}`,
    companyId: targetCompanyId,
    name: name || 'Nuevo Asesor',
    email: email || '',
    username: username || code || `ADV${Math.floor(10 + Math.random()*90)}`,
    password: security.hashPassword(password),
    mustChangePassword: true,
    status: status || 'ACTIVO',
    phone: phone || '',
    code: code || `ADV${Math.floor(10 + Math.random()*90)}`,
    mode: mode || 'POOL_GENERAL',
    type: advisorType,
    canRegisterExpenses: isOfficeAdvisorType(advisorType) && req.body.canRegisterExpenses === true,
    canViewCash: isOfficeAdvisorType(advisorType) && req.body.canViewCash === true,
    canManageAllTickets: isOfficeAdvisorType(advisorType) && req.body.canManageAllTickets === true,
    menuAccess: normalizeMenuAccess(req.body.menuAccess),
    assignedTicketRanges: [],
    createdAt: new Date().toISOString()
  };
  const checked = normalizeAdvisorRanges(assignedTicketRanges || [], newAdvisor);
  if (checked.error) return res.status(400).json({ error: checked.error });
  newAdvisor.assignedTicketRanges = checked.ranges;

  db.advisors.push(newAdvisor);

  if (Array.isArray(req.body.raffleIds)) {
    // El administrador eligió en qué rifas queda autorizado
    setAdvisorRaffles(newAdvisor, req.body.raffleIds);
  } else {
    // Sin elección: se autoriza en todas las rifas activas de la empresa (comportamiento anterior)
    (db.raffles || []).forEach(r => {
      if ((!r.companyId || r.companyId === targetCompanyId) && r.status === 'ACTIVA') {
        r.assignedAdvisorIds = (r.assignedAdvisorIds || []).filter(id => id !== NO_ADVISORS);
        if (!r.assignedAdvisorIds.includes(newAdvisor.id)) r.assignedAdvisorIds.push(newAdvisor.id);
      }
    });
  }

  saveDB();
  // Se le envía por WhatsApp el enlace, usuario, contraseña e instructivo
  const company = (db.companies || []).find(c => c.id === targetCompanyId);
  const access = await sendAdvisorAccess(req, newAdvisor, company, password, false);
  res.status(201).json({ ...newAdvisor, accessSent: access.sent, accessNote: access.reason || '' });
});

// POST Reenviar acceso: como la contraseña se guarda cifrada y no se puede leer, se genera una contraseña temporal NUEVA
// (el asesor la cambia al entrar) y se envía por WhatsApp con el enlace y el instructivo. Si WhatsApp no está conectado no se cambia nada.
app.post('/api/advisors/:id/send-access', adminOnly, async (req, res) => {
  const advisor = (db.advisors || []).find(a => a.id === req.params.id);
  if (!advisor) return res.status(404).json({ error: 'Asesor no encontrado' });
  if (req.auth.role === 'admin' && advisor.companyId !== req.auth.record.id) return res.status(404).json({ error: 'Asesor no encontrado' });
  if (!advisor.phone) return res.status(400).json({ error: 'El asesor no tiene teléfono registrado.' });
  const company = (db.companies || []).find(c => c.id === advisor.companyId);
  const instance = whatsappService.getInstanceName({ role: 'admin', record: company || {} });
  const health = whatsappService.getHealth(instance);
  if (!health || health.state !== 'open') return res.status(409).json({ error: 'El WhatsApp de la empresa no está conectado: no se envió nada y la contraseña actual no cambió.' });
  const alphabet = 'abcdefghjkmnpqrstuvwxyz';
  const tmp = 'Rifa' + Array.from({ length: 3 }, () => alphabet[require('crypto').randomInt(alphabet.length)]).join('') + String(require('crypto').randomInt(1000, 10000));
  const previousHash = advisor.password;
  const previousMust = advisor.mustChangePassword;
  advisor.password = security.hashPassword(tmp);
  advisor.mustChangePassword = true;
  const access = await sendAdvisorAccess(req, advisor, company, tmp, true);
  if (!access.sent) {
    advisor.password = previousHash;
    advisor.mustChangePassword = previousMust;
    return res.status(502).json({ error: `${access.reason} La contraseña actual no cambió.` });
  }
  saveDB();
  res.json({ ok: true, message: `Acceso enviado por WhatsApp a ${advisor.name}.` });
});

// PUT Update Advisor
app.put('/api/advisors/:id', adminOnly, (req, res) => {
  const { id } = req.params;
  const advisor = db.advisors.find(a => a.id === id && (req.auth.role === 'superadmin' || a.companyId === req.auth.record.id));
  if (!advisor) {
    return res.status(404).json({ error: 'Asesor no encontrado' });
  }

  let newRanges = null;
  if (req.body.assignedTicketRanges !== undefined) {
    const companyId = req.body.companyId !== undefined ? req.body.companyId : advisor.companyId;
    const checked = normalizeAdvisorRanges(req.body.assignedTicketRanges, { ...advisor, companyId });
    if (checked.error) return res.status(400).json({ error: checked.error });
    newRanges = checked.ranges;
  }

  if (req.body.companyId !== undefined && req.auth.role === 'superadmin') advisor.companyId = req.body.companyId;
  if (req.body.name !== undefined) advisor.name = req.body.name;
  if (req.body.email !== undefined) advisor.email = req.body.email;
  if (req.body.username !== undefined) advisor.username = req.body.username;
  // Password only changes when a new one is sent (it is never read back)
  if (typeof req.body.password === 'string' && req.body.password.trim() !== '') {
    const policyError = security.validatePasswordPolicy(req.body.password);
    if (policyError) return res.status(400).json({ error: `Contraseña del asesor: ${policyError}` });
    advisor.password = security.hashPassword(req.body.password);
    advisor.mustChangePassword = true;
  }
  if (req.body.status !== undefined) advisor.status = req.body.status;
  if (req.body.deletionReason !== undefined) advisor.deletionReason = req.body.deletionReason;
  if (req.body.phone !== undefined) advisor.phone = req.body.phone;
  if (req.body.code !== undefined) advisor.code = req.body.code;
  if (req.body.mode !== undefined) advisor.mode = req.body.mode;
  if (req.body.type !== undefined && req.body.type !== advisorTypeOf(advisor)) {
    if (!ADVISOR_TYPES.includes(req.body.type)) return res.status(400).json({ error: 'Tipo de asesor no válido.' });
    // Las ventas ya hechas conservan su zona: se fija con el tipo anterior antes de cambiarlo
    const previousType = advisorTypeOf(advisor);
    for (const t of db.tickets || []) {
      if (t.advisorId === advisor.id && !SALE_ZONES.includes(t.saleZone) && t.status !== 'DISPONIBLE') {
        t.saleZone = previousType === 'PUNTO' ? 'OFICINA' : 'CALLE';
      }
    }
    advisor.type = req.body.type;
    if (!db.auditLogs) db.auditLogs = [];
    db.auditLogs.push({
      id: `audit-${Date.now()}`, type: 'ADVISOR_TYPE', companyId: advisor.companyId, targetId: advisor.id, targetName: advisor.name,
      detail: `Tipo de asesor ${previousType} → ${advisor.type} (las ventas anteriores conservan su zona)`, by: actorName(req), date: new Date().toISOString()
    });
  }
  if (Array.isArray(req.body.raffleIds)) setAdvisorRaffles(advisor, req.body.raffleIds);
  if (req.body.canRegisterExpenses !== undefined) advisor.canRegisterExpenses = req.body.canRegisterExpenses === true;
  if (req.body.canViewCash !== undefined) advisor.canViewCash = req.body.canViewCash === true;
  if (req.body.canManageAllTickets !== undefined) advisor.canManageAllTickets = req.body.canManageAllTickets === true;
  if (req.body.menuAccess !== undefined) advisor.menuAccess = normalizeMenuAccess(req.body.menuAccess);
  // El asesor de calle no maneja la caja de la oficina
  if (!isOfficeAdvisorType(advisorTypeOf(advisor))) { advisor.canRegisterExpenses = false; advisor.canViewCash = false; advisor.canManageAllTickets = false; }
  if (newRanges) {
    const size = list => list.map(parseRange).filter(Boolean).reduce((sum, r) => sum + r.end - r.start + 1, 0);
    // Assigning more numbers answers the advisor's pending request
    if (advisor.rangeRequest && size(newRanges) > size(advisor.assignedTicketRanges || [])) advisor.rangeRequest = null;
    advisor.assignedTicketRanges = newRanges;
  }

  saveDB();
  res.json(advisor);
});

// DELETE Advisor (Only allowed if no sales/records exist)
app.delete('/api/advisors/:id', adminOnly, (req, res) => {
  const { id } = req.params;
  const { reason } = req.body || {};
  const advisor = db.advisors.find(a => a.id === id && (req.auth.role === 'superadmin' || a.companyId === req.auth.record.id));
  if (!advisor) {
    return res.status(404).json({ error: 'Asesor no encontrado' });
  }

  const advTickets = db.tickets.filter(t => t.advisorId === id);
  const totalSold = advTickets.filter(t => t.status === 'PAGADA' || t.status === 'ABONO_PARCIAL').length;
  const totalCollected = advTickets.reduce((sum, t) => sum + (t.totalPaid || 0), 0);

  if (totalSold > 0 || totalCollected > 0) {
    return res.status(400).json({ error: 'No se puede eliminar un usuario con ventas o abonos registrados. Por favor, inhabilítelo.' });
  }

  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({
    id: `audit-${Date.now()}`,
    type: 'DELETE_ADVISOR',
    targetId: advisor.id,
    targetName: advisor.name,
    reason: reason || 'Eliminación voluntaria por administración',
    date: new Date().toISOString()
  });

  db.advisors = db.advisors.filter(a => a.id !== id);
  saveDB();
  res.json({ message: 'Asesor eliminado correctamente' });
});

// DELETE Winner / Draw Record
app.delete('/api/winners/:id', adminOnly, (req, res) => {
  const { id } = req.params;
  const { reason } = req.body || {};
  const winner = db.winners.find(w => w.id === id);
  if (!winner) {
    return res.status(404).json({ error: 'Registro de sorteo/ganador no encontrado' });
  }

  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({
    id: `audit-${Date.now()}`,
    type: 'DELETE_WINNER_DRAW',
    targetId: winner.id,
    drawName: winner.drawName,
    winningNumber: winner.winningNumber,
    reason: reason || 'Eliminación del sorteo tras informe de auditoría PDF',
    date: new Date().toISOString()
  });

  db.winners = db.winners.filter(w => w.id !== id);
  saveDB();
  res.json({ message: 'Registro de sorteo eliminado correctamente' });
});

// POST Register Winner / Draw Number
const WINNING_POSITIONS = ['ULTIMAS', 'PRIMERAS', 'MEDIO'];

/** Raffle number taken from the lottery result according to the raffle's rule. */
function deriveWinningNumber(raffle, input) {
  const digits = raffle.digits || 4;
  const clean = String(input || '').replace(/\D/g, '');
  // The admin may type the raffle number directly or the full lottery result
  if (clean.length <= digits) return clean.padStart(digits, '0');
  const position = raffle.winningDigitsPosition || 'ULTIMAS';
  if (position === 'PRIMERAS') return clean.slice(0, digits);
  if (position === 'MEDIO') {
    const start = Math.floor((clean.length - digits) / 2);
    return clean.slice(start, start + digits);
  }
  return clean.slice(-digits);
}

function sortedDigits(value) {
  return String(value).split('').sort().join('');
}

function normalizeWinningConfig(body, digits) {
  const out = {};
  if (body.winningDigitsPosition !== undefined) {
    let position = WINNING_POSITIONS.includes(body.winningDigitsPosition) ? body.winningDigitsPosition : 'ULTIMAS';
    if (position === 'MEDIO' && digits !== 2) position = 'ULTIMAS'; // "middle" only applies to 2 digits
    out.winningDigitsPosition = position;
  }
  if (body.allowCombined !== undefined) out.allowCombined = body.allowCombined === true || body.allowCombined === 'true';
  return out;
}

/** Ticket of a raffle that holds [numStr] (exact or, if allowed, combinado) among those that qualify. */
function findWinningTicket(raffle, numStr, qualifies) {
  const raffleTickets = db.tickets.filter(t => t.raffleId === raffle.id);
  let matchType = 'EXACTO';
  let ticket = raffleTickets.find(t => (t.numbers || []).includes(numStr));
  if ((!ticket || !qualifies(ticket)) && raffle.allowCombined) {
    const combined = raffleTickets.find(t => qualifies(t) && (t.numbers || []).some(n => n !== numStr && sortedDigits(n) === sortedDigits(numStr)));
    if (combined) { ticket = combined; matchType = 'COMBINADO'; }
  }
  return { ticket, matchType };
}

function winnerDetailsOf(ticket, minRequiredAmount, qualified) {
  return {
    ticketId: ticket.id,
    ticketNumber: ticket.ticketNumber,
    numbers: ticket.numbers || [],
    buyerName: ticket.buyerName,
    buyerPhone: ticket.buyerPhone,
    buyerDocument: ticket.buyerDocument || '',
    advisorName: ticket.advisorName,
    status: ticket.status,
    totalPaid: ticket.totalPaid || 0,
    minRequiredAmount,
    insufficientAbono: !qualified,
    assignedDate: ticket.assignedDate,
    abonosSummary: (ticket.abonos || []).map(a => ({ date: a.date, amount: a.amount, sellerName: a.sellerName, note: a.note }))
  };
}

/**
 * Main draw (gran premio): the ticket must be fully paid. Only one per raffle; if nobody wins
 * (number not sold or not fully paid) the result is kept with the reason.
 */
function registerMainDraw(req, res, raffle) {
  const { winningNumber, drawDate, prizeDescription, prizeAmount, photoUrl } = req.body;
  // A new main draw is only possible when every previous one was played again on another date
  const previous = (db.winners || []).filter(w => w.raffleId === raffle.id && w.drawType === 'PRINCIPAL');
  const open = previous.find(w => !(w.decision && w.decision.type === 'REPROGRAMADO'));
  if (open) {
    return res.status(409).json({
      error: open.isWinner ? 'Esta rifa ya tiene ganador del gran premio.'
        : open.decision ? 'El gran premio de esta rifa se cerró sin ganador.'
        : 'El último resultado quedó sin ganador: decida primero si se vuelve a jugar en otra fecha o se cierra.'
    });
  }
  const lotteryResult = String(winningNumber || '').trim();
  if (!/\d/.test(lotteryResult)) return res.status(400).json({ error: 'Ingrese el número o resultado de la lotería.' });
  const numStr = deriveWinningNumber(raffle, lotteryResult);
  const price = Number(raffle.ticketPrice) || 0;
  const fullyPaid = t => t.status !== 'DISPONIBLE' && (t.totalPaid || 0) >= (t.price || price) && (t.totalPaid || 0) > 0;
  const { ticket, matchType } = findWinningTicket(raffle, numStr, fullyPaid);
  const isWinner = !!ticket && fullyPaid(ticket);
  const noWinnerReason = isWinner ? '' : !ticket ? 'El número no fue vendido.'
    : ticket.status === 'DISPONIBLE' ? 'El número no fue vendido.'
    : `La boleta no estaba pagada en su totalidad (abonado $${Math.round(ticket.totalPaid || 0).toLocaleString('es-CO')} de $${Math.round(ticket.price || price).toLocaleString('es-CO')}).`;
  const amount = parseFloat(prizeAmount) || 0;
  const record = {
    id: `win-${Date.now()}`,
    raffleId: raffle.id,
    drawType: 'PRINCIPAL',
    drawName: previous.length ? `Gran premio (intento ${previous.length + 1})` : 'Gran premio',
    attempt: previous.length + 1,
    drawDate: drawDate || raffle.mainDrawDate || new Date().toISOString(),
    lotteryName: mainLotteryOf(raffle),
    winningNumber: numStr,
    lotteryResult,
    matchType: isWinner ? matchType : null,
    prizeDescription: String(prizeDescription || '').trim().slice(0, 300),
    basePrizeAmount: amount,
    previousAccumulatedAmount: 0,
    totalPrizePaid: amount,
    prizeAmount: amount,
    isWinner,
    accumulated: false,
    noWinnerReason,
    winnerDetails: ticket ? winnerDetailsOf(ticket, ticket.price || price, isWinner) : null,
    photoUrl: photoUrl || '',
    registeredBy: req.auth.role === 'superadmin' ? 'SuperAdministrador' : (req.auth.record.adminName || 'Administrador'),
    createdAt: new Date().toISOString()
  };
  db.winners.unshift(record);
  saveDB();
  res.status(201).json(record);
}

app.post('/api/winners', adminOnly, (req, res) => {
  const { raffleId, winningNumber, drawName, drawDate, prizeAmount, photoUrl } = req.body;

  const raffle = db.raffles.find(r => r.id === (raffleId || (db.raffles[0] && db.raffles[0].id)));
  if (!raffle) {
    return res.status(404).json({ error: 'Sorteo no encontrado.' });
  }
  if (!canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Sorteo no encontrado.' });
  if (req.body.drawType === 'PRINCIPAL') return registerMainDraw(req, res, raffle);
  if (raffle.hasWeeklyDraws === false) {
    return res.status(400).json({ error: 'Este sorteo tiene deshabilitados los sorteos semanales. Habilítelos en "Gestionar Sorteo" para registrar ganadores semanales.' });
  }
  const lotteryResult = (winningNumber || '').toString().trim();
  if (!/\d/.test(lotteryResult)) return res.status(400).json({ error: 'Ingrese el número o resultado de la lotería.' });
  // Raffle number according to the rule (last / first / middle digits of the lottery result)
  const numStr = deriveWinningNumber(raffle, lotteryResult);
  const rawNumStr = numStr;

  // Minimum paid to participate; same defaults as the app (50% of the price) when not configured
  const reqAbono = weeklyMinAbonoOf(raffle, weeklyPrizeForDraw(raffle, drawName, prizeAmount));
  const raffleTickets = db.tickets.filter(t => t.raffleId === raffle.id);
  const qualifies = t => t.status !== 'DISPONIBLE' && (t.totalPaid || 0) >= reqAbono;

  // Exact match first; if it does not win and the raffle allows "combinado", the same digits
  // in any order also win (e.g. 21 for 12)
  let matchType = 'EXACTO';
  let matchingTicket = raffleTickets.find(t => t.numbers.includes(numStr));
  if ((!matchingTicket || !qualifies(matchingTicket)) && raffle.allowCombined) {
    const combined = raffleTickets.find(t => qualifies(t) && t.numbers.some(n => n !== numStr && sortedDigits(n) === sortedDigits(numStr)));
    if (combined) {
      matchingTicket = combined;
      matchType = 'COMBINADO';
    }
  }

  const isWinner = !!matchingTicket && qualifies(matchingTicket);

  let winnerDetails = null;
  if (matchingTicket) {
    let abonosSummary = [];
    if (matchingTicket.abonos && matchingTicket.abonos.length > 0) {
      abonosSummary = matchingTicket.abonos.map(a => ({
        date: a.date,
        amount: a.amount,
        sellerName: a.sellerName,
        note: a.note
      }));
    } else {
      abonosSummary = [{
        date: matchingTicket.assignedDate || new Date().toISOString(),
        amount: matchingTicket.totalPaid || 0,
        sellerName: matchingTicket.advisorName || '',
        note: 'Pago / Abono Inicial de Venta'
      }];
    }

    winnerDetails = {
      ticketNumber: matchingTicket.ticketNumber,
      buyerName: matchingTicket.buyerName,
      buyerPhone: matchingTicket.buyerPhone,
      advisorName: matchingTicket.advisorName,
      status: matchingTicket.status,
      totalPaid: matchingTicket.totalPaid || 0,
      minRequiredAmount: reqAbono,
      insufficientAbono: !isWinner,
      assignedDate: matchingTicket.assignedDate,
      abonosSummary: abonosSummary
    };
  }

  // Previous accumulated pot: only this raffle's draws (another raffle/company's pot never mixes in)
  const activeAccumulatedPrizes = db.winners.filter(w => w.accumulated && w.raffleId === raffle.id);
  const prevAccumulatedPot = activeAccumulatedPrizes.reduce((sum, w) => sum + (parseFloat(w.basePrizeAmount || w.prizeAmount) || 0), 0);

  const basePrizeAmount = prizeAmount ? parseFloat(prizeAmount) : 1000000;
  const totalPrizePaid = isWinner ? (basePrizeAmount + prevAccumulatedPot) : basePrizeAmount;

  const record = {
    id: `win-${Date.now()}`,
    raffleId: raffle ? raffle.id : 'raf-1',
    drawType: 'SEMANAL',
    drawName: drawName || 'Sorteo Semanal',
    drawDate: drawDate || new Date().toISOString(),
    winningNumber: rawNumStr,
    lotteryResult,
    matchType: isWinner ? matchType : null,
    basePrizeAmount: basePrizeAmount,
    previousAccumulatedAmount: isWinner ? prevAccumulatedPot : 0,
    totalPrizePaid: totalPrizePaid,
    prizeAmount: totalPrizePaid,
    isWinner, // true if sold and min abono met, false if accumulated
    accumulated: !isWinner,
    winnerDetails,
    photoUrl: photoUrl || '',
    createdAt: new Date().toISOString()
  };

  // If won, mark previous accumulated draws as consumed so they don't get re-accumulated
  if (isWinner) {
    db.winners.forEach(w => {
      if (w.accumulated && w.raffleId === raffle.id) {
        w.accumulated = false;
        w.accumulationReason = `Acumulado entregado en sorteo #${rawNumStr}`;
      }
    });
  }

  db.winners.unshift(record);
  saveDB();
  res.status(201).json(record);
});

// Main draw without winner: play it again on another date (and lottery) or close it without winner
app.put('/api/winners/:id/main-decision', adminOnly, (req, res) => {
  const record = (db.winners || []).find(w => w.id === req.params.id && w.drawType === 'PRINCIPAL');
  const raffle = record && (db.raffles || []).find(r => r.id === record.raffleId);
  if (!record || !raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Registro no encontrado.' });
  if (record.isWinner) return res.status(400).json({ error: 'Este sorteo tuvo ganador.' });
  if (record.decision) return res.status(400).json({ error: 'Ya se tomó una decisión para este resultado.' });
  const body = req.body || {};
  const note = String(body.note || '').trim().slice(0, 300);
  const by = actorName(req);
  const at = new Date().toISOString();
  if (body.decision === 'REPROGRAMAR') {
    const day = String(body.newDate || '').trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return res.status(400).json({ error: 'Indique la nueva fecha del sorteo.' });
    if (day <= todayColombia()) return res.status(400).json({ error: 'La nueva fecha debe ser posterior a hoy.' });
    let lottery = null;
    if (body.lotteryName !== undefined && String(body.lotteryName).trim()) {
      const checked = checkRaffleLottery(body.lotteryName, raffle.mainLotteryName, 'lotería del sorteo principal');
      if (checked.error) return res.status(400).json({ error: checked.error });
      lottery = checked.name;
    }
    record.decision = {
      type: 'REPROGRAMADO', previousDate: raffle.mainDrawDate, newDate: day,
      previousLottery: mainLotteryOf(raffle), newLottery: lottery || mainLotteryOf(raffle), note, by, at
    };
    raffle.mainDrawDate = `${day}T12:00:00.000`;
    if (lottery) raffle.mainLotteryName = lottery;
  } else if (body.decision === 'CERRAR') {
    if (note.length < 5) return res.status(400).json({ error: 'Explique por qué se cierra el sorteo sin ganador.' });
    record.decision = { type: 'CERRADO', note, by, at };
  } else {
    return res.status(400).json({ error: 'Decisión no válida.' });
  }
  saveDB();
  res.json({ record, raffle });
});

// Records who received a prize (main or weekly): name, ID number, date and note
app.put('/api/winners/:id/delivery', adminOnly, (req, res) => {
  const winner = (db.winners || []).find(w => w.id === req.params.id);
  const raffle = winner && (db.raffles || []).find(r => r.id === winner.raffleId);
  if (!winner || !raffle || !canAccessRaffle(req, raffle)) return res.status(404).json({ error: 'Registro no encontrado.' });
  if (!winner.isWinner) return res.status(400).json({ error: 'Este sorteo no tuvo ganador: no hay premio que entregar.' });
  const body = req.body || {};
  if (body.cancel === true) {
    winner.prizeDelivery = null;
    saveDB();
    return res.json(winner);
  }
  const receivedBy = String(body.receivedBy || '').trim().slice(0, 100);
  if (receivedBy.length < 3) return res.status(400).json({ error: 'Indique el nombre de quien recibió el premio.' });
  const deliveredOn = String(body.deliveredOn || '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(deliveredOn)) return res.status(400).json({ error: 'Indique la fecha de entrega.' });
  winner.prizeDelivery = {
    receivedBy,
    receivedDocument: String(body.receivedDocument || '').replace(/[^0-9A-Za-z]/g, '').slice(0, 20),
    deliveredOn,
    method: String(body.method || '').trim().slice(0, 60),
    note: String(body.note || '').trim().slice(0, 300),
    registeredBy: req.auth.role === 'superadmin' ? 'SuperAdministrador' : (req.auth.record.adminName || 'Administrador'),
    registeredAt: new Date().toISOString()
  };
  saveDB();
  res.json(winner);
});

// GET Winners (Multi-tenant isolated)
app.get('/api/winners', (req, res) => {
  const { raffleId, companyId } = req.query;
  let targetCompanyId = companyId;
  if (!targetCompanyId && req.auth) {
    if (req.auth.role === 'admin') targetCompanyId = req.auth.record.id;
    if (req.auth.role === 'asesor') targetCompanyId = req.auth.record.companyId;
  }

  let winners = db.winners || [];
  if (targetCompanyId) {
    const companyRaffleIds = (db.raffles || []).filter(r => !r.companyId || r.companyId === targetCompanyId).map(r => r.id);
    winners = winners.filter(w => companyRaffleIds.includes(w.raffleId));
  }
  if (raffleId) {
    winners = winners.filter(w => w.raffleId === raffleId);
  }
  res.json(winners);
});

// GET Dashboard Metrics Summary (Multi-tenant isolated)
app.get('/api/dashboard', (req, res) => {
  const { companyId } = req.query;
  let targetCompanyId = companyId;
  if (!targetCompanyId && req.auth) {
    if (req.auth.role === 'admin') targetCompanyId = req.auth.record.id;
    if (req.auth.role === 'asesor') targetCompanyId = req.auth.record.companyId;
  }

  const availableRaffles = targetCompanyId
    ? (db.raffles || []).filter(r => !r.companyId || r.companyId === targetCompanyId)
    : (db.raffles || []);

  const raffle = availableRaffles[0];
  const activeTickets = db.tickets.filter(t => t.raffleId === (raffle ? raffle.id : ''));

  const totalTickets = activeTickets.length;
  const soldPaidCount = activeTickets.filter(t => t.status === 'PAGADA').length;
  const partialAbonoCount = activeTickets.filter(t => t.status === 'ABONO_PARCIAL').length;
  const availableCount = activeTickets.filter(t => t.status === 'DISPONIBLE').length;

  const totalMoneyCollected = activeTickets.reduce((sum, t) => sum + (t.totalPaid || 0), 0);
  const totalMoneyConfirmed = activeTickets.filter(t => t.confirmedByAdmin).reduce((sum, t) => sum + (t.totalPaid || 0), 0);
  const totalMoneyPendingTurnIn = totalMoneyCollected - totalMoneyConfirmed;
  const totalPotentialRevenue = totalTickets * (raffle ? raffle.ticketPrice : 50000);

  const companyRaffleIds = availableRaffles.map(r => r.id);
  const accumulatedPrizes = (db.winners || []).filter(w => w.accumulated && companyRaffleIds.includes(w.raffleId));

  res.json({
    raffle,
    totalTickets,
    soldPaidCount,
    partialAbonoCount,
    availableCount,
    totalMoneyCollected,
    totalMoneyConfirmed,
    totalMoneyPendingTurnIn,
    totalPotentialRevenue,
    progressPercentage: totalTickets > 0 ? (((soldPaidCount + partialAbonoCount) / totalTickets) * 100).toFixed(1) : 0,
    accumulatedCount: accumulatedPrizes.length,
    accumulatedTotalAmount: accumulatedPrizes.reduce((sum, w) => sum + (w.prizeAmount || 0), 0)
  });
});

// ---------------------------------------------------------------------------
// Tipos de asesor y zona de venta
//  • PUNTO: asesor de oficina/punto. NO comisiona (todas sus ventas son de oficina).
//  • CALLE: asesor de calle. Comisiona en todas sus ventas.
//  • INTEGRAL: en cada venta se indica si fue en OFICINA (no comisiona) o en CALLE (comisiona).
// La zona de la venta se guarda en la boleta (ticket.saleZone). Sin zona guardada se deduce del tipo del asesor
// (los asesores existentes quedan como CALLE: todo sigue comisionando como antes).
// ---------------------------------------------------------------------------
const ADVISOR_TYPES = ['PUNTO', 'CALLE', 'INTEGRAL'];
const advisorTypeOf = adv => (adv && ADVISOR_TYPES.includes(adv.type) ? adv.type : 'CALLE');
// Solo el asesor de punto o integral (de oficina) puede tener permiso para registrar gastos y ver la caja
const isOfficeAdvisorType = type => type === 'PUNTO' || type === 'INTEGRAL';
// Partes del menú del administrador que se le pueden dar a un asesor (solo lectura)
const ADVISOR_MENU_KEYS = ['proyeccion', 'pagos'];
const normalizeMenuAccess = list => [...new Set((Array.isArray(list) ? list : []).map(String).filter(k => ADVISOR_MENU_KEYS.includes(k)))];
const advisorRecordOf = req => (req.auth && req.auth.role === 'asesor' ? (db.advisors || []).find(a => a.id === req.auth.record.id) : null);
// Asesor de oficina o integral con permiso de ver todas las boletas y recibir pagos como ayuda del administrador
const isTicketAssistant = adv => !!(adv && adv.status !== 'INHABILITADO' && adv.canManageAllTickets === true && isOfficeAdvisorType(advisorTypeOf(adv)));
// Pasa el administrador, o el asesor activo al que se le dio esa parte del menú
const adminOrAdvisorMenu = key => (req, res, next) => {
  const role = req.auth && req.auth.role;
  if (role === 'admin' || role === 'superadmin') return next();
  const adv = advisorRecordOf(req);
  if (adv && adv.status !== 'INHABILITADO' && normalizeMenuAccess(adv.menuAccess).includes(key)) return next();
  return res.status(403).json({ error: 'No tiene permisos para realizar esta acción.' });
};
const SALE_ZONES = ['OFICINA', 'CALLE'];

// Tipo de venta de una boleta que no lo tiene guardado: sin asesor o asesor de punto = OFICINA, asesor de calle = CALLE;
// el integral elige en cada venta, así que sin dato no se adivina (null)
function inferredSaleZone(ticket, advisor) {
  if (SALE_ZONES.includes(ticket.saleZone)) return ticket.saleZone;
  if (!advisor) return 'OFICINA';
  const type = advisorTypeOf(advisor);
  if (type === 'PUNTO') return 'OFICINA';
  if (type === 'CALLE') return 'CALLE';
  return null;
}

function ticketZoneOf(ticket, advisor) {
  if (SALE_ZONES.includes(ticket.saleZone)) return ticket.saleZone;
  return advisorTypeOf(advisor) === 'PUNTO' ? 'OFICINA' : 'CALLE';
}

/**
 * Comisión de un asesor en una rifa. Solo cuentan las ventas de CALLE; las de oficina/punto no comisionan.
 * rules = { commType, commVal, tiers }. Es el único lugar donde se calcula (ranking, liquidación y abonos usan esto).
 */
function computeAdvisorCommission(rules, adv, raffleTickets) {
  const { commType, commVal, tiers } = rules;
  const type = advisorTypeOf(adv);
  const advTickets = raffleTickets.filter(t =>
    t.advisorId === adv.id ||
    (t.advisorName && t.advisorName.trim().toLowerCase() === adv.name.trim().toLowerCase()) ||
    (adv.code && t.advisorName && t.advisorName.includes(adv.code))
  );
  const counts = t => t.status === 'PAGADA' || t.status === 'CONFIRMADA' || t.status === 'ABONO_PARCIAL';
  const totalTicketsSold = advTickets.filter(counts).length;
  // Boletas del asesor sin importar si están apartadas, abonadas o pagadas
  const ticketsReserved = advTickets.filter(t => t.status === 'RESERVADA').length;
  const ticketsPartial = advTickets.filter(t => t.status === 'ABONO_PARCIAL').length;
  const ticketsPaid = advTickets.filter(t => t.status === 'PAGADA' || t.status === 'CONFIRMADA').length;
  const totalCollected = advTickets.reduce((sum, t) => sum + (t.totalPaid || 0), 0);

  const street = advTickets.filter(t => ticketZoneOf(t, adv) === 'CALLE');
  const office = advTickets.filter(t => ticketZoneOf(t, adv) === 'OFICINA');
  const streetSold = street.filter(counts).length;
  const streetCollected = street.reduce((sum, t) => sum + (t.totalPaid || 0), 0);
  const officeSold = office.filter(counts).length;
  const officeCollected = office.reduce((sum, t) => sum + (t.totalPaid || 0), 0);

  // En comisión por PORCENTAJE: el porcentaje del rango completo se gana sobre lo recaudado en boletas PAGADAS; sobre lo recaudado en boletas
  // solo ABONADAS se gana la MITAD del porcentaje (pasa al completo cuando la boleta se paga).
  const isPaidT = t => t.status === 'PAGADA' || t.status === 'CONFIRMADA';
  const streetPaidCollected = street.filter(isPaidT).reduce((sum, t) => sum + (t.totalPaid || 0), 0);
  const streetPartialCollected = street.filter(t => t.status === 'ABONO_PARCIAL').reduce((sum, t) => sum + (t.totalPaid || 0), 0);
  const percentEarned = rate => (streetPaidCollected * rate + streetPartialCollected * rate / 2) / 100;

  let commissionEarned = 0;
  let activeTier = null;
  let tierDescription = '';
  // Tarifa vigente (la del rango actual, o la base) para calcular lo que AÚN no se ha ganado
  let rateType = commType === 'VALOR_FIJO' ? 'VALOR_FIJO' : 'PORCENTAJE';
  let rateValue = commVal;

  if (type === 'PUNTO') {
    tierDescription = 'Asesor de punto: no comisiona';
  } else if (commType === 'ESCALONADO' && tiers) {
    const sortedTiers = [...tiers].sort((a, b) => (Number(a.min || a.minBoletas) || 0) - (Number(b.min || b.minBoletas) || 0));
    // El rango se define por las boletas de calle que tiene el asesor (apartadas + abonadas + pagadas), no solo las pagadas:
    // con 21 o más ya comisiona el porcentaje del siguiente rango sobre TODO lo recaudado (no solo sobre lo nuevo).
    const streetHeld = street.filter(t => ['RESERVADA', 'ABONO_PARCIAL', 'PAGADA', 'CONFIRMADA'].includes(t.status)).length;
    for (const t of sortedTiers) {
      if (streetHeld >= (Number(t.min || t.minBoletas) || 0)) activeTier = t;
    }
    if (activeTier) {
      const rate = Number(activeTier.rate) || 0;
      rateType = (activeTier.type || 'PORCENTAJE') === 'VALOR_FIJO' ? 'VALOR_FIJO' : 'PORCENTAJE';
      rateValue = rate;
      const maxStr = (activeTier.max !== null && activeTier.max !== undefined && String(activeTier.max).trim() !== '') ? ` a ${activeTier.max}` : ' o más';
      if ((activeTier.type || 'PORCENTAJE') === 'VALOR_FIJO') {
        commissionEarned = streetHeld * rate;
        tierDescription = `Rango (${activeTier.min}${maxStr} boletas): $${rate.toLocaleString('es-CO')} COP/boleta`;
      } else {
        commissionEarned = percentEarned(rate);
        tierDescription = `Rango (${activeTier.min}${maxStr} boletas): ${rate}% si está pagada completa • ${rate / 2}% si está abonada`;
      }
    } else {
      commissionEarned = percentEarned(commVal);
      tierDescription = `${commVal}% base`;
    }
  } else if (commType === 'VALOR_FIJO') {
    commissionEarned = streetSold * commVal;
    tierDescription = `$${commVal.toLocaleString('es-CO')} COP por boleta`;
  } else {
    commissionEarned = percentEarned(commVal);
    tierDescription = `${commVal}% si está pagada completa • ${commVal / 2}% si está abonada`;
  }
  if (type === 'INTEGRAL' && officeSold > 0) tierDescription += ` • ${officeSold} de oficina sin comisión`;

  // Lo que todavía NO se ha ganado: boletas de calle apartadas o con abono parcial que aún no están pagadas.
  //  • Porcentaje: el % vigente sobre el saldo que falta cobrar de esas boletas.
  //  • Valor fijo por boleta: cada boleta apartada (las abonadas ya cuentan como vendidas) y todavía sin comisión.
  let pendingToEarn = 0;
  let pendingBalance = 0;
  let pendingTicketsCount = 0;
  if (type !== 'PUNTO') {
    for (const t of street) {
      if (t.status !== 'RESERVADA' && t.status !== 'ABONO_PARCIAL') continue;
      const balance = Math.max(0, (Number(t.price) || 0) - (Number(t.totalPaid) || 0));
      if (balance <= 0) continue;
      pendingTicketsCount++;
      pendingBalance += balance;
      // Cuando la boleta se pague gana el porcentaje completo sobre su precio; lo que ya gana por el abono es la mitad
      if (rateType === 'PORCENTAJE') pendingToEarn += ((Number(t.price) || 0) * rateValue - (t.status === 'ABONO_PARCIAL' ? (Number(t.totalPaid) || 0) * rateValue / 2 : 0)) / 100;
      else if (t.status === 'RESERVADA') pendingToEarn += rateValue;
    }
  }

  return {
    pendingToEarn, pendingBalance, pendingTicketsCount, rateType, rateValue,
    ticketsReserved, ticketsPartial, ticketsPaid, ticketsHeld: ticketsReserved + ticketsPartial + ticketsPaid,
    type, advTickets, totalTicketsSold, totalCollected, commissionEarned, activeTier, tierDescription,
    streetSold, streetCollected, streetPaidCollected, streetPartialCollected, officeSold, officeCollected,
    zoneUndefined: type === 'INTEGRAL' ? advTickets.filter(t => !SALE_ZONES.includes(t.saleZone)).length : 0
  };
}

// GET Analítica de ventas y proyección de una rifa (solo administrador): ventas por día y por día de la semana, ritmo promedio
// y cuánto se proyecta vender hasta el sorteo. Días en calendario de Colombia.
app.get('/api/analytics/sales', adminOrAdvisorMenu('proyeccion'), (req, res) => {
  const { raffle } = commissionScope(req, req.query.raffleId);
  if (!raffle) return res.status(404).json({ error: 'Rifa no encontrada' });
  const DAY = 24 * 3600 * 1000;
  const dayMs = d => Date.parse(`${d}T00:00:00Z`);
  const tickets = (db.tickets || []).filter(t => t.raffleId === raffle.id);
  const price = Number(raffle.ticketPrice) || 0;
  const sold = tickets.filter(t => t.status !== 'DISPONIBLE' && t.status !== 'ANULADA');
  const perDay = new Map(); // día -> { tickets, money }
  const bump = (d, k, v) => { if (!d) return; const e = perDay.get(d) || { tickets: 0, money: 0 }; e[k] += v; perDay.set(d, e); };
  const ticketDay = t => { const ms = Date.parse(t.assignedDate || ''); return isNaN(ms) ? null : colombiaDay(ms); };
  sold.forEach(t => bump(ticketDay(t), 'tickets', 1));
  tickets.forEach(t => (t.abonos || []).forEach(a => { const ms = Date.parse(a.date || ''); if (!isNaN(ms) && Number(a.amount) > 0) bump(colombiaDay(ms), 'money', Number(a.amount)); }));

  const today = colombiaDay(Date.now());
  const days = [...perDay.keys()].sort();
  const first = days[0] || today;
  const spanDays = Math.max(1, Math.round((dayMs(today) - dayMs(first)) / DAY) + 1);
  const daily = [];
  let cumTickets = 0, cumMoney = 0;
  for (let i = 0; i < spanDays; i++) {
    const d = new Date(dayMs(first) + i * DAY).toISOString().slice(0, 10);
    const e = perDay.get(d) || { tickets: 0, money: 0 };
    cumTickets += e.tickets; cumMoney += e.money;
    daily.push({ date: d, tickets: e.tickets, money: e.money, cumTickets, cumMoney });
  }
  // Por día de la semana (0 = domingo): total y promedio por cada vez que ese día ocurrió
  const names = ['Domingo', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado'];
  const weekday = names.map((name, i) => ({ weekday: i, name, tickets: 0, money: 0, occurrences: 0, avgTickets: 0, avgMoney: 0 }));
  daily.forEach(d => { const w = weekday[new Date(dayMs(d.date)).getUTCDay()]; w.tickets += d.tickets; w.money += d.money; w.occurrences++; });
  weekday.forEach(w => { w.avgTickets = w.occurrences ? w.tickets / w.occurrences : 0; w.avgMoney = w.occurrences ? w.money / w.occurrences : 0; });
  const best = [...weekday].sort((a, b) => b.avgTickets - a.avgTickets || b.avgMoney - a.avgMoney)[0];

  const soldCount = sold.length;
  const collected = tickets.reduce((sum, t) => sum + (Number(t.totalPaid) || 0), 0);
  const last7 = daily.slice(-7);
  const avgAll = soldCount / spanDays;
  const avg7 = last7.reduce((sum, d) => sum + d.tickets, 0) / Math.max(1, last7.length);
  const drawDay = drawDayOf(raffle);
  const daysLeft = drawDay ? Math.max(0, Math.round((dayMs(drawDay) - dayMs(today)) / DAY)) : null;
  const totalTickets = tickets.length;
  const collectRatio = soldCount > 0 && price > 0 ? Math.min(1, collected / (soldCount * price)) : 0;
  const project = avg => {
    if (daysLeft === null) return null;
    const projSold = Math.min(totalTickets, Math.round(soldCount + avg * daysLeft));
    return { avgPerDay: avg, tickets: projSold, soldOutPct: totalTickets ? projSold / totalTickets * 100 : 0, revenue: projSold * price, collected: projSold * price * collectRatio };
  };
  // Boletas por día necesarias para agotar la rifa a tiempo
  const neededPerDay = daysLeft && daysLeft > 0 ? Math.max(0, totalTickets - soldCount) / daysLeft : null;

  // Todos los asesores de la empresa (también los que aún no venden). Se muestran las ventas de calle y de oficina; el orden es por calle
  const zeroZone = () => ({ tickets: 0, money: 0 });
  const newAdvisorRow = name => ({ name, tickets: 0, money: 0, calle: zeroZone(), oficina: zeroZone() });
  const byAdvisor = new Map();
  (db.advisors || []).filter(a => a.companyId === raffle.companyId).forEach(a => byAdvisor.set(a.name, newAdvisorRow(a.name)));
  sold.forEach(t => {
    const k = t.advisorName || 'Venta directa';
    const e = byAdvisor.get(k) || newAdvisorRow(k);
    const paid = Number(t.totalPaid) || 0;
    e.tickets++; e.money += paid;
    const zone = inferredSaleZone(t, t.advisorId ? (db.advisors || []).find(a => a.id === t.advisorId) : null);
    if (zone === 'CALLE') { e.calle.tickets++; e.calle.money += paid; }
    else if (zone === 'OFICINA') { e.oficina.tickets++; e.oficina.money += paid; }
    byAdvisor.set(k, e);
  });

  // Boletas que vendió el chatbot (solo informativo): apartadas, abonadas y pagadas, y por cuál asesor quedaron referenciadas
  const botStatus = t => t.status === 'RESERVADA' ? 'reserved' : t.status === 'ABONO_PARCIAL' ? 'partial' : (t.status === 'PAGADA' || t.status === 'CONFIRMADA') ? 'paid' : null;
  const chatbot = { reserved: 0, partial: 0, paid: 0, total: 0, collected: 0, withAdvisor: 0, withoutAdvisor: 0, advisors: [], noAdvisor: { reserved: 0, partial: 0, paid: 0, total: 0 } };
  const botAdv = new Map();
  tickets.filter(t => t.soldByBot).forEach(t => {
    const st = botStatus(t);
    if (!st) return;
    chatbot[st]++; chatbot.total++; chatbot.collected += Number(t.totalPaid) || 0;
    const adv = t.advisorId ? (db.advisors || []).find(x => x.id === t.advisorId) : null;
    if (!adv) { chatbot.withoutAdvisor++; chatbot.noAdvisor[st]++; chatbot.noAdvisor.total++; return; }
    chatbot.withAdvisor++;
    const e = botAdv.get(adv.id) || { name: adv.name, reserved: 0, partial: 0, paid: 0, total: 0 };
    e[st]++; e.total++; botAdv.set(adv.id, e);
  });
  chatbot.advisors = [...botAdv.values()].sort((x, y) => y.total - x.total || x.name.localeCompare(y.name));

  res.json({
    raffleId: raffle.id, raffleTitle: raffle.title, ticketPrice: price, totalTickets, soldCount, collected,
    today, firstSaleDay: first, spanDays, drawDay, daysLeft, avgAll, avg7, neededPerDay, collectRatio,
    bestWeekday: best && best.tickets > 0 ? { weekday: best.weekday, name: best.name, avgTickets: best.avgTickets } : null,
    projectionAll: project(avgAll), projection7: project(avg7),
    chatbot, daily, weekday, topAdvisors: [...byAdvisor.values()].sort((a, b) => b.calle.tickets - a.calle.tickets || b.calle.money - a.calle.money || b.tickets - a.tickets || a.name.localeCompare(b.name))
  });
});

// GET Commissions Summary
/**
 * Raffle and advisors a commissions request may see: only the caller's company (the SuperAdmin passes a
 * raffleId of any company). Without a raffle there is nothing to show, never another company's data.
 */
function commissionScope(req, raffleId) {
  const ownCompanyId = req.auth.role === 'admin' ? req.auth.record.id
    : (req.auth.role === 'asesor' ? req.auth.record.companyId : null);
  const visible = (db.raffles || []).filter(r => canAccessRaffle(req, r) && (!ownCompanyId || r.companyId === ownCompanyId));
  const raffle = visible.find(r => r.id === raffleId) || (raffleId ? null : visible[0]) || null;
  if (!raffle) return { raffle: null, advisors: [] };
  const advisors = (db.advisors || []).filter(a => a.companyId && a.companyId === raffle.companyId);
  return { raffle, advisors };
}

app.get('/api/commissions', (req, res) => {
  if (!db.commissionPayouts) db.commissionPayouts = [];
  const { raffleId } = req.query;
  const { raffle, advisors } = commissionScope(req, raffleId);
  const targetRaffleId = raffle ? raffle.id : '';
  const advisorIds = new Set(advisors.map(a => a.id));
  
  const commType = raffle ? (raffle.commissionType || 'PORCENTAJE') : 'PORCENTAJE';
  const commVal = raffle ? (parseFloat(raffle.commissionValue) || 10) : 10;
  const tiers = raffle && Array.isArray(raffle.commissionTiers) && raffle.commissionTiers.length > 0 ? raffle.commissionTiers : null;
  const ticketPrice = raffle ? (parseFloat(raffle.ticketPrice) || 50000) : 50000;

  const raffleTickets = db.tickets.filter(t => t.raffleId === targetRaffleId);

  const advisorStats = advisors.map(adv => {
    const c = computeAdvisorCommission({ commType, commVal, tiers }, adv, raffleTickets);
    const advPayouts = db.commissionPayouts.filter(p => p.advisorId === adv.id && (p.raffleId === targetRaffleId || !p.raffleId));
    const commissionPaid = advPayouts.reduce((sum, p) => sum + (p.amount || 0), 0);
    const pendingCommission = Math.max(0, c.commissionEarned - commissionPaid);

    return {
      advisorId: adv.id,
      advisorName: adv.name,
      advisorCode: adv.code,
      phone: adv.phone,
      advisorType: c.type,
      totalTicketsSold: c.totalTicketsSold,
      // Todas las boletas del asesor (apartadas + abonadas + pagadas)
      ticketsHeld: c.ticketsHeld,
      ticketsReserved: c.ticketsReserved,
      ticketsPartial: c.ticketsPartial,
      ticketsPaid: c.ticketsPaid,
      totalCollected: c.totalCollected,
      // Solo las ventas de calle comisionan; las de oficina/punto se muestran aparte
      streetSold: c.streetSold,
      streetCollected: c.streetCollected,
      officeSold: c.officeSold,
      officeCollected: c.officeCollected,
      zoneUndefined: c.zoneUndefined,
      commissionEarned: c.commissionEarned,
      commissionPaid,
      pendingCommission,
      // Lo que aún no se ha ganado porque las boletas apartadas/abonadas no se han pagado del todo
      // Cómo se le paga ahora mismo: PORCENTAJE (% de lo recaudado) o VALOR_FIJO (valor por boleta)
      rateType: c.rateType,
      rateValue: c.rateValue,
      pendingToEarn: c.pendingToEarn,
      pendingBalance: c.pendingBalance,
      pendingTicketsCount: c.pendingTicketsCount,
      activeTier: c.activeTier,
      tierDescription: c.tierDescription,
      payoutsCount: advPayouts.length
    };
  });

  const globalCommissionEarned = advisorStats.reduce((sum, a) => sum + a.commissionEarned, 0);
  const globalCommissionPaid = advisorStats.reduce((sum, a) => sum + a.commissionPaid, 0);
  const globalPendingCommission = advisorStats.reduce((sum, a) => sum + a.pendingCommission, 0);
  const globalPendingToEarn = advisorStats.reduce((sum, a) => sum + a.pendingToEarn, 0);

  res.json({
    raffleId: targetRaffleId,
    commissionType: commType,
    commissionValue: commVal,
    commissionTiers: tiers,
    ticketPrice,
    globalCommissionEarned,
    globalCommissionPaid,
    globalPendingCommission,
    globalPendingToEarn,
    advisors: advisorStats,
    payoutsHistory: (db.commissionPayouts || []).filter(p => advisorIds.has(p.advisorId) && (p.raffleId === targetRaffleId || !p.raffleId))
  });
});

// POST Commission Payout (con soporte en Drive, abonos o liquidaciones totales, método y fecha)
app.post('/api/commissions/payout', adminOnly, async (req, res) => {
  if (!db.commissionPayouts) db.commissionPayouts = [];
  const { advisorId, amount, note, raffleId, paymentMethod, date, payoutType, approvalNumber, soporteBase64, soporteImageBase64 } = req.body || {};
  const { raffle, advisors } = commissionScope(req, raffleId);
  if (!raffle) return res.status(404).json({ error: 'Rifa no encontrada.' });
  const targetRaffleId = raffle.id;
  const payoutAmount = parseFloat(amount) || 0;

  // Si envían comprobante de foto base64, subir a Google Drive
  let soporteDriveId = null;
  let soporteUrl = null;
  let soporteWebViewUrl = null;

  const rawImage = soporteBase64 || soporteImageBase64;
  if (rawImage && typeof rawImage === 'string' && rawImage.length > 50) {
    try {
      const cleanBase64 = rawImage.replace(/^data:image\/\w+;base64,/, '');
      const buffer = Buffer.from(cleanBase64, 'base64');
      const filename = `comprobante_comision_${advisorId}_${Date.now()}.jpg`;
      const up = await driveService.uploadFileToDrive({
        buffer,
        filename,
        mimeType: 'image/jpeg'
      });
      if (up) {
        soporteDriveId = up.fileId;
        soporteUrl = up.directUrl;
        soporteWebViewUrl = up.webViewUrl;
      }
    } catch (e) {
      console.warn('⚠️ No se pudo subir soporte de comisión a Drive:', e.message);
    }
  }

  if (advisorId === 'ALL') {
    const commType = raffle ? (raffle.commissionType || 'PORCENTAJE') : 'PORCENTAJE';
    const commVal = raffle ? (parseFloat(raffle.commissionValue) || 10) : 10;
    const tiers = raffle && Array.isArray(raffle.commissionTiers) && raffle.commissionTiers.length > 0 ? raffle.commissionTiers : null;
    const raffleTickets = db.tickets.filter(t => t.raffleId === targetRaffleId);

    let totalPaidOut = 0;
    advisors.forEach(adv => {
      // Mismo cálculo que el resumen: solo comisionan las ventas de calle
      const earned = computeAdvisorCommission({ commType, commVal, tiers }, adv, raffleTickets).commissionEarned;

      const advPayouts = db.commissionPayouts.filter(p => p.advisorId === adv.id && (p.raffleId === targetRaffleId || !p.raffleId));
      const paid = advPayouts.reduce((sum, p) => sum + (p.amount || 0), 0);
      const pending = Math.max(0, earned - paid);

      if (pending > 0) {
        db.commissionPayouts.push({
          id: `pay-${Date.now()}-${adv.id}`,
          advisorId: adv.id,
          advisorName: adv.name,
          companyId: raffle.companyId,
          amount: pending,
          payoutType: 'TOTAL',
          paymentMethod: paymentMethod || 'efectivo',
          date: date ? new Date(date).toISOString() : new Date().toISOString(),
          approvalNumber: approvalNumber || '',
          soporteDriveId,
          soporteUrl,
          soporteWebViewUrl,
          registeredBy: actorName(req),
          note: note || 'Liquidación Global de Comisiones',
          raffleId: targetRaffleId
        });
        totalPaidOut += pending;
      }
    });
    saveDB();
    return res.json({ message: `Se liquidaron comisiones a todos los asesores por un total de $${totalPaidOut.toFixed(0)} COP.`, totalPaidOut });
  }

  const advisor = advisors.find(a => a.id === advisorId);
  if (!advisor) {
    return res.status(404).json({ error: 'Asesor no encontrado' });
  }

  const payout = {
    id: `pay-${Date.now()}`,
    advisorId: advisor.id,
    advisorName: advisor.name,
    companyId: raffle.companyId,
    amount: payoutAmount,
    payoutType: payoutType || 'ABONO',
    paymentMethod: paymentMethod || 'efectivo',
    date: date ? new Date(date).toISOString() : new Date().toISOString(),
    approvalNumber: approvalNumber || '',
    soporteDriveId,
    soporteUrl,
    soporteWebViewUrl,
    registeredBy: actorName(req),
    note: note || (payoutType === 'TOTAL' ? 'Liquidación Total de Comisión' : 'Abono a Comisión'),
    raffleId: targetRaffleId
  };

  db.commissionPayouts.push(payout);
  saveDB();
  res.status(201).json(payout);
});

/**
 * Boletas cuyo asesor pertenece a OTRA empresa (efecto del error anterior de asignación por rango):
 *  • disponibles: se les quita el asesor;
 *  • vendidas o apartadas: pasan al vendedor que registró su primer pago si es de la empresa (o la venta directa del
 *    administrador); si no hay pagos, se quita el asesor.
 * Nunca se tocan el dinero, el comprador ni el estado. Devuelve cuántas boletas se corrigieron.
 */
function repairCrossCompanyAdvisors(database = db) {
  const advisorById = new Map((database.advisors || []).map(a => [a.id, a]));
  const raffleCompany = new Map((database.raffles || []).map(r => [r.id, r.companyId]));
  let cleared = 0;
  let reassigned = 0;
  for (const t of database.tickets || []) {
    const adv = advisorById.get(t.advisorId);
    const companyId = raffleCompany.get(t.raffleId);
    if (!adv || !companyId || adv.companyId === companyId) continue;
    const wrongName = t.advisorName;
    const first = (t.abonos || []).find(ab => ab.sellerId);
    const firstAdvisor = first && advisorById.get(first.sellerId);
    if (t.status !== 'DISPONIBLE' && first && (first.sellerId === 'admin' || (firstAdvisor && firstAdvisor.companyId === companyId))) {
      t.advisorId = first.sellerId;
      t.advisorName = first.sellerName || (first.sellerId === 'admin' ? 'Administrador' : (firstAdvisor ? firstAdvisor.name : ''));
      reassigned++;
    } else {
      t.advisorId = '';
      t.advisorName = '';
      cleared++;
    }
    if (t.status !== 'DISPONIBLE') {
      t.auditLogs = t.auditLogs || [];
      t.auditLogs.push({
        id: `log-${Date.now()}-${Math.random().toString(36).slice(2, 5)}`,
        date: new Date().toISOString(),
        user: 'Sistema',
        action: 'REPARACION_ASESOR',
        description: `Se quitó el asesor "${wrongName}" (de otra empresa) asignado por error; vendedor actual: ${t.advisorName || 'ninguno'}`
      });
    }
  }
  return { cleared, reassigned, total: cleared + reassigned };
}

async function startServer() {
  await loadDB();
  try {
    // Rifas cerradas antes de este cambio: sin ventas para los asesores y eliminación 45 días después del cierre
    let fixedClosed = 0;
    for (const r of db.raffles || []) {
      if (!r.scheduledDeletionAt) continue;
      if (!salesLockOf(r).locked) { lockAdvisorSales(r, 'Sistema', 'Rifa cerrada'); fixedClosed++; }
      const manual = r.closedBy && !/^Sistema/.test(r.closedBy);
      const limit = Date.parse(r.closedAt || '') + CLOSE_GRACE_DAYS * 86400000;
      if (manual && Number.isFinite(limit) && Date.parse(r.scheduledDeletionAt) > limit) { r.scheduledDeletionAt = new Date(limit).toISOString(); fixedClosed++; }
    }
    if (fixedClosed > 0) { console.log(`🔒 Ajustadas ${fixedClosed} rifas cerradas (ventas bloqueadas / eliminación a 45 días).`); saveDB(); }
  } catch (err) {
    console.error('⚠️ No se pudieron ajustar las rifas cerradas:', err.message);
  }
  try {
    // Fotos de rifas guardadas con enlaces de Drive que no son imagen (página de vista / uc?export=view): se pasan al enlace directo
    let fixed = 0;
    for (const r of db.raffles || []) {
      if (!Array.isArray(r.prizeImages)) continue;
      r.prizeImages = r.prizeImages.map(u => { const n = normalizeDriveImageUrl(u); if (n !== u) fixed++; return n; });
    }
    if (fixed > 0) { console.log(`🖼️ Normalizados ${fixed} enlaces de fotos de rifas.`); saveDB(); }
  } catch (err) {
    console.error('⚠️ No se pudieron normalizar las fotos de rifas:', err.message);
  }
  try {
    // Boletas vendidas sin tipo de venta (oficina / calle): se completa según el vendedor
    let zoned = 0;
    for (const t of db.tickets || []) {
      if (!t.status || t.status === 'DISPONIBLE' || SALE_ZONES.includes(t.saleZone)) continue;
      const adv = t.advisorId ? (db.advisors || []).find(a => a.id === t.advisorId) : null;
      const zone = inferredSaleZone(t, adv);
      if (zone) { t.saleZone = zone; zoned++; }
    }
    if (zoned > 0) {
      console.log(`🛠️ Completado el tipo de venta de ${zoned} boletas que no lo tenían.`);
      if (!db.auditLogs) db.auditLogs = [];
      db.auditLogs.push({ id: `audit-${Date.now()}`, type: 'SALE_ZONE', companyId: '', targetId: 'migracion', targetName: 'Tipo de venta', detail: `Se completó el tipo de venta (oficina/calle) de ${zoned} boletas que no lo tenían`, by: 'Sistema', date: new Date().toISOString() });
      saveDB();
    }
  } catch (err) {
    console.error('⚠️ No se pudo completar el tipo de venta:', err.message);
  }
  try {
    const repair = repairCrossCompanyAdvisors();
    if (repair.total > 0) {
      console.log(`🛠️ Reparadas ${repair.total} boletas con asesor de otra empresa (${repair.cleared} liberadas, ${repair.reassigned} reasignadas al vendedor real).`);
      saveDB();
    }
  } catch (err) {
    console.error('⚠️ No se pudo revisar la asignación de asesores:', err.message);
  } // the first save after loading also takes the daily safety copy
  const httpServer = app.listen(PORT, '0.0.0.0', () => {
    console.log(`Backend API Servidor ejecutándose en http://0.0.0.0:${PORT}`);
    // Vigila la conexión de WhatsApp: si una instancia queda atascada, la reinicia sola
    if (!process.env.NO_BOT_WATCHDOG) whatsappService.startWatchdog();
    // Corrige referencias mal leídas por versiones anteriores del lector (una sola vez por pago)
    setTimeout(() => repairMisreadApprovals().catch(err => console.warn('⚠️ Revisión de referencias:', err.message)), 20000);
    alertService.start();

    // Keep-Alive Self-Ping: solo en Render (en el VPS no hace falta y pegaba a un servidor ajeno)
    const RENDER_EXTERNAL_URL = process.env.RENDER_EXTERNAL_URL || '';
    if (!RENDER_EXTERNAL_URL) return;
    const https = require('https');
    const http = require('http');

    setInterval(() => {
      try {
        const client = RENDER_EXTERNAL_URL.startsWith('https') ? https : http;
        client.get(`${RENDER_EXTERNAL_URL}/api/health`, (res) => {
          console.log(`[Keep-Alive] Ping 24/7 enviado a ${RENDER_EXTERNAL_URL}/api/health (Estado: ${res.statusCode})`);
        }).on('error', (err) => {
          console.warn(`[Keep-Alive] Advertencia ping: ${err.message}`);
        });
      } catch (err) {
        // Ignore
      }
    }, 8 * 60 * 1000); // Enviar ping cada 8 minutos (evita que entre en reposo tras 15 min)
  });
}

startServer();

// Cierre ordenado (los despliegues envían SIGTERM): se deja de recibir, se termina lo que está en curso y se sale en seguida.
// Sin esto Docker espera 10 s y mata el proceso, y el bot queda sin atender todo ese tiempo.
for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    console.log(`↩️ ${sig}: cerrando el servidor.`);
    setTimeout(() => process.exit(0), 1500).unref();
    process.exit(0);
  });
}
