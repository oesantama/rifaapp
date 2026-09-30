import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/theme.dart';

class WhatsAppHelper {
  /// Formats and sanitizes phone numbers for WhatsApp API compatibility.
  /// Automatically prepends country code '+57' for 10-digit Colombian mobile numbers if missing.
  static String cleanPhoneNumber(String rawPhone) {
    String digitsOnly = rawPhone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digitsOnly.startsWith('+')) {
      return digitsOnly.replaceAll('+', '');
    }
    // Standard 10-digit Colombian mobile number starting with '3'
    if (digitsOnly.length == 10 && digitsOnly.startsWith('3')) {
      return '57$digitsOnly';
    }
    return digitsOnly;
  }

  /// Opens WhatsApp app or web with a pre-filled message
  static Future<bool> sendWhatsAppMessage({
    required String phone,
    required String message,
  }) async {
    final cleanPhone = cleanPhoneNumber(phone);
    if (cleanPhone.isEmpty) return false;

    final encodedMsg = Uri.encodeComponent(message);
    final waUrl = Uri.parse('https://wa.me/$cleanPhone?text=$encodedMsg');

    try {
      if (await canLaunchUrl(waUrl)) {
        return await launchUrl(waUrl, mode: LaunchMode.externalApplication);
      } else {
        // Fallback for direct deep link
        final deepLink = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encodedMsg');
        if (await canLaunchUrl(deepLink)) {
          return await launchUrl(deepLink, mode: LaunchMode.externalApplication);
        }
      }
    } catch (_) {}
    return false;
  }

  /// Generates structured WhatsApp message for ticket receipt or payment reminder
  static String generateTicketMessage({
    required Ticket ticket,
    required String raffleTitle,
  }) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final pending = ticket.balancePending;
    final totalPaid = ticket.totalPaid;
    final statusLabel = AppTheme.getStatusLabel(ticket.status);

    final isDebt = pending > 0;
    final headerEmoji = isDebt ? '⚠️' : '🎟️';
    final headerTitle = isDebt ? '*RECORDATORIO DE PAGO / DEUDA*' : '*COMPROBANTE DE BOLETA*';

    final buffer = StringBuffer();
    buffer.writeln('$headerEmoji $headerTitle - $raffleTitle');
    buffer.writeln('----------------------------------------');
    buffer.writeln('👤 *Comprador:* ${ticket.buyerName.isNotEmpty ? ticket.buyerName : "Pendiente"}');
    buffer.writeln('📱 *Celular:* ${ticket.buyerPhone.isNotEmpty ? ticket.buyerPhone : "No registrado"}');
    buffer.writeln('🔢 *Número(s):* ${ticket.displayNumber}');
    buffer.writeln('💰 *Valor Boleta:* ${currency.format(ticket.price)}');
    buffer.writeln('✅ *Total Abonado:* ${currency.format(totalPaid)}');

    if (pending > 0) {
      buffer.writeln('🔴 *SALDO PENDIENTE:* ${currency.format(pending)}');
    } else {
      buffer.writeln('🎉 *PAGO COMPLETO:* ${currency.format(ticket.price)}');
    }

    buffer.writeln('📊 *Estado:* $statusLabel');
    buffer.writeln('----------------------------------------');

    if (pending > 0) {
      buffer.writeln('¡Agradecemos realizar tu abono o pago pendiente para asegurar tu número en el próximo sorteo! 🍀');
    } else {
      buffer.writeln('¡Gracias por tu compra y muchos éxitos en el sorteo! 🍀');
    }

    return buffer.toString();
  }
}
