// backend/agilService.js
// Pagos para AGIL: consulta de abonos/pagos legalizados por el administrador, Excel para subir a AGIL,
// envío programado por WhatsApp y lectura del Excel devuelto ("..._SUBIDO.xlsx") para cambiar el estado.
//
// Estado AGIL de cada pago (abono.agil): { status: 'PENDIENTE' | 'SUBIDO', batchId, batchNumber, uploadedAt, source, file }
// Lotes: db.agilBatches. Configuración por empresa: company.agilConfig.

const ExcelJS = require('exceljs');

const PENDING = 'PENDIENTE';
const UPLOADED = 'SUBIDO';
const MAX_BATCHES = 200;
const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const RETRY_AFTER_ERROR_MS = 10 * 60 * 1000;

const SAMPLE_COLUMNS = [
  ['ID PAGO', 34],
  ['LOTE', 8],
  ['FECHA PAGO', 13],
  ['FECHA TRANSFERENCIA', 14],
  ['N° BOLETA', 16],
  ['COMPRADOR', 26],
  ['ASESOR', 22],
  ['VALOR', 14],
  ['MÉTODO', 15],
  ['BANCO ORIGEN', 18],
  ['CUENTA DESTINO', 30],
  ['REFERENCIA / APROBACIÓN', 22],
  ['ESTADO EN CAJA', 15],
  ['LINK SOPORTE', 18],
  ['ESTADO AGIL', 14]
];

function defaultConfig() {
  return {
    enabled: false,
    phone: '',
    mode: 'DAILY', // DAILY | WEEKLY | EVERY_HOURS
    time: '18:00', // hora de Colombia (DAILY y WEEKLY)
    days: [1, 2, 3, 4, 5], // 0 = domingo … 6 = sábado (WEEKLY)
    everyHours: 6, // EVERY_HOURS
    resendSent: false, // reenviar pagos ya enviados que siguen PENDIENTES
    lastRunAt: null,
    lastRunDay: null,
    lastAttemptAt: null,
    lastError: ''
  };
}

module.exports = function createAgilService(deps) {
  const {
    getDb, saveDB, isReady, whatsappService, isAbonoSettled, abonoCashState, soporteLinkFor,
    actorName, colombiaDay, colombiaOffsetMs, baseUrl, getInstanceName, auditPush, accountLabel, uploadProof
  } = deps;

  const idOf = (ticket, abono) => `${ticket.id}~${abono.id}`;
  const agilOf = abono => (abono.agil && abono.agil.status ? abono.agil : { status: PENDING });
  const methodLabel = abono => (abono.metodoPago === 'transferencia' ? 'TRANSFERENCIA' : 'EFECTIVO');
  const dayOf = iso => (iso && !isNaN(Date.parse(iso)) ? colombiaDay(Date.parse(iso)) : '');
  const numbersOf = t => (Array.isArray(t.numbers) && t.numbers.length ? t.numbers.join(' - ') : String(t.ticketNumber || ''));
  const norm = s => String(s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/\s+/g, ' ').trim();
  /** Una transferencia pertenece a la cuenta que figura como destino; sin cuenta registrada va a su propio grupo. */
  const accountKeyOf = abono => norm(abono.cuentaDestino) || 'sin-cuenta';

  function getConfig(company) {
    const saved = (company && company.agilConfig) || {};
    return { ...defaultConfig(), ...saved, days: Array.isArray(saved.days) ? saved.days : defaultConfig().days };
  }

  function sanitizeConfig(input, company) {
    const prev = getConfig(company);
    if (!input || typeof input !== 'object') return { error: 'Configuración inválida.' };
    const next = { ...prev };
    if (input.enabled !== undefined) next.enabled = input.enabled === true;
    if (input.phone !== undefined) {
      const digits = String(input.phone || '').replace(/[^\d]/g, '');
      if (digits && (digits.length < 10 || digits.length > 15)) return { error: 'El número de WhatsApp no es válido (use el indicativo, ej: 573001234567).' };
      next.phone = digits;
    }
    if (input.mode !== undefined) {
      if (!['DAILY', 'WEEKLY', 'EVERY_HOURS'].includes(input.mode)) return { error: 'Frecuencia no válida.' };
      next.mode = input.mode;
    }
    if (input.time !== undefined) {
      if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(String(input.time))) return { error: 'Hora inválida (use HH:MM, formato 24 horas).' };
      next.time = String(input.time);
    }
    if (input.days !== undefined) {
      const days = [...new Set((Array.isArray(input.days) ? input.days : []).map(Number).filter(d => Number.isInteger(d) && d >= 0 && d <= 6))].sort();
      if (!days.length) return { error: 'Elija al menos un día de la semana.' };
      next.days = days;
    }
    if (input.everyHours !== undefined) {
      const hours = parseInt(input.everyHours, 10);
      if (!(hours >= 1 && hours <= 168)) return { error: 'Cada cuántas horas: entre 1 y 168.' };
      next.everyHours = hours;
    }
    if (input.resendSent !== undefined) next.resendSent = input.resendSent === true;
    if (next.enabled && !next.phone) return { error: 'Para activar el envío automático indique el número de WhatsApp de destino.' };
    return { config: next };
  }

  // ------------------------------------------------------------------ consulta
  function companyRaffles(db, companyId) {
    return new Map((db.raffles || []).filter(r => r.companyId === companyId).map(r => [r.id, r]));
  }

  /** Todos los pagos (abonos con valor) de la empresa que cumplen los filtros. */
  function collectRows(db, company, f = {}) {
    const raffles = companyRaffles(db, company.id);
    const q = norm(f.q);
    const rows = [];
    for (const ticket of db.tickets || []) {
      const raffle = raffles.get(ticket.raffleId);
      if (!raffle) continue;
      if (f.raffleId && ticket.raffleId !== f.raffleId) continue;
      for (const abono of ticket.abonos || []) {
        if ((Number(abono.amount) || 0) <= 0) continue;
        const day = dayOf(abono.date);
        if (f.from && day < f.from) continue;
        if (f.to && day > f.to) continue;
        const agil = agilOf(abono).status;
        if (f.agil && agil !== f.agil) continue;
        const method = methodLabel(abono);
        if (f.method && method !== f.method) continue;
        const settled = isAbonoSettled(abono);
        if (f.settled === 'SI' && !settled) continue;
        if (f.settled === 'NO' && settled) continue;
        if (f.advisorId && abono.sellerId !== f.advisorId) continue;
        if (f.bank && norm(abono.originBank) !== norm(f.bank)) continue;
        if (f.account && !(method === 'TRANSFERENCIA' && accountKeyOf(abono) === f.account)) continue;
        if (q) {
          const hay = norm([ticket.buyerName, numbersOf(ticket), abono.approvalNumber, abono.originBank, abono.cuentaDestino, abono.sellerName, ticket.buyerPhone].join(' '));
          if (!hay.includes(q)) continue;
        }
        rows.push({ ticket, abono, raffle, settled });
      }
    }
    rows.sort((a, b) => String(b.abono.date).localeCompare(String(a.abono.date)));
    return rows;
  }

  const isEligible = row => row.settled && agilOf(row.abono).status !== UPLOADED;

  function toApi(row) {
    const { ticket, abono, raffle } = row;
    const agil = agilOf(abono);
    return {
      id: idOf(ticket, abono),
      ticketId: ticket.id,
      abonoId: abono.id,
      raffleId: raffle.id,
      raffleTitle: raffle.title,
      date: abono.date,
      transferDate: abono.transferDate || null,
      numbers: ticket.numbers || [],
      ticketNumber: ticket.ticketNumber,
      buyerName: ticket.buyerName || '',
      advisorName: abono.sellerName || ticket.advisorName || '',
      amount: Number(abono.amount) || 0,
      method: methodLabel(abono),
      originBank: abono.originBank || '',
      cuentaDestino: abono.cuentaDestino || '',
      approvalNumber: abono.approvalNumber || '',
      cashState: abonoCashState(abono),
      settled: row.settled,
      hasSupport: !!(abono.soporteDriveId || abono.soporteWebViewUrl || abono.soporteUrl),
      soporteLink: (abono.soporteDriveId || abono.soporteWebViewUrl || abono.soporteUrl) ? soporteLinkFor(ticket.id, abono.id) : '',
      agilStatus: agil.status,
      batchNumber: agil.batchNumber || null,
      uploadedAt: agil.uploadedAt || null
    };
  }

  // ------------------------------------------------------------------ resumen por cuenta
  const CASH_KEY = 'efectivo';
  const emptyBucket = () => ({ amount: 0, count: 0 });
  const addTo = (bucket, amount) => { bucket.amount += amount; bucket.count += 1; };

  /**
   * Por cada cuenta de transferencia: total, legalizado (validado en Caja) y por legalizar. Y el efectivo:
   * recibido por el administrador vs. en poder de cada asesor. Rechazadas aparte (no suman al total).
   */
  function summarize(db, company, f = {}) {
    const accounts = new Map();
    const ensure = (key, label) => {
      if (!accounts.has(key)) accounts.set(key, { key, label, total: 0, count: 0, legalized: emptyBucket(), pending: emptyBucket(), rejected: emptyBucket(), uploaded: emptyBucket(), expenses: emptyBucket(), balance: 0 });
      return accounts.get(key);
    };
    // Las cuentas configuradas en las rifas aparecen aunque todavía no tengan movimiento
    if (accountLabel) {
      for (const raffle of companyRaffles(db, company.id).values()) {
        if (f.raffleId && raffle.id !== f.raffleId) continue;
        for (const acc of raffle.transferAccounts || []) {
          const label = accountLabel(acc);
          if (norm(label)) ensure(norm(label), label);
        }
      }
    }
    const cash = { total: 0, count: 0, legalized: emptyBucket(), pending: emptyBucket(), uploaded: emptyBucket(), expenses: emptyBucket(), balance: 0, advisorExpenses: 0, netPending: 0, byAdvisor: new Map() };
    const rows = collectRows(db, company, { from: f.from, to: f.to, raffleId: f.raffleId });
    for (const { abono, settled } of rows) {
      const amount = Number(abono.amount) || 0;
      const isUploaded = settled && agilOf(abono).status === UPLOADED;
      if (abono.metodoPago === 'transferencia') {
        const key = accountKeyOf(abono);
        const acc = ensure(key, (abono.cuentaDestino || '').trim() || 'Sin cuenta registrada');
        if (abono.verification && abono.verification.status === 'RECHAZADA') { addTo(acc.rejected, amount); continue; }
        addTo(settled ? acc.legalized : acc.pending, amount);
        acc.total += amount; acc.count += 1;
        if (isUploaded) addTo(acc.uploaded, amount);
      } else {
        addTo(settled ? cash.legalized : cash.pending, amount);
        cash.total += amount; cash.count += 1;
        if (isUploaded) addTo(cash.uploaded, amount);
        const name = abono.sellerName || 'Administrador';
        const advKey = abono.sellerId || `n:${name}`;
        if (!cash.byAdvisor.has(advKey)) cash.byAdvisor.set(advKey, { id: abono.sellerId || null, name, total: 0, legalized: 0, pending: 0, pendingCount: 0, expenses: 0, expensesCount: 0, toDeliver: 0 });
        const adv = cash.byAdvisor.get(advKey);
        adv.total += amount;
        if (settled) adv.legalized += amount; else { adv.pending += amount; adv.pendingCount += 1; }
      }
    }
    // Gastos de cada cuenta o del efectivo. Con filtro de rifa solo cuentan los de las cuentas de esa rifa (el efectivo no es de una rifa)
    {
      for (const e of db.expenses || []) {
        if (e.companyId !== company.id || e.voided) continue;
        if (f.from && e.date < f.from) continue;
        if (f.to && e.date > f.to) continue;
        if (f.raffleId && (e.account === CASH_KEY || !accounts.has(e.account))) continue;
        // Gasto en efectivo de un asesor que aún no se concilia con el administrador: reduce lo que ese asesor debe entregar
        if (e.account === CASH_KEY && e.advisorId && !e.applied) {
          const key = e.advisorId;
          if (!cash.byAdvisor.has(key)) cash.byAdvisor.set(key, { id: e.advisorId, name: e.advisorName || 'Asesor', total: 0, legalized: 0, pending: 0, pendingCount: 0, expenses: 0, expensesCount: 0, toDeliver: 0 });
          const adv = cash.byAdvisor.get(key);
          adv.expenses += e.amount; adv.expensesCount += 1;
          cash.advisorExpenses += e.amount;
        } else if (e.account === CASH_KEY) addTo(cash.expenses, e.amount);
        else addTo(ensure(e.account, e.accountLabel || e.account).expenses, e.amount);
      }
    }
    for (const adv of cash.byAdvisor.values()) adv.toDeliver = adv.pending - adv.expenses;
    cash.netPending = cash.pending.amount - cash.advisorExpenses;
    // Saldo que debe haber = lo legalizado menos los gastos
    for (const a of accounts.values()) a.balance = a.legalized.amount - a.expenses.amount;
    cash.balance = cash.legalized.amount - cash.expenses.amount;

    const list = [...accounts.values()].sort((a, b) => b.total - a.total || a.label.localeCompare(b.label));
    const grand = { total: 0, legalized: 0, pending: 0, expenses: 0, balance: 0 };
    for (const a of list) { grand.total += a.total; grand.legalized += a.legalized.amount; grand.pending += a.pending.amount; grand.expenses += a.expenses.amount; }
    grand.total += cash.total; grand.legalized += cash.legalized.amount; grand.pending += cash.pending.amount; grand.expenses += cash.expenses.amount;
    grand.balance = grand.legalized - grand.expenses;
    return {
      accounts: list,
      cash: { ...cash, byAdvisor: [...cash.byAdvisor.values()].sort((a, b) => b.toDeliver - a.toDeliver || b.pending - a.pending || b.total - a.total) },
      grand
    };
  }

  // ------------------------------------------------------------------ Excel
  async function buildWorkbook(rows, meta = {}) {
    const wb = new ExcelJS.Workbook();
    wb.creator = 'Rifa Master';
    wb.created = new Date();
    const ws = wb.addWorksheet('Pagos', { views: [{ state: 'frozen', ySplit: 1 }] });
    ws.columns = SAMPLE_COLUMNS.map(([header, width]) => ({ header, key: header, width }));
    const head = ws.getRow(1);
    head.font = { bold: true, color: { argb: 'FFFFFFFF' } };
    head.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF1D4ED8' } };
    head.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
    head.height = 30;

    let total = 0;
    for (const row of rows) {
      const api = toApi(row);
      total += api.amount;
      const r = ws.addRow({
        'ID PAGO': api.id,
        'LOTE': meta.batchNumber || api.batchNumber || '',
        'FECHA PAGO': api.date ? new Date(api.date) : '',
        'FECHA TRANSFERENCIA': api.transferDate ? new Date(api.transferDate) : '',
        'N° BOLETA': api.numbers.join(' - ') || String(api.ticketNumber || ''),
        'COMPRADOR': api.buyerName,
        'ASESOR': api.advisorName,
        'VALOR': api.amount,
        'MÉTODO': api.method,
        'BANCO ORIGEN': api.originBank,
        'CUENTA DESTINO': api.cuentaDestino,
        'REFERENCIA / APROBACIÓN': api.approvalNumber,
        'ESTADO EN CAJA': api.cashState,
        'LINK SOPORTE': api.soporteLink ? { text: 'Ver soporte', hyperlink: api.soporteLink } : 'Sin soporte',
        'ESTADO AGIL': api.agilStatus
      });
      if (api.soporteLink) r.getCell('LINK SOPORTE').font = { color: { argb: 'FF1D4ED8' }, underline: true };
    }
    ws.getColumn('FECHA PAGO').numFmt = 'dd/mm/yyyy hh:mm';
    ws.getColumn('FECHA TRANSFERENCIA').numFmt = 'dd/mm/yyyy';
    ws.getColumn('VALOR').numFmt = '"$"#,##0';
    const totalRow = ws.addRow({ 'COMPRADOR': 'TOTAL', 'VALOR': total });
    totalRow.font = { bold: true };
    totalRow.getCell('VALOR').numFmt = '"$"#,##0';
    ws.autoFilter = { from: { row: 1, column: 1 }, to: { row: 1, column: SAMPLE_COLUMNS.length } };

    const info = wb.addWorksheet('Instrucciones');
    info.getColumn(1).width = 110;
    [
      `Lote ${meta.batchNumber || ''} — ${rows.length} pagos — total $${Math.round(total).toLocaleString('es-CO')}`,
      '',
      'Pagos legalizados por el administrador (transferencias validadas y efectivo recibido) para subir a AGIL.',
      'Cuando estén subidos en AGIL, devuelva ESTE MISMO ARCHIVO por WhatsApp agregando SUBIDO al nombre,',
      'por ejemplo: AGIL_lote-0003_2026-11-07_SUBIDO.xlsx — el sistema marca todos los pagos del archivo como SUBIDO.',
      'No cambie ni borre la columna "ID PAGO": con ella se identifica cada pago.'
    ].forEach((line, i) => { info.getCell(i + 1, 1).value = line; });
    info.getCell(1, 1).font = { bold: true };
    return Buffer.from(await wb.xlsx.writeBuffer());
  }

  const fileNameFor = batch => `AGIL_lote-${String(batch.number).padStart(4, '0')}_${batch.createdAt.slice(0, 10)}.xlsx`;

  // ------------------------------------------------------------------ lotes
  function createBatch(db, company, rows, by) {
    company.agilBatchSeq = (company.agilBatchSeq || 0) + 1;
    const batch = {
      id: `agil-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 5)}`,
      number: company.agilBatchSeq,
      companyId: company.id,
      createdAt: new Date().toISOString(),
      by,
      count: rows.length,
      total: rows.reduce((s, r) => s + (Number(r.abono.amount) || 0), 0),
      rowIds: rows.map(r => idOf(r.ticket, r.abono)),
      status: 'GENERADO', // GENERADO → ENVIADO → SUBIDO (o ERROR_ENVIO)
      sentTo: '',
      sentAt: null,
      uploadedAt: null,
      error: ''
    };
    batch.fileName = fileNameFor(batch);
    for (const r of rows) {
      r.abono.agil = { status: PENDING, batchId: batch.id, batchNumber: batch.number };
    }
    if (!Array.isArray(db.agilBatches)) db.agilBatches = [];
    db.agilBatches.unshift(batch);
    if (db.agilBatches.length > MAX_BATCHES) db.agilBatches.length = MAX_BATCHES;
    return batch;
  }

  function rowsOfBatch(db, company, batch) {
    const wanted = new Set(batch.rowIds || []);
    return collectRows(db, company, {}).filter(r => wanted.has(idOf(r.ticket, r.abono)));
  }

  /** Pagos que aún no se han subido (y por defecto, que no se han enviado antes). */
  function pendingRows(db, company, { from, to, includeSent = false } = {}) {
    return collectRows(db, company, { from, to }).filter(r => isEligible(r) && (includeSent || !agilOf(r.abono).batchId));
  }

  async function sendBatch(db, company, batch, phone) {
    const rows = rowsOfBatch(db, company, batch);
    const buffer = await buildWorkbook(rows, { batchNumber: batch.number });
    const instance = getInstanceName({ role: 'admin', record: company });
    const caption =
      `📊 *Pagos para AGIL — lote ${batch.number}*\n` +
      `${batch.count} pagos • $${Math.round(batch.total).toLocaleString('es-CO')}\n\n` +
      `Cuando estén subidos en AGIL, devuélvame *este mismo archivo* agregando *SUBIDO* al nombre ` +
      `(ej: ${batch.fileName.replace('.xlsx', '_SUBIDO.xlsx')}) y los marco como subidos.`;
    const res = await whatsappService.sendDocument(instance, phone, { buffer, fileName: batch.fileName, caption, mimetype: XLSX_MIME });
    if (!res.ok) {
      batch.status = 'ERROR_ENVIO';
      batch.error = `No se pudo enviar por WhatsApp (${res.status || ''} ${typeof res.data === 'string' ? res.data : JSON.stringify(res.data || res.error || '')}`.slice(0, 220) + ')';
      return { ok: false, error: batch.error };
    }
    batch.status = 'ENVIADO';
    batch.sentTo = phone;
    batch.sentAt = new Date().toISOString();
    batch.error = '';
    return { ok: true };
  }

  /** Genera el lote de pendientes y lo envía al número configurado. */
  async function runBatch(company, { by = 'programado', force = false } = {}) {
    const db = getDb();
    const cfg = getConfig(company);
    company.agilConfig = cfg;
    const now = Date.now();
    cfg.lastAttemptAt = new Date(now).toISOString();
    if (!cfg.phone) {
      cfg.lastError = 'No hay número de WhatsApp configurado.';
      saveDB();
      return { ok: false, error: cfg.lastError };
    }
    const rows = pendingRows(db, company, { includeSent: cfg.resendSent });
    if (!rows.length) {
      cfg.lastRunAt = new Date(now).toISOString();
      cfg.lastRunDay = colombiaDay(now);
      cfg.lastError = '';
      saveDB();
      return { ok: true, empty: true, message: 'No hay pagos legalizados pendientes de enviar.' };
    }
    const batch = createBatch(db, company, rows, by);
    const sent = await sendBatch(db, company, batch, cfg.phone);
    if (sent.ok) {
      cfg.lastRunAt = new Date(now).toISOString();
      cfg.lastRunDay = colombiaDay(now);
      cfg.lastError = '';
    } else {
      cfg.lastError = sent.error;
    }
    if (auditPush) auditPush({ type: 'AGIL_LOTE', companyId: company.id, targetId: batch.id, targetName: `Lote ${batch.number}`, detail: `${by}: ${batch.count} pagos, $${Math.round(batch.total)} → ${sent.ok ? 'enviado a ' + cfg.phone : 'ERROR ' + sent.error}`, by });
    saveDB();
    return { ok: sent.ok, batch, error: sent.error };
  }

  // ------------------------------------------------------------------ cron
  function isDue(cfg, nowMs) {
    if (!cfg.enabled || !cfg.phone) return false;
    if (cfg.lastAttemptAt && cfg.lastError && nowMs - Date.parse(cfg.lastAttemptAt) < RETRY_AFTER_ERROR_MS) return false;
    if (cfg.mode === 'EVERY_HOURS') {
      return !cfg.lastRunAt || nowMs - Date.parse(cfg.lastRunAt) >= cfg.everyHours * 3600 * 1000;
    }
    const local = new Date(nowMs - colombiaOffsetMs()); // se lee con getUTC*: hora de Colombia
    const hhmm = `${String(local.getUTCHours()).padStart(2, '0')}:${String(local.getUTCMinutes()).padStart(2, '0')}`;
    if (cfg.lastRunDay === colombiaDay(nowMs)) return false;
    if (cfg.mode === 'WEEKLY' && !cfg.days.includes(local.getUTCDay())) return false;
    return hhmm >= cfg.time;
  }

  let ticking = false;
  async function tick() {
    if (ticking || !isReady()) return;
    ticking = true;
    try {
      const db = getDb();
      for (const company of db.companies || []) {
        const cfg = getConfig(company);
        if (isDue(cfg, Date.now())) {
          const res = await runBatch(company, { by: 'programado' });
          console.log(`📊 [AGIL] ${company.name || company.id}: ${res.ok ? (res.empty ? 'sin pagos pendientes' : `lote ${res.batch.number} enviado`) : 'ERROR ' + res.error}`);
        }
      }
    } catch (err) {
      console.error('⚠️ [AGIL] Error en el envío programado:', err.message);
    } finally {
      ticking = false;
    }
  }

  function start() {
    setInterval(() => { tick(); }, 60 * 1000);
  }

  // ------------------------------------------------------------------ Excel devuelto
  /** Marca como SUBIDO los pagos del archivo devuelto. El nombre con "subido" marca todos; si no, solo las filas con ESTADO AGIL = SUBIDO. */
  async function applyReturnedWorkbook(db, company, buffer, fileName, source, by) {
    const wb = new ExcelJS.Workbook();
    await wb.xlsx.load(buffer);
    const ws = wb.getWorksheet('Pagos') || wb.worksheets[0];
    if (!ws) return { error: 'El archivo no tiene hojas.' };
    let headerRow = 0;
    let idCol = 0;
    let statusCol = 0;
    for (let r = 1; r <= Math.min(5, ws.rowCount) && !idCol; r++) {
      ws.getRow(r).eachCell((cell, col) => {
        const text = norm(cell.text).trim();
        if (text === 'id pago') { idCol = col; headerRow = r; }
      });
    }
    if (!idCol) return { error: 'No encuentro la columna "ID PAGO". Use el archivo que se envió, sin cambiar las columnas.' };
    ws.getRow(headerRow).eachCell((cell, col) => { if (norm(cell.text).trim() === 'estado agil') statusCol = col; });

    const markAll = /subido/i.test(fileName || '');
    const index = new Map();
    const raffles = companyRaffles(db, company.id);
    for (const t of db.tickets || []) {
      if (!raffles.has(t.raffleId)) continue;
      for (const a of t.abonos || []) index.set(idOf(t, a), a);
    }

    const result = { marked: 0, already: 0, notFound: 0, skipped: 0, batches: 0 };
    const touchedBatches = new Set();
    const now = new Date().toISOString();
    for (let r = headerRow + 1; r <= ws.rowCount; r++) {
      const id = String(ws.getRow(r).getCell(idCol).text || '').trim();
      if (!id || !id.includes('~')) continue;
      const status = statusCol ? String(ws.getRow(r).getCell(statusCol).text || '').trim().toUpperCase() : '';
      const abono = index.get(id);
      if (!abono) { result.notFound++; continue; }
      if (agilOf(abono).status === UPLOADED) { result.already++; continue; }
      if (!markAll && status !== UPLOADED) { result.skipped++; continue; }
      const prev = agilOf(abono);
      abono.agil = { status: UPLOADED, batchId: prev.batchId || null, batchNumber: prev.batchNumber || null, uploadedAt: now, source, file: fileName || '' , by };
      if (prev.batchId) touchedBatches.add(prev.batchId);
      result.marked++;
    }
    // Un lote queda SUBIDO cuando todos sus pagos lo están
    for (const batch of db.agilBatches || []) {
      if (batch.companyId !== company.id || batch.status === UPLOADED) continue;
      if (!touchedBatches.has(batch.id) && !(new RegExp(`lote-0*${batch.number}\\b`, 'i').test(fileName || ''))) continue;
      const allDone = (batch.rowIds || []).every(id => { const a = index.get(id); return !a || agilOf(a).status === UPLOADED; });
      if (allDone) { batch.status = UPLOADED; batch.uploadedAt = now; result.batches++; }
    }
    if (result.marked && auditPush) {
      auditPush({ type: 'AGIL_SUBIDO', companyId: company.id, targetId: fileName || 'manual', targetName: 'Pagos AGIL', detail: `${result.marked} pagos marcados como SUBIDO (${source}) desde ${fileName || 'archivo'}`, by });
    }
    saveDB();
    return { result };
  }

  const companyOfInstance = (db, instance) => {
    const match = /^empresa_(.+)$/.exec(String(instance || ''));
    if (!match) return null;
    const code = match[1];
    return (db.companies || []).find(c =>
      (c.code && String(c.code).toLowerCase().replace(/[^a-z0-9_]/g, '') === code) ||
      String(c.id).toLowerCase().replace(/[^a-z0-9_]/g, '') === code ||
      (c.name && c.name.toLowerCase().replace(/[^a-z0-9_]/g, '') === code)
    ) || null;
  };

  /** Documento recibido por WhatsApp: solo se atiende un .xlsx enviado por el número configurado. */
  async function handleIncomingDocument({ instance, senderPhone, fileName, base64 }) {
    const db = getDb();
    const company = companyOfInstance(db, instance);
    if (!company) return { handled: false };
    const cfg = getConfig(company);
    if (!cfg.phone || whatsappService.formatPhoneNumber(cfg.phone) !== whatsappService.formatPhoneNumber(senderPhone)) return { handled: false };
    if (!/\.xlsx?$/i.test(fileName || '')) return { handled: false };
    const reply = text => whatsappService.sendTextMessage(instance, senderPhone, text).catch(() => {});
    if (!base64) {
      await reply('⚠️ Recibí el archivo pero no pude descargarlo. Envíelo de nuevo, por favor.');
      return { handled: true };
    }
    try {
      const buffer = Buffer.from(String(base64).replace(/^data:[^;]+;base64,/, ''), 'base64');
      const out = await applyReturnedWorkbook(db, company, buffer, fileName, 'WHATSAPP', `WhatsApp ${senderPhone}`);
      if (out.error) { await reply(`⚠️ ${out.error}`); return { handled: true }; }
      const r = out.result;
      if (!/subido/i.test(fileName) && !r.marked) {
        await reply(`ℹ️ Recibí *${fileName}* pero no lo marqué: agregue *SUBIDO* al nombre del archivo (ej: ${fileName.replace(/\.xlsx?$/i, '')}_SUBIDO.xlsx) para marcar todos los pagos como subidos.`);
        return { handled: true };
      }
      await reply(`✅ *${fileName}*\n${r.marked} pagos marcados como *SUBIDO* en AGIL${r.already ? `\n${r.already} ya estaban subidos` : ''}${r.notFound ? `\n⚠️ ${r.notFound} no se encontraron (¿archivo de otro sistema?)` : ''}${r.batches ? `\n📦 ${r.batches} lote(s) completo(s)` : ''}`);
    } catch (err) {
      console.error('⚠️ [AGIL] No se pudo leer el Excel devuelto:', err.message);
      await reply('⚠️ No pude leer el archivo. Verifique que sea el Excel original (.xlsx).');
    }
    return { handled: true };
  }

  // ------------------------------------------------------------------ rutas del administrador
  function registerRoutes(app, { adminOnly, targetCompanyOf }) {
    const need = (req, res) => {
      // Un asesor (con permiso) trabaja siempre con la empresa a la que pertenece
      const company = req.auth && req.auth.role === 'asesor'
        ? (getDb().companies || []).find(c => c.id === req.auth.record.companyId)
        : targetCompanyOf(req);
      if (!company) res.status(400).json({ error: 'Seleccione la empresa.' });
      return company;
    };
    // kind: 'view' (ver la caja) | 'register' (registrar gastos) | 'list' (cualquiera de las dos)
    const cashAccess = kind => (req, res, next) => {
      const role = req.auth && req.auth.role;
      if (role === 'admin' || role === 'superadmin') return next();
      if (role === 'asesor') {
        const adv = (getDb().advisors || []).find(a => a.id === req.auth.record.id);
        const canSeePayments = adv && Array.isArray(adv.menuAccess) && adv.menuAccess.includes('pagos');
        const ok = adv && adv.status !== 'INHABILITADO' &&
          ((kind === 'view' && (adv.canViewCash || canSeePayments)) || (kind === 'register' && adv.canRegisterExpenses) || (kind === 'list' && (adv.canViewCash || adv.canRegisterExpenses || canSeePayments)));
        if (ok) return next();
      }
      return res.status(403).json({ error: 'No tiene permiso para esta acción.' });
    };
    const myAdvisor = req => (req.auth && req.auth.role === 'asesor' ? (getDb().advisors || []).find(a => a.id === req.auth.record.id) : null);
    const filtersOf = q => ({
      from: /^\d{4}-\d{2}-\d{2}$/.test(q.from || '') ? q.from : '',
      to: /^\d{4}-\d{2}-\d{2}$/.test(q.to || '') ? q.to : '',
      agil: [PENDING, UPLOADED].includes(q.agil) ? q.agil : '',
      method: ['TRANSFERENCIA', 'EFECTIVO'].includes(q.method) ? q.method : '',
      settled: ['SI', 'NO'].includes(q.settled) ? q.settled : '',
      advisorId: q.advisorId || '',
      raffleId: q.raffleId || '',
      bank: q.bank || '',
      account: String(q.account || '').slice(0, 120),
      q: String(q.q || '').slice(0, 80)
    });
    const sendFile = (res, buffer, name) => {
      res.setHeader('Content-Type', XLSX_MIME);
      res.setHeader('Content-Disposition', `attachment; filename="${name}"`);
      res.send(buffer);
    };

    // Solo lectura de «Pagos y abonos»: el administrador o un asesor al que se le dio esa parte del menú
    const paymentsAccess = (req, res, next) => {
      const role = req.auth && req.auth.role;
      if (role === 'admin' || role === 'superadmin') return next();
      const adv = myAdvisor(req);
      if (adv && adv.status !== 'INHABILITADO' && Array.isArray(adv.menuAccess) && adv.menuAccess.includes('pagos')) return next();
      return res.status(403).json({ error: 'No tiene permiso para esta acción.' });
    };
    app.get('/api/agil/payments', paymentsAccess, (req, res) => {
      const company = need(req, res);
      if (!company) return;
      const rows = collectRows(getDb(), company, filtersOf(req.query));
      const sum = list => list.reduce((s, r) => s + (Number(r.abono.amount) || 0), 0);
      res.json({
        total: rows.length,
        payments: rows.slice(0, 1500).map(toApi),
        truncated: rows.length > 1500,
        totals: {
          amount: sum(rows),
          pending: { count: rows.filter(r => agilOf(r.abono).status !== UPLOADED).length, amount: sum(rows.filter(r => agilOf(r.abono).status !== UPLOADED)) },
          uploaded: { count: rows.filter(r => agilOf(r.abono).status === UPLOADED).length, amount: sum(rows.filter(r => agilOf(r.abono).status === UPLOADED)) },
          readyToSend: rows.filter(r => isEligible(r) && !agilOf(r.abono).batchId).length
        }
      });
    });

    // ---- Gastos: lo que se gastó de una cuenta o del efectivo (para que el saldo cuadre) ----
    const expenseView = e => ({ id: e.id, account: e.account, accountLabel: e.accountLabel, amount: e.amount, date: e.date, reason: e.reason, advisorName: e.advisorName || null, applied: e.applied || null, hasSupport: !!(e.soporteDriveId || e.soporteWebViewUrl), soporteDriveId: e.soporteDriveId || null, soporteWebViewUrl: e.soporteWebViewUrl || null, createdBy: e.createdBy, createdAt: e.createdAt, voided: e.voided || null });

    app.get('/api/agil/expenses', cashAccess('list'), (req, res) => {
      const company = need(req, res);
      if (!company) return;
      const f = filtersOf(req.query);
      const account = String(req.query.account || '').slice(0, 120);
      const me = myAdvisor(req);
      // Un asesor que solo registra gastos ve únicamente los suyos; con permiso de ver la caja ve todos
      const onlyMine = me && !me.canViewCash;
      const list = (getDb().expenses || [])
        .filter(e => e.companyId === company.id && (!onlyMine || e.advisorId === me.id) && (!account || e.account === account) && (!f.from || e.date >= f.from) && (!f.to || e.date <= f.to))
        .sort((a, b) => String(b.date).localeCompare(String(a.date)) || String(b.createdAt).localeCompare(String(a.createdAt)));
      const pendingMine = me ? unappliedCashExpenses(me.id) : [];
      res.json({
        expenses: list.slice(0, 500).map(expenseView),
        total: list.filter(e => !e.voided).reduce((s, e) => s + e.amount, 0),
        // Gastos en efectivo del asesor por justificar con el administrador (se descuentan de lo que entrega)
        pendingTotal: pendingMine.reduce((s, e) => s + e.amount, 0)
      });
    });

    app.post('/api/agil/expenses', cashAccess('register'), async (req, res) => {
      const company = need(req, res);
      if (!company) return;
      const me = myAdvisor(req);
      const body = req.body || {};
      const db = getDb();
      const account = String(body.account || '').slice(0, 120);
      const accountLabel = String(body.accountLabel || '').trim().slice(0, 160);
      const amount = Math.round(Number(body.amount));
      const reason = String(body.reason || '').trim();
      const date = String(body.date || '');
      if (!account || (account !== CASH_KEY && !accountLabel)) return res.status(400).json({ error: 'Seleccione la cuenta o el efectivo.' });
      if (!Number.isFinite(amount) || amount <= 0 || amount > 1000000000) return res.status(400).json({ error: 'El valor del gasto debe ser mayor a 0.' });
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return res.status(400).json({ error: 'Indique la fecha del gasto.' });
      if (date > colombiaDay(Date.now())) return res.status(400).json({ error: 'La fecha del gasto no puede ser posterior a hoy.' });
      if (reason.length < 3 || reason.length > 300) return res.status(400).json({ error: 'Escriba el motivo del gasto (3 a 300 caracteres).' });

      // Foto opcional del gasto (comprobante, factura, recibo)
      let soporte = { soporteDriveId: null, soporteUrl: null, soporteWebViewUrl: null };
      const raw = body.imageBase64;
      if (typeof raw === 'string' && raw.length > 100) {
        if (raw.length > 12 * 1024 * 1024) return res.status(400).json({ error: 'La foto es demasiado grande.' });
        try {
          const buffer = Buffer.from(raw.replace(/^data:image\/\w+;base64,/, ''), 'base64');
          const up = await uploadProof(buffer, `gasto_${colombiaDay(Date.now())}_${Date.now()}.jpg`, 'image/jpeg');
          if (up) soporte = { soporteDriveId: up.fileId, soporteUrl: up.directUrl, soporteWebViewUrl: up.webViewUrl };
        } catch (err) {
          return res.status(502).json({ error: 'No se pudo guardar la foto en Google Drive. Intente de nuevo o registre el gasto sin foto.' });
        }
      }
      if (!Array.isArray(db.expenses)) db.expenses = [];
      const expense = {
        id: `gas-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 5)}`,
        companyId: company.id,
        account,
        accountLabel: account === CASH_KEY ? 'Efectivo' : accountLabel,
        amount, date, reason, ...soporte,
        createdBy: actorName(req),
        ...(me ? { advisorId: me.id, advisorName: me.name } : {}),
        createdAt: new Date().toISOString()
      };
      db.expenses.unshift(expense);
      if (auditPush) auditPush({ type: 'GASTO', companyId: company.id, targetId: expense.id, targetName: expense.accountLabel, detail: `Gasto $${amount} (${date}): ${reason}`, by: expense.createdBy });
      saveDB();
      res.status(201).json({ expense: expenseView(expense) });
    });

    // Un gasto no se borra: se anula con su motivo y deja de restar del saldo
    app.post('/api/agil/expenses/:id/void', adminOnly, (req, res) => {
      const company = need(req, res);
      if (!company) return;
      const expense = (getDb().expenses || []).find(e => e.id === req.params.id && e.companyId === company.id);
      if (!expense) return res.status(404).json({ error: 'Gasto no encontrado.' });
      if (expense.voided) return res.status(400).json({ error: 'Este gasto ya está anulado.' });
      const reason = String((req.body || {}).reason || '').trim();
      if (reason.length < 5) return res.status(400).json({ error: 'Explique por qué anula el gasto (mínimo 5 caracteres).' });
      expense.voided = { by: actorName(req), at: new Date().toISOString(), reason: reason.slice(0, 300) };
      if (auditPush) auditPush({ type: 'GASTO_ANULADO', companyId: company.id, targetId: expense.id, targetName: expense.accountLabel, detail: `Gasto $${expense.amount} anulado: ${reason}`, by: actorName(req) });
      saveDB();
      res.json({ ok: true });
    });

    // Resumen por cuenta (transferencias) y efectivo: total, legalizado y por legalizar
    app.get('/api/agil/summary', cashAccess('view'), (req, res) => {
      const company = need(req, res);
      if (!company) return;
      const f = filtersOf(req.query);
      res.json(summarize(getDb(), company, { from: f.from, to: f.to, raffleId: f.raffleId }));
    });

    // Descarga manual de lo que se ve en pantalla (no cambia nada)
    app.get('/api/agil/export', adminOnly, async (req, res) => {
      const company = need(req, res);
      if (!company) return;
      const rows = collectRows(getDb(), company, filtersOf(req.query));
      const buffer = await buildWorkbook(rows, {});
      sendFile(res, buffer, `Pagos_${colombiaDay(Date.now())}.xlsx`);
    });

    app.get('/api/agil/config', adminOnly, (req, res) => {
      const company = need(req, res);
      if (!company) return;
      res.json({ config: getConfig(company), batches: (getDb().agilBatches || []).filter(b => b.companyId === company.id).slice(0, 30).map(({ rowIds, ...b }) => b) });
    });

    app.put('/api/agil/config', adminOnly, (req, res) => {
      const company = need(req, res);
      if (!company) return;
      const checked = sanitizeConfig(req.body && req.body.config, company);
      if (checked.error) return res.status(400).json({ error: checked.error });
      company.agilConfig = checked.config;
      saveDB();
      res.json({ message: 'Configuración guardada.', config: checked.config });
    });

    // Genera el lote de pendientes y lo deja listo para descargar (sin enviar)
    app.post('/api/agil/batches', adminOnly, async (req, res) => {
      const company = need(req, res);
      if (!company) return;
      const body = req.body || {};
      const db = getDb();
      const rows = pendingRows(db, company, { from: body.from, to: body.to, includeSent: body.includeSent === true });
      if (!rows.length) return res.status(400).json({ error: 'No hay pagos legalizados pendientes para el lote.' });
      const batch = createBatch(db, company, rows, actorName(req));
      saveDB();
      const { rowIds, ...view } = batch;
      res.json({ batch: view });
    });

    app.get('/api/agil/batches/:id/file', adminOnly, async (req, res) => {
      const company = need(req, res);
      if (!company) return;
      const db = getDb();
      const batch = (db.agilBatches || []).find(b => b.id === req.params.id && b.companyId === company.id);
      if (!batch) return res.status(404).json({ error: 'Lote no encontrado.' });
      sendFile(res, await buildWorkbook(rowsOfBatch(db, company, batch), { batchNumber: batch.number }), batch.fileName);
    });

    // Envía un lote existente por WhatsApp (al número configurado)
    app.post('/api/agil/batches/:id/send', adminOnly, async (req, res) => {
      const company = need(req, res);
      if (!company) return;
      const db = getDb();
      const cfg = getConfig(company);
      const batch = (db.agilBatches || []).find(b => b.id === req.params.id && b.companyId === company.id);
      if (!batch) return res.status(404).json({ error: 'Lote no encontrado.' });
      if (!cfg.phone) return res.status(400).json({ error: 'Configure primero el número de WhatsApp de destino.' });
      const sent = await sendBatch(db, company, batch, cfg.phone);
      saveDB();
      if (!sent.ok) return res.status(502).json({ error: sent.error });
      res.json({ ok: true });
    });

    // "Enviar ahora": genera el lote de pendientes y lo envía
    app.post('/api/agil/send-now', adminOnly, async (req, res) => {
      const company = need(req, res);
      if (!company) return;
      const result = await runBatch(company, { by: actorName(req), force: true });
      if (!result.ok) return res.status(502).json({ error: result.error });
      if (result.empty) return res.json({ ok: true, empty: true, message: result.message });
      res.json({ ok: true, batchNumber: result.batch.number, count: result.batch.count });
    });

    app.get('/api/agil/batches', adminOnly, (req, res) => {
      const company = need(req, res);
      if (!company) return;
      res.json({ batches: (getDb().agilBatches || []).filter(b => b.companyId === company.id).slice(0, 100).map(({ rowIds, ...b }) => b) });
    });

    // Cambio manual de estado de pagos puntuales
    app.post('/api/agil/mark', adminOnly, (req, res) => {
      const company = need(req, res);
      if (!company) return;
      const { ids, status } = req.body || {};
      if (![PENDING, UPLOADED].includes(status)) return res.status(400).json({ error: 'Estado no válido.' });
      if (!Array.isArray(ids) || !ids.length || ids.length > 2000) return res.status(400).json({ error: 'Seleccione los pagos.' });
      const db = getDb();
      const wanted = new Set(ids.map(String));
      const now = new Date().toISOString();
      let changed = 0;
      for (const row of collectRows(db, company, {})) {
        if (!wanted.has(idOf(row.ticket, row.abono))) continue;
        const prev = agilOf(row.abono);
        if (prev.status === status) continue;
        row.abono.agil = status === UPLOADED
          ? { ...prev, status: UPLOADED, uploadedAt: now, source: 'MANUAL', by: actorName(req) }
          : { status: PENDING, batchId: prev.batchId || null, batchNumber: prev.batchNumber || null };
        changed++;
      }
      if (changed && auditPush) auditPush({ type: 'AGIL_MARCA', companyId: company.id, targetId: 'manual', targetName: 'Pagos AGIL', detail: `${changed} pagos marcados como ${status} manualmente`, by: actorName(req) });
      saveDB();
      res.json({ ok: true, changed });
    });

    // Excel devuelto cargado desde la app
    app.post('/api/agil/upload', adminOnly, async (req, res) => {
      const company = need(req, res);
      if (!company) return;
      const { fileName, base64 } = req.body || {};
      if (!base64) return res.status(400).json({ error: 'Falta el archivo.' });
      try {
        const buffer = Buffer.from(String(base64).replace(/^data:[^;]+;base64,/, ''), 'base64');
        const out = await applyReturnedWorkbook(getDb(), company, buffer, String(fileName || 'manual_SUBIDO.xlsx'), 'MANUAL', actorName(req));
        if (out.error) return res.status(400).json({ error: out.error });
        res.json({ ok: true, ...out.result });
      } catch (err) {
        res.status(400).json({ error: 'No se pudo leer el archivo. Verifique que sea el Excel original (.xlsx).' });
      }
    });
  }

  /** Gastos en efectivo de un asesor que aún no se han conciliado con el administrador. */
  function unappliedCashExpenses(advisorId) {
    return (getDb().expenses || []).filter(e => e.advisorId === advisorId && e.account === CASH_KEY && !e.voided && !e.applied);
  }

  /** Al confirmar la entrega, esos gastos quedan conciliados (ya salieron del efectivo que entregó el asesor). */
  function applyExpenses(ids, info) {
    const wanted = new Set(ids || []);
    let applied = 0;
    for (const e of getDb().expenses || []) {
      if (wanted.has(e.id) && !e.voided && !e.applied) { e.applied = { ...info }; applied++; }
    }
    return applied;
  }

  return { unappliedCashExpenses, applyExpenses, summarize, registerRoutes, start, handleIncomingDocument, tick, runBatch, isDue, getConfig, buildWorkbook, collectRows, applyReturnedWorkbook, createBatch, pendingRows, sanitizeConfig };
};
