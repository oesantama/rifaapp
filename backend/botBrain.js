// backend/botBrain.js
// Configuración y lógica "editable" del chatbot de WhatsApp (sin IA externa: reglas + respuestas que el
// administrador mantiene desde el panel Control → Entrenar Bot). Se guarda en company.botConfig.

const DEFAULT_HOW_HEARD = ['Facebook', 'Instagram', 'TikTok', 'Estado de WhatsApp', 'Un asesor', 'Un amigo o familiar', 'Otro'];

const DEFAULT_HANDOFF_KEYWORDS = [
  'asesor', 'asesora', 'humano', 'persona', 'agente', 'hablar con', 'comercial', 'llamar', 'atencion'
];

const LIMITS = {
  faqs: 100,
  keywordsPerFaq: 20,
  keywordLen: 60,
  titleLen: 80,
  answerLen: 1500,
  messageLen: 1000,
  options: 10,
  optionLen: 40
};

function defaultConfig() {
  return {
    greeting: '',
    faqs: [],
    handoff: {
      enabled: true,
      keywords: [...DEFAULT_HANDOFF_KEYWORDS],
      message: '',
      notifyNumber: '',
      autoAfterFails: 2,
      resumeHours: 4
    },
    howHeard: { enabled: true, options: [...DEFAULT_HOW_HEARD] }
  };
}

/** Texto en minúsculas, sin tildes ni signos, para comparar mensajes. */
function normalize(text) {
  return String(text || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9ñ\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Configuración de la empresa mezclada con los valores por defecto. */
function getBotConfig(company) {
  const base = defaultConfig();
  const saved = (company && company.botConfig) || {};
  return {
    greeting: typeof saved.greeting === 'string' ? saved.greeting : base.greeting,
    faqs: Array.isArray(saved.faqs) ? saved.faqs : base.faqs,
    handoff: { ...base.handoff, ...(saved.handoff || {}) },
    howHeard: {
      enabled: saved.howHeard && typeof saved.howHeard.enabled === 'boolean' ? saved.howHeard.enabled : base.howHeard.enabled,
      options: saved.howHeard && Array.isArray(saved.howHeard.options) && saved.howHeard.options.length
        ? saved.howHeard.options
        : base.howHeard.options
    }
  };
}

function cleanString(value, max) {
  return String(value == null ? '' : value).replace(/\r/g, '').trim().slice(0, max);
}

function cleanList(value, maxItems, maxLen) {
  const list = Array.isArray(value) ? value : String(value || '').split(/[\n,]+/);
  const out = [];
  for (const item of list) {
    const text = cleanString(item, maxLen);
    if (text && !out.some(o => normalize(o) === normalize(text))) out.push(text);
    if (out.length >= maxItems) break;
  }
  return out;
}

/** Valida y limpia lo que envía el panel. Devuelve { config } o { error }. */
function sanitizeConfig(input, previous) {
  if (!input || typeof input !== 'object') return { error: 'Configuración inválida.' };
  const prev = getBotConfig({ botConfig: previous });
  const next = defaultConfig();

  if (input.greeting !== undefined) next.greeting = cleanString(input.greeting, LIMITS.messageLen);
  else next.greeting = prev.greeting;

  const rawFaqs = input.faqs !== undefined ? input.faqs : prev.faqs;
  if (!Array.isArray(rawFaqs)) return { error: 'La lista de respuestas no es válida.' };
  if (rawFaqs.length > LIMITS.faqs) return { error: `Máximo ${LIMITS.faqs} respuestas.` };
  const prevById = new Map(prev.faqs.map(f => [f.id, f]));
  const faqs = [];
  for (const raw of rawFaqs) {
    const title = cleanString(raw && raw.title, LIMITS.titleLen);
    const answer = cleanString(raw && raw.answer, LIMITS.answerLen);
    const keywords = cleanList(raw && raw.keywords, LIMITS.keywordsPerFaq, LIMITS.keywordLen).filter(k => normalize(k).length >= 2);
    if (!title && !answer && keywords.length === 0) continue;
    if (!answer) return { error: `La respuesta "${title || keywords[0] || ''}" no tiene texto.` };
    if (keywords.length === 0) return { error: `La respuesta "${title || answer.slice(0, 20)}" necesita al menos una palabra clave.` };
    const id = raw.id && prevById.has(raw.id) ? raw.id : (typeof raw.id === 'string' && /^faq-[\w-]{4,40}$/.test(raw.id) ? raw.id : `faq-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`);
    faqs.push({
      id,
      title: title || keywords[0],
      keywords,
      answer,
      active: raw.active !== false,
      hits: prevById.get(id) ? prevById.get(id).hits || 0 : 0
    });
  }
  next.faqs = faqs;

  const h = input.handoff || {};
  const ph = prev.handoff;
  next.handoff = {
    enabled: h.enabled === undefined ? ph.enabled : h.enabled === true,
    keywords: h.keywords === undefined ? ph.keywords : cleanList(h.keywords, 30, LIMITS.keywordLen),
    message: h.message === undefined ? ph.message : cleanString(h.message, LIMITS.messageLen),
    notifyNumber: h.notifyNumber === undefined ? ph.notifyNumber : cleanString(h.notifyNumber, 20).replace(/[^\d+]/g, ''),
    autoAfterFails: h.autoAfterFails === undefined ? ph.autoAfterFails : Math.max(0, Math.min(10, parseInt(h.autoAfterFails, 10) || 0)),
    resumeHours: h.resumeHours === undefined ? ph.resumeHours : Math.max(1, Math.min(72, parseInt(h.resumeHours, 10) || 4))
  };

  const hh = input.howHeard || {};
  const phh = prev.howHeard;
  const options = hh.options === undefined ? phh.options : cleanList(hh.options, LIMITS.options, LIMITS.optionLen);
  next.howHeard = {
    enabled: hh.enabled === undefined ? phh.enabled : hh.enabled === true,
    options: options.length ? options : [...DEFAULT_HOW_HEARD]
  };
  return { config: next };
}

/** ¿El mensaje activa una respuesta personalizada? Devuelve la de mayor coincidencia o null. */
function matchFaq(config, text) {
  const t = normalize(text);
  if (!t || /^\d+$/.test(t)) return null;
  const padded = ` ${t} `;
  const tokens = new Set(t.split(' '));
  let best = null;
  let bestScore = 0;
  for (const faq of config.faqs || []) {
    if (faq.active === false) continue;
    for (const kw of faq.keywords || []) {
      const k = normalize(kw);
      if (!k) continue;
      const kTokens = k.split(' ');
      let score = 0;
      if (padded.includes(` ${k} `)) score = kTokens.length * 10 + k.length / 100;
      else if (kTokens.length >= 2 && kTokens.every(w => tokens.has(w))) score = kTokens.length * 5 + k.length / 100;
      if (score > bestScore) { bestScore = score; best = faq; }
    }
  }
  return best;
}

/** ¿El cliente pide hablar con una persona? */
function isHandoffRequest(config, text) {
  if (!config.handoff.enabled) return false;
  const t = normalize(text);
  if (!t) return false;
  if (t === '2') return true; // opción 2 del menú: hablar con un asesor
  const padded = ` ${t} `;
  return (config.handoff.keywords || []).some(kw => {
    const k = normalize(kw);
    return k && padded.includes(` ${k} `);
  });
}

const GREETINGS = ['hola', 'buenas', 'buenos dias', 'buen dia', 'buenas tardes', 'buenas noches', 'menu', 'ayuda', 'inicio', 'info', 'informacion', 'gracias', 'ok', 'listo'];
function isGreeting(text) {
  const t = normalize(text);
  return GREETINGS.some(g => t === g || t.startsWith(`${g} `));
}

/** Rellena {empresa}, {rifa}, {precio}, {fecha} en una respuesta personalizada. */
function fillPlaceholders(answer, vars) {
  return String(answer).replace(/\{(\w+)\}/g, (m, key) => (vars && vars[key] !== undefined && vars[key] !== null ? String(vars[key]) : m));
}

module.exports = {
  DEFAULT_HOW_HEARD,
  LIMITS,
  normalize,
  getBotConfig,
  sanitizeConfig,
  matchFaq,
  isHandoffRequest,
  isGreeting,
  fillPlaceholders
};
