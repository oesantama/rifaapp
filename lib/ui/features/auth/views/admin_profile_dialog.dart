import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';

class AdminProfileDialog extends StatefulWidget {
  const AdminProfileDialog({super.key});

  @override
  State<AdminProfileDialog> createState() => _AdminProfileDialogState();
}

class _AdminProfileDialogState extends State<AdminProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    _nameController = TextEditingController(text: authVM.adminName);
    _emailController = TextEditingController(text: authVM.adminEmail);
    _usernameController = TextEditingController(text: authVM.adminUsername);
    _passwordController = TextEditingController(text: '1234');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authVM = Provider.of<AuthViewModel>(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.admin_panel_settings, color: AppTheme.primaryBlue),
          SizedBox(width: 10),
          Text('Editar Perfil Administrador', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Modifica los datos personales y credenciales de acceso para tu cuenta de Administrador:',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo del Administrador *',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Ingrese el nombre' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo Electrónico *',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Ingrese el correo electrónico';
                    if (!val.contains('@') || !val.contains('.')) return 'Ingrese un correo válido';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de Usuario / Cédula *',
                    prefixIcon: Icon(Icons.account_box),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Ingrese el nombre de usuario' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Nueva Contraseña (o mantener actual)',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val != null && val.isNotEmpty && val.length < 4) {
                      return 'La contraseña debe tener al menos 4 caracteres';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('Guardar Cambios'),
          onPressed: () async {
            if (_formKey.currentState!.validate()) {
              await authVM.updateCurrentAdminProfile(
                name: _nameController.text.trim(),
                email: _emailController.text.trim(),
                username: _usernameController.text.trim(),
                password: _passwordController.text.trim(),
              );

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: AppTheme.secondaryEmerald,
                    content: Text('¡Perfil de Administrador actualizado correctamente!'),
                  ),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ],
    );
  }
}
