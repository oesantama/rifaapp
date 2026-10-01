import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateFormatterColombia {
  /// Formatea cualquier string de fecha (ISO o YYYY-MM-DD) al formato de Colombia: "28/12/2026"
  static String formatShort(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return '';
    try {
      final str = dateStr.trim();
      final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(str);
      if (m != null) {
        return '${m.group(3)}/${m.group(2)}/${m.group(1)}';
      }
      DateTime dt = DateTime.parse(str).toLocal();
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      if (dateStr.contains('/')) return dateStr.trim();
      return dateStr.trim();
    }
  }

  /// Formatea fecha y hora al formato de Colombia: "28/12/2026 07:56 PM"
  static String formatWithTime(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return '';
    try {
      DateTime dt = DateTime.parse(dateStr.trim()).toLocal();
      return DateFormat('dd/MM/yyyy hh:mm a').format(dt);
    } catch (_) {
      return dateStr.trim();
    }
  }

  /// Convierte del formato de Colombia "dd/MM/yyyy" o ISO a ISO string para la API del backend
  static String toIsoString(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) {
      return DateTime.now().toIso8601String();
    }
    try {
      final str = dateStr.trim();
      if (str.contains('/')) {
        final parts = str.split('/');
        if (parts.length == 3) {
          int day = int.parse(parts[0]);
          int month = int.parse(parts[1]);
          int year = int.parse(parts[2]);
          return DateTime(year, month, day, 12, 0, 0).toIso8601String();
        }
      }
      final dt = DateTime.parse(str);
      return DateTime(dt.year, dt.month, dt.day, 12, 0, 0).toIso8601String();
    } catch (_) {
      return DateTime.now().toIso8601String();
    }
  }

  /// Abre un DatePicker con formato de Colombia y asigna "dd/MM/yyyy" al controller
  static Future<void> selectDate(
    BuildContext context,
    TextEditingController controller, {
    DateTime? firstDate,
    DateTime? lastDate,
  }) async {
    DateTime initial = DateTime.now();
    try {
      if (controller.text.trim().isNotEmpty) {
        if (controller.text.contains('/')) {
          final parts = controller.text.split('/');
          if (parts.length == 3) {
            initial = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          }
        } else {
          initial = DateTime.parse(controller.text.trim());
        }
      }
    } catch (_) {}

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime(2035),
      helpText: 'SELECCIONAR FECHA (COLOMBIA)',
      cancelText: 'CANCELAR',
      confirmText: 'ACEPTAR',
      fieldLabelText: 'Fecha',
      fieldHintText: 'dd/mm/aaaa',
    );

    if (picked != null) {
      controller.text = DateFormat('dd/MM/yyyy').format(picked);
    }
  }
}
