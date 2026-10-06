import 'package:flutter/foundation.dart';
import '../../../../data/models/winner.dart';
import '../../../../data/repositories/raffle_repository.dart';

class WinnerViewModel extends ChangeNotifier {
  final RaffleRepository _repository;

  WinnerViewModel({RaffleRepository? repository}) : _repository = repository ?? RaffleRepository();

  List<WinnerRecord> _winners = [];
  List<WinnerRecord> get winners => _winners;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> loadWinners() async {
    _isLoading = true;
    notifyListeners();

    try {
      _winners = await _repository.fetchWinners();
    } catch (e) {
      debugPrint('Error al cargar ganadores: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String? _lastError;

  /// Reason the last registration failed (as explained by the server).
  String? get lastError => _lastError;

  Future<WinnerRecord?> registerWinner(Map<String, dynamic> data) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      WinnerRecord rec = await _repository.registerWinner(data);
      _winners.insert(0, rec);
      return rec;
    } catch (e) {
      debugPrint('Error al registrar ganador/sorteo: $e');
      _lastError = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Records who received a prize (or removes it with cancel: true); returns the error or null.
  Future<String?> savePrizeDelivery(String winnerId, Map<String, dynamic> body) async {
    try {
      final updated = await _repository.savePrizeDelivery(winnerId, body);
      final idx = _winners.indexWhere((w) => w.id == winnerId);
      if (idx != -1) _winners[idx] = updated;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Main draw (gran premio) results of a raffle, latest first (earlier ones were played again).
  List<WinnerRecord> mainDrawsOf(String raffleId) =>
      _winners.where((w) => w.raffleId == raffleId && w.isMainDraw).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Plays a main draw without winner again on another date, or closes it. Returns
  /// (error, raffle json) so the caller can refresh the raffle.
  Future<(String?, Map<String, dynamic>?)> saveMainDrawDecision(String winnerId, Map<String, dynamic> body) async {
    try {
      final r = await _repository.saveMainDrawDecision(winnerId, body);
      final updated = WinnerRecord.fromJson(Map<String, dynamic>.from(r['record']));
      final idx = _winners.indexWhere((w) => w.id == winnerId);
      if (idx != -1) _winners[idx] = updated;
      notifyListeners();
      return (null, r['raffle'] is Map ? Map<String, dynamic>.from(r['raffle']) : null);
    } catch (e) {
      return (e.toString(), null);
    }
  }

  Future<bool> deleteWinner(String id, String reason) async {
    _isLoading = true;
    notifyListeners();

    try {
      bool ok = await _repository.deleteWinner(id, reason: reason);
      if (ok) {
        _winners.removeWhere((w) => w.id == id);
      }
      return ok;
    } catch (e) {
      debugPrint('Error al eliminar sorteo: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  int get accumulatedCount => _winners.where((w) => w.accumulated).length;
  double get totalAccumulatedAmount => _winners.where((w) => w.accumulated).fold(0.0, (sum, w) => sum + w.basePrizeAmount);

  int get totalWinnersCount => _winners.where((w) => w.isWinner).length;
  double get totalPrizesPaid => _winners.where((w) => w.isWinner).fold(0.0, (sum, w) => sum + w.prizeAmount);

  /// Drops data from a previous session so another user never sees it.
  void reset() {
    _winners = [];
    notifyListeners();
  }
}
