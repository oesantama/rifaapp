import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';

/// Same rule the server enforces: 8+ characters combining letters and numbers.
String? validateNewPassword(String? value) {
  final v = value ?? '';
  if (v.length < 8) return 'Mínimo 8 caracteres.';
  if (!RegExp(r'[A-Za-zÁÉÍÓÚáéíóúÑñ]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
    return 'Debe combinar letras y números.';
  }
  return null;
}

/// Lets the logged-in user change their own password. With [required] the dialog
/// cannot be dismissed (used when the password is the default or was assigned by someone else).
class ChangePasswordDialog extends StatefulWidget {
  final bool required;

  const ChangePasswordDialog({super.key, this.required = false});

  static Future<void> show(BuildContext context, {bool required = false}) {
    return showDialog(
      context: context,
      barrierDismissible: !required,
      builder: (_) => PopScope(canPop: !required, child: ChangePasswordDialog(required: required)),
    );
  }

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final error = await authVM.changePassword(currentPassword: _currentCtrl.text, newPassword: _newCtrl.text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(backgroundColor: AppTheme.secondaryEmerald, content: Text('Contraseña actualizada correctamente.')),
    );
  }

  Widget _strengthBar() {
    final v = _newCtrl.text;
    int score = 0;
    if (v.length >= 8) score++;
    if (v.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(v) && RegExp(r'[a-z]').hasMatch(v)) score++;
    if (RegExp(r'\d').hasMatch(v)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(v)) score++;
    final labels = ['Muy débil', 'Débil', 'Aceptable', 'Buena', 'Fuerte', 'Muy fuerte'];
    final colors = [
      AppTheme.dangerRose,
      AppTheme.dangerRose,
      AppTheme.accentAmber,
      AppTheme.accentAmber,
      AppTheme.secondaryEmerald,
      AppTheme.secondaryEmerald
    ];
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: v.isEmpty ? 0 : (score + 1) / 6,
              minHeight: 6,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(colors[score]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(v.isEmpty ? '' : labels[score], style: TextStyle(fontSize: 11, color: colors[score], fontWeight: FontWeight.w600)),
      ],
    );
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
          tooltip: _obscure ? 'Mostrar' : 'Ocultar',
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_reset_rounded, color: AppTheme.primaryBlue),
          SizedBox(width: 10),
          Expanded(child: Text('Cambiar contraseña', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.required)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.accentAmber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.accentAmber.withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_outlined, color: AppTheme.accentAmber, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Por seguridad debe definir una contraseña personal antes de continuar. '
                              'La contraseña actual es temporal o fue asignada por otra persona.',
                              style: TextStyle(fontSize: 12, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextFormField(
                    controller: _currentCtrl,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    decoration: _decoration('Contraseña actual', Icons.lock_outline),
                    validator: (v) => (v == null || v.isEmpty) ? 'Ingrese su contraseña actual.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _newCtrl,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: _decoration('Nueva contraseña', Icons.lock_reset),
                    onChanged: (_) => setState(() {}),
                    validator: validateNewPassword,
                  ),
                  const SizedBox(height: 8),
                  _strengthBar(),
                  const SizedBox(height: 4),
                  Text('Mínimo 8 caracteres, combinando letras y números.', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmCtrl,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: _decoration('Confirmar nueva contraseña', Icons.check_circle_outline),
                    validator: (v) => v != _newCtrl.text ? 'Las contraseñas no coinciden.' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppTheme.dangerRose, fontWeight: FontWeight.w600, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (widget.required)
          TextButton(
            onPressed: _saving
                ? null
                : () => Provider.of<AuthViewModel>(context, listen: false).logout().then((_) {
                      if (context.mounted) Navigator.of(context).pop();
                    }),
            child: const Text('Cerrar sesión'),
          )
        else
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Guardar contraseña'),
        ),
      ],
    );
  }
}
