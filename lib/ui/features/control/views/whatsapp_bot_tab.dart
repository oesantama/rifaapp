import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';

class WhatsAppBotTab extends StatefulWidget {
  const WhatsAppBotTab({super.key});

  @override
  State<WhatsAppBotTab> createState() => _WhatsAppBotTabState();
}

class _WhatsAppBotTabState extends State<WhatsAppBotTab> {
  final _phoneController = TextEditingController();
  final _testPhoneController = TextEditingController();

  bool _isLoading = true;
  bool _isConnecting = false;
  String _state = 'loading'; // 'open', 'connecting', 'close', 'not_created', 'error'
  String _instanceName = '';
  String? _connectedNumber;
  Uint8List? _qrBytes;
  String? _pairingCode;
  String? _errorMessage;

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    // Iniciar sondeo periódico cada 5 segundos si está pendiente de vinculación
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_state == 'connecting' || _state == 'close') {
        _fetchStatus(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _phoneController.dispose();
    _testPhoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final res = await api.getWhatsAppStatus();
      if (!mounted) return;

      final state = (res['state'] ?? 'close').toString();
      final instance = (res['instanceName'] ?? '').toString();
      final number = res['number']?.toString();
      final qrBase64 = res['qrcode']?.toString();
      final pairCode = res['pairingCode']?.toString();

      Uint8List? bytes;
      if (qrBase64 != null && qrBase64.isNotEmpty) {
        final cleanBase64 = qrBase64.contains(',') ? qrBase64.split(',')[1] : qrBase64;
        try {
          bytes = base64Decode(cleanBase64);
        } catch (_) {}
      }

      setState(() {
        _isLoading = false;
        _state = state;
        _instanceName = instance;
        _connectedNumber = number;
        _qrBytes = bytes;
        _pairingCode = pairCode;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _isLoading = false;
          _state = 'error';
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _connect({String? phoneNumber}) async {
    setState(() => _isConnecting = true);
    try {
      final api = ApiService();
      final res = await api.connectWhatsApp(phoneNumber: phoneNumber);
      if (!mounted) return;

      final qrBase64 = res['qrcode']?.toString();
      final pairCode = res['pairingCode']?.toString();

      Uint8List? bytes;
      if (qrBase64 != null && qrBase64.isNotEmpty) {
        final cleanBase64 = qrBase64.contains(',') ? qrBase64.split(',')[1] : qrBase64;
        try {
          bytes = base64Decode(cleanBase64);
        } catch (_) {}
      }

      setState(() {
        _isConnecting = false;
        _state = 'connecting';
        _qrBytes = bytes;
        _pairingCode = pairCode;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sesión iniciada. Escanea el código QR o ingresa el código numérico.'),
          backgroundColor: AppTheme.secondaryEmerald,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al conectar: $e'), backgroundColor: AppTheme.dangerRose),
      );
    }
  }

  Future<void> _disconnect() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desconectar WhatsApp'),
        content: const Text('¿Estás seguro de que deseas desconectar este WhatsApp? El Bot dejará de responder mensajes automáticos hasta que lo vuelvas a vincular.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desconectar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      await api.disconnectWhatsApp();
      if (!mounted) return;
      await _fetchStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp desconectado con éxito.'), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al desconectar: $e'), backgroundColor: AppTheme.dangerRose),
      );
    }
  }

  Future<void> _sendTestMessage() async {
    String phone = _testPhoneController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un número de celular de prueba')),
      );
      return;
    }
    // Auto-agrega indicativo 57 de Colombia si es un celular de 10 dígitos
    if (phone.length == 10 && phone.startsWith('3')) {
      phone = '57$phone';
    }

    try {
      final api = ApiService();
      await api.sendWhatsAppTest(phone);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Mensaje de prueba enviado con éxito a +$phone.'), backgroundColor: AppTheme.secondaryEmerald),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error enviando mensaje: $e'), backgroundColor: AppTheme.dangerRose),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authVM = Provider.of<AuthViewModel>(context);
    final roleName = authVM.isSuperAdmin
        ? 'Super Administrador (Ventas de Software)'
        : (authVM.isIndependent ? 'Asesor Independiente' : 'Empresa / Administrador');

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isConnected = _state == 'open';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isConnected ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isConnected ? Icons.check_circle : Icons.qr_code_scanner,
                          size: 36,
                          color: isConnected ? Colors.green : Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'WhatsApp Bot Automático',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Canal: $roleName | Instancia: $_instanceName',
                              style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isConnected ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isConnected ? Colors.green : Colors.red,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.circle,
                              size: 10,
                              color: isConnected ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isConnected ? 'CONECTADO' : 'DESCONECTADO',
                              style: TextStyle(
                                color: isConnected ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerRose.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.dangerRose.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.dangerRose, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppTheme.dangerRose, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Si está conectado
              if (isConnected) ...[
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.verified, color: Colors.green, size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Bot activo y respondiendo mensajes',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  if (_connectedNumber != null)
                                    Text(
                                      'Línea vinculada: +$_connectedNumber',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                    ),
                                ],
                              ),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.dangerRose),
                              icon: const Icon(Icons.logout, size: 18),
                              label: const Text('Desconectar'),
                              onPressed: _disconnect,
                            ),
                          ],
                        ),
                        const Divider(height: 32),
                        const Text(
                          '🧪 Probar envío de mensaje:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _testPhoneController,
                                decoration: const InputDecoration(
                                  labelText: 'Número destino con indicativo',
                                  hintText: 'Ej: 573001234567',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  prefixIcon: Icon(Icons.phone),
                                ),
                                keyboardType: TextInputType.phone,
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              ),
                              icon: const Icon(Icons.send, color: Colors.white, size: 18),
                              label: const Text('Enviar Prueba', style: TextStyle(color: Colors.white)),
                              onPressed: _sendTestMessage,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // Si está desconectado -> Muestra el QR y la opción de código
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Text(
                          'Vincular WhatsApp',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Abre WhatsApp en tu teléfono ➔ Menú (tres puntos o Configuración) ➔ Dispositivos vinculados ➔ Vincular un dispositivo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                        ),
                        const SizedBox(height: 24),

                        // Contenedor del QR
                        Container(
                          width: 260,
                          height: 260,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade300, width: 2),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4)),
                            ],
                          ),
                          child: _isConnecting
                              ? const Center(child: CircularProgressIndicator())
                              : (_qrBytes != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(_qrBytes!, fit: BoxFit.contain),
                                    )
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.qr_code, size: 64, color: Colors.grey.shade400),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Presiona el botón para generar el QR',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                      ],
                                    )),
                        ),

                        const SizedBox(height: 16),

                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          label: Text(
                            _qrBytes != null ? 'Refrescar Código QR' : 'Generar Código QR',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _isConnecting ? null : () => _connect(),
                        ),

                        const Divider(height: 40),

                        // Opción alternativa: Pairing Code por número de teléfono
                        const Text(
                          '¿Problemas con la cámara? Vincula con código de 8 dígitos:',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 250,
                              child: TextField(
                                controller: _phoneController,
                                decoration: const InputDecoration(
                                  labelText: 'Tu celular con indicativo país',
                                  hintText: '573001234567',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  prefixIcon: Icon(Icons.phone_android),
                                ),
                                keyboardType: TextInputType.phone,
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                              onPressed: _isConnecting ? null : () => _connect(phoneNumber: _phoneController.text.trim()),
                              child: const Text('Obtener Código'),
                            ),
                          ],
                        ),

                        if (_pairingCode != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.shade700),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'Ingresa este código en tu WhatsApp móvil:',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  _pairingCode!,
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 4,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'WhatsApp ➔ Dispositivos vinculados ➔ Vincular con número de teléfono',
                                  style: TextStyle(fontSize: 11, color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
