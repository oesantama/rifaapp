import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rifaapp/ui/core/theme.dart';

final cashCurrency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

/// "05/10/2026" for a day ("YYYY-MM-DD") or "05/10/2026 02:35 PM" (Colombia) for an instant.
String cashDate(String? value) {
  final text = value ?? '';
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return DateFormat('dd/MM/yyyy').format(DateTime.parse(text));
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return '';
  final col = parsed.toUtc().subtract(const Duration(hours: 5));
  return DateFormat('dd/MM/yyyy hh:mm a').format(DateTime(col.year, col.month, col.day, col.hour, col.minute));
}

/// Shows a payment proof stored in Google Drive. With [driveId] the image is fetched through our
/// server (the browser cannot load Drive images directly); the link opens it in Drive.
Future<void> showSoporte(BuildContext context, {String? url, String? webViewUrl, String? driveId, String title = 'Soporte'}) {
  final link = webViewUrl ?? url;
  final Future<Uint8List>? bytes = driveId != null && driveId.isNotEmpty ? RaffleRepository().fetchDriveFile(driveId) : null;
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: bytes == null
            ? Text(link == null ? 'Sin soporte adjunto.' : 'Ábralo con "Abrir en Drive".')
            : FutureBuilder<Uint8List>(
                future: bytes,
                builder: (c, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
                  }
                  if (snap.hasError || snap.data == null) {
                    return Text('No se pudo traer la imagen (${snap.error ?? 'sin datos'}). Ábrala con "Abrir en Drive".');
                  }
                  return ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.6),
                    child: InteractiveViewer(maxScale: 5, child: Image.memory(snap.data!, fit: BoxFit.contain)),
                  );
                },
              ),
      ),
      actions: [
        if (link != null)
          TextButton.icon(
            onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Abrir en Drive'),
          ),
        ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
      ],
    ),
  );
}

/// Asks for a reason (rejections); returns null if cancelled.
Future<String?> askReason(BuildContext context, String title, {String hint = '', String confirmLabel = 'Rechazar'}) async {
  final ctrl = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          autofocus: true,
          decoration: InputDecoration(labelText: 'Motivo *', hintText: hint, errorText: error),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose, foregroundColor: Colors.white),
            onPressed: () {
              if (ctrl.text.trim().length < 5) {
                setState(() => error = 'Escriba el motivo (mínimo 5 caracteres)');
                return;
              }
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
}

/// Small colored label.
class CashChip extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const CashChip(this.text, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
            Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      );
}

/// "label: value" line.
class CashInfoLine extends StatelessWidget {
  final String label;
  final String value;

  const CashInfoLine(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) => value.trim().isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$label: ', style: TextStyle(color: Colors.grey[700])),
              TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            style: const TextStyle(fontSize: 12.5),
          ),
        );
}

/// KPI tile for the cash screens.
class CashKpi extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  const CashKpi({super.key, required this.title, required this.value, required this.subtitle, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color))),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            ),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
          ],
        ),
      );
}
