import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/widgets/error_alert.dart';

/// Opens a public legal page (/terminos, /privacidad, /eliminar-cuenta).
void openLegalPage(String path) => launchUrl(Uri.parse('${ApiService.publicBaseUrl}/$path'), mode: LaunchMode.externalApplication);

/// "Términos · Privacidad" links (login screen and account menu).
class LegalLinks extends StatelessWidget {
  final Color? color;

  const LegalLinks({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12, color: color ?? Colors.white60, decoration: TextDecoration.underline);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      children: [
        TextButton(onPressed: () => openLegalPage('terminos'), child: Text('Términos y condiciones', style: style)),
        TextButton(onPressed: () => openLegalPage('privacidad'), child: Text('Política de privacidad', style: style)),
      ],
    );
  }
}

/// Account menu: profile / password, legal pages and the account deletion request.
Future<void> showAccountSheet(
  BuildContext context, {
  required String name,
  required bool isSuperAdmin,
  required VoidCallback onProfile,
}) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Mi perfil y contraseña'),
            onTap: () {
              Navigator.pop(ctx);
              onProfile();
            },
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Términos y condiciones'),
            onTap: () => openLegalPage('terminos'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Política de privacidad'),
            onTap: () => openLegalPage('privacidad'),
          ),
          if (!isSuperAdmin)
            ListTile(
              leading: const Icon(Icons.person_remove_outlined, color: AppTheme.dangerRose),
              title: const Text('Solicitar eliminación de mi cuenta', style: TextStyle(color: AppTheme.dangerRose)),
              onTap: () {
                Navigator.pop(ctx);
                _requestDeletion(context);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> _requestDeletion(BuildContext context) async {
  final reasonCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.person_remove_outlined, color: AppTheme.dangerRose, size: 36),
      title: const Text('Solicitar eliminación de la cuenta'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Se eliminará su cuenta y sus datos personales. Si usted es el administrador de la empresa, también se eliminarán '
              'la empresa, sus rifas, compradores, pagos y asesores. La solicitud se atiende en un máximo de 15 días hábiles.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(controller: reasonCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Motivo (opcional)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose, foregroundColor: Colors.white),
          child: const Text('Enviar solicitud'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    final message = await RaffleRepository().requestAccountDeletion(reasonCtrl.text.trim());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppTheme.secondaryEmerald, content: Text(message)));
    }
  } catch (e) {
    if (context.mounted) await showErrorAlert(context, 'No se pudo enviar', e.toString());
  }
}

/// SuperAdmin: the platform's legal data (shown on the legal pages) and account deletion requests.
class LegalAdminSection extends StatefulWidget {
  const LegalAdminSection({super.key});

  @override
  State<LegalAdminSection> createState() => _LegalAdminSectionState();
}

class _LegalAdminSectionState extends State<LegalAdminSection> {
  static const _labels = {
    'brandName': 'Nombre comercial de la app',
    'legalName': 'Razón social o nombre del responsable *',
    'nit': 'NIT o cédula *',
    'contactEmail': 'Correo de contacto y datos personales *',
    'contactPhone': 'Teléfono de contacto',
    'address': 'Dirección',
    'city': 'Ciudad',
  };
  final _ctrl = {for (final k in _labels.keys) k: TextEditingController()};
  List<Map<String, dynamic>> _requests = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = RaffleRepository();
      final results = await Future.wait([repo.fetchLegal(), repo.fetchDeletionRequests()]);
      final legal = results[0] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        for (final k in _labels.keys) {
          _ctrl[k]!.text = (legal[k] ?? '').toString();
        }
        _requests = results[1] as List<Map<String, dynamic>>;
        _loaded = true;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await RaffleRepository().saveLegal({for (final e in _ctrl.entries) e.key: e.value.text.trim()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: AppTheme.secondaryEmerald, content: Text('Datos legales guardados.')),
        );
      }
    } catch (e) {
      if (mounted) showErrorAlert(context, 'No se pudo guardar', e.toString());
    }
  }

  Future<void> _resolve(Map<String, dynamic> r, String status) async {
    try {
      await RaffleRepository().resolveDeletionRequest(r['id'], status);
      _load();
    } catch (e) {
      if (mounted) showErrorAlert(context, 'No se pudo actualizar', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final pending = _requests.where((r) => r['status'] == 'PENDIENTE').toList();
    String day(String? v) {
      final d = DateTime.tryParse(v ?? '');
      return d == null ? '' : DateFormat('dd/MM/yyyy').format(d.toLocal());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(children: [
                  Icon(Icons.gavel_outlined, color: AppTheme.primaryBlue),
                  SizedBox(width: 8),
                  Expanded(child: Text('Datos legales (Google Play)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                ]),
                const SizedBox(height: 4),
                Text(
                  'Aparecen en la política de privacidad, los términos y la página de eliminación de cuenta, que Google Play exige.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                for (final e in _labels.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: _ctrl[e.key],
                      decoration: InputDecoration(labelText: e.value, border: const OutlineInputBorder()),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                        onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Guardar datos legales')),
                    TextButton(onPressed: () => openLegalPage('privacidad'), child: const Text('Ver privacidad')),
                    TextButton(onPressed: () => openLegalPage('terminos'), child: const Text('Ver términos')),
                    TextButton(onPressed: () => openLegalPage('eliminar-cuenta'), child: const Text('Ver eliminación')),
                  ],
                ),
              ],
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.person_remove_outlined, color: AppTheme.dangerRose),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Solicitudes de eliminación de cuenta (${pending.length} pendientes)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  'Atienda cada solicitud en máximo 15 días hábiles: elimine el asesor o la empresa y márquela como atendida.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                ),
                if (_requests.isEmpty)
                  const Padding(padding: EdgeInsets.only(top: 10), child: Text('No hay solicitudes.'))
                else
                  for (final r in _requests)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '${r['name']} • ${r['identifier']}${(r['company'] ?? '').toString().isNotEmpty ? ' • ${r['company']}' : ''}'),
                      subtitle: Text(
                        '${r['source'] == 'app' ? 'Desde la app' : 'Desde la web'} el ${day(r['createdAt'])} • contacto: ${r['contact']}'
                        '${(r['reason'] ?? '').toString().isNotEmpty ? '\nMotivo: ${r['reason']}' : ''}\nEstado: ${r['status']}',
                      ),
                      isThreeLine: true,
                      trailing: r['status'] == 'PENDIENTE'
                          ? Wrap(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline, color: AppTheme.secondaryEmerald),
                                  tooltip: 'Marcar atendida',
                                  onPressed: () => _resolve(r, 'ATENDIDA'),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.block, color: Colors.grey),
                                  tooltip: 'Rechazar (no se pudo verificar)',
                                  onPressed: () => _resolve(r, 'RECHAZADA'),
                                ),
                              ],
                            )
                          : null,
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
