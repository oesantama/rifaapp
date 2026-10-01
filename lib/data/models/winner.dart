class WinnerDetails {
  final int ticketNumber;
  final String buyerName;
  final String buyerPhone;
  final String advisorName;
  final String status;
  final double totalPaid;
  final double minRequiredAmount;
  final bool insufficientAbono;
  final String? assignedDate;
  final List<Map<String, dynamic>> abonosSummary;

  WinnerDetails({
    required this.ticketNumber,
    required this.buyerName,
    required this.buyerPhone,
    required this.advisorName,
    required this.status,
    this.totalPaid = 0.0,
    this.minRequiredAmount = 0.0,
    this.insufficientAbono = false,
    this.assignedDate,
    this.abonosSummary = const [],
  });

  factory WinnerDetails.fromJson(Map<String, dynamic> json) {
    var rawAbonos = json['abonosSummary'] as List? ?? [];
    return WinnerDetails(
      ticketNumber: json['ticketNumber'] ?? 0,
      buyerName: json['buyerName'] ?? '',
      buyerPhone: json['buyerPhone'] ?? '',
      advisorName: json['advisorName'] ?? '',
      status: json['status'] ?? '',
      totalPaid: (json['totalPaid'] as num?)?.toDouble() ?? 0.0,
      minRequiredAmount: (json['minRequiredAmount'] as num?)?.toDouble() ?? 0.0,
      insufficientAbono: json['insufficientAbono'] ?? false,
      assignedDate: json['assignedDate'],
      abonosSummary: rawAbonos.cast<Map<String, dynamic>>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'ticketNumber': ticketNumber,
        'buyerName': buyerName,
        'buyerPhone': buyerPhone,
        'advisorName': advisorName,
        'status': status,
        'totalPaid': totalPaid,
        'minRequiredAmount': minRequiredAmount,
        'insufficientAbono': insufficientAbono,
        'assignedDate': assignedDate,
        'abonosSummary': abonosSummary,
      };
}

class WinnerRecord {
  final String id;
  final String raffleId;
  final String drawName;
  final String drawDate;
  final String winningNumber;

  /// Full lottery result typed by the admin (winningNumber is the part that counts).
  final String lotteryResult;

  /// EXACTO or COMBINADO (same digits in another order); empty when nobody won.
  final String matchType;
  final double basePrizeAmount;
  final double previousAccumulatedAmount;
  final double totalPrizePaid;
  final bool isWinner;
  final bool accumulated;
  final String lotteryName;
  final String weeklyDrawDay;
  final String accumulationReason;
  final WinnerDetails? winnerDetails;
  final String photoUrl;
  final String createdAt;

  WinnerRecord({
    required this.id,
    required this.raffleId,
    required this.drawName,
    required this.drawDate,
    required this.winningNumber,
    this.lotteryResult = '',
    this.matchType = '',
    required this.basePrizeAmount,
    this.previousAccumulatedAmount = 0.0,
    required this.totalPrizePaid,
    required this.isWinner,
    required this.accumulated,
    this.lotteryName = '',
    this.weeklyDrawDay = '',
    this.accumulationReason = '',
    this.winnerDetails,
    required this.photoUrl,
    required this.createdAt,
  });

  double get prizeAmount => totalPrizePaid;

  factory WinnerRecord.fromJson(Map<String, dynamic> json) {
    double base = (json['basePrizeAmount'] as num?)?.toDouble() ?? (json['prizeAmount'] as num?)?.toDouble() ?? 1000000.0;
    double prevAcc = (json['previousAccumulatedAmount'] as num?)?.toDouble() ?? 0.0;
    double total = (json['totalPrizePaid'] as num?)?.toDouble() ?? (base + prevAcc);

    return WinnerRecord(
      id: json['id'] ?? '',
      raffleId: json['raffleId'] ?? '',
      drawName: json['drawName'] ?? '',
      drawDate: json['drawDate'] ?? '',
      winningNumber: json['winningNumber'] ?? '',
      lotteryResult: json['lotteryResult'] ?? '',
      matchType: json['matchType'] ?? '',
      basePrizeAmount: base,
      previousAccumulatedAmount: prevAcc,
      totalPrizePaid: total,
      isWinner: json['isWinner'] ?? false,
      accumulated: json['accumulated'] ?? false,
      lotteryName: json['lotteryName'] ?? '',
      weeklyDrawDay: json['weeklyDrawDay'] ?? '',
      accumulationReason: json['accumulationReason'] ?? '',
      winnerDetails: json['winnerDetails'] != null ? WinnerDetails.fromJson(json['winnerDetails']) : null,
      photoUrl: json['photoUrl'] ?? '',
      createdAt: json['createdAt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'raffleId': raffleId,
        'drawName': drawName,
        'drawDate': drawDate,
        'winningNumber': winningNumber,
        'basePrizeAmount': basePrizeAmount,
        'previousAccumulatedAmount': previousAccumulatedAmount,
        'totalPrizePaid': totalPrizePaid,
        'isWinner': isWinner,
        'accumulated': accumulated,
        'lotteryName': lotteryName,
        'weeklyDrawDay': weeklyDrawDay,
        'accumulationReason': accumulationReason,
        'winnerDetails': winnerDetails?.toJson(),
        'photoUrl': photoUrl,
        'createdAt': createdAt,
      };
}
