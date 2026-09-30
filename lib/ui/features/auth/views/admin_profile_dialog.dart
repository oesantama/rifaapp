import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/features/auth/views/change_password_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    _nameController = TextEditingController(text: authVM.adminName);
    _emailController = TextEditingController(text: authVM.adminEmail);
    _usernameController = TextEditingController(text: authVM.adminUsername);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authVM = Provider.of<AuthViewModel>(context);
    final isSuperAdmin = authVM.isSuperAdmin;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.admin_panel_settings, color: isSuperAdmin ? Colors.purpleAccent : AppTheme.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isSuperAdmin ? 'Perfil SuperAdministrador Master' : 'Editar Perfil Administrador',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
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
                Text(
                  isSuperAdmin
                      ? 'Modifique sus datos personales y usuario de acceso principal para la cuenta de SuperAdmin:'
                      : 'Modifica los datos personales y credenciales de acceso para tu cuenta de Administrador:',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo *',
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
                    labelText: 'Nombre de Usuario *',
                    prefixIcon: Icon(Icons.account_box),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Ingrese el nombre de usuario' : null,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    ChangePasswordDialog.show(context);
                  },
                  icon: const Icon(Icons.lock_reset_rounded),
                  label: const Text('Cambiar mi contraseña'),
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
              final error = await authVM.updateCurrentAdminProfile(
                name: _nameController.text.trim(),
                email: _emailController.text.trim(),
                username: _usernameController.text.trim(),
              );

              if (mounted) {
                if (error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: AppTheme.dangerRose, content: Text(error)),
                  );
                } else {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppTheme.secondaryEmerald,
                      content: Text('✓ ¡Perfil actualizado correctamente!'),
                    ),
                  );
                }
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isSuperAdmin ? Colors.purple.shade800 : AppTheme.primaryBlue,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ],
    );
  }
}
