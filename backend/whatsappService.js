// backend/whatsappService.js
// Servicio de integración con Evolution API para WhatsApp Bots
// Soporta SuperAdmin (Planes), Empresa (Rifas oficiales) y Asesores Independientes (Talonarios)

const EVOLUTION_URL = process.env.EVOLUTION_URL || 'http://evolution_api:8080';
const EVOLUTION_APIKEY = process.env.EVOLUTION_APIKEY || 'rifaapp_evo_secret_key_2026';
const PUBLIC_WEBHOOK_URL = process.env.PUBLIC_WEBHOOK_URL || 'http://45.137.192.195/api/whatsapp/webhook';

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
    // Si ya está conectado, obtenemos datos del perfil
    return {
      state: 'open',
      instanceName,
      qrcode: null,
      number: stateRes.data?.instance?.owner || null
    };
  }

  // Si está esperando conexión, solicitamos el QR actual
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
  // Asegura que la instancia exista con Webhook configurado
  await evoRequest('/instance/create', {
    method: 'POST',
    body: JSON.stringify({
      instanceName,
      qrcode: !phoneNumber,
      number: phoneNumber || undefined,
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

  // Solicita conexión
  const query = phoneNumber ? `?number=${encodeURIComponent(phoneNumber)}` : '';
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
 * Envía un mensaje de texto por WhatsApp
 */
async function sendTextMessage(instanceName, number, text) {
  const cleanNumber = String(number).replace(/[^0-9]/g, '');
  return evoRequest(`/message/sendText/${instanceName}`, {
    method: 'POST',
    body: JSON.stringify({
      number: cleanNumber,
      text: text
    })
  });
}

/**
 * Cerebro del Bot: Procesa los mensajes entrantes de WhatsApp y responde
 */
async function handleWebhookEvent(body, db) {
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
    // Ignorar mensajes de grupos por ahora
    return { ignored: true };
  }

  const senderPhone = senderJid.split('@')[0];
  const userText = (msgData.conversation || msgData.extendedTextMessage?.text || '').trim();
  const hasImage = !!msgData.imageMessage;

  console.log(`💬 [WhatsApp Bot (${instance})] Mensaje de ${senderPhone}: "${userText}" ${hasImage ? '[FOTO COMPROBANTE]' : ''}`);

  // -------------------------------------------------------------
  // CASO 1: SUPER ADMIN BOT (Venta de Planes y Software RifaApp)
  // -------------------------------------------------------------
  if (instance === 'superadmin_sales' || instance === 'rifaapp_bot') {
    if (userText === '1' || userText.toLowerCase().includes('plan') || userText.toLowerCase().includes('precio')) {
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

    if (userText.toLowerCase().includes('demo') || userText === '2') {
      const demoText = 
`🎯 *ACCESO A LA DEMO DE RIFA MASTER:*
Puedes probar la plataforma ahora mismo:
🌐 *Web:* http://45.137.192.195

Explora el módulo de boletas, asesores, comisiones, caja y generador de afiches.
Si deseas una asesoría personalizada, un comercial te contactará en breve.`;
      await sendTextMessage(instance, senderPhone, demoText);
      return { handled: true };
    }

    // Saludo General SuperAdmin
    const greetingSuper = 
`👋 ¡Hola! Bienvenido a *Rifa Master Oficial* 🏆
El sistema profesional para gestión de rifas, boletas, asesores y recaudos.

¿En qué te podemos colaborar hoy?
1️⃣ Ver Planes y Precios
2️⃣ Solicitar Demo
3️⃣ Hablar con un Asesor Comercial

_(Escribe el número de la opción o tu consulta)_`;
    await sendTextMessage(instance, senderPhone, greetingSuper);
    return { handled: true };
  }

  // -------------------------------------------------------------
  // CASO 2: EMPRESA O ASESOR (Venta de Boletas y Sorteos)
  // -------------------------------------------------------------
  let company = null;
  let advisor = null;

  if (instance.startsWith('asesor_')) {
    const advId = instance.replace('asesor_', '');
    advisor = (db.advisors || []).find(a => a.id === advId || a.username === advId);
    if (advisor) {
      company = (db.companies || []).find(c => c.id === advisor.companyId);
    }
  } else if (instance.startsWith('empresa_')) {
    const compCode = instance.replace('empresa_', '');
    company = (db.companies || []).find(c => (c.code && c.code.toLowerCase() === compCode) || c.id === compCode);
  }

  // Si no se encuentra empresa específica, tomar la primera activa como fallback
  if (!company && db.companies && db.companies.length > 0) {
    company = db.companies[0];
  }

  const companyName = company?.name || 'Rifa Master';
  const activeRaffles = (db.raffles || []).filter(r => (!company || r.companyId === company.id) && r.active !== false);
  const mainRaffle = activeRaffles[0];

  // Si envía una foto (Comprobante de pago / abono)
  if (hasImage) {
    const receiptReply = 
`📸 *¡Comprobante de transferencia recibido!* ✅
Hemos recibido la imagen de tu pago para *${companyName}*.

Nuestro equipo administrativo verificará la transacción en Nequi / Bancolombia para asentar tu pago/abono en el sistema.
En breve te confirmaremos tus números y te enviaremos tu boleta digital con código QR. ¡Mucha suerte! 🍀`;
    await sendTextMessage(instance, senderPhone, receiptReply);
    return { handled: true };
  }

  // Si el usuario escribe cuentas o pagos
  if (userText.toLowerCase().includes('cuenta') || userText.toLowerCase().includes('pago') || userText.toLowerCase().includes('banco') || userText.toLowerCase().includes('nequi')) {
    const bankAccounts = (db.banks || []).filter(b => !company || b.companyId === company.id || !b.companyId);
    let bankMsg = `💳 *MEDIOS DE PAGO OFICIALES - ${companyName}:*\n\n`;
    if (bankAccounts.length > 0) {
      bankAccounts.forEach(b => {
        bankMsg += `• *${b.name}:* ${b.accountNumber || b.number || ''} (${b.type || 'Ahorros'}) - Titular: ${b.holder || companyName}\n`;
      });
    } else {
      bankMsg += `• *Nequi / Bancolombia:* Consulta con nuestro asesor al número de atención para los datos de transferencia.\n`;
    }
    bankMsg += `\n📌 *Importante:* Una vez realizada la transferencia o abono, envía la foto del comprobante aquí mismo.`;
    await sendTextMessage(instance, senderPhone, bankMsg);
    return { handled: true };
  }

  // Si el usuario escribe un número para consultar disponibilidad (ej: "428" o "0428")
  const numberMatch = userText.match(/\b\d{2,5}\b/);
  if (numberMatch && mainRaffle) {
    const searchedNum = numberMatch[0];
    const tickets = (db.tickets || []).filter(t => t.raffleId === mainRaffle.id);
    const foundTicket = tickets.find(t => {
      if (t.number === searchedNum) return true;
      if (t.series && Array.isArray(t.series) && t.series.includes(searchedNum)) return true;
      return false;
    });

    if (foundTicket) {
      if (foundTicket.status === 'DISPONIBLE') {
        const reply = 
`✅ *¡EL NÚMERO ${searchedNum} ESTÁ DISPONIBLE!* 🎉

🎟️ *Rifa:* ${mainRaffle.title}
💵 *Valor Boleta:* $${(mainRaffle.ticketPrice || 0).toLocaleString()} COP
${mainRaffle.minAbono ? `💰 *Abono Mínimo:* $${mainRaffle.minAbono.toLocaleString()} COP` : ''}

¿Deseas apartarlo? Responde con tu *NOMBRE COMPLETO* para reservarlo a tu número de WhatsApp.`;
        await sendTextMessage(instance, senderPhone, reply);
        return { handled: true };
      } else {
        const reply = 
`❌ *El número ${searchedNum} ya NO está disponible.*
Estado actual: *${foundTicket.status}*

💡 Puedes probar consultándome otro número (ejemplo: escribe otro número de 2 a 4 cifras).`;
        await sendTextMessage(instance, senderPhone, reply);
        return { handled: true };
      }
    }
  }

  // Saludo General de la Rifa
  let welcomeMsg = `👋 ¡Hola! Te comunicas con *${companyName}* 🎟️\n`;
  if (advisor) {
    welcomeMsg = `👋 ¡Hola! Te atiende *${advisor.name}*, asesor oficial de *${companyName}* 🎟️\n`;
  }

  if (mainRaffle) {
    welcomeMsg += `\n🎯 *Rifa Actual:* ${mainRaffle.title}\n`;
    if (mainRaffle.description) welcomeMsg += `🏆 *Premios:* ${mainRaffle.description}\n`;
    welcomeMsg += `💵 *Valor:* $${(mainRaffle.ticketPrice || 0).toLocaleString()} COP\n`;
    if (mainRaffle.mainDrawDate) welcomeMsg += `📅 *Fecha Sorteo:* ${mainRaffle.mainDrawDate.substring(0, 10)}\n`;
  }

  welcomeMsg += 
`\n📌 *¿Qué deseas hacer?*
• Escribe cualquier *número* para consultar si está libre (ej: *428*).
• Escribe *CUENTAS* para ver los datos de Nequi / Bancolombia.
• Envía la *foto de tu comprobante* si ya hiciste una consignación o abono.`;

  await sendTextMessage(instance, senderPhone, welcomeMsg);
  return { handled: true };
}

module.exports = {
  getInstanceName,
  getStatus,
  connectInstance,
  disconnectInstance,
  sendTextMessage,
  handleWebhookEvent
};
