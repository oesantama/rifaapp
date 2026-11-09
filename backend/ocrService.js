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

/** Texto de la imagen. Las lecturas se hacen de a una para no saturar el servidor. */
function recognize(buffer) {
  const job = queue.then(async () => {
    const w = await getWorker();
    const run = w.recognize(buffer);
    const result = await Promise.race([run, new Promise((_, rej) => setTimeout(() => rej(new Error('OCR demasiado lento')), TIMEOUT_MS))]);
    touchIdle();
    return result.data;
  });
  queue = job.catch(() => {});
  return job;
}

// ---------------------------------------------------------------------------
// Interpretación del texto
// ---------------------------------------------------------------------------
const REF_LABEL = /(referencia|\bref\b\.?|comprobante|aprobaci[oó]n|transacci[oó]n|c[oó]digo\s+de\s+(?:aprobaci[oó]n|confirmaci[oó]n)|\bcus\b|n[uú]mero\s+de\s+(?:aprobaci[oó]n|comprobante|transacci[oó]n|referencia|pago|operaci[oó]n)|n[o°º]\.?\s+de\s+operaci[oó]n|operaci[oó]n\s*(?:n[o°º]\.?|#|:))/i;

const normRef = s => String(s || '').toUpperCase().replace(/[^0-9A-Z]/g, '');
// El OCR confunde letras y números parecidos: se comparan con la misma equivalencia en ambos lados
const lookalike = s => normRef(s).replace(/O|Q|D/g, '0').replace(/[IL|]/g, '1').replace(/Z/g, '2').replace(/S/g, '5').replace(/B/g, '8');

function extractReferences(text) {
  const lines = String(text || '').split(/\r?\n/).map(l => l.trim()).filter(Boolean);
  const found = [];
  const add = (raw, score) => {
    const value = normRef(raw);
    const digits = (value.match(/\d/g) || []).length;
    if (value.length < 5 || value.length > 40 || digits < 4) return;
    if (!found.some(f => f.value === value)) found.push({ value, score });
  };
  const tokens = line => {
    const out = [];
    // números con espacios o guiones internos (ej: "1843 852 709") y códigos con letra (ej: "M18437283")
    for (const m of line.matchAll(/[A-Za-z]?\d[\d \-]{3,38}\d|[A-Za-z]\d{5,}/g)) out.push(m[0]);
    return out;
  };
  lines.forEach((line, i) => {
    const label = REF_LABEL.exec(line);
    if (!label) return;
    const after = line.slice(label.index + label[0].length);
    let got = tokens(after);
    if (!got.length && lines[i + 1]) got = tokens(lines[i + 1]);
    got.forEach((tok, k) => add(tok, 10 - k));
  });
  return found.sort((a, b) => b.score - a.score).map(f => f.value);
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
  const banks = [['nequi', 'Nequi'], ['daviplata', 'Daviplata'], ['bancolombia', 'Bancolombia'], ['davivienda', 'Davivienda'], ['bbva', 'BBVA'], ['banco de bogot', 'Banco de Bogotá'], ['occidente', 'Banco de Occidente'], ['agrario', 'Banco Agrario'], ['popular', 'Banco Popular'], ['scotiabank', 'Scotiabank Colpatria'], ['colpatria', 'Scotiabank Colpatria'], ['itau', 'Itaú'], ['av villas', 'AV Villas'], ['caja social', 'Banco Caja Social']];
  // El banco de origen es el primero que aparece en el comprobante (el destino suele ir después)
  let best = null;
  for (const [needle, name] of banks) {
    const at = t.indexOf(needle);
    if (at >= 0 && (!best || at < best.at)) best = { at, name };
  }
  return best ? best.name : '';
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
    const data = await recognize(buffer);
    const text = data.text || '';
    const alnum = text.replace(/[^0-9A-Za-z]/g, '');
    const hasDigits = /\d{4,}/.test(text);
    result = {
      available: true,
      readable: alnum.length >= 20 && hasDigits,
      references: extractReferences(text),
      amounts: extractAmounts(text),
      bank: guessBank(text),
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
  // La referencia también vale si aparece en cualquier parte del texto del comprobante
  if (lookalike(proof.text).includes(wanted)) return { status: 'MATCH', read };
  return { status: 'MISMATCH', read };
}

module.exports = { available, readProof, verifyReference, extractReferences, extractAmounts, guessBank, normRef };
