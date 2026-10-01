import 'package:flutter/foundation.dart';
import '../../../../data/models/advisor.dart';
import '../../../../data/repositories/raffle_repository.dart';

class AdvisorViewModel extends ChangeNotifier {
  final RaffleRepository _repository;

  AdvisorViewModel({RaffleRepository? repository}) : _repository = repository ?? RaffleRepository();

  List<Advisor> _advisors = [];
  List<Advisor> get advisors => _advisors;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Server message of the last failed save (e.g. overlapping ranges), shown to the user.
  String? _lastError;
  String? get lastError => _lastError;

  Map<String, dynamic>? _commissionsData;
  Map<String, dynamic>? get commissionsData => _commissionsData;

  Future<void> loadAdvisors() async {
    _isLoading = true;
    notifyListeners();

    try {
      _advisors = await _repository.fetchAdvisors();
    } catch (e) {
      debugPrint('Error al cargar asesores: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createAdvisor(Map<String, dynamic> data) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      Advisor created = await _repository.createAdvisor(data);
      _advisors.add(created);
      return true;
    } catch (e) {
      debugPrint('Error al crear asesor: $e');
      _lastError = e.toString().replaceFirst(RegExp(r'^(Exception|ApiException[^:]*): ?'), '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateAdvisor(String id, Map<String, dynamic> data) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      Advisor updated = await _repository.updateAdvisor(id, data);
      int idx = _advisors.indexWhere((a) => a.id == id);
      if (idx != -1) {
        _advisors[idx] = updated;
      }
      return true;
    } catch (e) {
      debugPrint('Error al actualizar asesor: $e');
      _lastError = e.toString().replaceFirst(RegExp(r'^(Exception|ApiException[^:]*): ?'), '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Advisors with a pending request for more numbers.
  List<Advisor> get pendingRangeRequests => _advisors.where((a) => a.rangeRequest != null).toList();

  Future<bool> dismissRangeRequest(String advisorId) async {
    try {
      await _repository.dismissRangeRequest(advisorId);
      await loadAdvisors();
      return true;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleAdvisorStatus(Advisor adv) async {
    String newStatus = adv.isActive ? 'INHABILITADO' : 'ACTIVO';
    return updateAdvisor(adv.id, {'status': newStatus});
  }

  Future<bool> deleteAdvisor(String id, String reason) async {
    _isLoading = true;
    notifyListeners();

    try {
      bool ok = await _repository.deleteAdvisor(id, reason: reason);
      if (ok) {
        _advisors.removeWhere((a) => a.id == id);
      }
      return ok;
    } catch (e) {
      debugPrint('Error al eliminar asesor: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCommissions({String? raffleId}) async {
    try {
      _commissionsData = await _repository.fetchCommissions(raffleId: raffleId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error al cargar comisiones: $e');
    }
  }

  Future<bool> registerPayout({
    required String advisorId,
    required double amount,
    String? note,
    String? raffleId,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      bool ok = await _repository.postCommissionPayout(
        advisorId: advisorId,
        amount: amount,
        note: note,
        raffleId: raffleId,
      );
      if (ok) {
        await loadCommissions(raffleId: raffleId);
        await loadAdvisors();
      }
      return ok;
    } catch (e) {
      debugPrint('Error al registrar pago de comisiones: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Drops data from a previous session so another user never sees it.
  void reset() {
    _advisors = [];
    notifyListeners();
  }
}
