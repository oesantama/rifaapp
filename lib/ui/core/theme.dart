import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF0F172A);
  static const Color secondaryEmerald = Color(0xFF10B981);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color dangerRose = Color(0xFFF43F5E);
  static const Color backgroundLight = Color(0xFFF8FAFC);
  static const Color backgroundDark = Color(0xFF090D16);
  static const Color cardLight = Colors.white;
  static const Color cardDark = Color(0xFF1E293B);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primaryBlue,
    scaffoldBackgroundColor: backgroundLight,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryBlue,
      brightness: Brightness.light,
      primary: primaryBlue,
      secondary: secondaryEmerald,
      surface: cardLight,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryDark,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: cardLight,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: const DialogThemeData(
      insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: primaryBlue,
    scaffoldBackgroundColor: backgroundDark,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryBlue,
      brightness: Brightness.dark,
      primary: primaryBlue,
      secondary: secondaryEmerald,
      surface: cardDark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0B1120),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: cardDark,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: const DialogThemeData(
      insetPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
    ),
  );

  static Color getStatusColor(String status) {
    switch (status) {
      case 'CONFIRMADA':
        return Colors.teal;
      case 'PAGADA':
        return secondaryEmerald;
      case 'ABONO_PARCIAL':
        return accentAmber;
      case 'RESERVADA':
        return Colors.purple;
      case 'DISPONIBLE':
        return Colors.grey.shade400;
      default:
        return Colors.blueGrey;
    }
  }

  static String getStatusLabel(String status) {
    switch (status) {
      case 'CONFIRMADA':
        return 'PAGO CONFIRMADO (ADMIN)';
      case 'PAGADA':
        return 'PAGADA AL ASESOR';
      case 'ABONO_PARCIAL':
        return 'ABONO PARCIAL';
      case 'RESERVADA':
        return 'APARTADA / FIADA';
      case 'DISPONIBLE':
        return 'DISPONIBLE';
      default:
        return status;
    }
  }
}
