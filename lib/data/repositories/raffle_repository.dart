import 'dart:typed_data';
import '../models/sale_channel.dart';
import '../models/bank.dart';
import '../models/lottery.dart';
import '../models/cash_delivery.dart';
import '../models/raffle.dart';
import '../models/ticket.dart';
import '../models/advisor.dart';
import '../models/winner.dart';
import '../models/company.dart';
import '../services/api_service.dart';

class RaffleRepository {
  final ApiService _apiService;

  RaffleRepository({ApiService? apiService}) : _apiService = apiService ?? ApiService();

  Future<List<Company>> fetchCompanies() => _apiService.fetchCompanies();

  Future<List<Raffle>> fetchRaffles({String? advisorId, bool isAsesor = false}) =>
      _apiService.getRaffles(advisorId: advisorId, isAsesor: isAsesor);

  Future<Raffle> createRaffle(Map<String, dynamic> data) => _apiService.createRaffle(data);

  Future<Raffle> updateRaffle(String raffleId, Map<String, dynamic> data) => _apiService.updateRaffle(raffleId, data);

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

  Future<Ticket> addAbono(String ticketId, Map<String, dynamic> body) => _apiService.registerAbono(ticketId, body);

  Future<Ticket> confirmTicketPayment(String ticketId) => _apiService.confirmTicket(ticketId);

  Future<List<Advisor>> fetchAdvisors() => _apiService.getAdvisors();

  Future<Advisor> createAdvisor(Map<String, dynamic> data) => _apiService.createAdvisor(data);

  Future<Advisor> updateAdvisor(String id, Map<String, dynamic> data) => _apiService.updateAdvisor(id, data);

  Future<void> requestMoreTickets(int quantity, String note) => _apiService.requestMoreTickets(quantity, note);

  Future<void> dismissRangeRequest(String advisorId) => _apiService.dismissRangeRequest(advisorId);

  Future<List<Map<String, dynamic>>> checkTransferApproval(String raffleId, String approvalNumber) =>
      _apiService.checkTransferApproval(raffleId, approvalNumber);

  Future<List<WinnerRecord>> fetchWinners() => _apiService.getWinners();

  Future<WinnerRecord> registerWinner(Map<String, dynamic> data) => _apiService.registerWinner(data);

  Future<Map<String, dynamic>> saveMainDrawDecision(String winnerId, Map<String, dynamic> body) =>
      _apiService.saveMainDrawDecision(winnerId, body);

  Future<WinnerRecord> savePrizeDelivery(String winnerId, Map<String, dynamic> body) => _apiService.savePrizeDelivery(winnerId, body);

  Future<bool> importTickets(String raffleId, List<Map<String, dynamic>> records) => _apiService.importTickets(raffleId, records);

  Future<Map<String, dynamic>> fetchCommissions({String? raffleId}) => _apiService.getCommissions(raffleId: raffleId);

  Future<bool> postCommissionPayout({required String advisorId, required double amount, String? note, String? raffleId}) =>
      _apiService.postCommissionPayout(advisorId: advisorId, amount: amount, note: note, raffleId: raffleId);

  Future<bool> deleteAdvisor(String id, {String? reason}) => _apiService.deleteAdvisor(id, reason: reason);

  Future<bool> deleteWinner(String id, {String? reason}) => _apiService.deleteWinner(id, reason: reason);

  Future<Map<String, dynamic>> login({required String role, required String username, required String password}) =>
      _apiService.login(role: role, username: username, password: password);

  Future<Map<String, dynamic>> loginDemo() => _apiService.loginDemo();

  Future<Map<String, dynamic>> currentUser() => _apiService.currentUser();

  Future<Map<String, dynamic>> changePassword({required String currentPassword, required String newPassword}) =>
      _apiService.changePassword(currentPassword: currentPassword, newPassword: newPassword);

  Future<Map<String, dynamic>> updateProfile({required String name, required String email, required String username}) =>
      _apiService.updateProfile(name: name, email: email, username: username);

  Future<bool> deleteCompany(String id) => _apiService.deleteCompany(id);

  Future<bool> deleteRaffle(String id) => _apiService.deleteRaffle(id);

  Future<String?> fetchRaffleTemplate(String raffleId, String type) => _apiService.fetchRaffleTemplate(raffleId, type);

  Future<void> saveRaffleTemplate(String raffleId, String type, String dataUri) => _apiService.saveRaffleTemplate(raffleId, type, dataUri);

  Future<void> deleteRaffleTemplate(String raffleId, String type) => _apiService.deleteRaffleTemplate(raffleId, type);

  Future<Ticket> voidTicket(String ticketId, String reason) => _apiService.voidTicket(ticketId, reason);

  Future<Ticket> voidAbono(String ticketId, String abonoId, String reason) => _apiService.voidAbono(ticketId, abonoId, reason);

  Future<List<SaleChannel>> fetchSaleChannels() => _apiService.fetchSaleChannels();

  Future<SaleChannel> saveSaleChannel(String? id, Map<String, dynamic> data) => _apiService.saveSaleChannel(id, data);

  Future<List<Bank>> fetchBanks() => _apiService.fetchBanks();

  Future<List<Lottery>> fetchLotteries() => _apiService.fetchLotteries();

  Future<Map<String, dynamic>> fetchAppConfig() => _apiService.fetchAppConfig();

  Future<Ticket> verifyTransferPayment(String ticketId, String abonoId, String action, {String note = ''}) =>
      _apiService.verifyTransferPayment(ticketId, abonoId, action, note: note);

  Future<Ticket> receiveCashPayment(String ticketId, String abonoId) => _apiService.receiveCashPayment(ticketId, abonoId);

  Future<Uint8List> fetchDriveFile(String fileId) => _apiService.fetchDriveFile(fileId);

  Future<String> requestAccountDeletion(String reason) => _apiService.requestAccountDeletion(reason);

  Future<Map<String, dynamic>> fetchLegal() => _apiService.fetchLegal();

  Future<void> saveLegal(Map<String, dynamic> data) => _apiService.saveLegal(data);

  Future<List<Map<String, dynamic>>> fetchDeletionRequests() => _apiService.fetchDeletionRequests();

  Future<void> resolveDeletionRequest(String id, String status, {String note = ''}) =>
      _apiService.resolveDeletionRequest(id, status, note: note);

  Future<Raffle> closeRaffle(String raffleId, {bool reopen = false}) => _apiService.closeRaffle(raffleId, reopen: reopen);

  Future<Uint8List> exportRaffle(String raffleId) => _apiService.exportRaffle(raffleId);

  Future<List<CashDelivery>> fetchCashDeliveries({String? raffleId}) => _apiService.fetchCashDeliveries(raffleId: raffleId);

  Future<CashDelivery> reportCashDelivery(Map<String, dynamic> body) => _apiService.reportCashDelivery(body);

  Future<CashDelivery> reviewCashDelivery(String id, String action, {String reason = ''}) =>
      _apiService.reviewCashDelivery(id, action, reason: reason);

  Future<Map<String, dynamic>> fetchMonetization() => _apiService.fetchMonetization();

  Future<Map<String, dynamic>> saveMonetization(Map<String, dynamic> data) => _apiService.saveMonetization(data);

  Future<Map<String, dynamic>> resetDemo() => _apiService.resetDemo();

  Future<Map<String, dynamic>> fetchMonetizationSummary() => _apiService.fetchMonetizationSummary();

  Future<List<Map<String, dynamic>>> fetchSubscriptionPayments({String? companyId}) =>
      _apiService.fetchSubscriptionPayments(companyId: companyId);

  Future<Map<String, dynamic>> registerSubscriptionPayment(Map<String, dynamic> body) => _apiService.registerSubscriptionPayment(body);

  Future<void> voidSubscriptionPayment(String id, String reason) => _apiService.voidSubscriptionPayment(id, reason);

  Future<Map<String, dynamic>> fetchMyPlan() => _apiService.fetchMyPlan();

  Future<Lottery> saveLottery(String? id, Map<String, dynamic> data) => _apiService.saveLottery(id, data);

  Future<Bank> saveBank(String? id, Map<String, dynamic> data) => _apiService.saveBank(id, data);

  Future<Map<String, dynamic>> fetchTerms({String? raffleId}) => _apiService.fetchTerms(raffleId: raffleId);

  Future<String?> previewTerms(String template, {String? raffleId}) => _apiService.previewTerms(template, raffleId: raffleId);

  Future<void> saveTerms(String template) => _apiService.saveTerms(template);

  Future<Map<String, dynamic>> fetchMessageTemplates() => _apiService.fetchMessageTemplates();

  Future<void> saveMessageTemplate(String type, String template) => _apiService.saveMessageTemplate(type, template);

  Future<Map<String, dynamic>> previewMessageTemplate(String type, String template, {String? raffleId}) =>
      _apiService.previewMessageTemplate(type, template, raffleId: raffleId);

  Future<Map<String, dynamic>> fetchTicketWhatsAppMessage(String ticketId, {String kind = 'receipt'}) =>
      _apiService.fetchTicketWhatsAppMessage(ticketId, kind: kind);

  Future<List<Map<String, dynamic>>> fetchVoidHistory({String? raffleId}) => _apiService.fetchVoidHistory(raffleId: raffleId);

  Future<String> forgotPassword(String identifier) => _apiService.forgotPassword(identifier);

  Future<String> resetPassword(String identifier, String code, String newPassword) =>
      _apiService.resetPassword(identifier, code, newPassword);

  Future<Map<String, dynamic>> fetchServerInfo() => _apiService.fetchServerInfo();
}
