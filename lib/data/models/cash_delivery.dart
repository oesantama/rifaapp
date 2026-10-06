/// Cash an advisor handed over to the company (in cash or by a transfer with proof), covering one
/// or several ticket payments. The admin confirms or rejects it.
class CashDelivery {
  final String id;
  final String raffleId;
  final String advisorId;
  final String advisorName;
  final String method; // efectivo | transferencia
  final double total;
  final List<Map<String, dynamic>> items; // ticketId, abonoId, numbers, amount, buyerName, state
  final String? transferDate;
  final String? approvalNumber;
  final String? originBank;
  final String? destination;
  final String? soporteUrl;
  final String? soporteWebViewUrl;
  final String? soporteDriveId;
  final String note;
  final String status; // PENDIENTE | CONFIRMADA | RECHAZADA
  final String reportedAt;
  final String? reviewedBy;
  final String? reviewedAt;
  final String? reviewNote;

  const CashDelivery({
    required this.id,
    required this.raffleId,
    required this.advisorId,
    required this.advisorName,
    required this.method,
    required this.total,
    required this.items,
    this.transferDate,
    this.approvalNumber,
    this.originBank,
    this.destination,
    this.soporteUrl,
    this.soporteWebViewUrl,
    this.soporteDriveId,
    this.note = '',
    required this.status,
    required this.reportedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
  });

  bool get isTransfer => method == 'transferencia';
  bool get isPending => status == 'PENDIENTE';

  factory CashDelivery.fromJson(Map<String, dynamic> json) => CashDelivery(
        id: json['id'] ?? '',
        raffleId: json['raffleId'] ?? '',
        advisorId: json['advisorId'] ?? '',
        advisorName: json['advisorName'] ?? '',
        method: json['method'] ?? 'efectivo',
        total: (json['total'] as num?)?.toDouble() ?? 0,
        items: [for (final i in (json['items'] as List? ?? [])) Map<String, dynamic>.from(i)],
        transferDate: json['transferDate'],
        approvalNumber: json['approvalNumber'],
        originBank: json['originBank'],
        destination: json['destination'],
        soporteUrl: json['soporteUrl'],
        soporteWebViewUrl: json['soporteWebViewUrl'],
        soporteDriveId: json['soporteDriveId'],
        note: json['note'] ?? '',
        status: json['status'] ?? 'PENDIENTE',
        reportedAt: json['reportedAt'] ?? '',
        reviewedBy: json['reviewedBy'],
        reviewedAt: json['reviewedAt'],
        reviewNote: json['reviewNote'],
      );
}
