import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/url_launcher_helper.dart' as web;

/// Campana de avisos del administrador y del asesor: sorteo a 3 días con boletas sin completar y efectivo sin legalizar
/// por 7 días o más. Muestra cuántos hay sin leer; en la web permite activar las notificaciones del navegador.
class AlertsBell extends StatefulWidget {
  const AlertsBell({super.key});

  @override
  State<AlertsBell> createState() => _AlertsBellState();
}

class _AlertsBellState extends State<AlertsBell> {
  int _unread = 0;
  List<Map<String, dynamic>> _alerts = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getAlerts();
      if (!mounted) return;
      setState(() {
        _unread = (res['unread'] as num?)?.toInt() ?? 0;
        _alerts = [for (final a in (res['alerts'] as List? ?? [])) Map<String, dynamic>.from(a as Map)];
      });
    } catch (_) {}
  }

  Future<void> _open() async {
    await _load();
    if (!mounted) return;
    await showDialog(context: context, builder: (_) => _AlertsDialog(alerts: _alerts, onMarkRead: _markAllRead));
    await _load();
  }

  Future<void> _markAllRead() async {
    try {
      await ApiService().markAlertsRead();
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _unread > 0 ? '$_unread aviso(s) sin leer' : 'Avisos',
      onPressed: _open,
      icon: Badge(
        isLabelVisible: _unread > 0,
        label: Text('$_unread'),
        backgroundColor: AppTheme.dangerRose,
        child: Icon(_unread > 0 ? Icons.notifications_active : Icons.notifications_none, size: 22, color: _unread > 0 ? Colors.amber : null),
      ),
    );
  }
}

class _AlertsDialog extends StatefulWidget {
  final List<Map<String, dynamic>> alerts;
  final Future<void> Function() onMarkRead;
  const _AlertsDialog({required this.alerts, required this.onMarkRead});

  @override
  State<_AlertsDialog> createState() => _AlertsDialogState();
}

class _AlertsDialogState extends State<_AlertsDialog> {
  String _pushState = kIsWeb ? web.pushPermissionState() : 'UNSUPPORTED';
  bool _enabling = false;

  Future<void> _enablePush() async {
    setState(() => _enabling = true);
    String message;
    try {
      final key = await ApiService().getPushPublicKey();
      final result = await web.enableWebPush(key);
      if (result == 'DENIED') {
        message = 'Las notificaciones están bloqueadas. Actívelas en los permisos del sitio (candado junto a la dirección).';
      } else if (result == 'UNSUPPORTED') {
        message = 'Este navegador no admite notificaciones. En iPhone, instale primero la app en la pantalla de inicio.';
      } else if (result.startsWith('ERROR')) {
        message = 'No se pudieron activar: $result';
      } else {
        await ApiService().pushSubscribe(Map<String, dynamic>.from(jsonDecode(result) as Map));
        message = '✓ Notificaciones activadas en este dispositivo.';
      }
    } catch (e) {
      message = 'No se pudieron activar: $e';
    }
    if (!mounted) return;
    setState(() {
      _pushState = web.pushPermissionState();
      _enabling = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _when(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return 'hace ${d.inMinutes < 1 ? 1 : d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    final alerts = widget.alerts;
    final canPush = kIsWeb && _pushState != 'UNSUPPORTED';
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        const Icon(Icons.notifications_active, color: Colors.amber),
        const SizedBox(width: 10),
        const Expanded(child: Text('Avisos', style: TextStyle(fontWeight: FontWeight.bold))),
        if (alerts.any((a) => a['readAt'] == null))
          TextButton(
            onPressed: () async {
              await widget.onMarkRead();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Marcar leídos'),
          ),
      ]),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canPush && _pushState != 'granted')
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.phonelink_ring, color: AppTheme.primaryBlue),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Reciba los avisos como notificación en este dispositivo, aunque no tenga la app abierta.', style: TextStyle(fontSize: 12))),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _enabling ? null : _enablePush, child: Text(_enabling ? '...' : 'Activar')),
                ]),
              )
            else if (canPush)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 6),
                  Text('Notificaciones activas en este dispositivo', style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                ]),
              ),
            Flexible(
              child: alerts.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No hay avisos. Aquí aparecerán los sorteos próximos con boletas sin completar y el efectivo con más de 7 días sin legalizar.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: alerts.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final a = alerts[i];
                        final unread = a['readAt'] == null;
                        final cash = a['type'] == 'EFECTIVO_SIN_LEGALIZAR';
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: (cash ? Colors.orange : AppTheme.primaryBlue).withValues(alpha: 0.12),
                            child: Icon(cash ? Icons.payments_outlined : Icons.event_available, size: 18, color: cash ? Colors.orange.shade800 : AppTheme.primaryBlue),
                          ),
                          title: Text('${a['title']}', style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.w500, fontSize: 13)),
                          subtitle: Text('${a['body']}\n${_when(a['createdAt']?.toString())}', style: const TextStyle(fontSize: 11.5)),
                          isThreeLine: true,
                          trailing: unread ? const Icon(Icons.circle, size: 10, color: AppTheme.dangerRose) : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}
