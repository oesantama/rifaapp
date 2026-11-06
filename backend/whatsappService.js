// backend/whatsappService.js
// Servicio de integración con Evolution API para WhatsApp Bots
// Soporta SuperAdmin (Planes), Empresa (Rifas oficiales) y Asesores Independientes (Talonarios)

const EVOLUTION_URL = process.env.EVOLUTION_URL || 'http://evolution_api:8080';
const EVOLUTION_APIKEY = process.env.EVOLUTION_APIKEY || 'rifaapp_evo_secret_key_2026';
const PUBLIC_WEBHOOK_URL = process.env.PUBLIC_WEBHOOK_URL || 'http://45.137.192.195/api/whatsapp/webhook';

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

// Memoria a corto plazo de última consulta por usuario { 'senderPhone': { lastTicketId, lastRaffleId, timestamp } }
const lastUserInquiry = new Map();

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
    // Ignorar grupos
    return { ignored: true };
  }

  const senderPhone = senderJid.split('@')[0];
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

    // Saludo General SuperAdmin
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
    advisor = (db.advisors || []).find(a => a.id === advId || a.username === advId);
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

  // Fallback a primera empresa si no se encuentra
  if (!company && db.companies && db.companies.length > 0) {
    company = db.companies[0];
  }

  const companyName = company?.name || company?.companyName || 'Rifa Master';
  const companyCode = company?.code || '';

  // Buscar rifas activas de la empresa
  const activeRaffles = (db.raffles || []).filter(r => 
    (!company || r.companyId === company.id) && 
    r.status !== 'INACTIVA' && 
    r.active !== false
  );
  const mainRaffle = activeRaffles[0];

  // Si no hay rifas creadas aún
  if (!mainRaffle) {
    let noRaffleMsg = `👋 ¡Hola! Te comunicas con *${companyName}* 🎟️\n\n`;
    noRaffleMsg += `Actualmente estamos afinando los detalles de nuestro próximo gran sorteo.\n`;
    noRaffleMsg += `Muy pronto publicaremos las fechas, premios y abriremos la venta de boletas.\n\n`;
    noRaffleMsg += `Escribe *CUENTAS* si deseas consultar información de contacto o medios de pago.`;
    await sendTextMessage(instance, senderPhone, noRaffleMsg);
    return { handled: true };
  }

  // Contexto inteligente de la rifa activa
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
    const receiptReply = 
`📸 *¡Comprobante de transferencia recibido con éxito!* ✅
Hemos recibido la imagen de tu pago para *${companyName}*.

📋 *Para procesar tu boleta más rápido, por favor indícanos:*
1️⃣ Tu *Nombre y Apellidos completos*.
2️⃣ El *número de boleta o cifras* que compraste o abonaste.

Nuestro equipo administrativo confirmará la transacción en Nequi / Bancolombia y te emitiremos tu boleta oficial con código QR y respaldo digital. 🍀`;
    await sendTextMessage(instance, senderPhone, receiptReply);
    return { handled: true };
  }

  // 2. CONSULTA DE MEDIOS DE PAGO / CUENTAS
  if (cleanLower.includes('cuenta') || cleanLower.includes('pago') || cleanLower.includes('banco') || 
      cleanLower.includes('nequi') || cleanLower.includes('bancolombia') || cleanLower.includes('daviplata') ||
      cleanLower.includes('donde pago') || cleanLower.includes('transferencia')) {
    
    const bankAccounts = (db.banks || []).filter(b => !company || b.companyId === company.id || !b.companyId);
    let bankMsg = `💳 *MEDIOS DE PAGO OFICIALES - ${companyName}* 🏦\n\n`;
    bankMsg += `Puedes realizar tu pago o abono a través de:\n\n`;
    
    if (bankAccounts.length > 0) {
      bankAccounts.forEach(b => {
        bankMsg += `• *${b.name || 'Banco'}:* ${b.accountNumber || b.number || ''}\n`;
        bankMsg += `  Tipo: ${b.type || 'Ahorros'} | Titular: ${b.holder || companyName}\n\n`;
      });
    } else {
      bankMsg += `• *Nequi / Bancolombia / Daviplata*\n`;
      bankMsg += `  Titular: *${companyName}*\n`;
      bankMsg += `  Pide los datos de transferencia a nuestro administrador aquí mismo.\n\n`;
    }

    bankMsg += `📌 *Importante:* Una vez realizada la transferencia, envía la *foto del comprobante aquí mismo* para validar tu pago y registrar tu boleta con QR oficial.`;
    await sendTextMessage(instance, senderPhone, bankMsg);
    return { handled: true };
  }

  // 3. CONSULTA DE PLAN DE PREMIOS / PREMIO MAYOR
  if (cleanLower.includes('premio') || cleanLower.includes('que se gana') || cleanLower.includes('gana') || cleanLower.includes('mayor')) {
    let prizeMsg = `🏆 *PLAN DE PREMIOS - ${mainRaffle.title}* 🎁\n\n`;
    prizeMsg += `🌟 *Premio Mayor:*\n${mainRaffle.description || 'Gran Premio Oficial'}\n\n`;
    
    if (mainRaffle.weeklyPrizes && mainRaffle.weeklyPrizes.length > 0) {
      prizeMsg += `🎁 *Premios Anticipados / Semanales:*\n`;
      mainRaffle.weeklyPrizes.forEach(p => {
        prizeMsg += `• *${p.name || 'Premio Semanal'}:* $${Number(p.amount || 0).toLocaleString('es-CO')} COP (${p.drawDate || 'según fecha programada'})\n`;
      });
      prizeMsg += '\n';
    }

    prizeMsg += `🎯 *Juega con:* ${lotteryName}\n`;
    prizeMsg += `📅 *Fecha del Gran Sorteo:* ${drawDateFormatted}\n`;
    prizeMsg += `💵 *Valor Boleta:* $${ticketPrice.toLocaleString('es-CO')} COP (${opportunities} oportunidades de ${digits} cifras)\n\n`;
    prizeMsg += `💡 *Escribe un número de ${digits} cifras (ej: ${digits === 4 ? '3456' : '428'}) para verificar si está disponible.*`;

    await sendTextMessage(instance, senderPhone, prizeMsg);
    return { handled: true };
  }

  // 4. CONSULTA DE FECHA, LOTERÍA Y CONDICIONES
  if (cleanLower.includes('fecha') || cleanLower.includes('cuando juega') || cleanLower.includes('loteria') || cleanLower.includes('con que juega')) {
    let dateMsg = `📅 *FECHA Y LOTERÍA DEL SORTEO* 🎰\n\n`;
    dateMsg += `🎯 *Rifa:* ${mainRaffle.title}\n`;
    dateMsg += `🏆 *Lotería:* ${lotteryName}\n`;
    dateMsg += `🗓️ *Fecha:* ${drawDateFormatted}\n`;
    dateMsg += `🔢 *Modalidad:* Sorteo de *${digits} cifras* (${mainRaffle.winningDigitsPosition === 'PRIMERAS' ? 'Primeras cifras' : 'Últimas cifras'} del premio mayor).\n`;
    dateMsg += `💵 *Precio:* $${ticketPrice.toLocaleString('es-CO')} COP\n\n`;
    dateMsg += `👉 Escribe cualquier número de ${digits} cifras para ver si está libre.`;

    await sendTextMessage(instance, senderPhone, dateMsg);
    return { handled: true };
  }

  // 5. CONSULTA DE POLÍTICAS Y REGLAS
  if (cleanLower.includes('politica') || cleanLower.includes('regla') || cleanLower.includes('termino') || cleanLower.includes('condicion') || cleanLower.includes('como funciona')) {
    let rulesMsg = `📜 *TÉRMINOS Y CONDICIONES - ${companyName}* 📋\n\n`;
    rulesMsg += `1️⃣ *Condición de Ganador:* La boleta debe encontrarse 100% cancelada antes del inicio del sorteo oficial de ${lotteryName}.\n`;
    rulesMsg += `2️⃣ *Apartados:* Las boletas apartadas sin abono tienen vigencia temporal fijada por la administración.\n`;
    rulesMsg += `3️⃣ *Transparencia:* Cada boleta cuenta con registro criptográfico, serial único y código QR de verificación.\n`;
    rulesMsg += `4️⃣ *Reclamo:* El titular ganador deberá identificarse con su cédula de ciudadanía coincidente con el registro del sistema.\n\n`;
    rulesMsg += `¿Tienes dudas con un número? Escribe el número que buscas para consultar su disponibilidad.`;

    await sendTextMessage(instance, senderPhone, rulesMsg);
    return { handled: true };
  }

  // 6. INTENCIÓN DE RESERVAR / APARTAR CON NOMBRE TRAS CONSULTAR
  const isNameReservation = cleanLower.startsWith('apartar a ') || cleanLower.startsWith('mi nombre es ') || cleanLower.startsWith('reservar a ');
  if (isNameReservation && lastUserInquiry.has(senderPhone)) {
    const inquiry = lastUserInquiry.get(senderPhone);
    const candidateName = userText.replace(/^(apartar a|mi nombre es|reservar a)\s*/i, '').trim();
    if (candidateName.length >= 3) {
      const tickets = (db.tickets || []).filter(t => t.raffleId === inquiry.lastRaffleId);
      const targetTicket = tickets.find(t => t.id === inquiry.lastTicketId && t.status === 'DISPONIBLE');
      if (targetTicket) {
        targetTicket.status = 'RESERVADA';
        targetTicket.buyerName = candidateName;
        targetTicket.buyerPhone = senderPhone;
        targetTicket.saleChannel = 'WhatsApp';
        targetTicket.assignedDate = new Date().toISOString();
        targetTicket.abonos.push({
          id: `ab-bot-${Date.now()}`,
          amount: 0,
          date: new Date().toISOString(),
          sellerId: advisor ? advisor.id : 'bot',
          sellerName: advisor ? advisor.name : 'Bot WhatsApp',
          note: `Apartada automáticamente vía WhatsApp Bot por ${candidateName}`,
          metodoPago: 'efectivo'
        });

        if (typeof saveDBCallback === 'function') {
          saveDBCallback(inquiry.lastRaffleId);
        }

        const confirmMsg = 
`🎉 *¡BOLETA APARTADA CON ÉXITO!* ✅

🎟️ *Boleta:* #${targetTicket.ticketNumber}
🔢 *Tus números:* ${targetTicket.numbers.join('  •  ')}
👤 *Titular:* ${candidateName}
📱 *Teléfono:* ${senderPhone}
💵 *Saldo Pendiente:* $${ticketPrice.toLocaleString('es-CO')} COP

📌 *Siguiente paso:*
Para asegurar tu boleta, puedes realizar tu pago a nuestras cuentas (escribe *CUENTAS*) y enviar la foto del comprobante aquí mismo. ¡Muchos éxitos! 🍀`;
        
        lastUserInquiry.delete(senderPhone);
        await sendTextMessage(instance, senderPhone, confirmMsg);
        return { handled: true };
      }
    }
  }

  // 7. BÚSQUEDA Y CONSULTA DE NÚMERO (INTELIGENTE: 2, 3 o 4 CIFRAS)
  const numbersFound = userText.match(/\d+/g);
  if (numbersFound && numbersFound.length > 0) {
    const rawNumber = numbersFound[0];
    const tickets = (db.tickets || []).filter(t => t.raffleId === mainRaffle.id);

    // Buscar coincidencia exacta en las oportunidades de la boleta o en el ticketNumber
    let matchedTicket = tickets.find(t => {
      if (Array.isArray(t.numbers) && t.numbers.includes(rawNumber)) return true;
      if (String(t.ticketNumber) === rawNumber) return true;
      return false;
    });

    // Si no encontró coincidencia exacta y el usuario escribió menos cifras de las requeridas,
    // rellenar con ceros a la izquierda (ej: 345 -> 0345 si digits=4)
    let paddedNumber = rawNumber;
    if (!matchedTicket && rawNumber.length < digits) {
      paddedNumber = rawNumber.padStart(digits, '0');
      matchedTicket = tickets.find(t => {
        if (Array.isArray(t.numbers) && t.numbers.includes(paddedNumber)) return true;
        return false;
      });
    }

    if (matchedTicket) {
      // Guardar en memoria para que el usuario pueda apartar con su nombre en el siguiente mensaje
      lastUserInquiry.set(senderPhone, {
        lastTicketId: matchedTicket.id,
        lastRaffleId: mainRaffle.id,
        timestamp: Date.now()
      });

      if (matchedTicket.status === 'DISPONIBLE') {
        const availReply = 
`✅ *¡EL NÚMERO ${paddedNumber} ESTÁ DISPONIBLE!* 🎉

🎟️ *Boleta:* #${matchedTicket.ticketNumber}
🔢 *Oportunidades que juegas:* ${matchedTicket.numbers.join('  y  ')} (${opportunities} números por boleta)
💵 *Valor Boleta:* $${ticketPrice.toLocaleString('es-CO')} COP
${mainRaffle.minAbono ? `💰 *Abono Mínimo:* $${Number(mainRaffle.minAbono).toLocaleString('es-CO')} COP\n` : ''}🎯 *Sorteo:* ${mainRaffle.title}
🏆 *Juega con:* ${lotteryName} el ${drawDateFormatted}

✍️ *¿Deseas apartarlo ahora mismo?*
Responde con tu *NOMBRE COMPLETO* (ejemplo: _Apartar a Juan Pérez_) para reservártelo de inmediato a este número de WhatsApp.`;

        await sendTextMessage(instance, senderPhone, availReply);
        return { handled: true };
      } else {
        // Buscar 3 boletas alternativas disponibles
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
          busyReply += `\n¿Te gustaría apartar alguno de ellos? Escribe el número que prefieras.`;
        } else {
          busyReply += `💡 Puedes escribir otro número de ${digits} cifras para verificar si está libre.`;
        }

        await sendTextMessage(instance, senderPhone, busyReply);
        return { handled: true };
      }
    } else {
      // Si el número no existe en la rifa, avisarle con amabilidad y sugerir opciones
      const availableAlts = tickets.filter(t => t.status === 'DISPONIBLE').slice(0, 3);
      let notFoundReply = `ℹ️ El número *${rawNumber}* no pertenece al rango de esta rifa (*sorteo de ${digits} cifras*).\n\n`;
      if (availableAlts.length > 0) {
        notFoundReply += `🎲 *Te sugerimos estos números disponibles:*\n`;
        availableAlts.forEach(a => {
          notFoundReply += `• Boleta *#${a.ticketNumber}:* ${a.numbers.join('  •  ')}\n`;
        });
        notFoundReply += `\nEscribe el número que desees consultar.`;
      }
      await sendTextMessage(instance, senderPhone, notFoundReply);
      return { handled: true };
    }
  }

  // 8. SALUDO GENERAL Y MENÚ INFORMATIVO
  let welcomeMsg = `👋 ¡Hola! Te comunicas con *${companyName}* 🎟️\n`;
  if (advisor) {
    welcomeMsg = `👋 ¡Hola! Te atiende *${advisor.name}*, asesor oficial de *${companyName}* 🎟️\n`;
  }

  welcomeMsg += `\n🎯 *Gran Sorteo:* ${mainRaffle.title}\n`;
  if (mainRaffle.description) welcomeMsg += `🏆 *Premio Mayor:* ${mainRaffle.description}\n`;
  welcomeMsg += `🔢 *Modalidad:* ${digits} cifras (${opportunities} oportunidades por boleta)\n`;
  welcomeMsg += `📅 *Juega el:* ${drawDateFormatted} con ${lotteryName}\n`;
  welcomeMsg += `💵 *Valor:* $${ticketPrice.toLocaleString('es-CO')} COP\n`;

  welcomeMsg += 
`\n📌 *¿Qué deseas hacer?*
• Escribe cualquier *número de ${digits} cifras* para consultar si está libre (ej: *${digits === 4 ? '3456' : '428'}*).
• Escribe *PREMIOS* para conocer el plan de premios completo.
• Escribe *CUENTAS* para ver los datos de Nequi / Bancolombia.
• Envía la *foto de tu comprobante* si ya realizaste tu pago.`;

  await sendTextMessage(instance, senderPhone, welcomeMsg);
  return { handled: true };
}

module.exports = {
  formatPhoneNumber,
  getInstanceName,
  getStatus,
  connectInstance,
  disconnectInstance,
  sendTextMessage,
  handleWebhookEvent
};
