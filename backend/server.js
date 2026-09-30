const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const security = require('./security');
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
          await reloadFromFirestore().catch(e => console.error('Error recargando desde Firestore:', e.message));
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
app.use(express.json({ limit: '10mb' }));
app.set('trust proxy', true);

// Never send password hashes or credentials to clients
app.use('/api', (req, res, next) => {
  const originalJson = res.json.bind(res);
  res.json = (body) => originalJson(security.stripSecrets(body));
  next();
});

// Serve static Flutter Web SPA if present
const publicDir = path.join(__dirname, 'public');
const webDir = path.join(__dirname, '../build/web');
const staticDir = fs.existsSync(publicDir) ? publicDir : (fs.existsSync(webDir) ? webDir : null);

if (staticDir) {
  app.use(express.static(staticDir));
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api')) return next();
    res.sendFile(path.join(staticDir, 'index.html'));
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
  const payload = snapshotPayload();
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

  if (firestore) {
    try {
      await writeFirestoreDb(payload, `snapshot_${reason}`);
      written++;
    } catch (err) {
      errors.push(`Firestore: ${err.message}`);
    }
  }

  if (reason === 'daily') lastDailySnapshotAt = Date.now();
  if (written === 0) throw new Error(`No se pudo crear la copia de seguridad automática (${errors.join('; ')})`);
  console.log(`🗂️ Copia automática "${reason}" creada${errors.length ? ` (con advertencias: ${errors.join('; ')})` : ''}.`);
}

function maybeDailySnapshot() {
  if (Date.now() - lastDailySnapshotAt < DAILY_SNAPSHOT_MS) return;
  lastDailySnapshotAt = Date.now();
  createSnapshot('daily').catch(err => console.error('⚠️', err.message));
}

/** Every known collection exists; unknown sections from backups are kept untouched. */
function ensureDbShape(target) {
  for (const key of ['companies', 'raffles', 'tickets', 'advisors', 'winners', 'cashTransactions', 'logs', 'auditLogs', 'commissionPayouts']) {
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
    logs: []
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

  const credentialsChanged = migrateCredentials();
  if (credentialsChanged) {
    console.log('🔐 Contraseñas protegidas con hash (scrypt) y cuenta SuperAdmin verificada.');
  }
  // Rewrite only when needed (new hashes, encryption or old storage format). Saving on every
  // startup would overwrite changes made on the previous server during a deploy.
  const needsRewrite =
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
async function reloadFromFirestore() {
  const doc = await firestore.collection(FIRESTORE_COLLECTION).doc(FIRESTORE_MANIFEST).get();
  if (!doc.exists) return;
  const data = decodeStoredDb(await readFirestoreDb(doc), 'Firestore');
  db = ensureDbShape(data);
  firestoreVersion = doc.data().version || 'legacy';
  console.log(`🔄 Datos recargados desde Firestore (versión ${firestoreVersion}).`);
}

function saveDB() {
  if (!isDbLoaded) {
    console.warn('⚠️ saveDB ignorado: La base de datos aún no ha sido cargada.');
    return;
  }
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
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString(), companiesCount: (db.companies || []).length, rafflesCount: db.raffles.length, ticketsCount: db.tickets.length });
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
    return {
      role: 'admin',
      id: record.id,
      name: record.adminName || 'Administrador',
      email: record.adminEmail || '',
      username: record.adminUsername,
      companyId: record.id,
      companyName: record.name,
      mustChangePassword: !!record.adminMustChangePassword
    };
  }
  const company = (db.companies || []).find(c => c.id === record.companyId);
  return {
    role: 'asesor',
    id: record.id,
    name: record.name,
    email: record.email || '',
    username: record.username || record.code,
    companyId: record.companyId || null,
    companyName: company ? company.name : '',
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
  if (payload.role === 'asesor' && record.status === 'INHABILITADO') return null;
  return { kind: payload.role, record };
}

app.post('/api/auth/login', (req, res) => {
  const { role, username, password } = req.body || {};
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
    record = (db.advisors || []).find(a => [a.code, a.username, a.email, a.phone].some(v => v && normalize(v) === identifier));
    kind = record ? 'asesor' : null;
  } else {
    const sa = db.superAdmin;
    if (sa && (normalize(sa.username) === identifier || normalize(sa.email) === identifier)) {
      kind = 'superadmin';
      record = sa;
    } else {
      record = (db.companies || []).find(c => [c.adminUsername, c.adminEmail].some(v => v && normalize(v) === identifier));
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

  security.clearFailures(ip, identifier);
  res.json(issueSession(kind, record));
});

// Every other API route requires a valid session
app.use('/api', (req, res, next) => {
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
    if (current !== firestoreVersion) {
      console.log(`🔄 Datos más recientes en Firestore (${current}); se cargan antes de aplicar el cambio.`);
      await reloadFromFirestore();
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
  const { name, code, adminUsername, adminPassword, adminName, adminEmail } = req.body;
  if (!name) {
    return res.status(400).json({ error: 'El nombre de la empresa es obligatorio' });
  }
  const policyError = security.validatePasswordPolicy(adminPassword);
  if (policyError) return res.status(400).json({ error: `Contraseña del administrador: ${policyError}` });
  if (adminUsername && isUsernameTaken(adminUsername)) {
    return res.status(409).json({ error: 'Ese usuario administrador ya existe.' });
  }

  const newCompany = {
    id: `comp-${Date.now()}`,
    name: name.trim(),
    code: code ? code.trim().toUpperCase() : `EMP${(db.companies || []).length + 1}`,
    status: 'ACTIVA',
    adminUsername: adminUsername ? adminUsername.trim() : `admin_${Date.now().toString().slice(-4)}`,
    adminPassword: security.hashPassword(adminPassword),
    adminMustChangePassword: true,
    adminName: adminName || 'Admin Empresa',
    adminEmail: adminEmail || '',
    createdAt: new Date().toISOString()
  };

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

  if (req.body.name !== undefined) company.name = req.body.name;
  if (req.body.code !== undefined) company.code = req.body.code;
  if (req.body.status !== undefined) company.status = req.body.status;
  if (req.body.adminUsername !== undefined) {
    if (normalize(req.body.adminUsername) !== normalize(company.adminUsername) && isUsernameTaken(req.body.adminUsername)) {
      return res.status(409).json({ error: 'Ese usuario administrador ya existe.' });
    }
    company.adminUsername = req.body.adminUsername;
  }
  // Password only changes when a new one is sent (it is never read back)
  if (typeof req.body.adminPassword === 'string' && req.body.adminPassword.trim() !== '') {
    const policyError = security.validatePasswordPolicy(req.body.adminPassword);
    if (policyError) return res.status(400).json({ error: `Contraseña del administrador: ${policyError}` });
    company.adminPassword = security.hashPassword(req.body.adminPassword);
    company.adminMustChangePassword = true;
  }
  if (req.body.adminName !== undefined) company.adminName = req.body.adminName;
  saveDB();
  res.json(company);
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

  // Remove commission payouts
  db.commissionPayouts = (db.commissionPayouts || []).filter(cp => !companyAdvisorIds.has(cp.advisorId) && !companyRaffleIds.has(cp.raffleId));

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

app.get('/api/backup/download', superAdminOnly, (req, res) => {
  // The backup file is encrypted with the server key: it can only be restored with that key
  const payload = security.hasMasterKey() ? security.encryptObject(db, security.BACKUP_FORMAT) : db;
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Content-Disposition', `attachment; filename=backup_rifamaster_${Date.now()}.json`);
  res.send(JSON.stringify(payload));
});

const KNOWN_SECTIONS = ['companies', 'raffles', 'tickets', 'advisors', 'winners', 'cashTransactions', 'logs', 'auditLogs', 'commissionPayouts'];

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
    const { superAdmin: _ignored, ...sections } = data;
    db = ensureDbShape({ ...sections, superAdmin: db.superAdmin });

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
  let targetCompanyId = companyId;
  if (!targetCompanyId && req.auth) {
    if (req.auth.role === 'admin') targetCompanyId = req.auth.record.id;
    if (req.auth.role === 'asesor') targetCompanyId = req.auth.record.companyId;
  }

  if (targetCompanyId) {
    raffles = raffles.filter(r => !r.companyId || r.companyId === targetCompanyId);
  }

  if ((role === 'asesor' || (req.auth && req.auth.role === 'asesor'))) {
    const advId = advisorId || (req.auth && req.auth.record ? req.auth.record.id : null);
    if (advId) {
      raffles = raffles.filter(r => r.status === 'ACTIVA' && (!r.assignedAdvisorIds || r.assignedAdvisorIds.length === 0 || r.assignedAdvisorIds.includes(advId)));
    }
  }
  res.json(raffles);
});

// PUT Update Raffle
app.put('/api/raffles/:id', adminOnly, (req, res) => {
  const { id } = req.params;
  const raffle = db.raffles.find(r => r.id === id);
  if (!raffle) {
    return res.status(404).json({ error: 'Sorteo no encontrado' });
  }

  if (req.body.status !== undefined) raffle.status = req.body.status;
  if (req.body.title !== undefined) raffle.title = req.body.title;
  if (req.body.description !== undefined) raffle.description = req.body.description;
  if (req.body.mainDrawDate !== undefined) raffle.mainDrawDate = req.body.mainDrawDate;
  if (req.body.weeklyPrizesStartDate !== undefined) raffle.weeklyPrizesStartDate = req.body.weeklyPrizesStartDate;
  if (req.body.assignedAdvisorIds !== undefined) raffle.assignedAdvisorIds = req.body.assignedAdvisorIds;
  if (req.body.commissionType !== undefined) raffle.commissionType = req.body.commissionType;
  if (req.body.commissionValue !== undefined) raffle.commissionValue = parseFloat(req.body.commissionValue) || 0;
  if (req.body.templateConfig !== undefined) raffle.templateConfig = req.body.templateConfig;
  // Weekly draw settings (previously ignored, so they reverted after every reload)
  if (req.body.hasWeeklyDraws !== undefined) raffle.hasWeeklyDraws = req.body.hasWeeklyDraws === true || req.body.hasWeeklyDraws === 'true';
  if (req.body.weeklyDrawDay !== undefined) raffle.weeklyDrawDay = String(req.body.weeklyDrawDay);
  if (req.body.lotteryName !== undefined) raffle.lotteryName = String(req.body.lotteryName);
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

  db.raffles.splice(index, 1);
  // Cascade delete tickets, winners, transactions for this raffle
  db.tickets = (db.tickets || []).filter(t => t.raffleId !== id);
  db.winners = (db.winners || []).filter(w => w.raffleId !== id);
  db.cashTransactions = (db.cashTransactions || []).filter(ct => ct.raffleId !== id);
  db.commissionPayouts = (db.commissionPayouts || []).filter(cp => cp.raffleId !== id);

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

// POST Create Raffle
app.post('/api/raffles', adminOnly, (req, res) => {
  const { title, description, mainDrawDate, weeklyPrizesStartDate, digits, totalTickets, ticketPrice, weeklyPrizes, generationMode, customNumbers, preSoldTickets, commissionType, commissionValue, companyId } = req.body;
  
  const numDigits = parseInt(digits) || 4;
  const numTickets = parseInt(totalTickets) || 2500;
  const totalNumbers = Math.pow(10, numDigits); // 10^4 = 10000
  const opps = Math.floor(totalNumbers / numTickets); // e.g. 10000 / 2500 = 4

  const targetCompanyId = req.auth && req.auth.role === 'admin' ? req.auth.record.id : (companyId || 'comp-1');

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
    commissionType: commissionType || 'PORCENTAJE',
    commissionValue: parseFloat(commissionValue) || 10,
    status: 'ACTIVA',
    createdAt: new Date().toISOString()
  };

  db.raffles.unshift(newRaffle);

  // Prepare series numbers based on generationMode
  let allSeries = [];
  const mode = generationMode || 'SECUENCIAL';

  if (mode === 'ALEATORIO') {
    // Generate pool 0..totalNumbers-1, shuffle and chunk
    const pool = Array.from({ length: totalNumbers }, (_, i) => i);
    for (let i = pool.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [pool[i], pool[j]] = [pool[j], pool[i]];
    }

    for (let i = 0; i < numTickets; i++) {
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
    for (let i = 1; i <= numTickets; i++) {
      if (customNumbers[i] && Array.isArray(customNumbers[i])) {
        allSeries.push(customNumbers[i].map(n => n.toString().padStart(numDigits, '0')));
      } else {
        const series = [];
        for (let k = 0; k < opps; k++) {
          const numVal = (i - 1) + (k * numTickets);
          series.push(numVal.toString().padStart(numDigits, '0'));
        }
        allSeries.push(series);
      }
    }
  } else {
    // SECUENCIAL
    for (let i = 1; i <= numTickets; i++) {
      const series = [];
      for (let k = 0; k < opps; k++) {
        const numVal = (i - 1) + (k * numTickets);
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
  for (let i = 1; i <= numTickets; i++) {
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

  let importedCount = 0;
  records.forEach(rec => {
    const ticket = db.tickets.find(t => t.raffleId === raffleId && t.ticketNumber === parseInt(rec.ticketNumber));
    if (ticket) {
      ticket.buyerName = rec.buyerName || ticket.buyerName;
      ticket.buyerPhone = rec.buyerPhone || ticket.buyerPhone;
      ticket.status = rec.status || ticket.status || 'RESERVADA';
      ticket.advisorName = rec.sellerName || ticket.advisorName;
      ticket.advisorId = rec.sellerCode || ticket.advisorId;
      
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
  res.json({ message: `${importedCount} boletas importadas correctamente`, count: importedCount });
});

// GET Tickets (with multi-tenant isolation)
app.get('/api/tickets', (req, res) => {
  const { raffleId, advisorId, status, search, numberSearch, companyId } = req.query;
  
  let targetCompanyId = companyId;
  if (!targetCompanyId && req.auth) {
    if (req.auth.role === 'admin') targetCompanyId = req.auth.record.id;
    if (req.auth.role === 'asesor') targetCompanyId = req.auth.record.companyId;
  }

  let result = db.tickets || [];

  if (targetCompanyId) {
    const companyRaffleIds = (db.raffles || []).filter(r => !r.companyId || r.companyId === targetCompanyId).map(r => r.id);
    result = result.filter(t => companyRaffleIds.includes(t.raffleId));
  }

  if (raffleId) {
    result = result.filter(t => t.raffleId === raffleId);
  } else if (targetCompanyId) {
    const availableRaffles = (db.raffles || []).filter(r => !r.companyId || r.companyId === targetCompanyId);
    if (availableRaffles.length > 0) {
      result = result.filter(t => availableRaffles.some(r => r.id === t.raffleId));
    }
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
      t.numbers.some(n => n.includes(q))
    );
  }

  res.json(result);
});

// POST Register Ticket Sale or Abono
app.post('/api/tickets/:id/abono', (req, res) => {
  const { id } = req.params;
  const { amount, buyerName, buyerPhone, sellerId, sellerName, note } = req.body;

  const ticket = db.tickets.find(t => t.id === id);
  if (!ticket) {
    return res.status(404).json({ error: 'Boleta no encontrada' });
  }

  const abonoAmount = parseFloat(amount) || 0;
  if (isNaN(abonoAmount) || abonoAmount < 0) {
    return res.status(400).json({ error: 'Monto de abono inválido' });
  }

  if (typeof buyerName === 'string' && buyerName.trim().length > 0) ticket.buyerName = buyerName.trim();
  if (typeof buyerPhone === 'string') ticket.buyerPhone = buyerPhone.trim();
  if (sellerId) ticket.advisorId = sellerId;
  if (sellerName) ticket.advisorName = sellerName;
  if (!ticket.assignedDate) ticket.assignedDate = new Date().toISOString();

  if (abonoAmount > 0) {
    const newAbono = {
      id: `ab-${Date.now()}`,
      amount: abonoAmount,
      date: new Date().toISOString(),
      sellerId: sellerId || 'admin',
      sellerName: sellerName || 'Administrador',
      note: note || 'Abono registrado'
    };
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
      note: note || 'Boleta apartada / fiada sin abono inicial'
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

  saveDB();
  res.json(ticket);
});

// POST Admin Confirm Ticket Payment Received
app.post('/api/tickets/:id/confirm', adminOnly, (req, res) => {
  const { id } = req.params;
  const ticket = db.tickets.find(t => t.id === id);
  if (!ticket) {
    return res.status(404).json({ error: 'Boleta no encontrada' });
  }

  ticket.confirmedByAdmin = true;
  ticket.confirmedDate = new Date().toISOString();
  if (ticket.status === 'PAGADA') {
    ticket.status = 'CONFIRMADA';
  }
  saveDB();
  res.json(ticket);
});

// GET Advisors (Multi-tenant isolated)
app.get('/api/advisors', (req, res) => {
  const { companyId } = req.query;
  let targetCompanyId = companyId;
  if (!targetCompanyId && req.auth) {
    if (req.auth.role === 'admin') targetCompanyId = req.auth.record.id;
    if (req.auth.role === 'asesor') targetCompanyId = req.auth.record.companyId;
  }

  let list = db.advisors || [];
  if (targetCompanyId) {
    list = list.filter(a => !a.companyId || a.companyId === targetCompanyId);
  }

  const advisorsWithStats = list.map(adv => {
    const advTickets = (db.tickets || []).filter(t => t.advisorId === adv.id);
    const totalSold = advTickets.filter(t => t.status === 'PAGADA' || t.status === 'ABONO_PARCIAL').length;
    const totalCollected = advTickets.reduce((sum, t) => sum + (t.totalPaid || 0), 0);
    const totalConfirmed = advTickets.filter(t => t.confirmedByAdmin).reduce((sum, t) => sum + (t.totalPaid || 0), 0);
    const pendingTurnIn = totalCollected - totalConfirmed;

    return {
      ...adv,
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
app.post('/api/advisors', adminOnly, (req, res) => {
  const { name, email, username, password, status, phone, code, mode, assignedTicketRanges, companyId } = req.body;
  const policyError = security.validatePasswordPolicy(password);
  if (policyError) return res.status(400).json({ error: `Contraseña del asesor: ${policyError}` });

  let targetCompanyId = req.auth && req.auth.role === 'admin' ? req.auth.record.id : companyId;
  if (!targetCompanyId && (db.companies || []).length > 0) {
    targetCompanyId = db.companies[0].id;
  }
  if (!targetCompanyId) targetCompanyId = 'comp-1';

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
    assignedTicketRanges: assignedTicketRanges || [],
    createdAt: new Date().toISOString()
  };

  db.advisors.push(newAdvisor);
  saveDB();
  res.status(201).json(newAdvisor);
});

// PUT Update Advisor
app.put('/api/advisors/:id', adminOnly, (req, res) => {
  const { id } = req.params;
  const advisor = db.advisors.find(a => a.id === id);
  if (!advisor) {
    return res.status(404).json({ error: 'Asesor no encontrado' });
  }

  if (req.body.companyId !== undefined) advisor.companyId = req.body.companyId;
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
  if (req.body.assignedTicketRanges !== undefined) advisor.assignedTicketRanges = req.body.assignedTicketRanges;

  saveDB();
  res.json(advisor);
});

// DELETE Advisor (Only allowed if no sales/records exist)
app.delete('/api/advisors/:id', adminOnly, (req, res) => {
  const { id } = req.params;
  const { reason } = req.body || {};
  const advisor = db.advisors.find(a => a.id === id);
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
app.post('/api/winners', adminOnly, (req, res) => {
  const { raffleId, winningNumber, drawName, drawDate, prizeAmount, photoUrl } = req.body;

  const raffle = db.raffles.find(r => r.id === (raffleId || (db.raffles[0] && db.raffles[0].id)));
  if (!raffle) {
    return res.status(404).json({ error: 'Sorteo no encontrado.' });
  }
  if (raffle.hasWeeklyDraws === false) {
    return res.status(400).json({ error: 'Este sorteo tiene deshabilitados los sorteos semanales. Habilítelos en "Gestionar Sorteo" para registrar ganadores semanales.' });
  }
  const rawNumStr = (winningNumber || '').toString().trim();
  const numStr = rawNumStr.padStart(raffle ? raffle.digits : 4, '0');

  // Search if any ticket has this winning number
  const matchingTicket = db.tickets.find(t => 
    t.raffleId === (raffleId || (db.raffles[0] ? db.raffles[0].id : 'raf-1')) && 
    (t.numbers.includes(numStr) || t.numbers.includes(rawNumStr))
  );

  const reqAbono = raffle ? (
    raffle.weeklyMinAbonoType === 'PORCENTAJE'
      ? (raffle.ticketPrice * (raffle.weeklyMinAbonoValue / 100))
      : raffle.weeklyMinAbonoValue
  ) : 0;

  let isWinner = false;
  if (matchingTicket && matchingTicket.status !== 'DISPONIBLE' && (matchingTicket.totalPaid || 0) >= reqAbono) {
    isWinner = true;
  }

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

  // Calculate previous accumulated pot from active accumulated draws
  const activeAccumulatedPrizes = db.winners.filter(w => w.accumulated);
  const prevAccumulatedPot = activeAccumulatedPrizes.reduce((sum, w) => sum + (parseFloat(w.basePrizeAmount || w.prizeAmount) || 0), 0);

  const basePrizeAmount = prizeAmount ? parseFloat(prizeAmount) : 1000000;
  const totalPrizePaid = isWinner ? (basePrizeAmount + prevAccumulatedPot) : basePrizeAmount;

  const record = {
    id: `win-${Date.now()}`,
    raffleId: raffle ? raffle.id : 'raf-1',
    drawName: drawName || 'Sorteo Semanal',
    drawDate: drawDate || new Date().toISOString(),
    winningNumber: rawNumStr,
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
      if (w.accumulated) {
        w.accumulated = false;
        w.accumulationReason = `Acumulado entregado en sorteo #${rawNumStr}`;
      }
    });
  }

  db.winners.unshift(record);
  saveDB();
  res.status(201).json(record);
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

// GET Commissions Summary
app.get('/api/commissions', (req, res) => {
  if (!db.commissionPayouts) db.commissionPayouts = [];
  const { raffleId } = req.query;
  const raffle = db.raffles.find(r => r.id === raffleId) || db.raffles[0];
  const targetRaffleId = raffle ? raffle.id : 'raf-1';
  
  const commType = raffle ? (raffle.commissionType || 'PORCENTAJE') : 'PORCENTAJE';
  const commVal = raffle ? (parseFloat(raffle.commissionValue) || 10) : 10;
  const ticketPrice = raffle ? (parseFloat(raffle.ticketPrice) || 50000) : 50000;

  const raffleTickets = db.tickets.filter(t => t.raffleId === targetRaffleId);

  const advisorStats = db.advisors.map(adv => {
    const advTickets = raffleTickets.filter(t => 
      t.advisorId === adv.id || 
      (t.advisorName && t.advisorName.trim().toLowerCase() === adv.name.trim().toLowerCase()) ||
      (adv.code && t.advisorName && t.advisorName.includes(adv.code))
    );
    
    const paidTickets = advTickets.filter(t => t.status === 'PAGADA' || t.status === 'CONFIRMADA');
    const partialTickets = advTickets.filter(t => t.status === 'ABONO_PARCIAL');
    const totalTicketsSold = paidTickets.length + partialTickets.length;
    
    const totalCollected = advTickets.reduce((sum, t) => sum + (t.totalPaid || 0), 0);

    let commissionEarned = 0;
    if (commType === 'VALOR_FIJO') {
      commissionEarned = totalTicketsSold * commVal;
    } else {
      commissionEarned = (totalCollected * commVal) / 100;
    }

    const advPayouts = db.commissionPayouts.filter(p => p.advisorId === adv.id && (p.raffleId === targetRaffleId || !p.raffleId));
    const commissionPaid = advPayouts.reduce((sum, p) => sum + (p.amount || 0), 0);
    const pendingCommission = Math.max(0, commissionEarned - commissionPaid);

    return {
      advisorId: adv.id,
      advisorName: adv.name,
      advisorCode: adv.code,
      phone: adv.phone,
      totalTicketsSold,
      totalCollected,
      commissionEarned,
      commissionPaid,
      pendingCommission,
      payoutsCount: advPayouts.length
    };
  });

  const globalCommissionEarned = advisorStats.reduce((sum, a) => sum + a.commissionEarned, 0);
  const globalCommissionPaid = advisorStats.reduce((sum, a) => sum + a.commissionPaid, 0);
  const globalPendingCommission = advisorStats.reduce((sum, a) => sum + a.pendingCommission, 0);

  res.json({
    raffleId: targetRaffleId,
    commissionType: commType,
    commissionValue: commVal,
    ticketPrice,
    globalCommissionEarned,
    globalCommissionPaid,
    globalPendingCommission,
    advisors: advisorStats,
    payoutsHistory: db.commissionPayouts.filter(p => p.raffleId === targetRaffleId || !p.raffleId)
  });
});

// POST Commission Payout
app.post('/api/commissions/payout', adminOnly, (req, res) => {
  if (!db.commissionPayouts) db.commissionPayouts = [];
  const { advisorId, amount, note, raffleId } = req.body;
  const targetRaffleId = raffleId || (db.raffles[0] ? db.raffles[0].id : 'raf-1');
  const payoutAmount = parseFloat(amount) || 0;

  if (advisorId === 'ALL') {
    const raffle = db.raffles.find(r => r.id === targetRaffleId) || db.raffles[0];
    const commType = raffle ? (raffle.commissionType || 'PORCENTAJE') : 'PORCENTAJE';
    const commVal = raffle ? (parseFloat(raffle.commissionValue) || 10) : 10;
    const raffleTickets = db.tickets.filter(t => t.raffleId === targetRaffleId);

    let totalPaidOut = 0;
    db.advisors.forEach(adv => {
      const advTickets = raffleTickets.filter(t => t.advisorId === adv.id || (t.advisorName && t.advisorName.trim().toLowerCase() === adv.name.trim().toLowerCase()));
      const totalTicketsSold = advTickets.filter(t => t.status === 'PAGADA' || t.status === 'CONFIRMADA' || t.status === 'ABONO_PARCIAL').length;
      const totalCollected = advTickets.reduce((sum, t) => sum + (t.totalPaid || 0), 0);

      let earned = commType === 'VALOR_FIJO' ? (totalTicketsSold * commVal) : ((totalCollected * commVal) / 100);
      const advPayouts = db.commissionPayouts.filter(p => p.advisorId === adv.id && (p.raffleId === targetRaffleId || !p.raffleId));
      const paid = advPayouts.reduce((sum, p) => sum + (p.amount || 0), 0);
      const pending = Math.max(0, earned - paid);

      if (pending > 0) {
        db.commissionPayouts.push({
          id: `pay-${Date.now()}-${adv.id}`,
          advisorId: adv.id,
          advisorName: adv.name,
          amount: pending,
          date: new Date().toISOString(),
          note: note || 'Liquidación Global de Comisiones',
          raffleId: targetRaffleId
        });
        totalPaidOut += pending;
      }
    });
    saveDB();
    return res.json({ message: `Se liquidaron comisiones a todos los asesores por un total de $${totalPaidOut.toFixed(0)} COP.`, totalPaidOut });
  }

  const advisor = db.advisors.find(a => a.id === advisorId);
  if (!advisor) {
    return res.status(404).json({ error: 'Asesor no encontrado' });
  }

  const payout = {
    id: `pay-${Date.now()}`,
    advisorId: advisor.id,
    advisorName: advisor.name,
    amount: payoutAmount,
    date: new Date().toISOString(),
    note: note || 'Pago de Comisión Asesor',
    raffleId: targetRaffleId
  };

  db.commissionPayouts.push(payout);
  saveDB();
  res.status(201).json(payout);
});

async function startServer() {
  await loadDB(); // the first save after loading also takes the daily safety copy
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Backend API Servidor ejecutándose en http://0.0.0.0:${PORT}`);

    // Keep-Alive Self-Ping Interval (Mantiene el servidor despiazado 24/7 en Render gratis)
    const RENDER_EXTERNAL_URL = process.env.RENDER_EXTERNAL_URL || 'https://rifaapp-backend.onrender.com';
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
