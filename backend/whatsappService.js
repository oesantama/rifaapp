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
const { byDrawDate, participationText: participationTextRaw } = require('./drawSchedule');
const participationText = (raffle, paid) => participationTextRaw(raffle, paid, new Date(Date.now() - 5 * 3600 * 1000).toISOString().slice(0, 10));

function formatPhoneNumber(number) {
  let clean = String(number || '').replace(/[^0-9]/g, '');
  if (clean.length === 10 && clean.startsWith('3')) {
    clean = '57' + clean;
  }
  return clean;
}

/**
 * Número real de quien escribe. WhatsApp a veces identifica al cliente con un código interno (@lid) y entrega el
 * teléfono aparte (remoteJidAlt / senderPn): se usa siempre el teléfono, nunca el código, para poder responderle.
 */
function senderJidOf(key, data) {
  const jid = String((key && key.remoteJid) || '');
  if (!jid.endsWith('@lid')) return jid;
  const alt = (key && (key.remoteJidAlt || key.senderPn)) || (data && (data.senderPn || data.remoteJidAlt)) || '';
  return String(alt).includes('@') ? String(alt) : (alt ? `${alt}@s.whatsapp.net` : jid);
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
  const ctx = botContext.getStore() || {};
  botLog({ kind: 'envio', instance: instanceName, to: maskPhone(formatPhoneNumber(number)), origin: ctx.origin || 'sistema', documento: String(fileName || '').slice(0, 60) });
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

const { AsyncLocalStorage } = require('async_hooks');
// Contexto de cada mensaje entrante: así cada respuesta del bot queda ligada al mensaje que la originó en el registro
const botContext = new AsyncLocalStorage();

/**
 * Envía un mensaje de texto por WhatsApp con formateo de número automático.
 * meta.origin dice quién lo manda (alerta, confirmación al comprador…); las respuestas del bot se marcan solas.
 * Cada envío queda en el registro (destino enmascarado y primeras palabras), sin guardar nada más.
 */
async function sendTextMessage(instanceName, number, text, meta = {}) {
  const targetNumber = formatPhoneNumber(number);
  const ctx = botContext.getStore() || {};
  let res;
  try {
    res = await evoRequest(`/message/sendText/${instanceName}`, {
      method: 'POST',
      body: JSON.stringify({
        number: targetNumber,
        text: text
      })
    });
  } catch (err) {
    botLog({ kind: 'envio', instance: instanceName, to: maskPhone(targetNumber), origin: meta.origin || ctx.origin || 'sistema', ok: false, error: String(err.message || err).slice(0, 120) });
    throw err;
  }
  botLog({
    kind: 'envio', instance: instanceName, to: maskPhone(targetNumber),
    origin: meta.origin || ctx.origin || 'sistema',
    enRespuestaA: ctx.msgId || undefined, edadMensajeMin: ctx.ageMin,
    chars: String(text || '').length, texto: String(text || '').replace(/\s+/g, ' ').slice(0, 90),
    ok: !!(res && res.ok), status: res && res.status
  });
  return res;
}

function maskPhone(n) {
  const d = String(n || '').replace(/\D/g, '');
  return d ? `***${d.slice(-4)}` : '';
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

function ticketInAdvisorRanges(ticket, advisor, raffle) {
  // Los rangos de números solo aplican en rifas independientes
  if (raffle && !raffle.isIndependentBook) return true;
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
  // Sin rifa independiente no se asigna asesor por rango de números
  if (!raffle || !raffle.isIndependentBook) return null;
  const advisors = (db.advisors || []).filter(a => 
    (!companyId || a.companyId === companyId) && 
    a.status === 'ACTIVO' && 
    a.mode === 'ASSIGNED' && 
    Array.isArray(a.assignedTicketRanges) && 
    a.assignedTicketRanges.length > 0
  );
  for (const adv of advisors) {
    if (ticketInAdvisorRanges(ticket, adv, raffle)) {
      return adv;
    }
  }
  return null;
}

function buildMainMenuMessage(companyName, advisor = null) {
  let msg = `¡Hola! 👋 Te escribe el equipo de *${companyName}*.\n\n`;
  if (advisor) {
    msg = `¡Hola! 👋 Soy *${advisor.name}*, asesor de *${companyName}*.\n\n`;
  }
  msg += `¿En qué te puedo ayudar?\n\n`;
  msg += `1️⃣ Ver la rifa: números disponibles, premios y cómo pagar\n`;
  msg += `2️⃣ Hablar con una persona del equipo\n\n`;
  msg += `Respóndeme con *1* o *2*, o cuéntame directamente qué necesitas 😊`;
  return msg;
}

function buildAdvisorHandOffMessage(companyName, advisor = null) {
  let msg = `Listo, ya avisé a nuestro equipo 🙌\n\n`;
  if (advisor) {
    msg += `*${advisor.name}* te va a escribir por este mismo chat en un momento.\n\n`;
  } else {
    msg += `Una persona de *${companyName}* te escribe por aquí en un momento.\n\n`;
  }
  msg += `Mientras tanto dejo de responder automáticamente para que puedan hablar con calma. Si quieres volver conmigo, escribe *MENU*.`;
  return msg;
}

function buildRaffleMessage(mainRaffle, companyName, digits, opportunities, ticketPrice, drawDateFormatted, lotteryName) {
  let msg = `Te cuento sobre la rifa 🎟️\n\n`;
  msg += `🎯 *${mainRaffle.title}*\n`;
  if (mainRaffle.description) msg += `🏆 *Premio Mayor:* ${mainRaffle.description}\n`;
  msg += `🔢 *Modalidad:* ${digits} cifras (${opportunities} oportunidades por boleta)\n`;
  msg += `📅 *Juega el:* ${drawDateFormatted} con ${lotteryName}\n`;
  msg += `💵 *Valor Boleta:* $${ticketPrice.toLocaleString('es-CO')} COP\n`;
  if (mainRaffle.minAbono) msg += `💰 *Abono Mínimo:* $${Number(mainRaffle.minAbono).toLocaleString('es-CO')} COP\n`;
  msg += `\n¿Qué quieres hacer?\n`;
  msg += `• Escríbeme el número que te gusta (de *${digits} cifras*, por ejemplo ${'1234567890'.slice(0, digits)}) y te digo si está libre.\n`;
  msg += `• Escribe *DISPONIBLES* y te muestro varios números libres.\n`;
  msg += `• *PREMIOS* para ver qué se gana, *CUENTAS* para saber dónde pagar.\n`;
  msg += `• Si ya pagaste, mándame la *foto del comprobante*.\n`;
  msg += `• *MENU* para volver al inicio.`;
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
const ADVISOR_REF_QUESTION = '🤝 Por cierto, ¿te atendió o te recomendó alguno de nuestros asesores?\nEscríbeme su nombre (aunque sea solo el primero) y lo busco. Si no te acuerdas, dime *no me acuerdo* y te ayudo. Si compraste directamente, escribe *NINGUNO*.';
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
async function handleWebhookEventInner(body, db, saveDBCallback) {
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

  const rawSender = senderJidOf(key, body.data).split('@')[0].split(':')[0];
  const senderPhone = formatPhoneNumber(rawSender);

  // Documentos (Excel devuelto de AGIL): los atiende quien se registró con setDocumentHandler
  const docMsg = msgData.documentMessage || msgData.documentWithCaptionMessage?.message?.documentMessage;
  if (docMsg && documentHandler) {
    const isSheetMime = /spreadsheetml|ms-excel/i.test(docMsg.mimetype || '');
    let fileName = docMsg.fileName || docMsg.title || '';
    // Algunos teléfonos envían el archivo sin nombre o sin extensión: si el tipo es de hoja de cálculo se trata como .xlsx
    if (isSheetMime && !/\.xlsx?$/i.test(fileName)) fileName = `${fileName || 'archivo'}.xlsx`;
    const isSheet = /\.xlsx?$/i.test(fileName);
    let base64 = msgData.base64 || body.data?.message?.base64 || body.data?.base64 || docMsg.base64 || null;
    // Evolution puede tardar en tener listo el archivo: se reintenta la descarga antes de rendirse
    for (let attempt = 0; !base64 && isSheet && attempt < 3; attempt++) {
      if (attempt > 0) await new Promise(r => setTimeout(r, 1500 * attempt));
      base64 = await fetchMediaBase64(instance, key);
    }
    const handled = await documentHandler({ instance, senderPhone, fileName, base64, mimetype: docMsg.mimetype });
    if (handled && handled.handled) return { handled: true, document: true };
    return { ignored: true, note: (handled && handled.reason) || (isSheet ? 'excel-no-atendido' : 'documento-no-es-excel') };
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
    // El WhatsApp que el asesor vincula es el suyo, personal: solo se usa para enviar avisos a sus clientes. El bot no contesta ahí
    // (salvo que el administrador haya habilitado el bot para ese asesor)
    if (!advisor || advisor.whatsappBot !== true) return { ignored: true, advisorLine: true };
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

  // Respuestas automáticas de ventas en pausa (la conexión de WhatsApp sigue abierta para los demás procesos)
  if (company && company.botSalesEnabled === false) return { ignored: true, paused: true };

  // 0. Si el chat está actualmente en atención manual por un asesor humano:
  if (session?.humanAssisted) {
    const isHumanResetCommand = cleanLower === 'menu' || cleanLower === 'menú' || cleanLower === 'bot' || 
                                cleanLower === 'reiniciar' || cleanLower === 'volver' || 
                                cleanLower === '1' || cleanLower === '2' || cleanLower === '3';
    const hoursSinceAssisted = (Date.now() - (session.humanAssistedAt || 0)) / (1000 * 60 * 60);

    // El chat pasó a un humano, pero si en 30 minutos nadie lo tomó (sigue PENDIENTE) y el cliente hace un pedido claro
    // (foto de comprobante, un número o una consulta conocida), el bot vuelve a atenderlo en lugar de dejarlo sin respuesta
    const pendingHand = (db.botHandoffs || []).find(h => h.companyId === (company ? company.id : null) && h.phone === senderPhone && h.status === 'PENDIENTE');
    const unattendedMin = pendingHand ? (Date.now() - (Date.parse(pendingHand.at) || Date.now())) / 60000 : 0;
    const handNorm = botBrain.normalize(userText);
    const clearIntent = hasImage || /^\d{3,}$/.test(handNorm) || hasPhrase(handNorm, ALL_INTENT_PHRASES);
    const wakeOnIntent = clearIntent && (!pendingHand || unattendedMin >= 30);
    if (!isHumanResetCommand && !wakeOnIntent && hoursSinceAssisted < cfg.handoff.resumeHours) {
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

  // Audios, stickers, videos, ubicaciones, contactos y reacciones: no son un "mensaje no entendido" ni cuentan para pasar a un humano
  if (!userText && !hasImage) {
    const kinds = Object.keys(msgData);
    const unreadable = ['audioMessage', 'pttMessage', 'stickerMessage', 'videoMessage', 'ptvMessage', 'contactMessage', 'contactsArrayMessage', 'locationMessage', 'documentMessage', 'documentWithCaptionMessage'];
    if (!kinds.some(k => unreadable.includes(k))) return { ignored: true }; // reacciones, avisos internos de WhatsApp, etc.
    const last = (session && session.lastMediaNoticeAt) || 0;
    if (Date.now() - last > 30 * 60 * 1000) {
      updateSession(senderPhone, { lastMediaNoticeAt: Date.now() }, db, saveDBCallback, null);
      await sendTextMessage(instance, senderPhone, 'Por aquí solo alcanzo a leer mensajes escritos y fotos de comprobantes 🙏 Cuéntame en un mensaje de texto qué necesitas, o escribe *ASESOR* si prefieres hablar con una persona.');
    }
    return { handled: true };
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
      await startHandoff({ instance, senderPhone, company, advisor, cfg, db, saveDBCallback, raffleId: mainRaffle?.id, reason: 'NO_ENTENDIDO', lastText: userText, intro: 'Disculpa, no logré entenderte 😅 Mejor te paso con una persona del equipo.' });
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
    const pendingFresh = Date.now() - (sess.pendingAt || 0) < 2 * 3600 * 1000; // lo anotado por texto vale 2 horas
    const mine = myTickets(db, mainRaffle.id, senderPhone);
    let hint = '';
    for (const run of (text.match(/\d{3,}/g) || [])) {
      const candidate = run.length < digits ? run.padStart(digits, '0') : run;
      if (mine.some(t => (t.numbers || []).includes(candidate))) { hint = candidate; break; }
    }
    if (!receiptMedia.base64) {
      // El webhook no trajo la imagen: se pide a Evolution. Sin imagen no se registra ningún pago.
      receiptMedia.base64 = await fetchMediaBase64(instance, key).catch(() => null);
      if (!receiptMedia.base64) console.log(`ℹ️ [WhatsApp Bot] Comprobante de ${senderPhone} sin imagen en base64 (revisar webhook de Evolution).`);
    }
    await startReceiptFlow(flowCtx, {
      amount: detectAmount(text) || (pendingFresh ? sess.pendingAmount : null) || null,
      approval: infoText.approvalNumber || (pendingFresh ? sess.pendingApproval : '') || '',
      bank: infoText.bank || (pendingFresh ? sess.pendingBank : '') || '',
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
    const normText = botBrain.normalize(userText);
    if (DIRECT_WORDS.includes(normText) || hasPhrase(normText, ['compre directo', 'ningun asesor', 'sin asesor', 'no fue ningun asesor'])) {
      await markDirectPurchase(flowCtx, targetTkt);
      return { handled: true };
    }
    if (hasPhrase(normText, FORGOT_PHRASES)) {
      await sendTextMessage(instance, senderPhone, 'No te preocupes 😊 Dime el nombre del asesor, aunque sea solo el primer nombre o una parte, y te muestro los que coinciden para que elijas.\n\nSi no lo recuerdas del todo, escribe *NINGUNO* y la dejo como compra directa.');
      return { handled: true };
    }
    const matches = findAdvisorMatches(db, mainRaffle.companyId || (company && company.id), userText);
    if (matches.length) {
      await offerAdvisorChoices(flowCtx, targetTkt, matches);
      return { handled: true };
    }
    // Parece un nombre pero no coincide con nadie (y no es otra consulta): se avisa en vez de quedarse callado
    const looksLikeName = /^[a-zñ ]{3,40}$/.test(normText) && normText.split(' ').length <= 4 && !botBrain.isGreeting(userText)
      && !hasPhrase(normText, ALL_INTENT_PHRASES) && !botBrain.matchFaq(cfg, userText) && !botBrain.isHandoffRequest(cfg, userText)
      && !['menu', 'inicio', 'volver', 'bot', 'ayuda', 'rifa', 'rifas', 'asesor'].includes(normText);
    if (looksLikeName) {
      await sendTextMessage(instance, senderPhone, 'No encontré a ningún asesor con ese nombre 🤔 Pruébame con otro nombre o apellido, o escribe *NINGUNO* si compraste directamente.');
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
        pendingBank: extractTransferInfo(userText).bank || undefined,
        pendingAt: Date.now()
      }, db, saveDBCallback, mainRaffle.id);
      await sendTextMessage(instance, senderPhone,
        `Gracias, anoté${reportedAmount ? ` el valor de *${money(reportedAmount)}*` : ''}${reportedApproval ? ` y el comprobante *#${reportedApproval}*` : ''} 📝\n\nPero todavía *no he registrado el pago*: para hacerlo necesito que me mandes la *foto o captura del comprobante*. Cuando me llegue, te pregunto a qué boleta corresponde y te pido que me confirmes antes de guardarlo.`);
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
      targetTicket.saleChannel = botSaleChannel(db);
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
      const askAdvisorRef = false; // el bot ya no pregunta por el asesor: la venta queda directa con el administrador
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
  const normMsg = botBrain.normalize(userText);
  if (['1', 'rifa', 'rifas', 'sorteo', 'sorteos', 'boleta', 'boletas'].includes(normMsg) || hasPhrase(normMsg, ['comprar boleta', 'comprar una boleta', 'comprar boletas'])) {
    
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
  if (hasPhrase(normMsg, PAY_PHRASES)) {
    
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
  if (hasPhrase(normMsg, PRIZE_PHRASES)) {
    let prizeMsg = `🏆 *PLAN DE PREMIOS - ${mainRaffle.title}* 🎁\n\n`;
    prizeMsg += `🌟 *Premio Mayor:*\n${mainRaffle.description || 'Gran Premio Oficial del Sorteo'}\n\n`;
    
    const winners = (db.winners || []).filter(w => w.raffleId === mainRaffle.id);
    if (mainRaffle.weeklyPrizes && mainRaffle.weeklyPrizes.length > 0) {
      prizeMsg += `🎁 *Sorteos Semanales / Anticipados:*\n`;
      // Del más antiguo al más reciente
      [...mainRaffle.weeklyPrizes].sort(byDrawDate).forEach(p => {
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
  if (hasPhrase(normMsg, DATE_PHRASES)) {
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
  if (hasPhrase(normMsg, RULE_PHRASES)) {
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
  if (hasPhrase(normMsg, AVAIL_PHRASES)) {
    const availableTickets = (db.tickets || []).filter(t => t.raffleId === mainRaffle.id && t.status === 'DISPONIBLE');
    if (availableTickets.length === 0) {
      await sendTextMessage(instance, senderPhone, `😕 Se agotaron las boletas de esta rifa, ya no quedan números disponibles.`);
      return { handled: true };
    }
    // 50 boletas al azar, mostradas en orden de menor a mayor; cada boleta con sus números juntos (van en pareja o más)
    const sample = [...availableTickets].sort(() => 0.5 - Math.random()).slice(0, 50)
      .sort((x, y) => String((x.numbers || [])[0] || '').localeCompare(String((y.numbers || [])[0] || '')));
    const perTicket = (opportunities > 1) ? `cada boleta incluye *${opportunities} números*` : 'un número por boleta';
    let dispMsg = `Estos son algunos números libres de *${mainRaffle.title}* 🎟️\n(${perTicket}; con cualquiera de los números de la boleta la aparto completa)\n\n`;
    sample.forEach(t => { dispMsg += `▫️ ${(t.numbers || []).join('  •  ')}\n`; });
    dispMsg += `\nValor: ${money(ticketPrice)} COP cada boleta.\n`;
    dispMsg += `\n✍️ Escríbeme el número que quieres (de ${digits} cifras, por ejemplo *${sample[0].numbers[0]}*) y te lo aparto. Si no ves el que buscas, escríbelo igual y te digo si está libre; o escribe *DISPONIBLES* para ver otros.`;
    await sendTextMessage(instance, senderPhone, dispMsg);
    return { handled: true };
  }

  // 8. CONSULTA DE NÚMERO: cada número debe tener las cifras que juega la rifa; el cliente puede mandar uno o varios
  const numberQuery = parseNumberQuery(userText, digits);
  if (numberQuery) {
    const tickets = (db.tickets || []).filter(t => t.raffleId === mainRaffle.id);
    const example = '1234567890'.slice(0, digits);
    const lines = [];
    const freeTickets = [];
    const seenTickets = new Set();
    let singleReply = null;
    for (const q of numberQuery) {
      if (q.tooLong) {
        lines.push(`❌ *${q.raw}* trae ${q.raw.length} cifras y esta rifa se juega con *${digits}*. Escríbelo con ${digits} cifras (por ejemplo ${example}).`);
        continue;
      }
      const t = tickets.find(x => Array.isArray(x.numbers) && x.numbers.includes(q.n));
      if (!t) { lines.push(`❔ El *${q.n}* no está en las oportunidades de este sorteo.`); continue; }
      if (seenTickets.has(t.id)) { lines.push(`ℹ️ El *${q.n}* es de la misma boleta que ya te mencioné (${numbersOf(t)}).`); continue; }
      seenTickets.add(t.id);
      if (t.status === 'DISPONIBLE') { freeTickets.push({ t, n: q.n }); lines.push(`✅ El *${q.n}* está libre (boleta ${numbersOf(t)}).`); continue; }
      if (t.buyerPhone === senderPhone) {
        const left = balanceOf(t, ticketPrice);
        lines.push(`ℹ️ El *${q.n}* ya es tuyo: boleta ${numbersOf(t)}, ${STATUS_LABEL[t.status] || t.status}${left > 0 ? `, saldo pendiente ${money(left)}` : ''}.`);
        continue;
      }
      const statusText = (t.status === 'PAGADA' || t.status === 'CONFIRMADA') ? 'vendido' : (t.status === 'ABONO_PARCIAL' ? 'con abono' : 'apartado');
      lines.push(`❌ El *${q.n}* ya no está disponible (${statusText}).`);
    }
    if (numberQuery.length === 1 && freeTickets.length === 1) {
      await offerReservation(flowCtx, freeTickets[0].t, freeTickets[0].n);
      return { handled: true };
    }
    let reply = lines.join('\n');
    if (!freeTickets.length) {
      const alts = tickets.filter(t => t.status === 'DISPONIBLE').slice(0, 3);
      if (alts.length) reply += `\n\nSi quieres, te sugiero estos que sí están libres:\n${alts.map(a => `▫️ ${a.numbers.join('  •  ')}`).join('\n')}\n\nEscríbeme el que prefieras o escribe *DISPONIBLES* para ver más.`;
      await sendTextMessage(instance, senderPhone, reply);
      return { handled: true };
    }
    if (freeTickets.length > 1) reply += `\n\nNada queda apartado hasta que tú me confirmes. Te voy preguntando de a una boleta: empecemos con la del *${freeTickets[0].n}*; después seguimos con ${freeTickets.slice(1).map(f => `*${f.n}*`).join(', ')}.`;
    await sendTextMessage(instance, senderPhone, reply);
    await offerReservation(flowCtx, freeTickets[0].t, freeTickets[0].n);
    return { handled: true };
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

/** true si alguna de las frases aparece como palabra(s) completas (no dentro de otra palabra: "mayor" no está en "mayoría"). */
const hasPhrase = (norm, list) => { const padded = ` ${norm} `; return list.some(w => padded.includes(` ${w} `)); };
const PAY_PHRASES = ['cuenta', 'cuentas', 'banco', 'bancos', 'nequi', 'bancolombia', 'daviplata', 'transferencia', 'transferencias', 'pago', 'pagos', 'donde pago', 'como pago', 'como puedo pagar', 'medios de pago', 'formas de pago', 'metodos de pago', 'a donde consigno', 'donde consigno'];
const PRIZE_PHRASES = ['premio', 'premios', 'que se gana', 'que gano', 'cuanto gano', 'cuanto se gana', 'que gana', 'acumulado', 'acumulados', 'plan de premios'];
const DATE_PHRASES = ['fecha', 'cuando juega', 'cuando se juega', 'que dia juega', 'loteria', 'con que juega', 'con cual loteria'];
const RULE_PHRASES = ['politica', 'politicas', 'regla', 'reglas', 'termino', 'terminos', 'condicion', 'condiciones', 'como funciona'];
const AVAIL_PHRASES = ['disponible', 'disponibles', 'libre', 'libres', 'que numeros hay', 'muestrame', 'azar', 'que queda', 'numeros'];
const ALL_INTENT_PHRASES = [...PAY_PHRASES, ...PRIZE_PHRASES, ...DATE_PHRASES, ...RULE_PHRASES, ...AVAIL_PHRASES];

// ---- Número escrito por el cliente: solo cuenta como consulta de boleta si el mensaje es básicamente números
const NUMBER_FILLERS = new Set(['quiero', 'quisiera', 'me', 'mi', 'el', 'la', 'los', 'las', 'un', 'una', 'numero', 'numeros', 'boleta', 'boletas', 'apartar', 'apartame', 'aparta', 'apartalo', 'dame', 'deme', 'separame', 'separa', 'comprar', 'compro', 'y', 'e', 'o', 'con', 'para', 'por', 'favor', 'porfa', 'tienes', 'tiene', 'esta', 'disponible', 'libre', 'hay', 'que', 'si', 'tambien', 'ademas', 'cual', 'es', 'del', 'de', 'al', 'ese', 'este', 'estos', 'esos', 'mas', 'otro', 'otros', 'seria', 'gustaria', 'jugar', 'juego', 'quedo', 'queda']);
/**
 * Cifras que pide la rifa (digits): cada número debe tener exactamente esa cantidad. Con menos se completa con ceros a la
 * izquierda (345 → 0345); con más se rechaza sin cortar nada. Devuelve null si el mensaje no es una consulta de número
 * (cédula, celular, valores, horas, frases largas), para que no se confunda con otra cosa.
 */
function parseNumberQuery(userText, digits) {
  const norm = botBrain.normalize(userText);
  const runs = norm.match(/\d+/g) || [];
  if (!runs.length) return null;
  if (runs.some(r => r.length >= 7)) return null;
  if (/\b(cedula|nit|telefono|celular|cc|pesos|valor|abono|abone|transfer\w*|consign\w*|hora|horas|correo|email)\b/.test(norm) || /\ba las\b/.test(norm)) return null;
  const unknown = norm.replace(/\d+/g, ' ').split(' ').filter(w => w && !NUMBER_FILLERS.has(w));
  if (unknown.length > 1) return null;
  const seen = new Set();
  const out = [];
  for (const raw of runs) {
    if (seen.has(raw)) continue;
    seen.add(raw);
    if (raw.length > digits) out.push({ raw, tooLong: true });
    else out.push({ raw, n: raw.length < digits ? raw.padStart(digits, '0') : raw, padded: raw.length < digits });
  }
  return out.slice(0, 8);
}

// ---- Asesor que lo atendió: se busca por nombre/código dentro de la MISMA empresa de la rifa
const ADVISOR_STOP = new Set(['de', 'del', 'la', 'el', 'los', 'las', 'asesor', 'asesora', 'con', 'fue', 'me', 'atendio', 'vendio', 'que', 'se', 'llama', 'llamaba', 'creo', 'era', 'un', 'una', 'senor', 'senora', 'don', 'dona', 'nombre', 'es', 'mi', 'y', 'no', 'recuerdo', 'acuerdo', 'compre', 'con', 'por', 'fue']);
const FORGOT_PHRASES = ['no me acuerdo', 'no recuerdo', 'no lo recuerdo', 'no se', 'no se como se llama', 'no me acuerdo como se llama', 'olvide', 'se me olvido', 'ni idea', 'no sabria', 'no tengo el nombre'];
const DIRECT_WORDS = ['ninguno', 'ninguna', 'nadie', 'directo', 'directa', 'no', 'sin asesor'];
function findAdvisorMatches(db, companyId, text) {
  if (!companyId) return [];
  const tokens = botBrain.normalize(text).split(' ').filter(w => w.length >= 3 && !ADVISOR_STOP.has(w));
  if (!tokens.length) return [];
  const scored = (db.advisors || [])
    .filter(a => a.companyId === companyId && (a.status || 'ACTIVO') === 'ACTIVO')
    .map(a => {
      const nameTokens = botBrain.normalize(a.name).split(' ').filter(Boolean);
      const code = botBrain.normalize(a.code);
      let score = 0;
      for (const t of tokens) {
        if (code && code === t) score += 100;
        if (nameTokens.includes(t)) score += 3;
        else if (nameTokens.some(n => n.startsWith(t))) score += 2;
        else if (t.length >= 4 && nameTokens.some(n => n.includes(t))) score += 1;
      }
      return { a, score };
    })
    .filter(x => x.score > 0)
    .sort((x, y) => y.score - x.score || String(x.a.name).localeCompare(String(y.a.name)));
  return scored.slice(0, 6).map(x => x.a);
}

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
    saleChannel: botSaleChannel(db),
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
  const askAdvisorRef = false; // el bot ya no pregunta por el asesor: la venta queda directa con el administrador
  const askHowHeard = missing.length === 0 && !askAdvisorRef && cfg.howHeard.enabled && !ticket.howHeard && !session?.howHeard;

  let msg = `${changed ? '🔄 ¡Listo, cambié tu boleta!' : '✅ ¡Listo, ya te aparté la boleta!'} 🎟️\n\n`;
  msg += `🔢 *Tus números:* ${numbersOf(ticket)}\n`;
  msg += `💵 *Valor:* ${money(priceOf(ticket, ticketPrice))} COP\n`;
  msg += `🎯 *Sorteo:* ${mainRaffle.title}${drawDateFormatted ? ` el ${drawDateFormatted}` : ''}\n`;
  if (ticket.advisorName && ticket.advisorName !== 'Venta WhatsApp') msg += `👤 *Asesor:* ${ticket.advisorName}\n`;

  if (missing.length === 0) {
    msg += `\n📋 *Datos que tenemos de ti:*\n${profileLines(profile).join('\n')}\n`;
    msg += `\nSi algún dato cambió, envíanos el dato corregido. Si todo está bien, no necesitas hacer nada más.`;
  } else {
    if (profileLines(profile).length) msg += `\n✅ *Datos ya registrados:*\n${profileLines(profile).join('\n')}\n`;
    msg += `\n📋 Para tu soporte de compra me faltan estos datos:\n${missing.map((m, i) => `${i + 1}️⃣ *${m}*`).join('\n')}\n`;
    msg += `\nPuedes mandármelos todos en un solo mensaje 😊`;
  }
  msg += `\n\n💳 Para pagar, escribe *PAGOS* y te muestro las cuentas. Cuando pagues, mándame la *foto del comprobante* y la asocio a tu boleta.`;
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
/** La rifa ya no vende boletas nuevas: cerrada, inactiva o con la fecha del sorteo final ya pasada (Colombia). */
function salesClosedMessage(raffle) {
  if (!raffle) return null;
  const day = String(raffle.mainDrawDate || '').slice(0, 10);
  const today = new Date(Date.now() - 5 * 3600 * 1000).toISOString().slice(0, 10);
  if (raffle.scheduledDeletionAt || raffle.status === 'INACTIVA' || (/^\d{4}-\d{2}-\d{2}$/.test(day) && day < today)) {
    return `🚫 Las ventas de *${raffle.title}* ya están cerradas: no se pueden apartar más números.\n\nSi ya tienes una boleta, escribe tu número para consultarla o *ASESOR* para hablar con una persona.`;
  }
  return null;
}

/** Medio de venta que el bot registra: el canal "WhatsApp" de la lista maestra (así aparece seleccionado en la boleta). */
function botSaleChannel(db) {
  const list = (db && db.saleChannels) || [];
  const ch = list.find(c => c.active && /whatsapp/i.test(c.name));
  return ch ? ch.name : 'WhatsApp';
}

async function offerReservation(ctx, ticket, number) {
  const { instance, senderPhone, db, saveDBCallback, mainRaffle, ticketPrice, lotteryName, drawDateFormatted } = ctx;
  const closedMsg = salesClosedMessage(mainRaffle);
  if (closedMsg) { await sendTextMessage(instance, senderPhone, closedMsg); return; }
  const mine = myTickets(db, mainRaffle.id, senderPhone);
  const others = ticket.numbers.filter(n => n !== number);
  const assignedAdv = getAssignedAdvisorForTicket(ticket, mainRaffle, db) || ctx.advisor;

  let head = `¡Buena elección! El *${number}* está libre 🎉\n\n`;
  head += `🔢 *Juegas con:* *${number}*${others.length ? ` y también con *${others.join(', ')}*` : ''}\n`;
  head += `💵 *Valor Boleta:* ${money(ticketPrice)} COP\n`;
  if (mainRaffle.minAbono) head += `💰 *Abono Mínimo:* ${money(mainRaffle.minAbono)} COP\n`;
  head += `🎯 *Sorteo:* ${mainRaffle.title}\n🏆 *Juega con:* ${lotteryName} el ${drawDateFormatted}`;
  if (assignedAdv) head += `\n👤 *Asesor asignado:* *${assignedAdv.name}*`;

  if (mine.length === 0) {
    setPending(senderPhone, { type: 'RESERVE', ticketId: ticket.id, number }, db, saveDBCallback, mainRaffle.id);
    await sendTextMessage(instance, senderPhone, `${head}\n\n¿La aparto a tu nombre? Respóndeme *SÍ* y la aparto, o *NO* si prefieres dejarlo así.`);
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
  const closedReservationMsg = salesClosedMessage(mainRaffle);
  if (closedReservationMsg) {
    setPending(senderPhone, null, db, saveDBCallback, mainRaffle.id);
    await sendTextMessage(instance, senderPhone, closedReservationMsg);
    return;
  }
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

/**
 * Cuánto de una transferencia (número de aprobación) ya se aplicó y cuánto queda, según el valor total que muestra el
 * comprobante (el leído ahora o el guardado en un pago anterior). Es la misma regla de la web: una transferencia puede
 * pagar varias boletas mientras la suma no pase de su valor total.
 */
function approvalAvailability(db, approval, proofTotal) {
  const key = approvalKeyOf(approval);
  if (!key) return { known: false, count: 0, registered: 0, total: 0, remaining: 0, ticketIds: [] };
  let registered = 0, stored = 0, count = 0;
  const ticketIds = [];
  for (const t of db.tickets || []) {
    for (const a of t.abonos || []) {
      if (approvalKeyOf(a.approvalNumber) !== key || !(Number(a.amount) > 0)) continue;
      registered += Number(a.amount);
      stored = Math.max(stored, Number(a.proofTotal) || 0);
      count++;
      ticketIds.push(t.id);
    }
  }
  const total = Number(proofTotal) > 0 ? Number(proofTotal) : stored;
  return { known: total > 0, count, registered, total, remaining: total > 0 ? Math.round(total - registered) : 0, ticketIds };
}

/**
 * Entiende "1 50000, 2 30000": cada pedazo es el número de la lista (o una oportunidad de la boleta) y el valor.
 * "1 todo" aplica el saldo completo. Devuelve { allocs, error }.
 */
function parseSplitReply(text, candidates, ticketPrice) {
  const allocs = [];
  const used = new Set();
  const chunks = String(text || '').split(/[,;\n]+/).map(c => c.trim()).filter(Boolean);
  if (!chunks.length) return { error: 'No entendí el reparto.' };
  for (const chunk of chunks) {
    const nums = chunk.match(/\d[\d.]*/g) || [];
    const wantsAll = /\b(todo|todos|saldo|total|completo)\b/i.test(chunk);
    if (!nums.length || (nums.length < 2 && !wantsAll)) return { error: `No entendí "${chunk}". Escribe el número de la lista y el valor, por ejemplo *1 50000*.` };
    const ref = nums[0].replace(/\./g, '');
    let ticket = null;
    if (ref.length <= 2) ticket = candidates[parseInt(ref, 10) - 1] || null;
    else ticket = candidates.find(t => (t.numbers || []).some(n => n === ref || n === ref.padStart(String(n).length, '0'))) || null;
    if (!ticket) return { error: `No encontré la boleta "${nums[0]}" entre tus boletas con saldo.` };
    if (used.has(ticket.id)) return { error: `La boleta ${numbersOf(ticket)} aparece dos veces: júntalas en un solo valor.` };
    used.add(ticket.id);
    const amount = (wantsAll && nums.length < 2) ? balanceOf(ticket, ticketPrice) : parseInt(nums[nums.length - 1].replace(/\./g, ''), 10);
    if (!(amount > 0)) return { error: `El valor de la boleta ${numbersOf(ticket)} no es válido.` };
    allocs.push({ ticketId: ticket.id, amount });
  }
  return { allocs };
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

/** Pregunta cuál de los asesores que coinciden es el correcto (siempre con la opción de "ninguno de estos" y "compra directa"). */
async function offerAdvisorChoices(ctx, ticket, advisors) {
  const { instance, senderPhone, db, saveDBCallback, mainRaffle } = ctx;
  let msg = advisors.length === 1 ? 'Encontré a este asesor, ¿es él/ella?\n\n' : 'Encontré estos asesores, ¿cuál es?\n\n';
  advisors.forEach((a, i) => { msg += `${i + 1}️⃣ ${a.name}\n`; });
  msg += `${advisors.length + 1}️⃣ Ninguno de estos (busco otro nombre)\n`;
  msg += `${advisors.length + 2}️⃣ Compré directo, sin asesor\n\n`;
  msg += 'Responde con el número de la opción.';
  setPending(senderPhone, { type: 'ADVISOR_PICK', ticketId: ticket.id, advisorIds: advisors.map(a => a.id) }, db, saveDBCallback, mainRaffle.id);
  await sendTextMessage(instance, senderPhone, msg);
}

/** Pregunta (una sola vez) por qué medio se enteró, si aplica, después de resolver el asesor. */
function advisorFollowUp(ctx, ticket) {
  const { senderPhone, db, saveDBCallback, mainRaffle, cfg } = ctx;
  const sess = getSession(senderPhone, db);
  if (cfg.howHeard.enabled && !ticket.howHeard && !(sess && sess.howHeard)) {
    updateSession(senderPhone, { awaitingAdvisorRef: false, awaitingHowHeard: true, awaitingHowHeardAt: Date.now() }, db, saveDBCallback, mainRaffle.id);
    return `\n\n${buildHowHeardQuestion(cfg.howHeard.options)}`;
  }
  updateSession(senderPhone, { awaitingAdvisorRef: false }, db, saveDBCallback, mainRaffle.id);
  return '';
}

async function markDirectPurchase(ctx, ticket) {
  const { instance, senderPhone, saveDBCallback, mainRaffle } = ctx;
  setPending(senderPhone, null, ctx.db, saveDBCallback, mainRaffle.id);
  ticket.advisorId = null;
  ticket.advisorName = 'Venta Directa WhatsApp';
  if (typeof saveDBCallback === 'function') saveDBCallback(mainRaffle.id);
  await sendTextMessage(instance, senderPhone, `Perfecto 🤝 Tu boleta (${numbersOf(ticket)}) quedó registrada como *compra directa*.${advisorFollowUp(ctx, ticket)}`);
}

async function linkAdvisor(ctx, ticket, adv) {
  const { instance, senderPhone, saveDBCallback, mainRaffle } = ctx;
  // Un asesor solo pertenece a una empresa: nunca se asigna uno de otra
  if (adv.companyId !== mainRaffle.companyId) { await markDirectPurchase(ctx, ticket); return; }
  setPending(senderPhone, null, ctx.db, saveDBCallback, mainRaffle.id);
  ticket.advisorId = adv.id;
  ticket.advisorName = adv.name;
  (ticket.abonos || []).forEach(ab => { ab.sellerId = adv.id; ab.sellerName = adv.name; });
  if (typeof saveDBCallback === 'function') saveDBCallback(mainRaffle.id);
  await sendTextMessage(instance, senderPhone, `¡Genial! 🤝 Dejé tu boleta (${numbersOf(ticket)}) vinculada con *${adv.name}*.${advisorFollowUp(ctx, ticket)}`);
}

async function startReceiptFlow(ctx, info) {
  const { instance, senderPhone, db, saveDBCallback, mainRaffle, ticketPrice, session } = ctx;
  const soporte = await storeReceiptMedia(ctx, info.media);
  const mine = myTickets(db, mainRaffle.id, senderPhone);
  const payable = mine.filter(t => balanceOf(t, ticketPrice) > 0);

  // Sin la imagen del soporte no se registra nada: se pide de nuevo
  if (!soporte || !soporte.hash) {
    await sendTextMessage(instance, senderPhone, 'Me llegó el mensaje pero no pude abrir la imagen del comprobante 😕 ¿Me la mandas de nuevo como foto o captura? Mientras no la tenga, no registro el pago.');
    return;
  }

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

  // La misma transferencia no se puede registrar dos veces en la misma boleta, y solo se puede aplicar hasta su valor total
  const apKey = approvalKeyOf(plan.approval);
  if (apKey) {
    candidates = candidates.filter(t => !(t.abonos || []).some(a => approvalKeyOf(a.approvalNumber) === apKey && Number(a.amount) > 0));
    const av = approvalAvailability(db, plan.approval, plan.proofTotal);
    if (av.count > 0 && av.known) {
      if (av.remaining <= 0) {
        setPending(senderPhone, null, db, saveDBCallback, mainRaffle.id);
        await sendTextMessage(instance, senderPhone, `🚫 Este comprobante (No. ${plan.approval}) fue por *${money(av.total)}* y ya está aplicado por completo (${money(av.registered)} en ${av.count} pago${av.count === 1 ? '' : 's'}). No me queda saldo de esta transferencia para otra boleta.\n\nSi crees que es un error, escribe *ASESOR*.`);
        return;
      }
      plan = { ...plan, availNote: `Este comprobante fue por ${money(av.total)}; ya se aplicaron ${money(av.registered)} y quedan ${money(av.remaining)} por aplicar.` };
      if (plan.amount > av.remaining) {
        plan = { ...plan, amount: av.remaining, availNote: `${plan.availNote} Solo puedo aplicar ${money(av.remaining)}.` };
      }
    }
    if (candidates.length === 0) {
      setPending(senderPhone, null, db, saveDBCallback, mainRaffle.id);
      await sendTextMessage(instance, senderPhone, `🚫 Este comprobante ya está registrado en tus boletas con saldo. Si es otro pago, envíame de nuevo la foto del nuevo comprobante.`);
      return;
    }
  }
  // Si el cliente nombró el número en el mensaje, se usa esa boleta
  if (plan.hint) {
    const byHint = candidates.filter(t => (t.numbers || []).includes(plan.hint));
    if (byHint.length === 1) candidates = byHint;
  }
  // Si ninguna boleta puede recibir todo el valor, el comprobante se reparte entre varias
  const maxBalance = Math.max(...candidates.map(t => balanceOf(t, ticketPrice)));
  if (candidates.length >= 2 && plan.amount > maxBalance) {
    await receiptStartSplit(ctx, plan, candidates);
    return;
  }
  if (candidates.length === 1) {
    await receiptConfirm(ctx, candidates[0], plan);
    return;
  }
  let msg = `📸 *¡Recibí tu comprobante por ${money(plan.amount)}!*\n\n${plan.availNote ? `ℹ️ ${plan.availNote}\n\n` : ''}Tienes varias boletas con saldo. *¿A cuál corresponde este pago?* Responde con el número de la lista:\n\n`;
  candidates.forEach((t, i) => { msg += `${i + 1}️⃣ ${numbersOf(t)} — saldo ${money(balanceOf(t, ticketPrice))}\n`; });
  msg += `0️⃣ *Repartirlo entre varias boletas*\n`;
  setPending(senderPhone, { type: 'RECEIPT_WHICH', ...plan, candidateIds: candidates.map(t => t.id) }, db, saveDBCallback, mainRaffle.id);
  await sendTextMessage(instance, senderPhone, msg.trim());
}

async function receiptStartSplit(ctx, plan, candidates) {
  const { instance, senderPhone, db, saveDBCallback, mainRaffle, ticketPrice } = ctx;
  // También en el reparto se identifica la cuenta de destino (se le pregunta al cliente si el comprobante no lo deja claro)
  const accounts = mainRaffle.transferAccounts || [];
  if (accounts.length && !plan.account) {
    const foundAccounts = (plan.accountIds || []).map(id => accounts.find(a => a.id === id)).filter(Boolean);
    if (accounts.length === 1) plan = { ...plan, account: accounts[0] };
    else if (foundAccounts.length === 1) plan = { ...plan, account: foundAccounts[0] };
    else {
      const options = foundAccounts.length > 1 ? foundAccounts : accounts;
      let ask = `🏦 *¿A cuál de nuestras cuentas hiciste la transferencia?*\n\nNo logré identificarla en el comprobante. Responde con el número:\n\n`;
      options.forEach((a, i) => { ask += `${i + 1}️⃣ ${accountLabelOf(a)}\n`; });
      setPending(senderPhone, { type: 'RECEIPT_ACCOUNT', split: true, candidateIds: candidates.map(t => t.id), amount: plan.amount, availNote: plan.availNote || '', ...planCarry(plan), accountIds: options.map(a => a.id) }, db, saveDBCallback, mainRaffle.id);
      await sendTextMessage(instance, senderPhone, ask.trim());
      return;
    }
  }
  let msg = `📸 *Tu comprobante es por ${money(plan.amount)}.* Vamos a repartirlo entre tus boletas.\n\n`;
  if (plan.availNote) msg += `ℹ️ ${plan.availNote}\n\n`;
  msg += `Tus boletas con saldo:\n`;
  candidates.forEach((t, i) => { msg += `${i + 1}️⃣ ${numbersOf(t)} — saldo ${money(balanceOf(t, ticketPrice))}\n`; });
  msg += `\n✍️ Escríbeme el *número de la lista y el valor* de cada abono, separados por comas. Ejemplo: *1 50000, 2 30000*\n`;
  msg += `O escribe *AUTO* y lo reparto en orden pagando cada saldo.\n`;
  msg += `\nEl total no puede pasar de ${money(plan.amount)} ni del saldo de cada boleta.`;
  if (plan.account) msg += `\n🏦 *Cuenta destino:* ${accountLabelOf(plan.account)}`;
  setPending(senderPhone, {
    type: 'RECEIPT_SPLIT', amount: plan.amount, availNote: plan.availNote || '', ...planCarry(plan), candidateIds: candidates.map(t => t.id),
    accountId: plan.account ? plan.account.id : null, accountLabel: plan.account ? accountLabelOf(plan.account) : ''
  }, db, saveDBCallback, mainRaffle.id);
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
  const confirmKey = approvalKeyOf(plan.approval);
  if (confirmKey && (ticket.abonos || []).some(a => approvalKeyOf(a.approvalNumber) === confirmKey && Number(a.amount) > 0)) {
    setPending(senderPhone, null, db, saveDBCallback, mainRaffle.id);
    await sendTextMessage(instance, senderPhone, `🚫 Este comprobante (No. ${plan.approval}) ya está registrado en la boleta ${numbersOf(ticket)}: no se puede usar dos veces en la misma boleta. Si es otro pago, envíame la foto del nuevo comprobante.`);
    return;
  }

  let msg = `📸 *Revisemos tu comprobante antes de registrarlo*\n\n`;
  if (plan.availNote) msg += `ℹ️ ${plan.availNote}\n\n`;
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

async function receiptRegister(ctx, pending, opts = {}) {
  const { instance, senderPhone, db, saveDBCallback, mainRaffle, ticketPrice, advisor, cfg, session } = ctx;
  if (!pending.soporte || !pending.soporte.hash) {
    setPending(senderPhone, null, db, saveDBCallback, mainRaffle.id);
    await sendTextMessage(instance, senderPhone, 'Para registrar un pago necesito la foto del comprobante. Mándamela y seguimos 🙏');
    return;
  }
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
      for (const a of [...(t.abonos || []), ...(t.voidedAbonos || [])]) {
        // Los pagos hermanos del mismo reparto no cuentan como repetición
        if (approvalKeyOf(a.approvalNumber) === key && !(pending.splitId && a.splitId === pending.splitId)) sameApproval.push(a);
      }
    }
    // Una transferencia que se reparte en varias boletas es legítima mientras la suma no pase de su valor total
    const av = approvalAvailability(db, pending.approval, pending.proofTotal);
    const withinCapacity = av.known && av.remaining >= amount;
    if (sameApproval.length && !withinCapacity) flags.push({ code: 'APROBACION_REPETIDA', level: 'MEDIA', detail: `El número de aprobación ya estaba en ${sameApproval.length} pago(s).` });
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
    ...(pending.splitId ? { splitId: pending.splitId } : {}),
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
  if (opts.silent) return { ticket, amount };

  const profile = knownProfile(db, senderPhone, session);
  const missing = missingProfileFields(profile);
  const hasRealAdvisor = !!ticket.advisorId && ticket.advisorName !== 'Venta WhatsApp';
  const askAdvisorRef = false; // el bot ya no pregunta por el asesor: la venta queda directa con el administrador

  let msg = `✅ *¡Pago registrado!* 📸\n\n`;
  msg += `🎟️ *Boleta:* ${numbersOf(ticket)}\n💸 *Comprobante:* ${money(amount)}\n`;
  msg += ticket.balancePending > 0 ? `⏳ *Saldo pendiente:* ${money(ticket.balancePending)}\n` : `🎉 *Tu boleta queda totalmente pagada* (sujeta a validación del banco).\n`;
  msg += `\nNuestro equipo validará la transferencia en la cuenta bancaria y te avisaremos por este chat.\n`;
  const participation = participationText(mainRaffle, ticket.totalPaid);
  if (participation) msg += `\n${participation}\n`;
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
    if (pending.split) {
      const splitCands = (pending.candidateIds || []).map(id => (db.tickets || []).find(t => t.id === id)).filter(Boolean);
      await receiptStartSplit(ctx, { ...planCarry(pending), amount: pending.amount, availNote: pending.availNote, account: chosenAccount }, splitCands);
      return true;
    }
    const accTicket = (db.tickets || []).find(t => t.id === pending.ticketId);
    if (!accTicket) { clear(); return false; }
    await receiptConfirm(ctx, accTicket, { ...planCarry(pending), amount: pending.amount, account: chosenAccount });
    return true;
  }

  if (pending.type === 'RECEIPT_WHICH') {
    if (wantsHuman) { clear(); return false; }
    if (isNo(userText)) return cancelled();
    const candidates = (pending.candidateIds || []).map(id => (db.tickets || []).find(t => t.id === id)).filter(Boolean);
    if (norm === '0' || /\b(repart|dividi|varias|varios|todas)\b/.test(norm)) {
      await receiptStartSplit(ctx, { ...planCarry(pending), amount: pending.amount, availNote: pending.availNote }, candidates);
      return true;
    }
    let chosen = null;
    if (/^\d{1,2}$/.test(norm)) chosen = candidates[parseInt(norm, 10) - 1] || null;
    if (!chosen && /^\d{3,}$/.test(norm)) chosen = candidates.find(t => (t.numbers || []).includes(norm) || (t.numbers || []).includes(norm.padStart(digits, '0'))) || null;
    if (!chosen) return remind(`Responde con el número de la lista (1${candidates.length > 1 ? ` a ${candidates.length}` : ''}) o escribe *NO* para cancelar.`);
    await receiptConfirm(ctx, chosen, { ...planCarry(pending), amount: pending.amount, availNote: pending.availNote });
    return true;
  }

  if (pending.type === 'RECEIPT_SPLIT') {
    if (wantsHuman) { clear(); return false; }
    if (isNo(userText)) return cancelled();
    const cands = (pending.candidateIds || []).map(id => (db.tickets || []).find(t => t.id === id)).filter(Boolean);
    let allocs = [];
    let problem = '';
    if (/^(auto|automatico|automatica)$/.test(norm)) {
      let left = pending.amount;
      for (const t of cands) {
        const give = Math.min(balanceOf(t, ticketPrice), left);
        if (give > 0) { allocs.push({ ticketId: t.id, amount: give }); left -= give; }
        if (left <= 0) break;
      }
    } else {
      const parsed = parseSplitReply(userText, cands, ticketPrice);
      if (parsed.error) problem = parsed.error;
      else allocs = parsed.allocs;
    }
    if (!problem) {
      const total = allocs.reduce((sum, a) => sum + a.amount, 0);
      const over = allocs.find(a => a.amount > balanceOf(cands.find(t => t.id === a.ticketId), ticketPrice) + 0.5);
      if (over) problem = `El abono a la boleta ${numbersOf(cands.find(t => t.id === over.ticketId))} (${money(over.amount)}) pasa de su saldo (${money(balanceOf(cands.find(t => t.id === over.ticketId), ticketPrice))}).`;
      else if (total > pending.amount + 0.5) problem = `La suma (${money(total)}) pasa del valor disponible del comprobante (${money(pending.amount)}). Quedan por repartir como máximo ${money(pending.amount)}.`;
      else if (!allocs.length) problem = 'No encontré valores para repartir.';
    }
    if (problem) return remind(`${problem}\n\nEscribe por ejemplo *1 50000, 2 30000* o *AUTO*, o *NO* para cancelar.`);
    const total = allocs.reduce((sum, a) => sum + a.amount, 0);
    let msg = `📸 *Revisemos el reparto de tu comprobante (${money(pending.amount)})*\n\n`;
    for (const a of allocs) {
      const t = cands.find(x => x.id === a.ticketId);
      const left = balanceOf(t, ticketPrice) - a.amount;
      msg += `🎟️ ${numbersOf(t)} → *${money(a.amount)}* ${left > 0 ? `(quedaría con saldo ${money(left)})` : '(quedaría *pagada*)'}\n`;
    }
    msg += `\n💸 *Aplicado:* ${money(total)}${total < pending.amount ? ` • *Sin aplicar:* ${money(pending.amount - total)} (lo podrás usar en otra boleta enviándome de nuevo este comprobante)` : ''}\n`;
    msg += `\n👉 ¿Registro estos ${allocs.length} pago${allocs.length === 1 ? '' : 's'}? Responde *SÍ* o *NO*.`;
    setPending(senderPhone, { type: 'RECEIPT_SPLIT_CONFIRM', allocations: allocs, amount: pending.amount, ...planCarry(pending), accountId: pending.accountId || null, accountLabel: pending.accountLabel || '' }, db, saveDBCallback, mainRaffle.id);
    await sendTextMessage(instance, senderPhone, msg);
    return true;
  }

  if (pending.type === 'RECEIPT_SPLIT_CONFIRM') {
    if (isNo(userText)) { clear(); await sendTextMessage(instance, senderPhone, `👍 No registré nada. Si quieres repartirlo de otra forma, envíame de nuevo la foto del comprobante.`); return true; }
    if (wantsHuman) { clear(); return false; }
    if (!isYes(userText)) return remind(`Responde *SÍ* para registrar el reparto o *NO* para cancelar.`);
    const splitId = `split-${Date.now()}`;
    const done = [];
    for (const a of pending.allocations || []) {
      const res = await receiptRegister(ctx, { ...pending, type: 'RECEIPT_CONFIRM', ticketId: a.ticketId, amount: a.amount, splitId }, { silent: true });
      if (res && res.ticket) done.push({ ticket: res.ticket, amount: a.amount });
    }
    const applied = done.reduce((sum, d) => sum + d.amount, 0);
    let msg = `✅ *¡Pagos registrados!* 📸\n\n`;
    for (const d of done) {
      const left = balanceOf(d.ticket, ticketPrice);
      msg += `🎟️ ${numbersOf(d.ticket)} → ${money(d.amount)} ${left > 0 ? `(saldo pendiente ${money(left)})` : '🎉 *queda totalmente pagada* (sujeta a validación)'}\n`;
    }
    msg += `\n💸 *Comprobante:* ${money(pending.amount)} • *Aplicado:* ${money(applied)}${applied < pending.amount ? ` • *Sin aplicar:* ${money(pending.amount - applied)}` : ''}\n`;
    msg += `\nNuestro equipo validará la transferencia en la cuenta bancaria y te avisaremos por este chat.\n\n🌐 *Consulta tus boletas aquí:*\n${PUBLIC_BASE_URL}/boleta?phone=${senderPhone}\n\n¡Muchas gracias y mucha suerte! 🍀`;
    updateSession(senderPhone, { pending: null, lastRaffleId: mainRaffle.id, pendingAmount: null, pendingApproval: null, pendingBank: null }, db, saveDBCallback, mainRaffle.id);
    await sendTextMessage(instance, senderPhone, msg);
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

  if (pending.type === 'ADVISOR_PICK') {
    if (wantsHuman) { clear(); return false; }
    const ticket = (db.tickets || []).find(t => t.id === pending.ticketId);
    if (!ticket) { clear(); return false; }
    const ids = pending.advisorIds || [];
    const n = ids.length;
    if (DIRECT_WORDS.includes(norm) || hasPhrase(norm, ['compre directo', 'sin asesor'])) { await markDirectPurchase(ctx, ticket); return true; }
    if (/^\d{1,2}$/.test(norm)) {
      const pick = parseInt(norm, 10);
      if (pick >= 1 && pick <= n) {
        const adv = (db.advisors || []).find(a => a.id === ids[pick - 1]);
        if (adv) { await linkAdvisor(ctx, ticket, adv); return true; }
      }
      if (pick === n + 1) {
        clear();
        await sendTextMessage(instance, senderPhone, 'Listo, escríbeme otro nombre (o apellido) y lo busco. Si prefieres dejarla sin asesor, escribe *NINGUNO*.');
        return true;
      }
      if (pick === n + 2) { await markDirectPurchase(ctx, ticket); return true; }
      return remind(`Responde con el número de la lista (de 1 a ${n + 2}).`);
    }
    // Escribió otro nombre en vez de un número: se busca de nuevo
    const again = findAdvisorMatches(db, mainRaffle.companyId || (ctx.company && ctx.company.id), userText);
    if (again.length) { await offerAdvisorChoices(ctx, ticket, again); return true; }
    return remind(`No encontré a nadie con ese nombre 🤔 Responde con el número de la lista (de 1 a ${n + 2}) o escribe otro nombre.`);
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


// ---------------------------------------------------------------------------
// Registro permanente del bot + vigilante de conexión (para que funcione 24/7 y se pueda saber qué pasó)
// ---------------------------------------------------------------------------
const BOT_LOG_FILE = process.env.BOT_LOG_FILE || require('path').join(__dirname, 'assets', 'bot-log.jsonl');
const BOT_LOG_RETENTION_DAYS = Number(process.env.BOT_LOG_RETENTION_DAYS) || 60;
const recentBotLog = [];

/** Una línea por evento, en un archivo que sobrevive a los reinicios. No guarda el contenido de los mensajes del cliente. */
function botLog(entry) {
  const line = { at: new Date().toISOString(), ...entry };
  recentBotLog.push(line);
  if (recentBotLog.length > 300) recentBotLog.shift();
  try {
    const fs = require('fs');
    fs.mkdirSync(require('path').dirname(BOT_LOG_FILE), { recursive: true });
    fs.appendFileSync(BOT_LOG_FILE, JSON.stringify(line) + '\n');
  } catch (_) { /* el registro nunca debe tumbar al bot */ }
}

/** Conserva solo los últimos BOT_LOG_RETENTION_DAYS días del registro del bot (solo este archivo; no toca WhatsApp). */
function pruneBotLog() {
  try {
    const fs = require('fs');
    if (!fs.existsSync(BOT_LOG_FILE)) return;
    const limit = Date.now() - BOT_LOG_RETENTION_DAYS * 24 * 3600 * 1000;
    const lines = fs.readFileSync(BOT_LOG_FILE, 'utf8').split('\n').filter(Boolean);
    const keep = lines.filter(l => { try { return Date.parse(JSON.parse(l).at) >= limit; } catch (_) { return false; } });
    if (keep.length !== lines.length) {
      fs.writeFileSync(BOT_LOG_FILE + '.tmp', keep.length ? keep.join('\n') + '\n' : '');
      fs.renameSync(BOT_LOG_FILE + '.tmp', BOT_LOG_FILE);
    }
  } catch (_) { /* sin archivo todavía */ }
}
setTimeout(pruneBotLog, 20 * 1000).unref();
setInterval(pruneBotLog, 24 * 3600 * 1000).unref();

/** Consulta del registro: por instancia, tipo (mensaje|envio|conexion|reinicio), teléfono (últimos dígitos) y días hacia atrás. */
function getBotLog(instance, limit = 40, filters = {}) {
  let lines = recentBotLog;
  const wide = filters.kind || filters.phone || filters.days;
  if (wide || lines.length < 40) {
    try {
      lines = require('fs').readFileSync(BOT_LOG_FILE, 'utf8').split('\n').filter(Boolean).map(l => { try { return JSON.parse(l); } catch (_) { return null; } }).filter(Boolean);
    } catch (_) { /* sin archivo todavía */ }
  }
  const since = filters.days ? Date.now() - Number(filters.days) * 24 * 3600 * 1000 : 0;
  const tail = String(filters.phone || '').replace(/\D/g, '').slice(-4);
  return lines
    .filter(l => (!instance || l.instance === instance)
      && (!filters.kind || l.kind === filters.kind)
      && (!tail || String(l.to || l.from || '').endsWith(tail))
      && (!since || Date.parse(l.at) >= since))
    .slice(-limit).reverse();
}

const botHealth = new Map(); // instancia -> { state, since, lastOkAt, lastRestartAt, restarts: [ms] }

function getHealth(instance) {
  const h = botHealth.get(instance);
  if (!h) return null;
  const now = Date.now();
  return {
    instance,
    state: h.state,
    since: new Date(h.since).toISOString(),
    lastOkAt: h.lastOkAt ? new Date(h.lastOkAt).toISOString() : null,
    minutesInState: Math.round((now - h.since) / 60000),
    needsQr: h.state === 'close',
    restartsLast24h: (h.restarts || []).filter(t => now - t < 24 * 3600 * 1000).length
  };
}

// Mensajes más viejos que esto se descartan: el cliente ya no está esperando y una respuesta tardía confunde
const BOT_MAX_MESSAGE_AGE_MIN = Number(process.env.BOT_MAX_MESSAGE_AGE_MIN) || 30;
const seenMessageIds = new Set();

const WATCHDOG_EVERY_MS = 60 * 1000;
const WATCHDOG_STUCK_MS = 3 * 60 * 1000;      // "connecting" o similar por más de esto: se reinicia la instancia
const WATCHDOG_RESTART_GAP_MS = 10 * 60 * 1000; // y no más de una vez cada 10 minutos (cada reinicio abre un socket nuevo)

async function watchInstances() {
  const res = await evoRequest('/instance/fetchInstances');
  if (!res.ok || !Array.isArray(res.data)) return;
  const now = Date.now();
  for (const i of res.data) {
    const name = i.name || i.instanceName || (i.instance && i.instance.instanceName);
    if (!name || name === 'rifaapp_bot') continue;
    const state = i.connectionStatus || (i.instance && i.instance.status) || 'unknown';
    let h = botHealth.get(name);
    if (!h) { h = { state, since: now, lastOkAt: state === 'open' ? now : null, restarts: [] }; botHealth.set(name, h); botLog({ kind: 'conexion', instance: name, state, note: 'vigilancia iniciada' }); }
    if (h.state !== state) {
      botLog({ kind: 'conexion', instance: name, state, from: h.state, after: `${Math.round((now - h.since) / 1000)}s` });
      h.state = state;
      h.since = now;
    }
    if (state === 'open') { h.lastOkAt = now; continue; }
    // 'close' = sesión cerrada desde el teléfono: solo se vuelve a conectar escaneando el QR (no se puede automatizar)
    if (state === 'close') continue;
    if (now - h.since >= WATCHDOG_STUCK_MS && now - (h.lastRestartAt || 0) >= WATCHDOG_RESTART_GAP_MS) {
      h.lastRestartAt = now;
      h.restarts.push(now);
      h.restarts = h.restarts.filter(t => now - t < 24 * 3600 * 1000);
      const r = await evoRequest(`/instance/restart/${name}`, { method: 'PUT' });
      botLog({ kind: 'reinicio', instance: name, state, ok: r.ok, status: r.status, note: `atascada ${Math.round((now - h.since) / 60000)} min en "${state}"` });
      console.warn(`🔁 [Vigilante] Instancia ${name} atascada en "${state}": reinicio ${r.ok ? 'solicitado' : 'falló (' + r.status + ')'}.`);
    }
  }
}

let watchdogTimer = null;
function startWatchdog() {
  if (watchdogTimer) return;
  const tick = () => watchInstances().catch(err => console.warn('⚠️ [Vigilante] No se pudo revisar WhatsApp:', err.message));
  setTimeout(tick, 15000);
  watchdogTimer = setInterval(tick, WATCHDOG_EVERY_MS);
}

async function handleWebhookEvent(body, db, saveDBCallback) {
  const event = body.event || body.type;
  const instance = body.instance || body.instanceName || '';
  if (event === 'connection.update' || event === 'CONNECTION_UPDATE') {
    const st = body.data && (body.data.state || body.data.status);
    if (st) botLog({ kind: 'conexion', instance, state: st, via: 'webhook' });
    return { ignored: true };
  }
  const isMessage = event === 'messages.upsert' || event === 'MESSAGES_UPSERT';
  if (!isMessage) return { ignored: true };
  const key = (body.data && body.data.key) || {};
  const m = (body.data && body.data.message) || {};
  const from = senderJidOf(key, body.data).split('@')[0];
  const info = {
    kind: 'mensaje',
    instance,
    from: from ? `***${from.slice(-3)}` : '',
    tipo: m.imageMessage ? 'imagen' : (m.documentMessage || m.documentWithCaptionMessage ? 'documento' : (m.conversation || m.extendedTextMessage ? 'texto' : 'otro')),
    propio: !!key.fromMe,
    grupo: String(key.remoteJid || '').endsWith('@g.us')
  };
  // Edad del mensaje: si el servicio de WhatsApp lo entrega tarde (reconexión, reinicio, sincronización) no se responde
  const ts = Number((body.data && body.data.messageTimestamp && (body.data.messageTimestamp.low ?? body.data.messageTimestamp)) || 0);
  const ageMin = ts ? Math.round((Date.now() / 1000 - ts) / 60) : undefined;
  const msgId = key.id ? String(key.id).slice(0, 24) : undefined;
  info.msgId = msgId;
  info.edadMin = ageMin;
  const isClientMsg = !info.propio && !info.grupo;
  // Un Excel (el que se devuelve a AGIL con SUBIDO) se procesa aunque llegue tarde: marcar pagos como subidos no depende de la hora
  // y no es una respuesta a un cliente que esté esperando; el filtro de mensajes viejos es solo para el chat con clientes
  const isSpreadsheet = !!(m.documentMessage || m.documentWithCaptionMessage);
  if (isClientMsg) {
    if (ageMin !== undefined && ageMin > BOT_MAX_MESSAGE_AGE_MIN && !isSpreadsheet) {
      botLog({ ...info, result: 'ignorado-antiguo', note: `mensaje de hace ${ageMin} min: no se responde` });
      return { ignored: true, stale: true };
    }
    if (msgId) {
      if (seenMessageIds.has(msgId)) { botLog({ ...info, result: 'ignorado-duplicado' }); return { ignored: true, duplicate: true }; }
      seenMessageIds.add(msgId);
      if (seenMessageIds.size > 3000) seenMessageIds.delete(seenMessageIds.values().next().value);
    }
  }
  const t0 = Date.now();
  try {
    const result = await botContext.run({ origin: 'respuesta-bot', msgId, ageMin }, () => handleWebhookEventInner(body, db, saveDBCallback));
    // Los mensajes propios, de grupos o sin contenido no son de clientes: no llenan el registro
    if (isClientMsg) botLog({ ...info, result: result && result.handled ? 'atendido' : (result && result.paused ? 'ignorado-pausa' : (result && result.ignored ? 'ignorado' : 'ok')), ...(result && result.note ? { note: result.note } : {}), ms: Date.now() - t0 });
    return result;
  } catch (err) {
    botLog({ ...info, result: 'error', error: String(err.message || err).slice(0, 160), ms: Date.now() - t0 });
    throw err;
  }
}

module.exports = {
  getBotLog,
  botLog,
  getHealth,
  startWatchdog,
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
