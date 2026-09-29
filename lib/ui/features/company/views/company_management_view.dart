import 'package:flutter/material.dart';
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

  /// Places two form fields side by side on wide screens and stacked on phones.
  Widget _responsivePair(Widget first, Widget second) {
    if (MediaQuery.of(context).size.width < 600) {
      return Column(children: [first, const SizedBox(height: 12), second]);
    }
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: 10),
        Expanded(child: second),
      ],
    );
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
              Expanded(child: Text('Registrar Nueva Empresa / Grupo')),
            ],
          ),
          content: SingleChildScrollView(
            child: Container(
              width: MediaQuery.of(context).size.width > 550 ? 500 : MediaQuery.of(context).size.width * 0.9,
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
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
                    _responsivePair(
                      TextFormField(
                        controller: adminUsernameController,
                        decoration: const InputDecoration(
                          labelText: 'Usuario Admin *',
                          hintText: 'ej: admin_sanmartin',
                          prefixIcon: Icon(Icons.account_circle),
                        ),
                        validator: (val) => val == null || val.trim().isEmpty ? 'Usuario requerido' : null,
                      ),
                      TextFormField(
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
                  Expanded(child: Text('Editar Empresa / Grupo')),
                ],
              ),
              content: SingleChildScrollView(
                child: Container(
                  width: MediaQuery.of(context).size.width > 550 ? 500 : MediaQuery.of(context).size.width * 0.9,
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
                        _responsivePair(
                          TextFormField(
                            controller: codeController,
                            decoration: const InputDecoration(
                              labelText: 'Código Identificador',
                              prefixIcon: Icon(Icons.qr_code),
                            ),
                          ),
                          DropdownButtonFormField<String>(
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
                        const SizedBox(height: 16),
                        const Divider(),
                        const Text(
                          '👤 Credenciales del Administrador:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
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
                        _responsivePair(
                          TextFormField(
                            controller: adminUsernameController,
                            decoration: const InputDecoration(
                              labelText: 'Usuario Admin *',
                              prefixIcon: Icon(Icons.account_circle),
                            ),
                            validator: (val) => val == null || val.trim().isEmpty ? 'Usuario requerido' : null,
                          ),
                          TextFormField(
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

  void _showCompanySummaryDialog(Company company) {
    showDialog(
      context: context,
      builder: (context) {
        return DefaultTabController(
          length: 3,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.analytics_rounded, color: AppTheme.primaryBlue, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        company.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Código: ${company.code} • Estado: ${company.status}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width > 700 ? 650 : MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.height * 0.6 > 480 ? 480 : MediaQuery.of(context).size.height * 0.6,
              child: Column(
                children: [
                  // KPI Cards Header
                  Row(
                    children: [
                      Expanded(
                        child: _buildKpiCard(
                          icon: Icons.admin_panel_settings,
                          color: Colors.purple,
                          title: 'Admins',
                          value: '${company.adminsCount}',
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildKpiCard(
                          icon: Icons.people,
                          color: Colors.blue,
                          title: 'Asesores',
                          value: '${company.advisorsCount}',
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildKpiCard(
                          icon: Icons.confirmation_number,
                          color: Colors.amber.shade800,
                          title: 'Rifas',
                          value: '${company.rafflesCount}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Tab Bar
                  const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: AppTheme.primaryBlue,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: AppTheme.primaryBlue,
                    tabs: [
                      Tab(icon: Icon(Icons.shield_outlined, size: 18), text: 'Admins'),
                      Tab(icon: Icon(Icons.badge_outlined, size: 18), text: 'Asesores'),
                      Tab(icon: Icon(Icons.event_note_outlined, size: 18), text: 'Rifas / Sorteos'),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Tab Views
                  Expanded(
                    child: TabBarView(
                      children: [
                        // TAB 1: ADMINS
                        company.admins.isEmpty
                            ? const Center(child: Text('No hay administradores registrados.'))
                            : ListView.builder(
                                itemCount: company.admins.length,
                                itemBuilder: (ctx, idx) {
                                  final adm = company.admins[idx];
                                  return Card(
                                    elevation: 1,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: const CircleAvatar(
                                        backgroundColor: Colors.purpleAccent,
                                        child: Icon(Icons.person, color: Colors.white),
                                      ),
                                      title: Text(
                                        adm['name'] ?? 'Administrador',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Text(
                                        'Usuario: ${adm['username']} • Clave: ${adm['password']}'
                                        '${(adm['email'] ?? '').toString().isNotEmpty ? '\n${adm['email']}' : ''}',
                                      ),
                                    ),
                                  );
                                },
                              ),

                        // TAB 2: ASESORES
                        company.advisors.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.people_outline, size: 48, color: Colors.grey),
                                    SizedBox(height: 8),
                                    Text('No hay asesores asignados a esta empresa.'),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: company.advisors.length,
                                itemBuilder: (ctx, idx) {
                                  final adv = company.advisors[idx];
                                  return Card(
                                    elevation: 1,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.blue.shade100,
                                        child: Text(
                                          adv['code'] ?? 'ADV',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blue),
                                        ),
                                      ),
                                      title: Text(
                                        adv['name'] ?? 'Asesor',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Text('Teléfono: ${adv['phone'] ?? 'N/A'} • Modo: ${adv['mode'] ?? 'POOL_GENERAL'}'),
                                      trailing: Chip(
                                        label: Text('Vendidas: ${adv['totalSold'] ?? 0}'),
                                        backgroundColor: Colors.green.shade50,
                                      ),
                                    ),
                                  );
                                },
                              ),

                        // TAB 3: RIFAS / EVENTOS
                        company.raffles.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.confirmation_number_outlined, size: 48, color: Colors.grey),
                                    SizedBox(height: 8),
                                    Text('No hay eventos de rifa registrados para esta empresa.'),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: company.raffles.length,
                                itemBuilder: (ctx, idx) {
                                  final raf = company.raffles[idx];
                                  return Card(
                                    elevation: 1,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: const CircleAvatar(
                                        backgroundColor: AppTheme.accentAmber,
                                        child: Icon(Icons.confirmation_number, color: Colors.white),
                                      ),
                                      title: Text(
                                        raf['title'] ?? 'Rifa',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Text(
                                        'Boletas: ${raf['totalTickets']} • Precio: \$${raf['ticketPrice']} COP • Fecha: ${raf['mainDrawDate'] != null ? raf['mainDrawDate'].toString().split('T')[0] : 'S/D'}',
                                      ),
                                      trailing: Chip(
                                        label: Text(
                                          raf['status'] ?? 'ACTIVA',
                                          style: const TextStyle(color: Colors.white, fontSize: 10),
                                        ),
                                        backgroundColor: raf['status'] == 'ACTIVA' ? AppTheme.secondaryEmerald : Colors.grey,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKpiCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w500),
                ),
                Text(
                  value,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[700]), overflow: TextOverflow.ellipsis, maxLines: 2),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildCompanyCard(Company comp) {
    final isActive = comp.status == 'ACTIVA';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                  child: Text(
                    comp.name.isNotEmpty ? comp.name[0].toUpperCase() : 'E',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comp.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Text(
                              comp.code,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isActive ? AppTheme.secondaryEmerald : Colors.grey,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              comp.status,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.analytics_rounded, color: AppTheme.primaryBlue),
                  tooltip: 'Ver Resumen Profesional (Admins, Asesores, Rifas)',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showCompanySummaryDialog(comp),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_note_rounded, color: Colors.orange),
                  tooltip: 'Editar Empresa y Admin',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _showEditCompanyDialog(comp),
                ),
              ],
            ),
            const Divider(height: 20),
            _buildInfoLine(Icons.person_outline, 'Admin: ${comp.adminName} (${comp.adminUsername})'),
            _buildInfoLine(Icons.key, 'Clave: ${comp.adminPassword}'),
            if (comp.adminEmail.isNotEmpty) _buildInfoLine(Icons.email_outlined, comp.adminEmail),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildMetricBadge(Icons.shield_outlined, 'Admins: ${comp.adminsCount}', Colors.purple),
                _buildMetricBadge(Icons.badge_outlined, 'Asesores: ${comp.advisorsCount}', Colors.blue),
                _buildMetricBadge(Icons.confirmation_number_outlined, 'Sorteos: ${comp.rafflesCount}', Colors.amber.shade900),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredCompanies = _companies.where((c) {
      return c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.code.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          c.adminUsername.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isMobile
          ? FloatingActionButton.extended(
              onPressed: _showCreateCompanyDialog,
              backgroundColor: AppTheme.secondaryEmerald,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_business_rounded),
              label: const Text('Nueva Empresa'),
            )
          : null,
      body: Padding(
        padding: EdgeInsets.fromLTRB(isMobile ? 12 : 20, isMobile ? 12 : 20, isMobile ? 12 : 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TITLE & BAR
            Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMobile ? 'Empresas / Grupos' : 'Gestión de Empresas / Grupos (SuperAdmin)',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: isMobile ? 20 : null,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Administración multitenant de empresas, grupos y usuarios administradores asociados.',
                        style: TextStyle(color: Colors.grey[600], fontSize: isMobile ? 12 : 13),
                      ),
                    ],
                  ),
                ),
                if (!isMobile)
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
            SizedBox(height: isMobile ? 12 : 20),

            // SEARCH BAR
            TextField(
              decoration: InputDecoration(
                hintText: isMobile ? 'Buscar empresa, código o usuario...' : 'Buscar por nombre de empresa, código o usuario admin...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                isDense: isMobile,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
            const SizedBox(height: 12),

            // LIST / TABLE
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredCompanies.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.apartment, size: 64, color: Colors.grey),
                              SizedBox(height: 12),
                              Text('No hay empresas registradas.'),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadCompanies,
                          child: ListView.builder(
                            padding: EdgeInsets.only(bottom: isMobile ? 88 : 16),
                            itemCount: filteredCompanies.length,
                            itemBuilder: (context, index) => _buildCompanyCard(filteredCompanies[index]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
