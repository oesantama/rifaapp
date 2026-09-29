import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/advisor.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';
import 'package:rifaapp/ui/features/advisors/views/commission_dashboard_view.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/core/theme.dart';

class AdvisorManagementView extends StatelessWidget {
  const AdvisorManagementView({super.key});

  void _showAdminDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Colors.amber, size: 28),
              SizedBox(width: 10),
              Text('Registrar Nuevo Administrador', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo del Admin *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Correo Electrónico *',
                    hintText: 'admin2@rifamaster.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Usuario de Acceso *',
                    hintText: 'Ej: admin2',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.account_circle),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono / WhatsApp *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passwordCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña de Acceso *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade900),
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty && passwordCtrl.text.trim().isNotEmpty && emailCtrl.text.trim().isNotEmpty) {
                  final authVM = Provider.of<AuthViewModel>(context, listen: false);
                  authVM.registerAdmin(
                    name: nameCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    username: usernameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    password: passwordCtrl.text.trim(),
                  );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.secondaryEmerald,
                      content: Text('¡Nuevo administrador "${nameCtrl.text.trim()}" registrado con éxito!'),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.red,
                      content: Text('Ingrese Nombre, Correo, Usuario y Contraseña válidos.'),
                    ),
                  );
                }
              },
              child: const Text('CREAR ADMINISTRADOR'),
            )
          ],
        );
      },
    );
  }

  void _showAdvisorDialog(BuildContext context, {Advisor? advisor}) {
    final bool isEditing = advisor != null;
    final nameCtrl = TextEditingController(text: advisor?.name ?? '');
    final emailCtrl = TextEditingController(text: advisor?.email ?? '');
    final usernameCtrl = TextEditingController(text: advisor?.username ?? '');
    final phoneCtrl = TextEditingController(text: advisor?.phone ?? '');
    final passwordCtrl = TextEditingController(text: advisor?.password ?? '1234');
    final codeCtrl = TextEditingController(text: advisor?.code ?? '');
    final rangeCtrl = TextEditingController(text: advisor?.assignedTicketRanges.join(', ') ?? '');
    String mode = advisor?.mode ?? 'POOL_GENERAL';
    String status = advisor?.status ?? 'ACTIVO';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(isEditing ? Icons.manage_accounts : Icons.person_add, color: AppTheme.primaryBlue),
                  const SizedBox(width: 10),
                  Text(isEditing ? 'Editar Perfil y Clave del Asesor' : 'Registrar Nuevo Asesor / Vendedor', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre Completo *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Correo Electrónico *',
                        hintText: 'asesor@rifamaster.com',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de Usuario de Acceso *',
                        hintText: 'Ej: adv01',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_box),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passwordCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña de Acceso *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono / WhatsApp *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Cédula / Documento de Identidad (Código) *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(
                        labelText: 'Estado de la Cuenta',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.shield),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'ACTIVO',
                          child: Text('🟢 ACTIVO (Puede acceder al sistema)'),
                        ),
                        DropdownMenuItem(
                          value: 'INHABILITADO',
                          child: Text('🔴 INHABILITADO (Acceso bloqueado)'),
                        ),
                      ],
                      onChanged: (v) => setState(() => status = v!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: mode,
                      decoration: const InputDecoration(
                        labelText: 'Modo de Trabajo (Boletas Disponibles)',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'POOL_GENERAL',
                          child: Text('Pool General (Ver todas la boletas libremente)'),
                        ),
                        DropdownMenuItem(
                          value: 'ASSIGNED',
                          child: Text('Boletas Asignadas (Ver solo su rango específico)'),
                        ),
                      ],
                      onChanged: (v) => setState(() => mode = v!),
                    ),
                    if (mode == 'ASSIGNED') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: rangeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Rangos Asignados (Ej: 1-100, 201-300)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isNotEmpty && codeCtrl.text.trim().isNotEmpty) {
                      final advVM = Provider.of<AdvisorViewModel>(context, listen: false);
                      List<String> ranges = rangeCtrl.text.isNotEmpty
                          ? rangeCtrl.text.split(',').map((e) => e.trim()).toList()
                          : [];
                      
                      Map<String, dynamic> data = {
                        'name': nameCtrl.text.trim(),
                        'email': emailCtrl.text.trim(),
                        'username': usernameCtrl.text.trim().isNotEmpty ? usernameCtrl.text.trim() : codeCtrl.text.trim(),
                        'password': passwordCtrl.text.trim().isNotEmpty ? passwordCtrl.text.trim() : '1234',
                        'phone': phoneCtrl.text.trim(),
                        'code': codeCtrl.text.trim(),
                        'mode': mode,
                        'status': status,
                        'assignedTicketRanges': ranges,
                      };

                      bool ok;
                      if (isEditing) {
                        ok = await advVM.updateAdvisor(advisor.id, data);
                      } else {
                        ok = await advVM.createAdvisor(data);
                      }

                      if (ok && ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(isEditing ? 'Perfil de asesor actualizado con éxito' : 'Asesor creado con éxito')),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Colors.red,
                          content: Text('Por favor complete Nombre y Cédula válidos'),
                        ),
                      );
                    }
                  },
                  child: Text(isEditing ? 'Guardar Cambios' : 'Guardar Asesor'),
                )
              ],
            );
          },
        );
      },
    );
  }

  void _handleDeleteAdvisor(BuildContext context, Advisor adv) {
    final advVM = Provider.of<AdvisorViewModel>(context, listen: false);

    // Check if advisor has sales or financial records
    if (adv.totalSold > 0 || adv.totalCollected > 0) {
      showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.block, color: Colors.orange, size: 28),
                SizedBox(width: 10),
                Text('Imposible Eliminar Asesor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⛔ El asesor "${adv.name}" cuenta con ${adv.totalSold} boleta(s) vendidas y recaudos de \$${adv.totalCollected.toStringAsFixed(0)} COP.',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Para mantener la integridad de la auditoría contable de la rifa, NO se permite eliminar asesores con ventas realizadas. En su lugar, puede INHABILITAR su cuenta.',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade900),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await advVM.toggleAdvisorStatus(adv);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('El asesor "${adv.name}" ha sido INHABILITADO.')),
                  );
                },
                child: const Text('INHABILITAR ACCESO'),
              )
            ],
          );
        },
      );
      return;
    }

    // Advisor has 0 sales -> Prompt for deletion reason
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.delete_forever, color: AppTheme.dangerRose, size: 28),
              SizedBox(width: 10),
              Text('Eliminar Asesor Sin Registros', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Va a eliminar el asesor "${adv.name}". Al no poseer ventas activas, la eliminación es permanente.'),
              const SizedBox(height: 14),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Motivo de Eliminación (Requerido para auditoría) *',
                  hintText: 'Ej: Asesor registrado por error',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose),
              onPressed: () async {
                final reason = reasonCtrl.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(backgroundColor: Colors.red, content: Text('Ingrese el motivo de eliminación.')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                bool ok = await advVM.deleteAdvisor(adv.id, reason);
                if (ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.secondaryEmerald,
                      content: Text('Asesor "${adv.name}" eliminado. Motivo conservado en auditoría.'),
                    ),
                  );
                }
              },
              child: const Text('ELIMINAR DEFINITIVAMENTE'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Consumer<AdvisorViewModel>(
      builder: (context, advVM, _) {
        if (advVM.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (advVM.advisors.isEmpty) {
          return Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => _showAdvisorDialog(context),
              icon: const Icon(Icons.person_add),
              label: const Text('Nuevo Asesor'),
              backgroundColor: AppTheme.primaryBlue,
            ),
            body: const Center(child: Text('No hay asesores registrados')),
          );
        }

        // Sort advisors by sales count descending for ranking
        final rankedAdvisors = List.from(advVM.advisors);
        rankedAdvisors.sort((a, b) => b.totalSold.compareTo(a.totalSold));

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: Colors.white,
                child: const TabBar(
                  labelColor: AppTheme.primaryBlue,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppTheme.primaryBlue,
                  tabs: [
                    Tab(icon: Icon(Icons.people_outline, size: 18), text: 'Gestión & Ranking de Asesores'),
                    Tab(icon: Icon(Icons.monetization_on_outlined, size: 18), text: 'Dashboard de Comisiones & Liquidación'),
                  ],
                ),
              ),
            ),
            floatingActionButton: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'fab_admin',
                  onPressed: () => _showAdminDialog(context),
                  icon: const Icon(Icons.admin_panel_settings, size: 20),
                  label: const Text('Nuevo Admin', style: TextStyle(fontSize: 12)),
                  backgroundColor: Colors.amber.shade900,
                ),
                const SizedBox(width: 10),
                FloatingActionButton.extended(
                  heroTag: 'fab_advisor',
                  onPressed: () => _showAdvisorDialog(context),
                  icon: const Icon(Icons.person_add, size: 20),
                  label: const Text('Nuevo Asesor', style: TextStyle(fontSize: 12)),
                  backgroundColor: AppTheme.primaryBlue,
                ),
              ],
            ),
            body: TabBarView(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Gestión de Asesores y Control de Caja',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Visualiza las ventas, dinero recaudado, correos, usuarios y estado de cuenta de cada asesor.',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // LEADERBOARD / RANKING CARD
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        color: AppTheme.primaryBlue.withOpacity(0.04),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Text('🏆', style: TextStyle(fontSize: 22)),
                                  SizedBox(width: 8),
                                  Text(
                                    'Ranking de Mejores Vendedores (Leaderboard)',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: rankedAdvisors.take(3).toList().asMap().entries.map((entry) {
                                  int rank = entry.key + 1;
                                  final adv = entry.value;
                                  String medal = rank == 1 ? '🥇' : rank == 2 ? '🥈' : '🥉';
                                  Color medalColor = rank == 1
                                      ? Colors.amber.shade700
                                      : rank == 2
                                          ? Colors.grey.shade600
                                          : Colors.brown.shade600;

                                  return Expanded(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 4),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: medalColor.withOpacity(0.4), width: 1.5),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.03),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          )
                                        ],
                                      ),
                                      child: Column(
                                        children: [
                                          Text(medal, style: const TextStyle(fontSize: 24)),
                                          const SizedBox(height: 4),
                                          Text(
                                            adv.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${adv.totalSold} boletas',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.secondaryEmerald,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'Listado de Asesores Registrados:',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),

                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: advVM.advisors.length,
                        itemBuilder: (context, i) {
                          final adv = advVM.advisors[i];
                          int rankIndex = rankedAdvisors.indexWhere((a) => a.id == adv.id) + 1;
                          String rankBadge = rankIndex == 1
                              ? '🥇 #1'
                              : rankIndex == 2
                                  ? '🥈 #2'
                                  : rankIndex == 3
                                      ? '🥉 #3'
                                      : '🎖️ #$rankIndex';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: adv.isActive
                                            ? AppTheme.primaryBlue.withOpacity(0.15)
                                            : Colors.grey.shade400,
                                        child: Text(
                                          adv.name.isNotEmpty ? adv.name[0].toUpperCase() : 'A',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: adv.isActive ? AppTheme.primaryBlue : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  adv.name,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    decoration: !adv.isActive ? TextDecoration.lineThrough : null,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    rankBadge,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.amber.shade900,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: adv.isActive ? Colors.green.shade100 : Colors.red.shade100,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    adv.isActive ? 'ACTIVO' : 'INHABILITADO',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: adv.isActive ? Colors.green.shade800 : Colors.red.shade800,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              'Usuario: ${adv.username.isNotEmpty ? adv.username : adv.code} • Correo: ${adv.email.isNotEmpty ? adv.email : "N/A"} • Tel: ${adv.phone}',
                                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Actions
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert),
                                        onSelected: (val) async {
                                          if (val == 'edit') {
                                            _showAdvisorDialog(context, advisor: adv);
                                          } else if (val == 'toggle_status') {
                                            await advVM.toggleAdvisorStatus(adv);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Estado de "${adv.name}" actualizado a ${adv.isActive ? "INHABILITADO" : "ACTIVO"}')),
                                            );
                                          } else if (val == 'delete') {
                                            _handleDeleteAdvisor(context, adv);
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Editar Datos & Clave')],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'toggle_status',
                                            child: Row(
                                              children: [
                                                Icon(adv.isActive ? Icons.block : Icons.check_circle, size: 18, color: adv.isActive ? Colors.orange : Colors.green),
                                                const SizedBox(width: 8),
                                                Text(adv.isActive ? 'Inhabilitar Acceso' : 'Activar Acceso'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [Icon(Icons.delete_forever, size: 18, color: AppTheme.dangerRose), SizedBox(width: 8), Text('Eliminar Usuario')],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: [
                                      _metricCol('Boletas Vendidas', '${adv.totalSold}', Colors.blueGrey),
                                      _metricCol('Recaudado Asesor', currency.format(adv.totalCollected), AppTheme.secondaryEmerald),
                                      _metricCol('Confirmado Admin', currency.format(adv.totalConfirmed), AppTheme.primaryBlue),
                                      _metricCol('Pendiente Turn-in', currency.format(adv.pendingTurnIn), AppTheme.dangerRose),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const CommissionDashboardView(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metricCol(String title, String val, Color color) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(val, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
