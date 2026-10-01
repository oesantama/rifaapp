import 'package:flutter/foundation.dart';
import 'package:rifaapp/data/models/sale_channel.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';

/// Sale channels from the server: active ones feed the sale form; the SuperAdmin manages all.
class SaleChannelViewModel extends ChangeNotifier {
  final RaffleRepository _repository;

  SaleChannelViewModel({RaffleRepository? repository}) : _repository = repository ?? RaffleRepository();

  List<SaleChannel> _channels = [];
  List<SaleChannel> get channels => _channels;
  List<SaleChannel> get activeChannels => _channels.where((c) => c.active).toList();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  /// Channel by name, also for inactive ones (old tickets keep showing their color/icon).
  SaleChannel? byName(String name) {
    for (final c in _channels) {
      if (c.name == name) return c;
    }
    return null;
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _channels = await _repository.fetchSaleChannels();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Creates (id == null) or updates a channel. Returns null on success or the error message.
  Future<String?> save(String? id, Map<String, dynamic> data) async {
    try {
      await _repository.saveSaleChannel(id, data);
      await load();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void reset() {
    _channels = [];
    notifyListeners();
  }
}
