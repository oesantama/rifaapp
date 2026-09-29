import 'package:flutter/material.dart';
import '../theme.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final bool isSmall;

  const StatusBadge({super.key, required this.status, this.isSmall = false});

  @override
  Widget build(BuildContext context) {
    Color color = AppTheme.getStatusColor(status);
    String label = AppTheme.getStatusLabel(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 8 : 12,
        vertical: isSmall ? 2 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: isSmall ? 10 : 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
