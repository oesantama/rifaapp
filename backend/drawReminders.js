/**
 * Recordatorios y resultados de los sorteos semanales por WhatsApp a los COMPRADORES.
 *
 *  • Recordatorio: faltando N días (3 por defecto) para un sorteo semanal / anticipado, cada comprador recibe un mensaje que le dice
 *    si todavía debe el abono mínimo para participar o, si ya cumple, que juega en esa fecha, con el premio del sorteo (y el
 *    acumulado de sorteos anteriores sin ganador, si lo hay).
 *  • Resultado: cuando el administrador registra el número del sorteo semanal en Ganadores, todos los compradores reciben qué número
 *    cayó y si fue vendido a alguien o no (y entonces el premio se acumula).
 *
 * Quién envía: los clientes de un asesor reciben el mensaje desde el WhatsApp que ese asesor vinculó; los clientes sin asesor
 * (ventas del administrador o del bot) desde el WhatsApp de la empresa. Si un asesor no tiene WhatsApp vinculado, sus clientes no
 * reciben el mensaje (el administrador lo ve en la vista previa).
 *
 * Cuidado con el volumen: se envía de a un mensaje con una pausa aleatoria entre mensajes, para no saturar ni poner en riesgo
 * los números de WhatsApp.
 */
const { drawDateKey, drawDateLabel, byDrawDate, participationText } = require('./drawSchedule');

const DAY_MS = 24 * 3600 * 1000;
const colombiaDay = ms => new Date(ms - 5 * 3600 * 1000).toISOString().slice(0, 10);
const money = n => `$${Math.round(Number(n) || 0).toLocaleString('es-CO')}`;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const WEEKDAYS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
const MONTHS = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

/** "sábado 14 de noviembre" a partir de AAAA-MM-DD */
function longDay(key) {
  const d = new Date(`${key}T12:00:00Z`);
  return `${WEEKDAYS[d.getUTCDay()]} ${d.getUTCDate()} de ${MONTHS[d.getUTCMonth()]}`;
}
function daysBetween(fromKey, toKey) {
  return Math.round((Date.parse(`${toKey}T00:00:00Z`) - Date.parse(`${fromKey}T00:00:00Z`)) / DAY_MS);
}
const cleanName = name => String(name || '').replace(/\s+/g, ' ').trim();
const firstNameOf = name => cleanName(name).split(' ')[0] || 'cliente';
/** "Guillermo M." — en los resultados no se publica el nombre completo del comprador */
function shortNameOf(name) {
  const parts = cleanName(name).split(' ').filter(Boolean);
  if (!parts.length) return 'un cliente';
  return parts.length === 1 ? parts[0] : `${parts[0]} ${parts[parts.length - 1][0].toUpperCase()}.`;
}
const nums = t => (t.numbers || []).join(' • ') || String(t.ticketNumber || '');

module.exports = function createDrawReminders({ getDb, saveDB, whatsappService, weeklyMinAbonoOf, log = console, pauseFn }) {
  // ------------------------------------------------------------------ configuración
  function configOf(company) {
    const c = (company && company.drawRemindersConfig) || {};
    const days = Math.round(Number(c.daysBefore));
    return { enabled: c.enabled === true, daysBefore: days >= 1 && days <= 7 ? days : 3 };
  }

  const advisorOf = (db, ticket) => (ticket.advisorId ? (db.advisors || []).find(a => a.id === ticket.advisorId) : null);
  const isOpen = instance => {
    const h = whatsappService.getHealth ? whatsappService.getHealth(instance) : null;
    return !h || h.state === 'open'; // sin dato de vigilancia todavía: se intenta y si falla se reintenta
  };

  /** Desde qué WhatsApp se le escribe al comprador de una boleta. */
  function senderFor(db, company, ticket) {
    const adv = advisorOf(db, ticket);
    if (adv && adv.companyId === company.id) {
      const instance = adv.whatsapp && adv.whatsapp.instance;
      if (!instance) return { skip: 'sin-whatsapp', label: adv.name };
      if (!isOpen(instance)) return { skip: 'desconectado', label: adv.name };
      return { key: `advisor:${adv.id}`, instance, label: adv.name, advisorName: adv.name };
    }
    // Sin asesor (venta del administrador o del bot): el WhatsApp de la empresa
    const instance = whatsappService.getInstanceName({ role: 'admin', record: company });
    if (!isOpen(instance)) return { skip: 'desconectado', label: company.name || 'Empresa' };
    return { key: 'company', instance, label: company.name || 'la empresa', advisorName: '' };
  }

  function soldTickets(db, raffle) {
    return (db.tickets || []).filter(t => t.raffleId === raffle.id && t.status !== 'DISPONIBLE' && t.status !== 'ANULADA' && String(t.buyerPhone || '').replace(/\D/g, '').length >= 7);
  }

  /** Premio de un sorteo: lo del sorteo más lo acumulado de sorteos anteriores sin ganador (como al registrar el ganador). */
  function prizeInfo(db, raffle, prize) {
    const base = Number(prize && prize.amount) || 0;
    const pot = (db.winners || []).filter(w => w.accumulated && w.raffleId === raffle.id).reduce((s, w) => s + (parseFloat(w.basePrizeAmount || w.prizeAmount) || 0), 0);
    return { base, pot, total: base + pot };
  }
  const prizeLine = info => (info.pot > 0
    ? `🎁 *Premio:* ${money(info.total)} COP (${money(info.base)} del sorteo + ${money(info.pot)} acumulado de sorteos anteriores sin ganador)`
    : `🎁 *Premio:* ${money(info.base)} COP`);
  const prizeKey = p => String(p.id || `${drawDateKey(p.drawDate)}|${p.name || ''}`);

  // ------------------------------------------------------------------ recordatorio antes del sorteo
  function reminderText({ company, raffle, prize, sender, buyerName, tickets, days, info }) {
    const key = drawDateKey(prize.drawDate);
    const min = weeklyMinAbonoOf(raffle, prize);
    const when = days <= 0 ? 'HOY' : days === 1 ? 'mañana' : `en ${days} días`;
    const lottery = String(prize.lotteryName || raffle.lotteryName || '').trim();
    const who = sender.advisorName ? `tu asesor(a) *${sender.advisorName}*` : `*${company.name || 'la organización'}*`;
    const lines = [];
    let lacking = false;
    for (const t of tickets.slice(0, 6)) {
      const paid = Number(t.totalPaid) || 0;
      if (paid + 0.5 >= min) lines.push(`✅ Boleta ${nums(t)}: llevas ${money(paid)} y *ya cumples* el abono mínimo de ${money(min)}: ¡juegas el ${drawDateLabel(prize.drawDate)}!`);
      else { lacking = true; lines.push(`⚠️ Boleta ${nums(t)}: llevas ${money(paid)}. Para participar debes completar un abono total de *${money(min)}* (te faltan *${money(min - paid)}*) antes del sorteo.`); }
    }
    if (tickets.length > 6) lines.push(`… y ${tickets.length - 6} boleta(s) más.`);
    return `🗓️ *RECORDATORIO DE SORTEO* - ${raffle.title}

Hola *${firstNameOf(buyerName)}* 👋, te escribe ${who}.

📅 *${prize.name || 'Sorteo semanal'}:* ${when}, el ${longDay(key)}${lottery ? `, con la ${lottery}` : ''}.
${prizeLine(info)}

${lines.join('\n')}

${lacking ? '💳 Puedes completar tu abono con tu asesor(a) o respondiendo este mensaje. ¡No te quedes por fuera del sorteo!' : '¡Mucha suerte! 🍀'}`;
  }

  /** Mensajes de recordatorio de un sorteo (agrupados por comprador y por quien envía) + a quiénes no se puede escribir. */
  function buildReminders(db, company, raffle, prize, today) {
    const key = drawDateKey(prize.drawDate);
    const days = daysBetween(today, key);
    const info = prizeInfo(db, raffle, prize);
    const groups = new Map(); // sender.key|phone -> { sender, phone, buyerName, tickets }
    const skipped = new Map(); // etiqueta -> { motivo, boletas }
    for (const t of soldTickets(db, raffle)) {
      const sender = senderFor(db, company, t);
      if (sender.skip) {
        const k = `${sender.label}|${sender.skip}`;
        const e = skipped.get(k) || { label: sender.label, reason: sender.skip, tickets: 0 };
        e.tickets++;
        skipped.set(k, e);
        continue;
      }
      const phone = String(t.buyerPhone).replace(/\D/g, '');
      const gk = `${sender.key}|${phone}`;
      if (!groups.has(gk)) groups.set(gk, { sender, phone, buyerName: t.buyerName, tickets: [] });
      groups.get(gk).tickets.push(t);
    }
    const messages = [...groups.values()].map(g => ({
      senderKey: g.sender.key, instance: g.sender.instance, senderLabel: g.sender.label, phone: g.phone, buyerName: g.buyerName,
      text: reminderText({ company, raffle, prize, sender: g.sender, buyerName: g.buyerName, tickets: g.tickets, days, info })
    }));
    return { messages, skipped: [...skipped.values()], days, info };
  }

  /** Sorteos pendientes de la empresa que se juegan dentro de exactamente [daysBefore] días. */
  function dueDraws(db, company, today, daysBefore) {
    const out = [];
    for (const raffle of (db.raffles || []).filter(r => r.companyId === company.id && r.status === 'ACTIVA' && !r.scheduledDeletionAt && r.hasWeeklyDraws !== false)) {
      for (const prize of Array.isArray(raffle.weeklyPrizes) ? raffle.weeklyPrizes : []) {
        const key = drawDateKey(prize.drawDate);
        if (key === '9999') continue;
        if (prize.status && prize.status !== 'PENDIENTE') continue; // ya se jugó
        if (daysBetween(today, key) === daysBefore) out.push({ raffle, prize });
      }
    }
    return out;
  }

  // ------------------------------------------------------------------ envío (de a uno, con pausa)
  async function sendOne(item, origin) {
    try {
      const res = await whatsappService.sendTextMessage(item.instance, item.phone, item.text, { origin });
      return !!(res && res.ok);
    } catch (err) {
      return false;
    }
  }
  // ------------------------------------------------------------------ ritmo de envío (para que WhatsApp no bloquee los números)
  // • Entre un mensaje y otro: 6-12 s; si son más de 30 por enviar, 10-20 s.
  // • Cada 15 mensajes: un descanso largo de 1 a 2 minutos más.
  // • Tope por número y por día (200): al llegar se detiene y sigue al día siguiente.
  // • Si un número falla 3 veces seguidas (desconectado o con restricción) se deja de usar en esa vuelta.
  // • Solo en horario de atención (resultados: 8 a.m. a 9 p.m.; recordatorios: 9 a.m. a 7 p.m., hora de Colombia).
  const DAILY_CAP = Number(process.env.DRAW_WA_DAILY_CAP) || 200;
  const REST_EVERY = Number(process.env.DRAW_WA_REST_EVERY) || 15;
  const MAX_FAILS_IN_ROW = 3;
  const MAX_PER_TICK = 120;
  const pause = pauseFn || sleep;

  /** Espera (ms) antes del siguiente mensaje: depende de cuántos van en esta vuelta y de cuántos faltan en total. */
  function delayMs(sentInRun, volume) {
    const big = volume > 30;
    let ms = (big ? 10000 : 6000) + Math.random() * (big ? 10000 : 6000);
    if (sentInRun > 0 && sentInRun % REST_EVERY === 0) ms += 60000 + Math.random() * 60000;
    return ms;
  }
  const counterKey = (instance, now) => `${colombiaDay(now)}|${instance}`;
  function sentToday(instance, now = Date.now()) {
    const db = getDb();
    return (db.drawSendCounters && db.drawSendCounters[counterKey(instance, now)]) || 0;
  }
  function countSent(instance, now = Date.now()) {
    const db = getDb();
    db.drawSendCounters = db.drawSendCounters || {};
    const k = counterKey(instance, now);
    db.drawSendCounters[k] = (db.drawSendCounters[k] || 0) + 1;
    // solo se guardan los contadores de los últimos días
    for (const key of Object.keys(db.drawSendCounters)) if (key.slice(0, 10) < colombiaDay(now - 3 * DAY_MS)) delete db.drawSendCounters[key];
  }
  const colombiaHour = now => new Date(now - 5 * 3600 * 1000).getUTCHours();
  const resultsWindowOpen = (now = Date.now()) => colombiaHour(now) >= 8 && colombiaHour(now) < 21;

  /**
   * Envía una lista respetando el ritmo y los topes. onResult(item, ok) guarda el resultado de cada uno.
   * Devuelve cuántos se enviaron y por qué se detuvo (si faltaron).
   */
  async function sendPaced(items, origin, { budget = Infinity, onResult, now = () => Date.now() }) {
    const fails = {};
    let sent = 0;
    let stopped = null;
    for (const item of items) {
      if (sent >= budget) { stopped = 'tope-de-la-vuelta'; break; }
      if ((fails[item.instance] || 0) >= MAX_FAILS_IN_ROW) continue; // ese número está fallando: se reintenta en otra vuelta
      if (sentToday(item.instance, now()) >= DAILY_CAP) { stopped = 'tope-diario'; continue; }
      const ok = await sendOne(item, origin);
      fails[item.instance] = ok ? 0 : (fails[item.instance] || 0) + 1;
      if (ok) countSent(item.instance, now());
      sent++;
      onResult(item, ok);
      await pause(delayMs(sent, items.length));
    }
    return { sent, stopped };
  }

  const running = { reminders: false, results: false };

  async function processReminders(now = Date.now()) {
    if (running.reminders) return;
    running.reminders = true;
    try {
      const db = getDb();
      const nowCo = new Date(now - 5 * 3600 * 1000);
      const hour = nowCo.getUTCHours();
      if (hour < 9 || hour >= 19) return; // solo en horario de atención
      const today = colombiaDay(now);
      let budget = MAX_PER_TICK;
      for (const company of db.companies || []) {
        const cfg = configOf(company);
        if (!cfg.enabled) continue;
        for (const { raffle, prize } of dueDraws(db, company, today, cfg.daysBefore)) {
          if (budget <= 0) return;
          // El estado (a quién ya se le envió) va aparte de la rifa: los teléfonos de los compradores no deben viajar a la app
          db.drawReminderState = db.drawReminderState || {};
          const stateKey = `${raffle.id}|${prizeKey(prize)}`;
          const state = db.drawReminderState[stateKey] = db.drawReminderState[stateKey] || { sent: {}, tries: {} };
          const { messages } = buildReminders(db, company, raffle, prize, today);
          const pending = messages.filter(m => !state.sent[`${m.senderKey}|${m.phone}`] && (state.tries[`${m.senderKey}|${m.phone}`] || 0) < 3);
          const { sent } = await sendPaced(pending, 'recordatorio-sorteo', {
            budget,
            now: () => now,
            onResult: (m, ok) => {
              const k = `${m.senderKey}|${m.phone}`;
              if (ok) state.sent[k] = new Date().toISOString();
              else state.tries[k] = (state.tries[k] || 0) + 1;
              saveDB();
            }
          });
          budget -= sent;
        }
      }
    } finally {
      running.reminders = false;
    }
  }

  // ------------------------------------------------------------------ resultado del sorteo
  function resultText({ company, raffle, record, sender, buyer, info, nextPrize }) {
    const lottery = String(raffle.lotteryName || '').trim();
    const d = record.winnerDetails || {};
    const sold = !!(d.buyerName && String(d.buyerName).trim()) && d.status && d.status !== 'DISPONIBLE';
    const head = `🏆 *RESULTADO DEL ${String(record.drawName || 'SORTEO SEMANAL').toUpperCase()}* - ${raffle.title}`;
    const draw = `🎯 ${lottery ? `Lotería ${lottery.replace(/^lotería\s+(de\s+)?/i, 'de ')}: ` : ''}resultado *${record.lotteryResult || record.winningNumber}* → jugó el número *${record.winningNumber}*.`;
    let outcome;
    if (record.isWinner) {
      outcome = `✅ Ese número fue vendido a *${shortNameOf(d.buyerName)}* y cumplía el abono mínimo: ¡ganó *${money(record.totalPrizePaid)} COP*! 🎉`;
    } else if (sold) {
      outcome = `⚠️ Ese número fue vendido a *${shortNameOf(d.buyerName)}*, pero no tenía el abono mínimo (${money(d.minRequiredAmount)}) para participar, así que el premio *se acumula* para el próximo sorteo.`;
    } else {
      outcome = '⚠️ Ese número *no está vendido aún*, por eso el premio *se acumula* para el próximo sorteo.';
    }
    let tail = '';
    if (!record.isWinner) {
      tail = `\n\n💰 *Pozo acumulado:* ${money(info.pot)} COP${nextPrize ? `\n📅 *Próximo sorteo:* ${nextPrize.name || 'Sorteo semanal'} el ${drawDateLabel(nextPrize.drawDate)}, con premio de ${money((Number(nextPrize.amount) || 0) + info.pot)} COP` : ''}`;
    }
    return `${head}\n\n${draw}\n${outcome}${tail}\n\n${sender.advisorName ? `Te escribe tu asesor(a) *${sender.advisorName}*. ` : ''}¡Gracias por participar y mucha suerte en el próximo! 🍀`;
  }

  function winnerText({ raffle, record, sender }) {
    const d = record.winnerDetails || {};
    return `🎉 *¡FELICITACIONES ${firstNameOf(d.buyerName).toUpperCase()}!* 🎉\n\nTu boleta *${record.winningNumber}* ganó el *${record.drawName || 'sorteo semanal'}* de ${raffle.title}.\n🏆 *Premio:* ${money(record.totalPrizePaid)} COP\n\n${sender.advisorName ? `Tu asesor(a) *${sender.advisorName}*` : 'Nuestro equipo'} se comunicará contigo para coordinar la entrega. ¡Gracias por participar! 🍀`;
  }

  /** Todos los compradores de la rifa con quién les escribe; el comprador de la boleta ganadora recibe el mensaje de felicitación. */
  function buildResultMessages(db, company, raffle, record) {
    const info = {
      pot: (db.winners || []).filter(w => w.accumulated && w.raffleId === raffle.id).reduce((s, w) => s + (parseFloat(w.basePrizeAmount || w.prizeAmount) || 0), 0)
    };
    const upcoming = (raffle.weeklyPrizes || []).filter(p => drawDateKey(p.drawDate) !== '9999' && drawDateKey(p.drawDate) > drawDateKey(record.drawDate) && (!p.status || p.status === 'PENDIENTE')).sort(byDrawDate)[0];
    const winnerPhone = record.isWinner && record.winnerDetails ? String(record.winnerDetails.buyerPhone || '').replace(/\D/g, '') : '';
    const seen = new Set();
    const messages = [];
    const skipped = new Map();
    for (const t of soldTickets(db, raffle)) {
      const sender = senderFor(db, company, t);
      if (sender.skip) { skipped.set(sender.label, (skipped.get(sender.label) || 0) + 1); continue; }
      const phone = String(t.buyerPhone).replace(/\D/g, '');
      const k = `${sender.key}|${phone}`;
      if (seen.has(k)) continue;
      seen.add(k);
      const isWinnerBuyer = winnerPhone && phone === winnerPhone;
      messages.push({
        senderKey: sender.key, instance: sender.instance, senderLabel: sender.label, phone, buyerName: t.buyerName,
        text: isWinnerBuyer ? winnerText({ raffle, record, sender }) : resultText({ company, raffle, record, sender, buyer: t, info, nextPrize: upcoming })
      });
    }
    return { messages, skipped: [...skipped.entries()].map(([label, tickets]) => ({ label, tickets })) };
  }

  /** Avisa el resultado a los compradores. Se llama al guardar el ganador del sorteo semanal; envía en segundo plano. */
  function announceResult(record) {
    const db = getDb();
    const raffle = (db.raffles || []).find(r => r.id === record.raffleId);
    const company = raffle && (db.companies || []).find(c => c.id === raffle.companyId);
    if (!raffle || !company || record.drawType === 'PRINCIPAL') return;
    if (record.announcement) return; // ya se avisó (o se está avisando)
    // En el registro solo van los totales; a quién se le envió queda aparte (db.drawAnnouncements) para no exponer teléfonos
    db.drawAnnouncements = db.drawAnnouncements || {};
    db.drawAnnouncements[record.id] = { sent: {}, tries: {} };
    record.announcement = { startedAt: new Date().toISOString(), done: false, total: 0, sentCount: 0, failedCount: 0, skipped: null };
    saveDB();
    processResults().catch(err => log.warn('⚠️ No se pudo avisar el resultado del sorteo:', err.message));
  }

  async function processResults() {
    if (running.results) return;
    if (!resultsWindowOpen()) return; // de noche no se envía: queda pendiente y sigue a las 8 a.m.
    running.results = true;
    try {
      const db = getDb();
      for (const record of db.winners || []) {
        const ann = record.announcement;
        if (!ann || ann.done) continue;
        const raffle = (db.raffles || []).find(r => r.id === record.raffleId);
        const company = raffle && (db.companies || []).find(c => c.id === raffle.companyId);
        if (!raffle || !company) { ann.done = true; continue; }
        db.drawAnnouncements = db.drawAnnouncements || {};
        const track = db.drawAnnouncements[record.id] = db.drawAnnouncements[record.id] || { sent: {}, tries: {} };
        const { messages, skipped } = buildResultMessages(db, company, raffle, record);
        ann.skipped = skipped;
        ann.total = messages.length;
        const pendingMsgs = messages.filter(m => !track.sent[`${m.senderKey}|${m.phone}`] && (track.tries[`${m.senderKey}|${m.phone}`] || 0) < 3);
        const { stopped } = await sendPaced(pendingMsgs, 'resultado-sorteo', {
          onResult: (m, ok) => {
            const k = `${m.senderKey}|${m.phone}`;
            if (ok) track.sent[k] = new Date().toISOString();
            else track.tries[k] = (track.tries[k] || 0) + 1;
            ann.sentCount = Object.keys(track.sent).length;
            ann.failedCount = Object.values(track.tries).filter(n => n >= 3).length;
            saveDB();
          }
        });
        // Si se detuvo por el tope diario o por un número que falla, quedan pendientes y siguen en la próxima vuelta (no se da por terminado)
        const leftover = messages.filter(m => !track.sent[`${m.senderKey}|${m.phone}`] && (track.tries[`${m.senderKey}|${m.phone}`] || 0) < 3);
        if (leftover.length) {
          if (stopped === 'tope-diario') ann.pausedByCap = new Date().toISOString();
          saveDB();
          continue;
        }
        ann.done = true;
        ann.finishedAt = new Date().toISOString();
        saveDB();
      }
    } finally {
      running.results = false;
    }
  }

  // ------------------------------------------------------------------ vista previa para el administrador
  function nextDraw(db, company, today) {
    const list = [];
    for (const raffle of (db.raffles || []).filter(r => r.companyId === company.id && r.status === 'ACTIVA' && !r.scheduledDeletionAt && r.hasWeeklyDraws !== false)) {
      for (const prize of Array.isArray(raffle.weeklyPrizes) ? raffle.weeklyPrizes : []) {
        const key = drawDateKey(prize.drawDate);
        if (key === '9999' || key < today || (prize.status && prize.status !== 'PENDIENTE')) continue;
        list.push({ raffle, prize, key });
      }
    }
    return list.sort((a, b) => a.key.localeCompare(b.key))[0] || null;
  }

  function preview(company, now = Date.now()) {
    const db = getDb();
    const today = colombiaDay(now);
    const next = nextDraw(db, company, today);
    if (!next) return { draw: null };
    const { messages, skipped, days, info } = buildReminders(db, company, next.raffle, next.prize, today);
    const bySender = new Map();
    for (const m of messages) {
      const e = bySender.get(m.senderKey) || { label: m.senderLabel, recipients: 0 };
      e.recipients++;
      bySender.set(m.senderKey, e);
    }
    const cfg = configOf(company);
    return {
      draw: { raffle: next.raffle.title, name: next.prize.name || 'Sorteo semanal', date: drawDateLabel(next.prize.drawDate), daysLeft: days, sendsOn: days > cfg.daysBefore ? drawDateLabel(new Date(Date.parse(`${next.key}T12:00:00Z`) - cfg.daysBefore * DAY_MS).toISOString().slice(0, 10)) : 'hoy', prize: info },
      senders: [...bySender.values()].sort((a, b) => b.recipients - a.recipients),
      skipped: skipped.map(s => ({ label: s.label, reason: s.reason === 'sin-whatsapp' ? 'No tiene WhatsApp vinculado' : 'Su WhatsApp está desconectado', tickets: s.tickets })),
      sample: messages[0] ? messages[0].text : ''
    };
  }

  // ------------------------------------------------------------------ rutas y arranque
  function registerRoutes(app, { adminOnly, targetCompanyOf }) {
    const company = (req, res) => {
      const c = targetCompanyOf(req);
      if (!c) res.status(400).json({ error: 'Seleccione la empresa.' });
      return c;
    };
    app.get('/api/draw-reminders/config', adminOnly, (req, res) => {
      const c = company(req, res);
      if (!c) return;
      const db = getDb();
      const advisors = (db.advisors || []).filter(a => a.companyId === c.id && a.status !== 'INHABILITADO').map(a => {
        const instance = a.whatsapp && a.whatsapp.instance;
        const h = instance && whatsappService.getHealth ? whatsappService.getHealth(instance) : null;
        return { id: a.id, name: a.name, linked: !!instance, number: (a.whatsapp && a.whatsapp.number) || null, state: h ? h.state : (instance ? 'unknown' : 'none') };
      });
      res.json({ ...configOf(c), advisors });
    });
    app.put('/api/draw-reminders/config', adminOnly, (req, res) => {
      const c = company(req, res);
      if (!c) return;
      const body = req.body || {};
      const days = Math.round(Number(body.daysBefore));
      c.drawRemindersConfig = { enabled: body.enabled === true, daysBefore: days >= 1 && days <= 7 ? days : 3 };
      saveDB();
      res.json(configOf(c));
    });
    app.get('/api/draw-reminders/preview', adminOnly, (req, res) => {
      const c = company(req, res);
      if (!c) return;
      res.json(preview(c));
    });
  }

  let timer = null;
  function start() {
    if (timer) return;
    const tick = () => {
      processReminders().catch(err => log.warn('⚠️ Recordatorios de sorteo:', err.message));
      processResults().catch(err => log.warn('⚠️ Resultados de sorteo:', err.message)); // retoma los avisos que quedaron a medias
    };
    setTimeout(tick, 120 * 1000);
    timer = setInterval(tick, 10 * 60 * 1000);
  }

  return { sendPaced, delayMs, sentToday, DAILY_CAP, REST_EVERY, start, registerRoutes, announceResult, processReminders, processResults, buildReminders, buildResultMessages, preview, configOf, reminderText, resultText, dueDraws };
};
