import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/company.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/theme.dart';

class CompanyManagementView extends StatefulWidget {
  const CompanyManagementView({super.key});

  @override
  State<CompanyManagementView> createState() => _CompanyManagementViewState();
}

class _CompanyManagementViewState extends State<CompanyManagementView> {
  final ApiService _apiService = ApiService();
  List<Company> _companies = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    setState(() => _isLoading = true);
    try {
      List<Company> result = await _apiService.fetchCompanies();
      setState(() {
        _companies = result;
      });
    } catch (_) {
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showCreateCompanyDialog() {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final adminNameController = TextEditingController();
    final adminEmailController = TextEditingController();
    final adminUsernameController = TextEditingController();
    final adminPasswordController = TextEditingController(text: '123');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.business_rounded, color: AppTheme.primaryBlue),
              SizedBox(width: 10),
              Text('Registrar Nueva Empresa / Grupo'),
            ],
          ),
          content: SingleChildScrollView(
            child: Container(
              width: 500,
              padding: const EdgeInsets.all(8),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de la Empresa / Grupo *',
                        hintText: 'Ej: Rifas San Martín S.A.S.',
                        prefixIcon: Icon(Icons.apartment),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'El nombre es obligatorio' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: codeController,
                      decoration: const InputDecoration(
                        labelText: 'Código Identificador',
                        hintText: 'Ej: EMP02 (Opcional)',
                        prefixIcon: Icon(Icons.qr_code),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const Text(
                      '👤 Credenciales para el Administrador de la Empresa:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryDark),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: adminNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre Completo del Admin',
                        hintText: 'Ej: Carlos Pérez',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: adminEmailController,
                      decoration: const InputDecoration(
                        labelText: 'Correo Electrónico',
                        hintText: 'admin@empresa.com',
                        prefixIcon: Icon(Icons.email),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: adminUsernameController,
                            decoration: const InputDecoration(
                              labelText: 'Usuario Admin *',
                              hintText: 'ej: admin_sanmartin',
                              prefixIcon: Icon(Icons.account_circle),
                            ),
                            validator: (val) => val == null || val.trim().isEmpty ? 'Usuario requerido' : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: adminPasswordController,
                            decoration: const InputDecoration(
                              labelText: 'Contraseña *',
                              prefixIcon: Icon(Icons.lock),
                            ),
                            validator: (val) => val == null || val.trim().isEmpty ? 'Contraseña requerida' : null,
                          ),
                        ),
                      ],
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
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final data = {
                    'name': nameController.text.trim(),
                    'code': codeController.text.trim(),
                    'adminName': adminNameController.text.trim(),
                    'adminEmail': adminEmailController.text.trim(),
                    'adminUsername': adminUsernameController.text.trim(),
                    'adminPassword': adminPasswordController.text.trim(),
                  };
                  Navigator.pop(context);
                  Company? created = await _apiService.createCompany(data);
                  if (created != null) {
                    _loadCompanies();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppTheme.secondaryEmerald,
                          content: Text('✓ Empresa "${created.name}" creada exitosamente con usuario Admin "${created.adminUsername}".'),
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Crear Empresa y Admin'),
            ),
          ],
        );
      },
    );
  }

  void _showEditCompanyDialog(Company company) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: company.name);
    final codeController = TextEditingController(text: company.code);
    final adminNameController = TextEditingController(text: company.adminName);
    final adminEmailController = TextEditingController(text: company.adminEmail);
    final adminUsernameController = TextEditingController(text: company.adminUsername);
    final adminPasswordController = TextEditingController(text: company.adminPassword);
    String selectedStatus = company.status;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.edit_square, color: AppTheme.primaryBlue),
                  SizedBox(width: 10),
                  Text('Editar Empresa / Grupo'),
                ],
              ),
              content: SingleChildScrollView(
                child: Container(
                  width: 500,
                  padding: const EdgeInsets.all(8),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nombre de la Empresa / Grupo *',
                            prefixIcon: Icon(Icons.apartment),
                          ),
                          validator: (val) => val == null || val.trim().isEmpty ? 'El nombre es obligatorio' : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: codeController,
                                decoration: const InputDecoration(
                                  labelText: 'Código Identificador',
                                  prefixIcon: Icon(Icons.qr_code),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: selectedStatus,
                                decoration: const InputDecoration(
                                  labelText: 'Estado',
                                  prefixIcon: Icon(Icons.toggle_on),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'ACTIVA', child: Text('🟢 ACTIVA')),
                                  DropdownMenuItem(value: 'INACTIVA', child: Text('🔴 INACTIVA')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setDialogState(() => selectedStatus = val);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const Text(
                          '👤 Credenciales del Administrador:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryDark),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: adminNameController,
                          decoration: const InputDecoration(
                            labelText: 'Nombre Completo del Admin',
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: adminEmailController,
                          decoration: const InputDecoration(
                            labelText: 'Correo Electrónico',
                            prefixIcon: Icon(Icons.email),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: adminUsernameController,
                                decoration: const InputDecoration(
                                  labelText: 'Usuario Admin *',
                                  prefixIcon: Icon(Icons.account_circle),
                                ),
                                validator: (val) => val == null || val.trim().isEmpty ? 'Usuario requerido' : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: adminPasswordController,
                                decoration: const InputDecoration(
                                  labelText: 'Contraseña *',
                                  prefixIcon: Icon(Icons.lock),
                                ),
                                validator: (val) => val == null || val.trim().isEmpty ? 'Contraseña requerida' : null,
                              ),
                            ),
                          ],
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
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      final updateData = {
                        'name': nameController.text.trim(),
                        'code': codeController.text.trim(),
                        'status': selectedStatus,
                        'adminName': adminNameController.text.trim(),
                        'adminEmail': adminEmailController.text.trim(),
                        'adminUsername': adminUsernameController.text.trim(),
                        'adminPassword': adminPasswordController.text.trim(),
                      };
                      Navigator.pop(context);
                      Company? updated = await _apiService.updateCompany(company.id, updateData);
                      if (updated != null) {
                        _loadCompanies();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: AppTheme.secondaryEmerald,
                              content: Text('✓ Empresa "${updated.name}" actualizada correctamente.'),
                            ),
                          );
                        }
                      }
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar Cambios'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredCompanies = _companies.where((c) {
      return c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.code.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.adminUsername.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TITLE & BAR
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gestión de Empresas / Grupos (SuperAdmin)',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryDark,
                        ),
                  ),
                  Text(
                    'Administración multitenant de empresas, grupos y usuarios administradores asociados.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _showCreateCompanyDialog,
                icon: const Icon(Icons.add_business_rounded),
                label: const Text('Nueva Empresa / Grupo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondaryEmerald,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // SEARCH BAR
          TextField(
            decoration: InputDecoration(
              hintText: 'Buscar por nombre de empresa, código o usuario admin...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: 16),

          // LIST / TABLE
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredCompanies.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.apartment, size: 64, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('No hay empresas registradas.'),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredCompanies.length,
                        itemBuilder: (context, index) {
                          final comp = filteredCompanies[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: CircleAvatar(
                                radius: 24,
                                backgroundColor: AppTheme.primaryBlue.withOpacity(0.15),
                                child: Text(
                                  comp.name.isNotEmpty ? comp.name[0].toUpperCase() : 'E',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 18),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    comp.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.blue.shade200),
                                    ),
                                    child: Text(
                                      comp.code,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Wrap(
                                  spacing: 20,
                                  runSpacing: 6,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text('Admin: ${comp.adminName} (${comp.adminUsername})'),
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.key, size: 16, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text('Clave: ${comp.adminPassword}'),
                                      ],
                                    ),
                                    if (comp.adminEmail.isNotEmpty)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.email_outlined, size: 16, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(comp.adminEmail),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Chip(
                                    label: Text(comp.status, style: const TextStyle(color: Colors.white, fontSize: 11)),
                                    backgroundColor: comp.status == 'ACTIVA' ? AppTheme.secondaryEmerald : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.edit_note_rounded, color: AppTheme.primaryBlue, size: 24),
                                    tooltip: 'Editar Empresa y Admin',
                                    onPressed: () => _showEditCompanyDialog(comp),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
