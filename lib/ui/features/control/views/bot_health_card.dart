import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/theme.dart';

/// Salud del bot de WhatsApp: si está conectado, desde cuándo, cuántas veces se reinició solo y la actividad reciente.
/// El servidor vigila la conexión cada minuto y reinicia la instancia si queda atascada; si la sesión se cerró desde
/// el teléfono, solo se recupera escaneando el QR (lo avisa aquí).
class BotHealthCard extends StatefulWidget {
  const BotHealthCard({super.key});

  @override
  State<BotHealthCard> createState() => _BotHealthCardState();
}

class _BotHealthCardState extends State<BotHealthCard> {
  Map<String, dynamic>? _data;
  String? _error;
  Timer? _timer;
  bool _expanded = false;
  bool _savingSwitch = false;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().getBotHealth();
      if (mounted) setState(() {
        _data = res;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _toggleSales(bool value) async {
    setState(() => _savingSwitch = true);
    try {
      final enabled = await ApiService().setBotSalesEnabled(value);
      if (mounted) {
        setState(() => _data = {...?_data, 'salesEnabled': enabled});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(enabled ? 'Respuestas automáticas activadas.' : 'Respuestas automáticas en pausa. WhatsApp sigue conectado.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo cambiar: $e')));
    } finally {
      if (mounted) setState(() => _savingSwitch = false);
    }
  }

  String _ago(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '—';
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 1) return 'hace instantes';
    if (m < 60) return 'hace $m min';
    if (m < 24 * 60) return 'hace ${m ~/ 60} h';
    return 'hace ${m ~/ (24 * 60)} d';
  }

  String _clock(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }

  String _describe(Map e) {
    switch (e['kind']) {
      case 'mensaje':
        final res = e['result'] == 'error' ? 'ERROR (${e['error'] ?? ''})' : (e['result'] ?? '');
        return 'Mensaje de ${e['from'] ?? ''} (${e['tipo'] ?? ''}) → $res';
      case 'conexion':
        return 'Conexión: ${e['from'] != null ? '${e['from']} → ' : ''}${e['state']}';
      case 'pausa':
        return 'Respuestas automáticas ${e['enabled'] == true ? 'ACTIVADAS' : 'PAUSADAS'} por ${e['by'] ?? ''}';
      case 'reinicio':
        return 'Reinicio automático de la conexión (${e['note'] ?? ''}) ${e['ok'] == true ? '✓' : '✗'}';
      default:
        return '${e['kind']}';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _data == null) return const SizedBox.shrink();
    final health = _data?['health'] as Map?;
    final log = ((_data?['log'] as List?) ?? const []).whereType<Map>().toList();
    if (_data == null) return const SizedBox.shrink();

    final state = (health?['state'] ?? 'desconocido').toString();
    final minutes = (health?['minutesInState'] as num?)?.toInt() ?? 0;
    final needsQr = health?['needsQr'] == true;
    final ok = state == 'open';
    final restarts = (health?['restartsLast24h'] as num?)?.toInt() ?? 0;
    final salesOn = _data?['salesEnabled'] != false;
    final color = ok && !salesOn ? Colors.orange.shade800 : ok ? AppTheme.secondaryEmerald : (needsQr ? AppTheme.dangerRose : Colors.orange.shade800);
    final headline = ok && !salesOn
        ? 'Respuestas automáticas en pausa'
        : ok
        ? 'Bot activo 24/7'
        : needsQr
            ? 'WhatsApp se desvinculó: escanee el QR para reconectar'
            : 'WhatsApp reconectando (${minutes < 1 ? 'hace instantes' : '$minutes min'})';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color.withValues(alpha: 0.5))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Icon(ok ? Icons.health_and_safety : Icons.warning_amber_rounded, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(headline, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
                        Text(
                          health == null
                              ? 'Aún sin datos de vigilancia (se empieza a medir al minuto de iniciar el servidor).'
                              : 'Conectado: ${ok ? 'desde ${_ago(health['since']?.toString())}' : 'última vez ${_ago(health['lastOkAt']?.toString())}'}'
                                  ' • Reinicios automáticos (24 h): $restarts',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Responder ventas automáticamente', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(salesOn
                  ? 'El bot contesta a los clientes. Apáguelo para pausarlo sin desconectar WhatsApp.'
                  : 'En pausa: el bot no contesta. WhatsApp sigue conectado; las alertas, avisos de pago y AGIL siguen funcionando. Los comprobantes que lleguen se atienden a mano.',
                  style: const TextStyle(fontSize: 12)),
              value: salesOn,
              onChanged: _savingSwitch ? null : _toggleSales,
            ),
            if (_expanded) ...[
              const Divider(height: 20),
              const Text('Actividad reciente', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              if (log.isEmpty)
                const Text('Todavía no hay actividad registrada.', style: TextStyle(fontSize: 12, color: Colors.grey))
              else
                for (final e in log.take(25))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 78, child: Text(_clock(e['at']?.toString()), style: const TextStyle(fontSize: 11, color: Colors.grey))),
                      Expanded(child: Text(_describe(e), style: const TextStyle(fontSize: 12))),
                    ]),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
