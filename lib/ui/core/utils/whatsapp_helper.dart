import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rifaapp/data/models/raffle.dart';
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

  /// Opens WhatsApp with a pre-filled message.
  ///
  /// The link is opened right away, without asking first whether it can be opened:
  /// - iPhone/iPad Safari only allows opening it during the tap itself (any wait before blocks it).
  /// - Android 11+ answers "no" to that question unless the app declares the links it opens.
  static Future<bool> sendWhatsAppMessage({
    required String phone,
    required String message,
  }) async {
    final cleanPhone = cleanPhoneNumber(phone);
    if (cleanPhone.isEmpty) return false;

    final encodedMsg = Uri.encodeComponent(message);
    final waUrl = Uri.parse('https://wa.me/$cleanPhone?text=$encodedMsg');

    try {
      if (await launchUrl(waUrl, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank')) return true;
    } catch (_) {}
    try {
      // Direct deep link to the installed app
      return await launchUrl(Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encodedMsg'), mode: LaunchMode.externalApplication);
    } catch (_) {}
    return false;
  }

  /// Receipt / payment reminder text, including the raffle's draw date, weekly draws and description.
  static String buildTicketReceipt({
    required Ticket ticket,
    Raffle? raffle,
    required String raffleTitle,
    required String buyerName,
    required String buyerPhone,
    required double totalPaid,
    required String status,
  }) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final pending = (ticket.price - totalPaid).clamp(0, double.infinity);
    final isDebt = pending > 0;
    final b = StringBuffer();

    b.writeln('${isDebt ? '⚠️ *RECORDATORIO DE PAGO - DEUDA*' : '🎟️ *COMPROBANTE DE BOLETA*'} - $raffleTitle');
    if (raffle != null && raffle.description.trim().isNotEmpty) b.writeln('📝 ${raffle.description.trim()}');
    b.writeln('----------------------------------------');
    b.writeln('🔢 *Número(s):* ${ticket.displayNumber}');
    b.writeln('👤 *Comprador:* $buyerName');
    b.writeln('📱 *Celular:* ${buyerPhone.isNotEmpty ? buyerPhone : "No registrado"}');
    b.writeln('💰 *Valor Boleta:* ${currency.format(ticket.price)}');
    b.writeln('✅ *Total Abonado:* ${currency.format(totalPaid)}');
    b.writeln(isDebt ? '🔴 *SALDO PENDIENTE:* ${currency.format(pending)}' : '🎉 *PAGO COMPLETO:* ${currency.format(ticket.price)}');
    b.writeln('📊 *Estado:* ${AppTheme.getStatusLabel(status)}');

    if (raffle != null) {
      final drawDate = DateTime.tryParse(raffle.mainDrawDate);
      final lottery = raffle.lotteryName.trim();
      if (drawDate != null || raffle.hasWeeklyDraws) b.writeln('----------------------------------------');
      if (drawDate != null) {
        b.writeln('📅 *Juega el día:* ${DateFormat('dd/MM/yyyy').format(drawDate.toLocal())}'
            '${lottery.isNotEmpty ? ' con la $lottery' : ''}');
        b.writeln('🏆 *Gana con:* ${raffle.winningRuleText}');
      }
      if (raffle.hasWeeklyDraws) {
        final minAbono =
            raffle.weeklyMinAbonoType == 'PORCENTAJE' ? raffle.ticketPrice * raffle.weeklyMinAbonoValue / 100 : raffle.weeklyMinAbonoValue;
        b.writeln('🗓️ *Sorteos semanales:* cada ${raffle.weeklyDrawDay}'
            '${lottery.isNotEmpty ? ' con la $lottery' : ''}');
        if (minAbono > 0) b.writeln('   Participas con un abono mínimo de ${currency.format(minAbono)}.');
      }
    }

    b.writeln('----------------------------------------');
    b.writeln(isDebt
        ? '¡Agradecemos realizar tu abono o pago pendiente para asegurar tu número en el próximo sorteo! 🍀'
        : '¡Gracias por tu compra y muchos éxitos en el sorteo! 🍀');
    return b.toString();
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
