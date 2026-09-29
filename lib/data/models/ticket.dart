class Abono {
  final String id;
  final double amount;
  final String date;
  final String sellerId;
  final String sellerName;
  final String note;

  Abono({
    required this.id,
    required this.amount,
    required this.date,
    required this.sellerId,
    required this.sellerName,
    required this.note,
  });

  factory Abono.fromJson(Map<String, dynamic> json) {
    return Abono(
      id: json['id'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      date: json['date'] ?? '',
      sellerId: json['sellerId'] ?? '',
      sellerName: json['sellerName'] ?? '',
      note: json['note'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'date': date,
        'sellerId': sellerId,
        'sellerName': sellerName,
        'note': note,
      };
}

class AuditLog {
  final String id;
  final String date;
  final String user;
  final String action; // CAMBIO_ASESOR, REGISTRO_VENTA, ABONO, CONFIRMACION_CAJA
  final String description;
  final String? note;

  AuditLog({
    required this.id,
    required this.date,
    required this.user,
    required this.action,
    required this.description,
    this.note,
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    return AuditLog(
      id: json['id'] ?? '',
      date: json['date'] ?? '',
      user: json['user'] ?? 'Sistema',
      action: json['action'] ?? 'LOG',
      description: json['description'] ?? '',
      note: json['note'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'user': user,
        'action': action,
        'description': description,
        'note': note,
      };
}

class Ticket {
  final String id;
  final String raffleId;
  final int ticketNumber;
  final List<String> numbers;
  final double price;
  final String status; // DISPONIBLE, RESERVADA, ABONO_PARCIAL, PAGADA, CONFIRMADA
  final String advisorId;
  final String advisorName;
  final String buyerName;
  final String buyerPhone;
  final double totalPaid;
  final double balancePending;
  final bool confirmedByAdmin;
  final String? assignedDate;
  final List<Abono> abonos;
  final List<AuditLog> auditLogs;

  Ticket({
    required this.id,
    required this.raffleId,
    required this.ticketNumber,
    required this.numbers,
    required this.price,
    required this.status,
    required this.advisorId,
    required this.advisorName,
    required this.buyerName,
    required this.buyerPhone,
    required this.totalPaid,
    required this.balancePending,
    required this.confirmedByAdmin,
    this.assignedDate,
    required this.abonos,
    this.auditLogs = const [],
  });

  factory Ticket.fromJson(Map<String, dynamic> json) {
    var rawAbonos = json['abonos'] as List? ?? [];
    List<Abono> abonosList = rawAbonos.map((a) => Abono.fromJson(a)).toList();

    var rawLogs = json['auditLogs'] as List? ?? [];
    List<AuditLog> logsList = rawLogs.map((l) => AuditLog.fromJson(l)).toList();

    var numList = (json['numbers'] as List? ?? []).map((e) => e.toString()).toList();

    return Ticket(
      id: json['id'] ?? '',
      raffleId: json['raffleId'] ?? '',
      ticketNumber: json['ticketNumber'] ?? 0,
      numbers: numList,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] ?? 'DISPONIBLE',
      advisorId: json['advisorId'] ?? '',
      advisorName: json['advisorName'] ?? '',
      buyerName: json['buyerName'] ?? '',
      buyerPhone: json['buyerPhone'] ?? '',
      totalPaid: (json['totalPaid'] as num?)?.toDouble() ?? 0.0,
      balancePending: (json['balancePending'] as num?)?.toDouble() ?? 0.0,
      confirmedByAdmin: json['confirmedByAdmin'] ?? false,
      assignedDate: json['assignedDate'],
      abonos: abonosList,
      auditLogs: logsList,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'raffleId': raffleId,
        'ticketNumber': ticketNumber,
        'numbers': numbers,
        'price': price,
        'status': status,
        'advisorId': advisorId,
        'advisorName': advisorName,
        'buyerName': buyerName,
        'buyerPhone': buyerPhone,
        'totalPaid': totalPaid,
        'balancePending': balancePending,
        'confirmedByAdmin': confirmedByAdmin,
        'assignedDate': assignedDate,
        'abonos': abonos.map((a) => a.toJson()).toList(),
        'auditLogs': auditLogs.map((l) => l.toJson()).toList(),
      };
}
