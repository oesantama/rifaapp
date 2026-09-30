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

  // Brand: navy + royal blue with gold accent (same palette as the app icon).
  static const Color brandGold = Color(0xFFF59E0B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderDark = Color(0xFF334155);
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF1E3A8A), primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData lightTheme = _build(Brightness.light);
  static ThemeData darkTheme = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? cardDark : cardLight;
    final border = isDark ? borderDark : borderLight;
    final radius = BorderRadius.circular(12);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryBlue,
      brightness: brightness,
      primary: primaryBlue,
      secondary: secondaryEmerald,
      tertiary: brandGold,
      error: dangerRose,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: primaryBlue,
      scaffoldBackgroundColor: isDark ? backgroundDark : backgroundLight,
      fontFamily: 'Roboto',
      colorScheme: colorScheme,
      dividerColor: border,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF0B1120) : primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: isDark ? 2 : 1,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border.withValues(alpha: isDark ? 0.6 : 0.9)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: primaryBlue, width: 1.6)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: radius),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: border),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radius)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primaryBlue,
        unselectedItemColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        type: BottomNavigationBarType.fixed,
        elevation: 12,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: primaryBlue.withValues(alpha: 0.14),
        selectedIconTheme: const IconThemeData(color: primaryBlue),
        selectedLabelTextStyle: const TextStyle(color: primaryBlue, fontWeight: FontWeight.w700, fontSize: 12),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: primaryBlue,
        indicatorColor: primaryBlue,
        labelStyle: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

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
