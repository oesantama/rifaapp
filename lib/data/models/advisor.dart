import 'ticket.dart';

class Advisor {
  final String id;
  final String companyId;
  final String name;
  final String email;
  final String username;
  final bool hasPassword; // passwords never leave the server
  final String phone;
  final String code;
  final String mode; // POOL_GENERAL or ASSIGNED
  final String status; // ACTIVO or INHABILITADO
  final String? deletionReason;
  final List<String> assignedTicketRanges;
  final AdvisorRangeRequest? rangeRequest; // pending request for more numbers
  final int totalTicketsCount;
  final int totalSold;
  final double totalCollected;
  final double totalConfirmed;
  final double pendingTurnIn;
  final String createdAt;

  Advisor({
    required this.id,
    this.companyId = 'comp-1',
    required this.name,
    this.email = '',
    this.username = '',
    this.hasPassword = false,
    required this.phone,
    required this.code,
    required this.mode,
    this.status = 'ACTIVO',
    this.deletionReason,
    required this.assignedTicketRanges,
    this.rangeRequest,
    this.totalTicketsCount = 0,
    this.totalSold = 0,
    this.totalCollected = 0.0,
    this.totalConfirmed = 0.0,
    this.pendingTurnIn = 0.0,
    required this.createdAt,
  });

  bool get isActive => status != 'INHABILITADO';

  bool get worksWithAssignedNumbers => mode == 'ASSIGNED' && assignedTicketRanges.isNotEmpty;

  /// Parsed "10-20" / "35" ranges; they refer to the numbers printed on the tickets.
  List<(int, int)> get parsedRanges => [
        for (final text in assignedTicketRanges)
          if (parseRange(text) case final range?) range,
      ];

  /// How many numbers the ranges cover.
  int get assignedNumbersCount => parsedRanges.fold(0, (sum, r) => sum + r.$2 - r.$1 + 1);

  /// A ticket belongs to the advisor's numbers when any of its numbers falls inside a range
  /// (same rule the server applies when selling).
  bool coversTicket(Ticket ticket) {
    if (!worksWithAssignedNumbers) return true;
    final ranges = parsedRanges;
    if (ranges.isEmpty) return true;
    final numbers = ticket.numbers.map(int.tryParse).whereType<int>().toList();
    final values = numbers.isEmpty ? [ticket.ticketNumber] : numbers;
    return values.any((n) => ranges.any((r) => n >= r.$1 && n <= r.$2));
  }

  static (int, int)? parseRange(String text) {
    final match = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$').firstMatch(text);
    if (match == null) return null;
    final start = int.parse(match.group(1)!);
    final end = match.group(2) != null ? int.parse(match.group(2)!) : start;
    return start <= end ? (start, end) : null;
  }

  factory Advisor.fromJson(Map<String, dynamic> json) {
    var ranges = (json['assignedTicketRanges'] as List? ?? []).map((e) => e.toString()).toList();
    String codeVal = json['code'] ?? '';
    return Advisor(
      id: json['id'] ?? '',
      companyId: json['companyId'] ?? 'comp-1',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      username: json['username'] ?? codeVal,
      hasPassword: json['hasPassword'] == true,
      phone: json['phone'] ?? '',
      code: codeVal,
      mode: json['mode'] ?? 'POOL_GENERAL',
      status: json['status'] ?? 'ACTIVO',
      deletionReason: json['deletionReason'],
      assignedTicketRanges: ranges,
      rangeRequest: json['rangeRequest'] is Map ? AdvisorRangeRequest.fromJson(Map<String, dynamic>.from(json['rangeRequest'])) : null,
      totalTicketsCount: json['totalTicketsCount'] ?? 0,
      totalSold: json['totalSold'] ?? 0,
      totalCollected: (json['totalCollected'] as num?)?.toDouble() ?? 0.0,
      totalConfirmed: (json['totalConfirmed'] as num?)?.toDouble() ?? 0.0,
      pendingTurnIn: (json['pendingTurnIn'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['createdAt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'companyId': companyId,
        'name': name,
        'email': email,
        'username': username.isNotEmpty ? username : code,
        'hasPassword': hasPassword,
        'phone': phone,
        'code': code,
        'mode': mode,
        'status': status,
        'deletionReason': deletionReason,
        'assignedTicketRanges': assignedTicketRanges,
        'totalTicketsCount': totalTicketsCount,
        'totalSold': totalSold,
        'totalCollected': totalCollected,
        'totalConfirmed': totalConfirmed,
        'pendingTurnIn': pendingTurnIn,
        'createdAt': createdAt,
      };
}

class AdvisorRangeRequest {
  final int quantity;
  final String note;
  final String requestedAt;

  const AdvisorRangeRequest({required this.quantity, this.note = '', this.requestedAt = ''});

  factory AdvisorRangeRequest.fromJson(Map<String, dynamic> json) => AdvisorRangeRequest(
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        note: json['note'] ?? '',
        requestedAt: json['requestedAt'] ?? '',
      );
}
