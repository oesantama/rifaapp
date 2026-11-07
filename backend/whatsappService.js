// backend/whatsappService.js
// Servicio de integración con Evolution API para WhatsApp Bots
// Soporta SuperAdmin (Planes), Empresa (Rifas oficiales) y Asesores Independientes (Talonarios)

const EVOLUTION_URL = process.env.EVOLUTION_URL || 'http://evolution_api:8080';
const EVOLUTION_APIKEY = process.env.EVOLUTION_APIKEY || 'rifaapp_evo_secret_key_2026';
const PUBLIC_WEBHOOK_URL = process.env.PUBLIC_WEBHOOK_URL || 'http://45.137.192.195/api/whatsapp/webhook';
const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL || "https://45-137-192-195.sslip.io").replace(/\/+$/, "");

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
    return {
      state: 'open',
      instanceName,
      qrcode: null,
      number: stateRes.data?.instance?.owner || null
    };
  }

  const connectRes = await evoRequest(`/instance/connect/${instanceName}`);
  const qrcode = connectRes.data?.base64 || null;
  const pairingCode = connectRes.data?.pairingCode || null;

  return {
    state,
    instanceName,
    qrcode,
    pairingCode
  };
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
  const connectRes = await evoRequest(`/instance/connect/${instanceName}${query}`);

  return {
    state: 'connecting',
    instanceName,
    qrcode: connectRes.data?.base64 || null,
    pairingCode: connectRes.data?.pairingCode || null
  };
}

/**
 * Desconecta la sesión de WhatsApp
 */
async function disconnectInstance(instanceName) {
  const res = await evoRequest(`/instance/logout/${instanceName}`, {
    method: 'DELETE'
  });
  return { ok: res.ok, data: res.data };
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
  if (ticket.advisorId) {
    const direct = (db.advisors || []).find(a => a.id === ticket.advisorId);
    if (direct) return direct;
  }
  const companyId = raffle?.companyId || ticket.companyId;
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
  msg += `_Constructora • Inmobiliaria • Rifas y Eventos_\n\n`;
  msg += `Con gusto te atendemos. Por favor elige el área de tu interés:\n\n`;
  msg += `1️⃣ 🎟️ *Rifas y Sorteos Oficiales*\n`;
  msg += `   (Consulta de boletas, números disponibles, plan de premios y pagos)\n\n`;
  msg += `2️⃣ 🏗️ *Constructora y Proyectos*\n`;
  msg += `   (Construcción de viviendas, obras civiles, venta de lotes, remodelaciones y presupuestos)\n\n`;
  msg += `3️⃣ 👤 *Hablar con un Asesor*\n`;
  msg += `   (Atención humana personalizada para cualquier consulta)\n\n`;
  msg += `👉 _Responde con el número de tu opción (*1*, *2* o *3*) o cuéntanos qué necesitas._`;
  return msg;
}

function buildConstructoraMessage(companyName) {
  let msg = `🏗️ *CONSTRUCTORA Y PROYECTOS - ${companyName}* 🏡✨\n`;
  msg += `_Diseño, planeación y construcción de obras civiles e inmobiliarias con garantía y cumplimiento legal._\n\n`;
  msg += `🛠️ *Nuestros Servicios Principales:*\n`;
  msg += `• 🏠 *Construcción de Viviendas:* Casas campestres, urbanas, cabañas y fincas (llave en mano, obra gris o acabados de lujo).\n`;
  msg += `• 📐 *Diseños y Planos Arquitectónicos:* Modelado 3D, cálculos estructurales y gestión de licencias.\n`;
  msg += `• 🔨 *Remodelaciones y Obra Civil:* Fachadas, pisos, cocinas integrales, cubiertas, pintura y estructuras.\n`;
  msg += `• 🏞️ *Venta de Lotes y Parcelas:* Terrenos disponibles para proyectos residenciales y campestres en la región.\n`;
  msg += `• 🏊‍♂️ *Piscinas, Kioscos y Zonas Sociales.*\n\n`;
  msg += `📋 *¿En qué te podemos colaborar hoy?*\n`;
  msg += `• Escribe *COTIZAR* indicando el tipo de obra, medidas o ubicación para formular una propuesta.\n`;
  msg += `• Escribe *ASESOR* para hablar directamente con nuestro director de proyectos o arquitecto.\n`;
  msg += `• Escribe *MENU* para volver al menú de opciones.`;
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
  const userText = (msgData.conversation || msgData.extendedTextMessage?.text || '').trim();
  const hasImage = !!msgData.imageMessage;
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

  // 0. Si el chat está actualmente en atención manual por un asesor humano:
  if (session?.humanAssisted) {
    const isHumanResetCommand = cleanLower === 'menu' || cleanLower === 'menú' || cleanLower === 'bot' || 
                                cleanLower === 'reiniciar' || cleanLower === 'volver' || 
                                cleanLower === '1' || cleanLower === '2' || cleanLower === '3';
    const hoursSinceAssisted = (Date.now() - (session.humanAssistedAt || 0)) / (1000 * 60 * 60);

    if (!isHumanResetCommand && hoursSinceAssisted < 12) {
      console.log(`👤 [WhatsApp Bot (${instance})] Chat ${senderPhone} en atención humana activa (hace ${hoursSinceAssisted.toFixed(1)}h); se omite auto-respuesta.`);
      return { handled: true, humanAssisted: true };
    } else {
      updateSession(senderPhone, { humanAssisted: false }, db, saveDBCallback, null);
    }
  }

  // Buscar rifas activas de la empresa
  const activeRaffles = (db.raffles || []).filter(r => 
    (!company || r.companyId === company.id) && 
    r.status !== 'INACTIVA' && 
    r.active !== false
  );
  const mainRaffle = activeRaffles[0];

  if (!mainRaffle) {
    if (cleanLower === '2' || cleanLower.includes('constructora') || cleanLower.includes('obra')) {
      await sendTextMessage(instance, senderPhone, buildConstructoraMessage(companyName));
      return { handled: true };
    }
    if (cleanLower === '3' || cleanLower.includes('asesor') || cleanLower.includes('humano')) {
      updateSession(senderPhone, { humanAssisted: true, humanAssistedAt: Date.now() }, db, saveDBCallback, null);
      await sendTextMessage(instance, senderPhone, buildAdvisorHandOffMessage(companyName, advisor));
      return { handled: true };
    }
    const noRaffleMsg = buildMainMenuMessage(companyName, advisor);
    await sendTextMessage(instance, senderPhone, noRaffleMsg);
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

  // 1. RECEPCIÓN DE COMPROBANTES DE PAGO / TRANSFERENCIA (FOTO)
  if (hasImage) {
    // Si la imagen viene acompañada de texto sobre obra o el usuario estaba en constructora:
    if (session?.currentTopic === 'constructora' || cleanLower.includes('obra') || cleanLower.includes('constructora') || cleanLower.includes('anticipo') || cleanLower.includes('material')) {
      const receiptReply = 
`📸 *¡Comprobante para Constructora recibido con éxito!* 🏗️✅

Hemos registrado el soporte de pago para *${companyName} Constructora y Proyectos*.
Nuestro equipo administrativo validará la transferencia en cuenta y emitirá tu soporte de anticipo / abono oficial de obra.

Un asesor se pondrá en contacto contigo para coordinar el avance o visita técnica.
_(Escribe *MENU* para volver al menú de opciones)._`;
      await sendTextMessage(instance, senderPhone, receiptReply);
      return { handled: true };
    }

    let targetTicket = null;
    let numberIdentified = '';

    if (session && session.lastTicketId) {
      targetTicket = (db.tickets || []).find(t => t.id === session.lastTicketId);
      numberIdentified = session.lastOpportunity || (targetTicket ? targetTicket.numbers[0] : '');
    }
    if (!targetTicket) {
      targetTicket = (db.tickets || []).find(t => t.buyerPhone === senderPhone && t.raffleId === mainRaffle.id);
      if (targetTicket) numberIdentified = targetTicket.numbers[0];
    }
    // Si aún no hay boleta asignada, apartar automáticamente la primera disponible
    if (!targetTicket) {
      const freeTicket = (db.tickets || []).find(t => t.raffleId === mainRaffle.id && t.status === 'DISPONIBLE');
      if (freeTicket) {
        targetTicket = freeTicket;
        numberIdentified = freeTicket.numbers[0];
        targetTicket.status = 'RESERVADA';
        targetTicket.buyerPhone = senderPhone;
        targetTicket.soldByBot = true;
        targetTicket.saleChannel = 'Bot WhatsApp';
        targetTicket.assignedDate = new Date().toISOString();
        const assignedAdv = getAssignedAdvisorForTicket(targetTicket, mainRaffle, db) || advisor;
        if (assignedAdv) {
          targetTicket.advisorId = assignedAdv.id;
          targetTicket.advisorName = assignedAdv.name;
        }
      }
    }

    // Extraer datos financieros del comprobante (monto, número de comprobante, banco)
    const transferInfo = extractTransferInfo(userText);
    const detectedAmount = transferInfo.amount || session?.pendingAmount || ticketPrice;
    const detectedApproval = transferInfo.approvalNumber || session?.pendingApproval || '';
    const detectedBank = transferInfo.bank || session?.pendingBank || 'Transferencia Bancaria';

    // Anti-fraude: Validar si este comprobante ya fue usado
    const duplicateVoucher = detectedApproval ? checkDuplicateApprovalNumber(detectedApproval, targetTicket?.id, db) : null;

    if (targetTicket) {
      targetTicket.soldByBot = true;
      targetTicket.saleChannel = targetTicket.saleChannel || 'Bot WhatsApp';
      const assignedAdv = getAssignedAdvisorForTicket(targetTicket, mainRaffle, db) || advisor;
      if (assignedAdv) {
        targetTicket.advisorId = assignedAdv.id;
        targetTicket.advisorName = assignedAdv.name;
      }

      targetTicket.abonos = targetTicket.abonos || [];
      let existingAbono = targetTicket.abonos.find(a => a.isTransfer || a.metodoPago === 'transferencia');
      if (!existingAbono) {
        existingAbono = {
          id: `abn-${Date.now()}`,
          amount: detectedAmount,
          metodoPago: 'transferencia',
          date: new Date().toISOString(),
          sellerId: targetTicket.advisorId || (assignedAdv ? assignedAdv.id : ''),
          sellerName: targetTicket.advisorName ? `${targetTicket.advisorName} (🤖 Bot WhatsApp)` : '🤖 Bot WhatsApp',
          note: `Transferencia reportada por WhatsApp${detectedApproval ? ` (Comprobante: #${detectedApproval})` : ''}`,
          approvalNumber: detectedApproval,
          originBank: detectedBank,
          transferDate: new Date().toISOString(),
          soporteWebViewUrl: null,
          duplicateApprovalConfirmed: !!duplicateVoucher
          // Sin objeto 'verification' para que cashState sea POR_VALIDAR
        };
        targetTicket.abonos.push(existingAbono);
      } else {
        if (transferInfo.amount) existingAbono.amount = transferInfo.amount;
        if (transferInfo.approvalNumber) existingAbono.approvalNumber = transferInfo.approvalNumber;
        if (transferInfo.bank) existingAbono.originBank = transferInfo.bank;
        if (targetTicket.advisorName) existingAbono.sellerName = `${targetTicket.advisorName} (🤖 Bot WhatsApp)`;
      }

      targetTicket.auditLogs = targetTicket.auditLogs || [];
      targetTicket.auditLogs.push({
        id: `log-${Date.now()}`,
        date: new Date().toISOString(),
        user: '🤖 Bot WhatsApp',
        action: 'VENTA_BOT',
        description: `Comprobante de pago ($${Number(detectedAmount).toLocaleString('es-CO')}) reportado vía Bot WhatsApp${targetTicket.advisorName ? ` • Asesor: ${targetTicket.advisorName}` : ''}`
      });

      targetTicket.pendingTransferValidation = true;
      targetTicket.totalPaid = (targetTicket.abonos || []).reduce((s, a) => s + (a.amount || 0), 0);
      if (targetTicket.status === 'DISPONIBLE') {
        targetTicket.status = 'RESERVADA';
      }

      if (typeof saveDBCallback === 'function') {
        saveDBCallback(mainRaffle.id);
      }
    }

    const knownName = targetTicket?.buyerName || session?.buyerName || '';
    const knownDoc = targetTicket?.buyerDocument || session?.buyerDocument || '';
    const knownEmail = targetTicket?.buyerEmail || session?.buyerEmail || '';
    const knownCity = targetTicket?.buyerCity || session?.buyerCity || '';
    const knownCountry = targetTicket?.buyerCountry || session?.buyerCountry || 'Colombia';
    const hasAdvisor = targetTicket?.advisorName && targetTicket.advisorName !== 'Venta WhatsApp';

    const missing = [];
    if (!knownName) missing.push('Nombre y Apellidos completos (o Razón Social)');
    if (!knownDoc) missing.push('Cédula de Ciudadanía o NIT');
    if (!knownEmail) missing.push('Correo electrónico (para envío de soporte de compra)');
    if (!knownCity) missing.push('Ciudad y País (ej: San Martín, Meta)');

    let receiptReply = `📸 *¡Comprobante de transferencia recibido con éxito!* ✅\nHemos registrado tu comprobante en el sistema para *${companyName}*.\n\n`;

    if (numberIdentified && targetTicket) {
      receiptReply += `🎟️ *Boleta identificada:* *${numberIdentified}* (Boleta #${targetTicket.ticketNumber})\n`;
      receiptReply += `_(¿Deseas cambiar este número? Solo escribe el nuevo número que prefieres antes de confirmar).\n\n`;
    }

    // Reporte de monto y validación de excedente si paga más de una boleta
    receiptReply += `💵 *Valor reportado:* $${detectedAmount.toLocaleString('es-CO')} COP\n`;
    if (detectedApproval) receiptReply += `🧾 *Comprobante No.:* ${detectedApproval}\n`;
    if (detectedBank) receiptReply += `🏛️ *Medio / Banco:* ${detectedBank}\n`;

    if (detectedAmount > ticketPrice) {
      const surplus = detectedAmount - ticketPrice;
      const extraTickets = Math.floor(surplus / ticketPrice);
      const leftover = surplus % ticketPrice;
      receiptReply += `\n💡 *¡Tienes un excedente a tu favor de $${surplus.toLocaleString('es-CO')} COP!*\n`;
      receiptReply += `El valor de la boleta #${targetTicket.ticketNumber} es de $${ticketPrice.toLocaleString('es-CO')} COP. `;
      if (extraTickets > 0) {
        receiptReply += `¡Tu pago cubre *${extraTickets} boleta(s) adicional(es) completa(s)*${leftover > 0 ? ` y un abono de $${leftover.toLocaleString('es-CO')}` : ''}!\n`;
        receiptReply += `👉 *¿Deseas elegir tus números adicionales ahora?* Responde con los números que deseas apartar o escribe *DISPONIBLES*.\n`;
      }
    }

    if (duplicateVoucher) {
      receiptReply += `\n🚨 *ALERTA DE SEGURIDAD:* Este número de comprobante (#${detectedApproval}) ya figura registrado en otra boleta. Nuestro equipo administrativo cotejará el extracto bancario antes de la activación.\n`;
    }

    // Preguntar por asesor si aún no está asignado
    if (!hasAdvisor) {
      receiptReply += `\n🤝 *¿Te recomendó algún asesor de nuestro equipo?*\nIndícanos su nombre o código (o escribe *Ninguno* si compraste directamente).\n`;
    }

    if (missing.length === 0) {
      receiptReply += `\n👤 *Titular:* ${knownName}\n`;
      receiptReply += `🪪 *Cédula/NIT:* ${knownDoc}\n`;
      receiptReply += `📧 *Correo:* ${knownEmail}\n`;
      receiptReply += `📍 *Ciudad:* ${knownCity}, ${knownCountry}\n\n`;
      receiptReply += `✨ *Todos tus datos ya están completos y vinculados.* Nuestro equipo administrativo validará la transferencia en cuenta bancaria y activará tu boleta oficial.\n\n`;
      receiptReply += `🌐 *Puedes consultar tu boleta y Soporte Digital de Compra aquí:*\n`;
      receiptReply += `${PUBLIC_BASE_URL}/boleta?phone=${senderPhone}\n\n`;
      receiptReply += `¡Muchas gracias y mucha suerte en el sorteo! 🍀`;
    } else {
      let registeredLines = [];
      if (knownName) registeredLines.push(`• *Titular:* ${knownName}`);
      if (knownDoc) registeredLines.push(`• *Cédula/NIT:* ${knownDoc}`);
      if (knownEmail) registeredLines.push(`• *Correo:* ${knownEmail}`);
      if (knownCity) registeredLines.push(`• *Ciudad:* ${knownCity}`);

      if (registeredLines.length > 0) {
        receiptReply += `\n✅ *Datos ya registrados:*\n${registeredLines.join('\n')}\n\n`;
      }

      receiptReply += `\n📋 *Para completar tu Soporte Digital de Compra oficial, indícanos únicamente:*\n`;
      missing.forEach((m, idx) => {
        receiptReply += `${idx + 1}️⃣ *${m}*\n`;
      });
      receiptReply += `\n✍️ *Por favor indícanos ${missing.length === 1 ? 'este dato' : 'estos datos faltantes'} en tu siguiente mensaje.*`;
    }

    updateSession(senderPhone, {
      lastRaffleId: mainRaffle.id,
      lastTicketId: targetTicket ? targetTicket.id : (session?.lastTicketId || null),
      lastOpportunity: numberIdentified,
      waitingData: missing.length > 0,
      lastImageAt: Date.now(),
      pendingAmount: detectedAmount,
      pendingApproval: detectedApproval,
      pendingBank: detectedBank
    }, db, saveDBCallback, mainRaffle.id);

    await sendTextMessage(instance, senderPhone, receiptReply);
    return { handled: true };
  }

  // 1.5. RESPUESTA SOBRE ASESOR RECOMENDADO / REFERIDO
  const refreshedSession = getSession(senderPhone, db);
  const targetTkt = refreshedSession?.lastTicketId ? (db.tickets || []).find(t => t.id === refreshedSession.lastTicketId) : (db.tickets || []).find(t => t.buyerPhone === senderPhone);
  if (targetTkt && (!targetTkt.advisorName || targetTkt.advisorName === 'Venta WhatsApp')) {
    if (cleanLower === 'ninguno' || cleanLower === 'ninguna' || cleanLower === 'nadie' || cleanLower === 'directo' || cleanLower === 'no') {
      targetTkt.advisorId = null;
      targetTkt.advisorName = 'Venta Directa WhatsApp';
      if (typeof saveDBCallback === 'function') saveDBCallback(mainRaffle.id);
      await sendTextMessage(instance, senderPhone, `🤝 ¡Perfecto! Tu boleta #${targetTkt.ticketNumber} quedó registrada como *compra directa*.`);
      return { handled: true };
    }

    // Buscar si escribió el nombre o código de un asesor
    const matchedAdvisor = (db.advisors || []).find(a => {
      const advNameClean = (a.name || '').toLowerCase();
      const advCodeClean = (a.code || '').toLowerCase();
      return cleanLower.includes(advNameClean) || (advCodeClean && cleanLower.includes(advCodeClean)) ||
             (cleanLower.startsWith('asesor') && cleanLower.includes(advNameClean.split(' ')[0]));
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
      await sendTextMessage(instance, senderPhone, `🤝 ¡Excelente! Tu boleta #${targetTkt.ticketNumber} ha quedado formalmente vinculada a nuestro asesor *${matchedAdvisor.name}*.`);
      return { handled: true };
    }
  }

  // 1.6. DETECCIÓN DE DATOS DE TRANSFERENCIA EN TEXTO (Si envía comprobante, valor o banco por mensaje)
  const textTransfer = extractTransferInfo(userText);
  if ((textTransfer.amount || textTransfer.approvalNumber) && targetTkt) {
    targetTkt.abonos = targetTkt.abonos || [];
    let existingAbono = targetTkt.abonos.find(a => a.isTransfer || a.metodoPago === 'transferencia');
    if (!existingAbono) {
      existingAbono = {
        id: `abn-${Date.now()}`,
        amount: textTransfer.amount || ticketPrice,
        metodoPago: 'transferencia',
        date: new Date().toISOString(),
        sellerId: targetTkt.advisorId || '',
        sellerName: targetTkt.advisorName || 'Venta WhatsApp',
        note: `Transferencia reportada por WhatsApp${textTransfer.approvalNumber ? ` (Comprobante: #${textTransfer.approvalNumber})` : ''}`,
        approvalNumber: textTransfer.approvalNumber || '',
        originBank: textTransfer.bank || 'Transferencia Bancaria',
        transferDate: new Date().toISOString(),
        soporteWebViewUrl: null
      };
      targetTkt.abonos.push(existingAbono);
    } else {
      if (textTransfer.amount) existingAbono.amount = textTransfer.amount;
      if (textTransfer.approvalNumber) existingAbono.approvalNumber = textTransfer.approvalNumber;
      if (textTransfer.bank) existingAbono.originBank = textTransfer.bank;
    }
    targetTkt.pendingTransferValidation = true;
    targetTkt.totalPaid = (targetTkt.abonos || []).reduce((s, a) => s + (a.amount || 0), 0);
    if (typeof saveDBCallback === 'function') saveDBCallback(mainRaffle.id);
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

🎟️ *Boleta:* #${targetTicket.ticketNumber}
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

🎟️ *Boleta:* #${targetTicket.ticketNumber} (${targetTicket.numbers.join(' • ')})
${targetTicket.buyerName ? `• *Titular:* ${targetTicket.buyerName}\n` : ''}${targetTicket.buyerDocument ? `• *Cédula/NIT:* ${targetTicket.buyerDocument}\n` : ''}${targetTicket.buyerEmail ? `• *Correo:* ${targetTicket.buyerEmail}\n` : ''}${targetTicket.buyerCity ? `• *Ciudad:* ${targetTicket.buyerCity}\n` : ''}
📋 *Para completar tu Soporte Digital de Compra, solo indícanos:*
${missingAfter.map((m, idx) => `${idx + 1}️⃣ *${m}*`).join('\n')}

✍️ *Por favor indícanos ${missingAfter.length === 1 ? 'este dato' : 'estos datos faltantes'} para finalizar.*`;
      }

      updateSession(senderPhone, {
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
  // ENRUTAMIENTO MULTI-SERVICIO Y MENÚ DE ATENCIÓN (Rifas / Constructora / Asesor)
  // =============================================================

  // A. HABLAR CON UN ASESOR HUMANO (Opción 3)
  if (cleanLower === '3' || 
      cleanLower === 'asesor' || cleanLower === 'asesora' ||
      cleanLower.includes('humano') || cleanLower.includes('persona') ||
      cleanLower.includes('hablar con') || cleanLower.includes('comercial') ||
      cleanLower.includes('llamar') || cleanLower.includes('atencion') ||
      cleanLower.includes('atención') || cleanLower.includes('agente')) {
    
    updateSession(senderPhone, {
      humanAssisted: true,
      humanAssistedAt: Date.now()
    }, db, saveDBCallback, mainRaffle?.id);

    const handoffMsg = buildAdvisorHandOffMessage(companyName, advisor);
    await sendTextMessage(instance, senderPhone, handoffMsg);
    return { handled: true };
  }

  // B. CONSTRUCTORA Y PROYECTOS (Opción 2)
  if (cleanLower === '2' || 
      cleanLower.includes('constructora') || 
      cleanLower.includes('construccion') || cleanLower.includes('construcción') ||
      cleanLower.includes('obra') || cleanLower.includes('obras') ||
      cleanLower.includes('remodelacion') || cleanLower.includes('remodelación') ||
      cleanLower.includes('lote') || cleanLower.includes('lotes') ||
      cleanLower.includes('parcela') || cleanLower.includes('parcelas') ||
      cleanLower.includes('terreno') || cleanLower.includes('terrenos') ||
      cleanLower.includes('inmobiliaria') ||
      cleanLower.includes('plano') || cleanLower.includes('planos') ||
      cleanLower.includes('diseño') || cleanLower.includes('diseno') ||
      cleanLower.includes('casa campestre') || cleanLower.includes('construir')) {
    
    updateSession(senderPhone, {
      currentTopic: 'constructora',
      humanAssisted: false
    }, db, saveDBCallback, mainRaffle?.id);

    const constMsg = buildConstructoraMessage(companyName);
    await sendTextMessage(instance, senderPhone, constMsg);
    return { handled: true };
  }

  // C. SOLICITUD DE COTIZACIÓN DE CONSTRUCCIÓN
  if (cleanLower.includes('cotizar') || cleanLower.includes('cotizacion') || cleanLower.includes('cotización') || cleanLower.includes('presupuesto')) {
    updateSession(senderPhone, {
      currentTopic: 'constructora',
      humanAssisted: false
    }, db, saveDBCallback, mainRaffle?.id);

    const quoteMsg = 
`📐 *¡SOLICITUD DE COTIZACIÓN DE OBRA!* 🏗️✨

Para estructurar tu cotización personalizada con *${companyName} Constructora*, indícanos:
1️⃣ *Tipo de proyecto:* (Casa campestre, vivienda urbana, cabaña, piscina, remodelación o lote).
2️⃣ *Medidas estimadas:* (Metros cuadrados de construcción o área del terreno).
3️⃣ *Ubicación:* (Municipio o vereda donde se desarrollará la obra).

Un asesor técnico o arquitecto evaluará los requerimientos para formular la propuesta.
_(Escribe *ASESOR* si deseas agendar visita técnica en el lote o llamada directa)._`;

    await sendTextMessage(instance, senderPhone, quoteMsg);
    return { handled: true };
  }

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
      dispMsg += `• Boleta *#${t.ticketNumber}:* ${t.numbers.join('  •  ')}\n`;
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
      const prevSession = getSession(senderPhone, db);
      const isChangingNumber = prevSession && prevSession.lastTicketId && prevSession.lastTicketId !== matchedTicket.id;
      const previousTicket = isChangingNumber ? tickets.find(t => t.id === prevSession.lastTicketId) : null;

      if (matchedTicket.status === 'DISPONIBLE') {
        // Si el usuario ya tenía una boleta RESERVADA por él mismo y sin pagos, liberamos la anterior
        if (previousTicket && previousTicket.status === 'RESERVADA' && previousTicket.buyerPhone === senderPhone && (previousTicket.totalPaid || 0) === 0) {
          previousTicket.status = 'DISPONIBLE';
          previousTicket.buyerName = '';
          previousTicket.buyerPhone = '';
          previousTicket.buyerDocument = '';
          previousTicket.buyerEmail = '';
          previousTicket.buyerCity = '';
          previousTicket.buyerCountry = '';
        }

        // Si ya teníamos datos del comprador en la sesión, transferirlos a la nueva boleta
        const assignedAdv = getAssignedAdvisorForTicket(matchedTicket, mainRaffle, db) || advisor;
        if (assignedAdv) {
          matchedTicket.advisorId = assignedAdv.id;
          matchedTicket.advisorName = assignedAdv.name;
        }

        if (prevSession && (prevSession.buyerName || prevSession.buyerDocument)) {
          if (prevSession.buyerName) matchedTicket.buyerName = prevSession.buyerName;
          if (prevSession.buyerDocument) matchedTicket.buyerDocument = prevSession.buyerDocument;
          if (prevSession.buyerEmail) matchedTicket.buyerEmail = prevSession.buyerEmail;
          if (prevSession.buyerCity) matchedTicket.buyerCity = prevSession.buyerCity;
          if (prevSession.buyerCountry) matchedTicket.buyerCountry = prevSession.buyerCountry;
          matchedTicket.buyerPhone = senderPhone;
          matchedTicket.soldByBot = true;
          matchedTicket.saleChannel = 'Bot WhatsApp';
          matchedTicket.assignedDate = matchedTicket.assignedDate || new Date().toISOString();
          matchedTicket.status = 'RESERVADA';
          matchedTicket.auditLogs = matchedTicket.auditLogs || [];
          matchedTicket.auditLogs.push({
            id: `log-${Date.now()}`,
            date: new Date().toISOString(),
            user: '🤖 Bot WhatsApp',
            action: 'VENTA_BOT',
            description: `Boleta reservada por Bot de WhatsApp${matchedTicket.advisorName ? ` • Asignada a: ${matchedTicket.advisorName}` : ''}`
          });
          if (typeof saveDBCallback === 'function') {
            saveDBCallback(mainRaffle.id);
          }
        }

        updateSession(senderPhone, {
          lastTicketId: matchedTicket.id,
          lastRaffleId: mainRaffle.id,
          lastOpportunity: paddedNumber,
          lastTicketNumber: matchedTicket.ticketNumber,
          waitingData: !matchedTicket.buyerDocument
        }, db, saveDBCallback, mainRaffle.id);

        const otherOpportunities = matchedTicket.numbers.filter(n => n !== paddedNumber);

        if (isChangingNumber) {
          const changeMsg = 
`🔄 *¡NÚMERO CAMBIADO CON ÉXITO!* ✅

🎟️ *Tu nueva boleta es:* #${matchedTicket.ticketNumber}
🔢 *Juegas con el número:* *${paddedNumber}* ${otherOpportunities.length > 0 ? `(y también con *${otherOpportunities.join(', ')}*)` : ''}
${matchedTicket.buyerName ? `👤 *Titular:* ${matchedTicket.buyerName}\n` : ''}${matchedTicket.buyerDocument ? `🪪 *Cédula/NIT:* ${matchedTicket.buyerDocument}\n` : ''}${matchedTicket.advisorName ? `👤 *Asesor:* ${matchedTicket.advisorName}\n` : ''}💵 *Valor Boleta:* $${ticketPrice.toLocaleString('es-CO')} COP
🎯 *Sorteo:* ${mainRaffle.title} el ${drawDateFormatted}

${!matchedTicket.buyerDocument ? '📋 *Por favor indícanos tu Nombre, Cédula/NIT, Correo electrónico y Ciudad* para vincular tus datos al soporte digital de compra y tu boleta oficial.' : `🌐 *Puedes consultar tu boleta actualizada:* ${PUBLIC_BASE_URL}/boleta?phone=${senderPhone}`}
_(Si deseas cambiar a otro número, solo escribe el nuevo número)._ 🍀`;

          await sendTextMessage(instance, senderPhone, changeMsg);
          return { handled: true };
        }

        let advisorTxt = '';
        if (assignedAdv) {
          advisorTxt = `\n👤 *Asesor asignado:* *${assignedAdv.name}*\n💡 _(Este número se encuentra asignado a nuestro asesor *${assignedAdv.name}*. Si lo deseas, podemos apartártelo aquí directamente o puedes validar con él)._\n`;
        }

        const availReply = 
`✅ *¡EL NÚMERO ${paddedNumber} ESTÁ DISPONIBLE!* 🎉

🎟️ *Boleta:* #${matchedTicket.ticketNumber}
🔢 *Juegas con:* *${paddedNumber}* ${otherOpportunities.length > 0 ? `(y también con *${otherOpportunities.join(', ')}*)` : ''}
💵 *Valor Boleta:* $${ticketPrice.toLocaleString('es-CO')} COP
${mainRaffle.minAbono ? `💰 *Abono Mínimo:* $${Number(mainRaffle.minAbono).toLocaleString('es-CO')} COP\n` : ''}🎯 *Sorteo:* ${mainRaffle.title}
🏆 *Juega con:* ${lotteryName} el ${drawDateFormatted}${advisorTxt}
✍️ *¿Deseas apartarlo ahora mismo?*
Indícanos tu *NOMBRE COMPLETO, CÉDULA/NIT, CORREO y CIUDAD* (o envíanos la foto de tu comprobante de pago Nequi/Bancolombia) para reservártelo de inmediato a este número de WhatsApp.`;

        await sendTextMessage(instance, senderPhone, availReply);
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
            busyReply += `• Boleta *#${a.ticketNumber}:* ${a.numbers.join('  •  ')}\n`;
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
          notFoundReply += `• Boleta *#${a.ticketNumber}:* ${a.numbers.join('  •  ')}\n`;
        });
        notFoundReply += `\nEscribe el número que desees consultar o escribe *DISPONIBLES*.`;
      }
      await sendTextMessage(instance, senderPhone, notFoundReply);
      return { handled: true };
    }
  }

  // 9. FALLBACK Y ENRUTAMIENTO INTELIGENTE
  if (session?.currentTopic === 'constructora') {
    const constFollowup = 
`👷‍♂️ *Constructora y Proyectos - ${companyName}* 🏗️
Hemos recibido tu mensaje. Para coordinar los detalles de tu obra, presupuesto o visita técnica:
• Escribe *ASESOR* para hablar con nuestro director de proyectos.
• Escribe *COTIZAR* para solicitar una cotización formal.
• Escribe *MENU* para volver al menú de opciones.`;
    await sendTextMessage(instance, senderPhone, constFollowup);
    return { handled: true };
  }

  if (session?.currentTopic === 'rifa') {
    const raffleMsg = buildRaffleMessage(mainRaffle, companyName, digits, opportunities, ticketPrice, drawDateFormatted, lotteryName);
    await sendTextMessage(instance, senderPhone, raffleMsg);
    return { handled: true };
  }

  const defaultMenu = buildMainMenuMessage(companyName, advisor);
  await sendTextMessage(instance, senderPhone, defaultMenu);
  return { handled: true };
}

module.exports = {
  formatPhoneNumber,
  getInstanceName,
  getStatus,
  connectInstance,
  disconnectInstance,
  sendTextMessage,
  handleWebhookEvent,
  extractBuyerProfile
};
