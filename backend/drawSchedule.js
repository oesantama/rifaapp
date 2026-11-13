// backend/drawSchedule.js
// Fechas de los sorteos semanales / anticipados: orden, abono mínimo y el texto "en qué sorteos participas" para el comprador.
// Lo usan el servidor (mensajes, página de verificación) y el bot de WhatsApp.

// Clave de orden de una fecha de sorteo: acepta AAAA-MM-DD(…) y DD/MM/AAAA; sin fecha va al final
const drawDateKey = v => {
  const t = String(v || '').trim();
  const dmy = /^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})/.exec(t);
  if (dmy) return `${dmy[3]}-${dmy[2].padStart(2, '0')}-${dmy[1].padStart(2, '0')}`;
  return /^\d{4}-\d{2}-\d{2}/.test(t) ? t.slice(0, 10) : '9999';
};
const byDrawDate = (a, b) => drawDateKey(a.drawDate).localeCompare(drawDateKey(b.drawDate));

/** "05/12/2026" a partir de una fecha de sorteo (AAAA-MM-DD o DD/MM/AAAA). */
function drawDateLabel(value) {
  const k = drawDateKey(value);
  return k === '9999' ? 'fecha por definir' : `${k.slice(8, 10)}/${k.slice(5, 7)}/${k.slice(0, 4)}`;
}

/** Abono mínimo para participar en un sorteo semanal: el del propio sorteo (cada uno tiene el suyo) o, si no lo define, el de la rifa. */
function weeklyMinAbonoOf(raffle, prize) {
  const price = Number(raffle.ticketPrice) || 0;
  const hasOwn = prize && prize.minAbonoType && prize.minAbonoValue !== undefined && prize.minAbonoValue !== null;
  const type = hasOwn ? prize.minAbonoType : (raffle.weeklyMinAbonoType || 'PORCENTAJE');
  const value = hasOwn ? Number(prize.minAbonoValue) : (Number.isFinite(Number(raffle.weeklyMinAbonoValue)) && raffle.weeklyMinAbonoValue !== null && raffle.weeklyMinAbonoValue !== undefined ? Number(raffle.weeklyMinAbonoValue) : 50);
  return type === 'PORCENTAJE' ? price * value / 100 : value;
}

/**
 * Texto para el comprador: en qué sorteos semanales / anticipados participa con lo que lleva pagado y cuánto debe tener abonado
 * en total para el siguiente. Solo cuenta los sorteos que aún no se juegan (today: AAAA-MM-DD); vacío si no hay sorteos semanales.
 */
function participationText(raffle, paid, today) {
  if (!raffle || raffle.hasWeeklyDraws === false) return '';
  const money = v => `$${Math.round(Number(v) || 0).toLocaleString('es-CO')}`;
  const upcoming = (Array.isArray(raffle.weeklyPrizes) ? raffle.weeklyPrizes : [])
    .filter(p => drawDateKey(p.drawDate) !== '9999' && drawDateKey(p.drawDate) >= today)
    .sort(byDrawDate)
    .map(p => ({ req: weeklyMinAbonoOf(raffle, p), label: `${drawDateLabel(p.drawDate)}${p.name ? ` (${p.name})` : ''}` }));
  if (!upcoming.length) return '';
  const total = Number(paid) || 0;
  const price = Number(raffle.ticketPrice) || 0;
  const ok = upcoming.filter(i => total >= i.req);
  const next = upcoming.find(i => total < i.req);
  const lines = ['🗓️ *Tu participación en los sorteos:*'];
  lines.push(ok.length
    ? `✅ Con lo que llevas pagado (${money(total)}) participas en: ${ok.map(i => i.label).join('; ')}.`
    : `⚠️ Con lo que llevas pagado (${money(total)}) todavía no participas en los sorteos anticipados.`);
  if (next) lines.push(`➡️ Para participar en ${next.label} debes completar un total abonado de ${money(next.req)} (te faltan ${money(next.req - total)}).`);
  if (price > 0 && total < price) lines.push(`🏆 Para el Gran Sorteo la boleta debe estar pagada completa (${money(price)}).`);
  return lines.join('\n');
}

module.exports = { drawDateKey, byDrawDate, drawDateLabel, weeklyMinAbonoOf, participationText };
