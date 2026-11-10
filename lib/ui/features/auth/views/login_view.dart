import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rifaapp/data/services/auth_http.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';
import 'package:rifaapp/ui/features/legal/legal_widgets.dart';
import 'package:rifaapp/version.dart';
import 'package:rifaapp/ui/features/monetization/app_config_view_model.dart';
import 'package:rifaapp/ui/core/utils/url_launcher_helper.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/widgets/app_logo.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  UserRole _selectedRole = UserRole.admin;
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _userFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  // "Recordar contraseña": recuerda el usuario y le pide al navegador (o al administrador de contraseñas del celular) guardar la contraseña.
  // La contraseña nunca se guarda en la aplicación.
  bool _rememberMe = false;
  static const _kRememberUser = 'login_remember_user';
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Explain why the user is back at the login (expired or revoked session)
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    if (authVM.sessionExpired && authVM.loginErrorMessage.isNotEmpty) {
      _errorMessage = authVM.loginErrorMessage;
    }
    _loadRemembered();
  }

  Future<void> _loadRemembered() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = prefs.getString(_kRememberUser);
      if (user != null && user.isNotEmpty && mounted) {
        setState(() {
          _rememberMe = true;
          if (_userController.text.isEmpty) _userController.text = user;
        });
        _focusPassword();
      }
    } catch (_) {}
  }

  Future<void> _saveRemembered() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString(_kRememberUser, _userController.text.trim());
      } else {
        await prefs.remove(_kRememberUser);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    _userFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (_isLoading) return;
    // Both fields are always required; the server validates the credentials
    if (_userController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = _userController.text.trim().isEmpty ? 'Ingrese su usuario o correo.' : 'Ingrese su contraseña.';
      });
      return;
    }
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    bool success = false;
    String? unexpected;

    try {
      // Tope de espera: si el servidor no responde (por ejemplo, mientras se reinicia) el formulario no se queda congelado
      success = await (_selectedRole == UserRole.admin
              ? authVM.loginAsAdmin(_userController.text, _passwordController.text)
              : authVM.loginAsAdvisor(_userController.text, _passwordController.text))
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      unexpected = 'No hubo respuesta del servidor. Intente de nuevo en unos segundos.';
    }

    if (success) {
      // shouldSave: el navegador ofrece guardar la contraseña solo si la persona marcó "Recordar contraseña"
      TextInput.finishAutofillContext(shouldSave: _rememberMe);
      await _saveRemembered();
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (!success) {
          _errorMessage = unexpected ??
              (authVM.loginErrorMessage.isNotEmpty ? authVM.loginErrorMessage : 'Usuario o contraseña incorrectos. Verifique sus credenciales.');
          _passwordController.clear();
        }
      });
      // Tras un intento fallido el navegador deja el campo "enfocado" pero sin conexión con el teclado (hay que refrescar).
      // Se cierra el contexto de autocompletado, se suelta el foco y se vuelve a pedir en el siguiente ciclo: crea una conexión nueva.
      if (!success) {
        TextInput.finishAutofillContext(shouldSave: false);
        _passwordFocus.unfocus();
        Future.delayed(const Duration(milliseconds: 120), () {
          if (mounted) _focusPassword();
        });
      }
    }
  }

  /// Devuelve el teclado al campo de contraseña. En web, un clic fuera del campo (por ejemplo en el ojo) quita el foco
  /// real del navegador aunque Flutter crea que sigue enfocado: se vuelve a pedir el teclado de forma explícita.
  void _focusPassword() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _passwordFocus.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  void _handleDemoLogin() async {
    if (_isLoading) return;
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    bool success = false;
    try {
      success = await authVM.loginDemo().timeout(const Duration(seconds: 25));
    } catch (_) {
      success = false;
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (!success) {
          _errorMessage = authVM.loginErrorMessage.isNotEmpty ? authVM.loginErrorMessage : 'No fue posible iniciar la sesión Demo.';
        }
      });
    }
  }

  /// Password recovery: (1) a 6-digit code is sent to the account's e-mail, (2) code + new password.
  void _showPasswordRecoveryDialog() {
    final idCtrl = TextEditingController(text: _userController.text.trim());
    final codeCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool codeSent = false;
    bool busy = false;
    bool obscure = true;
    String? info;
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          Future<void> run(Future<String> Function() action, {bool next = false}) async {
            setD(() {
              busy = true;
              error = null;
            });
            try {
              final msg = await action();
              setD(() {
                info = msg;
                if (next) codeSent = true;
              });
              if (!next && ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppTheme.secondaryEmerald, content: Text(msg)));
              }
            } catch (e) {
              setD(() => error = e is ApiException ? e.message : e.toString());
            } finally {
              if (ctx.mounted) setD(() => busy = false);
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.lock_reset, color: AppTheme.primaryBlue),
                SizedBox(width: 10),
                Expanded(child: Text('Recuperar contraseña', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      codeSent
                          ? 'Escriba el código de 6 dígitos que le llegó al correo y su nueva contraseña.'
                          : 'Escriba su usuario o correo. Le enviaremos un código de 6 dígitos al correo registrado en su cuenta.',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: idCtrl,
                      enabled: !codeSent,
                      decoration: const InputDecoration(
                        labelText: 'Usuario o correo *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    if (codeSent) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: codeCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Código de 6 dígitos *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.pin_outlined),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passCtrl,
                        obscureText: obscure,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(
                          labelText: 'Nueva contraseña *',
                          helperText: 'Mínimo 8 caracteres, con letras y números',
                          helperMaxLines: 2,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setD(() => obscure = !obscure),
                          ),
                        ),
                      ),
                    ],
                    if (info != null && error == null) ...[
                      const SizedBox(height: 12),
                      Text(info!, style: TextStyle(fontSize: 12.5, color: Colors.blue.shade800)),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!, style: const TextStyle(color: AppTheme.dangerRose, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancelar')),
              if (codeSent)
                TextButton(
                  onPressed: busy ? null : () => run(() => RaffleRepository().forgotPassword(idCtrl.text.trim()), next: true),
                  child: const Text('Reenviar código'),
                ),
              ElevatedButton(
                onPressed: busy
                    ? null
                    : () {
                        if (idCtrl.text.trim().isEmpty) {
                          setD(() => error = 'Escriba su usuario o correo.');
                          return;
                        }
                        if (!codeSent) {
                          run(() => RaffleRepository().forgotPassword(idCtrl.text.trim()), next: true);
                        } else {
                          if (codeCtrl.text.trim().length != 6) {
                            setD(() => error = 'El código tiene 6 dígitos.');
                            return;
                          }
                          run(() => RaffleRepository().resetPassword(idCtrl.text.trim(), codeCtrl.text.trim(), passCtrl.text));
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                child: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(codeSent ? 'CAMBIAR CONTRASEÑA' : 'ENVIAR CÓDIGO'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 420;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 24, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 20 : 32, vertical: isCompact ? 28 : 32),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 35,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Professional Header Logo / Badge
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: AppLogo(size: isCompact ? 76 : 88),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'RIFA MASTER',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sistema Profesional de Control de Rifas, Juegos y Espectáculos',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w400),
                  ),
                  const SizedBox(height: 4),
                  const Text('Versión $appVersion', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white38)),
                  const SizedBox(height: 28),

                  // Role selector toggle
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedRole = UserRole.admin;
                                _userController.clear();
                                _passwordController.clear();
                                _errorMessage = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                              decoration: BoxDecoration(
                                color: _selectedRole == UserRole.admin ? AppTheme.primaryBlue : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.admin_panel_settings,
                                      size: 18, color: _selectedRole == UserRole.admin ? Colors.white : Colors.grey),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'Administrador',
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: _selectedRole == UserRole.admin ? Colors.white : Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedRole = UserRole.asesor;
                                _userController.clear();
                                _passwordController.clear();
                                _errorMessage = null;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                              decoration: BoxDecoration(
                                color: _selectedRole == UserRole.asesor ? AppTheme.primaryBlue : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person, size: 18, color: _selectedRole == UserRole.asesor ? Colors.white : Colors.grey),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'Asesor / Vendedor',
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: _selectedRole == UserRole.asesor ? Colors.white : Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // One autofill group: browsers and password managers treat both fields as one login form
                  AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Username / Email Input Field
                        Text(
                          _selectedRole == UserRole.admin ? 'Usuario o Correo (Admin):' : 'Usuario / Cédula / Correo (Asesor):',
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _userController,
                          focusNode: _userFocus,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          enableSuggestions: false,
                          onSubmitted: (_) => _passwordFocus.requestFocus(),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            prefixIcon: Icon(_selectedRole == UserRole.admin ? Icons.admin_panel_settings_outlined : Icons.person_outline,
                                color: Colors.grey),
                            hintText:
                                _selectedRole == UserRole.admin ? 'Usuario o correo del administrador' : 'Código, cédula, usuario o correo',
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password Input Field
                        const Text(
                          'Contraseña / Clave de Acceso:',
                          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          enableSuggestions: false,
                          autocorrect: false,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
                            // The eye button must not take the focus: otherwise the next keystrokes go nowhere
                            suffixIcon: ExcludeFocus(
                              child: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                                tooltip: _obscurePassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                  // Cambiar entre ocultar/mostrar recrea el campo en el navegador: se devuelve el teclado
                                  _focusPassword();
                                },
                              ),
                            ),
                            hintText: 'Ingrese su contraseña',
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          onSubmitted: (_) => _handleLogin(),
                        ),
                      ],
                    ),
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: _isLoading ? null : () => setState(() => _rememberMe = !_rememberMe),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                visualDensity: VisualDensity.compact,
                                side: const BorderSide(color: Colors.white54),
                                onChanged: _isLoading ? null : (v) => setState(() => _rememberMe = v ?? false),
                              ),
                              const Flexible(
                                child: Text('Recordar contraseña', style: TextStyle(color: Colors.white70, fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Password Recovery Link
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showPasswordRecoveryDialog,
                      child: const Text(
                        '¿Olvidó su contraseña?',
                        style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerRose.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.dangerRose.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppTheme.dangerRose, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_errorMessage!,
                                style: const TextStyle(color: AppTheme.dangerRose, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Submit button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _selectedRole == UserRole.admin ? 'INGRESAR COMO ADMINISTRADOR' : 'INGRESAR COMO ASESOR',
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                            ),
                          ),
                  ),

                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.devices, size: 16, color: Color(0xFF38BDF8)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Disponible para tu celular o PC:',
                                style: TextStyle(
                                  color: Color(0xFFCBD5E1),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: downloadApk,
                                icon: const Icon(Icons.android, size: 18, color: Colors.white),
                                label: const Text(
                                  'Descargar APK',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: promptPwaInstall,
                                icon: const Icon(Icons.install_mobile, size: 18, color: Colors.white),
                                label: const Text(
                                  'Instalar PWA',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Modo demo: separado del ingreso y con aspecto de enlace, para que no se confunda con "Ingresar"
                  if (context.watch<AppConfigViewModel>().demoEnabled) ...[
                    const SizedBox(height: 18),
                    const Divider(color: Color(0xFF334155)),
                    const SizedBox(height: 6),
                    Center(
                      child: Text('¿Aún no tiene cuenta y quiere conocer la app?', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                    TextButton.icon(
                      onPressed: _isLoading ? null : _handleDemoLogin,
                      icon: const Icon(Icons.science_outlined, color: Colors.amber, size: 18),
                      label: const Text('Probar modo demo (datos de ejemplo, se reinicia cada 48 h)',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ],

                  const SizedBox(height: 12),
                  const LegalLinks(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
