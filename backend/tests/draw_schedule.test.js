// Orden de sorteos semanales y texto de participación. Ejecutar: node backend/tests/draw_schedule.test.js
const assert = require('assert');
const { drawDateKey, byDrawDate, participationText } = require('../drawSchedule');

assert.strictEqual(drawDateKey('05/12/2026'), '2026-12-05');
assert.strictEqual(drawDateKey('2026-12-05T00:00:00.000Z'), '2026-12-05');
assert.strictEqual(drawDateKey(''), '9999');

const raffle = {
  ticketPrice: 150000, hasWeeklyDraws: true,
  weeklyPrizes: [
    { drawDate: '05/12/2026', name: '#4', minAbonoType: 'VALOR_FIJO', minAbonoValue: 50000 },
    { drawDate: '12/12/2026', name: '#5', minAbonoType: 'VALOR_FIJO', minAbonoValue: 100000 },
    { drawDate: '14/11/2026', name: '#1', minAbonoType: 'VALOR_FIJO', minAbonoValue: 50000 },
    { drawDate: '2026-11-21', name: '#2', minAbonoType: 'VALOR_FIJO', minAbonoValue: 50000 },
    { drawDate: '10/11/2026', name: 'ya jugado', minAbonoType: 'VALOR_FIJO', minAbonoValue: 50000 },
    { name: 'sin fecha', minAbonoType: 'VALOR_FIJO', minAbonoValue: 1 }
  ]
};
assert.deepStrictEqual([...raffle.weeklyPrizes].sort(byDrawDate).map(p => p.name), ['ya jugado', '#1', '#2', '#4', '#5', 'sin fecha']);

const t = participationText(raffle, 50000, '2026-11-13');
assert.ok(t.includes('14/11/2026 (#1); 21/11/2026 (#2); 05/12/2026 (#4)'), 'participa en los tres primeros, por fecha');
assert.ok(!t.includes('ya jugado'), 'los sorteos pasados no cuentan');
assert.ok(t.includes('Para participar en 12/12/2026 (#5) debes completar un total abonado de $100.000 (te faltan $50.000)'));
assert.ok(t.includes('Gran Sorteo'));
assert.ok(participationText(raffle, 0, '2026-11-13').includes('todavía no participas'));
assert.ok(!participationText(raffle, 150000, '2026-11-13').includes('Para participar en'), 'pagada completa: no falta nada');
assert.strictEqual(participationText({ ...raffle, hasWeeklyDraws: false }, 1, '2026-11-13'), '');
assert.strictEqual(participationText({ ticketPrice: 1, weeklyPrizes: [] }, 1, '2026-11-13'), '');
console.log('OK: sorteos semanales');
