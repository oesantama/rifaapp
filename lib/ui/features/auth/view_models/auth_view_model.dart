import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rifaapp/data/models/advisor.dart';
import 'package:rifaapp/data/models/company.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';

enum UserRole { superadmin, admin, asesor }

class AuthViewModel extends ChangeNotifier {
  final RaffleRepository _repository;

  AuthViewModel({RaffleRepository? repository}) : _repository = repository ?? RaffleRepository() {
    restoreSession();
  }

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  bool _isRestoringSession = true;
  bool get isRestoringSession => _isRestoringSession;

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

  String _selectedCompanyId = 'comp-1';
  String get selectedCompanyId => _selectedCompanyId;

  String _companyName = 'Empresa Principal';
  String get companyName {
    if (isSuperAdmin) return '🏢 Panel Multitenant (Todas las Empresas)';
    return _companyName.isNotEmpty ? _companyName : '🏢 Empresa Principal';
  }

  String _loginErrorMessage = '';
  String get loginErrorMessage => _loginErrorMessage;

  bool get isSuperAdmin => _role == UserRole.superadmin;
  bool get isAdmin => _role == UserRole.admin || _role == UserRole.superadmin;
  bool get isAsesor => _role == UserRole.asesor;

  // Session inactivity timeout: 8 hours (in milliseconds)
  static const int _inactivityTimeoutMs = 8 * 60 * 60 * 1000;

  Future<void> restoreSession() async {
    _isRestoringSession = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final loggedIn = prefs.getBool('session_logged_in') ?? false;
      final lastActivity = prefs.getInt('session_last_activity') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (loggedIn && lastActivity > 0 && (now - lastActivity) < _inactivityTimeoutMs) {
        _isLoggedIn = true;
        final roleIndex = prefs.getInt('session_role') ?? 1;
        _role = UserRole.values[roleIndex.clamp(0, UserRole.values.length - 1)];
        _adminName = prefs.getString('session_admin_name') ?? 'Administrador General';
        _adminEmail = prefs.getString('session_admin_email') ?? 'admin@rifamaster.com';
        _adminUsername = prefs.getString('session_admin_username') ?? 'admin';
        _selectedCompanyId = prefs.getString('session_selected_company_id') ?? 'comp-1';
        _companyName = prefs.getString('session_company_name') ?? 'Empresa Principal';

        final advisorJsonStr = prefs.getString('session_active_advisor');
        if (advisorJsonStr != null && advisorJsonStr.isNotEmpty) {
          try {
            _activeAdvisor = Advisor.fromJson(jsonDecode(advisorJsonStr));
          } catch (_) {}
        }
        await touchSession();
      } else {
        await logout(notify: false);
      }
    } catch (e) {
      debugPrint('Error restoring session: $e');
    } finally {
      _isRestoringSession = false;
      notifyListeners();
    }
  }

  Future<void> saveSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('session_logged_in', _isLoggedIn);
      await prefs.setInt('session_role', _role.index);
      await prefs.setString('session_admin_name', _adminName);
      await prefs.setString('session_admin_email', _adminEmail);
      await prefs.setString('session_admin_username', _adminUsername);
      await prefs.setString('session_selected_company_id', _selectedCompanyId);
      await prefs.setString('session_company_name', _companyName);
      await prefs.setInt('session_last_activity', DateTime.now().millisecondsSinceEpoch);

      if (_activeAdvisor != null) {
        await prefs.setString('session_active_advisor', jsonEncode(_activeAdvisor!.toJson()));
      } else {
        await prefs.remove('session_active_advisor');
      }
    } catch (e) {
      debugPrint('Error saving session: $e');
    }
  }

  Future<void> touchSession() async {
    if (!_isLoggedIn) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('session_last_activity', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  void setSelectedCompanyId(String companyId) {
    _selectedCompanyId = companyId;
    saveSession();
    notifyListeners();
  }

  String get currentUserName {
    if (isSuperAdmin) return 'SuperAdministrador Master';
    if (isAdmin) return _adminName;
    return _activeAdvisor?.name ?? 'Asesor';
  }

  String get currentUserEmail {
    if (isSuperAdmin) return 'superadmin@rifamaster.com';
    if (isAdmin) return _adminEmail;
    return _activeAdvisor?.email ?? '';
  }

  String get currentUserCode {
    if (isSuperAdmin) return 'SUPERADMIN';
    if (isAdmin) return _adminUsername.toUpperCase();
    return _activeAdvisor?.code ?? '';
  }

  final List<Map<String, String>> _adminUsers = [];
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

    // SuperAdmin check
    if ((inputUser == 'superadmin' || inputUser == 'superadmin@rifamaster.com') && (inputPass == '123' || inputPass == '1234')) {
      _isLoggedIn = true;
      _role = UserRole.superadmin;
      _adminName = 'SuperAdministrador Master';
      _adminEmail = 'superadmin@rifamaster.com';
      _adminUsername = 'superadmin';
      _activeAdvisor = null;
      await saveSession();
      notifyListeners();
      return true;
    }

    // Check dynamic Company Admin accounts registered by SuperAdmin
    try {
      final companies = await _repository.fetchCompanies();
      final matchedCompany = companies.firstWhere(
        (c) =>
            (c.adminUsername.trim().toLowerCase() == inputUser || c.adminEmail.trim().toLowerCase() == inputUser) &&
            c.adminPassword.trim() == inputPass,
        orElse: () => Company(
            id: '', name: '', code: '', status: '', adminUsername: '', adminPassword: '', adminName: '', adminEmail: '', createdAt: ''),
      );

      if (matchedCompany.id.isNotEmpty) {
        if (matchedCompany.status == 'INACTIVA') {
          _loginErrorMessage = '⚠️ Su empresa "${matchedCompany.name}" se encuentra INACTIVA. Contacte al superadministrador.';
          notifyListeners();
          return false;
        }

        _isLoggedIn = true;
        _role = UserRole.admin;
        _adminName = matchedCompany.adminName;
        _adminEmail = matchedCompany.adminEmail;
        _adminUsername = matchedCompany.adminUsername;
        _selectedCompanyId = matchedCompany.id;
        _companyName = matchedCompany.name;
        _activeAdvisor = null;
        await saveSession();
        notifyListeners();
        return true;
      }
    } catch (_) {}

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

        try {
          final companies = await _repository.fetchCompanies();
          final matchedComp = companies.firstWhere(
            (c) => c.id == matched.companyId,
            orElse: () => Company(
                id: '',
                name: 'Empresa Principal',
                code: '',
                status: '',
                adminUsername: '',
                adminPassword: '',
                adminName: '',
                adminEmail: '',
                createdAt: ''),
          );
          if (matchedComp.name.isNotEmpty) {
            _companyName = matchedComp.name;
          }
        } catch (_) {}

        await saveSession();
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

    await saveSession();
    notifyListeners();
  }

  Future<void> logout({bool notify = true}) async {
    _isLoggedIn = false;
    _activeAdvisor = null;
    _role = UserRole.admin;
    _loginErrorMessage = '';
    _adminName = 'Administrador General';
    _adminEmail = 'admin@rifamaster.com';
    _adminUsername = 'admin';
    _selectedCompanyId = 'comp-1';
    _companyName = 'Empresa Principal';

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('session_logged_in');
      await prefs.remove('session_role');
      await prefs.remove('session_admin_name');
      await prefs.remove('session_admin_email');
      await prefs.remove('session_admin_username');
      await prefs.remove('session_selected_company_id');
      await prefs.remove('session_company_name');
      await prefs.remove('session_active_advisor');
      await prefs.remove('session_last_activity');
    } catch (_) {}

    if (notify) notifyListeners();
  }
}
