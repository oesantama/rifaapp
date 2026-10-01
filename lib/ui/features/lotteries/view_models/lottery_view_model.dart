import 'package:flutter/foundation.dart';
import 'package:rifaapp/data/models/lottery.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';

/// Lotteries from the server: active ones feed the raffle settings; the SuperAdmin manages all.
class LotteryViewModel extends ChangeNotifier {
  final RaffleRepository _repository;

  LotteryViewModel({RaffleRepository? repository}) : _repository = repository ?? RaffleRepository();

  List<Lottery> _lotteries = [];
  List<Lottery> get lotteries => _lotteries;
  List<Lottery> get activeLotteries => _lotteries.where((b) => b.active).toList();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _lotteries = await _repository.fetchLotteries();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Creates (id == null) or updates a lottery. Returns null on success or the error message.
  Future<String?> save(String? id, Map<String, dynamic> data) async {
    try {
      await _repository.saveLottery(id, data);
      await load();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void reset() {
    _lotteries = [];
    notifyListeners();
  }
}
