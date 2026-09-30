import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_http.dart';
import '../models/raffle.dart';
import '../models/ticket.dart';
import '../models/advisor.dart';
import '../models/winner.dart';
import '../models/company.dart';

class ApiService {
  final String baseUrl;

  ApiService({String? baseUrl}) : baseUrl = _resolveBaseUrl(baseUrl);

  static String _resolveBaseUrl(String? customUrl) {
    if (customUrl != null && customUrl.isNotEmpty) return customUrl;
    const envUrl = String.fromEnvironment('API_URL');
    if (envUrl.isNotEmpty) return envUrl;
    if (kIsWeb) return '/api';
    return 'https://rifaapp-backend.onrender.com/api';
  }

  bool _useLocalFallback = false;

  final List<Raffle> _localRaffles = [];
  late final List<Ticket> _localTickets = [];
  final List<Advisor> _localAdvisors = [];
  final List<WinnerRecord> _localWinners = [];

  List<Ticket> _generateFallbackTickets(Raffle raffle) {
    List<Ticket> list = [];
    int opps = raffle.opportunitiesPerTicket;
    int numTickets = raffle.totalTickets;

    for (int i = 1; i <= numTickets; i++) {
      List<String> series = [];
      for (int k = 0; k < opps; k++) {
        int numVal = (i - 1) + (k * numTickets);
        series.add(numVal.toString().padLeft(raffle.digits, '0'));
      }

      String status = 'DISPONIBLE';
      String buyerName = '';
      String buyerPhone = '';
      String advisorId = '';
      String advisorName = '';
      double totalPaid = 0.0;
      bool confirmedByAdmin = false;
      List<Abono> abonos = [];

      if (i == 1) {
        status = 'PAGADA';
        buyerName = 'Juan Pérez';
        buyerPhone = '3114445566';
        advisorId = 'adv-1';
        advisorName = 'Carlos Mendoza';
        totalPaid = 50000.0;
        confirmedByAdmin = true;
        abonos.add(Abono(
          id: 'ab-1',
          amount: 50000.0,
          date: DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
          sellerId: 'adv-1',
          sellerName: 'Carlos Mendoza',
          note: 'Pago Total Efectivo',
        ));
      } else if (i == 2) {
        status = 'ABONO_PARCIAL';
        buyerName = 'Laura Restrepo';
        buyerPhone = '3128889900';
        advisorId = 'adv-1';
        advisorName = 'Carlos Mendoza';
        totalPaid = 20000.0;
        confirmedByAdmin = false;
        abonos.add(Abono(
          id: 'ab-2',
          amount: 20000.0,
          date: DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
          sellerId: 'adv-1',
          sellerName: 'Carlos Mendoza',
          note: 'Abono Inicial',
        ));
      }

      list.add(Ticket(
        id: 'tkt-$i',
        raffleId: raffle.id,
        ticketNumber: i,
        numbers: series,
        price: raffle.ticketPrice,
        status: status,
        advisorId: advisorId,
        advisorName: advisorName,
        buyerName: buyerName,
        buyerPhone: buyerPhone,
        totalPaid: totalPaid,
        balancePending: raffle.ticketPrice - totalPaid,
        confirmedByAdmin: confirmedByAdmin,
        assignedDate: status != 'DISPONIBLE' ? DateTime.now().toIso8601String() : null,
        abonos: abonos,
      ));
    }
    return list;
  }

  Future<List<Raffle>> getRaffles({String? advisorId, bool isAsesor = false}) async {
    if (!_useLocalFallback) {
      try {
        Uri uri = Uri.parse('$baseUrl/raffles').replace(queryParameters: {
          if (isAsesor && advisorId != null) 'advisorId': advisorId,
          if (isAsesor) 'role': 'asesor',
        });
        final response = await authGet(uri).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          List data = jsonDecode(response.body);
          return data.map((json) => Raffle.fromJson(json)).toList();
        }
      } catch (e) {
        debugPrint('⚠️ Error/Timeout obteniendo sorteos de API: $e');
      }
    }

    if (isAsesor && advisorId != null) {
      return _localRaffles
          .where((r) => r.status == 'ACTIVA' && (r.assignedAdvisorIds.isEmpty || r.assignedAdvisorIds.contains(advisorId)))
          .toList();
    }
    return _localRaffles;
  }

  Future<Raffle> updateRaffle(String raffleId, Map<String, dynamic> body) async {
    if (!_useLocalFallback) {
      try {
        final response = await authPut(
          Uri.parse('$baseUrl/raffles/$raffleId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
        if (response.statusCode == 200) {
          return Raffle.fromJson(jsonDecode(response.body));
        }
        // The server answered but rejected the change: show its reason, never fake success locally
        throw ApiException.fromResponse(response);
      } on ApiException {
        rethrow;
      } catch (_) {
        _useLocalFallback = true;
      }
    }

    int idx = _localRaffles.indexWhere((r) => r.id == raffleId);
    if (idx != -1) {
      Raffle cur = _localRaffles[idx];
      var prizesRaw = body['weeklyPrizes'] as List?;
      List<WeeklyPrize> prizes =
          prizesRaw != null ? prizesRaw.map((p) => p is WeeklyPrize ? p : WeeklyPrize.fromJson(p)).toList() : cur.weeklyPrizes;

      Raffle updated = Raffle(
        id: cur.id,
        title: body['title'] ?? cur.title,
        description: body['description'] ?? cur.description,
        mainDrawDate: cur.mainDrawDate,
        digits: cur.digits,
        totalTickets: cur.totalTickets,
        totalNumbers: cur.totalNumbers,
        opportunitiesPerTicket: cur.opportunitiesPerTicket,
        ticketPrice: cur.ticketPrice,
        weeklyPrizes: prizes,
        hasWeeklyDraws: body['hasWeeklyDraws'] ?? cur.hasWeeklyDraws,
        weeklyDrawDay: body['weeklyDrawDay'] ?? cur.weeklyDrawDay,
        lotteryName: body['lotteryName'] ?? cur.lotteryName,
        weeklyMinAbonoType: body['weeklyMinAbonoType'] ?? cur.weeklyMinAbonoType,
        weeklyMinAbonoValue: (body['weeklyMinAbonoValue'] as num?)?.toDouble() ?? cur.weeklyMinAbonoValue,
        isWeeklyPrizeAccumulative: body['isWeeklyPrizeAccumulative'] ?? cur.isWeeklyPrizeAccumulative,
        commissionType: body['commissionType'] ?? cur.commissionType,
        commissionValue: (body['commissionValue'] as num?)?.toDouble() ?? cur.commissionValue,
        status: body['status'] ?? cur.status,
        assignedAdvisorIds: body['assignedAdvisorIds'] != null
            ? (body['assignedAdvisorIds'] as List).map((e) => e.toString()).toList()
            : cur.assignedAdvisorIds,
        createdAt: cur.createdAt,
      );
      _localRaffles[idx] = updated;
      return updated;
    }
    throw Exception('Sorteo no encontrado');
  }

  Future<Raffle> createRaffle(Map<String, dynamic> body) async {
    if (!_useLocalFallback) {
      try {
        final response = await authPost(
          Uri.parse('$baseUrl/raffles'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
        if (response.statusCode == 201) {
          return Raffle.fromJson(jsonDecode(response.body));
        }
      } catch (_) {
        _useLocalFallback = true;
      }
    }

    int digits = int.tryParse(body['digits'].toString()) ?? 4;
    int totalTickets = int.tryParse(body['totalTickets'].toString()) ?? 2500;
    int totalNumbers = 10000;
    if (digits == 2) totalNumbers = 100;
    if (digits == 3) totalNumbers = 1000;
    if (digits == 5) totalNumbers = 100000;
    int opps = totalNumbers ~/ totalTickets;

    var prizesRaw = body['weeklyPrizes'] as List? ?? [];
    List<WeeklyPrize> prizes = prizesRaw.map((p) => p is WeeklyPrize ? p : WeeklyPrize.fromJson(p)).toList();

    Raffle newRaf = Raffle(
      id: 'raf-${DateTime.now().millisecondsSinceEpoch}',
      title: body['title'] ?? 'Nuevo Sorteo',
      description: body['description'] ?? '',
      mainDrawDate: body['mainDrawDate'] ?? DateTime.now().add(const Duration(days: 90)).toIso8601String(),
      digits: digits,
      totalTickets: totalTickets,
      totalNumbers: totalNumbers,
      opportunitiesPerTicket: opps,
      ticketPrice: (body['ticketPrice'] as num?)?.toDouble() ?? 50000.0,
      weeklyPrizes: prizes,
      hasWeeklyDraws: body['hasWeeklyDraws'] ?? true,
      weeklyDrawDay: body['weeklyDrawDay'] ?? 'Viernes',
      lotteryName: body['lotteryName'] ?? 'Lotería de Medellín',
      weeklyMinAbonoType: body['weeklyMinAbonoType'] ?? 'PORCENTAJE',
      weeklyMinAbonoValue: (body['weeklyMinAbonoValue'] as num?)?.toDouble() ?? 50.0,
      isWeeklyPrizeAccumulative: body['isWeeklyPrizeAccumulative'] ?? true,
      commissionType: body['commissionType'] ?? 'PORCENTAJE',
      commissionValue: (body['commissionValue'] as num?)?.toDouble() ?? 10.0,
      status: 'ACTIVA',
      createdAt: DateTime.now().toIso8601String(),
    );

    _localRaffles.insert(0, newRaf);

    // Generate tickets taking into account mode & pre-sold tickets
    String mode = body['generationMode'] ?? 'SECUENCIAL';
    Map<int, List<String>>? customMap = body['customNumbersMap'] as Map<int, List<String>>?;
    List<Map<String, dynamic>>? preSoldList = (body['preSoldTickets'] as List?)?.cast<Map<String, dynamic>>();

    _localTickets.addAll(_generateCustomFallbackTickets(newRaf, mode: mode, customMap: customMap, preSoldList: preSoldList));
    return newRaf;
  }

  List<Ticket> _generateCustomFallbackTickets(
    Raffle raffle, {
    String mode = 'SECUENCIAL',
    Map<int, List<String>>? customMap,
    List<Map<String, dynamic>>? preSoldList,
  }) {
    List<Ticket> list = [];
    int opps = raffle.opportunitiesPerTicket;
    int numTickets = raffle.totalTickets;

    List<List<String>> allSeries = [];
    if (mode == 'ALEATORIO') {
      List<int> pool = List.generate(raffle.totalNumbers, (i) => i)..shuffle();
      for (int i = 0; i < numTickets; i++) {
        List<String> series = [];
        for (int k = 0; k < opps; k++) {
          int idx = i * opps + k;
          if (idx < pool.length) {
            series.add(pool[idx].toString().padLeft(raffle.digits, '0'));
          }
        }
        allSeries.add(series);
      }
    } else if (mode == 'EXCEL' && customMap != null) {
      for (int i = 1; i <= numTickets; i++) {
        if (customMap.containsKey(i)) {
          allSeries.add(customMap[i]!);
        } else {
          List<String> series = [];
          for (int k = 0; k < opps; k++) {
            int val = (i - 1) + (k * numTickets);
            series.add(val.toString().padLeft(raffle.digits, '0'));
          }
          allSeries.add(series);
        }
      }
    } else {
      for (int i = 1; i <= numTickets; i++) {
        List<String> series = [];
        for (int k = 0; k < opps; k++) {
          int val = (i - 1) + (k * numTickets);
          series.add(val.toString().padLeft(raffle.digits, '0'));
        }
        allSeries.add(series);
      }
    }

    Map<int, Map<String, dynamic>> preSoldMap = {};
    if (preSoldList != null) {
      for (var r in preSoldList) {
        if (r['ticketNumber'] != null) {
          preSoldMap[r['ticketNumber']] = r;
        }
      }
    }

    for (int i = 1; i <= numTickets; i++) {
      List<String> series = allSeries[i - 1];
      String status = 'DISPONIBLE';
      String buyerName = '';
      String buyerPhone = '';
      String advisorId = '';
      String advisorName = '';
      double totalPaid = 0.0;
      List<Abono> abonos = [];

      if (preSoldMap.containsKey(i)) {
        final rec = preSoldMap[i]!;
        status = rec['status'] ?? 'RESERVADA';
        buyerName = rec['buyerName'] ?? '';
        buyerPhone = rec['buyerPhone'] ?? '';
        advisorName = rec['sellerName'] ?? '';
        advisorId = rec['sellerCode'] ?? 'ADV01';
        totalPaid = (rec['amountPaid'] as num?)?.toDouble() ?? 0.0;
        if (totalPaid > 0) {
          abonos.add(Abono(
            id: 'ab-presold-$i',
            amount: totalPaid,
            date: DateTime.now().toIso8601String(),
            sellerId: advisorId,
            sellerName: advisorName.isNotEmpty ? advisorName : 'Asesor',
            note: rec['note'] ?? 'Abono Importado CSV',
          ));
        }
      }

      list.add(Ticket(
        id: 'tkt-${raffle.id}-$i',
        raffleId: raffle.id,
        ticketNumber: i,
        numbers: series,
        price: raffle.ticketPrice,
        status: status,
        advisorId: advisorId,
        advisorName: advisorName,
        buyerName: buyerName,
        buyerPhone: buyerPhone,
        totalPaid: totalPaid,
        balancePending: raffle.ticketPrice - totalPaid,
        confirmedByAdmin: false,
        assignedDate: status != 'DISPONIBLE' ? DateTime.now().toIso8601String() : null,
        abonos: abonos,
      ));
    }

    return list;
  }

  Future<bool> importTickets(String raffleId, List<Map<String, dynamic>> records) async {
    if (!_useLocalFallback) {
      try {
        final response = await authPost(
          Uri.parse('$baseUrl/tickets/import'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'raffleId': raffleId, 'records': records}),
        );
        if (response.statusCode == 200) {
          return true;
        }
      } catch (_) {
        _useLocalFallback = true;
      }
    }

    for (var rec in records) {
      int? numVal = rec['ticketNumber'];
      if (numVal == null) continue;

      int index = _localTickets.indexWhere((t) => t.raffleId == raffleId && t.ticketNumber == numVal);
      if (index != -1) {
        Ticket existing = _localTickets[index];
        double amt = (rec['amountPaid'] as num?)?.toDouble() ?? 0.0;
        List<Abono> updatedAbonos = List.from(existing.abonos);
        if (amt > 0) {
          updatedAbonos.add(Abono(
            id: 'ab-imp-${DateTime.now().millisecondsSinceEpoch}',
            amount: amt,
            date: DateTime.now().toIso8601String(),
            sellerId: rec['sellerCode'] ?? existing.advisorId,
            sellerName: rec['sellerName'] ?? existing.advisorName,
            note: rec['note'] ?? 'Importación Masiva CSV',
          ));
        }

        double newPaid = existing.totalPaid + amt;
        _localTickets[index] = Ticket(
          id: existing.id,
          raffleId: existing.raffleId,
          ticketNumber: existing.ticketNumber,
          numbers: existing.numbers,
          price: existing.price,
          status: rec['status'] ?? existing.status,
          advisorId: rec['sellerCode'] ?? existing.advisorId,
          advisorName: rec['sellerName'] ?? existing.advisorName,
          buyerName: rec['buyerName'] ?? existing.buyerName,
          buyerPhone: rec['buyerPhone'] ?? existing.buyerPhone,
          totalPaid: newPaid,
          balancePending: (existing.price - newPaid).clamp(0, existing.price),
          confirmedByAdmin: existing.confirmedByAdmin,
          assignedDate: existing.assignedDate ?? DateTime.now().toIso8601String(),
          abonos: updatedAbonos,
        );
      }
    }
    return true;
  }

  Future<List<Ticket>> getTickets({String? raffleId, String? search, String? numberSearch, String? status, String? advisorId}) async {
    if (!_useLocalFallback) {
      try {
        Uri uri = Uri.parse('$baseUrl/tickets').replace(queryParameters: {
          if (raffleId != null) 'raffleId': raffleId,
          if (search != null && search.isNotEmpty) 'search': search,
          if (numberSearch != null && numberSearch.isNotEmpty) 'numberSearch': numberSearch,
          if (status != null && status.isNotEmpty) 'status': status,
          if (advisorId != null && advisorId.isNotEmpty) 'advisorId': advisorId,
        });
        final response = await authGet(uri).timeout(const Duration(seconds: 25));
        if (response.statusCode == 200) {
          List data = jsonDecode(response.body);
          return data.map((json) => Ticket.fromJson(json)).toList();
        }
      } catch (e) {
        debugPrint('⚠️ Error/Timeout obteniendo boletas de API: $e');
      }
    }

    List<Ticket> res = _localTickets;
    if (raffleId != null) {
      res = res.where((t) => t.raffleId == raffleId).toList();
    }
    if (advisorId != null && advisorId.isNotEmpty) {
      res = res.where((t) => t.advisorId == advisorId).toList();
    }
    if (status != null && status.isNotEmpty) {
      res = res.where((t) => t.status == status).toList();
    }
    if (numberSearch != null && numberSearch.isNotEmpty) {
      String q = numberSearch.trim();
      res = res.where((t) => t.ticketNumber.toString() == q || t.numbers.any((n) => n.contains(q))).toList();
    }
    if (search != null && search.isNotEmpty) {
      String q = search.toLowerCase();
      res = res
          .where((t) =>
              t.ticketNumber.toString().contains(q) ||
              t.buyerName.toLowerCase().contains(q) ||
              t.buyerPhone.contains(q) ||
              t.numbers.any((n) => n.contains(q)))
          .toList();
    }
    return res;
  }

  Future<Ticket> registerAbono(String ticketId, Map<String, dynamic> body) async {
    if (!_useLocalFallback) {
      try {
        final response = await authPost(
          Uri.parse('$baseUrl/tickets/$ticketId/abono'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
        if (response.statusCode == 200) {
          return Ticket.fromJson(jsonDecode(response.body));
        }
      } catch (_) {
        _useLocalFallback = true;
      }
    }

    int idx = _localTickets.indexWhere((t) => t.id == ticketId);
    if (idx != -1) {
      Ticket old = _localTickets[idx];
      double amount = (body['amount'] as num).toDouble();
      List<Abono> ab = List.from(old.abonos);
      if (amount > 0) {
        ab.add(Abono(
          id: 'ab-${DateTime.now().millisecondsSinceEpoch}',
          amount: amount,
          date: DateTime.now().toIso8601String(),
          sellerId: body['sellerId'] ?? 'admin',
          sellerName: body['sellerName'] ?? 'Administrador',
          note: body['note'] ?? 'Abono registrado',
        ));
      } else if (ab.isEmpty) {
        ab.add(Abono(
          id: 'ab-${DateTime.now().millisecondsSinceEpoch}',
          amount: 0,
          date: DateTime.now().toIso8601String(),
          sellerId: body['sellerId'] ?? 'admin',
          sellerName: body['sellerName'] ?? 'Administrador',
          note: body['note'] ?? 'Boleta apartada / fiada sin abono inicial',
        ));
      }

      double newPaid = old.totalPaid + amount;
      double newBal = (old.price - newPaid).clamp(0, double.infinity);
      String newStatus;
      if (newBal <= 0 && newPaid > 0) {
        newStatus = old.confirmedByAdmin ? 'CONFIRMADA' : 'PAGADA';
      } else if (newPaid > 0) {
        newStatus = 'ABONO_PARCIAL';
      } else {
        newStatus = 'RESERVADA'; // Apartada / Fiada ($0)
      }

      Ticket updated = Ticket(
        id: old.id,
        raffleId: old.raffleId,
        ticketNumber: old.ticketNumber,
        numbers: old.numbers,
        price: old.price,
        status: newStatus,
        advisorId: body['sellerId'] ?? old.advisorId,
        advisorName: body['sellerName'] ?? old.advisorName,
        buyerName: body['buyerName'] ?? old.buyerName,
        buyerPhone: body['buyerPhone'] ?? old.buyerPhone,
        totalPaid: newPaid,
        balancePending: newBal,
        confirmedByAdmin: old.confirmedByAdmin,
        assignedDate: old.assignedDate ?? DateTime.now().toIso8601String(),
        abonos: ab,
      );
      _localTickets[idx] = updated;
      return updated;
    }
    throw Exception('Boleta no encontrada');
  }

  Future<Ticket> confirmTicket(String ticketId) async {
    if (!_useLocalFallback) {
      try {
        final response = await authPost(Uri.parse('$baseUrl/tickets/$ticketId/confirm'));
        if (response.statusCode == 200) {
          return Ticket.fromJson(jsonDecode(response.body));
        }
      } catch (_) {
        _useLocalFallback = true;
      }
    }

    int idx = _localTickets.indexWhere((t) => t.id == ticketId);
    if (idx != -1) {
      Ticket old = _localTickets[idx];
      String newStatus = old.status == 'PAGADA' ? 'CONFIRMADA' : old.status;
      Ticket updated = Ticket(
        id: old.id,
        raffleId: old.raffleId,
        ticketNumber: old.ticketNumber,
        numbers: old.numbers,
        price: old.price,
        status: newStatus,
        advisorId: old.advisorId,
        advisorName: old.advisorName,
        buyerName: old.buyerName,
        buyerPhone: old.buyerPhone,
        totalPaid: old.totalPaid,
        balancePending: old.balancePending,
        confirmedByAdmin: true,
        assignedDate: old.assignedDate,
        abonos: old.abonos,
      );
      _localTickets[idx] = updated;
      return updated;
    }
    throw Exception('Boleta no encontrada');
  }

  Future<List<Advisor>> getAdvisors() async {
    if (!_useLocalFallback) {
      try {
        final response = await authGet(Uri.parse('$baseUrl/advisors')).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          List data = jsonDecode(response.body);
          return data.map((json) => Advisor.fromJson(json)).toList();
        }
      } catch (e) {
        debugPrint('⚠️ Error/Timeout obteniendo asesores de API: $e');
      }
    }
    return _localAdvisors;
  }

  Future<Advisor> createAdvisor(Map<String, dynamic> body) async {
    if (!_useLocalFallback) {
      try {
        final response = await authPost(
          Uri.parse('$baseUrl/advisors'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
        if (response.statusCode == 201) {
          return Advisor.fromJson(jsonDecode(response.body));
        }
        throw ApiException.fromResponse(response);
      } on ApiException {
        rethrow;
      } catch (_) {
        _useLocalFallback = true;
      }
    }

    Advisor adv = Advisor(
      id: 'adv-${DateTime.now().millisecondsSinceEpoch}',
      name: body['name'] ?? 'Nuevo Asesor',
      email: body['email'] ?? '',
      username: body['username'] ?? body['code'] ?? '',
      phone: body['phone'] ?? '',
      code: body['code'] ?? 'ADV${DateTime.now().millisecond}',
      mode: body['mode'] ?? 'POOL_GENERAL',
      status: body['status'] ?? 'ACTIVO',
      assignedTicketRanges: (body['assignedTicketRanges'] as List? ?? []).cast<String>(),
      createdAt: DateTime.now().toIso8601String(),
    );
    _localAdvisors.add(adv);
    return adv;
  }

  Future<Advisor> updateAdvisor(String advisorId, Map<String, dynamic> body) async {
    if (!_useLocalFallback) {
      try {
        final response = await authPut(
          Uri.parse('$baseUrl/advisors/$advisorId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
        if (response.statusCode == 200) {
          return Advisor.fromJson(jsonDecode(response.body));
        }
        throw ApiException.fromResponse(response);
      } on ApiException {
        rethrow;
      } catch (_) {
        _useLocalFallback = true;
      }
    }

    int idx = _localAdvisors.indexWhere((a) => a.id == advisorId);
    if (idx != -1) {
      Advisor cur = _localAdvisors[idx];
      Advisor updated = Advisor(
        id: cur.id,
        name: body['name'] ?? cur.name,
        email: body['email'] ?? cur.email,
        username: body['username'] ?? cur.username,
        phone: body['phone'] ?? cur.phone,
        code: body['code'] ?? cur.code,
        mode: body['mode'] ?? cur.mode,
        status: body['status'] ?? cur.status,
        deletionReason: body['deletionReason'] ?? cur.deletionReason,
        assignedTicketRanges:
            body['assignedTicketRanges'] != null ? List<String>.from(body['assignedTicketRanges']) : cur.assignedTicketRanges,
        totalTicketsCount: cur.totalTicketsCount,
        totalSold: cur.totalSold,
        totalCollected: cur.totalCollected,
        totalConfirmed: cur.totalConfirmed,
        pendingTurnIn: cur.pendingTurnIn,
        createdAt: cur.createdAt,
      );
      _localAdvisors[idx] = updated;
      return updated;
    }
    throw Exception('Asesor no encontrado');
  }

  Future<bool> deleteAdvisor(String advisorId, {String? reason}) async {
    if (!_useLocalFallback) {
      try {
        final response = await authDelete(
          Uri.parse('$baseUrl/advisors/$advisorId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'reason': reason}),
        );
        if (response.statusCode == 200 || response.statusCode == 204) {
          _localAdvisors.removeWhere((a) => a.id == advisorId);
          return true;
        }
      } catch (_) {
        _useLocalFallback = true;
      }
    }
    _localAdvisors.removeWhere((a) => a.id == advisorId);
    return true;
  }

  Future<bool> deleteWinner(String winnerId, {String? reason}) async {
    if (!_useLocalFallback) {
      try {
        final response = await authDelete(
          Uri.parse('$baseUrl/winners/$winnerId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'reason': reason}),
        );
        if (response.statusCode == 200 || response.statusCode == 204) {
          _localWinners.removeWhere((w) => w.id == winnerId);
          return true;
        }
      } catch (_) {
        _useLocalFallback = true;
      }
    }
    _localWinners.removeWhere((w) => w.id == winnerId);
    return true;
  }

  Future<WinnerRecord> registerWinner(Map<String, dynamic> body) async {
    if (!_useLocalFallback) {
      try {
        final response = await authPost(
          Uri.parse('$baseUrl/winners'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
        if (response.statusCode == 201) {
          return WinnerRecord.fromJson(jsonDecode(response.body));
        }
        // The server answered but rejected the change: show its reason, never fake success locally
        throw ApiException.fromResponse(response);
      } on ApiException {
        rethrow;
      } catch (_) {
        _useLocalFallback = true;
      }
    }

    String numStr = body['winningNumber'].toString().trim();
    Raffle curRaffle = _localRaffles.firstWhere(
      (r) => r.id == (body['raffleId'] ?? _localRaffles[0].id),
      orElse: () => _localRaffles[0],
    );

    String paddedNumStr = numStr.padLeft(curRaffle.digits, '0');

    Ticket? match;
    for (var t in _localTickets) {
      if (t.numbers.contains(numStr) || t.numbers.contains(paddedNumStr)) {
        match = t;
        break;
      }
    }

    double reqAbono = curRaffle.weeklyMinAbonoType == 'PORCENTAJE'
        ? (curRaffle.ticketPrice * (curRaffle.weeklyMinAbonoValue / 100))
        : curRaffle.weeklyMinAbonoValue;

    bool isWin = match != null && match.status != 'DISPONIBLE' && match.totalPaid >= reqAbono;

    // Calculate previous accumulated pot from active accumulated draws
    double prevAccumulatedPot = 0.0;
    for (var w in _localWinners) {
      if (w.accumulated) {
        prevAccumulatedPot += w.basePrizeAmount;
      }
    }

    double basePrize = (body['prizeAmount'] as num?)?.toDouble() ?? 1000000.0;
    double totalPrize = isWin ? (basePrize + prevAccumulatedPot) : basePrize;

    List<Map<String, dynamic>> abonosSummary = [];
    if (match != null) {
      if (match.abonos.isNotEmpty) {
        abonosSummary = match.abonos
            .map((a) => {
                  'date': a.date,
                  'amount': a.amount,
                  'sellerName': a.sellerName,
                  'note': a.note,
                })
            .toList();
      } else {
        abonosSummary = [
          {
            'date': match.assignedDate ?? DateTime.now().toIso8601String(),
            'amount': match.totalPaid,
            'sellerName': match.advisorName,
            'note': 'Pago / Abono Inicial de Venta',
          }
        ];
      }
    }

    WinnerRecord rec = WinnerRecord(
      id: 'win-${DateTime.now().millisecondsSinceEpoch}',
      raffleId: curRaffle.id,
      drawName: body['drawName'] ?? 'Sorteo Semanal',
      drawDate: body['drawDate'] ?? DateTime.now().toIso8601String(),
      winningNumber: numStr,
      basePrizeAmount: basePrize,
      previousAccumulatedAmount: isWin ? prevAccumulatedPot : 0.0,
      totalPrizePaid: totalPrize,
      isWinner: isWin,
      accumulated: !isWin,
      winnerDetails: match != null
          ? WinnerDetails(
              ticketNumber: match.ticketNumber,
              buyerName: match.buyerName,
              buyerPhone: match.buyerPhone,
              advisorName: match.advisorName,
              status: match.status,
              totalPaid: match.totalPaid,
              minRequiredAmount: reqAbono,
              insufficientAbono: !isWin,
              assignedDate: match.assignedDate,
              abonosSummary: abonosSummary,
            )
          : null,
      photoUrl: body['photoUrl'] ?? '',
      createdAt: DateTime.now().toIso8601String(),
    );

    // If won, clear previous accumulated draws so they don't count for future draws
    if (isWin) {
      for (int i = 0; i < _localWinners.length; i++) {
        var w = _localWinners[i];
        if (w.accumulated) {
          _localWinners[i] = WinnerRecord(
            id: w.id,
            raffleId: w.raffleId,
            drawName: w.drawName,
            drawDate: w.drawDate,
            winningNumber: w.winningNumber,
            basePrizeAmount: w.basePrizeAmount,
            previousAccumulatedAmount: w.previousAccumulatedAmount,
            totalPrizePaid: w.totalPrizePaid,
            isWinner: false,
            accumulated: false, // Marked as consumed / claimed
            lotteryName: w.lotteryName,
            weeklyDrawDay: w.weeklyDrawDay,
            accumulationReason: 'Acumulado entregado en sorteo #${numStr}',
            winnerDetails: w.winnerDetails,
            photoUrl: w.photoUrl,
            createdAt: w.createdAt,
          );
        }
      }
    }

    _localWinners.insert(0, rec);
    return rec;
  }

  Future<List<WinnerRecord>> getWinners() async {
    if (!_useLocalFallback) {
      try {
        final response = await authGet(Uri.parse('$baseUrl/winners')).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          List data = jsonDecode(response.body);
          return data.map((json) => WinnerRecord.fromJson(json)).toList();
        }
      } catch (e) {
        debugPrint('⚠️ Error/Timeout obteniendo ganadores de API: $e');
      }
    }
    return _localWinners;
  }

  Future<Map<String, dynamic>> getCommissions({String? raffleId}) async {
    if (!_useLocalFallback) {
      try {
        final Uri url = raffleId != null && raffleId.isNotEmpty
            ? Uri.parse('$baseUrl/commissions?raffleId=$raffleId')
            : Uri.parse('$baseUrl/commissions');
        final response = await authGet(url).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        }
      } catch (e) {
        debugPrint('⚠️ Error/Timeout obteniendo comisiones de API: $e');
      }
    }

    Raffle raffle = _localRaffles.firstWhere((r) => r.id == raffleId, orElse: () => _localRaffles[0]);
    String commType = raffle.commissionType;
    double commVal = raffle.commissionValue;
    double price = raffle.ticketPrice;

    List<Map<String, dynamic>> advs = _localAdvisors.map((adv) {
      var advTkts = _localTickets.where((t) => t.advisorId == adv.id || t.advisorName.contains(adv.name)).toList();
      int soldCount = advTkts.where((t) => t.status == 'PAGADA' || t.status == 'ABONO_PARCIAL').length;
      double collected = advTkts.fold(0.0, (sum, t) => sum + t.totalPaid);

      double earned = commType == 'VALOR_FIJO' ? (soldCount * commVal) : ((collected * commVal) / 100);
      double paid = 0.0;
      double pending = earned - paid;

      return {
        'advisorId': adv.id,
        'advisorName': adv.name,
        'advisorCode': adv.code,
        'phone': adv.phone,
        'totalTicketsSold': soldCount,
        'totalCollected': collected,
        'commissionEarned': earned,
        'commissionPaid': paid,
        'pendingCommission': pending,
        'payoutsCount': 0
      };
    }).toList();

    return {
      'raffleId': raffle.id,
      'commissionType': commType,
      'commissionValue': commVal,
      'ticketPrice': price,
      'globalCommissionEarned': advs.fold<double>(0.0, (sum, a) => sum + (a['commissionEarned'] as num).toDouble()),
      'globalCommissionPaid': 0.0,
      'globalPendingCommission': advs.fold<double>(0.0, (sum, a) => sum + (a['pendingCommission'] as num).toDouble()),
      'advisors': advs,
      'payoutsHistory': []
    };
  }

  Future<bool> postCommissionPayout({required String advisorId, required double amount, String? note, String? raffleId}) async {
    if (!_useLocalFallback) {
      try {
        final response = await authPost(
          Uri.parse('$baseUrl/commissions/payout'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'advisorId': advisorId, 'amount': amount, 'note': note ?? '', 'raffleId': raffleId}),
        ).timeout(const Duration(seconds: 3));
        if (response.statusCode == 200 || response.statusCode == 201) {
          return true;
        }
      } catch (_) {
        _useLocalFallback = true;
      }
    }
    return true;
  }

  // Company / Group methods (SuperAdmin)
  Future<List<Company>> fetchCompanies() async {
    try {
      final response = await authGet(Uri.parse('$baseUrl/companies')).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        return data.map((c) => Company.fromJson(c)).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<Company> createCompany(Map<String, dynamic> data) async {
    final response = await authPost(
      Uri.parse('$baseUrl/companies'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200 || response.statusCode == 201) {
      return Company.fromJson(jsonDecode(response.body));
    }
    throw ApiException.fromResponse(response);
  }

  Future<Company> updateCompany(String id, Map<String, dynamic> data) async {
    final response = await authPut(
      Uri.parse('$baseUrl/companies/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      return Company.fromJson(jsonDecode(response.body));
    }
    throw ApiException.fromResponse(response);
  }

  Future<bool> deleteCompany(String id) async {
    final response = await authDelete(
      Uri.parse('$baseUrl/companies/$id'),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return true;
    throw ApiException.fromResponse(response);
  }

  Future<bool> deleteRaffle(String id) async {
    final response = await authDelete(
      Uri.parse('$baseUrl/raffles/$id'),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return true;
    throw ApiException.fromResponse(response);
  }

  // Authentication: credentials are validated by the server only
  Future<Map<String, dynamic>> login({required String role, required String username, required String password}) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'role': role, 'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    throw ApiException.fromResponse(response);
  }

  /// Returns the current user if the stored session is still valid, or throws.
  Future<Map<String, dynamic>> currentUser() async {
    final response = await authGet(Uri.parse('$baseUrl/auth/me')).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return (jsonDecode(response.body) as Map<String, dynamic>)['user'] as Map<String, dynamic>;
    throw ApiException.fromResponse(response);
  }

  Future<Map<String, dynamic>> changePassword({required String currentPassword, required String newPassword}) async {
    final response = await authPost(
      Uri.parse('$baseUrl/auth/change-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'currentPassword': currentPassword, 'newPassword': newPassword}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    throw ApiException.fromResponse(response);
  }

  Future<Map<String, dynamic>> updateProfile({required String name, required String email, required String username}) async {
    final response = await authPut(
      Uri.parse('$baseUrl/auth/profile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'email': email, 'username': username}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    throw ApiException.fromResponse(response);
  }

  // Raffle templates (poster / printed ticket images), stored apart from the raffle data
  /// Returns the template image as a data URI, or null when the raffle has none.
  Future<String?> fetchRaffleTemplate(String raffleId, String type) async {
    final response = await authGet(Uri.parse('$baseUrl/raffles/$raffleId/templates/$type')).timeout(const Duration(seconds: 60));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw ApiException.fromResponse(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['dataUri'] as String?;
  }

  Future<void> saveRaffleTemplate(String raffleId, String type, String dataUri) async {
    final response = await authPut(
      Uri.parse('$baseUrl/raffles/$raffleId/templates/$type'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'dataUri': dataUri}),
    ).timeout(const Duration(seconds: 90));
    if (response.statusCode != 200) throw ApiException.fromResponse(response);
  }

  Future<void> deleteRaffleTemplate(String raffleId, String type) async {
    final response = await authDelete(Uri.parse('$baseUrl/raffles/$raffleId/templates/$type')).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 && response.statusCode != 404) throw ApiException.fromResponse(response);
  }
}
