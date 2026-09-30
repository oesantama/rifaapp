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
    this.totalTicketsCount = 0,
    this.totalSold = 0,
    this.totalCollected = 0.0,
    this.totalConfirmed = 0.0,
    this.pendingTurnIn = 0.0,
    required this.createdAt,
  });

  bool get isActive => status != 'INHABILITADO';

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
