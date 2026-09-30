import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rifaapp/data/models/advisor.dart';
import 'package:rifaapp/data/services/auth_http.dart';
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

  bool _mustChangePassword = false;

  /// True when the server requires this user to replace their password (default or assigned by someone else).
  bool get mustChangePassword => _mustChangePassword;

  bool _sessionExpired = false;
  bool get sessionExpired => _sessionExpired;

  // Session inactivity timeout: 8 hours (the server token itself expires after 12 hours)
  static const int _inactivityTimeoutMs = 8 * 60 * 60 * 1000;
  static const String _tokenKey = 'session_token';
  static const String _lastActivityKey = 'session_last_activity';

  /// Restores a saved session only if the server still accepts its token.
  Future<void> restoreSession() async {
    _isRestoringSession = true;
    AuthSession.onUnauthorized = _handleUnauthorized;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Sessions from older versions (flags without a server token) are discarded
      await _clearLegacySessionKeys(prefs);
      final token = prefs.getString(_tokenKey);
      final lastActivity = prefs.getInt(_lastActivityKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (token != null && token.isNotEmpty && (now - lastActivity) < _inactivityTimeoutMs) {
        AuthSession.token = token;
        final user = await _repository.currentUser();
        _applyUser(user);
        _isLoggedIn = true;
        await touchSession();
      } else {
        await logout(notify: false);
      }
    } catch (e) {
      debugPrint('Sesión no restaurada: $e');
      await logout(notify: false);
    } finally {
      _isRestoringSession = false;
      notifyListeners();
    }
  }

  Future<void> _clearLegacySessionKeys(SharedPreferences prefs) async {
    for (final key in [
      'session_logged_in',
      'session_role',
      'session_admin_name',
      'session_admin_email',
      'session_admin_username',
      'session_selected_company_id',
      'session_company_name',
      'session_active_advisor',
    ]) {
      await prefs.remove(key);
    }
  }

  void _applyUser(Map<String, dynamic> user) {
    switch (user['role']) {
      case 'superadmin':
        _role = UserRole.superadmin;
        break;
      case 'asesor':
        _role = UserRole.asesor;
        break;
      default:
        _role = UserRole.admin;
    }
    _adminName = (user['name'] ?? '').toString();
    _adminEmail = (user['email'] ?? '').toString();
    _adminUsername = (user['username'] ?? '').toString();
    _selectedCompanyId = (user['companyId'] ?? '').toString();
    _companyName = (user['companyName'] ?? '').toString();
    _mustChangePassword = user['mustChangePassword'] == true;
    _activeAdvisor = user['advisor'] is Map ? Advisor.fromJson(Map<String, dynamic>.from(user['advisor'])) : null;
  }

  Future<void> _startSession(Map<String, dynamic> session) async {
    AuthSession.token = session['token'] as String;
    _applyUser(Map<String, dynamic>.from(session['user']));
    _isLoggedIn = true;
    _sessionExpired = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, AuthSession.token!);
    await prefs.setInt(_lastActivityKey, DateTime.now().millisecondsSinceEpoch);
  }

  void _handleUnauthorized() {
    if (!_isLoggedIn) return;
    _sessionExpired = true;
    logout();
  }

  Future<void> touchSession() async {
    if (!_isLoggedIn) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastActivityKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  void setSelectedCompanyId(String companyId) {
    _selectedCompanyId = companyId;
    notifyListeners();
  }

  String get currentUserName {
    if (isSuperAdmin) return _adminName.isNotEmpty ? _adminName : 'SuperAdministrador';
    if (isAdmin) return _adminName;
    return _activeAdvisor?.name ?? _adminName;
  }

  String get currentUserEmail {
    if (isAsesor) return _activeAdvisor?.email ?? _adminEmail;
    return _adminEmail;
  }

  String get currentUserCode {
    if (isSuperAdmin) return 'SUPERADMIN';
    if (isAdmin) return _adminUsername.toUpperCase();
    return _activeAdvisor?.code ?? '';
  }

  Future<bool> loginAsAdmin(String userOrEmail, String password) => _login('admin', userOrEmail, password);

  Future<bool> loginAsAdvisor(String userOrEmail, String password) => _login('asesor', userOrEmail, password);

  /// Credentials are always validated by the server (never locally).
  Future<bool> _login(String role, String userOrEmail, String password) async {
    _loginErrorMessage = '';
    final user = userOrEmail.trim();
    if (user.isEmpty || password.isEmpty) {
      _loginErrorMessage = 'Ingrese usuario y contraseña.';
      notifyListeners();
      return false;
    }

    try {
      final session = await _repository.login(role: role, username: user, password: password);
      await _startSession(session);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _loginErrorMessage = e.message;
    } catch (_) {
      _loginErrorMessage = 'No fue posible conectar con el servidor. Verifique su conexión e intente de nuevo.';
    }
    notifyListeners();
    return false;
  }

  /// Changes the password of the logged-in user. Returns null on success or an error message.
  Future<String?> changePassword({required String currentPassword, required String newPassword}) async {
    try {
      final session = await _repository.changePassword(currentPassword: currentPassword, newPassword: newPassword);
      await _startSession(session);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'No fue posible conectar con el servidor.';
    }
  }

  String recoverPassword(String identifier) {
    if (identifier.trim().isEmpty) return 'Ingrese su usuario o correo electrónico.';
    return 'Por seguridad, las contraseñas solo pueden ser restablecidas por la administración. '
        'Asesores: contacte a su administrador. Administradores: contacte al superadministrador.';
  }

  /// Updates the name/email shown for the current admin in this session.
  Future<void> updateCurrentAdminProfile({required String name, required String email, required String username}) async {
    _adminName = name.trim();
    _adminEmail = email.trim();
    _adminUsername = username.trim();
    notifyListeners();
  }

  Future<void> logout({bool notify = true}) async {
    _isLoggedIn = false;
    _activeAdvisor = null;
    _role = UserRole.admin;
    _loginErrorMessage = _sessionExpired ? 'Su sesión expiró o fue cerrada. Inicie sesión nuevamente.' : '';
    _mustChangePassword = false;
    _adminName = '';
    _adminEmail = '';
    _adminUsername = '';
    _selectedCompanyId = '';
    _companyName = '';
    AuthSession.token = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_lastActivityKey);
    } catch (_) {}

    if (notify) notifyListeners();
  }
}
