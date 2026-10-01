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

  /// Which lottery digits decide the winner: ULTIMAS, PRIMERAS or MEDIO (2 digits only).
  final String winningDigitsPosition;

  /// "Combinado": the same digits in any order also win.
  final bool allowCombined;
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
  final String companyId;
  final Map<String, dynamic>? templateConfig;

  /// Accounts where buyers pay by bank transfer.
  final List<TransferAccount> transferAccounts;

  /// Drive URLs and Folder metadata
  final String? aficheUrl;
  final String? aficheDriveId;
  final String? fondoBoletaUrl;
  final String? fondoBoletaDriveId;
  final String? driveFolderId;

  /// Metadata of stored template images by type ('poster', 'ticket'); images are fetched separately.
  final Map<String, dynamic> templates;
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
    this.winningDigitsPosition = 'ULTIMAS',
    this.allowCombined = false,
    this.weeklyDrawDay = 'Viernes',
    this.lotteryName = 'Lotería de Medellín',
    this.weeklyMinAbonoType = 'PORCENTAJE',
    this.weeklyMinAbonoValue = 50.0,
    this.isWeeklyPrizeAccumulative = true,
    this.commissionType = 'PORCENTAJE',
    this.commissionValue = 10.0,
    required this.status,
    this.assignedAdvisorIds = const [],
    this.companyId = 'comp-1',
    this.templateConfig,
    this.transferAccounts = const [],
    this.aficheUrl,
    this.aficheDriveId,
    this.fondoBoletaUrl,
    this.fondoBoletaDriveId,
    this.driveFolderId,
    this.templates = const {},
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
      winningDigitsPosition: json['winningDigitsPosition'] ?? 'ULTIMAS',
      allowCombined: json['allowCombined'] == true,
      weeklyDrawDay: json['weeklyDrawDay'] ?? 'Viernes',
      lotteryName: json['lotteryName'] ?? 'Lotería de Medellín',
      weeklyMinAbonoType: json['weeklyMinAbonoType'] ?? 'PORCENTAJE',
      weeklyMinAbonoValue: (json['weeklyMinAbonoValue'] as num?)?.toDouble() ?? 50.0,
      isWeeklyPrizeAccumulative: json['isWeeklyPrizeAccumulative'] ?? true,
      commissionType: json['commissionType'] ?? 'PORCENTAJE',
      commissionValue: (json['commissionValue'] as num?)?.toDouble() ?? 10.0,
      status: json['status'] ?? 'ACTIVA',
      assignedAdvisorIds: advsList,
      companyId: json['companyId'] ?? 'comp-1',
      templateConfig: json['templateConfig'] != null ? Map<String, dynamic>.from(json['templateConfig']) : null,
      transferAccounts: [
        for (final a in (json['transferAccounts'] as List? ?? []))
          if (a is Map) TransferAccount.fromJson(Map<String, dynamic>.from(a)),
      ],
      aficheUrl: json['aficheUrl'],
      aficheDriveId: json['aficheDriveId'],
      fondoBoletaUrl: json['fondoBoletaUrl'],
      fondoBoletaDriveId: json['fondoBoletaDriveId'],
      driveFolderId: json['driveFolderId'],
      templates: json['templates'] is Map ? Map<String, dynamic>.from(json['templates']) : const {},
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
        'winningDigitsPosition': winningDigitsPosition,
        'allowCombined': allowCombined,
        'weeklyDrawDay': weeklyDrawDay,
        'lotteryName': lotteryName,
        'weeklyMinAbonoType': weeklyMinAbonoType,
        'weeklyMinAbonoValue': weeklyMinAbonoValue,
        'isWeeklyPrizeAccumulative': isWeeklyPrizeAccumulative,
        'commissionType': commissionType,
        'commissionValue': commissionValue,
        'status': status,
        'assignedAdvisorIds': assignedAdvisorIds,
        'companyId': companyId,
        'templateConfig': templateConfig,
        'transferAccounts': transferAccounts.map((a) => a.toJson()).toList(),
        'aficheUrl': aficheUrl,
        'aficheDriveId': aficheDriveId,
        'fondoBoletaUrl': fondoBoletaUrl,
        'fondoBoletaDriveId': fondoBoletaDriveId,
        'driveFolderId': driveFolderId,
        'templates': templates,
        'createdAt': createdAt,
      };

  /// e.g. "las 2 últimas cifras" / "las 3 primeras cifras" (+ " o combinado").
  String get winningRuleText {
    if (digits >= 4) return allowCombined ? 'el número completo o combinado' : 'el número completo';
    final where = switch (winningDigitsPosition) {
      'PRIMERAS' => 'primeras',
      'MEDIO' => 'del medio',
      _ => 'últimas',
    };
    final text = winningDigitsPosition == 'MEDIO' ? 'las $digits cifras del medio' : 'las $digits $where cifras';
    return allowCombined ? '$text (también combinado)' : text;
  }

  /// Raffle number from a lottery result, using this raffle's rule (same logic as the server).
  /// If the admin types the raffle number itself (no more digits than the raffle), it is used as is.
  String winningNumberFrom(String input) {
    final clean = input.replaceAll(RegExp(r'\D'), '');
    if (clean.length <= digits) return clean.padLeft(digits, '0');
    switch (winningDigitsPosition) {
      case 'PRIMERAS':
        return clean.substring(0, digits);
      case 'MEDIO':
        final start = (clean.length - digits) ~/ 2;
        return clean.substring(start, start + digits);
      default:
        return clean.substring(clean.length - digits);
    }
  }
}

/// A bank account (or key) where a raffle receives transfers.
class TransferAccount {
  final String id;
  final String bank;
  final String accountType;
  final String accountNumber;
  final String holder;
  final String key; // "llave" (Bre-B) or similar

  const TransferAccount({
    this.id = '',
    required this.bank,
    this.accountType = '',
    this.accountNumber = '',
    this.holder = '',
    this.key = '',
  });

  factory TransferAccount.fromJson(Map<String, dynamic> json) => TransferAccount(
        id: json['id'] ?? '',
        bank: json['bank'] ?? '',
        accountType: json['accountType'] ?? '',
        accountNumber: json['accountNumber'] ?? '',
        holder: json['holder'] ?? '',
        key: json['key'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'bank': bank,
        'accountType': accountType,
        'accountNumber': accountNumber,
        'holder': holder,
        'key': key,
      };

  /// One line, e.g. "Bancolombia • Ahorros • 123-456789-01 • llave @rifa • William S".
  String get label => [bank, accountType, accountNumber, if (key.isNotEmpty) 'llave $key', holder].where((p) => p.isNotEmpty).join(' • ');
}
