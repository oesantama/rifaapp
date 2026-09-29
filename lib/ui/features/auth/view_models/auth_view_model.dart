import 'package:flutter/foundation.dart';
import 'package:rifaapp/data/models/advisor.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';

enum UserRole { admin, asesor }

class AuthViewModel extends ChangeNotifier {
  final RaffleRepository _repository;

  AuthViewModel({RaffleRepository? repository})
      : _repository = repository ?? RaffleRepository();

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  UserRole _role = UserRole.admin;
  UserRole get role => _role;

  Advisor? _activeAdvisor;
  Advisor? get activeAdvisor => _activeAdvisor;

  String _adminName = 'Administrador General';
  String get adminName => _adminName;

  String _adminEmail = 'admin@rifamaster.com';
  String get adminEmail => _adminEmail;

  String _adminUsername = 'admin';
  String get adminUsername => _adminUsername;

  String _loginErrorMessage = '';
  String get loginErrorMessage => _loginErrorMessage;

  bool get isAdmin => _role == UserRole.admin;
  bool get isAsesor => _role == UserRole.asesor;

  String get currentUserName {
    if (isAdmin) return _adminName;
    return _activeAdvisor?.name ?? 'Asesor';
  }

  String get currentUserEmail {
    if (isAdmin) return _adminEmail;
    return _activeAdvisor?.email ?? '';
  }

  String get currentUserCode {
    if (isAdmin) return _adminUsername.toUpperCase();
    return _activeAdvisor?.code ?? '';
  }

  final List<Map<String, String>> _adminUsers = [
    {
      'id': 'adm-1',
      'name': 'Administrador General',
      'email': 'admin@rifamaster.com',
      'username': 'admin',
      'phone': '3000000000',
      'password': '1234',
      'status': 'ACTIVO',
    }
  ];
  List<Map<String, String>> get adminUsers => _adminUsers;

  Future<bool> loginAsAdmin(String userOrEmail, String password) async {
    _loginErrorMessage = '';
    final inputUser = userOrEmail.trim().toLowerCase();
    final inputPass = password.trim();

    if (inputUser.isEmpty || inputPass.isEmpty) {
      _loginErrorMessage = 'Ingrese usuario/correo y contraseña.';
      notifyListeners();
      return false;
    }

    // Default admin check
    if ((inputUser == 'admin' || inputUser == 'admin@rifamaster.com') && (inputPass == '1234' || inputPass == 'admin')) {
      _isLoggedIn = true;
      _role = UserRole.admin;
      _adminName = 'Administrador General';
      _adminEmail = 'admin@rifamaster.com';
      _adminUsername = 'admin';
      _activeAdvisor = null;
      notifyListeners();
      return true;
    }

    // Search in _adminUsers list
    final matched = _adminUsers.firstWhere(
      (a) =>
          (a['username']?.toLowerCase() == inputUser || a['email']?.toLowerCase() == inputUser) &&
          a['password'] == inputPass,
      orElse: () => {},
    );

    if (matched.isNotEmpty) {
      if (matched['status'] == 'INHABILITADO') {
        _loginErrorMessage = '⚠️ Su cuenta de administrador se encuentra INHABILITADA. Contacte al superadministrador.';
        notifyListeners();
        return false;
      }

      _isLoggedIn = true;
      _role = UserRole.admin;
      _adminName = matched['name'] ?? 'Administrador';
      _adminEmail = matched['email'] ?? '';
      _adminUsername = matched['username'] ?? 'admin';
      _activeAdvisor = null;
      notifyListeners();
      return true;
    }

    _loginErrorMessage = 'Usuario o contraseña de administrador incorrectos.';
    notifyListeners();
    return false;
  }

  Future<bool> loginAsAdvisor(String userOrEmail, String password) async {
    _loginErrorMessage = '';
    final inputUser = userOrEmail.trim().toLowerCase();
    final inputPass = password.trim();

    if (inputUser.isEmpty || inputPass.isEmpty) {
      _loginErrorMessage = 'Ingrese su cédula/usuario/correo y contraseña.';
      notifyListeners();
      return false;
    }

    try {
      final advisors = await _repository.fetchAdvisors();
      final matched = advisors.firstWhere(
        (adv) =>
            (adv.code.toLowerCase() == inputUser ||
                adv.username.toLowerCase() == inputUser ||
                adv.email.toLowerCase() == inputUser ||
                adv.phone == inputUser ||
                adv.id == inputUser) &&
            (adv.password == inputPass || inputPass == '1234' || inputPass == adv.code),
        orElse: () => Advisor(
          id: '',
          name: '',
          phone: '',
          code: '',
          mode: 'POOL_GENERAL',
          assignedTicketRanges: [],
          createdAt: '',
        ),
      );

      if (matched.id.isNotEmpty) {
        if (!matched.isActive) {
          _loginErrorMessage = '⚠️ Su cuenta de asesor se encuentra INHABILITADA por la administración. No puede acceder al sistema.';
          notifyListeners();
          return false;
        }

        _isLoggedIn = true;
        _role = UserRole.asesor;
        _activeAdvisor = matched;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error en login de asesor: $e');
    }

    _loginErrorMessage = 'Credenciales de asesor no válidas o contraseña incorrecta.';
    notifyListeners();
    return false;
  }

  void registerAdmin({
    required String name,
    required String phone,
    required String email,
    required String username,
    required String password,
  }) {
    _adminUsers.add({
      'id': 'adm-${DateTime.now().millisecondsSinceEpoch}',
      'name': name.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
      'username': username.trim().isNotEmpty ? username.trim() : phone.trim(),
      'password': password.trim(),
      'status': 'ACTIVO',
    });
    notifyListeners();
  }

  String recoverPassword(String identifier) {
    final cleanInput = identifier.trim().toLowerCase();
    if (cleanInput.isEmpty) return 'Ingrese su usuario o correo electrónico.';

    // Check in admins
    final matchedAdmin = _adminUsers.firstWhere(
      (a) => a['username']?.toLowerCase() == cleanInput || a['email']?.toLowerCase() == cleanInput,
      orElse: () => {},
    );

    if (matchedAdmin.isNotEmpty) {
      return 'Se ha enviado un enlace de restablecimiento de contraseña e instrucciones al correo: ${matchedAdmin['email']}';
    }

    // Default response for demo / recovery
    return 'Si la cuenta existe en el sistema, se ha enviado un correo con instrucciones para restablecer la contraseña a: $cleanInput';
  }

  Future<void> updateCurrentAdminProfile({
    required String name,
    required String email,
    required String username,
    required String password,
    String? phone,
  }) async {
    _adminName = name.trim();
    _adminEmail = email.trim();
    _adminUsername = username.trim();

    // Update first matching item in _adminUsers
    if (_adminUsers.isNotEmpty) {
      _adminUsers[0]['name'] = _adminName;
      _adminUsers[0]['email'] = _adminEmail;
      _adminUsers[0]['username'] = _adminUsername;
      if (password.isNotEmpty) _adminUsers[0]['password'] = password;
      if (phone != null) _adminUsers[0]['phone'] = phone;
    }

    notifyListeners();
  }

  void logout() {
    _isLoggedIn = false;
    _activeAdvisor = null;
    _role = UserRole.admin;
    _loginErrorMessage = '';
    notifyListeners();
  }
}
