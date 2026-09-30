// Security helpers: password hashing, data encryption at rest, signed session tokens
// and login throttling. Uses only Node's built-in crypto module.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const SECRETS_DIR = process.env.SECRETS_DIR || path.join(__dirname, 'secrets');
const KEY_FILE = path.join(SECRETS_DIR, 'data.key');
const ENCRYPTED_FORMAT = 'rifamaster-enc';
const BACKUP_FORMAT = 'rifamaster-backup';

// ---------------------------------------------------------------------------
// Master key (AES-256). Source: DATA_ENCRYPTION_KEY (base64 or hex, 32 bytes)
// or secrets/data.key. Losing this key makes the encrypted data unreadable.
// ---------------------------------------------------------------------------
let masterKey = null;

function parseKey(raw) {
  const value = raw.trim();
  const buf = /^[0-9a-fA-F]{64}$/.test(value) ? Buffer.from(value, 'hex') : Buffer.from(value, 'base64');
  if (buf.length !== 32) throw new Error('La llave de cifrado debe tener 32 bytes (base64 o hex).');
  return buf;
}

/**
 * Loads the master key. When `allowCreate` is true and no key exists, a new one
 * is generated and saved to secrets/data.key (mode 600).
 * Returns null when there is no key and it may not be created.
 */
function loadMasterKey({ allowCreate }) {
  if (masterKey) return masterKey;
  if (process.env.DATA_ENCRYPTION_KEY) {
    masterKey = parseKey(process.env.DATA_ENCRYPTION_KEY);
    return masterKey;
  }
  if (fs.existsSync(KEY_FILE)) {
    masterKey = parseKey(fs.readFileSync(KEY_FILE, 'utf8'));
    return masterKey;
  }
  if (!allowCreate) return null;
  fs.mkdirSync(SECRETS_DIR, { recursive: true, mode: 0o700 });
  const key = crypto.randomBytes(32);
  fs.writeFileSync(KEY_FILE, key.toString('base64') + '\n', { mode: 0o600 });
  console.log(`🔐 Nueva llave de cifrado creada en ${KEY_FILE}. ¡Haga una copia segura de este archivo!`);
  masterKey = key;
  return masterKey;
}

function hasMasterKey() {
  return masterKey !== null;
}

// Without a master key, session tokens are signed with a per-process random key
// (users simply log in again after a restart). Data encryption always needs the master key.
let ephemeralTokenKey = null;

function deriveKey(label) {
  if (!masterKey) {
    if (label === 'auth-token') return (ephemeralTokenKey ||= crypto.randomBytes(32));
    throw new Error('Llave maestra no cargada');
  }
  return Buffer.from(crypto.hkdfSync('sha256', masterKey, Buffer.from('rifamaster'), Buffer.from(label), 32));
}

// ---------------------------------------------------------------------------
// Encryption at rest (AES-256-GCM)
// ---------------------------------------------------------------------------
function encryptObject(obj, format = ENCRYPTED_FORMAT) {
  const key = deriveKey('data-encryption');
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const data = Buffer.concat([cipher.update(JSON.stringify(obj), 'utf8'), cipher.final()]);
  return {
    format,
    version: 1,
    alg: 'aes-256-gcm',
    iv: iv.toString('base64'),
    tag: cipher.getAuthTag().toString('base64'),
    data: data.toString('base64'),
  };
}

function isEncryptedEnvelope(value) {
  return !!value && typeof value === 'object' && (value.format === ENCRYPTED_FORMAT || value.format === BACKUP_FORMAT) && !!value.data;
}

function decryptObject(envelope) {
  const key = deriveKey('data-encryption');
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(envelope.iv, 'base64'));
  decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
  const plain = Buffer.concat([decipher.update(Buffer.from(envelope.data, 'base64')), decipher.final()]);
  return JSON.parse(plain.toString('utf8'));
}

// ---------------------------------------------------------------------------
// Password hashing (scrypt). Stored as scrypt$N$r$p$salt$hash
// ---------------------------------------------------------------------------
const SCRYPT = { N: 16384, r: 8, p: 1, keylen: 64 };

function isPasswordHash(value) {
  return typeof value === 'string' && value.startsWith('scrypt$');
}

function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.scryptSync(String(password), salt, SCRYPT.keylen, { N: SCRYPT.N, r: SCRYPT.r, p: SCRYPT.p });
  return ['scrypt', SCRYPT.N, SCRYPT.r, SCRYPT.p, salt.toString('base64'), hash.toString('base64')].join('$');
}

function verifyPassword(password, stored) {
  if (typeof password !== 'string' || !password || typeof stored !== 'string' || !stored) return false;
  if (!isPasswordHash(stored)) return false;
  const [, N, r, p, saltB64, hashB64] = stored.split('$');
  const expected = Buffer.from(hashB64, 'base64');
  const actual = crypto.scryptSync(password, Buffer.from(saltB64, 'base64'), expected.length, {
    N: Number(N),
    r: Number(r),
    p: Number(p),
  });
  return crypto.timingSafeEqual(actual, expected);
}

/** Minimum policy for new passwords: 8+ characters with letters and numbers. */
function validatePasswordPolicy(password) {
  if (typeof password !== 'string' || password.length < 8) return 'La contraseña debe tener al menos 8 caracteres.';
  if (!/[A-Za-zÁÉÍÓÚáéíóúÑñ]/.test(password) || !/\d/.test(password)) return 'La contraseña debe combinar letras y números.';
  if (password.length > 128) return 'La contraseña es demasiado larga.';
  return null;
}

// Hash used to spend the same time when the user does not exist (avoids user enumeration by timing)
let dummyHash = null;
function burnPasswordCheck(password) {
  if (!dummyHash) dummyHash = hashPassword('dummy-password-1');
  verifyPassword(String(password || ''), dummyHash);
}

// ---------------------------------------------------------------------------
// Signed session tokens (HMAC-SHA256)
// ---------------------------------------------------------------------------
const TOKEN_TTL_MS = 12 * 60 * 60 * 1000;

function b64url(buf) {
  return Buffer.from(buf).toString('base64url');
}

function signToken(payload) {
  const body = { ...payload, iat: Date.now(), exp: Date.now() + TOKEN_TTL_MS };
  const encoded = b64url(JSON.stringify(body));
  const sig = crypto.createHmac('sha256', deriveKey('auth-token')).update(encoded).digest('base64url');
  return { token: `${encoded}.${sig}`, expiresAt: new Date(body.exp).toISOString() };
}

function verifyToken(token) {
  if (typeof token !== 'string' || !token.includes('.')) return null;
  const [encoded, sig] = token.split('.');
  const expected = crypto.createHmac('sha256', deriveKey('auth-token')).update(encoded).digest();
  let given;
  try {
    given = Buffer.from(sig, 'base64url');
  } catch (_) {
    return null;
  }
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return null;
  try {
    const payload = JSON.parse(Buffer.from(encoded, 'base64url').toString('utf8'));
    if (!payload.exp || Date.now() > payload.exp) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

/** Short fingerprint of the password hash: changing the password invalidates old tokens. */
function passwordVersion(hash) {
  return crypto.createHash('sha256').update(String(hash || '')).digest('base64url').slice(0, 12);
}

// ---------------------------------------------------------------------------
// Login throttling: 5 failed attempts per user+IP => 15 minute lock
// ---------------------------------------------------------------------------
const MAX_ATTEMPTS = 5;
const LOCK_MS = 15 * 60 * 1000;
const attempts = new Map();

function throttleKey(ip, username) {
  return `${ip}|${String(username || '').toLowerCase()}`;
}

function isLocked(ip, username) {
  const entry = attempts.get(throttleKey(ip, username));
  if (!entry || !entry.lockedUntil) return 0;
  const remaining = entry.lockedUntil - Date.now();
  if (remaining <= 0) {
    attempts.delete(throttleKey(ip, username));
    return 0;
  }
  return remaining;
}

function registerFailure(ip, username) {
  const key = throttleKey(ip, username);
  const entry = attempts.get(key) || { count: 0, lockedUntil: 0 };
  entry.count += 1;
  if (entry.count >= MAX_ATTEMPTS) entry.lockedUntil = Date.now() + LOCK_MS;
  attempts.set(key, entry);
  return MAX_ATTEMPTS - entry.count;
}

function clearFailures(ip, username) {
  attempts.delete(throttleKey(ip, username));
}

// ---------------------------------------------------------------------------
// Removes credential fields from anything sent to clients
// ---------------------------------------------------------------------------
const SECRET_KEYS = new Set(['password', 'adminPassword', 'passwordHash', 'adminPasswordHash']);

function stripSecrets(value) {
  if (Array.isArray(value)) return value.map(stripSecrets);
  if (value && typeof value === 'object' && !(value instanceof Date)) {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      if (SECRET_KEYS.has(k)) continue;
      out[k] = stripSecrets(v);
    }
    return out;
  }
  return value;
}

module.exports = {
  ENCRYPTED_FORMAT,
  BACKUP_FORMAT,
  KEY_FILE,
  loadMasterKey,
  hasMasterKey,
  encryptObject,
  decryptObject,
  isEncryptedEnvelope,
  isPasswordHash,
  hashPassword,
  verifyPassword,
  validatePasswordPolicy,
  burnPasswordCheck,
  signToken,
  verifyToken,
  passwordVersion,
  isLocked,
  registerFailure,
  clearFailures,
  stripSecrets,
};
