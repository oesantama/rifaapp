// backend/whatsappService.js
// Servicio de integración con Evolution API para WhatsApp Bots
// Soporta SuperAdmin (Planes), Empresa (Rifas oficiales) y Asesores Independientes (Talonarios)

const EVOLUTION_URL = process.env.EVOLUTION_URL || 'http://evolution_api:8080';
const EVOLUTION_APIKEY = process.env.EVOLUTION_APIKEY || 'rifaapp_evo_secret_key_2026';
const PUBLIC_WEBHOOK_URL = process.env.PUBLIC_WEBHOOK_URL || 'http://45.137.192.195/api/whatsapp/webhook';
const botBrain = require('./botBrain');
const driveService = require('./driveService');
const ocrService = require('./ocrService');
const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL || 'https://williamrifas.santamariapp.com').replace(/\/+$/, '');

/**
 * Normaliza números telefónicos para WhatsApp:
 * Si es un número colombiano de 10 dígitos (inicia en 3), le antepone automáticamente el 57.
 */
function formatPhoneNumber(number) {
  let clean = String(number || '').replace(/[^0-9]/g, '');
  if (clean.length === 10 && clean.startsWith('3')) {
    clean = '57' + clean;
  }
  return clean;
}

function getInstanceName(auth) {
  if (!auth) return 'rifaapp_bot';
  if (auth.role === 'superadmin') {
    return 'superadmin_sales';
  }
  if (auth.role === 'asesor') {
    const id = auth.record?.id || auth.record?.advisorId || 'advisor';
    return `asesor_${id}`.toLowerCase().replace(/[^a-z0-9_]/g, '');
  }
  // Admin / Company
  const companyId = auth.record?.code || auth.record?.id || 'empresa';
  return `empresa_${companyId}`.toLowerCase().replace(/[^a-z0-9_]/g, '');
}

async function evoRequest(endpoint, options = {}) {
  const url = `${EVOLUTION_URL}${endpoint}`;
  const headers = {
    'apikey': EVOLUTION_APIKEY,
    'Content-Type': 'application/json',
    ...(options.headers || {})
  };
  try {
    const res = await fetch(url, {
      ...options,
      headers
    });
    const text = await res.text();
    let data;
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
    return { ok: res.ok, status: res.status, data };
  } catch (err) {
    return { ok: false, status: 500, error: err.message };
  }
}

// Cada llamada a /instance/connect abre un socket nuevo de Baileys. Si se llama en cada consulta de estado
// (el front consulta cada pocos segundos) los sockets se "reemplazan" entre sí (conflict/replaced) en un bucle
// infinito y la sesión se cae y se reconecta sola. Por eso se limita a 1 llamada cada 40 s por instancia y se
// reutiliza el último QR.
const CONNECT_MIN_INTERVAL_MS = 40000;
const connectCache = new Map(); // instanceName -> { at, qrcode, pairingCode }

async function requestConnect(instanceName, query = '', force = false) {
  const cached = connectCache.get(instanceName);
  if (!force && cached && Date.now() - cached.at < CONNECT_MIN_INTERVAL_MS) {
    return { qrcode: cached.qrcode, pairingCode: cached.pairingCode, cached: true };
  }
  const connectRes = await evoRequest(`/instance/connect/${instanceName}${query}`);
  const entry = {
    at: Date.now(),
    qrcode: connectRes.data?.base64 || null,
    pairingCode: connectRes.data?.pairingCode || null
  };
  connectCache.set(instanceName, entry);
  return { qrcode: entry.qrcode, pairingCode: entry.pairingCode, cached: false };
}

/**
 * Obtiene el estado actual de la instancia WhatsApp y el QR si está pendiente de conexión.
 */
async function getStatus(instanceName) {
  const stateRes = await evoRequest(`/instance/connectionState/${instanceName}`);
  if (!stateRes.ok) {
    if (stateRes.status === 404) {
      return { state: 'not_created', instanceName, qrcode: null };
    }
    return { state: 'error', instanceName, error: stateRes.error || stateRes.data };
  }

  const state = stateRes.data?.instance?.state || 'close';

  if (state === 'open') {
    connectCache.delete(instanceName);
    // El estado de conexión no trae el número: se consulta la instancia (ownerJid = número vinculado)
    let number = stateRes.data?.instance?.owner || null;
    let profileName = null;
    const info = await evoRequest(`/instance/fetchInstances?instanceName=${encodeURIComponent(instanceName)}`);
    const rec = Array.isArray(info.data) ? info.data[0] : info.data;
    const jid = rec?.ownerJid || rec?.instance?.owner || rec?.owner;
    if (jid) number = String(jid).split('@')[0].split(':')[0];
    profileName = rec?.profileName || rec?.instance?.profileName || null;
    return {
      state: 'open',
      instanceName,
      qrcode: null,
      number,
      profileName
    };
  }

  const { qrcode, pairingCode } = await requestConnect(instanceName);
  return { state, instanceName, qrcode, pairingCode };
}

/**
 * Inicia la creación o renovación de sesión de la instancia.
 * phoneNumber es opcional (para Pairing Code de 8 dígitos).
 */
async function connectInstance(instanceName, phoneNumber = null) {
  const formattedNumber = phoneNumber ? formatPhoneNumber(phoneNumber) : null;
  await evoRequest('/instance/create', {
    method: 'POST',
    body: JSON.stringify({
      instanceName,
      qrcode: !formattedNumber,
      number: formattedNumber || undefined,
      integration: 'WHATSAPP-BAILEYS',
      webhook: {
        enabled: true,
        url: PUBLIC_WEBHOOK_URL,
        byEvents: false,
        base64: true,
        events: ['MESSAGES_UPSERT', 'CONNECTION_UPDATE']
      }
    })
  });

  const query = formattedNumber ? `?number=${encodeURIComponent(formattedNumber)}` : '';
  const { qrcode, pairingCode } = await requestConnect(instanceName, query);

  return {
    state: 'connecting',
    instanceName,
    qrcode,
    pairingCode
  };
}

/**
 * Desconecta la sesión de WhatsApp y VERIFICA que realmente quedó cerrada. Si Evolution sigue reportando
 * la sesión abierta/conectando (sesión pegada), elimina la instancia para forzar un QR nuevo al reconectar.
 */
async function disconnectInstance(instanceName) {
  connectCache.delete(instanceName);
  const res = await evoRequest(`/instance/logout/${instanceName}`, { method: 'DELETE' });
  let state = 'unknown';
  for (let i = 0; i < 4; i++) {
    await new Promise(r => setTimeout(r, 1500));
    const st = await evoRequest(`/instance/connectionState/${instanceName}`);
    state = st.ok ? (st.data?.instance?.state || 'close') : (st.status === 404 ? 'not_created' : 'unknown');
    if (state === 'close' || state === 'not_created') break;
  }
  let deleted = false;
  if (state !== 'close' && state !== 'not_created') {
    const del = await evoRequest(`/instance/delete/${instanceName}`, { method: 'DELETE' });
    deleted = del.ok;
    state = deleted ? 'not_created' : state;
  }
  connectCache.delete(instanceName);
  return { ok: state === 'close' || state === 'not_created', state, forcedDelete: deleted, data: res.data };
}

/**
 * Envía un archivo (ej: el Excel de pagos) por WhatsApp. buffer = contenido del archivo.
 */
async function sendDocument(instanceName, number, { buffer, fileName, caption = '', mimetype = 'application/octet-stream' }) {
  return evoRequest(`/message/sendMedia/${instanceName}`, {
    method: 'POST',
    body: JSON.stringify({
      number: formatPhoneNumber(number),
      mediatype: 'document',
      mimetype,
      caption,
      fileName,
      media: Buffer.from(buffer).toString('base64')
    })
  });
}

// Quien necesite recibir documentos (ej: el Excel devuelto de AGIL) se registra aquí
let documentHandler = null;
function setDocumentHandler(fn) { documentHandler = fn; }

/** Descarga el contenido de un archivo recibido cuando el webhook no lo trae en base64. */
async function fetchMediaBase64(instanceName, key) {
  const res = await evoRequest(`/chat/getBase64FromMediaMessage/${instanceName}`, {
    method: 'POST',
    body: JSON.stringify({ message: { key }, convertToMp4: false })
  });
  return (res.ok && res.data && res.data.base64) || null;
}

/**
 * Envía un mensaje de texto por WhatsApp con formateo de número automático
 */
async function sendTextMessage(instanceName, number, text) {
  const targetNumber = formatPhoneNumber(number);
  return evoRequest(`/message/sendText/${instanceName}`, {
    method: 'POST',
    body: JSON.stringify({
      number: targetNumber,
      text: text
    })
  });
}

// Memoria y persistencia de sesiones conversacionales por WhatsApp
const localSessions = new Map();

function getSession(senderPhone, db) {
  const cleanPhone = formatPhoneNumber(senderPhone);
  if (db && db.whatsappSessions && db.whatsappSessions[cleanPhone]) {
    return db.whatsappSessions[cleanPhone];
  }
  return localSessions.get(cleanPhone) || null;
}

function updateSession(senderPhone, data, db, saveDBCallback, raffleId) {
  const cleanPhone = formatPhoneNumber(senderPhone);
  const updated = {
    ...(getSession(senderPhone, db) || {}),
    ...data,
    updatedAt: Date.now()
  };
  localSessions.set(cleanPhone, updated);
  if (db) {
    db.whatsappSessions = db.whatsappSessions || {};
    db.whatsappSessions[cleanPhone] = updated;
    if (typeof saveDBCallback === 'function') {
      saveDBCallback(raffleId);
    }
  }
  return updated;
}

/**
 * Normaliza nombres a formato Capitalizado (Title Case)
 */
function cleanTitle(str) {
  if (!str) return '';
  return str.trim().split(/\s+/).map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join(' ');
}

function getBusinessDisplayName(company) {
  if (!company) return 'Santa María';
  const raw = company.name || company.companyName || '';
  if (/santamaria/i.test(raw)) return 'Santa María';
  return raw || 'Santa María';
}

function parseRange(str) {
  if (!str) return null;
  const parts = String(str).trim().split('-');
  const start = parseInt(parts[0], 10);
  const end = parts.length > 1 ? parseInt(parts[1], 10) : start;
  if (isNaN(start) || isNaN(end) || start < 0 || end < start) return null;
  return { start, end };
}

function ticketNumbersOf(ticket) {
  const nums = (ticket.numbers || []).map(n => parseInt(n, 10)).filter(n => !isNaN(n));
  return nums.length ? nums : [ticket.ticketNumber];
}

function ticketInAdvisorRanges(ticket, advisor) {
  if (!advisor || advisor.mode !== 'ASSIGNED') return true;
  const ranges = (advisor.assignedTicketRanges || []).map(parseRange).filter(Boolean);
  if (!ranges.length) return true;
  return ticketNumbersOf(ticket).some(n => ranges.some(r => n >= r.start && n <= r.end));
}

function getAssignedAdvisorForTicket(ticket, raffle, db) {
  if (!ticket) return null;
  const companyId = raffle?.companyId || ticket.companyId;
  if (ticket.advisorId) {
    const direct = (db.advisors || []).find(a => a.id === ticket.advisorId);
    // Cada asesor pertenece a una sola empresa: uno de otra empresa nunca se asigna
    if (direct && (!companyId || direct.companyId === companyId)) return direct;
  }
  const advisors = (db.advisors || []).filter(a => 
    (!companyId || a.companyId === companyId) && 
    a.status === 'ACTIVO' && 
    a.mode === 'ASSIGNED' && 
    Array.isArray(a.assignedTicketRanges) && 
    a.assignedTicketRanges.length > 0
  );
  for (const adv of advisors) {
    if (ticketInAdvisorRanges(ticket, adv)) {
      return adv;
    }
  }
  return null;
}

function buildMainMenuMessage(companyName, advisor = null) {
  let msg = `👋 ¡Hola! Te comunicas con *${companyName}* 🏢✨\n`;
  if (advisor) {
    msg = `👋 ¡Hola! Te atiende *${advisor.name}*, asesor oficial de *${companyName}* 🏢✨\n`;
  }
  msg += `_Rifas y Sorteos Oficiales_\n\n`;
  msg += `Con gusto te atendemos. Por favor elige una opción:\n\n`;
  msg += `1️⃣ 🎟️ *Rifas y Sorteos Oficiales*\n`;
  msg += `   (Consulta de boletas, números disponibles, plan de premios y pagos)\n\n`;
  msg += `2️⃣ 👤 *Hablar con un Asesor*\n`;
  msg += `   (Atención humana personalizada para cualquier consulta)\n\n`;
  msg += `👉 _Responde con el número de tu opción (*1* o *2*) o cuéntanos qué necesitas._`;
  return msg;
}

function buildAdvisorHandOffMessage(companyName, advisor = null) {
  let msg = `👤 *¡TRANSFERIDO A ATENCIÓN HUMANA!* 📲✨\n\n`;
  if (advisor) {
    msg += `Nuestro asesor *${advisor.name}* de *${companyName}* ha sido notificado y te responderá directamente por este mismo chat en breve.\n\n`;
  } else {
    msg += `Hemos notificado a nuestro equipo de *${companyName}*. Un asesor humano se comunicará contigo por este mismo chat a la brevedad.\n\n`;
  }
  msg += `_(Hemos pausado las respuestas automáticas para este chat para que puedas conversar libremente con el asesor).\n\n`;
  msg += `💡 *Si en cualquier momento deseas volver al menú automático, solo escribe MENU o BOT.*`;
  return msg;
}

function buildRaffleMessage(mainRaffle, companyName, digits, opportunities, ticketPrice, drawDateFormatted, lotteryName) {
  let msg = `🎟️ *RIFAS Y SORTEOS OFICIALES - ${companyName}* 🏆\n\n`;
  msg += `🎯 *Gran Sorteo:* ${mainRaffle.title}\n`;
  if (mainRaffle.description) msg += `🏆 *Premio Mayor:* ${mainRaffle.description}\n`;
  msg += `🔢 *Modalidad:* ${digits} cifras (${opportunities} oportunidades por boleta)\n`;
  msg += `📅 *Juega el:* ${drawDateFormatted} con ${lotteryName}\n`;
  msg += `💵 *Valor Boleta:* $${ticketPrice.toLocaleString('es-CO')} COP\n`;
  if (mainRaffle.minAbono) msg += `💰 *Abono Mínimo:* $${Number(mainRaffle.minAbono).toLocaleString('es-CO')} COP\n`;
  msg += `\n📌 *¿Qué deseas hacer?*\n`;
  msg += `• Escribe un *número de ${digits} cifras* para consultar si está libre (ej: ${digits === 4 ? '1987' : '428'}).\n`;
  msg += `• Escribe *DISPONIBLES* para ver opciones libres al azar.\n`;
  msg += `• Escribe *PREMIOS* para conocer el plan de premios y semanales.\n`;
  msg += `• Escribe *CUENTAS* para ver los medios de pago (Nequi / Bancolombia).\n`;
  msg += `• Envía la *foto de tu comprobante* si ya realizaste tu pago.\n`;
  msg += `• Escribe *MENU* para volver al menú de opciones.`;
  return msg;
}

/**
 * Extrae datos del perfil del comprador para soporte digital de compra y registro legal
 * Soporta entradas separadas por comas, saltos de línea, etiquetas o texto fluido
 */
function extractBuyerProfile(text) {
  const result = {
    name: '',
    document: '',
    email: '',
    city: '',
    country: 'Colombia'
  };

  if (!text || typeof text !== 'string') return result;

  // 1. Detección por etiquetas explícitas (ej: "Nombre: ...", "CC: ...", "Correo: ...", "Ciudad: ...")
  const nameLabel = text.match(/(?:nombre(?: y apellidos)?|titular|raz[oó]n social|a nombre de|apartar a)[:\s]+([^,\n;]+)/i);
  if (nameLabel) result.name = cleanTitle(nameLabel[1]);

  const docLabel = text.match(/(?:cc|c\.c\.|nit|c[eé]dula|id|doc|identificaci[oó]n|ti|pasaporte)[:\s#]+([0-9]{6,12})/i);
  if (docLabel) result.document = docLabel[1].trim();

  const emailLabel = text.match(/(?:correo|email|e-mail)[:\s]+([^\s,\n;]+)/i);
  if (emailLabel) {
    let em = emailLabel[1].trim().toLowerCase();
    if (em && !em.includes('@') && em.includes('.')) em += '@gmail.com';
    result.email = em;
  }

  const cityLabel = text.match(/(?:ciudad|municipio|ubicaci[oó]n|vive en|de)[:\s]+([^,\n;]+)/i);
  if (cityLabel) result.city = cleanTitle(cityLabel[1]);

  const countryLabel = text.match(/(?:pa[ií]s)[:\s]+([^,\n;]+)/i);
  if (countryLabel) result.country = cleanTitle(countryLabel[1]);

  // 2. Correo electrónico completo en cualquier parte del texto
  if (!result.email) {
    const fullEmailMatch = text.match(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/);
    if (fullEmailMatch) {
      result.email = fullEmailMatch[0].toLowerCase();
    }
  }

  // 3. Documento de 6 a 12 dígitos en cualquier parte (que no sea celular 3XX...)
  if (!result.document) {
    const allNums = text.match(/\b\d{6,12}\b/g) || [];
    const nonCell = allNums.find(n => !(n.length === 10 && n.startsWith('3')));
    if (nonCell) {
      result.document = nonCell;
    }
  }

  // 4. Procesamiento inteligente por delimitadores (comas, punto y coma, saltos de línea, plecas)
  // Ej: "oscar santamaria, 1121837405 ,oscars.santamaria, san martin"
  const rawSegments = text.split(/[,;\n|]+/).map(s => s.trim()).filter(Boolean);
  if (rawSegments.length >= 2) {
    const unassigned = [];
    for (const seg of rawSegments) {
      // ¿Es documento numérico?
      const docClean = seg.replace(/[^0-9]/g, '');
      if (docClean.length >= 6 && docClean.length <= 12 && (!result.document || result.document === docClean)) {
        if (!result.document) result.document = docClean;
        continue;
      }

      // ¿Es email o usuario con punto (ej: "oscars.santamaria")?
      if (!result.email && (seg.includes('@') || (!seg.includes(' ') && seg.includes('.') && /[a-zA-Z]/.test(seg)))) {
        let em = seg.toLowerCase().replace(/^(?:correo|email|e-mail)[:\s]*/i, '').trim();
        if (!em.includes('@')) em += '@gmail.com';
        result.email = em;
        continue;
      }

      // ¿Es mención clara de ciudad conocida de Colombia?
      if (!result.city && /(?:bogot[aá]|medell[ií]n|cali|barranquilla|cartagena|bucaramanga|villavicencio|san mart[ií]n|ibagu[eé]|pereira|manizales|c[uú]cuta|santa marta|valledupar|monter[ií]a|pasto|armenia|neiva|popay[aá]|sincelejo|riohacha|tunja|florencia|yopal|quibd[oó]|in[ií]rida|mit[uú]|mocoa|puerto carre[ñn]o)/i.test(seg)) {
        result.city = cleanTitle(seg);
        continue;
      }

      unassigned.push(seg);
    }

    // Asignar los segmentos no asignados restantes en orden posicional (1º Nombre, 2º Ciudad si falta)
    if (!result.name && unassigned.length > 0) {
      result.name = cleanTitle(unassigned.shift());
    }
    if (!result.city && unassigned.length > 0) {
      result.city = cleanTitle(unassigned.shift());
    }
  } else {
    // Si viene texto libre continuo sin comas
    if (!result.name) {
      let cleaned = text
        .replace(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g, '')
        .replace(/(?:cc|c\.c\.|nit|c[eé]dula|id|ciudad|pa[ií]s|correo|email|colombia)[:\s]*/gi, '')
        .replace(/\b\d{4,12}\b/g, '')
        .replace(/[,;.\n]+/g, ' ')
        .trim();
      const words = cleaned.split(/\s+/).filter(w => w.length >= 2);
      if (words.length >= 2 && words.length <= 6) {
        result.name = cleanTitle(words.join(' '));
      }
    }
  }

  // País por defecto
  if (/colombia/i.test(text)) result.country = 'Colombia';

  return result;
}

/**
 * Extrae detalles de transferencia: valor, comprobante y banco
 */
function extractTransferInfo(text) {
  if (!text) return {};
  const clean = String(text).trim();
  const info = {};

  // 1. Monto: $400.000, 400.000, $400000, 400000 COP
  const amountMatch = clean.match(/(?:\$|valor|monto|total|consign[eé]|pagu[eé]|transfer[ií]|abono)?\s*([1-9]\d{1,2}(?:\.\d{3})+|[1-9]\d{4,8})\b/i);
  if (amountMatch) {
    const rawVal = parseInt(amountMatch[1].replace(/\./g, ''), 10);
    if (rawVal >= 5000) {
      info.amount = rawVal;
    }
  }

  // 2. Comprobante / Aprobación: Comprobante No. 1831555615, Aprobación 1831555615
  const voucherMatch = clean.match(/(?:comprobante|aprobaci[oó]n|transacci[oó]n|ref|n[uú]mero|no\.?)\s*[:#]?\s*([0-9]{6,14})/i);
  if (voucherMatch) {
    info.approvalNumber = voucherMatch[1];
  } else {
    const standaloneDigits = clean.match(/\b([1-9][0-9]{7,11})\b/);
    if (standaloneDigits && !standaloneDigits[1].startsWith('3')) {
      info.approvalNumber = standaloneDigits[1];
    }
  }

  // 3. Banco origen / medio
  if (/nequi/i.test(clean)) info.bank = 'Nequi';
  else if (/bancolombia/i.test(clean)) info.bank = 'Bancolombia';
  else if (/daviplata/i.test(clean)) info.bank = 'Daviplata';
  else if (/davivienda/i.test(clean)) info.bank = 'Davivienda';
  else if (/agrario/i.test(clean)) info.bank = 'Banco Agrario';
  else if (/bogot[aá]/i.test(clean)) info.bank = 'Banco de Bogotá';
  else if (/occidente/i.test(clean)) info.bank = 'Banco de Occidente';
  else if (/bbva/i.test(clean)) info.bank = 'BBVA';
  else if (/popular/i.test(clean)) info.bank = 'Banco Popular';
  else if (/ahorros/i.test(clean)) info.bank = 'Cuenta de Ahorros';

  return info;
}

/**
 * Valida si un comprobante ya fue usado en otra boleta (Antifraude)
 */
function checkDuplicateApprovalNumber(approvalNumber, currentTicketId, db) {
  if (!approvalNumber) return null;
  const cleanApp = String(approvalNumber).trim();
  for (const t of db.tickets || []) {
    if (t.id === currentTicketId) continue;
    for (const a of t.abonos || []) {
      if (a.approvalNumber && String(a.approvalNumber).trim() === cleanApp) {
        return { ticketNumber: t.ticketNumber, buyerName: t.buyerName, numbers: t.numbers, date: a.date };
      }
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Entrenamiento del bot: preguntas sin respuesta, pase a asesor y "¿cómo se enteró?"
// ---------------------------------------------------------------------------
const ADVISOR_REF_QUESTION = '🤝 *¿Te recomendó algún asesor de nuestro equipo?*\nIndícanos su nombre o código (o escribe *Ninguno* si compraste directamente).';
const MAX_UNANSWERED = 300;
const MAX_HANDOFFS = 300;

function logUnanswered(db, company, phone, text) {
  const clean = String(text || '').trim();
  if (!clean) return;
  db.botUnanswered = db.botUnanswered || [];
  const norm = botBrain.normalize(clean);
  if (!norm) return;
  const companyId = company ? company.id : null;
  const now = new Date().toISOString();
  const existing = db.botUnanswered.find(u => u.companyId === companyId && u.norm === norm);
  if (existing) {
    existing.count = (existing.count || 1) + 1;
    existing.lastAt = now;
    existing.phone = phone;
    return;
  }
  db.botUnanswered.unshift({
    id: `unans-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`,
    companyId, phone, text: clean.slice(0, 300), norm, count: 1, at: now, lastAt: now
  });
  if (db.botUnanswered.length > MAX_UNANSWERED) db.botUnanswered.length = MAX_UNANSWERED;
}

function resolveHandoffsFor(db, companyId, phone, by) {
  (db.botHandoffs || []).forEach(h => {
    if (h.companyId === companyId && h.phone === phone && h.status === 'PENDIENTE') {
      h.status = 'ATENDIDO';
      h.resolvedAt = new Date().toISOString();
      h.resolvedBy = by;
    }
  });
}

const HANDOFF_REASONS = {
  SOLICITUD: 'Pidió hablar con un asesor',
  NO_ENTENDIDO: 'El bot no entendió sus mensajes'
};

/**
 * Pasa el chat a una persona: el bot se calla, queda en la lista "Chats por atender" del panel
 * y (si está configurado) se avisa por WhatsApp al número del administrador.
 */
async function startHandoff({ instance, senderPhone, company, advisor, cfg, db, saveDBCallback, raffleId, reason, lastText, intro }) {
  updateSession(senderPhone, { humanAssisted: true, humanAssistedAt: Date.now(), failCount: 0 }, db, saveDBCallback, raffleId || null);
  db.botHandoffs = db.botHandoffs || [];
  const companyId = company ? company.id : null;
  const now = new Date().toISOString();
  const ticket = (db.tickets || []).find(t => t.buyerPhone === senderPhone);
  const customerName = (ticket && ticket.buyerName) || '';
  let rec = db.botHandoffs.find(h => h.companyId === companyId && h.phone === senderPhone && h.status === 'PENDIENTE');
  if (rec) {
    rec.lastMessage = String(lastText || '').slice(0, 300);
    rec.updatedAt = now;
  } else {
    rec = {
      id: `hand-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`,
      companyId, phone: senderPhone, name: customerName, reason: reason || 'SOLICITUD',
      lastMessage: String(lastText || '').slice(0, 300), status: 'PENDIENTE', at: now, updatedAt: now
    };
    db.botHandoffs.unshift(rec);
    if (db.botHandoffs.length > MAX_HANDOFFS) db.botHandoffs.length = MAX_HANDOFFS;
  }

  const companyName = getBusinessDisplayName(company);
  const body = cfg.handoff.message
    ? botBrain.fillPlaceholders(cfg.handoff.message, { empresa: companyName })
    : buildAdvisorHandOffMessage(companyName, advisor);
  await sendTextMessage(instance, senderPhone, `${intro ? `${intro}\n\n` : ''}${body}`);

  const notify = cfg.handoff.notifyNumber;
  if (notify && formatPhoneNumber(notify) !== formatPhoneNumber(senderPhone)) {
    await sendTextMessage(instance, notify,
`🔔 *Un cliente necesita un asesor*
👤 ${customerName || 'Cliente'}
📱 +${formatPhoneNumber(senderPhone)}
📝 ${HANDOFF_REASONS[rec.reason] || HANDOFF_REASONS.SOLICITUD}
💬 "${rec.lastMessage}"

Respóndele desde WhatsApp. Al terminar, márcalo como atendido en Control → Entrenar Bot.`).catch(() => {});
  }
  if (typeof saveDBCallback === 'function') saveDBCallback(raffleId || null);
}

function buildHowHeardQuestion(options) {
  const nums = ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣', '7️⃣', '8️⃣', '9️⃣', '🔟'];
  return `📣 *Una última pregunta:* ¿por qué medio te enteraste de nosotros?\n${options.map((o, i) => `${nums[i] || `${i + 1}.`} ${o}`).join('\n')}\n\n_(Responde con el número o escribe el medio)_`;
}

/** Guarda la respuesta a "¿cómo se enteró?". Devuelve true si el mensaje era esa respuesta. */
async function handleHowHeardAnswer({ instance, senderPhone, cfg, db, saveDBCallback, session, userText }) {
  const expired = !session.awaitingHowHeardAt || Date.now() - session.awaitingHowHeardAt > 24 * 3600 * 1000;
  const text = String(userText || '').trim();
  const norm = botBrain.normalize(text);
  // Un número suelto aquí es la opción elegida (no la opción 2 del menú principal)
  const isCommand = !norm || ['menu', 'bot', 'volver', 'reiniciar'].includes(norm) || (!/^\d{1,2}$/.test(text) && botBrain.isHandoffRequest(cfg, text));
  let answer = null;
  if (!expired && !isCommand) {
    const options = cfg.howHeard.options;
    if (/^\d{1,2}$/.test(text)) {
      answer = options[parseInt(text, 10) - 1] || null;
    } else {
      answer = options.find(o => botBrain.normalize(o) === norm) ||
               options.find(o => norm.length >= 3 && botBrain.normalize(o).includes(norm)) || null;
      if (!answer && text.length <= 60 && !/\d{4,}/.test(text)) answer = text;
    }
  }
  updateSession(senderPhone, { awaitingHowHeard: false }, db, saveDBCallback, null);
  if (!answer) return false;
  (db.tickets || []).forEach(t => {
    if (t.buyerPhone === senderPhone) { t.howHeard = answer; t.howHeardAt = new Date().toISOString(); }
  });
  updateSession(senderPhone, { howHeard: answer }, db, saveDBCallback, null);
  if (typeof saveDBCallback === 'function') saveDBCallback(null);
  await sendTextMessage(instance, senderPhone, `🙌 ¡Gracias! Anotamos: *${answer}*.\nEscribe *MENU* cuando quieras ver las opciones.`);
  return true;
}


/**
 * Cerebro del Bot: Procesa los mensajes entrantes de WhatsApp y responde de forma inteligente
 */
async function handleWebhookEvent(body, db, saveDBCallback) {
  const event = body.event || body.type;
  if (event !== 'messages.upsert' && event !== 'MESSAGES_UPSERT') {
    return { ignored: true };
  }

  const instance = body.instance || body.instanceName;
  const msgData = body.data?.message;
  const key = body.data?.key;

  if (!instance || !key || key.fromMe || !msgData) {
    return { ignored: true };
  }

  const senderJid = key.remoteJid || '';
  if (senderJid.endsWith('@g.us')) {
    return { ignored: true };
  }

  const rawSender = (key.remoteJid || '').split('@')[0].split(':')[0];
  const senderPhone = formatPhoneNumber(rawSender);

  // Documentos (Excel devuelto de AGIL): los atiende quien se registró con setDocumentHandler
  const docMsg = msgData.documentMessage || msgData.documentWithCaptionMessage?.message?.documentMessage;
  if (docMsg && documentHandler) {
    const fileName = docMsg.fileName || docMsg.title || '';
    let base64 = msgData.base64 || body.data?.message?.base64 || body.data?.base64 || docMsg.base64 || null;
    if (!base64 && /\.xlsx?$/i.test(fileName)) base64 = await fetchMediaBase64(instance, key);
    const handled = await documentHandler({ instance, senderPhone, fileName, base64, mimetype: docMsg.mimetype });
    if (handled && handled.handled) return { handled: true, document: true };
    return { ignored: true };
  }
  const userText = (msgData.conversation || msgData.extendedTextMessage?.text || msgData.imageMessage?.caption || '').trim();
  const hasImage = !!msgData.imageMessage;
  // Evolution entrega la imagen en base64 cuando el webhook lo permite
  const receiptMedia = hasImage ? {
    base64: msgData.base64 || body.data?.message?.base64 || body.data?.base64 || msgData.imageMessage?.base64 || null,
    mimeType: msgData.imageMessage?.mimetype || 'image/jpeg'
  } : null;
  const cleanLower = userText.toLowerCase();

  console.log(`💬 [WhatsApp Bot (${instance})] Mensaje de ${senderPhone}: "${userText}" ${hasImage ? '[IMAGEN COMPROBANTE]' : ''}`);

  // -------------------------------------------------------------
  // CASO 1: SUPER ADMIN BOT (Venta de Planes y Software Rifa Master)
  // -------------------------------------------------------------
  if (instance === 'superadmin_sales' || instance === 'rifaapp_bot') {
    if (userText === '1' || cleanLower.includes('plan') || cleanLower.includes('precio') || cleanLower.includes('costo')) {
      const plansText = 
`💎 *PLANES Y PRECIOS RIFA MASTER* 🚀

1️⃣ *PLAN GRATIS:*
• Hasta 500 boletas por rifa
• 1 rifa activa a la vez
• 3 asesores registrados
• Control básico de caja

2️⃣ *PLAN PRO MENSUAL:* ($39.000 COP / $10 USD)
• 🎟️ Boletas ILIMITADAS
• 🏆 Rifas ILIMITADAS
• 👥 Asesores ILIMITADOS
• 🤖 Bot de WhatsApp Automático
• ☁️ Respaldo diario en Google Drive
• 📊 Reportes en Excel e impresión 2D

3️⃣ *PLAN PRO ANUAL (Mejor Opción):* ($299.000 COP)
• Todo lo de PRO + 4 meses GRATIS
• Soporte prioritario y dominio personalizado

¿Deseas activar un plan o probar la Demo? Responde *DEMO* o *ACTIVAR*.`;
      await sendTextMessage(instance, senderPhone, plansText);
      return { handled: true };
    }

    if (cleanLower.includes('demo') || userText === '2') {
      const demoText = 
`🎯 *ACCESO A LA DEMO DE RIFA MASTER:*
Puedes probar la plataforma ahora mismo:
🌐 *Web:* http://45.137.192.195

Explora el módulo de boletas en tiempo real, asesores, comisiones, caja y generador de afiches.
Si deseas una asesoría personalizada, responde *ASESOR* y un comercial te contactará.`;
      await sendTextMessage(instance, senderPhone, demoText);
      return { handled: true };
    }

    const greetingSuper = 
`👋 ¡Hola! Bienvenido a *Rifa Master Oficial* 🏆
El sistema profesional para gestión de rifas, boletas concurrentes para +100 asesores, caja y bots de WhatsApp.

¿En qué te podemos colaborar hoy?
1️⃣ Ver Planes y Precios
2️⃣ Solicitar Demo
3️⃣ Hablar con un Asesor Comercial

_(Escribe el número de la opción o tu consulta)_`;
    await sendTextMessage(instance, senderPhone, greetingSuper);
    return { handled: true };
  }

  // -------------------------------------------------------------
  // CASO 2: EMPRESA O ASESOR INDEPENDIENTE (Venta de Boletas)
  // -------------------------------------------------------------
  let company = null;
  let advisor = null;

  if (instance.startsWith('asesor_')) {
    const advId = instance.replace('asesor_', '');
    advisor = (db.advisors || []).find(a => a.id === advId || a.username === advId || (a.code && a.code.toLowerCase() === advId));
    if (advisor) {
      company = (db.companies || []).find(c => c.id === advisor.companyId);
    }
  } else if (instance.startsWith('empresa_')) {
    const compCode = instance.replace('empresa_', '');
    company = (db.companies || []).find(c => 
      (c.code && c.code.toLowerCase() === compCode) || 
      c.id === compCode ||
      (c.name && c.name.toLowerCase().replace(/[^a-z0-9_]/g, '') === compCode)
    );
  }

  if (!company && db.companies && db.companies.length > 0) {
    company = db.companies[0];
  }

  const companyName = getBusinessDisplayName(company);
  const session = getSession(senderPhone, db);
  const cfg = botBrain.getBotConfig(company);

  // 0. Si el chat está actualmente en atención manual por un asesor humano:
  if (session?.humanAssisted) {
    const isHumanResetCommand = cleanLower === 'menu' || cleanLower === 'menú' || cleanLower === 'bot' || 
                                cleanLower === 'reiniciar' || cleanLower === 'volver' || 
                                cleanLower === '1' || cleanLower === '2' || cleanLower === '3';
    const hoursSinceAssisted = (Date.now() - (session.humanAssistedAt || 0)) / (1000 * 60 * 60);

    if (!isHumanResetCommand && hoursSinceAssisted < cfg.handoff.resumeHours) {
      // Mantener al día el último mensaje del cliente en la lista de chats por atender
      const pending = (db.botHandoffs || []).find(h => h.companyId === (company ? company.id : null) && h.phone === senderPhone && h.status === 'PENDIENTE');
      if (pending && userText) { pending.lastMessage = String(userText).slice(0, 300); pending.updatedAt = new Date().toISOString(); }
      console.log(`👤 [WhatsApp Bot (${instance})] Chat ${senderPhone} en atención humana activa (hace ${hoursSinceAssisted.toFixed(1)}h); se omite auto-respuesta.`);
      return { handled: true, humanAssisted: true };
    } else {
      resolveHandoffsFor(db, company ? company.id : null, senderPhone, 'bot-reanudado');
      updateSession(senderPhone, { humanAssisted: false }, db, saveDBCallback, null);
    }
  }

  // 0.1 Respuesta a "¿por qué medio te enteraste de nosotros?"
  if (session?.awaitingHowHeard) {
    if (await handleHowHeardAnswer({ instance, senderPhone, cfg, db, saveDBCallback, session, userText })) {
      return { handled: true };
    }
  }

  // Buscar rifas activas de la empresa
  const activeRaffles = (db.raffles || []).filter(r => 
    (!company || r.companyId === company.id) && 
    r.status !== 'INACTIVA' && 
    r.active !== false
  );
  const mainRaffle = activeRaffles[0];

  // Respuestas personalizadas del administrador y pase a asesor
  const raffleVars = mainRaffle ? {
    empresa: companyName,
    rifa: mainRaffle.title || '',
    precio: `$${Number(mainRaffle.ticketPrice || 0).toLocaleString('es-CO')}`,
    fecha: mainRaffle.mainDrawDate ? mainRaffle.mainDrawDate.substring(0, 10).split('-').reverse().join('/') : ''
  } : { empresa: companyName };
  const customIntents = async () => {
    const faq = botBrain.matchFaq(cfg, userText);
    if (faq) {
      faq.hits = (faq.hits || 0) + 1;
      updateSession(senderPhone, { failCount: 0 }, db, saveDBCallback, mainRaffle?.id);
      await sendTextMessage(instance, senderPhone, botBrain.fillPlaceholders(faq.answer, raffleVars));
      return true;
    }
    if (botBrain.isHandoffRequest(cfg, userText)) {
      await startHandoff({ instance, senderPhone, company, advisor, cfg, db, saveDBCallback, raffleId: mainRaffle?.id, reason: 'SOLICITUD', lastText: userText });
      return true;
    }
    return false;
  };
  // Mensaje que el bot no entendió: se guarda para que el administrador lo convierta en respuesta y,
  // tras varios intentos seguidos, se pasa a un asesor.
  const fallbackReply = async (defaultText) => {
    const text = cfg.greeting ? botBrain.fillPlaceholders(cfg.greeting, raffleVars) : defaultText;
    if (botBrain.isGreeting(userText)) {
      updateSession(senderPhone, { failCount: 0 }, db, saveDBCallback, mainRaffle?.id);
      await sendTextMessage(instance, senderPhone, text);
      return;
    }
    logUnanswered(db, company, senderPhone, userText);
    const s = getSession(senderPhone, db) || {};
    const recent = s.lastFailAt && Date.now() - s.lastFailAt < 30 * 60 * 1000;
    const fails = (recent ? (s.failCount || 0) : 0) + 1;
    const limit = cfg.handoff.autoAfterFails;
    if (cfg.handoff.enabled && limit > 0 && fails >= limit) {
      await startHandoff({ instance, senderPhone, company, advisor, cfg, db, saveDBCallback, raffleId: mainRaffle?.id, reason: 'NO_ENTENDIDO', lastText: userText, intro: '🤔 No logré entender tu mensaje, así que te comunico con una persona.' });
      return;
    }
    updateSession(senderPhone, { failCount: fails, lastFailAt: Date.now() }, db, saveDBCallback, mainRaffle?.id);
    await sendTextMessage(instance, senderPhone, text);
  };

  if (!mainRaffle) {
    if (await customIntents()) return { handled: true };
    await fallbackReply(buildMainMenuMessage(companyName, advisor));
    return { handled: true };
  }

  const digits = mainRaffle.digits || 4;
  const opportunities = mainRaffle.opportunitiesPerTicket || 1;
  const ticketPrice = Number(mainRaffle.ticketPrice || 0);
  const lotteryName = mainRaffle.mainLotteryName || mainRaffle.lotteryName || 'Lotería Oficial';
  const drawDateRaw = mainRaffle.mainDrawDate ? mainRaffle.mainDrawDate.substring(0, 10) : '';
  let drawDateFormatted = drawDateRaw;
  if (drawDateRaw.includes('-')) {
    const parts = drawDateRaw.split('-');
    if (parts.length === 3) drawDateFormatted = `${parts[2]}/${parts[1]}/${parts[0]}`;
  }

  // Contexto de los flujos con confirmación (apartar, cambiar, registrar pagos)
  const flowCtx = {
    instance, senderPhone, userText, db, saveDBCallback, session: getSession(senderPhone, db),
    mainRaffle, company, companyName, advisor, cfg, digits, ticketPrice, lotteryName, drawDateFormatted, opportunities
  };

  // 0.2 Respuesta del cliente a una confirmación pendiente (SÍ/NO, opción de una lista, valor del pago)
  if (!hasImage && await handlePendingFlow(flowCtx)) return { handled: true };

  // 1. COMPROBANTES DE PAGO (FOTO): se valida a qué boleta corresponde y por cuánto, y el cliente confirma
  if (hasImage) {
    const text = String(userText || '');
    const infoText = extractTransferInfo(text);
    const sess = flowCtx.session || {};
    const mine = myTickets(db, mainRaffle.id, senderPhone);
    let hint = '';
    for (const run of (text.match(/\d{3,}/g) || [])) {
      const candidate = run.length < digits ? run.padStart(digits, '0') : run;
      if (mine.some(t => (t.numbers || []).includes(candidate))) { hint = candidate; break; }
    }
    if (!receiptMedia.base64) console.log(`ℹ️ [WhatsApp Bot] Comprobante de ${senderPhone} sin imagen en base64 (revisar webhook de Evolution).`);
    await startReceiptFlow(flowCtx, {
      amount: detectAmount(text) || sess.pendingAmount || null,
      approval: infoText.approvalNumber || sess.pendingApproval || '',
      bank: infoText.bank || sess.pendingBank || '',
      hintNumber: hint,
      media: receiptMedia
    });
    return { handled: true };
  }

  // 1.5. RESPUESTA SOBRE ASESOR RECOMENDADO / REFERIDO
  const refreshedSession = getSession(senderPhone, db);
  const targetTkt = refreshedSession?.lastTicketId ? (db.tickets || []).find(t => t.id === refreshedSession.lastTicketId) : (db.tickets || []).find(t => t.buyerPhone === senderPhone);
  const waitingAdvisorRef = refreshedSession?.awaitingAdvisorRef === true &&
    Date.now() - (refreshedSession.awaitingAdvisorRefAt || 0) < 24 * 3600 * 1000;
  if (waitingAdvisorRef && targetTkt && (!targetTkt.advisorName || targetTkt.advisorName === 'Venta WhatsApp')) {
    // Tras responder, se pregunta (una sola vez) por qué medio se enteró
    const followUp = () => {
      if (cfg.howHeard.enabled && !targetTkt.howHeard && !refreshedSession?.howHeard) {
        updateSession(senderPhone, { awaitingAdvisorRef: false, awaitingHowHeard: true, awaitingHowHeardAt: Date.now() }, db, saveDBCallback, mainRaffle.id);
        return `\n\n${buildHowHeardQuestion(cfg.howHeard.options)}`;
      }
      updateSession(senderPhone, { awaitingAdvisorRef: false }, db, saveDBCallback, mainRaffle.id);
      return '';
    };
    if (cleanLower === 'ninguno' || cleanLower === 'ninguna' || cleanLower === 'nadie' || cleanLower === 'directo' || cleanLower === 'no') {
      targetTkt.advisorId = null;
      targetTkt.advisorName = 'Venta Directa WhatsApp';
      if (typeof saveDBCallback === 'function') saveDBCallback(mainRaffle.id);
      await sendTextMessage(instance, senderPhone, `🤝 ¡Perfecto! Tu boleta (${(targetTkt.numbers || []).join(' • ')}) quedó registrada como *compra directa*.${followUp()}`);
      return { handled: true };
    }

    // Buscar si escribió el nombre o código de un asesor
    const matchedAdvisor = (db.advisors || []).find(a => {
      const advNameClean = (a.name || '').toLowerCase();
      const advCodeClean = (a.code || '').toLowerCase();
      const firstName = advNameClean.split(' ')[0];
      return (advNameClean && cleanLower.includes(advNameClean)) || (advCodeClean && cleanLower.includes(advCodeClean)) ||
             (firstName.length >= 4 && firstName !== 'asesor' && cleanLower.includes(firstName));
    });

    if (matchedAdvisor) {
      targetTkt.advisorId = matchedAdvisor.id;
      targetTkt.advisorName = matchedAdvisor.name;
      if (targetTkt.abonos) {
        targetTkt.abonos.forEach(ab => {
          ab.sellerId = matchedAdvisor.id;
          ab.sellerName = matchedAdvisor.name;
        });
      }
      if (typeof saveDBCallback === 'function') saveDBCallback(mainRaffle.id);
      await sendTextMessage(instance, senderPhone, `🤝 ¡Excelente! Tu boleta (${(targetTkt.numbers || []).join(' • ')}) ha quedado formalmente vinculada a nuestro asesor *${matchedAdvisor.name}*.${followUp()}`);
      return { handled: true };
    }
  }

  // 1.6. PAGO REPORTADO POR TEXTO: el soporte (foto) es obligatorio; se guarda el valor y se pide la foto
  if (/transfer|consign|pagu[eé]|abon[eé]|comprobante|aprobaci[oó]n|nequi|bancolombia|daviplata|\$/i.test(userText)) {
    const reportedAmount = detectAmount(userText);
    const reportedApproval = extractTransferInfo(userText).approvalNumber || '';
    const openTickets = myTickets(db, mainRaffle.id, senderPhone).filter(t => balanceOf(t, ticketPrice) > 0);
    if ((reportedAmount || reportedApproval) && openTickets.length) {
      updateSession(senderPhone, {
        pendingAmount: reportedAmount || undefined,
        pendingApproval: reportedApproval || undefined,
        pendingBank: extractTransferInfo(userText).bank || undefined
      }, db, saveDBCallback, mainRaffle.id);
      await sendTextMessage(instance, senderPhone,
        `📝 Anoté${reportedAmount ? ` el valor de *${money(reportedAmount)}*` : ''}${reportedApproval ? ` y el comprobante *#${reportedApproval}*` : ''}.\n\nPara registrar el pago envíame ahora la *foto o captura del comprobante*; yo la asocio a tu boleta y te pido confirmar.`);
      return { handled: true };
    }
  }

  // 2. PARSEO DE DATOS DEL COMPRADOR (Si responde con sus datos: Nombre, Cédula, Correo, Ciudad, País)
  const profile = extractBuyerProfile(userText);
  const hasProfileData = (profile.name && (profile.document || profile.email)) || 
                         (profile.document && profile.email) || 
                         (session && session.waitingData && (profile.name || profile.document || profile.email || profile.city));

  if (hasProfileData && session && (session.lastTicketId || session.lastOpportunity)) {
    const tickets = (db.tickets || []).filter(t => t.raffleId === (session.lastRaffleId || mainRaffle.id));
    let targetTicket = session.lastTicketId ? tickets.find(t => t.id === session.lastTicketId) : null;
    if (!targetTicket && session.lastOpportunity) {
      targetTicket = tickets.find(t => (t.numbers || []).includes(session.lastOpportunity));
    }
    if (!targetTicket) {
      targetTicket = tickets.find(t => t.buyerPhone === senderPhone);
    }

    if (targetTicket) {
      if (profile.name) targetTicket.buyerName = profile.name;
      if (profile.document) targetTicket.buyerDocument = profile.document;
      if (profile.email) targetTicket.buyerEmail = profile.email;
      if (profile.city) targetTicket.buyerCity = profile.city;
      if (profile.country) targetTicket.buyerCountry = profile.country;
      targetTicket.buyerPhone = senderPhone;
      targetTicket.soldByBot = true;
      targetTicket.saleChannel = 'Bot WhatsApp';
      targetTicket.assignedDate = targetTicket.assignedDate || new Date().toISOString();
      const assignedAdv = getAssignedAdvisorForTicket(targetTicket, mainRaffle, db) || advisor;
      if (assignedAdv) {
        targetTicket.advisorId = assignedAdv.id;
        targetTicket.advisorName = assignedAdv.name;
      }
      if (targetTicket.status === 'DISPONIBLE') {
        targetTicket.status = 'RESERVADA';
      }

      if (typeof saveDBCallback === 'function') {
        saveDBCallback(session.lastRaffleId || mainRaffle.id);
      }

      const missingAfter = [];
      if (!targetTicket.buyerName) missingAfter.push('Nombre y Apellidos completos');
      if (!targetTicket.buyerDocument) missingAfter.push('Cédula de Ciudadanía o NIT');
      if (!targetTicket.buyerEmail) missingAfter.push('Correo electrónico');
      if (!targetTicket.buyerCity) missingAfter.push('Ciudad y País');

      let replyMsg = '';
      if (missingAfter.length === 0) {
        replyMsg = 
`🎉 *¡DATOS VINCULADOS A TU BOLETA Y SOPORTE DE COMPRA!* ✅

🔢 *Tus números:* ${targetTicket.numbers.join('  •  ')}
👤 *Titular / Razón Social:* ${targetTicket.buyerName || 'Registrado'}
🪪 *Cédula / NIT:* ${targetTicket.buyerDocument || 'Registrada'}
📧 *Correo Electrónico:* ${targetTicket.buyerEmail || 'Registrado'}
📍 *Ciudad y País:* ${targetTicket.buyerCity ? `${targetTicket.buyerCity}, ` : ''}${targetTicket.buyerCountry || 'Colombia'}
${advisor ? `👤 *Asesor:* ${advisor.name}\n` : ''}📱 *WhatsApp:* ${senderPhone}
💵 *Valor:* $${ticketPrice.toLocaleString('es-CO')} COP

🌐 *Consulta tu boleta digital oficial y soporte de compra:*
${PUBLIC_BASE_URL}/boleta?phone=${senderPhone}

Tus datos han quedado formalmente registrados para el sorteo y la emisión de tu soporte de compra. Nuestro equipo validará el comprobante bancario para emitir la certificación oficial.
_(Si deseas cambiar de número, escribe el nuevo número que deseas)._ ¡Mucha suerte! 🍀`;
      } else {
        replyMsg = 
`✅ *¡Datos recibidos y actualizados con éxito!*

🎟️ *Tus números:* ${targetTicket.numbers.join(' • ')}
${targetTicket.buyerName ? `• *Titular:* ${targetTicket.buyerName}\n` : ''}${targetTicket.buyerDocument ? `• *Cédula/NIT:* ${targetTicket.buyerDocument}\n` : ''}${targetTicket.buyerEmail ? `• *Correo:* ${targetTicket.buyerEmail}\n` : ''}${targetTicket.buyerCity ? `• *Ciudad:* ${targetTicket.buyerCity}\n` : ''}
📋 *Para completar tu Soporte Digital de Compra, solo indícanos:*
${missingAfter.map((m, idx) => `${idx + 1}️⃣ *${m}*`).join('\n')}

✍️ *Por favor indícanos ${missingAfter.length === 1 ? 'este dato' : 'estos datos faltantes'} para finalizar.*`;
      }

      // Con los datos completos, preguntar (una sola vez) por qué medio se enteró de nosotros
      const hasRealAdvisor = !!targetTicket.advisorId && targetTicket.advisorName !== 'Venta WhatsApp';
      const askAdvisorRef = missingAfter.length === 0 && !hasRealAdvisor && targetTicket.advisorName !== 'Venta Directa WhatsApp';
      const askHowHeard = missingAfter.length === 0 && !askAdvisorRef && cfg.howHeard.enabled && !targetTicket.howHeard && !session?.howHeard;
      if (askAdvisorRef) replyMsg += `\n\n${ADVISOR_REF_QUESTION}`;
      else if (askHowHeard) replyMsg += `\n\n${buildHowHeardQuestion(cfg.howHeard.options)}`;

      updateSession(senderPhone, {
        awaitingAdvisorRef: askAdvisorRef,
        awaitingAdvisorRefAt: askAdvisorRef ? Date.now() : undefined,
        awaitingHowHeard: askHowHeard,
        awaitingHowHeardAt: askHowHeard ? Date.now() : undefined,
        waitingData: missingAfter.length > 0,
        profileCaptured: missingAfter.length === 0,
        buyerName: targetTicket.buyerName,
        buyerDocument: targetTicket.buyerDocument,
        buyerEmail: targetTicket.buyerEmail,
        buyerCity: targetTicket.buyerCity,
        buyerCountry: targetTicket.buyerCountry
      }, db, saveDBCallback, mainRaffle.id);

      await sendTextMessage(instance, senderPhone, replyMsg);
      return { handled: true };
    }
  }

  // =============================================================
  // MENÚ DE ATENCIÓN (Rifas / Asesor)
  // =============================================================

  // A. RESPUESTAS PERSONALIZADAS DEL ADMINISTRADOR Y HABLAR CON UN ASESOR HUMANO (Opción 3)
  if (await customIntents()) return { handled: true };

  // D. ENTRADA EXPLÍCITA AL FLUJO DE RIFAS (Opción 1)
  if (cleanLower === '1' || cleanLower === 'rifa' || cleanLower === 'rifas' || 
      cleanLower === 'sorteo' || cleanLower === 'sorteos' || 
      cleanLower === 'boleta' || cleanLower === 'boletas' ||
      cleanLower.includes('comprar boleta')) {
    
    updateSession(senderPhone, {
      currentTopic: 'rifa',
      humanAssisted: false
    }, db, saveDBCallback, mainRaffle?.id);

    const raffleMsg = buildRaffleMessage(mainRaffle, companyName, digits, opportunities, ticketPrice, drawDateFormatted, lotteryName);
    await sendTextMessage(instance, senderPhone, raffleMsg);
    return { handled: true };
  }

  // E. MENÚ PRINCIPAL MULTI-SERVICIO (GREETINGS, MENU, INICIO, AYUDA)
  if (cleanLower === 'menu' || cleanLower === 'menú' || cleanLower === 'inicio' || 
      cleanLower === 'opciones' || cleanLower === 'servicios' || cleanLower === 'volver' || 
      cleanLower === 'bot' || cleanLower === 'ayuda' || cleanLower === 'hola' || 
      cleanLower === 'buenas' || cleanLower === 'buen dia' || cleanLower === 'buenos dias' || 
      cleanLower === 'buenas tardes' || cleanLower === 'buenas noches' || 
      cleanLower === 'saludos' || cleanLower === 'cordial saludo') {
    
    updateSession(senderPhone, {
      currentTopic: null,
      humanAssisted: false
    }, db, saveDBCallback, mainRaffle?.id);

    const menuMsg = buildMainMenuMessage(companyName, advisor);
    await sendTextMessage(instance, senderPhone, menuMsg);
    return { handled: true };
  }

  // 3. CONSULTA DE MEDIOS DE PAGO / CUENTAS (Priorizando cuentas de la rifa)
  if (cleanLower.includes('cuenta') || cleanLower.includes('pago') || cleanLower.includes('banco') || 
      cleanLower.includes('nequi') || cleanLower.includes('bancolombia') || cleanLower.includes('daviplata') ||
      cleanLower.includes('donde pago') || cleanLower.includes('transferencia')) {
    
    let bankAccounts = [];
    if (Array.isArray(mainRaffle.transferAccounts) && mainRaffle.transferAccounts.length > 0) {
      bankAccounts = mainRaffle.transferAccounts.map(a => ({
        name: a.bankName || a.bank || 'Banco',
        accountNumber: a.accountNumber || a.number || '',
        type: a.accountType || a.type || 'Ahorros',
        holder: a.holderName || a.holder || companyName
      }));
    } else {
      bankAccounts = (db.banks || []).filter(b => !company || b.companyId === company.id || !b.companyId);
    }

    let bankMsg = `💳 *MEDIOS DE PAGO OFICIALES - ${companyName}* 🏦\n\n`;
    bankMsg += `Para asegurar tus números en *${mainRaffle.title}*, transfiere a:\n\n`;
    
    if (bankAccounts.length > 0) {
      bankAccounts.forEach(b => {
        bankMsg += `• *${b.name || 'Banco'}:* ${b.accountNumber || b.number || ''}\n`;
        bankMsg += `  Tipo: ${b.type || 'Ahorros'} | Titular: ${b.holder || companyName}\n\n`;
      });
    } else {
      bankMsg += `• *Nequi / Bancolombia / Daviplata*\n`;
      bankMsg += `  Titular: *${companyName}*\n`;
      bankMsg += `  Pide los datos de transferencia a nuestro asesor aquí mismo.\n\n`;
    }

    bankMsg += `📌 *Importante:* Una vez realizada la transferencia, envía la *foto del comprobante aquí mismo* para validar tu pago y registrar tu boleta con QR oficial.`;
    await sendTextMessage(instance, senderPhone, bankMsg);
    return { handled: true };
  }

  // 4. CONSULTA DE PLAN DE PREMIOS / PREMIOS ACUMULADOS / SEMANALES
  if (cleanLower.includes('premio') || cleanLower.includes('que se gana') || cleanLower.includes('gana') || cleanLower.includes('mayor') || cleanLower.includes('acumulado')) {
    let prizeMsg = `🏆 *PLAN DE PREMIOS - ${mainRaffle.title}* 🎁\n\n`;
    prizeMsg += `🌟 *Premio Mayor:*\n${mainRaffle.description || 'Gran Premio Oficial del Sorteo'}\n\n`;
    
    const winners = (db.winners || []).filter(w => w.raffleId === mainRaffle.id);
    if (mainRaffle.weeklyPrizes && mainRaffle.weeklyPrizes.length > 0) {
      prizeMsg += `🎁 *Sorteos Semanales / Anticipados:*\n`;
      mainRaffle.weeklyPrizes.forEach(p => {
        const winner = winners.find(w => w.prizeName === p.name || w.prizeId === p.id);
        const statusText = winner ? `✅ Ganador: ${winner.winnerName || 'Entregado'}` : (p.isAccumulative ? '⏳ Acumulado' : '🗓️ Por jugar');
        prizeMsg += `• *${p.name || 'Premio Semanal'}:* $${Number(p.amount || 0).toLocaleString('es-CO')} COP (${p.drawDate || 'según fecha'}) - [${statusText}]\n`;
      });
      prizeMsg += '\n';
    }

    prizeMsg += `🎯 *Juega con:* ${lotteryName}\n`;
    prizeMsg += `📅 *Fecha del Gran Sorteo:* ${drawDateFormatted}\n`;
    prizeMsg += `💵 *Valor Boleta:* $${ticketPrice.toLocaleString('es-CO')} COP (${opportunities} oportunidades de ${digits} cifras)\n\n`;
    prizeMsg += `💡 *Escribe un número de ${digits} cifras (ej: ${digits === 4 ? '3456' : '428'}) o escribe DISPONIBLES para ver opciones libres.*`;

    await sendTextMessage(instance, senderPhone, prizeMsg);
    return { handled: true };
  }

  // 5. CONSULTA DE FECHA, LOTERÍA Y CONDICIONES
  if (cleanLower.includes('fecha') || cleanLower.includes('cuando juega') || cleanLower.includes('loteria') || cleanLower.includes('con que juega')) {
    let dateMsg = `📅 *FECHA Y LOTERÍA DEL SORTEO* 🎰\n\n`;
    dateMsg += `🎯 *Rifa:* ${mainRaffle.title}\n`;
    dateMsg += `🏆 *Lotería:* ${lotteryName}\n`;
    dateMsg += `🗓️ *Fecha:* ${drawDateFormatted}\n`;
    dateMsg += `🔢 *Modalidad:* Sorteo de *${digits} cifras* (${mainRaffle.winningDigitsPosition === 'PRIMERAS' ? 'Primeras cifras' : 'Últimas cifras'} del premio mayor).\n`;
    dateMsg += `💵 *Precio:* $${ticketPrice.toLocaleString('es-CO')} COP\n\n`;
    dateMsg += `👉 Escribe un número de ${digits} cifras o escribe *DISPONIBLES* para ver números para jugar.`;

    await sendTextMessage(instance, senderPhone, dateMsg);
    return { handled: true };
  }

  // 6. CONSULTA DE POLÍTICAS Y REGLAS
  if (cleanLower.includes('politica') || cleanLower.includes('regla') || cleanLower.includes('termino') || cleanLower.includes('condicion') || cleanLower.includes('como funciona')) {
    let rulesMsg = `📜 *TÉRMINOS Y CONDICIONES - ${companyName}* 📋\n\n`;
    rulesMsg += `1️⃣ *Condición de Ganador:* La boleta debe encontrarse 100% cancelada antes del inicio del sorteo oficial de ${lotteryName}.\n`;
    rulesMsg += `2️⃣ *Apartados:* Las boletas apartadas sin abono tienen vigencia temporal fijada por la administración.\n`;
    rulesMsg += `3️⃣ *Transparencia:* Cada boleta cuenta con registro criptográfico, serial único y código QR de verificación.\n`;
    rulesMsg += `4️⃣ *Reclamo:* El titular ganador deberá identificarse con su cédula de ciudadanía coincidente con el registro del sistema.\n\n`;
    rulesMsg += `¿Quieres ver números libres? Escribe *DISPONIBLES* o escribe el número que buscas.`;

    await sendTextMessage(instance, senderPhone, rulesMsg);
    return { handled: true };
  }

  // 7. MOSTRAR NÚMEROS DISPONIBLES AL AZAR
  if (cleanLower.includes('disponible') || cleanLower.includes('libres') || cleanLower.includes('que numeros hay') || 
      cleanLower.includes('muestrame') || cleanLower.includes('azar') || cleanLower.includes('que queda') || cleanLower === 'numeros') {
    const availableTickets = (db.tickets || []).filter(t => t.raffleId === mainRaffle.id && t.status === 'DISPONIBLE');
    if (availableTickets.length === 0) {
      await sendTextMessage(instance, senderPhone, `❌ *¡Boletas agotadas!* No quedan números disponibles para esta rifa.`);
      return { handled: true };
    }
    const shuffled = [...availableTickets].sort(() => 0.5 - Math.random()).slice(0, 8);
    let dispMsg = `🎲 *NÚMEROS DISPONIBLES - ${mainRaffle.title}* 🎟️\n\n`;
    dispMsg += `Aquí tienes opciones de números libres para jugar (${opportunities} números por boleta):\n\n`;
    shuffled.forEach(t => {
      dispMsg += `• ${t.numbers.join('  •  ')}\n`;
    });
    dispMsg += `\n💵 *Valor:* $${ticketPrice.toLocaleString('es-CO')} COP\n`;
    dispMsg += `\n✍️ *Para apartar cualquiera de ellos,* solo responde con el número que deseas (ejemplo: *${shuffled[0].numbers[0]}*).`;
    await sendTextMessage(instance, senderPhone, dispMsg);
    return { handled: true };
  }

  // 8. BÚSQUEDA Y CONSULTA DE NÚMERO (ESTRICTAMENTE EN OPORTUNIDADES t.numbers)
  const numbersFound = userText.match(/\d+/g);
  if (numbersFound && numbersFound.length > 0) {
    const rawNumber = numbersFound[0];
    const tickets = (db.tickets || []).filter(t => t.raffleId === mainRaffle.id);

    // BÚSQUEDA ESTRICTA DE LA OPORTUNIDAD: Se busca ÚNICAMENTE dentro de t.numbers
    let matchedTicket = tickets.find(t => Array.isArray(t.numbers) && t.numbers.includes(rawNumber));

    // Si no encontró coincidencia exacta y el usuario escribió menos cifras, rellenar con ceros (ej: 345 -> 0345)
    let paddedNumber = rawNumber;
    if (!matchedTicket && rawNumber.length < digits) {
      paddedNumber = rawNumber.padStart(digits, '0');
      matchedTicket = tickets.find(t => Array.isArray(t.numbers) && t.numbers.includes(paddedNumber));
    }

    if (matchedTicket) {
      if (matchedTicket.status === 'DISPONIBLE') {
        // Se muestra y se pide confirmación: nunca se aparta (ni se cambia una boleta) sin que el cliente confirme
        await offerReservation(flowCtx, matchedTicket, paddedNumber);
        return { handled: true };
      } else if (matchedTicket.buyerPhone === senderPhone) {
        const left = balanceOf(matchedTicket, ticketPrice);
        await sendTextMessage(instance, senderPhone,
          `ℹ️ El número *${paddedNumber}* ya es tuyo: boleta *${numbersOf(matchedTicket)}*, ${STATUS_LABEL[matchedTicket.status] || matchedTicket.status}${left > 0 ? `, saldo pendiente *${money(left)}*` : ''}.\n\n${left > 0 ? 'Para pagar o abonar, envíame la *foto del comprobante*.' : 'Está al día. ¡Mucha suerte! 🍀'}`);
        return { handled: true };
      } else {
        const availableAlts = tickets.filter(t => t.status === 'DISPONIBLE').slice(0, 3);
        let statusText = 'APARTADO';
        if (matchedTicket.status === 'PAGADA' || matchedTicket.status === 'CONFIRMADA') statusText = 'VENDIDO';
        if (matchedTicket.status === 'ABONO_PARCIAL') statusText = 'CON ABONO PARCIAL';

        let busyReply = `❌ *El número ${paddedNumber} ya NO está disponible.* (Estado: *${statusText}*)\n\n`;
        if (availableAlts.length > 0) {
          busyReply += `🎲 *Te sugerimos estas opciones disponibles:*\n`;
          availableAlts.forEach(a => {
            busyReply += `• ${a.numbers.join('  •  ')}\n`;
          });
          busyReply += `\n¿Te gustaría apartar alguno de ellos? Escribe el número que prefieras o escribe *DISPONIBLES*.`;
        } else {
          busyReply += `💡 Puedes escribir otro número de ${digits} cifras para verificar si está libre.`;
        }

        await sendTextMessage(instance, senderPhone, busyReply);
        return { handled: true };
      }
    } else {
      const availableAlts = tickets.filter(t => t.status === 'DISPONIBLE').slice(0, 3);
      let notFoundReply = `ℹ️ El número *${rawNumber}* no se encuentra en las oportunidades de este sorteo (*juega con ${digits} cifras*).\n\n`;
      if (availableAlts.length > 0) {
        notFoundReply += `🎲 *Te sugerimos estos números que sí están disponibles:*\n`;
        availableAlts.forEach(a => {
          notFoundReply += `• ${a.numbers.join('  •  ')}\n`;
        });
        notFoundReply += `\nEscribe el número que desees consultar o escribe *DISPONIBLES*.`;
      }
      await sendTextMessage(instance, senderPhone, notFoundReply);
      return { handled: true };
    }
  }

  // 9. FALLBACK Y ENRUTAMIENTO INTELIGENTE
  if (session?.currentTopic === 'rifa') {
    const raffleMsg = buildRaffleMessage(mainRaffle, companyName, digits, opportunities, ticketPrice, drawDateFormatted, lotteryName);
    await fallbackReply(raffleMsg);
    return { handled: true };
  }

  await fallbackReply(buildMainMenuMessage(companyName, advisor));
  return { handled: true };
}

// ---------------------------------------------------------------------------
// Flujos con confirmación: apartar una boleta y registrar comprobantes de pago.
// El bot nunca aparta, cambia ni registra un pago sin que el cliente lo confirme.
// El estado de la conversación se guarda en session.pending ({ type, ...datos }) por 30 minutos.
// ---------------------------------------------------------------------------
const PENDING_TTL_MS = 30 * 60 * 1000;
const YES_WORDS = new Set(['si', 'sii', 's', 'ok', 'okey', 'dale', 'listo', 'claro', 'confirmo', 'confirmado', 'confirmar', 'correcto', 'de acuerdo',
  'si confirmo', 'si quiero', 'si apartala', 'si apartalo', 'apartala', 'apartalo', 'vale', 'perfecto', 'si es correcto', 'si correcto']);
const NO_WORDS = new Set(['no', 'n', 'cancelar', 'cancela', 'cancelo', 'no gracias', 'nel', 'negativo', 'no es', 'incorrecto']);
const money = n => `$${Math.round(Number(n) || 0).toLocaleString('es-CO')}`;
const isYes = text => YES_WORDS.has(botBrain.normalize(text));
const isNo = text => NO_WORDS.has(botBrain.normalize(text));

function setPending(senderPhone, pending, db, saveDBCallback, raffleId) {
  updateSession(senderPhone, { pending: pending ? { ...pending, at: Date.now(), reminders: 0 } : null }, db, saveDBCallback, raffleId || null);
}

function getPending(session) {
  const p = session && session.pending;
  if (!p || !p.type) return null;
  return Date.now() - (p.at || 0) > PENDING_TTL_MS ? null : p;
}

const numbersOf = t => (t.numbers || []).join(' • ');
/** Solo se puede cambiar una boleta apartada que no tenga ningún pago (ni abono pendiente de validar). */
const isChangeable = t => t.status === 'RESERVADA' && (Number(t.totalPaid) || 0) === 0 && !(t.abonos || []).some(a => (Number(a.amount) || 0) > 0);
const priceOf = (t, fallback) => Number(t.price) || Number(fallback) || 0;
const balanceOf = (t, fallback) => Math.max(0, priceOf(t, fallback) - (Number(t.totalPaid) || 0));
const STATUS_LABEL = { RESERVADA: 'apartada', ABONO_PARCIAL: 'con abono parcial', PAGADA: 'pagada', CONFIRMADA: 'pagada y confirmada' };

/** Boletas de la rifa que ya son de este cliente (apartadas, con abono o pagadas). */
function myTickets(db, raffleId, phone) {
  return (db.tickets || []).filter(t => t.raffleId === raffleId && t.buyerPhone === phone && t.status !== 'DISPONIBLE');
}

/** Datos del comprador que el sistema ya conoce (de sus boletas anteriores o de la conversación). */
function knownProfile(db, phone, session) {
  const withData = (db.tickets || [])
    .filter(t => t.buyerPhone === phone && (t.buyerName || t.buyerDocument))
    .sort((a, b) => String(b.assignedDate || '').localeCompare(String(a.assignedDate || '')));
  const t = withData[0] || {};
  return {
    name: t.buyerName || session?.buyerName || '',
    document: t.buyerDocument || session?.buyerDocument || '',
    email: t.buyerEmail || session?.buyerEmail || '',
    city: t.buyerCity || session?.buyerCity || '',
    country: t.buyerCountry || session?.buyerCountry || 'Colombia'
  };
}

function missingProfileFields(p) {
  const missing = [];
  if (!p.name) missing.push('Nombre y Apellidos completos (o Razón Social)');
  if (!p.document) missing.push('Cédula de Ciudadanía o NIT');
  if (!p.email) missing.push('Correo electrónico (para envío de soporte de compra)');
  if (!p.city) missing.push('Ciudad y País (ej: San Martín, Meta)');
  return missing;
}

function profileLines(p) {
  const lines = [];
  if (p.name) lines.push(`• *Titular:* ${p.name}`);
  if (p.document) lines.push(`• *Cédula/NIT:* ${p.document}`);
  if (p.email) lines.push(`• *Correo:* ${p.email}`);
  if (p.city) lines.push(`• *Ciudad:* ${p.city}${p.country ? `, ${p.country}` : ''}`);
  return lines;
}

function releaseTicket(t) {
  t.status = 'DISPONIBLE';
  ['buyerName', 'buyerPhone', 'buyerDocument', 'buyerEmail', 'buyerCity', 'buyerCountry'].forEach(k => { t[k] = ''; });
  t.advisorId = null;
  t.advisorName = '';
  t.soldByBot = false;
  t.assignedDate = null;
  t.totalPaid = 0;
  t.balancePending = t.price;
}

/** Aparta la boleta para el cliente con los datos que ya se conocen. */
function reserveTicket(ctx, ticket, replacing) {
  const { db, senderPhone, mainRaffle, advisor, session } = ctx;
  const profile = knownProfile(db, senderPhone, session);
  if (replacing) {
    ticket.auditLogs = ticket.auditLogs || [];
    releaseTicket(replacing);
  }
  Object.assign(ticket, {
    buyerName: profile.name || ticket.buyerName || '',
    buyerDocument: profile.document || ticket.buyerDocument || '',
    buyerEmail: profile.email || ticket.buyerEmail || '',
    buyerCity: profile.city || ticket.buyerCity || '',
    buyerCountry: profile.country || ticket.buyerCountry || '',
    buyerPhone: senderPhone,
    soldByBot: true,
    saleChannel: 'Bot WhatsApp',
    assignedDate: new Date().toISOString(),
    status: 'RESERVADA'
  });
  const assignedAdv = getAssignedAdvisorForTicket(ticket, mainRaffle, db) || advisor;
  if (assignedAdv) {
    ticket.advisorId = assignedAdv.id;
    ticket.advisorName = assignedAdv.name;
    // Tipo de venta: punto = oficina (no comisiona), calle = calle; el integral lo define el administrador
    if (assignedAdv.type === 'PUNTO') ticket.saleZone = 'OFICINA';
    else if (!assignedAdv.type || assignedAdv.type === 'CALLE') ticket.saleZone = 'CALLE';
  }
  ticket.auditLogs = ticket.auditLogs || [];
  ticket.auditLogs.push({
    id: `log-${Date.now()}`,
    date: new Date().toISOString(),
    user: '🤖 Bot WhatsApp',
    action: 'VENTA_BOT',
    description: `Boleta ${replacing ? 'cambiada' : 'apartada'} por el cliente (confirmó por WhatsApp)${replacing ? ` • Reemplaza la boleta ${numbersOf(replacing)}` : ''}${ticket.advisorName ? ` • Asignada a: ${ticket.advisorName}` : ''}`
  });
}

/** Mensaje tras apartar: datos conocidos o faltantes, y las preguntas pendientes (asesor, cómo se enteró). */
async function sendReservedReply(ctx, ticket, number, changed) {
  const { instance, senderPhone, db, saveDBCallback, mainRaffle, cfg, session, drawDateFormatted, ticketPrice } = ctx;
  const profile = knownProfile(db, senderPhone, session);
  const missing = missingProfileFields(profile);
  const hasRealAdvisor = !!ticket.advisorId && ticket.advisorName !== 'Venta WhatsApp';
  const askAdvisorRef = missing.length === 0 && !hasRealAdvisor && ticket.advisorName !== 'Venta Directa WhatsApp';
  const askHowHeard = missing.length === 0 && !askAdvisorRef && cfg.howHeard.enabled && !ticket.howHeard && !session?.howHeard;

  let msg = `${changed ? '🔄 *¡BOLETA CAMBIADA!*' : '✅ *¡BOLETA APARTADA!*'} 🎟️\n\n`;
  msg += `🔢 *Tus números:* ${numbersOf(ticket)}\n`;
  msg += `💵 *Valor:* ${money(priceOf(ticket, ticketPrice))} COP\n`;
  msg += `🎯 *Sorteo:* ${mainRaffle.title}${drawDateFormatted ? ` el ${drawDateFormatted}` : ''}\n`;
  if (ticket.advisorName && ticket.advisorName !== 'Venta WhatsApp') msg += `👤 *Asesor:* ${ticket.advisorName}\n`;

  if (missing.length === 0) {
    msg += `\n📋 *Datos que tenemos de ti:*\n${profileLines(profile).join('\n')}\n`;
    msg += `\nSi algún dato cambió, envíanos el dato corregido. Si todo está bien, no necesitas hacer nada más.`;
  } else {
    if (profileLines(profile).length) msg += `\n✅ *Datos ya registrados:*\n${profileLines(profile).join('\n')}\n`;
    msg += `\n📋 *Para completar tu Soporte Digital de Compra, indícanos:*\n${missing.map((m, i) => `${i + 1}️⃣ *${m}*`).join('\n')}\n`;
    msg += `\n✍️ *Envíalos en tu siguiente mensaje.*`;
  }
  msg += `\n\n💳 Escribe *PAGOS* para ver las cuentas. Cuando pagues, envíame la *foto del comprobante* y yo lo asocio a tu boleta.`;
  if (askAdvisorRef) msg += `\n\n${ADVISOR_REF_QUESTION}`;
  else if (askHowHeard) msg += `\n\n${buildHowHeardQuestion(cfg.howHeard.options)}`;

  updateSession(senderPhone, {
    pending: null,
    lastTicketId: ticket.id,
    lastRaffleId: mainRaffle.id,
    lastOpportunity: number,
    lastTicketNumber: ticket.ticketNumber,
    waitingData: missing.length > 0,
    awaitingAdvisorRef: askAdvisorRef,
    awaitingAdvisorRefAt: askAdvisorRef ? Date.now() : undefined,
    awaitingHowHeard: askHowHeard,
    awaitingHowHeardAt: askHowHeard ? Date.now() : undefined
  }, db, saveDBCallback, mainRaffle.id);
  if (typeof saveDBCallback === 'function') saveDBCallback(mainRaffle.id);
  await sendTextMessage(instance, senderPhone, msg);
}

/** El cliente escribió un número libre: se le muestra y se le pide confirmar (nunca se aparta solo). */
async function offerReservation(ctx, ticket, number) {
  const { instance, senderPhone, db, saveDBCallback, mainRaffle, ticketPrice, lotteryName, drawDateFormatted } = ctx;
  const mine = myTickets(db, mainRaffle.id, senderPhone);
  const others = ticket.numbers.filter(n => n !== number);
  const assignedAdv = getAssignedAdvisorForTicket(ticket, mainRaffle, db) || ctx.advisor;

  let head = `✅ *¡EL NÚMERO ${number} ESTÁ DISPONIBLE!* 🎉\n\n`;
  head += `🔢 *Juegas con:* *${number}* ${others.length ? `(y también con *${others.join(', ')}*)` : ''}\n`;
  head += `💵 *Valor Boleta:* ${money(ticketPrice)} COP\n`;
  if (mainRaffle.minAbono) head += `💰 *Abono Mínimo:* ${money(mainRaffle.minAbono)} COP\n`;
  head += `🎯 *Sorteo:* ${mainRaffle.title}\n🏆 *Juega con:* ${lotteryName} el ${drawDateFormatted}`;
  if (assignedAdv) head += `\n👤 *Asesor asignado:* *${assignedAdv.name}*`;

  if (mine.length === 0) {
    setPending(senderPhone, { type: 'RESERVE', ticketId: ticket.id, number }, db, saveDBCallback, mainRaffle.id);
    await sendTextMessage(instance, senderPhone, `${head}\n\n✍️ *¿Confirmas que deseas apartarla?*\nResponde *SÍ* para apartarla o *NO* para cancelar.`);
    return;
  }

  // Ya tiene boletas: se pregunta si es una compra nueva o un cambio
  const changeable = mine.filter(isChangeable);
  const options = ['NEW'];
  if (changeable.length) options.push('CHANGE');
  options.push('CANCEL');
  const labels = {
    NEW: '*Comprar una boleta NUEVA* (además de la que ya tienes)',
    CHANGE: '*CAMBIAR* una de tus boletas apartadas (sin pagos) por esta',
    CANCEL: '*Cancelar* (no hacer nada)'
  };
  let msg = `${head}\n\n`;
  msg += `🎟️ *Ya tienes ${mine.length === 1 ? 'esta boleta' : 'estas boletas'}:*\n`;
  mine.forEach(t => { msg += `• ${numbersOf(t)} — ${STATUS_LABEL[t.status] || t.status}${balanceOf(t, ticketPrice) > 0 ? `, saldo ${money(balanceOf(t, ticketPrice))}` : ''}\n`; });
  msg += `\n¿Qué deseas hacer?\n${options.map((o, i) => `${i + 1}️⃣ ${labels[o]}`).join('\n')}`;
  setPending(senderPhone, { type: 'KIND', ticketId: ticket.id, number, options }, db, saveDBCallback, mainRaffle.id);
  await sendTextMessage(instance, senderPhone, msg);
}

async function confirmReservation(ctx, ticket, number, action, oldTicket) {
  const { instance, senderPhone, db, saveDBCallback, mainRaffle, ticketPrice } = ctx;
  let msg;
  if (action === 'CHANGE') {
    msg = `🔄 *Vas a CAMBIAR tu boleta*\n\n• Actual: *${numbersOf(oldTicket)}* (quedará libre)\n• Nueva: *${numbersOf(ticket)}* — ${money(priceOf(ticket, ticketPrice))} COP\n\n¿Confirmas el cambio? Responde *SÍ* o *NO*.`;
  } else {
    msg = `🎟️ *Vas a apartar una boleta NUEVA* (además de las que ya tienes)\n\n• Números: *${numbersOf(ticket)}*\n• Valor: ${money(priceOf(ticket, ticketPrice))} COP\n\n¿Confirmas? Responde *SÍ* o *NO*.`;
  }
  setPending(senderPhone, { type: 'CONFIRM', action, ticketId: ticket.id, number, oldTicketId: oldTicket ? oldTicket.id : null }, db, saveDBCallback, mainRaffle.id);
  await sendTextMessage(instance, senderPhone, msg);
}

async function executeReservation(ctx, pending) {
  const { instance, senderPhone, db, saveDBCallback, mainRaffle } = ctx;
  const ticket = (db.tickets || []).find(t => t.id === pending.ticketId);
  if (!ticket || ticket.status !== 'DISPONIBLE') {
    setPending(senderPhone, null, db, saveDBCallback, mainRaffle.id);
    await sendTextMessage(instance, senderPhone, `😕 Ese número ya no está disponible (alguien lo acaba de apartar). Escribe *DISPONIBLES* para ver otras opciones.`);
    return;
  }
  let old = null;
  if (pending.action === 'CHANGE') {
    old = (db.tickets || []).find(t => t.id === pending.oldTicketId);
    if (!old || old.buyerPhone !== senderPhone || !isChangeable(old)) {
      setPending(senderPhone, null, db, saveDBCallback, mainRaffle.id);
      await sendTextMessage(instance, senderPhone, `⚠️ Tu boleta anterior ya no se puede cambiar (tiene pagos o cambió de estado). Escribe *ASESOR* para que te ayudemos.`);
      return;
    }
  }
  reserveTicket(ctx, ticket, old);
  await sendReservedReply(ctx, ticket, pending.number, !!old);
}

// ---------------------------------------------------------------------------
// Comprobantes de pago
// ---------------------------------------------------------------------------
const approvalKeyOf = v => String(v || '').toUpperCase().replace(/[^0-9A-Z]/g, '');

/** Monto escrito por el cliente, sin confundir el número de comprobante con un valor. */
function detectAmount(text) {
  if (!text) return null;
  const stripped = String(text)
    .replace(/(?:comprobante|aprobaci[oó]n|transacci[oó]n|referencia|ref)\D{0,6}\d{6,}/gi, ' ')
    .replace(/\b\d{9,}\b/g, ' ');
  const info = extractTransferInfo(stripped);
  if (info.amount) return info.amount;
  const plain = stripped.trim().match(/^\$?\s*([\d.,]+)\s*(?:cop|pesos)?$/i);
  if (plain) {
    const value = parseInt(plain[1].replace(/[.,]/g, ''), 10);
    if (value >= 1000) return value;
  }
  return null;
}

/** Guarda la imagen del comprobante (si llegó en el mensaje): huella para detectar repetidos y copia en Drive. */
async function storeReceiptMedia(ctx, media) {
  if (!media || !media.base64) return null;
  const clean = String(media.base64).replace(/^data:[^;]+;base64,/, '');
  const buffer = Buffer.from(clean, 'base64');
  if (buffer.length < 2000) return null;
  const out = { hash: require('crypto').createHash('sha256').update(buffer).digest('hex'), driveId: null, url: null, webViewUrl: null };
  try {
    const { mainRaffle, company, companyName } = ctx;
    const folders = await driveService.getRaffleFolders(companyName, mainRaffle.companyId || (company && company.id), mainRaffle.title, mainRaffle.id, mainRaffle.driveFolderId);
    mainRaffle.driveFolderId = folders.raffleFolderId;
    const up = await driveService.uploadFileToDrive({
      buffer,
      filename: `soporte_whatsapp_${ctx.senderPhone}_${Date.now()}.jpg`,
      mimeType: media.mimeType || 'image/jpeg',
      parentFolderId: folders.soportesFolderId
    });
    out.driveId = up.fileId;
    out.url = up.directUrl;
    out.webViewUrl = up.webViewUrl;
  } catch (err) {
    console.warn('⚠️ No se pudo guardar el comprobante de WhatsApp en Drive:', err.message);
  }
  return out;
}

const accountLabelOf = a => [a.bank, a.accountType, a.accountNumber, a.key ? `llave ${a.key}` : '', a.holder].filter(Boolean).join(' • ');

/**
 * Cuentas de la rifa cuyo número o llave aparece en el texto leído del comprobante. Solo cuenta un identificador fuerte
 * (número completo, sus últimos 6 dígitos —los bancos suelen ocultar el resto— o una llave alfanumérica).
 */
function accountsFoundInProof(text, accounts) {
  const digitsOnly = String(text || '').replace(/\D/g, '');
  const compact = String(text || '').toLowerCase().replace(/\s+/g, '');
  return (accounts || []).filter(a => [a.accountNumber, a.key].some(v => {
    const raw = String(v || '').trim();
    if (!raw) return false;
    const d = raw.replace(/\D/g, '');
    if (d.length >= 6 && d.length === raw.replace(/[\s.-]/g, '').length) {
      return digitsOnly.includes(d) || (d.length >= 8 && digitsOnly.includes(d.slice(-6)));
    }
    const k = raw.toLowerCase().replace(/\s+/g, '');
    return k.length >= 5 && compact.includes(k);
  }));
}

/** Datos del comprobante que viajan de un paso al siguiente de la conversación. */
const planCarry = plan => ({
  approval: plan.approval || '', bank: plan.bank || '', soporte: plan.soporte || null, hint: plan.hint || '',
  proofTotal: plan.proofTotal || 0, proofUnreadable: !!plan.proofUnreadable, accountIds: plan.accountIds || []
});

async function startReceiptFlow(ctx, info) {
  const { instance, senderPhone, db, saveDBCallback, mainRaffle, ticketPrice, session } = ctx;
  const soporte = await storeReceiptMedia(ctx, info.media);
  const mine = myTickets(db, mainRaffle.id, senderPhone);
  const payable = mine.filter(t => balanceOf(t, ticketPrice) > 0);

  if (mine.length === 0) {
    await sendTextMessage(instance, senderPhone,
      `📸 Recibí tu comprobante, pero *aún no tienes ninguna boleta apartada* a este número de WhatsApp.\n\nDime qué número deseas jugar (o escribe *DISPONIBLES*), apártalo y luego envíame el comprobante para asociarlo a tu boleta.`);
    return;
  }
  if (payable.length === 0) {
    await sendTextMessage(instance, senderPhone, `✅ Todas tus boletas ya están *pagadas por completo*, así que no tengo saldo pendiente al que aplicar este comprobante.\n\nSi quieres comprar otra boleta, escribe el número que deseas o *DISPONIBLES*. Si crees que es un error, escribe *ASESOR*.`);
    return;
  }

  // Se lee la imagen (OCR en el servidor): número de aprobación, banco de origen, valor y a qué cuenta de la rifa se hizo
  let proofRead = null;
  if (info.media && info.media.base64) {
    try {
      proofRead = await ocrService.readProof(Buffer.from(String(info.media.base64).replace(/^data:[^;]+;base64,/, ''), 'base64'));
    } catch (err) {
      console.warn('⚠️ No se pudo leer el comprobante del bot:', err.message);
    }
  }
  const readable = !!(proofRead && proofRead.readable);
  const found = readable ? accountsFoundInProof(proofRead.text, mainRaffle.transferAccounts || []) : [];
  const readAmounts = readable ? (proofRead.amounts || []).filter(v => Number.isFinite(v) && v > 0) : [];
  const proofTotal = readAmounts.length ? Math.max(...readAmounts) : 0;
  const base = {
    // El número de aprobación se sube del soporte; lo escrito por el cliente en el mensaje tiene prioridad
    approval: info.approval || (readable && proofRead.references && proofRead.references[0]) || '',
    bank: info.bank || (readable && proofRead.bank) || '',
    soporte,
    hint: info.hintNumber || '',
    proofTotal,
    proofUnreadable: !!(proofRead && proofRead.available && !readable),
    accountIds: found.map(a => a.id)
  };
  if (!info.amount) {
    setPending(senderPhone, { type: 'RECEIPT_AMOUNT', ...base, suggestedAmount: proofTotal || 0 }, db, saveDBCallback, mainRaffle.id);
    await sendTextMessage(instance, senderPhone, proofTotal
      ? `📸 *¡Recibí tu comprobante!*\n\nLeí *${money(proofTotal)}* en la imagen. ¿Ese es el valor transferido? Responde *SÍ* o escribe el valor correcto solo en números (ej: *150000*).`
      : `📸 *¡Recibí tu comprobante!*\n\nPara registrarlo bien necesito el *valor transferido*. ¿De cuánto fue? Escríbelo solo en números (ej: *150000*).`);
    return;
  }
  await receiptSelectTarget(ctx, { ...base, amount: info.amount }, payable);
}

async function receiptSelectTarget(ctx, plan, payable) {
  const { instance, senderPhone, db, saveDBCallback, mainRaffle, ticketPrice, session } = ctx;
  let candidates = payable || myTickets(db, mainRaffle.id, senderPhone).filter(t => balanceOf(t, ticketPrice) > 0);
  // Si el cliente nombró el número en el mensaje, se usa esa boleta
  if (plan.hint) {
    const byHint = candidates.filter(t => (t.numbers || []).includes(plan.hint));
    if (byHint.length === 1) candidates = byHint;
  }
  if (candidates.length === 1) {
    await receiptConfirm(ctx, candidates[0], plan);
    return;
  }
  let msg = `📸 *¡Recibí tu comprobante por ${money(plan.amount)}!*\n\nTienes varias boletas con saldo. *¿A cuál corresponde este pago?* Responde con el número de la lista:\n\n`;
  candidates.forEach((t, i) => { msg += `${i + 1}️⃣ ${numbersOf(t)} — saldo ${money(balanceOf(t, ticketPrice))}\n`; });
  setPending(senderPhone, { type: 'RECEIPT_WHICH', ...plan, candidateIds: candidates.map(t => t.id) }, db, saveDBCallback, mainRaffle.id);
  await sendTextMessage(instance, senderPhone, msg.trim());
}

async function receiptConfirm(ctx, ticket, plan) {
  const { instance, senderPhone, db, saveDBCallback, mainRaffle, ticketPrice } = ctx;
  // ¿A qué cuenta se transfirió? Si el comprobante no lo deja claro y la rifa tiene varias cuentas, se le pregunta al cliente
  const accounts = mainRaffle.transferAccounts || [];
  if (accounts.length && !plan.account) {
    const foundAccounts = (plan.accountIds || []).map(id => accounts.find(a => a.id === id)).filter(Boolean);
    if (accounts.length === 1) plan = { ...plan, account: accounts[0] };
    else if (foundAccounts.length === 1) plan = { ...plan, account: foundAccounts[0] };
    else {
      const options = foundAccounts.length > 1 ? foundAccounts : accounts;
      let ask = `🏦 *¿A cuál de nuestras cuentas hiciste la transferencia?*\n\nNo logré identificarla en el comprobante. Responde con el número:\n\n`;
      options.forEach((a, i) => { ask += `${i + 1}️⃣ ${accountLabelOf(a)}\n`; });
      setPending(senderPhone, { type: 'RECEIPT_ACCOUNT', ticketId: ticket.id, amount: plan.amount, ...planCarry(plan), accountIds: options.map(a => a.id) }, db, saveDBCallback, mainRaffle.id);
      await sendTextMessage(instance, senderPhone, ask.trim());
      return;
    }
  }
  const price = priceOf(ticket, ticketPrice);
  const paid = Number(ticket.totalPaid) || 0;
  const balance = balanceOf(ticket, ticketPrice);
  const amount = plan.amount;

  let msg = `📸 *Revisemos tu comprobante antes de registrarlo*\n\n`;
  msg += `🎟️ *Boleta:* ${numbersOf(ticket)}\n`;
  msg += `💵 *Valor de la boleta:* ${money(price)}\n`;
  msg += `✅ *Pagado hasta hoy:* ${money(paid)}\n`;
  msg += `⏳ *Saldo pendiente:* ${money(balance)}\n`;
  msg += `💸 *Valor de este comprobante:* ${money(amount)}\n`;
  if (plan.approval) msg += `🧾 *Comprobante No.:* ${plan.approval}\n`;
  if (plan.bank) msg += `🏛️ *Medio / Banco:* ${plan.bank}\n`;
  if (plan.account) msg += `🏦 *Cuenta destino:* ${accountLabelOf(plan.account)}\n`;

  if (amount > balance) {
    const surplus = amount - balance;
    msg += `\n💡 *Este pago supera el saldo por ${money(surplus)}.* Esos ${money(surplus)} quedan a tu favor para otra boleta${surplus >= price ? ` (alcanza para ${Math.floor(surplus / price)} boleta(s) completa(s))` : ''}. Un asesor te ayudará a aplicarlos.\n`;
  } else if (amount === balance) {
    msg += `\n✅ Con este pago tu boleta *quedaría totalmente pagada*.\n`;
  } else {
    msg += `\nℹ️ Es un *abono parcial*: después de este pago quedarían pendientes *${money(balance - amount)}*.\n`;
    if (mainRaffle.minAbono && amount < Number(mainRaffle.minAbono)) {
      msg += `⚠️ Ojo: el abono mínimo de esta rifa es ${money(mainRaffle.minAbono)}.\n`;
    }
  }
  if (plan.approval && checkDuplicateApprovalNumber(plan.approval, ticket.id, db)) {
    msg += `\n🚨 Este número de comprobante ya figura en otra boleta; nuestro equipo lo revisará con el banco antes de validarlo.\n`;
  }
  if (!plan.soporte) {
    msg += `\n⚠️ No pude guardar la imagen del comprobante; nuestro equipo puede pedirte que la envíes de nuevo.\n`;
  }
  msg += `\n👉 *¿Confirmas que este pago es para la boleta ${numbersOf(ticket)}?* Responde *SÍ* para registrarlo o *NO* para cancelar.`;

  setPending(senderPhone, {
    type: 'RECEIPT_CONFIRM', ticketId: ticket.id, amount, ...planCarry(plan),
    accountId: plan.account ? plan.account.id : null, accountLabel: plan.account ? accountLabelOf(plan.account) : ''
  }, db, saveDBCallback, mainRaffle.id);
  await sendTextMessage(instance, senderPhone, msg);
}

async function receiptRegister(ctx, pending) {
  const { instance, senderPhone, db, saveDBCallback, mainRaffle, ticketPrice, advisor, cfg, session } = ctx;
  const ticket = (db.tickets || []).find(t => t.id === pending.ticketId);
  if (!ticket || ticket.buyerPhone !== senderPhone) {
    setPending(senderPhone, null, db, saveDBCallback, mainRaffle.id);
    await sendTextMessage(instance, senderPhone, `😕 No pude encontrar esa boleta. Escribe *ASESOR* y te ayudamos.`);
    return;
  }
  const balanceBefore = balanceOf(ticket, ticketPrice);
  const amount = pending.amount;
  const soporte = pending.soporte;
  const flags = [];
  const key = approvalKeyOf(pending.approval);
  const sameApproval = [];
  if (key) {
    for (const t of db.tickets || []) {
      for (const a of [...(t.abonos || []), ...(t.voidedAbonos || [])]) if (approvalKeyOf(a.approvalNumber) === key) sameApproval.push(a);
    }
    if (sameApproval.length) flags.push({ code: 'APROBACION_REPETIDA', level: 'MEDIA', detail: `El número de aprobación ya estaba en ${sameApproval.length} pago(s).` });
  }
  if (soporte && soporte.hash) {
    const same = [];
    for (const t of db.tickets || []) {
      for (const a of [...(t.abonos || []), ...(t.voidedAbonos || [])]) if (a.soporteHash === soporte.hash) same.push(a);
    }
    if (same.length) {
      const sameKey = same.every(a => approvalKeyOf(a.approvalNumber) === key);
      flags.push({ code: 'SOPORTE_REPETIDO', level: sameKey ? 'MEDIA' : 'ALTA', detail: sameKey ? `Mismo soporte y misma aprobación en ${same.length} pago(s) ya registrados.` : `El mismo soporte se usó con OTRO número de aprobación en ${same.length} pago(s).` });
    }
  } else {
    flags.push({ code: 'SIN_SOPORTE', level: 'MEDIA', detail: 'El comprobante llegó por WhatsApp pero no se pudo guardar la imagen: solicítela de nuevo antes de validar.' });
  }
  if (pending.proofUnreadable) flags.push({ code: 'COMPROBANTE_ILEGIBLE', level: 'MEDIA', detail: 'No se pudo leer el comprobante: compare a mano el valor, la cuenta y el número de aprobación con el soporte.' });
  else if (!pending.approval) flags.push({ code: 'SIN_APROBACION', level: 'MEDIA', detail: 'No se encontró el número de aprobación en el comprobante: ingréselo a mano al validar.' });
  if (amount > balanceBefore) flags.push({ code: 'EXCEDENTE', level: 'BAJA', detail: `El pago supera el saldo por ${money(amount - balanceBefore)}: distribuya el excedente en otra boleta.` });

  const now = new Date().toISOString();
  const abono = {
    id: `abn-${Date.now()}`,
    amount,
    metodoPago: 'transferencia',
    date: now,
    sellerId: ticket.advisorId || (advisor ? advisor.id : ''),
    sellerName: ticket.advisorName ? `${ticket.advisorName} (🤖 Bot WhatsApp)` : '🤖 Bot WhatsApp',
    note: `Transferencia reportada por WhatsApp${pending.approval ? ` (Comprobante: #${pending.approval})` : ''} — confirmada por el cliente`,
    approvalNumber: pending.approval || '',
    originBank: pending.bank || 'Transferencia Bancaria',
    cuentaDestino: pending.accountLabel || '',
    ...(pending.accountId ? { transferAccountId: pending.accountId } : {}),
    // Valor total que muestra el comprobante: permite repartir una misma transferencia entre varias boletas
    ...(pending.proofTotal > 0 ? { proofTotal: pending.proofTotal } : {}),
    transferDate: now,
    duplicateApprovalConfirmed: sameApproval.length > 0,
    soporteUrl: soporte ? soporte.url : null,
    soporteDriveId: soporte ? soporte.driveId : null,
    soporteWebViewUrl: soporte ? soporte.webViewUrl : null,
    ...(soporte && soporte.hash ? { soporteHash: soporte.hash } : {}),
    ...(flags.some(f => f.level !== 'BAJA') ? { riskFlags: flags, riskReview: { status: 'PENDIENTE' } } : (flags.length ? { riskFlags: flags, riskReview: { status: 'DESCARTADA', by: '🤖 Bot', at: now, note: 'Solo informativa (excedente)' } } : {}))
    // Sin 'verification': queda POR_VALIDAR en Caja
  };
  ticket.abonos = ticket.abonos || [];
  ticket.abonos.push(abono);
  ticket.totalPaid = ticket.abonos.reduce((s, a) => s + (a.amount || 0), 0);
  ticket.balancePending = Math.max(0, priceOf(ticket, ticketPrice) - ticket.totalPaid);
  ticket.pendingTransferValidation = true;
  ticket.auditLogs = ticket.auditLogs || [];
  ticket.auditLogs.push({
    id: `log-${Date.now()}`,
    date: now,
    user: '🤖 Bot WhatsApp',
    action: 'VENTA_BOT',
    description: `Comprobante de ${money(amount)} reportado y confirmado por el cliente en WhatsApp (pendiente de validar en Caja)`
  });
  if (typeof saveDBCallback === 'function') saveDBCallback(mainRaffle.id);

  const profile = knownProfile(db, senderPhone, session);
  const missing = missingProfileFields(profile);
  const hasRealAdvisor = !!ticket.advisorId && ticket.advisorName !== 'Venta WhatsApp';
  const askAdvisorRef = !hasRealAdvisor && ticket.advisorName !== 'Venta Directa WhatsApp';

  let msg = `✅ *¡Pago registrado!* 📸\n\n`;
  msg += `🎟️ *Boleta:* ${numbersOf(ticket)}\n💸 *Comprobante:* ${money(amount)}\n`;
  msg += ticket.balancePending > 0 ? `⏳ *Saldo pendiente:* ${money(ticket.balancePending)}\n` : `🎉 *Tu boleta queda totalmente pagada* (sujeta a validación del banco).\n`;
  msg += `\nNuestro equipo validará la transferencia en la cuenta bancaria y te avisaremos por este chat.\n`;
  if (missing.length) {
    msg += `\n📋 *Para completar tu Soporte Digital de Compra, indícanos:*\n${missing.map((m, i) => `${i + 1}️⃣ *${m}*`).join('\n')}\n`;
  } else {
    msg += `\n🌐 *Consulta tu boleta y soporte aquí:*\n${PUBLIC_BASE_URL}/boleta?phone=${senderPhone}\n`;
  }
  if (askAdvisorRef) msg += `\n${ADVISOR_REF_QUESTION}\n`;
  msg += `\n¡Muchas gracias y mucha suerte! 🍀`;

  updateSession(senderPhone, {
    pending: null,
    lastTicketId: ticket.id,
    lastRaffleId: mainRaffle.id,
    waitingData: missing.length > 0,
    awaitingAdvisorRef: askAdvisorRef,
    awaitingAdvisorRefAt: askAdvisorRef ? Date.now() : undefined,
    pendingAmount: null,
    pendingApproval: null,
    pendingBank: null
  }, db, saveDBCallback, mainRaffle.id);
  await sendTextMessage(instance, senderPhone, msg);
}

/**
 * Responde a lo que el cliente contesta mientras hay una confirmación pendiente.
 * Devuelve true si el mensaje se atendió aquí; false para que siga el flujo normal.
 */
async function handlePendingFlow(ctx) {
  const { instance, senderPhone, userText, db, saveDBCallback, session, mainRaffle, cfg, digits, ticketPrice } = ctx;
  const pending = getPending(session);
  if (!pending) return false;
  const norm = botBrain.normalize(userText);
  if (!norm) return false;
  const clear = () => setPending(senderPhone, null, db, saveDBCallback, mainRaffle.id);
  const looksLikeNumberQuery = /^\d+$/.test(norm) && norm.length >= 3;
  const wantsHuman = botBrain.isHandoffRequest(cfg, userText) && !/^\d{1,2}$/.test(norm);
  const remind = async (text) => {
    if ((pending.reminders || 0) >= 2) { clear(); return false; }
    updateSession(senderPhone, { pending: { ...pending, reminders: (pending.reminders || 0) + 1 } }, db, saveDBCallback, mainRaffle.id);
    await sendTextMessage(instance, senderPhone, text);
    return true;
  };
  const cancelled = async () => {
    clear();
    await sendTextMessage(instance, senderPhone, `👍 Listo, no hice ningún cambio. Escribe un número para consultarlo, *DISPONIBLES* para ver opciones o *ASESOR* para hablar con una persona.`);
    return true;
  };

  if (pending.type === 'RECEIPT_AMOUNT') {
    if (wantsHuman) { clear(); return false; }
    // "SÍ" confirma el valor que se leyó en el comprobante
    const amount = (isYes(userText) && pending.suggestedAmount) ? pending.suggestedAmount : detectAmount(userText);
    if (!amount) return remind(`No pude entender el valor. Escríbelo solo en números, por ejemplo *150000*${pending.suggestedAmount ? ` o responde *SÍ* si fueron ${money(pending.suggestedAmount)}` : ''}.`);
    await receiptSelectTarget(ctx, { ...planCarry(pending), amount });
    return true;
  }

  if (pending.type === 'RECEIPT_ACCOUNT') {
    if (wantsHuman) { clear(); return false; }
    if (isNo(userText)) return cancelled();
    const accounts = mainRaffle.transferAccounts || [];
    const options = (pending.accountIds || []).map(id => accounts.find(a => a.id === id)).filter(Boolean);
    const chosenAccount = /^\d{1,2}$/.test(norm) ? (options[parseInt(norm, 10) - 1] || null) : null;
    if (!chosenAccount) return remind(`Responde con el número de la lista (1${options.length > 1 ? ` a ${options.length}` : ''}) para saber a qué cuenta transferiste, o *NO* para cancelar.`);
    const accTicket = (db.tickets || []).find(t => t.id === pending.ticketId);
    if (!accTicket) { clear(); return false; }
    await receiptConfirm(ctx, accTicket, { ...planCarry(pending), amount: pending.amount, account: chosenAccount });
    return true;
  }

  if (pending.type === 'RECEIPT_WHICH') {
    if (wantsHuman) { clear(); return false; }
    if (isNo(userText)) return cancelled();
    const candidates = (pending.candidateIds || []).map(id => (db.tickets || []).find(t => t.id === id)).filter(Boolean);
    let chosen = null;
    if (/^\d{1,2}$/.test(norm)) chosen = candidates[parseInt(norm, 10) - 1] || null;
    if (!chosen && /^\d{3,}$/.test(norm)) chosen = candidates.find(t => (t.numbers || []).includes(norm) || (t.numbers || []).includes(norm.padStart(digits, '0'))) || null;
    if (!chosen) return remind(`Responde con el número de la lista (1${candidates.length > 1 ? ` a ${candidates.length}` : ''}) o escribe *NO* para cancelar.`);
    await receiptConfirm(ctx, chosen, { ...planCarry(pending), amount: pending.amount });
    return true;
  }

  if (pending.type === 'RECEIPT_CONFIRM') {
    if (isYes(userText)) { await receiptRegister(ctx, pending); return true; }
    if (isNo(userText)) {
      clear();
      await sendTextMessage(instance, senderPhone, `👍 No registré el pago. Si te equivocaste de boleta o de valor, envíame de nuevo la foto del comprobante.`);
      return true;
    }
    if (wantsHuman) { clear(); return false; }
    return remind(`Responde *SÍ* para registrar este pago o *NO* para cancelar.`);
  }

  // Reserva / cambio de boleta
  if (looksLikeNumberQuery || wantsHuman) { clear(); return false; }

  if (pending.type === 'RESERVE') {
    if (isYes(userText)) { await executeReservation(ctx, { ...pending, action: 'NEW' }); return true; }
    if (isNo(userText)) return cancelled();
    return remind(`¿Confirmas que deseas apartar el número *${pending.number}*? Responde *SÍ* o *NO*.`);
  }

  if (pending.type === 'KIND') {
    const options = pending.options || ['NEW', 'CANCEL'];
    let choice = null;
    if (/^\d$/.test(norm)) choice = options[parseInt(norm, 10) - 1] || null;
    else if (/nueva|nuevo|otra|adicional/.test(norm)) choice = 'NEW';
    else if (/cambi/.test(norm)) choice = options.includes('CHANGE') ? 'CHANGE' : null;
    else if (isNo(userText)) choice = 'CANCEL';
    if (!choice) return remind(`Responde con el número de la opción (1${options.length > 1 ? ` a ${options.length}` : ''}).`);
    if (choice === 'CANCEL') return cancelled();
    const ticket = (db.tickets || []).find(t => t.id === pending.ticketId);
    if (!ticket || ticket.status !== 'DISPONIBLE') {
      clear();
      await sendTextMessage(instance, senderPhone, `😕 Ese número ya no está disponible. Escribe *DISPONIBLES* para ver otras opciones.`);
      return true;
    }
    if (choice === 'NEW') { await confirmReservation(ctx, ticket, pending.number, 'NEW', null); return true; }
    const all = myTickets(db, mainRaffle.id, senderPhone);
    let msg = `🔄 *¿Cuál de tus boletas quieres cambiar* por la nueva *${numbersOf(ticket)}*?\n\n`;
    all.forEach((t, i) => {
      msg += `${i + 1}️⃣ ${numbersOf(t)} — ${isChangeable(t) ? 'apartada, sin pagos ✅' : `${STATUS_LABEL[t.status] || t.status} 🔒 _(no se puede cambiar: ya tiene pagos)_`}\n`;
    });
    msg += `\nResponde con el número de la boleta que deseas cambiar o escribe *NO* para cancelar.`;
    setPending(senderPhone, { type: 'WHICH_CHANGE', ticketId: ticket.id, number: pending.number, listIds: all.map(t => t.id) }, db, saveDBCallback, mainRaffle.id);
    await sendTextMessage(instance, senderPhone, msg);
    return true;
  }

  if (pending.type === 'WHICH_CHANGE') {
    if (isNo(userText)) return cancelled();
    const list = (pending.listIds || []).map(id => (db.tickets || []).find(t => t.id === id)).filter(Boolean);
    const chosen = /^\d{1,2}$/.test(norm) ? list[parseInt(norm, 10) - 1] : null;
    if (!chosen) return remind(`Responde con el número de la lista (1${list.length > 1 ? ` a ${list.length}` : ''}) o escribe *NO* para cancelar.`);
    if (!isChangeable(chosen)) {
      // No se puede cambiar una boleta con pagos: se le explica y se le deja elegir otra
      await sendTextMessage(instance, senderPhone, `🔒 La boleta *${numbersOf(chosen)}* ya tiene pagos registrados y *no se puede cambiar*.\n\nElige otra de la lista (solo las apartadas sin pagos) o escribe *NO* para cancelar. Si necesitas ayuda con esa boleta, escribe *ASESOR*.`);
      return true;
    }
    const ticket = (db.tickets || []).find(t => t.id === pending.ticketId);
    if (!ticket || ticket.status !== 'DISPONIBLE') { clear(); await sendTextMessage(instance, senderPhone, `😕 Ese número ya no está disponible.`); return true; }
    await confirmReservation(ctx, ticket, pending.number, 'CHANGE', chosen);
    return true;
  }

  if (pending.type === 'CONFIRM') {
    if (isYes(userText)) { await executeReservation(ctx, pending); return true; }
    if (isNo(userText)) return cancelled();
    return remind(`Responde *SÍ* para confirmar o *NO* para cancelar.`);
  }

  clear();
  return false;
}

module.exports = {
  formatPhoneNumber,
  getInstanceName,
  getStatus,
  connectInstance,
  disconnectInstance,
  sendTextMessage,
  sendDocument,
  setDocumentHandler,
  handleWebhookEvent,
  extractBuyerProfile
};
