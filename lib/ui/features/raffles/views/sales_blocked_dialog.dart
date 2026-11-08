import 'package:flutter/material.dart';
import 'package:rifaapp/ui/core/theme.dart';

/// Aviso cuando alguien (administrador o asesor) intenta vender en una rifa cerrada, inactiva o con el sorteo final vencido.
Future<void> showSalesBlockedDialog(BuildContext context, String reason) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.block, color: AppTheme.dangerRose, size: 44),
      title: const Text('No se puede vender', textAlign: TextAlign.center),
      content: Text(reason, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.4)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
    ),
  );
}
