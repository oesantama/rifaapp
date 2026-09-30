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

  Future<WinnerRecord?> registerWinner(Map<String, dynamic> data) async {
    _isLoading = true;
    notifyListeners();

    try {
      WinnerRecord rec = await _repository.registerWinner(data);
      _winners.insert(0, rec);
      return rec;
    } catch (e) {
      debugPrint('Error al registrar ganador/sorteo: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
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
}
