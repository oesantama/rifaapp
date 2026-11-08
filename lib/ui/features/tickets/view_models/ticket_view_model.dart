import 'dart:math';
import 'package:rifaapp/ui/core/utils/text_search.dart';
import 'package:flutter/foundation.dart';
import 'package:rifaapp/data/services/auth_http.dart';
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

  int _currentRevision = 0;
  int get currentRevision => _currentRevision;
  bool _isBackgroundSyncing = false;
  bool get isBackgroundSyncing => _isBackgroundSyncing;

  /// Loads every ticket of the raffle. Search, status and advisor filters are applied
  /// locally, so [tickets] always holds the full raffle (dashboard, cash, winners, poster)
  /// and the grid can show how many tickets each status has.
  int _loadSeq = 0;
  bool _loadFailed = false;
  /// true si la última carga falló (se conserva la lista anterior en pantalla).
  bool get loadFailed => _loadFailed;

  Future<void> loadTickets({String? raffleId}) async {
    // Varias pantallas piden la carga a la vez (rifa distinta, refresco tras un abono…): solo cuenta la última pedida,
    // para que una respuesta lenta y vieja no pise a la nueva.
    final seq = ++_loadSeq;
    _isLoading = true;
    notifyListeners();

    try {
      final fresh = await _repository.fetchTickets(raffleId: raffleId);
      if (seq != _loadSeq) return;
      _tickets = fresh;
      _loadFailed = false;
      if (raffleId != null && raffleId.isNotEmpty) {
        _currentRevision = await _repository.getRaffleRevision(raffleId);
      }
    } catch (e) {
      debugPrint('Error al cargar boletas: $e');
      if (seq == _loadSeq) _loadFailed = true; // se conservan las boletas que ya estaban en pantalla
    } finally {
      if (seq == _loadSeq) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Silently checks if the server revision has changed.
  /// If changed, reloads tickets in the background without triggering _isLoading
  /// (avoiding full-screen spinner, jitter, or resetting user view).
  Future<void> syncIfChanged({required String raffleId}) async {
    if (_isLoading || _isBackgroundSyncing || raffleId.isEmpty) return;
    try {
      final remoteRev = await _repository.getRaffleRevision(raffleId);
      if (_currentRevision == 0) {
        _currentRevision = remoteRev;
        return;
      }
      if (remoteRev > _currentRevision) {
        _isBackgroundSyncing = true;
        // Cuando alguien vende, TODOS los equipos se enteran a la vez: un retraso aleatorio evita que pidan la lista completa en el mismo instante
        await Future.delayed(Duration(milliseconds: 100 + Random().nextInt(1500)));
        final seq = _loadSeq;
        final freshTickets = await _repository.fetchTickets(raffleId: raffleId);
        if (seq != _loadSeq || _isLoading) {
          _isBackgroundSyncing = false;
          return;
        }
        _tickets = freshTickets;
        _currentRevision = remoteRev;
        _isBackgroundSyncing = false;
        notifyListeners();
      }
    } catch (e) {
      _isBackgroundSyncing = false;
    }
  }

  bool _matchesSearch(Ticket t) {
    // Sin distinguir mayúsculas, tildes ni espacios repetidos: "maria jose" encuentra "María José"
    final q = foldText(_searchQuery);
    if (q.isEmpty) return true;
    // Asesor, oportunidad (número que juega), nombre, celular, cédula y correo del comprador. NO el id interno de la boleta:
    // buscar "204" traía boletas cuyo id contiene 204 aunque su oportunidad fuera otra.
    return foldText(t.advisorName).contains(q) ||
        foldText(t.buyerName).contains(q) ||
        t.buyerPhone.contains(q) ||
        foldText(t.buyerDocument).contains(q) ||
        foldText(t.buyerEmail).contains(q) ||
        t.numbers.any((n) => n.contains(q));
  }

  /// Sales of each advisor in the loaded raffle, by status (key: advisorId).
  Map<String, AdvisorSales> salesByAdvisor({Map<String, String> advisorTypes = const {}}) {
    final result = <String, AdvisorSales>{};
    for (final t in _tickets) {
      if (t.status == 'DISPONIBLE' || t.advisorId.isEmpty) continue;
      final s = result.putIfAbsent(t.advisorId, () => AdvisorSales());
      // Zona de la venta: la guardada o, en ventas anteriores, la que corresponde al tipo del asesor
      final zone = t.saleZone.isNotEmpty ? t.saleZone : (advisorTypes[t.advisorId] == 'PUNTO' ? 'OFICINA' : 'CALLE');
      zone == 'OFICINA' ? s.oficina++ : s.calle++;
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

  static bool matchesStatus(Ticket t, String status) {
    if (status == 'TODOS') return true;
    if (status == 'POR_VALIDAR') {
      return t.abonos.any((a) => a.isTransfer && a.cashState == 'POR_VALIDAR');
    }
    return t.status == status;
  }

  /// Number of tickets per status (plus 'TODOS') within [source].
  static Map<String, int> countByStatus(List<Ticket> source) {
    final counts = <String, int>{'TODOS': source.length};
    for (final t in source) {
      counts[t.status] = (counts[t.status] ?? 0) + 1;
    }
    counts['POR_VALIDAR'] = source.where((t) => t.abonos.any((a) => a.isTransfer && a.cashState == 'POR_VALIDAR')).length;
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
  String? _lastErrorCode;
  Map<String, dynamic>? _lastErrorData;
  String? get lastErrorCode => _lastErrorCode;
  Map<String, dynamic>? get lastErrorData => _lastErrorData;

  Future<bool> addAbono(String ticketId, Map<String, dynamic> body, {String? raffleId}) async {
    _isLoading = true;
    _lastError = null;
    _lastErrorCode = null;
    _lastErrorData = null;
    notifyListeners();

    try {
      await _repository.addAbono(ticketId, body);
      await loadTickets(raffleId: raffleId);
      return true;
    } catch (e) {
      debugPrint('Error al registrar abono: $e');
      _lastError = e.toString();
      if (e is ApiException) {
        _lastErrorCode = e.code;
        _lastErrorData = e.data;
      }
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Payments already registered with this transfer approval number; throws if the check fails.
  Future<Map<String, dynamic>> checkTransferApproval(String raffleId, String approvalNumber,
          {String? ticketId, double? amount, double? proofAmount}) =>
      _repository.checkTransferApproval(raffleId, approvalNumber, ticketId: ticketId, amount: amount, proofAmount: proofAmount);

  /// Reads the proof image on the server (reference, amount, bank).
  Future<Map<String, dynamic>> readTransferProof(String imageDataUri) => _repository.readTransferProof(imageDataUri);

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
  /// Ventas de oficina/punto (no comisionan) y de calle.
  int oficina = 0;
  int calle = 0;
  double collected = 0;
  double confirmed = 0;

  /// Total sold = reserved + partially paid + paid.
  int get total => reservadas + abonadas + pagadas;
  double get pendingTurnIn => collected - confirmed;
}
