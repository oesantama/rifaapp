import 'package:flutter/material.dart';

/// Rifa Master app icon (gold ticket on navy tile), same artwork as the web/desktop icons.
class AppLogo extends StatelessWidget {
  final double size;

  const AppLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/app_icon.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Icon(Icons.confirmation_number, size: size * 0.8, color: const Color(0xFFF59E0B)),
    );
  }
}
