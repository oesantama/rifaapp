const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const DB_FILE = path.join(__dirname, 'data.json');

app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Initial Database structure
let db = {
  auditLogs: [],
  raffles: [
    {
      id: 'raf-1',
      title: 'Gran Rifa Casa Campestre & Auto Okm',
      description: 'Sorteo Principal de Fin de Año con Premios Semanales de $1.000.000 COP',
      mainDrawDate: '2026-12-31T20:00:00.000Z',
      weeklyPrizesStartDate: '2026-10-01T00:00:00.000Z',
      digits: 4,
      totalTickets: 2500,
      totalNumbers: 10000,
      opportunitiesPerTicket: 4,
      ticketPrice: 50000,
      weeklyPrizes: [
        { id: 'wp-1', name: 'Sorteo Semanal 1', amount: 1000000, drawDate: '2026-10-15' },
        { id: 'wp-2', name: 'Sorteo Semanal 2', amount: 1000000, drawDate: '2026-10-22' }
      ],
      commissionType: 'PORCENTAJE',
      commissionValue: 10,
      status: 'ACTIVA',
      createdAt: new Date().toISOString()
    }
  ],
  advisors: [
    {
      id: 'adv-1',
      name: 'Carlos Mendoza',
      email: 'carlos@rifas.com',
      username: 'ADV01',
      password: '123',
      status: 'ACTIVO',
      phone: '3001234567',
      code: 'ADV01',
      mode: 'POOL_GENERAL', // or 'ASSIGNED'
      assignedTicketRanges: ['1-500'],
      createdAt: new Date().toISOString()
    },
    {
      id: 'adv-2',
      name: 'Maria Fernanda Gomez',
      email: 'maria@rifas.com',
      username: 'ADV02',
      password: '123',
      status: 'ACTIVO',
      phone: '3159876543',
      code: 'ADV02',
      mode: 'ASSIGNED',
      assignedTicketRanges: ['501-1000'],
      createdAt: new Date().toISOString()
    }
  ],
  tickets: [],
  winners: [],
  commissionPayouts: []
};

// Auto generate 2500 tickets with 4 opportunities each for initial raffle
function generateInitialTickets() {
  if (db.tickets.length > 0) return;
  const raffle = db.raffles[0];
  const totalNumbers = raffle.totalNumbers; // 10000 (0000 to 9999)
  const opps = raffle.opportunitiesPerTicket; // 4
  const numTickets = raffle.totalTickets; // 2500

  for (let i = 1; i <= numTickets; i++) {
    // Opportunities formula: e.g. ticket 1 -> 0000, 2500, 5000, 7500
    const series = [];
    for (let k = 0; k < opps; k++) {
      const numVal = (i - 1) + (k * numTickets);
      series.push(numVal.toString().padStart(raffle.digits, '0'));
    }

    // Demo status for first few tickets
    let status = 'DISPONIBLE';
    let buyerName = '';
    let buyerPhone = '';
    let advisorId = '';
    let advisorName = '';
    let totalPaid = 0;
    let abonos = [];
    let confirmedByAdmin = false;

    if (i === 1) {
      status = 'PAGADA';
      buyerName = 'Juan Pérez';
      buyerPhone = '3114445566';
      advisorId = 'adv-1';
      advisorName = 'Carlos Mendoza';
      totalPaid = 50000;
      confirmedByAdmin = true;
      abonos = [
        { id: 'ab-1', amount: 50000, date: new Date().toISOString(), sellerId: 'adv-1', sellerName: 'Carlos Mendoza', note: 'Pago Total Efectivo' }
      ];
    } else if (i === 2) {
      status = 'ABONO_PARCIAL';
      buyerName = 'Laura Restrepo';
      buyerPhone = '3128889900';
      advisorId = 'adv-1';
      advisorName = 'Carlos Mendoza';
      totalPaid = 20000;
      confirmedByAdmin = false;
      abonos = [
        { id: 'ab-2', amount: 20000, date: new Date().toISOString(), sellerId: 'adv-1', sellerName: 'Carlos Mendoza', note: 'Abono Inicial' }
      ];
    }

    db.tickets.push({
      id: `tkt-${i}`,
      raffleId: raffle.id,
      ticketNumber: i,
      numbers: series,
      price: raffle.ticketPrice,
      status, // DISPONIBLE, RESERVADA, ABONO_PARCIAL, PAGADA
      advisorId,
      advisorName,
      buyerName,
      buyerPhone,
      totalPaid,
      balancePending: raffle.ticketPrice - totalPaid,
      confirmedByAdmin,
      assignedDate: status !== 'DISPONIBLE' ? new Date().toISOString() : null,
      abonos
    });
  }
}

// File persistence helpers
function loadDB() {
  try {
    if (fs.existsSync(DB_FILE)) {
      const data = fs.readFileSync(DB_FILE, 'utf8');
      db = JSON.parse(data);
    } else {
      db = {
        companies: [],
        raffles: [],
        tickets: [],
        advisors: [],
        winners: [],
        cashTransactions: [],
        logs: []
      };
      saveDB();
    }
  } catch (err) {
    console.error('Error loading DB:', err);
    db = {
      companies: [],
      raffles: [],
      tickets: [],
      advisors: [],
      winners: [],
      cashTransactions: [],
      logs: []
    };
  }

  // Ensure DB arrays exist
  if (!db.companies) db.companies = [];
  if (!db.raffles) db.raffles = [];
  if (!db.tickets) db.tickets = [];
  if (!db.advisors) db.advisors = [];
  if (!db.winners) db.winners = [];
  if (!db.cashTransactions) db.cashTransactions = [];
  if (!db.logs) db.logs = [];

  db.raffles.forEach(r => {
    if (!r.companyId) r.companyId = 'comp-1';
  });

  db.advisors.forEach(a => {
    if (!a.companyId) a.companyId = 'comp-1';
  });
}

function saveDB() {
  try {
    fs.writeFileSync(DB_FILE, JSON.stringify(db, null, 2), 'utf8');
  } catch (err) {
    console.error('Error saving DB:', err);
  }
}

loadDB();

// API Routes

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString(), companiesCount: (db.companies || []).length, rafflesCount: db.raffles.length, ticketsCount: db.tickets.length });
});

// GET Companies (SuperAdmin) - Enriched with Admins, Raffles and Advisors stats
app.get('/api/companies', (req, res) => {
  const companiesList = db.companies || [];
  const enriched = companiesList.map(comp => {
    // Company Raffles
    const raffles = (db.raffles || []).filter(r => !r.companyId || r.companyId === comp.id);
    // Company Advisors
    const advisors = (db.advisors || []).filter(a => !a.companyId || a.companyId === comp.id);
    // Company Admins
    const admins = [
      {
        name: comp.adminName || 'Administrador General',
        username: comp.adminUsername || 'ADMIN',
        email: comp.adminEmail || 'admin@empresa.com',
        password: comp.adminPassword || '123',
        status: 'ACTIVO'
      }
    ];

    return {
      ...comp,
      adminsCount: admins.length,
      admins: admins,
      rafflesCount: raffles.length,
      raffles: raffles.map(r => ({
        id: r.id,
        title: r.title,
        status: r.status,
        totalTickets: r.totalTickets,
        ticketPrice: r.ticketPrice,
        mainDrawDate: r.mainDrawDate
      })),
      advisorsCount: advisors.length,
      advisors: advisors.map(a => ({
        id: a.id,
        name: a.name,
        code: a.code,
        phone: a.phone,
        mode: a.mode,
        totalSold: a.totalSold || 0,
        totalTicketsCount: a.totalTicketsCount || 0
      }))
    };
  });
  res.json(enriched);
});

// POST Create Company
app.post('/api/companies', (req, res) => {
  const { name, code, adminUsername, adminPassword, adminName, adminEmail } = req.body;
  if (!name) {
    return res.status(400).json({ error: 'El nombre de la empresa es obligatorio' });
  }

  const newCompany = {
    id: `comp-${Date.now()}`,
    name: name.trim(),
    code: code ? code.trim().toUpperCase() : `EMP${(db.companies || []).length + 1}`,
    status: 'ACTIVA',
    adminUsername: adminUsername ? adminUsername.trim() : `admin_${Date.now().toString().slice(-4)}`,
    adminPassword: adminPassword || '123',
    adminName: adminName || 'Admin Empresa',
    adminEmail: adminEmail || '',
    createdAt: new Date().toISOString()
  };

  if (!db.companies) db.companies = [];
  db.companies.push(newCompany);
  saveDB();
  res.status(201).json(newCompany);
});

// PUT Update Company
app.put('/api/companies/:id', (req, res) => {
  const { id } = req.params;
  const company = (db.companies || []).find(c => c.id === id);
  if (!company) {
    return res.status(404).json({ error: 'Empresa no encontrada' });
  }

  if (req.body.name !== undefined) company.name = req.body.name;
  if (req.body.code !== undefined) company.code = req.body.code;
  if (req.body.status !== undefined) company.status = req.body.status;
  if (req.body.adminUsername !== undefined) company.adminUsername = req.body.adminUsername;
  if (req.body.adminPassword !== undefined) company.adminPassword = req.body.adminPassword;
  if (req.body.adminName !== undefined) company.adminName = req.body.adminName;
  if (req.body.adminEmail !== undefined) company.adminEmail = req.body.adminEmail;

  saveDB();
  res.json(company);
});

// Backup & Database Management Routes (SuperAdmin)
app.get('/api/backup', (req, res) => {
  let stats = {};
  try {
    if (fs.existsSync(DB_FILE)) {
      const fileStat = fs.statSync(DB_FILE);
      stats = {
        fileSizeBytes: fileStat.size,
        lastModified: fileStat.mtime.toISOString(),
      };
    }
  } catch (_) {}

  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    stats: {
      companiesCount: (db.companies || []).length,
      rafflesCount: (db.raffles || []).length,
      ticketsCount: (db.tickets || []).length,
      advisorsCount: (db.advisors || []).length,
      winnersCount: (db.winners || []).length,
      auditLogsCount: (db.auditLogs || []).length,
      ...stats
    },
    database: db
  });
});

app.get('/api/backup/download', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Content-Disposition', `attachment; filename=backup_rifamaster_${Date.now()}.json`);
  res.send(JSON.stringify(db, null, 2));
});

app.post('/api/backup/restore', (req, res) => {
  try {
    const backupData = req.body;
    if (!backupData || typeof backupData !== 'object') {
      return res.status(400).json({ error: 'Formato de copia de seguridad inválido' });
    }

    db = {
      auditLogs: backupData.auditLogs || [],
      companies: backupData.companies || [],
      raffles: backupData.raffles || [],
      advisors: backupData.advisors || [],
      tickets: backupData.tickets || [],
      winners: backupData.winners || [],
      commissionPayouts: backupData.commissionPayouts || []
    };

    saveDB();
    res.json({
      message: 'Base de datos restaurada exitosamente.',
      timestamp: new Date().toISOString(),
      stats: {
        companiesCount: db.companies.length,
        rafflesCount: db.raffles.length,
        ticketsCount: db.tickets.length
      }
    });
  } catch (err) {
    res.status(500).json({ error: `Error al restaurar base de datos: ${err.message}` });
  }
});

// GET Raffles
app.get('/api/raffles', (req, res) => {
  const { advisorId, role, companyId } = req.query;
  let raffles = db.raffles;
  if (companyId) {
    raffles = raffles.filter(r => !r.companyId || r.companyId === companyId);
  }
  if (role === 'asesor' && advisorId) {
    raffles = raffles.filter(r => r.status === 'ACTIVA' && (!r.assignedAdvisorIds || r.assignedAdvisorIds.length === 0 || r.assignedAdvisorIds.includes(advisorId)));
  }
  res.json(raffles);
});

// PUT Update Raffle
app.put('/api/raffles/:id', (req, res) => {
  const { id } = req.params;
  const raffle = db.raffles.find(r => r.id === id);
  if (!raffle) {
    return res.status(404).json({ error: 'Sorteo no encontrado' });
  }

  if (req.body.status !== undefined) raffle.status = req.body.status;
  if (req.body.title !== undefined) raffle.title = req.body.title;
  if (req.body.description !== undefined) raffle.description = req.body.description;
  if (req.body.mainDrawDate !== undefined) raffle.mainDrawDate = req.body.mainDrawDate;
  if (req.body.weeklyPrizesStartDate !== undefined) raffle.weeklyPrizesStartDate = req.body.weeklyPrizesStartDate;
  if (req.body.assignedAdvisorIds !== undefined) raffle.assignedAdvisorIds = req.body.assignedAdvisorIds;
  if (req.body.commissionType !== undefined) raffle.commissionType = req.body.commissionType;
  if (req.body.commissionValue !== undefined) raffle.commissionValue = parseFloat(req.body.commissionValue) || 0;
  if (req.body.templateConfig !== undefined) raffle.templateConfig = req.body.templateConfig;

  saveDB();
  res.json(raffle);
});

// POST Create Raffle
app.post('/api/raffles', (req, res) => {
  const { title, description, mainDrawDate, weeklyPrizesStartDate, digits, totalTickets, ticketPrice, weeklyPrizes, generationMode, customNumbers, preSoldTickets, commissionType, commissionValue, companyId } = req.body;
  
  const numDigits = parseInt(digits) || 4;
  const numTickets = parseInt(totalTickets) || 2500;
  const totalNumbers = Math.pow(10, numDigits); // 10^4 = 10000
  const opps = Math.floor(totalNumbers / numTickets); // e.g. 10000 / 2500 = 4

  const newRaffle = {
    id: `raf-${Date.now()}`,
    companyId: companyId || 'comp-1',
    title: title || 'Nuevo Sorteo',
    description: description || '',
    mainDrawDate: mainDrawDate || new Date(Date.now() + 90*86400000).toISOString(),
    weeklyPrizesStartDate: weeklyPrizesStartDate || new Date().toISOString(),
    digits: numDigits,
    totalTickets: numTickets,
    totalNumbers,
    opportunitiesPerTicket: opps,
    ticketPrice: parseFloat(ticketPrice) || 50000,
    weeklyPrizes: weeklyPrizes || [],
    commissionType: commissionType || 'PORCENTAJE',
    commissionValue: parseFloat(commissionValue) || 10,
    status: 'ACTIVA',
    createdAt: new Date().toISOString()
  };

  db.raffles.unshift(newRaffle);

  // Prepare series numbers based on generationMode
  let allSeries = [];
  const mode = generationMode || 'SECUENCIAL';

  if (mode === 'ALEATORIO') {
    // Generate pool 0..totalNumbers-1, shuffle and chunk
    const pool = Array.from({ length: totalNumbers }, (_, i) => i);
    for (let i = pool.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [pool[i], pool[j]] = [pool[j], pool[i]];
    }

    for (let i = 0; i < numTickets; i++) {
      const tktNumbers = [];
      for (let k = 0; k < opps; k++) {
        const idx = i * opps + k;
        if (idx < pool.length) {
          tktNumbers.push(pool[idx].toString().padStart(numDigits, '0'));
        }
      }
      allSeries.push(tktNumbers);
    }
  } else if (mode === 'EXCEL' && customNumbers && typeof customNumbers === 'object') {
    for (let i = 1; i <= numTickets; i++) {
      if (customNumbers[i] && Array.isArray(customNumbers[i])) {
        allSeries.push(customNumbers[i].map(n => n.toString().padStart(numDigits, '0')));
      } else {
        const series = [];
        for (let k = 0; k < opps; k++) {
          const numVal = (i - 1) + (k * numTickets);
          series.push(numVal.toString().padStart(numDigits, '0'));
        }
        allSeries.push(series);
      }
    }
  } else {
    // SECUENCIAL
    for (let i = 1; i <= numTickets; i++) {
      const series = [];
      for (let k = 0; k < opps; k++) {
        const numVal = (i - 1) + (k * numTickets);
        series.push(numVal.toString().padStart(numDigits, '0'));
      }
      allSeries.push(series);
    }
  }

  // Pre-sold tickets lookup
  const preSoldMap = {};
  if (Array.isArray(preSoldTickets)) {
    preSoldTickets.forEach(rec => {
      if (rec.ticketNumber) {
        preSoldMap[rec.ticketNumber] = rec;
      }
    });
  }

  // Generate Tickets for this raffle
  for (let i = 1; i <= numTickets; i++) {
    const series = allSeries[i - 1] || [];
    let status = 'DISPONIBLE';
    let buyerName = '';
    let buyerPhone = '';
    let advisorName = '';
    let advisorId = '';
    let totalPaid = 0;
    let abonos = [];

    if (preSoldMap[i]) {
      const rec = preSoldMap[i];
      status = rec.status || 'RESERVADA';
      buyerName = rec.buyerName || '';
      buyerPhone = rec.buyerPhone || '';
      advisorName = rec.sellerName || '';
      advisorId = rec.sellerCode || 'ADV01';
      totalPaid = parseFloat(rec.amountPaid) || 0;
      if (totalPaid > 0) {
        abonos.push({
          id: `ab-${Date.now()}-${i}`,
          amount: totalPaid,
          date: new Date().toISOString(),
          sellerId: advisorId,
          sellerName: advisorName || 'Asesor',
          note: rec.note || 'Importación Inicial CSV'
        });
      }
    }

    db.tickets.push({
      id: `tkt-${newRaffle.id}-${i}`,
      raffleId: newRaffle.id,
      ticketNumber: i,
      numbers: series,
      price: newRaffle.ticketPrice,
      status: status,
      advisorId: advisorId,
      advisorName: advisorName,
      buyerName: buyerName,
      buyerPhone: buyerPhone,
      totalPaid: totalPaid,
      balancePending: newRaffle.ticketPrice - totalPaid,
      confirmedByAdmin: false,
      assignedDate: status !== 'DISPONIBLE' ? new Date().toISOString() : null,
      abonos: abonos
    });
  }

  saveDB();
  res.status(201).json(newRaffle);
});

// POST Bulk Import Tickets
app.post('/api/tickets/import', (req, res) => {
  const { raffleId, records } = req.body;
  if (!raffleId || !Array.isArray(records)) {
    return res.status(400).json({ error: 'Datos de importación inválidos' });
  }

  let importedCount = 0;
  records.forEach(rec => {
    const ticket = db.tickets.find(t => t.raffleId === raffleId && t.ticketNumber === parseInt(rec.ticketNumber));
    if (ticket) {
      ticket.buyerName = rec.buyerName || ticket.buyerName;
      ticket.buyerPhone = rec.buyerPhone || ticket.buyerPhone;
      ticket.status = rec.status || ticket.status || 'RESERVADA';
      ticket.advisorName = rec.sellerName || ticket.advisorName;
      ticket.advisorId = rec.sellerCode || ticket.advisorId;
      
      const amt = parseFloat(rec.amountPaid) || 0;
      if (amt > 0) {
        ticket.totalPaid += amt;
        ticket.balancePending = Math.max(0, ticket.price - ticket.totalPaid);
        ticket.abonos.push({
          id: `ab-${Date.now()}-${importedCount}`,
          amount: amt,
          date: new Date().toISOString(),
          sellerId: ticket.advisorId || 'ADV01',
          sellerName: ticket.advisorName || 'Asesor',
          note: rec.note || 'Abono Importado CSV'
        });
      }
      importedCount++;
    }
  });

  saveDB();
  res.json({ message: `${importedCount} boletas importadas correctamente`, count: importedCount });
});

// GET Tickets (with filtering)
app.get('/api/tickets', (req, res) => {
  const { raffleId, advisorId, status, search, numberSearch } = req.query;
  
  let result = db.tickets;
  if (raffleId) {
    result = result.filter(t => t.raffleId === raffleId);
  } else if (db.raffles.length > 0) {
    // default to active raffle
    result = result.filter(t => t.raffleId === db.raffles[0].id);
  }

  if (advisorId) {
    result = result.filter(t => t.advisorId === advisorId);
  }

  if (status) {
    result = result.filter(t => t.status === status);
  }

  if (numberSearch) {
    const target = numberSearch.toString().trim();
    result = result.filter(t => 
      t.ticketNumber.toString() === target || 
      t.numbers.some(n => n.includes(target))
    );
  }

  if (search) {
    const q = search.toLowerCase();
    result = result.filter(t => 
      t.ticketNumber.toString().includes(q) ||
      t.buyerName.toLowerCase().includes(q) ||
      t.buyerPhone.includes(q) ||
      t.numbers.some(n => n.includes(q))
    );
  }

  res.json(result);
});

// POST Register Ticket Sale or Abono
app.post('/api/tickets/:id/abono', (req, res) => {
  const { id } = req.params;
  const { amount, buyerName, buyerPhone, sellerId, sellerName, note } = req.body;

  const ticket = db.tickets.find(t => t.id === id);
  if (!ticket) {
    return res.status(404).json({ error: 'Boleta no encontrada' });
  }

  const abonoAmount = parseFloat(amount) || 0;
  if (isNaN(abonoAmount) || abonoAmount < 0) {
    return res.status(400).json({ error: 'Monto de abono inválido' });
  }

  ticket.buyerName = buyerName || ticket.buyerName || 'Sin Nombre';
  ticket.buyerPhone = buyerPhone || ticket.buyerPhone || '';
  if (sellerId) ticket.advisorId = sellerId;
  if (sellerName) ticket.advisorName = sellerName;
  if (!ticket.assignedDate) ticket.assignedDate = new Date().toISOString();

  if (abonoAmount > 0) {
    const newAbono = {
      id: `ab-${Date.now()}`,
      amount: abonoAmount,
      date: new Date().toISOString(),
      sellerId: sellerId || 'admin',
      sellerName: sellerName || 'Administrador',
      note: note || 'Abono registrado'
    };
    ticket.abonos.push(newAbono);
    ticket.totalPaid += abonoAmount;
  } else if (ticket.abonos.length === 0) {
    // Register initial note for reservation if 0 amount
    ticket.abonos.push({
      id: `ab-${Date.now()}`,
      amount: 0,
      date: new Date().toISOString(),
      sellerId: sellerId || 'admin',
      sellerName: sellerName || 'Administrador',
      note: note || 'Boleta apartada / fiada sin abono inicial'
    });
  }

  ticket.balancePending = Math.max(0, ticket.price - ticket.totalPaid);

  if (ticket.balancePending <= 0 && ticket.totalPaid > 0) {
    ticket.status = ticket.confirmedByAdmin ? 'CONFIRMADA' : 'PAGADA';
  } else if (ticket.totalPaid > 0) {
    ticket.status = 'ABONO_PARCIAL';
  } else {
    ticket.status = 'RESERVADA'; // Apartada / Fiada sin abono ($0)
  }

  saveDB();
  res.json(ticket);
});

// POST Admin Confirm Ticket Payment Received
app.post('/api/tickets/:id/confirm', (req, res) => {
  const { id } = req.params;
  const ticket = db.tickets.find(t => t.id === id);
  if (!ticket) {
    return res.status(404).json({ error: 'Boleta no encontrada' });
  }

  ticket.confirmedByAdmin = true;
  ticket.confirmedDate = new Date().toISOString();
  if (ticket.status === 'PAGADA') {
    ticket.status = 'CONFIRMADA';
  }
  saveDB();
  res.json(ticket);
});

// GET Advisors
app.get('/api/advisors', (req, res) => {
  // calculate live metrics for each advisor
  const advisorsWithStats = db.advisors.map(adv => {
    const advTickets = db.tickets.filter(t => t.advisorId === adv.id);
    const totalSold = advTickets.filter(t => t.status === 'PAGADA' || t.status === 'ABONO_PARCIAL').length;
    const totalCollected = advTickets.reduce((sum, t) => sum + t.totalPaid, 0);
    const totalConfirmed = advTickets.filter(t => t.confirmedByAdmin).reduce((sum, t) => sum + t.totalPaid, 0);
    const pendingTurnIn = totalCollected - totalConfirmed;

    return {
      ...adv,
      totalTicketsCount: advTickets.length,
      totalSold,
      totalCollected,
      totalConfirmed,
      pendingTurnIn
    };
  });

  res.json(advisorsWithStats);
});

// POST Create Advisor
app.post('/api/advisors', (req, res) => {
  const { name, email, username, password, status, phone, code, mode, assignedTicketRanges, companyId } = req.body;
  const newAdvisor = {
    id: `adv-${Date.now()}`,
    companyId: companyId || 'comp-1',
    name: name || 'Nuevo Asesor',
    email: email || '',
    username: username || code || `ADV${Math.floor(10 + Math.random()*90)}`,
    password: password || '1234',
    status: status || 'ACTIVO',
    phone: phone || '',
    code: code || `ADV${Math.floor(10 + Math.random()*90)}`,
    mode: mode || 'POOL_GENERAL',
    assignedTicketRanges: assignedTicketRanges || [],
    createdAt: new Date().toISOString()
  };

  db.advisors.push(newAdvisor);
  saveDB();
  res.status(201).json(newAdvisor);
});

// PUT Update Advisor
app.put('/api/advisors/:id', (req, res) => {
  const { id } = req.params;
  const advisor = db.advisors.find(a => a.id === id);
  if (!advisor) {
    return res.status(404).json({ error: 'Asesor no encontrado' });
  }

  if (req.body.name !== undefined) advisor.name = req.body.name;
  if (req.body.email !== undefined) advisor.email = req.body.email;
  if (req.body.username !== undefined) advisor.username = req.body.username;
  if (req.body.password !== undefined) advisor.password = req.body.password;
  if (req.body.status !== undefined) advisor.status = req.body.status;
  if (req.body.deletionReason !== undefined) advisor.deletionReason = req.body.deletionReason;
  if (req.body.phone !== undefined) advisor.phone = req.body.phone;
  if (req.body.code !== undefined) advisor.code = req.body.code;
  if (req.body.mode !== undefined) advisor.mode = req.body.mode;
  if (req.body.assignedTicketRanges !== undefined) advisor.assignedTicketRanges = req.body.assignedTicketRanges;

  saveDB();
  res.json(advisor);
});

// DELETE Advisor (Only allowed if no sales/records exist)
app.delete('/api/advisors/:id', (req, res) => {
  const { id } = req.params;
  const { reason } = req.body || {};
  const advisor = db.advisors.find(a => a.id === id);
  if (!advisor) {
    return res.status(404).json({ error: 'Asesor no encontrado' });
  }

  const advTickets = db.tickets.filter(t => t.advisorId === id);
  const totalSold = advTickets.filter(t => t.status === 'PAGADA' || t.status === 'ABONO_PARCIAL').length;
  const totalCollected = advTickets.reduce((sum, t) => sum + (t.totalPaid || 0), 0);

  if (totalSold > 0 || totalCollected > 0) {
    return res.status(400).json({ error: 'No se puede eliminar un usuario con ventas o abonos registrados. Por favor, inhabilítelo.' });
  }

  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({
    id: `audit-${Date.now()}`,
    type: 'DELETE_ADVISOR',
    targetId: advisor.id,
    targetName: advisor.name,
    reason: reason || 'Eliminación voluntaria por administración',
    date: new Date().toISOString()
  });

  db.advisors = db.advisors.filter(a => a.id !== id);
  saveDB();
  res.json({ message: 'Asesor eliminado correctamente' });
});

// DELETE Winner / Draw Record
app.delete('/api/winners/:id', (req, res) => {
  const { id } = req.params;
  const { reason } = req.body || {};
  const winner = db.winners.find(w => w.id === id);
  if (!winner) {
    return res.status(404).json({ error: 'Registro de sorteo/ganador no encontrado' });
  }

  if (!db.auditLogs) db.auditLogs = [];
  db.auditLogs.push({
    id: `audit-${Date.now()}`,
    type: 'DELETE_WINNER_DRAW',
    targetId: winner.id,
    drawName: winner.drawName,
    winningNumber: winner.winningNumber,
    reason: reason || 'Eliminación del sorteo tras informe de auditoría PDF',
    date: new Date().toISOString()
  });

  db.winners = db.winners.filter(w => w.id !== id);
  saveDB();
  res.json({ message: 'Registro de sorteo eliminado correctamente' });
});

// POST Register Winner / Draw Number
app.post('/api/winners', (req, res) => {
  const { raffleId, winningNumber, drawName, drawDate, prizeAmount, photoUrl } = req.body;

  const raffle = db.raffles.find(r => r.id === (raffleId || db.raffles[0].id));
  const rawNumStr = (winningNumber || '').toString().trim();
  const numStr = rawNumStr.padStart(raffle ? raffle.digits : 4, '0');

  // Search if any ticket has this winning number
  const matchingTicket = db.tickets.find(t => 
    t.raffleId === (raffleId || (db.raffles[0] ? db.raffles[0].id : 'raf-1')) && 
    (t.numbers.includes(numStr) || t.numbers.includes(rawNumStr))
  );

  const reqAbono = raffle ? (
    raffle.weeklyMinAbonoType === 'PORCENTAJE'
      ? (raffle.ticketPrice * (raffle.weeklyMinAbonoValue / 100))
      : raffle.weeklyMinAbonoValue
  ) : 0;

  let isWinner = false;
  if (matchingTicket && matchingTicket.status !== 'DISPONIBLE' && (matchingTicket.totalPaid || 0) >= reqAbono) {
    isWinner = true;
  }

  let winnerDetails = null;
  if (matchingTicket) {
    let abonosSummary = [];
    if (matchingTicket.abonos && matchingTicket.abonos.length > 0) {
      abonosSummary = matchingTicket.abonos.map(a => ({
        date: a.date,
        amount: a.amount,
        sellerName: a.sellerName,
        note: a.note
      }));
    } else {
      abonosSummary = [{
        date: matchingTicket.assignedDate || new Date().toISOString(),
        amount: matchingTicket.totalPaid || 0,
        sellerName: matchingTicket.advisorName || '',
        note: 'Pago / Abono Inicial de Venta'
      }];
    }

    winnerDetails = {
      ticketNumber: matchingTicket.ticketNumber,
      buyerName: matchingTicket.buyerName,
      buyerPhone: matchingTicket.buyerPhone,
      advisorName: matchingTicket.advisorName,
      status: matchingTicket.status,
      totalPaid: matchingTicket.totalPaid || 0,
      minRequiredAmount: reqAbono,
      insufficientAbono: !isWinner,
      assignedDate: matchingTicket.assignedDate,
      abonosSummary: abonosSummary
    };
  }

  // Calculate previous accumulated pot from active accumulated draws
  const activeAccumulatedPrizes = db.winners.filter(w => w.accumulated);
  const prevAccumulatedPot = activeAccumulatedPrizes.reduce((sum, w) => sum + (parseFloat(w.basePrizeAmount || w.prizeAmount) || 0), 0);

  const basePrizeAmount = prizeAmount ? parseFloat(prizeAmount) : 1000000;
  const totalPrizePaid = isWinner ? (basePrizeAmount + prevAccumulatedPot) : basePrizeAmount;

  const record = {
    id: `win-${Date.now()}`,
    raffleId: raffle ? raffle.id : 'raf-1',
    drawName: drawName || 'Sorteo Semanal',
    drawDate: drawDate || new Date().toISOString(),
    winningNumber: rawNumStr,
    basePrizeAmount: basePrizeAmount,
    previousAccumulatedAmount: isWinner ? prevAccumulatedPot : 0,
    totalPrizePaid: totalPrizePaid,
    prizeAmount: totalPrizePaid,
    isWinner, // true if sold and min abono met, false if accumulated
    accumulated: !isWinner,
    winnerDetails,
    photoUrl: photoUrl || '',
    createdAt: new Date().toISOString()
  };

  // If won, mark previous accumulated draws as consumed so they don't get re-accumulated
  if (isWinner) {
    db.winners.forEach(w => {
      if (w.accumulated) {
        w.accumulated = false;
        w.accumulationReason = `Acumulado entregado en sorteo #${rawNumStr}`;
      }
    });
  }

  db.winners.unshift(record);
  saveDB();
  res.status(201).json(record);
});

// GET Winners
app.get('/api/winners', (req, res) => {
  res.json(db.winners);
});

// GET Dashboard Metrics Summary
app.get('/api/dashboard', (req, res) => {
  const raffle = db.raffles[0];
  const activeTickets = db.tickets.filter(t => t.raffleId === (raffle ? raffle.id : 'raf-1'));

  const totalTickets = activeTickets.length;
  const soldPaidCount = activeTickets.filter(t => t.status === 'PAGADA').length;
  const partialAbonoCount = activeTickets.filter(t => t.status === 'ABONO_PARCIAL').length;
  const availableCount = activeTickets.filter(t => t.status === 'DISPONIBLE').length;

  const totalMoneyCollected = activeTickets.reduce((sum, t) => sum + t.totalPaid, 0);
  const totalMoneyConfirmed = activeTickets.filter(t => t.confirmedByAdmin).reduce((sum, t) => sum + t.totalPaid, 0);
  const totalMoneyPendingTurnIn = totalMoneyCollected - totalMoneyConfirmed;
  const totalPotentialRevenue = totalTickets * (raffle ? raffle.ticketPrice : 50000);

  const accumulatedPrizes = db.winners.filter(w => w.accumulated);

  res.json({
    raffle,
    totalTickets,
    soldPaidCount,
    partialAbonoCount,
    availableCount,
    totalMoneyCollected,
    totalMoneyConfirmed,
    totalMoneyPendingTurnIn,
    totalPotentialRevenue,
    progressPercentage: totalTickets > 0 ? (((soldPaidCount + partialAbonoCount) / totalTickets) * 100).toFixed(1) : 0,
    accumulatedCount: accumulatedPrizes.length,
    accumulatedTotalAmount: accumulatedPrizes.reduce((sum, w) => sum + w.prizeAmount, 0)
  });
});

// GET Commissions Summary
app.get('/api/commissions', (req, res) => {
  if (!db.commissionPayouts) db.commissionPayouts = [];
  const { raffleId } = req.query;
  const raffle = db.raffles.find(r => r.id === raffleId) || db.raffles[0];
  const targetRaffleId = raffle ? raffle.id : 'raf-1';
  
  const commType = raffle ? (raffle.commissionType || 'PORCENTAJE') : 'PORCENTAJE';
  const commVal = raffle ? (parseFloat(raffle.commissionValue) || 10) : 10;
  const ticketPrice = raffle ? (parseFloat(raffle.ticketPrice) || 50000) : 50000;

  const raffleTickets = db.tickets.filter(t => t.raffleId === targetRaffleId);

  const advisorStats = db.advisors.map(adv => {
    const advTickets = raffleTickets.filter(t => 
      t.advisorId === adv.id || 
      (t.advisorName && t.advisorName.trim().toLowerCase() === adv.name.trim().toLowerCase()) ||
      (adv.code && t.advisorName && t.advisorName.includes(adv.code))
    );
    
    const paidTickets = advTickets.filter(t => t.status === 'PAGADA' || t.status === 'CONFIRMADA');
    const partialTickets = advTickets.filter(t => t.status === 'ABONO_PARCIAL');
    const totalTicketsSold = paidTickets.length + partialTickets.length;
    
    const totalCollected = advTickets.reduce((sum, t) => sum + (t.totalPaid || 0), 0);

    let commissionEarned = 0;
    if (commType === 'VALOR_FIJO') {
      commissionEarned = totalTicketsSold * commVal;
    } else {
      commissionEarned = (totalCollected * commVal) / 100;
    }

    const advPayouts = db.commissionPayouts.filter(p => p.advisorId === adv.id && (p.raffleId === targetRaffleId || !p.raffleId));
    const commissionPaid = advPayouts.reduce((sum, p) => sum + (p.amount || 0), 0);
    const pendingCommission = Math.max(0, commissionEarned - commissionPaid);

    return {
      advisorId: adv.id,
      advisorName: adv.name,
      advisorCode: adv.code,
      phone: adv.phone,
      totalTicketsSold,
      totalCollected,
      commissionEarned,
      commissionPaid,
      pendingCommission,
      payoutsCount: advPayouts.length
    };
  });

  const globalCommissionEarned = advisorStats.reduce((sum, a) => sum + a.commissionEarned, 0);
  const globalCommissionPaid = advisorStats.reduce((sum, a) => sum + a.commissionPaid, 0);
  const globalPendingCommission = advisorStats.reduce((sum, a) => sum + a.pendingCommission, 0);

  res.json({
    raffleId: targetRaffleId,
    commissionType: commType,
    commissionValue: commVal,
    ticketPrice,
    globalCommissionEarned,
    globalCommissionPaid,
    globalPendingCommission,
    advisors: advisorStats,
    payoutsHistory: db.commissionPayouts.filter(p => p.raffleId === targetRaffleId || !p.raffleId)
  });
});

// POST Commission Payout
app.post('/api/commissions/payout', (req, res) => {
  if (!db.commissionPayouts) db.commissionPayouts = [];
  const { advisorId, amount, note, raffleId } = req.body;
  const targetRaffleId = raffleId || (db.raffles[0] ? db.raffles[0].id : 'raf-1');
  const payoutAmount = parseFloat(amount) || 0;

  if (advisorId === 'ALL') {
    const raffle = db.raffles.find(r => r.id === targetRaffleId) || db.raffles[0];
    const commType = raffle ? (raffle.commissionType || 'PORCENTAJE') : 'PORCENTAJE';
    const commVal = raffle ? (parseFloat(raffle.commissionValue) || 10) : 10;
    const raffleTickets = db.tickets.filter(t => t.raffleId === targetRaffleId);

    let totalPaidOut = 0;
    db.advisors.forEach(adv => {
      const advTickets = raffleTickets.filter(t => t.advisorId === adv.id || (t.advisorName && t.advisorName.trim().toLowerCase() === adv.name.trim().toLowerCase()));
      const totalTicketsSold = advTickets.filter(t => t.status === 'PAGADA' || t.status === 'CONFIRMADA' || t.status === 'ABONO_PARCIAL').length;
      const totalCollected = advTickets.reduce((sum, t) => sum + (t.totalPaid || 0), 0);

      let earned = commType === 'VALOR_FIJO' ? (totalTicketsSold * commVal) : ((totalCollected * commVal) / 100);
      const advPayouts = db.commissionPayouts.filter(p => p.advisorId === adv.id && (p.raffleId === targetRaffleId || !p.raffleId));
      const paid = advPayouts.reduce((sum, p) => sum + (p.amount || 0), 0);
      const pending = Math.max(0, earned - paid);

      if (pending > 0) {
        db.commissionPayouts.push({
          id: `pay-${Date.now()}-${adv.id}`,
          advisorId: adv.id,
          advisorName: adv.name,
          amount: pending,
          date: new Date().toISOString(),
          note: note || 'Liquidación Global de Comisiones',
          raffleId: targetRaffleId
        });
        totalPaidOut += pending;
      }
    });
    saveDB();
    return res.json({ message: `Se liquidaron comisiones a todos los asesores por un total de $${totalPaidOut.toFixed(0)} COP.`, totalPaidOut });
  }

  const advisor = db.advisors.find(a => a.id === advisorId);
  if (!advisor) {
    return res.status(404).json({ error: 'Asesor no encontrado' });
  }

  const payout = {
    id: `pay-${Date.now()}`,
    advisorId: advisor.id,
    advisorName: advisor.name,
    amount: payoutAmount,
    date: new Date().toISOString(),
    note: note || 'Pago de Comisión Asesor',
    raffleId: targetRaffleId
  };

  db.commissionPayouts.push(payout);
  saveDB();
  res.status(201).json(payout);
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Backend API Servidor ejecutándose en http://0.0.0.0:${PORT}`);
});
