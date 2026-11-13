// Recordatorios y resultados de sorteos por WhatsApp. Ejecutar: node backend/tests/draw_reminders.test.js
const assert = require('assert');
const { weeklyMinAbonoOf } = require('../drawSchedule');
const create = require('../drawReminders');

const day = ms => new Date(ms - 5 * 3600 * 1000).toISOString().slice(0, 10);
const dmy = key => `${key.slice(8, 10)}/${key.slice(5, 7)}/${key.slice(0, 4)}`;
const NOW = Date.parse('2026-11-11T15:00:00Z'); // 10:00 en Colombia
const today = day(NOW);
const in3 = day(NOW + 3 * 86400000);
const in10 = day(NOW + 10 * 86400000);

const db = {
  companies: [{ id: 'c1', name: 'William Rifas', code: 'wr', drawRemindersConfig: { enabled: true, daysBefore: 3 } }],
  advisors: [
    { id: 'a1', companyId: 'c1', name: 'Lina Marcela Orozco', status: 'ACTIVO', whatsapp: { instance: 'asesor_a1', number: '573001' } },
    { id: 'a2', companyId: 'c1', name: 'Juan Andres', status: 'ACTIVO' }
  ],
  raffles: [{
    id: 'r1', companyId: 'c1', title: 'Gran Rifa', status: 'ACTIVA', ticketPrice: 150000, hasWeeklyDraws: true, lotteryName: 'Lotería de Boyacá',
    weeklyPrizes: [
      { id: 'p1', name: 'Sorteo Anticipado #1', drawDate: dmy(in3), amount: 1000000, minAbonoType: 'VALOR_FIJO', minAbonoValue: 50000, status: 'PENDIENTE' },
      { id: 'p2', name: 'Sorteo Anticipado #2', drawDate: dmy(in10), amount: 1000000, minAbonoType: 'VALOR_FIJO', minAbonoValue: 50000, status: 'PENDIENTE' }
    ]
  }],
  tickets: [
    { id: 't1', raffleId: 'r1', ticketNumber: 1, numbers: ['1789', '9193'], status: 'ABONO_PARCIAL', totalPaid: 60000, buyerName: 'Guillermo Muñoz Pérez', buyerPhone: '3108570461', advisorId: 'a1' },
    { id: 't2', raffleId: 'r1', ticketNumber: 2, numbers: ['0001', '0002'], status: 'RESERVADA', totalPaid: 20000, buyerName: 'Guillermo Muñoz Pérez', buyerPhone: '3108570461', advisorId: 'a1' },
    { id: 't3', raffleId: 'r1', ticketNumber: 3, numbers: ['5555', '6666'], status: 'PAGADA', totalPaid: 150000, buyerName: 'Ana Largo', buyerPhone: '3115550000', advisorId: '' },
    { id: 't4', raffleId: 'r1', ticketNumber: 4, numbers: ['7777', '8888'], status: 'ABONO_PARCIAL', totalPaid: 50000, buyerName: 'Pedro Sin Whatsapp', buyerPhone: '3120000000', advisorId: 'a2' },
    { id: 't5', raffleId: 'r1', ticketNumber: 5, numbers: ['1111', '2222'], status: 'DISPONIBLE', totalPaid: 0, buyerName: '', buyerPhone: '' },
    { id: 't6', raffleId: 'r1', ticketNumber: 6, numbers: ['3333', '4444'], status: 'PAGADA', totalPaid: 150000, buyerName: 'Sin Telefono', buyerPhone: '', advisorId: 'a1' }
  ],
  winners: [{ id: 'w0', raffleId: 'r1', accumulated: true, basePrizeAmount: 1000000 }]
};
const sent = [];
const whatsappService = {
  getInstanceName: ({ record }) => `empresa_${record.code}`,
  getHealth: () => ({ state: 'open' }),
  sendTextMessage: async (instance, phone, text, meta) => { sent.push({ instance, phone, text, meta }); return { ok: true }; }
};
const svc = create({ getDb: () => db, saveDB() {}, whatsappService, weeklyMinAbonoOf, log: { warn() {} }, pauseFn: async () => {} });
const company = db.companies[0];

(async () => {
  // --- qué sorteos tocan hoy: el de dentro de 3 días, no el de 10
  const due = svc.dueDraws(db, company, today, 3);
  assert.deepStrictEqual(due.map(d => d.prize.id), ['p1']);

  // --- mensajes: agrupados por comprador y por quien envía; sin asesor → WhatsApp de la empresa; sin WhatsApp vinculado → no se escribe
  const r = svc.buildReminders(db, company, due[0].raffle, due[0].prize, today);
  assert.strictEqual(r.messages.length, 2, 'Guillermo (por Lina) y Ana (empresa)');
  assert.deepStrictEqual(r.skipped.map(s => `${s.label}:${s.reason}:${s.tickets}`), ['Juan Andres:sin-whatsapp:1']);
  const g = r.messages.find(m => m.phone === '3108570461');
  assert.strictEqual(g.instance, 'asesor_a1');
  assert.ok(g.text.includes('Hola *Guillermo*') && g.text.includes('tu asesor(a) *Lina Marcela Orozco*'));
  assert.ok(g.text.includes('en 3 días') && g.text.includes('Sorteo Anticipado #1'));
  assert.ok(g.text.includes('Boleta 1789 • 9193: llevas $60.000 y *ya cumples* el abono mínimo de $50.000'), 'la que califica');
  assert.ok(g.text.includes('Boleta 0001 • 0002: llevas $20.000. Para participar debes completar un abono total de *$50.000* (te faltan *$30.000*)'), 'la que debe');
  assert.ok(g.text.includes('$2.000.000 COP ($1.000.000 del sorteo + $1.000.000 acumulado'), 'premio con acumulado');
  const a = r.messages.find(m => m.phone === '3115550000');
  assert.strictEqual(a.instance, 'empresa_wr');
  assert.ok(a.text.includes('*William Rifas*') && a.text.includes('¡Mucha suerte!') && !a.text.includes('completar tu abono'));

  // --- envío: una sola vez por comprador y día (aunque el programador corra varias veces)
  await svc.processReminders(NOW);
  assert.strictEqual(sent.length, 2);
  assert.strictEqual(sent.every(s => s.meta.origin === 'recordatorio-sorteo'), true);
  await svc.processReminders(NOW + 600000);
  assert.strictEqual(sent.length, 2, 'no repite');
  // fuera de horario no envía; con la opción apagada tampoco
  db.drawReminderState = {};
  await svc.processReminders(Date.parse('2026-11-11T05:00:00Z'));
  assert.strictEqual(sent.length, 2, 'antes de las 9 am no envía');
  company.drawRemindersConfig.enabled = false;
  await svc.processReminders(NOW);
  assert.strictEqual(sent.length, 2, 'apagado no envía');
  company.drawRemindersConfig.enabled = true;

  // --- vista previa
  const pv = svc.preview(company, NOW);
  assert.strictEqual(pv.draw.name, 'Sorteo Anticipado #1');
  assert.deepStrictEqual(pv.senders.map(x => x.label).sort(), ['Lina Marcela Orozco', 'William Rifas']);
  assert.ok(pv.sample.includes('RECORDATORIO'));

  // --- resultado: vendido y gana
  sent.length = 0;
  const winnerRecord = { id: 'w1', raffleId: 'r1', drawType: 'SEMANAL', drawName: 'Sorteo Anticipado #1', drawDate: dmy(in3), winningNumber: '1789', lotteryResult: '1789', isWinner: true, accumulated: false, totalPrizePaid: 2000000,
    winnerDetails: { buyerName: 'Guillermo Muñoz Pérez', buyerPhone: '3108570461', status: 'ABONO_PARCIAL', minRequiredAmount: 50000 } };
  db.winners.unshift(winnerRecord);
  svc.announceResult(winnerRecord);
  await new Promise(r => setTimeout(r, 50));
  assert.strictEqual(sent.length, 2);
  const win = sent.find(s => s.phone === '3108570461');
  assert.ok(win.text.includes('FELICITACIONES GUILLERMO') && win.text.includes('$2.000.000'), 'el ganador recibe la felicitación');
  const other = sent.find(s => s.phone === '3115550000');
  assert.ok(other.text.includes('jugó el número *1789*') && other.text.includes('vendido a *Guillermo P.*') && other.text.includes('ganó *$2.000.000 COP*'));
  assert.ok(!other.text.includes('Muñoz Pérez'), 'no publica el nombre completo');
  assert.strictEqual(winnerRecord.announcement.done, true);
  assert.strictEqual(winnerRecord.announcement.sentCount, 2);
  assert.ok(!JSON.stringify(winnerRecord).includes('3108570461') || JSON.stringify(winnerRecord.announcement).includes('3108570461') === false, 'el aviso no guarda teléfonos en el registro');
  svc.announceResult(winnerRecord); await new Promise(r => setTimeout(r, 20));
  assert.strictEqual(sent.length, 2, 'no se avisa dos veces');

  // --- resultado: número no vendido → se acumula
  sent.length = 0;
  const unsold = { id: 'w2', raffleId: 'r1', drawType: 'SEMANAL', drawName: 'Sorteo Anticipado #1', drawDate: dmy(in3), winningNumber: '1111', lotteryResult: '1111', isWinner: false, accumulated: true, basePrizeAmount: 1000000, totalPrizePaid: 1000000,
    winnerDetails: { buyerName: '', status: 'DISPONIBLE', minRequiredAmount: 50000 } };
  db.winners.unshift(unsold);
  svc.announceResult(unsold);
  await new Promise(r => setTimeout(r, 50));
  const t = sent[0].text;
  assert.ok(t.includes('no está vendido aún') && t.includes('se acumula') && t.includes('Pozo acumulado') && t.includes('Próximo sorteo'), t);

  // --- vendido pero sin abono mínimo
  sent.length = 0;
  const lacking = { ...unsold, announcement: undefined, id: 'w3', winningNumber: '7777', winnerDetails: { buyerName: 'Pedro Sin Whatsapp', status: 'ABONO_PARCIAL', minRequiredAmount: 80000 } };
  db.winners.unshift(lacking);
  svc.announceResult(lacking);
  await new Promise(r => setTimeout(r, 50));
  assert.ok(sent[0].text.includes('vendido a *Pedro W.*') && sent[0].text.includes('no tenía el abono mínimo ($80.000)') && sent[0].text.includes('se acumula'));
  console.log('OK: recordatorios y resultados de sorteos');
})().catch(e => { console.error('FALLO', e); process.exit(1); });

// ---------------------------------------------------------------- ritmo de envío (que WhatsApp no bloquee los números)
(async () => {
  const waits = [];
  const db2 = { companies: [{ id: 'c1' }], advisors: [], raffles: [], tickets: [], winners: [] };
  let n = 0;
  const wa = { getInstanceName: () => 'empresa_x', getHealth: () => ({ state: 'open' }), sendTextMessage: async () => { n++; return { ok: true }; } };
  const svc = create({ getDb: () => db2, saveDB() {}, whatsappService: wa, weeklyMinAbonoOf, log: { warn() {} }, pauseFn: async ms => { waits.push(ms); } });
  const items = Array.from({ length: 40 }, (_, i) => ({ instance: 'empresa_x', phone: `300${i}`, text: 'hola' }));
  const r = await svc.sendPaced(items, 'prueba', { onResult() {}, now: () => Date.parse('2026-11-11T15:00:00Z') });
  assert.strictEqual(r.sent, 40);
  assert.strictEqual(waits.length, 40, 'una pausa después de cada mensaje');
  assert.ok(waits.every(w => w >= 10000), 'con más de 30 mensajes: mínimo 10 s entre uno y otro');
  assert.ok(waits.filter(w => w >= 70000).length === 2, 'descanso largo (1-2 min más) cada 15 mensajes: 2 en 40');
  const small = Array.from({ length: 5 }, (_, i) => ({ instance: 'empresa_x', phone: `310${i}`, text: 'hola' }));
  waits.length = 0;
  await svc.sendPaced(small, 'prueba', { onResult() {}, now: () => Date.parse('2026-11-12T15:00:00Z') });
  assert.ok(waits.every(w => w >= 6000 && w < 12000), 'pocos mensajes: 6 a 12 s');

  // tope diario por número
  n = 0;
  const cap = Array.from({ length: svc.DAILY_CAP + 30 }, (_, i) => ({ instance: 'empresa_cap', phone: `320${i}`, text: 'hola' }));
  const rc = await svc.sendPaced(cap, 'prueba', { onResult() {}, now: () => Date.parse('2026-11-13T15:00:00Z') });
  assert.strictEqual(rc.sent, svc.DAILY_CAP, `no pasa de ${svc.DAILY_CAP} por número y día`);
  assert.strictEqual(rc.stopped, 'tope-diario');
  const rc2 = await svc.sendPaced(cap.slice(0, 5), 'prueba', { onResult() {}, now: () => Date.parse('2026-11-14T15:00:00Z') });
  assert.strictEqual(rc2.sent, 5, 'al día siguiente se puede enviar otra vez');

  // un número que falla 3 veces seguidas se deja de usar en la vuelta, pero otro número sigue
  const wa3 = { getInstanceName: () => 'x', getHealth: () => ({ state: 'open' }), sendTextMessage: async (inst) => (inst === 'roto' ? { ok: false } : { ok: true }) };
  const svc3 = create({ getDb: () => db2, saveDB() {}, whatsappService: wa3, weeklyMinAbonoOf, log: { warn() {} }, pauseFn: async () => {} });
  const mixed = [
    ...Array.from({ length: 6 }, (_, i) => ({ instance: 'roto', phone: `330${i}`, text: 'x' })),
    ...Array.from({ length: 3 }, (_, i) => ({ instance: 'sano', phone: `340${i}`, text: 'x' }))
  ];
  const results = [];
  const rm = await svc3.sendPaced(mixed, 'prueba', { onResult: (m, ok) => results.push(`${m.instance}:${ok}`) });
  assert.strictEqual(results.filter(x => x === 'roto:false').length, 3, 'tras 3 fallos seguidos no insiste con ese número');
  assert.strictEqual(results.filter(x => x === 'sano:true').length, 3, 'el otro número sigue enviando');
  console.log('OK: ritmo de envío de WhatsApp');
})().catch(e => { console.error('FALLO ritmo', e); process.exit(1); });
