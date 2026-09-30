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

  Future<void> loadTickets({String? raffleId}) async {
    _isLoading = true;
    notifyListeners();

    try {
      _tickets = await _repository.fetchTickets(
        raffleId: raffleId,
        search: _searchQuery,
        status: _selectedStatusFilter == 'TODOS' ? null : _selectedStatusFilter,
        advisorId: _selectedAdvisorFilter,
      );
    } catch (e) {
      debugPrint('Error al cargar boletas: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String query, {String? raffleId}) {
    _searchQuery = query;
    loadTickets(raffleId: raffleId);
  }

  void setStatusFilter(String status, {String? raffleId}) {
    _selectedStatusFilter = status;
    loadTickets(raffleId: raffleId);
  }

  void setAdvisorFilter(String? advisorId, {String? raffleId}) {
    _selectedAdvisorFilter = advisorId;
    loadTickets(raffleId: raffleId);
  }

  Future<bool> addAbono(String ticketId, Map<String, dynamic> body, {String? raffleId}) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _repository.addAbono(ticketId, body);
      await loadTickets(raffleId: raffleId);
      return true;
    } catch (e) {
      debugPrint('Error al registrar abono: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
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
}
