import 'package:flutter/foundation.dart';
import '../../../../data/models/raffle.dart';
import '../../../../data/repositories/raffle_repository.dart';

class RaffleViewModel extends ChangeNotifier {
  final RaffleRepository _repository;

  RaffleViewModel({RaffleRepository? repository})
      : _repository = repository ?? RaffleRepository();

  List<Raffle> _raffles = [];
  List<Raffle> get raffles => _raffles;

  Raffle? _selectedRaffle;
  Raffle? get selectedRaffle => _selectedRaffle;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Future<void> loadRaffles({String? advisorId, bool isAsesor = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _raffles = await _repository.fetchRaffles(advisorId: advisorId, isAsesor: isAsesor);
      if (_raffles.isNotEmpty) {
        if (_selectedRaffle == null || !_raffles.any((r) => r.id == _selectedRaffle!.id)) {
          _selectedRaffle = _raffles.first;
        } else {
          _selectedRaffle = _raffles.firstWhere((r) => r.id == _selectedRaffle!.id);
        }
      } else {
        _selectedRaffle = null;
      }
    } catch (e) {
      _errorMessage = 'Error al cargar sorteos: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectRaffle(Raffle raffle) {
    _selectedRaffle = raffle;
    notifyListeners();
  }

  Future<bool> createRaffle(Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      Raffle created = await _repository.createRaffle(data);
      _raffles.insert(0, created);
      _selectedRaffle = created;
      return true;
    } catch (e) {
      _errorMessage = 'Error al crear sorteo: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateRaffle(String raffleId, Map<String, dynamic> data) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      Raffle updated = await _repository.updateRaffle(raffleId, data);
      int idx = _raffles.indexWhere((r) => r.id == raffleId);
      if (idx != -1) {
        _raffles[idx] = updated;
      }
      if (_selectedRaffle?.id == raffleId) {
        _selectedRaffle = updated;
      }
      return true;
    } catch (e) {
      _errorMessage = 'Error al actualizar sorteo: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
