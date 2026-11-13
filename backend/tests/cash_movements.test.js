// Prueba de traslados entre cajas con una base sintética (sin tocar datos reales). Ejecutar: node backend/tests/cash_movements.test.js
const assert = require('assert');
const create = require('../agilService.js');
const day = ms => new Date(ms - 5 * 3600 * 1000).toISOString().slice(0, 10);
const db = {
  companies: [{ id: 'c1', name: 'Emp' }],
  raffles: [{ id: 'r1', companyId: 'c1', title: 'R', transferAccounts: [{ id: 'a1', bank: 'Nequi', accountType: 'ahorros', accountNumber: '3114225536', holder: 'Lina' }, { id: 'a2', bank: 'Bancolombia', accountType: 'Ahorros', accountNumber: '89000001817', holder: 'William' }] }],
  tickets: [{
    id: 't1', raffleId: 'r1', ticketNumber: 1, numbers: ['01'], status: 'PAGADA', abonos: [
      { id: 'ab1', amount: 100000, date: new Date().toISOString(), metodoPago: 'efectivo', sellerId: 'adv1', sellerName: 'Asesor', received: { by: 'Admin', at: new Date().toISOString(), method: 'transferencia', deliveryId: 'ent-1' } }
    ]
  }],
  advisors: [], expenses: [], cashMovements: [], cashDeliveries: [], auditLogs: []
};
const deps = {
  getDb: () => db, saveDB() {}, isReady: () => true, whatsappService: {}, isAbonoSettled: a => !!a.received || !!(a.verification && a.verification.status === 'VALIDADA'),
  abonoCashState: () => 'RECIBIDO', soporteLinkFor: () => '', actorName: () => 'Admin', colombiaDay: day, colombiaOffsetMs: -5 * 3600 * 1000,
  baseUrl: () => '', getInstanceName: () => '', auditPush() {}, accountLabel: a => `${a.bank} • ${a.accountType} • ${a.accountNumber} • ${a.holder}`, uploadProof: async () => null
};
const svc = create(deps);
(async () => {
const company = db.companies[0];
let s = svc.summarize(db, company, {});
assert.strictEqual(s.cash.balance, 100000, 'antes de la entrega todo el dinero figura en efectivo');

// entrega por transferencia confirmada -> traslado automático Efectivo → cuenta
const delivery = { id: 'ent-1', companyId: 'c1', method: 'transferencia', total: 100000, destination: 'Nequi • ahorros • 3114225536 • Lina', transferDate: day(Date.now()), approvalNumber: 'M1234567', advisorName: 'Asesor' };
const mv = svc.recordDeliveryTransfer(delivery, 'Admin', new Date().toISOString());
assert.ok(mv && mv.type === 'ENTREGA_TRANSFERENCIA' && mv.amount === 100000);
assert.strictEqual(svc.recordDeliveryTransfer(delivery, 'Admin', new Date().toISOString()).id, mv.id, 'no se duplica');
s = svc.summarize(db, company, {});
const nequi = s.accounts.find(a => a.label.startsWith('Nequi'));
assert.strictEqual(s.cash.balance, 0, 'el efectivo queda en 0');
assert.strictEqual(nequi.balance, 100000, 'la cuenta recibe el dinero');
assert.strictEqual(s.grand.balance, 100000, 'el total no cambia');

// una entrega por efectivo no genera traslado
assert.strictEqual(svc.recordDeliveryTransfer({ ...delivery, id: 'ent-2', method: 'efectivo' }, 'Admin', new Date().toISOString()), null);

// con filtro de fechas: un traslado de otro día no cuenta
db.cashMovements[0].date = '2020-01-01';
s = svc.summarize(db, company, { from: day(Date.now()) });
assert.strictEqual(s.cash.balance, 100000, 'fuera del rango no se aplica');
db.cashMovements[0].date = day(Date.now());

// anulado no cuenta
db.cashMovements[0].voided = { by: 'x' };
assert.strictEqual(svc.summarize(db, company, {}).cash.balance, 100000);
db.cashMovements[0].voided = null;

// ---- rutas manuales ----
const routes = {};
const app = { get: (p, ...h) => routes['GET ' + p] = h[h.length - 1], post: (p, ...h) => routes['POST ' + p] = h[h.length - 1], put() {}, delete() {} };
svc.registerRoutes(app, { adminOnly: (q, r, n) => n(), targetCompanyOf: () => company });
const call = async (key, { body = {}, query = {}, params = {} } = {}) => {
  const res = { code: 200, body: null, status(c) { this.code = c; return this; }, json(b) { this.body = b; return this; } };
  await routes[key]({ auth: { role: 'admin', record: company }, body, query, params }, res);
  return res;
};
const nequiKey = nequi.key;
const today = day(Date.now());
let r = await call('POST /api/agil/movements', { body: { from: nequiKey, to: 'efectivo', amount: 30000, date: today, reason: 'Retiro para pagar proveedor' } });
assert.strictEqual(r.code, 201, JSON.stringify(r.body));
s = svc.summarize(db, company, {});
assert.strictEqual(s.cash.balance, 30000);
assert.strictEqual(s.accounts.find(a => a.key === nequiKey).balance, 70000);
r = await call('POST /api/agil/movements', { body: { from: nequiKey, to: 'efectivo', amount: 90000, date: today, reason: 'Más de lo que hay' } });
assert.strictEqual(r.code, 400); assert.strictEqual(r.body.code, 'INSUFFICIENT_BALANCE');
r = await call('POST /api/agil/movements', { body: { from: nequiKey, to: nequiKey, amount: 1000, date: today, reason: 'Mismo origen y destino' } });
assert.strictEqual(r.code, 400);
r = await call('POST /api/agil/movements', { body: { from: nequiKey, to: 'efectivo', amount: 1000, date: today, reason: 'abc' } });
assert.strictEqual(r.code, 400, 'justificación mínima');
r = await call('POST /api/agil/movements', { body: { from: nequiKey, to: 'efectivo', amount: 1000, date: '2999-01-01', reason: 'Fecha futura no vale' } });
assert.strictEqual(r.code, 400);
r = await call('GET /api/agil/movements', { query: {} });
assert.strictEqual(r.body.count, 2);
const manual = r.body.movements.find(m => m.type === 'MANUAL');
const auto = r.body.movements.find(m => m.auto);
r = await call('POST /api/agil/movements/:id/void', { params: { id: auto.id }, body: { reason: 'quiero anular' } });
assert.strictEqual(r.code, 400, 'el automático no se anula');
r = await call('POST /api/agil/movements/:id/void', { params: { id: manual.id }, body: { reason: 'Se registró por error' } });
assert.strictEqual(r.code, 200, JSON.stringify(r.body));
s = svc.summarize(db, company, {});
assert.strictEqual(s.cash.balance, 0); assert.strictEqual(s.accounts.find(a => a.key === nequiKey).balance, 100000);
console.log('OK: traslados entre cajas');

})().catch(e => { console.error('FALLO', e.message); process.exit(1); });
