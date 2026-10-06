import 'package:flutter/material.dart';
import 'package:rifaapp/ui/core/theme.dart';

/// Error shown on top of everything (also over an open form), so it is never missed.
Future<void> showErrorAlert(BuildContext context, String title, String message) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.error_outline, color: AppTheme.dangerRose, size: 40),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(message, style: const TextStyle(fontSize: 14, height: 1.4)),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose, foregroundColor: Colors.white),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}
