import '../models/raffle.dart';
import '../models/ticket.dart';
import '../models/advisor.dart';
import '../models/winner.dart';
import '../services/api_service.dart';

class RaffleRepository {
  final ApiService _apiService;

  RaffleRepository({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  Future<List<Raffle>> fetchRaffles({String? advisorId, bool isAsesor = false}) =>
      _apiService.getRaffles(advisorId: advisorId, isAsesor: isAsesor);

  Future<Raffle> createRaffle(Map<String, dynamic> data) =>
      _apiService.createRaffle(data);

  Future<Raffle> updateRaffle(String raffleId, Map<String, dynamic> data) =>
      _apiService.updateRaffle(raffleId, data);

  Future<List<Ticket>> fetchTickets({
    String? raffleId,
    String? search,
    String? numberSearch,
    String? status,
    String? advisorId,
  }) =>
      _apiService.getTickets(
        raffleId: raffleId,
        search: search,
        numberSearch: numberSearch,
        status: status,
        advisorId: advisorId,
      );

  Future<Ticket> addAbono(String ticketId, Map<String, dynamic> body) =>
      _apiService.registerAbono(ticketId, body);

  Future<Ticket> confirmTicketPayment(String ticketId) =>
      _apiService.confirmTicket(ticketId);

  Future<List<Advisor>> fetchAdvisors() => _apiService.getAdvisors();

  Future<Advisor> createAdvisor(Map<String, dynamic> data) =>
      _apiService.createAdvisor(data);

  Future<Advisor> updateAdvisor(String id, Map<String, dynamic> data) =>
      _apiService.updateAdvisor(id, data);

  Future<List<WinnerRecord>> fetchWinners() => _apiService.getWinners();

  Future<WinnerRecord> registerWinner(Map<String, dynamic> data) =>
      _apiService.registerWinner(data);

  Future<bool> importTickets(String raffleId, List<Map<String, dynamic>> records) =>
      _apiService.importTickets(raffleId, records);

  Future<Map<String, dynamic>> fetchCommissions({String? raffleId}) =>
      _apiService.getCommissions(raffleId: raffleId);

  Future<bool> postCommissionPayout({required String advisorId, required double amount, String? note, String? raffleId}) =>
      _apiService.postCommissionPayout(advisorId: advisorId, amount: amount, note: note, raffleId: raffleId);

  Future<bool> deleteAdvisor(String id, {String? reason}) =>
      _apiService.deleteAdvisor(id, reason: reason);

  Future<bool> deleteWinner(String id, {String? reason}) =>
      _apiService.deleteWinner(id, reason: reason);
}
