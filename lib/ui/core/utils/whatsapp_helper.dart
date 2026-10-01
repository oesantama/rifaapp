import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rifaapp/data/models/raffle.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/data/services/api_service.dart';
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
  /// If phone is empty, opens WhatsApp contact selector with the message pre-filled.
  static Future<bool> sendWhatsAppMessage({
    required String phone,
    required String message,
  }) async {
    final cleanPhone = cleanPhoneNumber(phone);
    final encodedMsg = Uri.encodeComponent(message);
    final waUrl = Uri.parse(cleanPhone.isNotEmpty
        ? 'https://wa.me/$cleanPhone?text=$encodedMsg'
        : 'https://wa.me/?text=$encodedMsg');

    try {
      if (await launchUrl(waUrl, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank')) return true;
    } catch (_) {}
    try {
      final deepLink = cleanPhone.isNotEmpty
          ? 'whatsapp://send?phone=$cleanPhone&text=$encodedMsg'
          : 'whatsapp://send?text=$encodedMsg';
      return await launchUrl(Uri.parse(deepLink), mode: LaunchMode.externalApplication);
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
    if (ticket.verificationCode != null) {
      b.writeln('🔐 *Verifica tu boleta:* ${ApiService.verificationUrl(ticket.verificationCode!)}');
    }

    if (raffle != null) {
      final drawDate = DateTime.tryParse(raffle.mainDrawDate);
      final lottery = raffle.mainLottery; // main draw
      final weeklyLottery = raffle.lotteryName.trim().isNotEmpty ? raffle.lotteryName.trim() : lottery;
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
            '${weeklyLottery.isNotEmpty ? ' con la $weeklyLottery' : ''}');
        if (minAbono > 0) b.writeln('   Participas con un abono mínimo de ${currency.format(minAbono)}.');
      }
      if (raffle.transferAccounts.isNotEmpty) {
        b.writeln('----------------------------------------');
        b.writeln('🏦 *CUENTAS DE TRANSFERENCIA PARA PAGO:*');
        for (final acc in raffle.transferAccounts) {
          b.writeln('• ${acc.label}');
        }
      }
    }

    b.writeln('----------------------------------------');
    b.writeln(isDebt
        ? '¡Agradecemos realizar tu abono o pago pendiente a cualquiera de las cuentas indicadas para asegurar tu número en el próximo sorteo! 🍀'
        : '¡Gracias por tu compra y muchos éxitos en el sorteo! 🍀');
    return b.toString();
  }

  /// Generates structured WhatsApp message for ticket receipt or payment reminder
  static String generateTicketMessage({
    required Ticket ticket,
    required String raffleTitle,
    Raffle? raffle,
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
    if (raffle != null && raffle.transferAccounts.isNotEmpty) {
      buffer.writeln('----------------------------------------');
      buffer.writeln('🏦 *CUENTAS DE TRANSFERENCIA PARA PAGO:*');
      for (final acc in raffle.transferAccounts) {
        buffer.writeln('• ${acc.label}');
      }
    }
    buffer.writeln('----------------------------------------');

    if (pending > 0) {
      buffer.writeln('¡Agradecemos realizar tu abono o pago pendiente a cualquiera de las cuentas indicadas para asegurar tu número en el próximo sorteo! 🍀');
    } else {
      buffer.writeln('¡Gracias por tu compra y muchos éxitos en el sorteo! 🍀');
    }

    return buffer.toString();
  }
}
