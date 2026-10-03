import 'package:flutter/foundation.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';

class TicketViewModel extends ChangeNotifier {
  final RaffleRepository _repository;

  TicketViewModel({RaffleRepository? repository}) : _repository = repository ?? RaffleRepository();

  List<Ticket> _tickets = [];
  List<Ticket> get tickets => _tickets;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  String _selectedStatusFilter = 'TODOS';
  String get selectedStatusFilter => _selectedStatusFilter;

  String? _selectedAdvisorFilter;
  String? get selectedAdvisorFilter => _selectedAdvisorFilter;

  /// Loads every ticket of the raffle. Search, status and advisor filters are applied
  /// locally, so [tickets] always holds the full raffle (dashboard, cash, winners, poster)
  /// and the grid can show how many tickets each status has.
  Future<void> loadTickets({String? raffleId}) async {
    _isLoading = true;
    notifyListeners();

    try {
      _tickets = await _repository.fetchTickets(raffleId: raffleId);
    } catch (e) {
      debugPrint('Error al cargar boletas: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  bool _matchesSearch(Ticket t) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return t.ticketNumber.toString().contains(q) ||
        t.buyerName.toLowerCase().contains(q) ||
        t.buyerPhone.contains(q) ||
        t.buyerDocument.toLowerCase().contains(q) ||
        t.numbers.any((n) => n.contains(q));
  }

  /// Sales of each advisor in the loaded raffle, by status (key: advisorId).
  Map<String, AdvisorSales> salesByAdvisor() {
    final result = <String, AdvisorSales>{};
    for (final t in _tickets) {
      if (t.status == 'DISPONIBLE' || t.advisorId.isEmpty) continue;
      final s = result.putIfAbsent(t.advisorId, () => AdvisorSales());
      switch (t.status) {
        case 'RESERVADA':
          s.reservadas++;
          break;
        case 'ABONO_PARCIAL':
          s.abonadas++;
          break;
        default: // PAGADA, CONFIRMADA
          s.pagadas++;
      }
      s.collected += t.totalPaid;
      if (t.confirmedByAdmin) s.confirmed += t.totalPaid;
    }
    return result;
  }

  /// Tickets matching the search and advisor filter, before the status filter.
  List<Ticket> get searchedTickets =>
      _tickets.where((t) => (_selectedAdvisorFilter == null || t.advisorId == _selectedAdvisorFilter) && _matchesSearch(t)).toList();

  static bool matchesStatus(Ticket t, String status) => status == 'TODOS' || t.status == status;

  /// Number of tickets per status (plus 'TODOS') within [source].
  static Map<String, int> countByStatus(List<Ticket> source) {
    final counts = <String, int>{'TODOS': source.length};
    for (final t in source) {
      counts[t.status] = (counts[t.status] ?? 0) + 1;
    }
    return counts;
  }

  void setSearchQuery(String query, {String? raffleId}) {
    _searchQuery = query;
    notifyListeners();
  }

  void setStatusFilter(String status, {String? raffleId}) {
    _selectedStatusFilter = status;
    notifyListeners();
  }

  void setAdvisorFilter(String? advisorId, {String? raffleId}) {
    _selectedAdvisorFilter = advisorId;
    notifyListeners();
  }

  String? _lastError;

  /// Reason the last save failed, as explained by the server (or a connection problem).
  String? get lastError => _lastError;

  Future<bool> addAbono(String ticketId, Map<String, dynamic> body, {String? raffleId}) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      await _repository.addAbono(ticketId, body);
      await loadTickets(raffleId: raffleId);
      return true;
    } catch (e) {
      debugPrint('Error al registrar abono: $e');
      _lastError = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Payments already registered with this transfer approval number; throws if the check fails.
  Future<List<Map<String, dynamic>>> checkTransferApproval(String raffleId, String approvalNumber) =>
      _repository.checkTransferApproval(raffleId, approvalNumber);

  /// The company's WhatsApp message for a saved ticket ('receipt' or 'reminder'); throws if it fails.
  Future<Map<String, dynamic>> fetchWhatsAppMessage(String ticketId, {String kind = 'receipt'}) =>
      _repository.fetchTicketWhatsAppMessage(ticketId, kind: kind);

  /// Voids one payment and reloads the raffle. Returns null on success or the error message.
  Future<String?> voidAbono(String ticketId, String abonoId, String reason, {String? raffleId}) async {
    try {
      await _repository.voidAbono(ticketId, abonoId, reason);
      await loadTickets(raffleId: raffleId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Voids a sale and reloads the raffle. Returns null on success or the error message.
  Future<String?> voidTicket(String ticketId, String reason, {String? raffleId}) async {
    try {
      await _repository.voidTicket(ticketId, reason);
      await loadTickets(raffleId: raffleId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<bool> confirmTicketPayment(String ticketId, {String? raffleId}) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _repository.confirmTicketPayment(ticketId);
      await loadTickets(raffleId: raffleId);
      return true;
    } catch (e) {
      debugPrint('Error al confirmar pago: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> importTickets(String raffleId, List<Map<String, dynamic>> records) async {
    _isLoading = true;
    notifyListeners();

    try {
      bool ok = await _repository.importTickets(raffleId, records);
      await loadTickets(raffleId: raffleId);
      return ok;
    } catch (e) {
      debugPrint('Error al importar boletas: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Calculated Metrics
  int get countTotal => _tickets.length;
  int get countPagadas => _tickets.where((t) => t.status == 'PAGADA' || t.status == 'CONFIRMADA').length;
  int get countAbonadas => _tickets.where((t) => t.status == 'ABONO_PARCIAL').length;
  int get countReservadas => _tickets.where((t) => t.status == 'RESERVADA').length;
  int get countDisponibles => _tickets.where((t) => t.status == 'DISPONIBLE').length;

  double get totalCollected => _tickets.fold(0.0, (sum, t) => sum + t.totalPaid);
  double get totalConfirmed => _tickets.where((t) => t.confirmedByAdmin).fold(0.0, (sum, t) => sum + t.totalPaid);
  double get totalPendingTurnIn => totalCollected - totalConfirmed;

  /// Drops data from a previous session so another user never sees it.
  void reset() {
    _tickets = [];
    _searchQuery = '';
    _selectedStatusFilter = 'TODOS';
    _selectedAdvisorFilter = null;
    notifyListeners();
  }
}

/// One advisor's sales in a raffle: reserved (fiadas), with partial payments, fully paid.
class AdvisorSales {
  int reservadas = 0;
  int abonadas = 0;
  int pagadas = 0;
  double collected = 0;
  double confirmed = 0;

  /// Total sold = reserved + partially paid + paid.
  int get total => reservadas + abonadas + pagadas;
  double get pendingTurnIn => collected - confirmed;
}
