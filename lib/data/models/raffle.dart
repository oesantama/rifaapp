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

/// Enlace directo de imagen para cualquier enlace de Drive (uc?export=view, /file/d/ID/view, open?id=).
String normalizeDriveImageUrl(String url) {
  final u = url.trim();
  if (!RegExp(r'(drive|docs)\.google\.com', caseSensitive: false).hasMatch(u)) return u;
  final m = RegExp(r'/d/([A-Za-z0-9_-]{10,})').firstMatch(u) ?? RegExp(r'[?&]id=([A-Za-z0-9_-]{10,})').firstMatch(u);
  return m == null ? u : 'https://lh3.googleusercontent.com/d/${m.group(1)}=s1600';
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
  final String lotteryName; // lottery of the weekly draws
  final String mainLotteryName; // lottery of the main draw
  final String weeklyMinAbonoType; // PORCENTAJE or VALOR_FIJO
  final double weeklyMinAbonoValue; // e.g. 50 (%) or 50000 ($)
  final bool isWeeklyPrizeAccumulative; // Whether weekly prize accumulates if no qualifying winner
  final String commissionType; // PORCENTAJE, VALOR_FIJO, or ESCALONADO
  final double commissionValue; // e.g. 10 (%) or 5000 ($)
  final List<CommissionTier> commissionTiers; // Escalas por rangos de ventas
  final String weeklyPrizesStartDate;
  final String status;
  final List<String> assignedAdvisorIds;
  final String companyId;
  final Map<String, dynamic>? templateConfig;

  /// Lottery of the main draw; older raffles only had the weekly one.
  bool get isClosed => scheduledDeletionAt != null;

  /// Days left before the closed raffle is deleted.
  int get daysUntilDeletion {
    final at = DateTime.tryParse(scheduledDeletionAt ?? '');
    if (at == null) return 0;
    final hours = at.difference(DateTime.now()).inHours;
    return hours <= 0 ? 0 : (hours / 24).ceil();
  }

  /// The main draw date has passed (Colombian calendar).
  bool get drawDatePassed {
    final d = DateTime.tryParse(mainDrawDate);
    if (d == null) return false;
    final colNow = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    final today = DateTime(colNow.year, colNow.month, colNow.day);
    return DateTime(d.year, d.month, d.day).isBefore(today);
  }

  /// Abono mínimo para participar en un sorteo semanal: el del propio sorteo (cada uno tiene el suyo) o, sin él, el de la rifa.
  double weeklyMinAbonoOf([WeeklyPrize? prize]) {
    final type = prize?.minAbonoType ?? weeklyMinAbonoType;
    final value = prize?.minAbonoValue ?? weeklyMinAbonoValue;
    return type == 'PORCENTAJE' ? ticketPrice * value / 100 : value;
  }

  static DateTime? _parseDrawDate(String s) {
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(s.trim());
    return m != null ? DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!)) : DateTime.tryParse(s.trim());
  }

  /// Próximo sorteo semanal (el primero que aún no se juega; si todos pasaron, el último).
  WeeklyPrize? get nextWeeklyPrize {
    final dated = [
      for (final p in weeklyPrizes)
        if (_parseDrawDate(p.drawDate) case final d?) (p, d),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    if (dated.isEmpty) return weeklyPrizes.isEmpty ? null : weeklyPrizes.first;
    final from = DateTime.now().subtract(const Duration(days: 1));
    return dated.firstWhere((x) => !x.$2.isBefore(from), orElse: () => dated.last).$1;
  }

  /// Sorteo semanal que se registra: por nombre, luego por valor del premio y, si no, el próximo.
  WeeklyPrize? weeklyPrizeForDraw(String drawName, double amount) {
    final name = drawName.trim().toLowerCase();
    for (final p in weeklyPrizes) {
      if (name.isNotEmpty && p.name.trim().toLowerCase() == name) return p;
    }
    for (final p in weeklyPrizes) {
      if (amount > 0 && p.amount == amount) return p;
    }
    return nextWeeklyPrize;
  }

  String get mainLottery => mainLotteryName.trim().isNotEmpty ? mainLotteryName.trim() : lotteryName.trim();

  /// Accounts where buyers pay by bank transfer.
  final List<TransferAccount> transferAccounts;

  /// Closed after its draw: deleted with all its data on [scheduledDeletionAt].
  final String? closedAt;
  final String? closedBy;
  final String? scheduledDeletionAt;

  /// Advisors only: why they cannot sell new tickets of this raffle now (locked by the admin), or null.
  final String? advisorSalesBlock;

  /// Drive URLs and Folder metadata
  final String? aficheUrl;
  final String? aficheDriveId;
  final String? fondoBoletaUrl;
  final String? fondoBoletaDriveId;
  final String? driveFolderId;

  /// Independent seller book details
  final String? ownerName;
  final bool isIndependentBook;

  /// Metadata of stored template images by type ('poster', 'ticket'); images are fetched separately.
  final Map<String, dynamic> templates;
  final String createdAt;
  final List<String> prizeImages;

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
    this.mainLotteryName = '',
    this.weeklyMinAbonoType = 'PORCENTAJE',
    this.weeklyMinAbonoValue = 50.0,
    this.isWeeklyPrizeAccumulative = true,
    this.commissionType = 'PORCENTAJE',
    this.commissionValue = 10.0,
    this.commissionTiers = const [],
    required this.status,
    this.assignedAdvisorIds = const [],
    this.companyId = 'comp-1',
    this.templateConfig,
    this.transferAccounts = const [],
    this.closedAt,
    this.closedBy,
    this.scheduledDeletionAt,
    this.advisorSalesBlock,
    this.aficheUrl,
    this.aficheDriveId,
    this.fondoBoletaUrl,
    this.fondoBoletaDriveId,
    this.driveFolderId,
    this.ownerName,
    this.isIndependentBook = false,
    this.templates = const {},
    required this.createdAt,
    this.prizeImages = const [],
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
      mainLotteryName: json['mainLotteryName'] ?? '',
      weeklyMinAbonoType: json['weeklyMinAbonoType'] ?? 'PORCENTAJE',
      weeklyMinAbonoValue: (json['weeklyMinAbonoValue'] as num?)?.toDouble() ?? 50.0,
      isWeeklyPrizeAccumulative: json['isWeeklyPrizeAccumulative'] ?? true,
      commissionType: json['commissionType'] ?? 'PORCENTAJE',
      commissionValue: (json['commissionValue'] as num?)?.toDouble() ?? 10.0,
      commissionTiers: [
        for (final t in (json['commissionTiers'] as List? ?? []))
          if (t is Map) CommissionTier.fromJson(Map<String, dynamic>.from(t)),
      ],
      status: json['status'] ?? 'ACTIVA',
      assignedAdvisorIds: advsList,
      companyId: json['companyId'] ?? 'comp-1',
      templateConfig: json['templateConfig'] != null ? Map<String, dynamic>.from(json['templateConfig']) : null,
      transferAccounts: [
        for (final a in (json['transferAccounts'] as List? ?? []))
          if (a is Map) TransferAccount.fromJson(Map<String, dynamic>.from(a)),
      ],
      closedAt: json['closedAt'],
      closedBy: json['closedBy'],
      scheduledDeletionAt: json['scheduledDeletionAt'],
      advisorSalesBlock: json['advisorSalesBlock'] as String?,
      aficheUrl: json['aficheUrl'],
      aficheDriveId: json['aficheDriveId'],
      fondoBoletaUrl: json['fondoBoletaUrl'],
      fondoBoletaDriveId: json['fondoBoletaDriveId'],
      driveFolderId: json['driveFolderId'],
      ownerName: json['ownerName'] as String?,
      isIndependentBook: json['isIndependentBook'] == true,
      templates: json['templates'] is Map ? Map<String, dynamic>.from(json['templates']) : const {},
      createdAt: json['createdAt'] ?? '',
      prizeImages: [for (final img in (json['prizeImages'] as List? ?? [])) normalizeDriveImageUrl(img.toString())],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'prizeImages': prizeImages,
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
        'mainLotteryName': mainLotteryName,
        'weeklyMinAbonoType': weeklyMinAbonoType,
        'weeklyMinAbonoValue': weeklyMinAbonoValue,
        'isWeeklyPrizeAccumulative': isWeeklyPrizeAccumulative,
        'commissionType': commissionType,
        'commissionValue': commissionValue,
        'commissionTiers': commissionTiers.map((t) => t.toJson()).toList(),
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
        'ownerName': ownerName,
        'isIndependentBook': isIndependentBook,
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

  /// One field per line, for WhatsApp messages:
  /// 🏦 *Banco:* Nequi / 🔢 *Número:* ... / 📋 *Tipo:* ... / 🔑 *Llave:* ... / 👤 *Titular:* ...
  String get messageBlock => [
        if (bank.isNotEmpty) '🏦 *Banco:* $bank',
        if (accountNumber.isNotEmpty) '🔢 *Número:* $accountNumber',
        if (accountType.isNotEmpty) '📋 *Tipo:* $accountType',
        if (key.isNotEmpty) '🔑 *Llave:* $key',
        if (holder.isNotEmpty) '👤 *Titular:* $holder',
      ].join('\n');

  /// One line, e.g. "Bancolombia • Ahorros • 123-456789-01 • llave @rifa • William S".
  String get label => [bank, accountType, accountNumber, if (key.isNotEmpty) 'llave $key', holder].where((p) => p.isNotEmpty).join(' • ');
}

class CommissionTier {
  final int min;
  final int? max;
  final double rate;
  final String type; // 'PORCENTAJE' or 'VALOR_FIJO'

  CommissionTier({
    required this.min,
    this.max,
    required this.rate,
    this.type = 'PORCENTAJE',
  });

  factory CommissionTier.fromJson(Map<String, dynamic> json) {
    return CommissionTier(
      min: (json['min'] as num?)?.toInt() ?? (json['minBoletas'] as num?)?.toInt() ?? 1,
      max: json['max'] != null ? int.tryParse(json['max'].toString()) : (json['maxBoletas'] != null ? int.tryParse(json['maxBoletas'].toString()) : null),
      rate: (json['rate'] as num?)?.toDouble() ?? 10.0,
      type: json['type'] ?? 'PORCENTAJE',
    );
  }

  Map<String, dynamic> toJson() => {
    'min': min,
    if (max != null) 'max': max,
    'rate': rate,
    'type': type,
  };
}
