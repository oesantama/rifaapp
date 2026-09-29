class WeeklyPrize {
  final String id;
  final String name;
  final double amount;
  final String drawDate;
  final String lotteryName;
  final String minAbonoType; // PORCENTAJE or VALOR_FIJO
  final double minAbonoValue;
  final bool isAccumulative;
  final String status; // PENDIENTE, GANADO, ACUMULADO
  final String? winningTicketNumber;
  final String? winnerName;

  WeeklyPrize({
    required this.id,
    required this.name,
    required this.amount,
    required this.drawDate,
    this.lotteryName = 'Lotería de Medellín',
    this.minAbonoType = 'PORCENTAJE',
    this.minAbonoValue = 50.0,
    this.isAccumulative = true,
    this.status = 'PENDIENTE',
    this.winningTicketNumber,
    this.winnerName,
  });

  factory WeeklyPrize.fromJson(Map<String, dynamic> json) {
    return WeeklyPrize(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      drawDate: json['drawDate'] ?? '',
      lotteryName: json['lotteryName'] ?? 'Lotería de Medellín',
      minAbonoType: json['minAbonoType'] ?? 'PORCENTAJE',
      minAbonoValue: (json['minAbonoValue'] as num?)?.toDouble() ?? 50.0,
      isAccumulative: json['isAccumulative'] ?? true,
      status: json['status'] ?? 'PENDIENTE',
      winningTicketNumber: json['winningTicketNumber'],
      winnerName: json['winnerName'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'drawDate': drawDate,
        'lotteryName': lotteryName,
        'minAbonoType': minAbonoType,
        'minAbonoValue': minAbonoValue,
        'isAccumulative': isAccumulative,
        'status': status,
        'winningTicketNumber': winningTicketNumber,
        'winnerName': winnerName,
      };
}

class Raffle {
  final String id;
  final String title;
  final String description;
  final String mainDrawDate;
  final int digits;
  final int totalTickets;
  final int totalNumbers;
  final int opportunitiesPerTicket;
  final double ticketPrice;
  final List<WeeklyPrize> weeklyPrizes;
  final bool hasWeeklyDraws;
  final String weeklyDrawDay;
  final String lotteryName;
  final String weeklyMinAbonoType; // PORCENTAJE or VALOR_FIJO
  final double weeklyMinAbonoValue; // e.g. 50 (%) or 50000 ($)
  final bool isWeeklyPrizeAccumulative; // Whether weekly prize accumulates if no qualifying winner
  final String commissionType; // PORCENTAJE or VALOR_FIJO
  final double commissionValue; // e.g. 10 (%) or 5000 ($)
  final String weeklyPrizesStartDate;
  final String status;
  final List<String> assignedAdvisorIds;
  final String createdAt;

  Raffle({
    required this.id,
    required this.title,
    required this.description,
    required this.mainDrawDate,
    this.weeklyPrizesStartDate = '',
    required this.digits,
    required this.totalTickets,
    required this.totalNumbers,
    required this.opportunitiesPerTicket,
    required this.ticketPrice,
    required this.weeklyPrizes,
    this.hasWeeklyDraws = true,
    this.weeklyDrawDay = 'Viernes',
    this.lotteryName = 'Lotería de Medellín',
    this.weeklyMinAbonoType = 'PORCENTAJE',
    this.weeklyMinAbonoValue = 50.0,
    this.isWeeklyPrizeAccumulative = true,
    this.commissionType = 'PORCENTAJE',
    this.commissionValue = 10.0,
    required this.status,
    this.assignedAdvisorIds = const [],
    required this.createdAt,
  });

  factory Raffle.fromJson(Map<String, dynamic> json) {
    var prizesRaw = json['weeklyPrizes'] as List? ?? [];
    List<WeeklyPrize> prizes = prizesRaw.map((p) => WeeklyPrize.fromJson(p)).toList();

    var advsRaw = json['assignedAdvisorIds'] as List? ?? [];
    List<String> advsList = advsRaw.map((a) => a.toString()).toList();

    return Raffle(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Sin Título',
      description: json['description'] ?? '',
      mainDrawDate: json['mainDrawDate'] ?? '',
      weeklyPrizesStartDate: json['weeklyPrizesStartDate'] ?? '',
      digits: json['digits'] ?? 4,
      totalTickets: json['totalTickets'] ?? 2500,
      totalNumbers: json['totalNumbers'] ?? 10000,
      opportunitiesPerTicket: json['opportunitiesPerTicket'] ?? 4,
      ticketPrice: (json['ticketPrice'] as num?)?.toDouble() ?? 50000.0,
      weeklyPrizes: prizes,
      hasWeeklyDraws: json['hasWeeklyDraws'] ?? true,
      weeklyDrawDay: json['weeklyDrawDay'] ?? 'Viernes',
      lotteryName: json['lotteryName'] ?? 'Lotería de Medellín',
      weeklyMinAbonoType: json['weeklyMinAbonoType'] ?? 'PORCENTAJE',
      weeklyMinAbonoValue: (json['weeklyMinAbonoValue'] as num?)?.toDouble() ?? 50.0,
      isWeeklyPrizeAccumulative: json['isWeeklyPrizeAccumulative'] ?? true,
      commissionType: json['commissionType'] ?? 'PORCENTAJE',
      commissionValue: (json['commissionValue'] as num?)?.toDouble() ?? 10.0,
      status: json['status'] ?? 'ACTIVA',
      assignedAdvisorIds: advsList,
      createdAt: json['createdAt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'mainDrawDate': mainDrawDate,
        'weeklyPrizesStartDate': weeklyPrizesStartDate,
        'digits': digits,
        'totalTickets': totalTickets,
        'totalNumbers': totalNumbers,
        'opportunitiesPerTicket': opportunitiesPerTicket,
        'ticketPrice': ticketPrice,
        'weeklyPrizes': weeklyPrizes.map((p) => p.toJson()).toList(),
        'hasWeeklyDraws': hasWeeklyDraws,
        'weeklyDrawDay': weeklyDrawDay,
        'lotteryName': lotteryName,
        'weeklyMinAbonoType': weeklyMinAbonoType,
        'weeklyMinAbonoValue': weeklyMinAbonoValue,
        'isWeeklyPrizeAccumulative': isWeeklyPrizeAccumulative,
        'commissionType': commissionType,
        'commissionValue': commissionValue,
        'status': status,
        'assignedAdvisorIds': assignedAdvisorIds,
        'createdAt': createdAt,
      };
}
