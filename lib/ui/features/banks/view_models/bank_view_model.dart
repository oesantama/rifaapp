import 'package:flutter/foundation.dart';
import 'package:rifaapp/data/models/bank.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';

/// Banks from the server: active ones feed the transfer forms; the SuperAdmin manages all.
class BankViewModel extends ChangeNotifier {
  final RaffleRepository _repository;

  BankViewModel({RaffleRepository? repository}) : _repository = repository ?? RaffleRepository();

  List<Bank> _banks = [];
  List<Bank> get banks => _banks;
  List<Bank> get activeBanks => _banks.where((b) => b.active).toList();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _banks = await _repository.fetchBanks();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Creates (id == null) or updates a bank. Returns null on success or the error message.
  Future<String?> save(String? id, Map<String, dynamic> data) async {
    try {
      await _repository.saveBank(id, data);
      await load();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void reset() {
    _banks = [];
    notifyListeners();
  }
}
