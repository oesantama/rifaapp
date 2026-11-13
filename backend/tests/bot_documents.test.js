// El bot recibe siempre el Excel de AGIL (aunque llegue tarde o sin nombre) y no se queda "dormido" si nadie atiende al cliente.
// Ejecutar: node backend/tests/bot_documents.test.js
const assert = require('assert');
const sentTexts = [];
globalThis.fetch = async (url, opts) => {
  if (String(url).includes('/message/sendText/')) sentTexts.push(JSON.parse(opts.body).text);
  return { ok: true, status: 200, text: async () => '{}' };
};
const wa = require('../whatsappService');

const db = {
  companies: [{ id: 'c1', name: 'Empresa Uno', code: 'uno' }],
  raffles: [{ id: 'r1', companyId: 'c1', title: 'Gran Rifa', status: 'ACTIVA', ticketPrice: 150000, digits: 4, mainDrawDate: '2027-03-06T00:00:00.000Z', opportunitiesPerTicket: 2, totalTickets: 10 }],
  tickets: [{ id: 't1', raffleId: 'r1', ticketNumber: 1, numbers: ['1234', '5678'], status: 'DISPONIBLE', price: 150000, totalPaid: 0, abonos: [] }],
  winners: [], advisors: [], botHandoffs: [], botSessions: {}
};
const save = () => {};
const docEvent = (id, ageMin, doc, from = '573001234567') => ({
  event: 'messages.upsert', instance: 'empresa_uno',
  data: { key: { remoteJid: `${from}@s.whatsapp.net`, id, fromMe: false }, messageTimestamp: Math.floor(Date.now() / 1000) - ageMin * 60, message: { base64: 'UEsDBA==', documentMessage: doc } }
});

(async () => {
  const calls = [];
  wa.setDocumentHandler(async args => { calls.push(args); return { handled: true }; });

  // 1) un Excel que llega 3 horas tarde (reconexión) SÍ se procesa
  let r = await wa.handleWebhookEvent(docEvent('D1', 180, { fileName: 'AGIL_lote-0001_2026-11-13_SUBIDO.xlsx', mimetype: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }), db, save);
  assert.strictEqual(r.handled, true, 'el Excel tardío se atiende');
  assert.strictEqual(calls.length, 1);

  // 2) sin nombre pero con tipo de hoja de cálculo: se trata como .xlsx
  r = await wa.handleWebhookEvent(docEvent('D2', 1, { mimetype: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }), db, save);
  assert.strictEqual(calls.length, 2);
  assert.ok(/\.xlsx$/i.test(calls[1].fileName), calls[1].fileName);

  // 3) no es Excel: se ignora, con el motivo
  wa.setDocumentHandler(async () => ({ handled: false, reason: 'documento-no-es-excel' }));
  r = await wa.handleWebhookEvent(docEvent('D3', 1, { fileName: 'foto.pdf', mimetype: 'application/pdf' }), db, save);
  assert.strictEqual(r.ignored, true);
  assert.strictEqual(r.note, 'documento-no-es-excel');

  // 4) un mensaje de TEXTO viejo sigue descartándose (el filtro es solo para el chat)
  const textEvent = (id, ageMin, text, phone = '573009998877') => ({
    event: 'messages.upsert', instance: 'empresa_uno',
    data: { key: { remoteJid: `${phone}@s.whatsapp.net`, id, fromMe: false }, messageTimestamp: Math.floor(Date.now() / 1000) - ageMin * 60, message: { conversation: text } }
  });
  r = await wa.handleWebhookEvent(textEvent('T1', 200, 'hola'), db, save);
  assert.strictEqual(r.stale, true);

  // 5) "dormido": el chat está en atención humana y nadie lo tomó en 40 min: una consulta clara despierta al bot
  const phone = '573009998877';
  db.botSessions = db.botSessions || {};
  db.botHandoffs.push({ id: 'h1', companyId: 'c1', phone, status: 'PENDIENTE', at: new Date(Date.now() - 40 * 60000).toISOString() });
  // la sesión se guarda dentro de db según getSession/updateSession
  const before = sentTexts.length;
  // marcar el chat como atendido por humano
  await wa.handleWebhookEvent(textEvent('T2', 0, 'quiero hablar con un asesor', phone), db, save);
  assert.ok(sentTexts.length > before, 'el pedido de asesor se atiende y pasa a humano');
  const afterHandoff = sentTexts.length;
  // ya en atención humana y reciente: el bot calla ante un texto cualquiera
  await wa.handleWebhookEvent(textEvent('T3', 0, 'gracias', phone), db, save);
  assert.strictEqual(sentTexts.length, afterHandoff, 'en atención humana reciente el bot no responde');
  // envejece el pendiente 40 min y pide disponibles: el bot responde
  db.botHandoffs.find(h => h.phone === phone && h.status === 'PENDIENTE').at = new Date(Date.now() - 40 * 60000).toISOString();
  await wa.handleWebhookEvent(textEvent('T4', 0, 'disponibles', phone), db, save);
  assert.ok(sentTexts.length > afterHandoff, 'nadie tomó el chat en 40 min: el bot vuelve con una consulta clara');
  console.log('OK: documentos y chat sin atender del bot');
})().catch(e => { console.error('FALLO', e); process.exit(1); });
