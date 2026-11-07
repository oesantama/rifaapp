import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/file_saver.dart';
import 'package:rifaapp/ui/features/admin_cash/views/cash_widgets.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Control → Pagos AGIL: a qué número de WhatsApp y con qué frecuencia se envía el Excel de pagos legalizados,
/// y el historial de lotes.
class AgilConfigTab extends StatefulWidget {
  const AgilConfigTab({super.key});

  @override
  State<AgilConfigTab> createState() => _AgilConfigTabState();
}

class _AgilConfigTabState extends State<AgilConfigTab> {
  final _api = ApiService();
  final _phone = TextEditingController();
  final _time = TextEditingController(text: '18:00');
  final _hours = TextEditingController(text: '6');

  bool _loading = true;
  bool _saving = false;
  bool _sending = false;
  String? _error;
  bool _enabled = false;
  String _mode = 'DAILY';
  Set<int> _days = {1, 2, 3, 4, 5};
  bool _resendSent = false;
  Map<String, dynamic> _config = {};
  List<Map<String, dynamic>> _batches = [];

  static const _dayLabels = {1: 'Lun', 2: 'Mar', 3: 'Mié', 4: 'Jue', 5: 'Vie', 6: 'Sáb', 0: 'Dom'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    _time.dispose();
    _hours.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.agilConfig();
      if (!mounted) return;
      final c = Map<String, dynamic>.from(res['config'] ?? {});
      setState(() {
        _config = c;
        _enabled = c['enabled'] == true;
        _mode = '${c['mode'] ?? 'DAILY'}';
        _phone.text = '${c['phone'] ?? ''}';
        _time.text = '${c['time'] ?? '18:00'}';
        _hours.text = '${c['everyHours'] ?? 6}';
        _days = ((c['days'] as List?) ?? [1, 2, 3, 4, 5]).map((e) => (e as num).toInt()).toSet();
        _resendSent = c['resendSent'] == true;
        _batches = ((res['batches'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: error ? AppTheme.dangerRose : AppTheme.secondaryEmerald, content: Text(text)));
  }

  Future<bool> _save() async {
    setState(() => _saving = true);
    try {
      await _api.agilSaveConfig({
        'enabled': _enabled,
        'phone': _phone.text.trim(),
        'mode': _mode,
        'time': _time.text.trim(),
        'days': _days.toList()..sort(),
        'everyHours': int.tryParse(_hours.text.trim()) ?? 6,
        'resendSent': _resendSent,
      });
      _toast('Configuración guardada.');
      await _load();
      return true;
    } catch (e) {
      _toast(e.toString(), error: true);
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime() async {
    final parts = _time.text.split(':');
    final initial = TimeOfDay(hour: int.tryParse(parts.first) ?? 18, minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
    final picked = await showTimePicker(context: context, initialTime: initial, builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!));
    if (picked != null) setState(() => _time.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
  }

  Future<void> _sendNow() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar ahora'),
        content: Text('Se generará un lote con los pagos legalizados pendientes y se enviará por WhatsApp al número ${_phone.text.trim().isEmpty ? '(sin configurar)' : _phone.text.trim()}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (ok != true) return;
    // Primero se guarda lo que esté en pantalla (por ejemplo el número recién escrito)
    if (!await _save()) return;
    setState(() => _sending = true);
    try {
      final res = await _api.agilSendNow();
      _toast(res['empty'] == true ? '${res['message']}' : 'Lote ${res['batchNumber']} enviado (${res['count']} pagos).');
      await _load();
    } catch (e) {
      _toast(e.toString(), error: true);
      await _load();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _download(Map<String, dynamic> b) async {
    try {
      final bytes = await _api.agilBatchFile('${b['id']}');
      await saveAndDownloadBytes('${b['fileName']}', bytes, mimeType: _xlsxMime);
    } catch (e) {
      _toast(e.toString(), error: true);
    }
  }

  Future<void> _resend(Map<String, dynamic> b) async {
    try {
      await _api.agilSendBatch('${b['id']}');
      _toast('Lote ${b['number']} reenviado.');
    } catch (e) {
      _toast(e.toString(), error: true);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: AppTheme.dangerRose), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
        ]),
      );
    }
    final lastError = '${_config['lastError'] ?? ''}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: AppTheme.primaryBlue.withValues(alpha: 0.05),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Los pagos legalizados por el administrador (transferencias validadas y efectivo recibido) se envían en un Excel por WhatsApp '
              'al número configurado. Cuando los suban a AGIL, esa persona responde con el mismo archivo agregando SUBIDO al nombre '
              '(ej: AGIL_lote-0003_2026-11-07_SUBIDO.xlsx) y el sistema marca esos pagos como SUBIDOS automáticamente.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Envío automático', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(_enabled ? 'Activo: el Excel se envía según la frecuencia elegida.' : 'Apagado: solo se envía con el botón "Enviar ahora".'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
          decoration: const InputDecoration(
            labelText: 'WhatsApp que recibe y devuelve el Excel',
            hintText: '573001234567',
            helperText: 'Con indicativo de país. El archivo devuelto solo se acepta desde este número.',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.phone_android),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _mode,
          decoration: const InputDecoration(labelText: 'Frecuencia', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'DAILY', child: Text('Todos los días')),
            DropdownMenuItem(value: 'WEEKLY', child: Text('Días de la semana')),
            DropdownMenuItem(value: 'EVERY_HOURS', child: Text('Cada cierto número de horas')),
          ],
          onChanged: (v) => setState(() => _mode = v ?? 'DAILY'),
        ),
        const SizedBox(height: 12),
        if (_mode == 'EVERY_HOURS')
          TextField(
            controller: _hours,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Cada cuántas horas (1 a 168)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.schedule)),
          )
        else ...[
          if (_mode == 'WEEKLY')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Wrap(spacing: 6, children: [
                for (final e in _dayLabels.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: _days.contains(e.key),
                    onSelected: (v) => setState(() => v ? _days.add(e.key) : _days.remove(e.key)),
                  ),
              ]),
            ),
          TextField(
            controller: _time,
            readOnly: true,
            onTap: _pickTime,
            decoration: const InputDecoration(labelText: 'Hora de envío (hora de Colombia)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.access_time)),
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Reenviar pagos ya enviados que siguen pendientes'),
          subtitle: const Text('Apagado (recomendado): cada envío trae solo los pagos nuevos.'),
          value: _resendSent,
          onChanged: (v) => setState(() => _resendSent = v),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Guardar'),
          ),
          OutlinedButton.icon(
            onPressed: (_sending || _saving) ? null : _sendNow,
            icon: _sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send, size: 18),
            label: const Text('Enviar ahora'),
          ),
          if (_config['lastRunAt'] != null) Text('Último envío: ${cashDate('${_config['lastRunAt']}')}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ]),
        if (lastError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('⚠️ Último error: $lastError', style: const TextStyle(color: AppTheme.dangerRose, fontSize: 12.5)),
          ),
        const Divider(height: 32),
        const Text('Lotes generados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_batches.isEmpty) Text('Aún no se ha generado ningún lote.', style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic)),
        for (final b in _batches)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(child: Text('${b['number']}')),
              title: Text('${b['count']} pagos • ${cashCurrency.format((b['total'] as num?) ?? 0)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${cashDate('${b['createdAt']}')} • ${b['by']}'
                '${(b['sentTo'] ?? '').toString().isNotEmpty ? '\nEnviado a +${b['sentTo']}' : ''}'
                '${(b['error'] ?? '').toString().isNotEmpty ? '\n⚠️ ${b['error']}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: (b['sentTo'] ?? '').toString().isNotEmpty || (b['error'] ?? '').toString().isNotEmpty,
              trailing: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _statusChip('${b['status']}'),
                IconButton(tooltip: 'Descargar Excel', icon: const Icon(Icons.download, size: 20), onPressed: () => _download(b)),
                if (b['status'] != 'SUBIDO') IconButton(tooltip: 'Reenviar por WhatsApp', icon: const Icon(Icons.send, size: 20), onPressed: () => _resend(b)),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _statusChip(String status) {
    switch (status) {
      case 'SUBIDO':
        return const CashChip('SUBIDO', AppTheme.secondaryEmerald, icon: Icons.cloud_done_outlined);
      case 'ENVIADO':
        return CashChip('ENVIADO', Colors.blue.shade700, icon: Icons.mark_email_read_outlined);
      case 'ERROR_ENVIO':
        return const CashChip('ERROR DE ENVÍO', AppTheme.dangerRose, icon: Icons.error_outline);
      default:
        return CashChip('GENERADO', Colors.grey.shade700);
    }
  }
}
