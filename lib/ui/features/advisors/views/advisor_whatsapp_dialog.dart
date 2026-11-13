import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';

/// El asesor vincula SU WhatsApp (QR o código de 8 dígitos). Con él el sistema envía a sus clientes los recordatorios del sorteo
/// semanal y el resultado. Ese WhatsApp solo envía: el bot no contesta los mensajes que le lleguen.
class AdvisorWhatsAppDialog extends StatefulWidget {
  const AdvisorWhatsAppDialog({super.key});

  @override
  State<AdvisorWhatsAppDialog> createState() => _AdvisorWhatsAppDialogState();
}

class _AdvisorWhatsAppDialogState extends State<AdvisorWhatsAppDialog> {
  final _api = ApiService();
  final _phone = TextEditingController();
  Timer? _poll;
  bool _loading = true;
  bool _busy = false;
  String _state = 'loading'; // open | connecting | close | not_created | error
  String? _number;
  Uint8List? _qr;
  String? _pairing;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status();
    // Mientras no esté vinculado, se consulta cada 5 s para detectar cuando se escanea el código
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_state != 'open' && _state != 'loading') _status(silent: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _phone.dispose();
    super.dispose();
  }

  Uint8List? _decode(dynamic raw) {
    final text = raw?.toString() ?? '';
    if (text.isEmpty) return null;
    try {
      return base64Decode(text.contains(',') ? text.split(',')[1] : text);
    } catch (_) {
      return null;
    }
  }

  Future<void> _status({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res = await _api.getWhatsAppStatus();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _state = (res['state'] ?? 'close').toString();
        _number = res['number']?.toString();
        _qr = _state == 'open' ? null : _decode(res['qrcode']);
        _pairing = _state == 'open' ? null : res['pairingCode']?.toString();
        _error = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _state = 'error';
        _error = e.toString();
      });
    }
  }

  Future<void> _connect({String? phone}) async {
    setState(() => _busy = true);
    try {
      final res = await _api.connectWhatsApp(phoneNumber: phone);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _state = 'connecting';
        _qr = _decode(res['qrcode']);
        _pairing = res['pairingCode']?.toString();
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desvincular mi WhatsApp'),
        content: const Text('Tus clientes dejarán de recibir los recordatorios y resultados de los sorteos desde tu número. Puedes volver a vincularlo cuando quieras.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desvincular')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _api.disconnectWhatsApp();
      await _status();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _busy = false);
  }

  String _pretty(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    return d.length == 12 && d.startsWith('57') ? '+57 ${d.substring(2, 5)} ${d.substring(5, 8)} ${d.substring(8)}' : '+$d';
  }

  @override
  Widget build(BuildContext context) {
    final linked = _state == 'open';
    return AlertDialog(
      title: const Row(children: [Icon(Icons.chat, color: Color(0xFF128C7E)), SizedBox(width: 8), Expanded(child: Text('Mi WhatsApp para mis clientes'))]),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Vincula tu WhatsApp para que el sistema escriba a tus clientes, desde tu número: el recordatorio del sorteo semanal (si aún les falta el abono mínimo o ya participan) y, cuando se juegue, qué número cayó. '
              'No responde mensajes por ti: solo envía esos avisos.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else if (linked) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppTheme.secondaryEmerald.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.check_circle, color: AppTheme.secondaryEmerald),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Vinculado${_number == null ? '' : ': ${_pretty(_number!)}'}', style: const TextStyle(fontWeight: FontWeight.bold))),
                ]),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _disconnect,
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('Desvincular'),
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.dangerRose),
              ),
            ] else ...[
              Text('Estado: ${_state == 'connecting' ? 'esperando que escanees el código…' : 'sin vincular'}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (_qr != null) ...[
                Center(child: Container(color: Colors.white, padding: const EdgeInsets.all(8), child: Image.memory(_qr!, width: 230, height: 230, fit: BoxFit.contain))),
                const SizedBox(height: 6),
                Text('En tu teléfono: WhatsApp → Dispositivos vinculados → Vincular un dispositivo, y escanea este código.', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              ] else
                FilledButton.icon(
                  onPressed: _busy ? null : () => _connect(),
                  icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.qr_code_2),
                  label: const Text('Mostrar código QR'),
                ),
              if (_pairing != null) ...[
                const SizedBox(height: 10),
                Center(child: SelectableText(_pairing!, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 3))),
              ],
              const Divider(height: 24),
              Text('¿Sin cámara? Vincula con un código de 8 dígitos:', style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _phone,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Tu celular con indicativo (573001234567)', isDense: true, border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _busy || _phone.text.replaceAll(RegExp(r'\D'), '').length < 10 ? null : () => _connect(phone: _phone.text.trim()),
                  child: const Text('Obtener código'),
                ),
              ]),
            ],
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: AppTheme.dangerRose))),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}

/// Abre el diálogo y, al cerrarlo, vuelve a leer al asesor para que el aviso desaparezca si ya quedó vinculado.
Future<void> openAdvisorWhatsApp(BuildContext context) async {
  final auth = context.read<AuthViewModel>();
  await showDialog(context: context, builder: (_) => const AdvisorWhatsAppDialog());
  await auth.refreshActiveAdvisor();
}

/// Aviso en el Dashboard del asesor que aún no vinculó su WhatsApp.
class AdvisorWhatsAppPrompt extends StatelessWidget {
  const AdvisorWhatsAppPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: const Color(0xFF128C7E).withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF128C7E), width: 0.8)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Icon(Icons.chat, color: Color(0xFF128C7E), size: 28),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Vincula tu WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Para que tus clientes reciban desde tu número el recordatorio del sorteo semanal y el resultado.', style: TextStyle(fontSize: 12.5)),
            ]),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF128C7E)),
            onPressed: () => openAdvisorWhatsApp(context),
            child: const Text('Vincular'),
          ),
        ]),
      ),
    );
  }
}
