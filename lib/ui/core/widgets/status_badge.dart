import 'package:flutter/material.dart';
import '../theme.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final bool isSmall;

  const StatusBadge({super.key, required this.status, this.isSmall = false});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = AppTheme.getStatusColor(status);
    // En modo oscuro el texto se aclara y el fondo se refuerza para que se lea (DISPONIBLE usa gris claro)
    final color = dark && status == 'DISPONIBLE' ? Colors.grey.shade500 : base;
    final textColor = status == 'DISPONIBLE' ? (dark ? Colors.grey.shade200 : Colors.grey.shade800) : AppTheme.readable(context, base);
    String label = AppTheme.getStatusLabel(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 8 : 12,
        vertical: isSmall ? 2 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.22 : 0.15),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          // DISPONIBLE usa gris claro: el texto va en gris oscuro y más grueso para que se lea bien
          color: textColor,
          fontSize: isSmall ? 10.5 : 12,
          fontWeight: status == 'DISPONIBLE' ? FontWeight.w900 : FontWeight.bold,
        ),
      ),
    );
  }
}
