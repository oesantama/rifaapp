import 'package:flutter/foundation.dart';
import 'package:rifaapp/data/models/cash_delivery.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';

/// Advisors' cash deliveries and the admin's cash actions. Ticket data comes from TicketViewModel;
/// after an action the caller reloads the tickets.
class CashViewModel extends ChangeNotifier {
  final RaffleRepository _repository;

  CashViewModel({RaffleRepository? repository}) : _repository = repository ?? RaffleRepository();

  List<CashDelivery> _deliveries = [];
  List<CashDelivery> get deliveries => _deliveries;
  List<CashDelivery> get pendingDeliveries => _deliveries.where((d) => d.isPending).toList();

  bool _loading = false;
  bool get isLoading => _loading;

  Future<void> loadDeliveries({String? raffleId}) async {
    _loading = true;
    notifyListeners();
    try {
      _deliveries = await _repository.fetchCashDeliveries(raffleId: raffleId);
    } catch (e) {
      debugPrint('No se pudieron cargar las entregas: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Each action returns null on success or the error message.
  Future<String?> _run(Future<void> Function() action, {String? raffleId}) async {
    try {
      await action();
      await loadDeliveries(raffleId: raffleId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> verifyTransfer(String ticketId, String abonoId, String action, {String note = '', String? raffleId}) =>
      _run(() => _repository.verifyTransferPayment(ticketId, abonoId, action, note: note), raffleId: raffleId);

  Future<String?> receiveCash(String ticketId, String abonoId, {String? raffleId}) =>
      _run(() => _repository.receiveCashPayment(ticketId, abonoId), raffleId: raffleId);

  Future<String?> reportDelivery(Map<String, dynamic> body, {String? raffleId}) =>
      _run(() => _repository.reportCashDelivery(body), raffleId: raffleId);

  Future<String?> reviewDelivery(String id, String action, {String reason = '', String? raffleId}) =>
      _run(() => _repository.reviewCashDelivery(id, action, reason: reason), raffleId: raffleId);

  void reset() {
    _deliveries = [];
    notifyListeners();
  }
}
