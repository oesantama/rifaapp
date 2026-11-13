// backend/ocrService.js
// Lectura del comprobante de pago (OCR) dentro del propio servidor: sin servicios externos ni costo por uso.
// Extrae la referencia / número de aprobación, el valor y el banco de la imagen, y verifica que la referencia
// escrita por el usuario sea la del comprobante. Si el OCR no está disponible o no puede leer la imagen,
// nunca bloquea: solo informa (los pagos quedan para revisión del administrador).

const path = require('path');
const crypto = require('crypto');

let createWorker = null;
let langPath = null;
try {
  ({ createWorker } = require('tesseract.js'));
  // Datos del idioma incluidos en el paquete (funciona sin internet)
  langPath = path.join(path.dirname(require.resolve('@tesseract.js-data/spa/package.json')), '4.0.0_best_int');
} catch (_) {
  createWorker = null;
}

const IDLE_MS = 10 * 60 * 1000; // se libera la memoria del OCR si no se usa
const TIMEOUT_MS = 60 * 1000;
const CACHE_TTL_MS = 30 * 60 * 1000;
const CACHE_MAX = 60;

let worker = null;
let idleTimer = null;
let queue = Promise.resolve();
const cache = new Map(); // sha256 de la imagen -> { at, result }

const available = () => !!createWorker;

async function getWorker() {
  if (worker) return worker;
  worker = await createWorker('spa', 1, { langPath, gzip: true, cachePath: '/tmp/ocr-cache', logger: () => {} });
  return worker;
}

function touchIdle() {
  clearTimeout(idleTimer);
  idleTimer = setTimeout(async () => {
    const w = worker;
    worker = null;
    if (w) { try { await w.terminate(); } catch (_) {} }
  }, IDLE_MS);
  if (idleTimer.unref) idleTimer.unref();
}

/** Texto de la imagen. Las lecturas se hacen de a una para no saturar el servidor. psm: modo de segmentación de página (opcional). */
function recognize(buffer, psm) {
  const job = queue.then(async () => {
    const w = await getWorker();
    if (psm) await w.setParameters({ tessedit_pageseg_mode: String(psm) });
    try {
      const run = w.recognize(buffer);
      const result = await Promise.race([run, new Promise((_, rej) => setTimeout(() => rej(new Error('OCR demasiado lento')), TIMEOUT_MS))]);
      touchIdle();
      return result.data;
    } finally {
      if (psm) { try { await w.setParameters({ tessedit_pageseg_mode: '3' }); } catch (_) {} }
    }
  });
  queue = job.catch(() => {});
  return job;
}

// ---------------------------------------------------------------------------
// Interpretación del texto
// ---------------------------------------------------------------------------
const REF_LABEL = /(referencia|autorizaci[oó]n|confirmaci[oó]n|seguimiento|n[o°º]\.?\s+de\s+(?:comprobante|referencia|transacci[oó]n|aprobaci[oó]n|autorizaci[oó]n)|id\s+de\s+(?:transacci[oó]n|pago|operaci[oó]n)|\bref\b\.?|comprobante|aprob\w*|\bapr[o0c][a-z0-9]{0,2}\s*[:.]|transacci[oó]n|c[oó]digo\s+de\s+(?:aprobaci[oó]n|confirmaci[oó]n)|\bcus\b|n[uú]mero\s+de\s+(?:aprobaci[oó]n|comprobante|transacci[oó]n|referencia|pago|operaci[oó]n)|n[o°º]\.?\s+de\s+operaci[oó]n|operaci[oó]n\s*(?:n[o°º]\.?|#|:))/i;

const normRef = s => String(s || '').toUpperCase().replace(/[^0-9A-Z]/g, '');
// El OCR confunde letras y números parecidos: se comparan con la misma equivalencia en ambos lados
const lookalike = s => normRef(s).replace(/O|Q|D/g, '0').replace(/[IL|]/g, '1').replace(/Z/g, '2').replace(/S/g, '5').replace(/B/g, '8');

function extractReferences(text) {
  const rawLines = String(text || '').split(/\r?\n/).map(l => l.trim()).filter(Boolean);
  // Etiquetas que el comprobante parte en dos líneas ("Número de" / "operación"): se unen para reconocerlas
  const lines = [];
  for (let i = 0; i < rawLines.length; i++) {
    if (i + 1 < rawLines.length && /(?:n[uú]mero|nro\.?|n[°ºo]\.?|c[oó]digo|id)\s+de$/i.test(rawLines[i]) &&
        /^(?:operaci[oó]n|aprobaci[oó]n|autorizaci[oó]n|transacci[oó]n|referencia|comprobante|confirmaci[oó]n|pago)\b/i.test(rawLines[i + 1])) {
      lines.push(`${rawLines[i]} ${rawLines[i + 1]}`);
      i++;
    } else lines.push(rawLines[i]);
  }
  const found = [];
  const add = (raw, score) => {
    const value = normRef(raw);
    const digits = (value.match(/\d/g) || []).length;
    const letters = (value.match(/[A-Z]/g) || []).length;
    // Códigos alfanuméricos de comprobante (ej. Bre-B "TRmZEHJAB5EC"): pocas cifras pero mezclados con letras
    const mixedCode = value.length >= 8 && digits >= 1 && letters >= 4;
    if (value.length < 5 || value.length > 40 || (digits < 4 && !mixedCode)) return;
    if (!found.some(f => f.value === value)) found.push({ value, score });
  };
  const tokens = line => {
    const out = [];
    // números con espacios o guiones internos (ej: "1843 852 709") y códigos con letra (ej: "M18437283")
    for (const m of line.matchAll(/[A-Za-z]?\d[\d \-]{3,38}\d|[A-Za-z]\d{5,}/g)) out.push(m[0]);
    // códigos con letras y números mezclados, de una sola palabra
    for (const m of line.matchAll(/\b(?=[A-Za-z0-9]*\d)(?=[A-Za-z0-9]*[A-Za-z])[A-Za-z0-9]{8,40}\b/g)) out.push(m[0]);
    return out;
  };
  // Recibos de corresponsal bancario (Wompi/Bancolombia): "RRN: 933760239331 Aprob: 722001". Si el OCR estropea la palabra
  // «Aprob», el número corto que sigue al RRN es la aprobación.
  for (const m of String(text || '').matchAll(/\brrn\W{0,3}\d{9,}\W+(?:[A-Za-z]{0,8}\W{0,3})?(\d{5,7})\b/gi)) add(m[1], 20);
  lines.forEach((line, i) => {
    const label = REF_LABEL.exec(line);
    if (!label) return;
    const after = line.slice(label.index + label[0].length);
    let got = tokens(after);
    // La línea siguiente solo se usa si no es una fecha u hora (antes "10 nov 2026 - 2:54 p.m." daba la «referencia» 20262)
    const looksLikeDate = l => /\d{1,2}:\d{2}|\b(?:a\.?\s?m|p\.?\s?m)\b|\b(?:ene|feb|mar|abr|may|jun|jul|ago|sep|sept|oct|nov|dic|jan|apr|aug|dec)[a-z]*\.?\s+\d{1,2}|\d{1,2}\s+(?:de\s+)?(?:ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic)/i.test(l);
    if (!got.length && lines[i + 1] && !looksLikeDate(lines[i + 1])) got = tokens(lines[i + 1]);
    // Prioridad por etiqueta: «aprobación» y «código de autorización» son la referencia de pago; «transacción» u «operación» solo si no hay otra
    const strength = /aprob|apr[o0c]|autorizaci/i.test(label[0]) ? 6 : (/transacci|operaci|movimiento|seguimiento/i.test(label[0]) ? 0 : 3);
    // Un fragmento que está dentro de otro código de la misma línea ("O695949" dentro de "M2O695949") no es una referencia aparte
    // Números largos que el comprobante parte en varias líneas (ej. Bre-B: número de operación de 35 dígitos en 3 líneas): se unen
    if (got.length) {
      const first = normRef(got[0]);
      if (/^\d{10,}$/.test(first)) {
        const tokenLine = tokens(after).length ? i : i + 1;
        let joined = first;
        for (let k = tokenLine + 1; k <= tokenLine + 4 && lines[k] && /^[\d \-]{4,}$/.test(lines[k]); k++) joined += normRef(lines[k]);
        if (joined.length > first.length && joined.length <= 40) got = [joined, ...got.slice(1)];
      }
    }
    got = got.filter(a => !got.some(b => b !== a && normRef(b).length > normRef(a).length && normRef(b).includes(normRef(a))));
    got.forEach((tok, k) => add(tok, strength + 10 - k));
  });
  return found.sort((a, b) => b.score - a.score).map(f => f.value);
}


const MONTHS = { ene: 1, jan: 1, feb: 2, mar: 3, abr: 4, apr: 4, may: 5, jun: 6, jul: 7, ago: 8, aug: 8, sep: 9, set: 9, oct: 10, nov: 11, dic: 12, dec: 12 };
const monthOf = word => MONTHS[String(word || '').toLowerCase().replace(/[^a-z]/g, '').slice(0, 3)] || null;

// Fecha de la transferencia (AAAA-MM-DD). Acepta 09/11/2026, 2026-11-09, "9 de noviembre de 2026" y "NOV 09 2026"
function extractDate(text, now = new Date()) {
  const t = String(text || '');
  const found = [];
  const push = (index, y, m, d) => {
    y = Number(y); m = Number(m); d = Number(d);
    if (!(m >= 1 && m <= 12 && d >= 1 && d <= 31 && y >= 2000)) return;
    const when = Date.UTC(y, m - 1, d);
    if (new Date(when).getUTCDate() !== d) return;
    const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
    if (when > today + 86400000 || when < today - 400 * 86400000) return;
    found.push({ index, value: `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}` });
  };
  for (const m of t.matchAll(/(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})/g)) push(m.index, m[1], m[2], m[3]);
  for (const m of t.matchAll(/(?<!\d)(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})/g)) push(m.index, m[3], m[2], m[1]);
  for (const m of t.matchAll(/(?<!\d)(\d{1,2})\s*(?:de\s+)?([A-Za-záéíóúÁÉÍÓÚ]{3,10})\.?,?\s*(?:de\s+)?(\d{4})/gi)) { const mo = monthOf(m[2]); if (mo) push(m.index, m[3], mo, m[1]); }
  for (const m of t.matchAll(/([A-Za-z]{3,10})\.?\s+(\d{1,2}),?\s+(\d{4})/g)) { const mo = monthOf(m[1]); if (mo) push(m.index, m[3], mo, m[2]); }
  found.sort((a, b) => a.index - b.index);
  return found.length ? found[0].value : '';
}

// Secuencias numéricas largas del comprobante (posibles cuentas destino), sin espacios ni guiones
function extractAccountNumbers(text) {
  const out = new Set();
  for (const m of String(text || '').matchAll(/\d[\d \-.]{4,24}\d/g)) {
    const digits = m[0].replace(/\D/g, '');
    if (digits.length >= 6 && digits.length <= 22) out.add(digits);
  }
  return [...out];
}

// Posibles referencias SIN etiqueta (códigos mezclados de letras y números o números largos). Solo se sugieren: nunca se rellenan solas
function extractReferenceGuesses(text, exclude = []) {
  const skip = new Set((exclude || []).map(normRef));
  const out = [];
  for (const line of String(text || '').split(/\r?\n/)) {
    if (/\d{1,2}:\d{2}|\b(?:a\.?\s?m|p\.?\s?m)\b|\$/.test(line)) continue; // fechas, horas y valores
    for (const m of line.matchAll(/\b(?=[A-Za-z0-9]*\d)(?=[A-Za-z0-9]*[A-Za-z])[A-Za-z0-9]{8,40}\b|\b\d{8,30}\b/g)) {
      const v = normRef(m[0]);
      if (v.length >= 8 && !skip.has(v) && !out.includes(v)) out.push(v);
    }
  }
  return out.slice(0, 5);
}

function parseAmount(raw) {
  let s = String(raw).replace(/[^\d.,]/g, '');
  if (!s) return null;
  // 150.000 | 150,000 | 1.250.000 | 150.000,00 | 150000
  const lastSep = Math.max(s.lastIndexOf('.'), s.lastIndexOf(','));
  if (lastSep >= 0 && s.length - lastSep - 1 === 2 && /[.,]/.test(s.slice(0, lastSep))) s = s.slice(0, lastSep); // quita centavos
  const value = parseInt(s.replace(/[.,]/g, ''), 10);
  return Number.isFinite(value) && value >= 1000 && value <= 500000000 ? value : null;
}

function extractAmounts(text) {
  const found = new Set();
  for (const m of String(text || '').matchAll(/\$\s*([\d][\d.,]*)/g)) { const v = parseAmount(m[1]); if (v) found.add(v); }
  for (const m of String(text || '').matchAll(/(?:valor|monto|total|enviaste|transferiste|pagaste|enviado|pago)[^\d\n]{0,25}([\d][\d.,]{3,})/gi)) { const v = parseAmount(m[1]); if (v) found.add(v); }
  return [...found];
}

function guessBank(text) {
  const t = String(text || '').toLowerCase();
  // Recargas, consignaciones y depósitos en corresponsal: el banco o billetera que aparece es el DESTINO; no hay banco de origen
  if (/recarga|corresponsal|consignaci[oó]n|dep[oó]sito/.test(t)) return '';
  const banks = [['nequi', 'Nequi'], ['daviplata', 'Daviplata'], ['bancolombia', 'Bancolombia'], ['davivienda', 'Davivienda'], ['bbva', 'BBVA'], ['banco de bogot', 'Banco de Bogotá'], ['occidente', 'Banco de Occidente'], ['agrario', 'Banco Agrario'], ['popular', 'Banco Popular'], ['scotiabank', 'Scotiabank Colpatria'], ['colpatria', 'Scotiabank Colpatria'], ['itau', 'Itaú'], ['av villas', 'AV Villas'], ['caja social', 'Banco Caja Social']];
  // El banco de origen es el primero que aparece en el comprobante, salvo el que viene bajo una etiqueta de destino
  // ("Banco" / "Para" / "Enviado a" / "Destino"), que es el banco que recibe
  const lines = String(text || '').split(/\r?\n/).map(l => l.trim()).filter(Boolean);
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i].toLowerCase();
    const prev = (lines[i - 1] || '').toLowerCase();
    if (/^(?:banco(?:\s+destino)?|banco\s+que\s+recibe|destino|para|enviado\s+a|beneficiario)\s*:?$/.test(prev) || /^banco\s+destino/.test(l)) continue;
    let best = null;
    for (const [needle, name] of banks) {
      const at = l.indexOf(needle);
      if (at >= 0 && (!best || at < best.at)) best = { at, name };
    }
    if (best) return best.name;
  }
  return '';
}

/**
 * Lee un comprobante. Devuelve { available, readable, references, amounts, bank, hash, cached }.
 * El texto completo se guarda solo en memoria (para verificar la referencia) y no se envía al cliente.
 */
async function readProof(buffer) {
  const hash = crypto.createHash('sha256').update(buffer).digest('hex');
  const hit = cache.get(hash);
  if (hit && Date.now() - hit.at < CACHE_TTL_MS) return { ...hit.result, cached: true };
  if (!available()) return { available: false, readable: false, references: [], amounts: [], bank: '', hash, text: '' };
  let result;
  try {
    const started = Date.now();
    const data = await recognize(buffer);
    let text = data.text || '';
    // Fotos torcidas o con sombra: si no apareció ninguna referencia, se lee de nuevo en modo de texto disperso (y por bloques)
    for (const psm of [11, 6]) {
      if (extractReferences(text).length || Date.now() - started > 25000) break;
      try { text += '\n' + ((await recognize(buffer, psm)).text || ''); } catch (_) { /* con la primera lectura basta */ }
    }
    const alnum = text.replace(/[^0-9A-Za-z]/g, '');
    const hasDigits = /\d{4,}/.test(text);
    result = {
      available: true,
      readable: alnum.length >= 20 && hasDigits,
      references: extractReferences(text),
      referenceGuesses: extractReferenceGuesses(text, extractReferences(text)),
      amounts: extractAmounts(text),
      bank: guessBank(text),
      date: extractDate(text),
      accountNumbers: extractAccountNumbers(text),
      confidence: Math.round(data.confidence || 0),
      hash,
      text
    };
  } catch (err) {
    console.warn('⚠️ OCR no pudo leer el comprobante:', err.message);
    return { available: true, error: err.message, readable: false, references: [], amounts: [], bank: '', hash, text: '' };
  }
  cache.set(hash, { at: Date.now(), result });
  if (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value);
  return { ...result, cached: false };
}

/**
 * ¿La referencia escrita es la del comprobante?
 *  MATCH       la referencia aparece en el comprobante
 *  MISMATCH    se leyó el comprobante y la referencia NO aparece
 *  UNREADABLE  no se pudo leer (OCR apagado o imagen ilegible): no se puede validar
 */
function verifyReference(proof, typed) {
  const wanted = lookalike(typed);
  if (!proof || !proof.available || !proof.readable || wanted.length < 4) return { status: 'UNREADABLE', read: (proof && proof.references) || [] };
  const read = proof.references || [];
  if (read.some(r => lookalike(r) === wanted)) return { status: 'MATCH', read };
  // También vale si aparece en el texto del comprobante como una palabra completa (o como un número escrito en grupos,
  // ej. "1843 852 709"). Antes bastaba con que estuviera dentro del texto pegado, y fragmentos de la fecha o la hora
  // (ej. "2026 - 2:54") daban por buena una referencia falsa como 20262.
  // Números partidos en varias líneas consecutivas de solo dígitos
  const allLines = String(proof.text || '').split(/\r?\n/).map(l => l.trim());
  for (let i = 0; i < allLines.length; i++) {
    if (!/^[\d \-]{4,}$/.test(allLines[i])) continue;
    let joined = normRef(allLines[i]);
    for (let k = i + 1; k <= i + 4 && /^[\d \-]{4,}$/.test(allLines[k] || ''); k++) {
      joined += normRef(allLines[k]);
      if (lookalike(joined) === wanted) return { status: 'MATCH', read };
    }
  }
  for (const line of String(proof.text || '').split(/\r?\n/)) {
    const words = line.split(/[^0-9A-Za-z]+/).filter(Boolean);
    if (words.some(w => lookalike(w) === wanted)) return { status: 'MATCH', read };
    for (let i = 0; i < words.length; i++) {
      let joined = '';
      for (let j = i; j < Math.min(words.length, i + 4); j++) {
        if (!/^\d+$/.test(words[j])) break;
        joined += words[j];
        if (j > i && joined.length >= 8 && lookalike(joined) === wanted) return { status: 'MATCH', read };
      }
    }
  }
  return { status: 'MISMATCH', read };
}

module.exports = { available, readProof, verifyReference, extractReferenceGuesses, extractDate, extractAccountNumbers, extractReferences, extractAmounts, guessBank, normRef };
