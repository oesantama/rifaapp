import 'package:flutter/material.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/theme.dart';

/// Recordatorios del sorteo semanal por WhatsApp a los compradores: se activan aquí, se ve qué asesores tienen su WhatsApp vinculado
/// y se puede revisar (sin enviar nada) a quién le llegaría y con qué texto.
class DrawRemindersCard extends StatefulWidget {
  const DrawRemindersCard({super.key});

  @override
  State<DrawRemindersCard> createState() => _DrawRemindersCardState();
}

class _DrawRemindersCardState extends State<DrawRemindersCard> {
  final _api = ApiService();
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  int _days = 3;
  List<Map<String, dynamic>> _advisors = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _api.drawRemindersConfig();
      if (!mounted) return;
      setState(() {
        _enabled = res['enabled'] == true;
        _days = (res['daysBefore'] as num?)?.toInt() ?? 3;
        _advisors = ((res['advisors'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _save({bool? enabled, int? days}) async {
    setState(() => _saving = true);
    try {
      final res = await _api.saveDrawRemindersConfig(enabled: enabled ?? _enabled, daysBefore: days ?? _days);
      if (mounted) {
        setState(() {
          _enabled = res['enabled'] == true;
          _days = (res['daysBefore'] as num?)?.toInt() ?? _days;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppTheme.dangerRose, content: Text('$e')));
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _preview() async {
    try {
      final res = await _api.drawRemindersPreview();
      if (!mounted) return;
      await showDialog(context: context, builder: (_) => _PreviewDialog(data: res, days: _days));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppTheme.dangerRose, content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_error != null) return const SizedBox.shrink();
    final linked = _advisors.where((a) => a['linked'] == true).length;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.campaign_outlined, color: AppTheme.primaryBlue),
            const SizedBox(width: 10),
            const Expanded(child: Text('Recordatorios del sorteo semanal a los compradores', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Enviar recordatorios y resultados por WhatsApp', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              'Faltando $_days día(s) para el sorteo, cada comprador recibe si aún debe el abono mínimo o si ya participa, con el premio. '
              'Al guardar el ganador en Ganadores, todos reciben qué número cayó y si se acumula. '
              'Cada cliente lo recibe desde el WhatsApp de su asesor (si lo vinculó) o desde el de la empresa si no tiene asesor.',
              style: const TextStyle(fontSize: 12),
            ),
            value: _enabled,
            onChanged: _saving ? null : (v) => _save(enabled: v),
          ),
          Row(children: [
            const Text('Avisar faltando', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _days,
              isDense: true,
              items: [for (var d = 1; d <= 7; d++) DropdownMenuItem(value: d, child: Text('$d día${d == 1 ? '' : 's'}'))],
              onChanged: _saving ? null : (v) => _save(days: v),
            ),
            const Spacer(),
            OutlinedButton.icon(onPressed: _preview, icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('Ver a quién le llegaría')),
          ]),
          const Divider(height: 22),
          Text('WhatsApp de los asesores ($linked de ${_advisors.length} vinculados)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          if (_advisors.isEmpty)
            Text('Aún no hay asesores.', style: TextStyle(color: Colors.grey[600]))
          else
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final a in _advisors)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(a['linked'] == true ? (a['state'] == 'open' ? Icons.check_circle : Icons.warning_amber_rounded) : Icons.link_off,
                      size: 16, color: a['linked'] == true ? (a['state'] == 'open' ? AppTheme.secondaryEmerald : Colors.orange.shade800) : Colors.grey),
                  label: Text('${a['name']}${a['linked'] == true ? (a['state'] == 'open' ? '' : ' (desconectado)') : ' · sin vincular'}', style: const TextStyle(fontSize: 12)),
                ),
            ]),
          const SizedBox(height: 6),
          Text('Cada asesor vincula su WhatsApp en su cuenta: toca su nombre (arriba a la derecha) → «Mi WhatsApp para mis clientes». Los clientes de un asesor sin WhatsApp vinculado no reciben estos avisos.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
        ]),
      ),
    );
  }
}

class _PreviewDialog extends StatelessWidget {
  final Map<String, dynamic> data;
  final int days;
  const _PreviewDialog({required this.data, required this.days});

  @override
  Widget build(BuildContext context) {
    final draw = data['draw'] as Map?;
    if (draw == null) {
      return AlertDialog(
        title: const Text('Próximo recordatorio'),
        content: const Text('No hay sorteos semanales pendientes con fecha en las rifas activas.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      );
    }
    final senders = ((data['senders'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    final skipped = ((data['skipped'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    final total = senders.fold<int>(0, (s, e) => s + ((e['recipients'] as num?)?.toInt() ?? 0));
    return AlertDialog(
      title: const Text('Próximo recordatorio', style: TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${draw['name']} • ${draw['date']} (${draw['raffle']})', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Se envía ${draw['sendsOn']} (faltando $days día${days == 1 ? '' : 's'}).', style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
            const SizedBox(height: 10),
            Text('Le llegaría a $total comprador(es):', style: const TextStyle(fontWeight: FontWeight.w600)),
            for (final s in senders) Text('• ${s['recipients']} desde el WhatsApp de ${s['label']}', style: const TextStyle(fontSize: 13)),
            if (senders.isEmpty) const Text('• Nadie (no hay compradores con celular y un WhatsApp para enviarles).', style: TextStyle(fontSize: 13)),
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('No recibirían (se quedan sin aviso):', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.dangerRose)),
              for (final s in skipped) Text('• ${s['label']}: ${s['tickets']} boleta(s) — ${s['reason']}', style: const TextStyle(fontSize: 13)),
            ],
            if ('${data['sample'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Ejemplo del mensaje:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFDCF8C6).withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)),
                child: SelectableText('${data['sample']}', style: const TextStyle(fontSize: 12.5)),
              ),
            ],
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}
