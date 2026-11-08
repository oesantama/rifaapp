/**
 * Alertas y notificaciones push.
 *
 *  • Sorteo cerca: faltando 3 días (o menos) para un sorteo, avisa qué boletas aún no llegan al abono mínimo (sorteos
 *    semanales) o no están pagas completas (sorteo principal): al asesor dueño de cada boleta y al administrador.
 *  • Efectivo sin legalizar: pagos en efectivo con 7 días o más en poder del asesor sin entregar/legalizar: al asesor y al
 *    administrador, y se repite cada día mientras siga pendiente.
 *
 * Canales: bandeja dentro de la app (siempre), notificación push del navegador/PWA (Web Push, gratis) y WhatsApp por el bot
 * de la empresa (si está conectado). Cada aviso se crea una sola vez por día y asunto (clave de duplicado).
 */
const webpush = require('web-push');

const DAY_MS = 24 * 3600 * 1000;
const DRAW_WARN_DAYS = 3;
const CASH_STALE_DAYS = 7;
const KEEP_DAYS = 45;
const MAX_ALERTS = 2000;

const colombiaDay = ms => new Date(ms - 5 * 3600 * 1000).toISOString().slice(0, 10);
const money = n => `$${Math.round(Number(n) || 0).toLocaleString('es-CO')}`;

/** "14/11/2026" o "2026-11-14T12:00:00" -> "2026-11-14" (sin depender de la zona horaria del servidor). */
function dayKey(raw) {
  const s = String(raw || '').trim();
  let m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})/);
  if (m) return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`;
  m = s.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  const t = Date.parse(s);
  return isNaN(t) ? null : colombiaDay(t);
}

function daysBetween(fromDay, toDay) {
  const a = Date.parse(`${fromDay}T00:00:00Z`);
  const b = Date.parse(`${toDay}T00:00:00Z`);
  return Math.round((b - a) / DAY_MS);
}

module.exports = function createAlertService({ getDb, saveDB, weeklyMinAbonoOf, whatsappService, log = console }) {
  // ------------------------------------------------------------------ VAPID (Web Push)
  function ensureVapid() {
    const db = getDb();
    db.settings = db.settings || {};
    if (!db.settings.vapid || !db.settings.vapid.publicKey) {
      db.settings.vapid = webpush.generateVAPIDKeys();
      saveDB();
    }
    webpush.setVapidDetails(process.env.VAPID_SUBJECT || 'mailto:soporte@rifamaster.app', db.settings.vapid.publicKey, db.settings.vapid.privateKey);
    return db.settings.vapid.publicKey;
  }

  // ------------------------------------------------------------------ cálculo de alertas
  function companyRaffles(db, company) {
    return (db.raffles || []).filter(r => r.companyId === company.id && r.status === 'ACTIVA' && !r.scheduledDeletionAt);
  }

  /** Avisos que corresponden HOY (sin duplicar los que ya existen). Devuelve la lista de avisos nuevos. */
  function buildAlerts(now = Date.now()) {
    const db = getDb();
    const today = colombiaDay(now);
    const existing = new Set((db.alerts || []).map(a => a.key));
    const out = [];
    const push = a => { if (!existing.has(a.key)) { existing.add(a.key); out.push(a); } };
    const advisorById = new Map((db.advisors || []).map(a => [a.id, a]));

    for (const company of db.companies || []) {
      const raffles = companyRaffles(db, company);

      // ---- 1. Sorteos a 3 días o menos: boletas que aún no pueden participar
      for (const raffle of raffles) {
        const price = Number(raffle.ticketPrice) || 0;
        const draws = [];
        if (raffle.hasWeeklyDraws !== false) {
          for (const p of raffle.weeklyPrizes || []) {
            const day = dayKey(p.drawDate);
            if (!day) continue;
            const days = daysBetween(today, day);
            if (days >= 0 && days <= DRAW_WARN_DAYS) draws.push({ id: `${p.name}|${day}`, name: p.name || 'Sorteo semanal', day, days, min: weeklyMinAbonoOf(raffle, p), main: false });
          }
        }
        const mainDay = dayKey(raffle.mainDrawDate);
        if (mainDay) {
          const days = daysBetween(today, mainDay);
          if (days >= 0 && days <= DRAW_WARN_DAYS) draws.push({ id: `PRINCIPAL|${mainDay}`, name: 'Sorteo principal', day: mainDay, days, min: price, main: true });
        }
        if (!draws.length) continue;
        const sold = (db.tickets || []).filter(t => t.raffleId === raffle.id && t.status !== 'DISPONIBLE' && t.status !== 'ANULADA');
        for (const draw of draws) {
          const lacking = sold.filter(t => (Number(t.totalPaid) || 0) + 0.5 < draw.min);
          if (!lacking.length) continue;
          const when = draw.days === 0 ? 'HOY' : draw.days === 1 ? 'mañana' : `en ${draw.days} días`;
          const byAdvisor = new Map();
          for (const t of lacking) {
            const k = advisorById.has(t.advisorId) ? t.advisorId : '';
            if (!byAdvisor.has(k)) byAdvisor.set(k, { count: 0, missing: 0 });
            const g = byAdvisor.get(k);
            g.count++;
            g.missing += Math.max(0, draw.min - (Number(t.totalPaid) || 0));
          }
          const requirement = draw.main ? 'estar pagada por completo' : `tener el abono mínimo de ${money(draw.min)}`;
          for (const [advId, g] of byAdvisor) {
            if (!advId) continue;
            push({
              key: `DRAW|${raffle.id}|${draw.id}|${advId}|${today}`, type: 'SORTEO_CERCA', audience: `advisor:${advId}`, companyId: company.id,
              title: `${draw.name} ${when}: boletas sin completar`,
              body: `${g.count} boleta${g.count === 1 ? '' : 's'} tuya${g.count === 1 ? '' : 's'} en "${raffle.title}" aún ${g.count === 1 ? 'no cumple' : 'no cumplen'} el requisito (${requirement}). Faltan ${money(g.missing)} en total para que participen.`
            });
          }
          const top = [...byAdvisor.entries()].sort((a, b) => b[1].missing - a[1].missing).slice(0, 5)
            .map(([id, g]) => `${id ? (advisorById.get(id).name) : 'Venta directa'}: ${g.count} (${money(g.missing)})`).join(' • ');
          push({
            key: `DRAW_ADMIN|${raffle.id}|${draw.id}|${today}`, type: 'SORTEO_CERCA', audience: `admin:${company.id}`, companyId: company.id,
            title: `${draw.name} ${when}: ${lacking.length} boletas sin completar`,
            body: `En "${raffle.title}", ${lacking.length} boleta${lacking.length === 1 ? '' : 's'} aún ${lacking.length === 1 ? 'no puede participar' : 'no pueden participar'} (requisito: ${requirement}). ${top}.`
          });
        }
      }

      // ---- 2. Efectivo en poder del asesor por 7 días o más sin legalizar
      const raffleIds = new Set(raffles.map(r => r.id));
      const cashByAdvisor = new Map();
      for (const t of db.tickets || []) {
        if (!raffleIds.has(t.raffleId)) continue;
        for (const ab of t.abonos || []) {
          if (!(Number(ab.amount) > 0) || ab.metodoPago === 'transferencia' || ab.received || ab.deliveryId) continue;
          if (!advisorById.has(ab.sellerId)) continue; // efectivo del administrador o de ventas directas: no hay asesor al que cobrar
          const days = Math.floor((now - Date.parse(ab.date)) / DAY_MS);
          if (!(days >= CASH_STALE_DAYS)) continue;
          if (!cashByAdvisor.has(ab.sellerId)) cashByAdvisor.set(ab.sellerId, { total: 0, count: 0, oldest: 0 });
          const g = cashByAdvisor.get(ab.sellerId);
          g.total += Number(ab.amount);
          g.count++;
          g.oldest = Math.max(g.oldest, days);
        }
      }
      for (const [advId, g] of cashByAdvisor) {
        push({
          key: `CASH7|${advId}|${today}`, type: 'EFECTIVO_SIN_LEGALIZAR', audience: `advisor:${advId}`, companyId: company.id,
          title: `Tienes ${money(g.total)} en efectivo sin legalizar`,
          body: `${g.count} pago${g.count === 1 ? '' : 's'} en efectivo con más de ${CASH_STALE_DAYS} días en tu poder (el más antiguo hace ${g.oldest} días). Repórtalos en "Mi Caja" para entregarlos.`
        });
      }
      if (cashByAdvisor.size) {
        const total = [...cashByAdvisor.values()].reduce((s, g) => s + g.total, 0);
        const detail = [...cashByAdvisor.entries()].sort((a, b) => b[1].total - a[1].total).slice(0, 6)
          .map(([id, g]) => `${advisorById.get(id).name}: ${money(g.total)} (${g.oldest} d)`).join(' • ');
        push({
          key: `CASH7_ADMIN|${company.id}|${today}`, type: 'EFECTIVO_SIN_LEGALIZAR', audience: `admin:${company.id}`, companyId: company.id,
          title: `${money(total)} en efectivo sin legalizar hace más de ${CASH_STALE_DAYS} días`,
          body: `${cashByAdvisor.size} asesor${cashByAdvisor.size === 1 ? '' : 'es'} con efectivo sin legalizar: ${detail}.`
        });
      }
    }
    return out.map(a => ({ id: `al-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`, createdAt: new Date(now).toISOString(), readAt: null, ...a }));
  }

  // ------------------------------------------------------------------ entrega
  async function deliver(alert) {
    const db = getDb();
    const text = `🔔 *Rifa Master*\n*${alert.title}*\n${alert.body}`;
    // 1) Notificación push del navegador / PWA
    const [kind, id] = alert.audience.split(':');
    const subs = (db.pushSubscriptions || []).filter(s => (kind === 'advisor' ? s.userKind === 'asesor' && s.userId === id : s.userKind === 'admin' && s.companyId === id));
    for (const s of subs) {
      try {
        await webpush.sendNotification({ endpoint: s.endpoint, keys: s.keys }, JSON.stringify({ title: alert.title, body: alert.body, url: '/', tag: alert.type }), { TTL: 6 * 3600 });
      } catch (err) {
        if (err.statusCode === 404 || err.statusCode === 410) db.pushSubscriptions = (db.pushSubscriptions || []).filter(x => x.endpoint !== s.endpoint);
        else log.warn(`⚠️ Push no enviado: ${err.statusCode || err.message}`);
      }
    }
    // 2) WhatsApp por el bot de la empresa (si está conectado)
    try {
      const company = (db.companies || []).find(c => c.id === alert.companyId);
      if (!company || company.alertsWhatsapp === false) return;
      const phone = kind === 'advisor' ? ((db.advisors || []).find(a => a.id === id) || {}).phone : company.phone;
      if (!phone) return;
      const instance = whatsappService.getInstanceName({ role: 'admin', record: company });
      const health = whatsappService.getHealth(instance);
      if (health && health.state === 'open') await whatsappService.sendTextMessage(instance, phone, text);
    } catch (err) {
      log.warn(`⚠️ Aviso por WhatsApp no enviado: ${err.message}`);
    }
  }

  async function run({ now = Date.now(), companyId = null } = {}) {
    const db = getDb();
    ensureVapid();
    db.alerts = db.alerts || [];
    let fresh = buildAlerts(now);
    if (companyId) fresh = fresh.filter(a => a.companyId === companyId);
    if (!fresh.length) return { created: 0 };
    db.alerts.unshift(...fresh);
    const cutoff = now - KEEP_DAYS * DAY_MS;
    db.alerts = db.alerts.filter(a => Date.parse(a.createdAt) >= cutoff).slice(0, MAX_ALERTS);
    saveDB();
    for (const a of fresh) await deliver(a);
    saveDB();
    log.log(`🔔 Alertas creadas: ${fresh.length} (${[...new Set(fresh.map(a => a.type))].join(', ')})`);
    return { created: fresh.length };
  }

  // ------------------------------------------------------------------ programador: una vez al día, desde las 8:00 (Colombia)
  let timer = null;
  function start() {
    if (timer) return;
    const tick = async () => {
      try {
        const db = getDb();
        const nowCo = new Date(Date.now() - 5 * 3600 * 1000);
        const today = colombiaDay(Date.now());
        if (nowCo.getUTCHours() >= 8 && db.alertsLastRunDay !== today) {
          db.alertsLastRunDay = today;
          await run();
        }
      } catch (err) {
        log.warn('⚠️ No se pudieron generar las alertas:', err.message);
      }
    };
    setTimeout(tick, 90 * 1000);
    timer = setInterval(tick, 30 * 60 * 1000);
  }

  // ------------------------------------------------------------------ rutas
  function audiencesOf(req) {
    if (req.auth.role === 'asesor') return [`advisor:${req.auth.record.id}`];
    if (req.auth.role === 'admin') return [`admin:${req.auth.record.id}`];
    return [];
  }

  function registerRoutes(app, { adminOnly }) {
    app.get('/api/alerts', (req, res) => {
      const mine = new Set(audiencesOf(req));
      const list = (getDb().alerts || []).filter(a => mine.has(a.audience));
      res.json({ unread: list.filter(a => !a.readAt).length, alerts: list.slice(0, 60) });
    });

    app.post('/api/alerts/read', (req, res) => {
      const mine = new Set(audiencesOf(req));
      const ids = Array.isArray((req.body || {}).ids) ? new Set(req.body.ids) : null;
      const now = new Date().toISOString();
      let changed = 0;
      for (const a of getDb().alerts || []) {
        if (mine.has(a.audience) && !a.readAt && (!ids || ids.has(a.id))) { a.readAt = now; changed++; }
      }
      if (changed) saveDB();
      res.json({ ok: true, changed });
    });

    // Genera ahora los avisos de la empresa del administrador (no repite los de hoy)
    app.post('/api/alerts/run', adminOnly, async (req, res) => {
      try {
        const result = await run({ companyId: req.auth.role === 'admin' ? req.auth.record.id : null });
        res.json({ ok: true, ...result });
      } catch (err) {
        res.status(500).json({ error: err.message });
      }
    });

    app.get('/api/push/public-key', (req, res) => res.json({ publicKey: ensureVapid() }));

    app.post('/api/push/subscribe', (req, res) => {
      const sub = (req.body || {}).subscription;
      if (!sub || !sub.endpoint || !sub.keys || !sub.keys.p256dh || !sub.keys.auth) return res.status(400).json({ error: 'Suscripción no válida.' });
      if (req.auth.role !== 'asesor' && req.auth.role !== 'admin') return res.status(403).json({ error: 'Solo administradores y asesores reciben notificaciones.' });
      const db = getDb();
      db.pushSubscriptions = (db.pushSubscriptions || []).filter(s => s.endpoint !== sub.endpoint);
      db.pushSubscriptions.push({
        id: `ps-${Date.now()}`, endpoint: sub.endpoint, keys: { p256dh: sub.keys.p256dh, auth: sub.keys.auth },
        userKind: req.auth.role, userId: req.auth.record.id, companyId: req.auth.role === 'asesor' ? req.auth.record.companyId : req.auth.record.id,
        createdAt: new Date().toISOString()
      });
      saveDB();
      res.json({ ok: true });
    });

    app.post('/api/push/unsubscribe', (req, res) => {
      const endpoint = (req.body || {}).endpoint;
      const db = getDb();
      db.pushSubscriptions = (db.pushSubscriptions || []).filter(s => s.endpoint !== endpoint || s.userId !== req.auth.record.id);
      saveDB();
      res.json({ ok: true });
    });
  }

  return { registerRoutes, start, run, buildAlerts };
};
