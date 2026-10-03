import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rifaapp/data/models/raffle.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/url_launcher_helper.dart' as web_launcher;

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
    final waUrl = Uri.parse(cleanPhone.isNotEmpty ? 'https://wa.me/$cleanPhone?text=$encodedMsg' : 'https://wa.me/?text=$encodedMsg');

    if (kIsWeb) {
      // Web: open the app directly; a wa.me tab would stay blank after handing over to the app
      final appUrl = cleanPhone.isNotEmpty ? 'whatsapp://send?phone=$cleanPhone&text=$encodedMsg' : 'whatsapp://send?text=$encodedMsg';
      final isPhone = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
      final fallback = isPhone
          ? waUrl.toString()
          : (cleanPhone.isNotEmpty
              ? 'https://web.whatsapp.com/send?phone=$cleanPhone&text=$encodedMsg'
              : 'https://web.whatsapp.com/send?text=$encodedMsg');
      web_launcher.openWhatsAppApp(appUrl, fallback);
      return true;
    }
    try {
      if (await launchUrl(waUrl, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank')) return true;
    } catch (_) {}
    try {
      final deepLink = cleanPhone.isNotEmpty ? 'whatsapp://send?phone=$cleanPhone&text=$encodedMsg' : 'whatsapp://send?text=$encodedMsg';
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
      // Accounts only for who still owes
      if (isDebt && raffle.transferAccounts.isNotEmpty) {
        b.writeln('----------------------------------------');
        b.writeln('💳 *CUENTAS PARA PAGO:*');
        b.write(accountsBlock(raffle.transferAccounts));
      }
    }

    b.writeln('----------------------------------------');
    b.writeln(isDebt
        ? '¡Agradecemos realizar tu abono o pago pendiente a cualquiera de las cuentas indicadas para asegurar tu número en el próximo sorteo! 🍀'
        : '¡Gracias por tu compra y muchos éxitos en el sorteo! 🍀');
    return b.toString();
  }

  /// Transfer accounts, one field per line and a blank line between accounts.
  static String accountsBlock(List<TransferAccount> accounts) =>
      accounts.isEmpty ? '' : '${accounts.map((a) => a.messageBlock).join('\n\n')}\n';

  static const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  static const _months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  /// "sábado 03 de octubre de 2026" in Colombian time (UTC-5), whatever the device's time zone.
  static String? drawDateText(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return null;
    final col = parsed.isUtc || iso.endsWith('Z') ? parsed.toUtc().subtract(const Duration(hours: 5)) : parsed;
    return '${_weekdays[col.weekday - 1]} ${col.day.toString().padLeft(2, '0')} de ${_months[col.month - 1]} de ${col.year}';
  }

  /// Reminder for a reserved or partially paid ticket: what is still owed, when the raffle plays,
  /// that an unpaid ticket does not play, and how to pay (cash or the raffle's transfer accounts).
  static String buildPaymentReminder({required Ticket ticket, Raffle? raffle, required String raffleTitle}) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final pending = ticket.balancePending > 0 ? ticket.balancePending : (ticket.price - ticket.totalPaid).clamp(0, double.infinity);
    final b = StringBuffer();
    b.writeln('🔔 *RECORDATORIO DE PAGO* - $raffleTitle');
    b.writeln('----------------------------------------');
    b.writeln(ticket.buyerName.isNotEmpty ? 'Hola *${ticket.buyerName}* 👋' : 'Hola 👋');
    b.writeln('Te recordamos que tu boleta *N° ${ticket.displayNumber}* aún tiene saldo pendiente:');
    b.writeln('💰 *Valor boleta:* ${currency.format(ticket.price)}');
    b.writeln('✅ *Abonado:* ${currency.format(ticket.totalPaid)}');
    b.writeln('🔴 *Debes:* ${currency.format(pending)}');
    b.writeln('----------------------------------------');
    final date = raffle != null ? drawDateText(raffle.mainDrawDate) : null;
    final lottery = raffle?.mainLottery ?? '';
    if (date != null) {
      b.writeln('📅 La rifa juega el *$date*${lottery.isNotEmpty ? ' con la *$lottery*' : ''}.');
    }
    b.writeln('⚠️ *Recuerda: la boleta que no esté pagada en su totalidad NO juega.*');
    b.writeln('----------------------------------------');
    final accounts = raffle?.transferAccounts ?? const [];
    final advisor = ticket.advisorName.trim();
    b.writeln('💵 Puedes pagar en *efectivo*${advisor.isNotEmpty ? ' con tu asesor(a) $advisor' : ''}'
        '${accounts.isNotEmpty ? ' o por *transferencia* a:' : ' o por transferencia (pregúntanos por las cuentas).'}');
    b.write(accountsBlock(accounts));
    if (accounts.isNotEmpty) b.writeln('📲 Si pagas por transferencia, envíanos el comprobante por este medio.');
    b.writeln('----------------------------------------');
    b.writeln('¡Gracias y muchos éxitos en el sorteo! 🍀');
    return b.toString();
  }

  /// Sends the company's message for a saved ticket, filled on the server ([kind]: 'receipt' or
  /// 'reminder'). If the server cannot be reached, [fallback] builds the text locally.
  static Future<bool> sendSavedTicketMessage(
    Ticket ticket, {
    required String kind,
    required String Function() fallback,
    BuildContext? context,
  }) async {
    String message;
    String phone = ticket.buyerPhone;
    try {
      final data = await RaffleRepository().fetchTicketWhatsAppMessage(ticket.id, kind: kind);
      message = (data['message'] ?? '').toString();
      if ((data['phone'] ?? '').toString().isNotEmpty) phone = data['phone'].toString();
      if (message.isEmpty) message = fallback();
    } catch (_) {
      message = fallback();
    }
    // Without a phone number the message can be copied and sent by any other means
    if (cleanPhoneNumber(phone).isEmpty && context != null && context.mounted) {
      await showShareMessageDialog(context, message);
      return true;
    }
    // Like the receipt button: the message is also copied, in case it has to be pasted
    try {
      await Clipboard.setData(ClipboardData(text: message)).timeout(const Duration(seconds: 2));
    } catch (_) {}
    final launched = await sendWhatsAppMessage(phone: phone, message: message);
    if (context != null && context.mounted) {
      if (launched) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppTheme.secondaryEmerald,
            content: Text('✓ Abriendo WhatsApp con el mensaje del comprador...'),
          ),
        );
      } else {
        await showShareMessageDialog(context, message);
      }
    }
    return launched;
  }

  /// Shows [message] with options to copy it or open WhatsApp to choose the contact.
  static Future<void> showShareMessageDialog(BuildContext context, String message) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.phone_disabled_outlined, color: Colors.orange, size: 36),
        title: const Text('El comprador no tiene celular registrado'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Copie el mensaje para enviarlo por otro medio, o abra WhatsApp y elija el contacto.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCF8C6).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.5)),
                  ),
                  child: SingleChildScrollView(child: SelectableText(message, style: const TextStyle(fontSize: 12.5, height: 1.4))),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              sendWhatsAppMessage(phone: '', message: message);
            },
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Abrir WhatsApp'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              var copied = true;
              try {
                await Clipboard.setData(ClipboardData(text: message)).timeout(const Duration(seconds: 2));
              } catch (_) {
                copied = false;
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(copied
                        ? '✓ Mensaje copiado. Péguelo en el medio que prefiera.'
                        : 'No se pudo copiar automáticamente: mantenga presionado el texto para copiarlo.'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar mensaje'),
          ),
        ],
      ),
    );
  }

  /// Opens WhatsApp with the payment reminder for [ticket] (to the buyer's phone if it has one).
  static Future<bool> sendPaymentReminder({required Ticket ticket, Raffle? raffle, required String raffleTitle, BuildContext? context}) =>
      sendSavedTicketMessage(
        ticket,
        kind: 'reminder',
        context: context,
        fallback: () => buildPaymentReminder(ticket: ticket, raffle: raffle, raffleTitle: raffleTitle),
      );

  /// Tickets that can get a payment reminder: reserved or with a partial payment, still owing.
  static bool canRemind(Ticket ticket) =>
      (ticket.status == 'RESERVADA' || ticket.status == 'ABONO_PARCIAL') && ticket.totalPaid < ticket.price;

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
    if (isDebt && raffle != null && raffle.transferAccounts.isNotEmpty) {
      buffer.writeln('----------------------------------------');
      buffer.writeln('💳 *CUENTAS PARA PAGO:*');
      buffer.write(accountsBlock(raffle.transferAccounts));
    }
    buffer.writeln('----------------------------------------');

    if (pending > 0) {
      buffer.writeln(
          '¡Agradecemos realizar tu abono o pago pendiente a cualquiera de las cuentas indicadas para asegurar tu número en el próximo sorteo! 🍀');
    } else {
      buffer.writeln('¡Gracias por tu compra y muchos éxitos en el sorteo! 🍀');
    }

    return buffer.toString();
  }
}
