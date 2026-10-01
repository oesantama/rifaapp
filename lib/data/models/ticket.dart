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

/// A voided sale kept as history: who voided it, when, why, and the sale as it was.
class TicketAnnulment {
  final String id;
  final String date;
  final String by;
  final String reason;
  final String previousStatus;
  final String previousBuyerName;
  final String previousBuyerPhone;
  final String previousAdvisorName;
  final String previousSaleChannel;
  final double previousTotalPaid;
  final int previousAbonosCount;

  TicketAnnulment({
    required this.id,
    required this.date,
    required this.by,
    required this.reason,
    this.previousStatus = '',
    this.previousBuyerName = '',
    this.previousBuyerPhone = '',
    this.previousAdvisorName = '',
    this.previousSaleChannel = '',
    this.previousTotalPaid = 0,
    this.previousAbonosCount = 0,
  });

  factory TicketAnnulment.fromJson(Map<String, dynamic> json) {
    final prev = json['previous'] is Map ? Map<String, dynamic>.from(json['previous']) : <String, dynamic>{};
    return TicketAnnulment(
      id: json['id'] ?? '',
      date: json['date'] ?? '',
      by: json['by'] ?? '',
      reason: json['reason'] ?? '',
      previousStatus: prev['status'] ?? '',
      previousBuyerName: prev['buyerName'] ?? '',
      previousBuyerPhone: prev['buyerPhone'] ?? '',
      previousAdvisorName: prev['advisorName'] ?? '',
      previousSaleChannel: prev['saleChannel'] ?? '',
      previousTotalPaid: (prev['totalPaid'] as num?)?.toDouble() ?? 0,
      previousAbonosCount: (prev['abonos'] as List?)?.length ?? 0,
    );
  }
}

/// A payment voided by an admin, with who/when/why.
class VoidedAbono {
  final String id;
  final double amount;
  final String date;
  final String sellerName;
  final String voidedAt;
  final String voidedBy;
  final String voidReason;

  VoidedAbono({
    required this.id,
    required this.amount,
    required this.date,
    required this.sellerName,
    required this.voidedAt,
    required this.voidedBy,
    required this.voidReason,
  });

  factory VoidedAbono.fromJson(Map<String, dynamic> json) => VoidedAbono(
        id: json['id'] ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        date: json['date'] ?? '',
        sellerName: json['sellerName'] ?? '',
        voidedAt: json['voidedAt'] ?? '',
        voidedBy: json['voidedBy'] ?? '',
        voidReason: json['voidReason'] ?? '',
      );
}

class Ticket {
  /// Opportunity number(s) the buyer actually plays. Shown to users instead of the
  /// internal ticket index (ticketNumber), which only exists for storage.
  String get displayNumber => numbers.isNotEmpty ? numbers.join(' - ') : ticketNumber.toString();

  /// Numeric value of the first opportunity, used to sort tickets as users read them.
  int get sortNumber => numbers.isNotEmpty ? (int.tryParse(numbers.first) ?? ticketNumber) : ticketNumber;

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

  /// How the buyer was reached: Facebook, WhatsApp, Familiar, Conocido, Voz a voz, Otro ('' = not recorded).
  final String saleChannel;

  /// Voided sales of this ticket (oldest first); kept even after it is sold again.
  final List<TicketAnnulment> annulments;

  /// Payments voided by an admin (e.g. registered twice); kept for traceability.
  final List<VoidedAbono> voidedAbonos;

  /// Signed code that proves the receipt is authentic (null for available tickets).
  final String? verificationCode;
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
    this.saleChannel = '',
    this.annulments = const [],
    this.voidedAbonos = const [],
    this.verificationCode,
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
      saleChannel: json['saleChannel'] ?? '',
      annulments: (json['annulments'] as List? ?? []).map((a) => TicketAnnulment.fromJson(Map<String, dynamic>.from(a))).toList(),
      verificationCode: json['verificationCode'],
      voidedAbonos: (json['voidedAbonos'] as List? ?? []).map((a) => VoidedAbono.fromJson(Map<String, dynamic>.from(a))).toList(),
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
        'saleChannel': saleChannel,
        'totalPaid': totalPaid,
        'balancePending': balancePending,
        'confirmedByAdmin': confirmedByAdmin,
        'assignedDate': assignedDate,
        'abonos': abonos.map((a) => a.toJson()).toList(),
        'auditLogs': auditLogs.map((l) => l.toJson()).toList(),
      };
}
