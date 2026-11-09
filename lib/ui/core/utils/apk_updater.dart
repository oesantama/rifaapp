import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rifaapp/ui/core/theme.dart';

/// Descarga la última versión del APK desde el propio servidor y abre el instalador de Android:
/// la persona solo toca "Instalar". Se instala encima de la actual y NO pierde sus datos.
class ApkUpdateDialog extends StatefulWidget {
  final String url;
  const ApkUpdateDialog({super.key, required this.url});

  static Future<void> show(BuildContext context, String url) =>
      showDialog(context: context, barrierDismissible: false, builder: (_) => ApkUpdateDialog(url: url));

  @override
  State<ApkUpdateDialog> createState() => _ApkUpdateDialogState();
}

class _ApkUpdateDialogState extends State<ApkUpdateDialog> {
  StreamSubscription<OtaEvent>? _sub;
  int _percent = 0;
  bool _installing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    setState(() {
      _percent = 0;
      _installing = false;
      _error = null;
    });
    try {
      _sub?.cancel();
      _sub = OtaUpdate().execute(widget.url, destinationFilename: 'rifamaster.apk').listen(
        (event) {
          if (!mounted) return;
          switch (event.status) {
            case OtaStatus.DOWNLOADING:
              setState(() => _percent = int.tryParse(event.value ?? '') ?? _percent);
            case OtaStatus.INSTALLING:
              // Android muestra su pantalla de instalación: se cierra este aviso para no taparla
              setState(() => _installing = true);
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) Navigator.of(context).maybePop();
              });
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              setState(() => _error = 'Falta el permiso para instalar aplicaciones. Actívelo en Ajustes > "Instalar apps desconocidas" para Rifa Master y vuelva a intentar.');
            case OtaStatus.ALREADY_RUNNING_ERROR:
              setState(() => _error = 'Ya hay una descarga en curso. Espere un momento.');
            case OtaStatus.DOWNLOAD_ERROR:
              setState(() => _error = 'No se pudo descargar la actualización. Revise su conexión e intente de nuevo.');
            case OtaStatus.INSTALLATION_ERROR:
            case OtaStatus.INTERNAL_ERROR:
            case OtaStatus.CHECKSUM_ERROR:
              setState(() => _error = 'No se pudo instalar la actualización (${event.value ?? event.status.name}).');
            default:
              break;
          }
        },
        onError: (Object e) {
          if (mounted) setState(() => _error = 'No se pudo descargar la actualización: $e');
        },
      );
    } catch (e) {
      _error = 'No se pudo iniciar la descarga: $e';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.system_update, color: AppTheme.primaryBlue),
        SizedBox(width: 10),
        Expanded(child: Text('Actualizando Rifa Master', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppTheme.dangerRose, fontWeight: FontWeight.w600))
          else if (_installing)
            const Text('Listo. Toque "Instalar" en la pantalla de Android. No pierde sus datos.')
          else ...[
            Text(_percent < 100 ? 'Descargando la última versión: $_percent%' : 'Descarga lista, abriendo el instalador...'),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _percent > 0 ? _percent / 100 : null, minHeight: 8, borderRadius: BorderRadius.circular(6)),
            const SizedBox(height: 10),
            const Text('Al terminar, Android le pedirá confirmar la instalación.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ],
      ),
      actions: [
        if (_error != null) TextButton(onPressed: _start, child: const Text('Reintentar')),
        // Plan B: si la descarga dentro de la app falla, el navegador del teléfono la descarga y la instala
        if (_error != null)
          TextButton(
            onPressed: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
            child: const Text('Descargar con el navegador'),
          ),
        TextButton(
          onPressed: () {
            _sub?.cancel();
            Navigator.of(context).pop();
          },
          child: Text(_installing ? 'Cerrar' : 'Cancelar'),
        ),
      ],
    );
  }
}
