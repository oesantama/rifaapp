import 'package:flutter/material.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/widgets/error_alert.dart';
import 'package:rifaapp/ui/features/auth/views/change_password_dialog.dart' show validateNewPassword;
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/ui/features/advisors/views/advisor_sales_breakdown.dart';
import 'package:rifaapp/ui/features/advisors/views/assigned_numbers_widgets.dart';
import 'package:rifaapp/ui/core/widgets/current_raffle_banner.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/advisor.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';
import 'package:rifaapp/ui/features/advisors/views/commission_dashboard_view.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/tickets/views/available_numbers_dialog.dart';
import 'package:rifaapp/ui/core/theme.dart';

class AdvisorManagementView extends StatelessWidget {
  /// Con qué ventas se ordena el ranking: 'calle' (por defecto) u 'oficina'. Siempre se muestran las dos.
  static final ValueNotifier<String> _rankBy = ValueNotifier<String>('calle');

  const AdvisorManagementView({super.key});

  void _showAdminDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Colors.amber, size: 28),
              SizedBox(width: 10),
              Expanded(child: Text('Gestión de Administradores', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ],
          ),
          content: const Text(
            'Las empresas y sus administradores principales se crean y gestionan desde la vista del SuperAdministrador ("Gestión Empresas").\n\nSi necesita agregar o editar credenciales de administradores de empresa, hágalo desde ese panel.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
              child: const Text('Entendido'),
            ),
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
    final passwordCtrl = TextEditingController();
    final codeCtrl = TextEditingController(text: advisor?.code ?? '');
    final rangeCtrl = TextEditingController(text: advisor?.assignedTicketRanges.join(', ') ?? '');
    String mode = advisor?.mode ?? 'POOL_GENERAL';
    String status = advisor?.status ?? 'ACTIVO';
    // Obligatorio al crear: define si el asesor comisiona (calle), no comisiona (punto) o depende de cada venta (integral)
    String? advisorType = advisor?.type;
    bool canExpenses = advisor?.canRegisterExpenses ?? false;
    bool canCash = advisor?.canViewCash ?? false;
    bool canAllTickets = advisor?.canManageAllTickets ?? false;
    final Set<String> menuAccess = {...?advisor?.menuAccess};
    // Rifas en las que queda autorizado: al editar, las que ya tiene; al crear, las activas (puede cambiarlas)
    final allRaffles = Provider.of<RaffleViewModel>(context, listen: false).raffles;
    final Set<String> selectedRaffles = isEditing
        ? {...advisor.raffleIds}
        : {for (final r in allRaffles) if (r.status == 'ACTIVA' && !r.isClosed) r.id};

    bool obscurePassword = true;
    final formKey = GlobalKey<FormState>();

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
                  Expanded(
                      child: Text(isEditing ? 'Editar Perfil y Clave del Asesor' : 'Registrar Nuevo Asesor / Vendedor',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                ],
              ),
              content: SingleChildScrollView(
                  child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      validator: (v) => (v ?? '').trim().length < 3 ? 'Escriba el nombre completo (mínimo 3 letras)' : null,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: const InputDecoration(
                        labelText: 'Nombre Completo *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: emailCtrl,
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Escriba el correo'
                          : (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v!.trim())
                              ? 'Correo no válido (ej: nombre@correo.com)'
                              : null),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: const InputDecoration(
                        labelText: 'Correo Electrónico *',
                        hintText: 'asesor@rifamaster.com',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: usernameCtrl,
                      validator: (v) => (v ?? '').trim().length < 3
                          ? 'Escriba el usuario (mínimo 3 caracteres)'
                          : (v!.trim().contains(' ') ? 'El usuario no puede tener espacios' : null),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      autofillHints: const [AutofillHints.newUsername],
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de Usuario de Acceso *',
                        hintText: 'Ej: adv01',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_box),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: passwordCtrl,
                      validator: (v) => (v ?? '').isEmpty ? (isEditing ? null : 'Escriba la contraseña') : validateNewPassword(v),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      autofillHints: const [AutofillHints.newPassword],
                      autocorrect: false,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: isEditing ? 'Nueva Contraseña (opcional)' : 'Contraseña de Acceso *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: Colors.grey,
                          ),
                          tooltip: obscurePassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
                          onPressed: () {
                            setState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: phoneCtrl,
                      validator: (v) => (v ?? '').trim().length != 10 ? 'Debe tener 10 dígitos (ej: 3001234567)' : null,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono / WhatsApp *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: codeCtrl,
                      validator: (v) =>
                          (v ?? '').trim().length < 5 || v!.trim().length > 15 ? 'Escriba la cédula (de 5 a 15 dígitos)' : null,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
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
                      isExpanded: true,
                      value: advisorType,
                      decoration: InputDecoration(
                        labelText: 'Tipo de asesor *',
                        helperText: advisorType == null
                            ? 'Defina cómo vende y si comisiona'
                            : (advisorType == 'PUNTO'
                                ? 'Todas sus ventas son de oficina: no comisionan.'
                                : advisorType == 'CALLE'
                                    ? 'Todas sus ventas son de calle: comisionan.'
                                    : 'En cada venta indicará si fue en oficina (no comisiona) o en calle (comisiona).'),
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.storefront),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'PUNTO', child: Text('🏢 Asesor de punto (no comisiona)')),
                        DropdownMenuItem(value: 'CALLE', child: Text('🛣️ Asesor de calle (comisiona)')),
                        DropdownMenuItem(value: 'INTEGRAL', child: Text('🔀 Asesor integral (oficina y calle)')),
                      ],
                      validator: (v) => v == null ? 'Seleccione el tipo de asesor' : null,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      onChanged: (v) => setState(() => advisorType = v),
                    ),
                    if (isEditing && advisorType != null && advisorType != advisor.type)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Las ventas que ya hizo conservan su tipo; el cambio aplica a las ventas nuevas.',
                            style: TextStyle(fontSize: 11.5, color: Colors.orange)),
                      ),
                    // Permisos de la oficina: solo para el asesor de punto o el integral
                    if (advisorType == 'PUNTO' || advisorType == 'INTEGRAL') ...[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                        child: Column(children: [
                          SwitchListTile(
                            dense: true,
                            title: const Text('Puede registrar gastos'),
                            subtitle: const Text('Registra gastos en efectivo o de una cuenta. Los de efectivo se descuentan de lo que entrega al administrador.', style: TextStyle(fontSize: 11.5)),
                            value: canExpenses,
                            onChanged: (v) => setState(() => canExpenses = v),
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            dense: true,
                            title: const Text('Puede ver la caja'),
                            subtitle: const Text('Ve el resumen de las cuentas y del efectivo (solo lectura).', style: TextStyle(fontSize: 11.5)),
                            value: canCash,
                            onChanged: (v) => setState(() => canCash = v),
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            dense: true,
                            title: const Text('Ayuda del administrador con las boletas'),
                            subtitle: const Text(
                                'Ve las boletas apartadas y abonadas de todos los asesores, como el administrador, y recibe pagos en efectivo o transferencia. La boleta y la comisión siguen con quien la vendió; el efectivo queda en su caja para entregarlo.',
                                style: TextStyle(fontSize: 11.5)),
                            value: canAllTickets,
                            onChanged: (v) => setState(() => canAllTickets = v),
                          ),
                        ]),
                      ),
                    ],
                    // Partes del menú del administrador que este asesor también puede ver (solo lectura)
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Menú adicional (solo lectura)', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        const Text('Partes del menú del administrador que este asesor también puede ver.', style: TextStyle(fontSize: 11.5)),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Proyección'),
                          value: menuAccess.contains('proyeccion'),
                          onChanged: (v) => setState(() => v == true ? menuAccess.add('proyeccion') : menuAccess.remove('proyeccion')),
                        ),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Pagos y abonos'),
                          value: menuAccess.contains('pagos'),
                          onChanged: (v) => setState(() => v == true ? menuAccess.add('pagos') : menuAccess.remove('pagos')),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
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
                      isExpanded: true,
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
                          child: Text('Boletas Asignadas (solo en rifas independientes)'),
                        ),
                      ],
                      onChanged: (v) => setState(() => mode = v!),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      const Icon(Icons.confirmation_number_outlined, size: 18),
                      const SizedBox(width: 6),
                      const Expanded(child: Text('Rifas en las que puede vender', style: TextStyle(fontWeight: FontWeight.bold))),
                      if (allRaffles.isNotEmpty) ...[
                        TextButton(onPressed: () => setState(() => selectedRaffles.addAll(allRaffles.map((r) => r.id))), child: const Text('Todas')),
                        TextButton(onPressed: () => setState(selectedRaffles.clear), child: const Text('Ninguna')),
                      ],
                    ]),
                    if (allRaffles.isEmpty)
                      const Text('Aún no hay rifas creadas.', style: TextStyle(color: Colors.grey))
                    else
                      for (final r in allRaffles)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: selectedRaffles.contains(r.id),
                          title: Text(r.title),
                          subtitle: r.status == 'ACTIVA' && !r.isClosed ? null : Text(r.isClosed ? 'Cerrada' : r.status),
                          onChanged: (v) => setState(() => v == true ? selectedRaffles.add(r.id) : selectedRaffles.remove(r.id)),
                        ),
                    if (mode == 'ASSIGNED') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: rangeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Rangos Asignados (Ej: 1-100, 201-300)',
                          helperText: 'Solo aplica en rifas independientes (talonarios). En las rifas normales el asesor vende todas las boletas.',
                          helperMaxLines: 2,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              )),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () async {
                    // Says exactly what is missing (each field also shows its error in red)
                    final checks = <(String, String?)>[
                      (
                        'Nombre',
                        ((v) => (v ?? '').trim().length < 3 ? 'Escriba el nombre completo (mínimo 3 letras)' : null)(nameCtrl.text)
                      ),
                      (
                        'Correo',
                        ((v) => (v ?? '').trim().isEmpty
                            ? 'Escriba el correo'
                            : (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v!.trim())
                                ? 'Correo no válido (ej: nombre@correo.com)'
                                : null))(emailCtrl.text)
                      ),
                      (
                        'Usuario',
                        ((v) => (v ?? '').trim().length < 3
                            ? 'Escriba el usuario (mínimo 3 caracteres)'
                            : (v!.trim().contains(' ') ? 'El usuario no puede tener espacios' : null))(usernameCtrl.text)
                      ),
                      (
                        'Contraseña',
                        ((v) =>
                            (v ?? '').isEmpty ? (isEditing ? null : 'Escriba la contraseña') : validateNewPassword(v))(passwordCtrl.text)
                      ),
                      (
                        'Teléfono',
                        ((v) => (v ?? '').trim().length != 10 ? 'Debe tener 10 dígitos (ej: 3001234567)' : null)(phoneCtrl.text)
                      ),
                      (
                        'Cédula',
                        ((v) => (v ?? '').trim().length < 5 || v!.trim().length > 15 ? 'Escriba la cédula (de 5 a 15 dígitos)' : null)(
                            codeCtrl.text)
                      ),
                      ('Tipo de asesor', advisorType == null ? 'Seleccione el tipo de asesor' : null),
                    ].where((c) => c.$2 != null).toList();
                    formKey.currentState?.validate();
                    if (checks.isEmpty) {
                      final authVM = Provider.of<AuthViewModel>(context, listen: false);
                      final advVM = Provider.of<AdvisorViewModel>(context, listen: false);
                      List<String> ranges = rangeCtrl.text.isNotEmpty ? rangeCtrl.text.split(',').map((e) => e.trim()).toList() : [];

                      Map<String, dynamic> data = {
                        'companyId': authVM.selectedCompanyId,
                        'name': nameCtrl.text.trim(),
                        'email': emailCtrl.text.trim(),
                        'username': usernameCtrl.text.trim().isNotEmpty ? usernameCtrl.text.trim() : codeCtrl.text.trim(),
                        'phone': phoneCtrl.text.trim(),
                        'code': codeCtrl.text.trim(),
                        'mode': mode,
                        'type': advisorType,
                        'canRegisterExpenses': (advisorType == 'PUNTO' || advisorType == 'INTEGRAL') && canExpenses,
                        'canViewCash': (advisorType == 'PUNTO' || advisorType == 'INTEGRAL') && canCash,
        'canManageAllTickets': (advisorType == 'PUNTO' || advisorType == 'INTEGRAL') && canAllTickets,
        'menuAccess': menuAccess.toList(),
                        'status': status,
                        'assignedTicketRanges': ranges,
                      };
                      if (passwordCtrl.text.trim().isNotEmpty) {
                        data['password'] = passwordCtrl.text.trim();
                      }
                      if (allRaffles.isNotEmpty) {
                        if (selectedRaffles.isEmpty) {
                          final goOn = await showDialog<bool>(
                            context: ctx,
                            builder: (c) => AlertDialog(
                              title: const Text('Sin rifas'),
                              content: const Text('No marcó ninguna rifa: el asesor no podrá vender en ninguna hasta que lo autorice. ¿Guardar así?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Volver')),
                                ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar sin rifas')),
                              ],
                            ),
                          );
                          if (goOn != true) return;
                        }
                        data['raffleIds'] = selectedRaffles.toList();
                      }

                      bool ok;
                      if (isEditing) {
                        ok = await advVM.updateAdvisor(advisor.id, data);
                      } else {
                        ok = await advVM.createAdvisor(data);
                      }

                      if (!ok && ctx.mounted) {
                        await showErrorAlert(ctx, 'No se pudo guardar el asesor', advVM.lastError ?? 'Intente de nuevo.');
                      }
                      if (ok && ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: Duration(seconds: isEditing ? 4 : 8),
                            content: Text(isEditing ? 'Perfil de asesor actualizado con éxito' : 'Asesor creado con éxito. ${ApiService.lastAdvisorAccessNote ?? ''}'),
                          ),
                        );
                      }
                    } else {
                      await showErrorAlert(
                        ctx,
                        'Faltan datos del asesor',
                        'Revise ${checks.length == 1 ? 'este campo' : 'estos campos'} (también están marcados en rojo):\n\n'
                            '${checks.map((c) => '• ${c.$1}: ${c.$2}').join('\n')}',
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
    final isMobile = MediaQuery.of(context).size.width < 600;

    return ValueListenableBuilder<String>(
      valueListenable: _rankBy,
      builder: (context, rankBy, _) => Consumer<AdvisorViewModel>(
      builder: (context, advVM, _) {
        if (advVM.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (advVM.advisors.isEmpty) {
          return Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              heroTag: 'fab_new_empty',
              onPressed: () => _showCreateMenu(context),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo Asesor / Admin'),
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            ),
            body: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No hay asesores registrados'),
                ],
              ),
            ),
          );
        }

        // Sort advisors by sales count descending for ranking
        // Sales of the current raffle by status (same raffle as the header and the commissions tab)
        final sales = context.watch<TicketViewModel>().salesByAdvisor(advisorTypes: {for (final a in advVM.advisors) a.id: a.type});
        AdvisorSales salesOf(String advisorId) => sales[advisorId] ?? AdvisorSales();
        final rankedAdvisors = List.from(advVM.advisors);
        // El ranking cuenta las ventas de calle (o de oficina si se elige); en desempate, el total
        int rankKey(String id) => rankBy == 'calle' ? salesOf(id).calle : salesOf(id).oficina;
        rankedAdvisors.sort((a, b) {
          final byZone = rankKey(b.id).compareTo(rankKey(a.id));
          return byZone != 0 ? byZone : salesOf(b.id).total.compareTo(salesOf(a.id).total);
        });

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: Theme.of(context).cardColor,
                child: TabBar(
                  labelColor: AppTheme.primaryBlue,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppTheme.primaryBlue,
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.people_outline, size: 18),
                      text: isMobile ? 'Asesores y Ranking' : 'Gestión & Ranking de Asesores',
                      iconMargin: EdgeInsets.zero,
                    ),
                    Tab(
                      icon: const Icon(Icons.monetization_on_outlined, size: 18),
                      text: isMobile ? 'Comisiones' : 'Dashboard de Comisiones & Liquidación',
                      iconMargin: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            floatingActionButton: isMobile
                ? FloatingActionButton.extended(
                    heroTag: 'fab_new',
                    onPressed: () => _showCreateMenu(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo'),
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                  )
                : Row(
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
                  padding: EdgeInsets.fromLTRB(isMobile ? 12 : 16, isMobile ? 12 : 16, isMobile ? 12 : 16, 96),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CurrentRaffleBanner(),
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          Expanded(
                            child: Column(
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
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const RangeRequestsBanner(),

                      // LEADERBOARD / RANKING CARD
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        color: AppTheme.primaryBlue.withValues(alpha: 0.04),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text('🏆', style: TextStyle(fontSize: 22)),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Ranking de Mejores Vendedores (Leaderboard)',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                Text('Se ordena por ventas de:', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                                SegmentedButton<String>(
                                  showSelectedIcon: false,
                                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                                  segments: const [
                                    ButtonSegment(value: 'calle', label: Text('🛣️ Calle')),
                                    ButtonSegment(value: 'oficina', label: Text('🏢 Oficina')),
                                  ],
                                  selected: {rankBy},
                                  onSelectionChanged: (v) => _rankBy.value = v.first,
                                ),
                              ]),
                              const SizedBox(height: 12),
                              Row(
                                children: rankedAdvisors.take(3).toList().asMap().entries.map((entry) {
                                  int rank = entry.key + 1;
                                  final adv = entry.value;
                                  String medal = rank == 1
                                      ? '🥇'
                                      : rank == 2
                                          ? '🥈'
                                          : '🥉';
                                  Color medalColor = rank == 1
                                      ? Colors.amber.shade700
                                      : rank == 2
                                          ? Colors.grey.shade600
                                          : Colors.brown.shade600;

                                  return Expanded(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).cardColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: medalColor.withValues(alpha: 0.4), width: 1.5),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.03),
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
                                            '${salesOf(adv.id).total} vendidas',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.secondaryEmerald,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text.rich(
                                            TextSpan(
                                              style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                                              children: [
                                                TextSpan(
                                                  text: '🏢 ${salesOf(adv.id).oficina} oficina',
                                                  style: rankBy == 'oficina' ? const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue) : null,
                                                ),
                                                const TextSpan(text: ' • '),
                                                TextSpan(
                                                  text: '🛣️ ${salesOf(adv.id).calle} calle',
                                                  style: rankBy == 'calle' ? const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue) : null,
                                                ),
                                              ],
                                            ),
                                            textAlign: TextAlign.center,
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

                      _SearchableAdvisors(
                        advisors: advVM.advisors,
                        itemBuilder: (context, adv) {
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
                              padding: EdgeInsets.all(isMobile ? 12 : 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: adv.isActive ? AppTheme.primaryBlue.withValues(alpha: 0.15) : Colors.grey.shade400,
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
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              children: [
                                                Text(
                                                  adv.name,
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    decoration: !adv.isActive ? TextDecoration.lineThrough : null,
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.withValues(alpha: 0.2),
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
                                                Tooltip(
                                                  message: adv.typeHint,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: (adv.isPunto ? Colors.blueGrey : (adv.isIntegral ? Colors.deepPurple : Colors.teal)).withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      '${adv.isPunto ? '🏢' : (adv.isIntegral ? '🔀' : '🛣️')} ${adv.typeLabel.toUpperCase()}',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: adv.isPunto ? Colors.blueGrey.shade800 : (adv.isIntegral ? Colors.deepPurple.shade700 : Colors.teal.shade800),
                                                      ),
                                                    ),
                                                  ),
                                                ),
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
                                                // WhatsApp vinculado: desde ahí se avisa a sus clientes los recordatorios y resultados de los sorteos
                                                Tooltip(
                                                  message: adv.whatsappLinked
                                                      ? 'Tiene su WhatsApp vinculado${adv.whatsappNumber != null ? ' (+${adv.whatsappNumber})' : ''}: sus clientes reciben los avisos de sorteos'
                                                      : 'No ha vinculado su WhatsApp: sus clientes no reciben los avisos de sorteos',
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: (adv.whatsappLinked ? const Color(0xFF128C7E) : Colors.grey).withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                      Icon(adv.whatsappLinked ? Icons.chat : Icons.link_off, size: 11, color: adv.whatsappLinked ? const Color(0xFF128C7E) : Colors.grey.shade700),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        adv.whatsappLinked ? 'WHATSAPP' : 'SIN WHATSAPP',
                                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: adv.whatsappLinked ? const Color(0xFF128C7E) : Colors.grey.shade700),
                                                      ),
                                                    ]),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Usuario: ${adv.username.isNotEmpty ? adv.username : adv.code} • Correo: ${adv.email.isNotEmpty ? adv.email : "N/A"} • Tel: ${adv.phone}',
                                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                                            ),
                                            AdvisorNumbersSummary(advisor: adv),
                                          ],
                                        ),
                                      ),

                                      // Actions
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert),
                                        onSelected: (val) async {
                                          if (val == 'edit') {
                                            _showAdvisorDialog(context, advisor: adv);
                                          } else if (val == 'available_numbers') {
                                            final currentRaffle = context.read<RaffleViewModel>().selectedRaffle;
                                            if (currentRaffle != null) {
                                              AvailableNumbersDialog.show(context, raffle: currentRaffle, initialAdvisor: adv);
                                            } else {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('No hay una rifa activa seleccionada.')),
                                              );
                                            }
                                          } else if (val == 'send_access') {
                                            final go = await showDialog<bool>(
                                              context: context,
                                              builder: (dctx) => AlertDialog(
                                                title: const Text('Enviar acceso por WhatsApp'),
                                                content: Text(
                                                  'Se enviará a ${adv.name} (${adv.phone}) el enlace, su usuario, una contraseña temporal NUEVA y un pequeño instructivo.\n\n'
                                                  'La contraseña actual dejará de servir y deberá cambiarla al ingresar. Si WhatsApp no está conectado, no se cambia nada.',
                                                ),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancelar')),
                                                  ElevatedButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Enviar')),
                                                ],
                                              ),
                                            );
                                            if (go == true && context.mounted) {
                                              final (ok, msg) = await advVM.sendAccess(adv.id);
                                              if (context.mounted) {
                                                if (ok) {
                                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppTheme.secondaryEmerald, content: Text(msg)));
                                                } else {
                                                  await showErrorAlert(context, 'No se pudo enviar el acceso', msg);
                                                }
                                              }
                                            }
                                          } else if (val == 'numbers') {
                                            AssignNumbersDialog.show(context, adv);
                                          } else if (val == 'toggle_status') {
                                            await advVM.toggleAdvisorStatus(adv);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                  content: Text(
                                                      'Estado de "${adv.name}" actualizado a ${adv.isActive ? "INHABILITADO" : "ACTIVO"}')),
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
                                          const PopupMenuItem(
                                            value: 'available_numbers',
                                            child: Row(
                                              children: [
                                                Icon(Icons.mark_chat_read_outlined, size: 18, color: AppTheme.secondaryEmerald),
                                                SizedBox(width: 8),
                                                Text('Números Disponibles (Imagen/Excel)'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'send_access',
                                            child: Row(children: [Icon(Icons.send_outlined, size: 18, color: Color(0xFF25D366)), SizedBox(width: 8), Text('Enviar acceso por WhatsApp')]),
                                          ),
                                          const PopupMenuItem(
                                            value: 'numbers',
                                            child: Row(
                                              children: [Icon(Icons.pin_outlined, size: 18), SizedBox(width: 8), Text('Asignar números')],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'toggle_status',
                                            child: Row(
                                              children: [
                                                Icon(adv.isActive ? Icons.block : Icons.check_circle,
                                                    size: 18, color: adv.isActive ? Colors.orange : Colors.green),
                                                const SizedBox(width: 8),
                                                Text(adv.isActive ? 'Inhabilitar Acceso' : 'Activar Acceso'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete_forever, size: 18, color: AppTheme.dangerRose),
                                                SizedBox(width: 8),
                                                Text('Eliminar Usuario')
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  Text('Ventas en la rifa actual',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[600])),
                                  const SizedBox(height: 6),
                                  AdvisorSalesBreakdown(sales: salesOf(adv.id)),
                                  const SizedBox(height: 12),
                                  _metricsRow([
                                    _metricCol('Recaudado Asesor', currency.format(salesOf(adv.id).collected), AppTheme.secondaryEmerald),
                                    _metricCol('Confirmado Admin', currency.format(salesOf(adv.id).confirmed), AppTheme.primaryBlue),
                                    _metricCol('Pendiente Turn-in', currency.format(salesOf(adv.id).pendingTurnIn), AppTheme.dangerRose),
                                  ])
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
      ),
    );
  }

  /// Four metrics side by side on wide screens, a 2x2 grid on phones.
  Widget _metricsRow(List<Widget> metrics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 520 ? metrics.length : 2;
        final width = constraints.maxWidth / perRow;
        return Wrap(
          runSpacing: 12,
          children: metrics.map((m) => SizedBox(width: width, child: m)).toList(),
        );
      },
    );
  }

  Widget _metricCol(String title, String val, Color color) {
    return Column(
      children: [
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(val, maxLines: 1, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ),
      ],
    );
  }

  void _showCreateMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppTheme.primaryBlue,
                child: Icon(Icons.person_add, color: Colors.white, size: 20),
              ),
              title: const Text('Nuevo Asesor', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Registrar un vendedor con usuario y clave'),
              onTap: () {
                Navigator.pop(ctx);
                _showAdvisorDialog(context);
              },
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.amber.shade900,
                child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 20),
              ),
              title: const Text('Nuevo Administrador', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Dar acceso de administración a otra persona'),
              onTap: () {
                Navigator.pop(ctx);
                _showAdminDialog(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}


/// Listado de asesores con un buscador (nombre, usuario, código, correo o teléfono).
class _SearchableAdvisors extends StatefulWidget {
  final List<Advisor> advisors;
  final Widget Function(BuildContext context, Advisor advisor) itemBuilder;
  const _SearchableAdvisors({required this.advisors, required this.itemBuilder});

  @override
  State<_SearchableAdvisors> createState() => _SearchableAdvisorsState();
}

class _SearchableAdvisorsState extends State<_SearchableAdvisors> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.advisors
        : widget.advisors.where((a) => [a.name, a.username, a.code, a.email, a.phone].any((v) => v.toLowerCase().contains(q))).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ctrl,
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            hintText: 'Buscar asesor por nombre, usuario, código o teléfono...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() => _q = '');
                    },
                  ),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        if (list.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: Text('Ningún asesor coincide con la búsqueda.')))
        else
          for (final adv in list) widget.itemBuilder(context, adv),
      ],
    );
  }
}
