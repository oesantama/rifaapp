import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rifaapp/data/models/raffle.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/whatsapp_helper.dart';
import 'package:rifaapp/ui/features/banks/view_models/bank_view_model.dart';

/// Colombia has no daylight saving time: always UTC-5. Wall-clock times are handled as
/// DateTime values whose fields are the Colombian date and time.
class ColombiaTime {
  static const offset = Duration(hours: 5);
  static const maxTransferAgeDays = 15;

  /// Current date and time in Colombia, whatever the device's time zone.
  static DateTime now() {
    final utc = DateTime.now().toUtc().subtract(offset);
    return DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second);
  }

  static DateTime today() {
    final n = now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Oldest day a transfer may have (00:00 of the day 15 days ago).
  static DateTime oldestTransferDay() => today().subtract(const Duration(days: maxTransferAgeDays));

  /// Transfer day for the server: "YYYY-MM-DD".
  static String toDay(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  /// Date from the server -> "30/09/2026" for a day ("YYYY-MM-DD") or
  /// "30/09/2026 02:35 PM" (Colombian time) for an instant.
  static String format(String? iso) {
    final text = iso ?? '';
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return DateFormat('dd/MM/yyyy').format(DateTime.parse(text));
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return '';
    final col = parsed.toUtc().subtract(offset);
    return DateFormat('dd/MM/yyyy hh:mm a').format(DateTime(col.year, col.month, col.day, col.hour, col.minute));
  }
}

/// Approval numbers are compared without spaces, dashes or case (same rule as the server).
String approvalKey(String value) => value.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');

/// Raffle settings: accounts where buyers pay by bank transfer.
class TransferAccountsEditor extends StatelessWidget {
  final List<TransferAccount> accounts;
  final ValueChanged<List<TransferAccount>> onChanged;

  const TransferAccountsEditor({super.key, required this.accounts, required this.onChanged});

  Future<void> _edit(BuildContext context, int? index) async {
    final current = index != null ? accounts[index] : null;
    final bank = TextEditingController(text: current?.bank ?? '');
    final type = TextEditingController(text: current?.accountType ?? '');
    final number = TextEditingController(text: current?.accountNumber ?? '');
    final holder = TextEditingController(text: current?.holder ?? '');
    final key = TextEditingController(text: current?.key ?? '');
    String? error;

    final saved = await showDialog<TransferAccount>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(current == null ? 'Nueva cuenta' : 'Editar cuenta'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BankField(controller: bank, label: 'Banco o billetera *'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: type,
                    decoration: const InputDecoration(labelText: 'Tipo de cuenta', hintText: 'Ahorros, Corriente, Depósito'),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: number, decoration: const InputDecoration(labelText: 'Número de cuenta o celular')),
                  const SizedBox(height: 10),
                  TextField(
                    controller: key,
                    decoration: const InputDecoration(labelText: 'Llave (Bre-B)', hintText: 'Ej: @rifamaster, correo o celular'),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: holder, decoration: const InputDecoration(labelText: 'Titular')),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: AppTheme.dangerRose, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                if (bank.text.trim().isEmpty) {
                  setDialogState(() => error = 'Indique el banco o billetera.');
                  return;
                }
                if (number.text.trim().isEmpty && key.text.trim().isEmpty) {
                  setDialogState(() => error = 'Indique el número de cuenta o la llave.');
                  return;
                }
                Navigator.pop(
                  ctx,
                  TransferAccount(
                    id: current?.id ?? '',
                    bank: bank.text.trim(),
                    accountType: type.text.trim(),
                    accountNumber: number.text.trim(),
                    holder: holder.text.trim(),
                    key: key.text.trim(),
                  ),
                );
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved == null) return;
    final list = [...accounts];
    if (index != null) {
      list[index] = saved;
    } else {
      list.add(saved);
    }
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    void copySingleAccount(TransferAccount acc) {
      final text = '🏦 *${acc.bank}*\n'
          '• ${[
        acc.accountType,
        acc.accountNumber,
        if (acc.key.isNotEmpty) "Llave: ${acc.key}",
        acc.holder
      ].where((p) => p.isNotEmpty).join(" • ")}';
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.secondaryEmerald,
          content: Text('✓ Cuenta de ${acc.bank} copiada al portapapeles.'),
        ),
      );
    }

    void shareSingleAccountWhatsApp(TransferAccount acc) {
      final text = '🏦 *CUENTA PARA TRANSFERENCIA*\n'
          '----------------------------------------\n'
          '• *Banco:* ${acc.bank}\n'
          '${acc.accountType.isNotEmpty ? "• *Tipo:* ${acc.accountType}\n" : ""}'
          '${acc.accountNumber.isNotEmpty ? "• *Número:* ${acc.accountNumber}\n" : ""}'
          '${acc.key.isNotEmpty ? "• *Llave:* ${acc.key}\n" : ""}'
          '${acc.holder.isNotEmpty ? "• *Titular:* ${acc.holder}\n" : ""}'
          '----------------------------------------';
      Clipboard.setData(ClipboardData(text: text));
      WhatsAppHelper.sendWhatsAppMessage(phone: '', message: text);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.secondaryEmerald,
          content: Text('✓ Texto de cuenta copiado y listo para enviar por WhatsApp.'),
        ),
      );
    }

    void copyAllAccounts() {
      if (accounts.isEmpty) return;
      final buffer = StringBuffer();
      buffer.writeln('🏦 *CUENTAS DE TRANSFERENCIA*');
      buffer.writeln('----------------------------------------');
      for (final a in accounts) {
        buffer.writeln('• ${a.label}');
      }
      Clipboard.setData(ClipboardData(text: buffer.toString()));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.secondaryEmerald,
          content: Text('✓ Cuentas de transferencia copiadas al portapapeles.'),
        ),
      );
    }

    void shareAllAccountsWhatsApp() {
      if (accounts.isEmpty) return;
      final buffer = StringBuffer();
      buffer.writeln('🏦 *CUENTAS DE TRANSFERENCIA PARA PAGO*');
      buffer.writeln('----------------------------------------');
      for (final a in accounts) {
        buffer.writeln('• ${a.label}');
      }
      buffer.writeln('----------------------------------------');
      final text = buffer.toString();
      Clipboard.setData(ClipboardData(text: text));
      WhatsAppHelper.sendWhatsAppMessage(phone: '', message: text);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.secondaryEmerald,
          content: Text('✓ Cuentas copiadas y listos para enviar por WhatsApp.'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_balance, color: Colors.deepPurple, size: 22),
            const SizedBox(width: 8),
            const Expanded(child: Text('Cuentas para transferencias', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            if (accounts.isNotEmpty) ...[
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.primaryBlue),
                tooltip: 'Copiar todas las cuentas',
                onPressed: copyAllAccounts,
              ),
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.green),
                tooltip: 'Enviar todas por WhatsApp',
                onPressed: shareAllAccountsWhatsApp,
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Al registrar un pago por transferencia se elige a cuál de estas cuentas llegó el dinero.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < accounts.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.account_balance_wallet_outlined, color: Colors.deepPurple),
              title: Text(accounts[i].bank, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                [
                  accounts[i].accountType,
                  accounts[i].accountNumber,
                  if (accounts[i].key.isNotEmpty) 'Llave: ${accounts[i].key}',
                  accounts[i].holder,
                ].where((p) => p.isNotEmpty).join(' • '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.primaryBlue),
                    tooltip: 'Copiar esta cuenta',
                    onPressed: () => copySingleAccount(accounts[i]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.green),
                    tooltip: 'Enviar por WhatsApp',
                    onPressed: () => shareSingleAccountWhatsApp(accounts[i]),
                  ),
                  IconButton(icon: const Icon(Icons.edit_outlined, size: 20), tooltip: 'Editar', onPressed: () => _edit(context, i)),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    tooltip: 'Quitar',
                    onPressed: () => onChanged([...accounts]..removeAt(i)),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => _edit(context, null),
          icon: const Icon(Icons.add),
          label: const Text('Agregar cuenta'),
        ),
      ],
    );
  }
}

/// Bank picker with the active banks of the SuperAdmin's master list. A value that is no longer
/// active (e.g. an existing account) stays selectable so it is not lost.
class BankField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;

  const BankField({super.key, required this.controller, required this.label, this.validator});

  @override
  State<BankField> createState() => _BankFieldState();
}

class _BankFieldState extends State<BankField> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vm = context.read<BankViewModel>();
      if (vm.banks.isEmpty && !vm.isLoading) {
        vm.load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<BankViewModel>();
    final names = vm.activeBanks.map((b) => b.name).toList();
    final current = widget.controller.text.trim();
    if (current.isNotEmpty && !names.contains(current)) names.insert(0, current);

    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: current.isEmpty ? null : current,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.account_balance_outlined),
        border: const OutlineInputBorder(),
        helperText: vm.error != null
            ? 'No se pudo cargar la lista de bancos'
            : (names.isEmpty && !vm.isLoading ? 'No hay bancos activos: el SuperAdmin debe agregarlos' : null),
        helperMaxLines: 2,
      ),
      items: [for (final name in names) DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis))],
      onChanged: (v) => widget.controller.text = v ?? '',
      validator: widget.validator,
    );
  }
}

/// Shows where an approval number was already used. Returns true when the user decides to continue.
Future<bool> showApprovalMatchesDialog(BuildContext context, String approvalNumber, List<Map<String, dynamic>> matches) async {
  final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40),
      title: const Text('Número de aprobación ya registrado'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'La aprobación "$approvalNumber" aparece en ${matches.length == 1 ? 'otro pago' : '${matches.length} pagos'}. '
                'Puede ser la misma transferencia registrada dos veces. Revise antes de continuar.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              for (final m in matches) _MatchCard(match: m, currency: currency),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar y corregir')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
          child: const Text('Continuar de todas formas'),
        ),
      ],
    ),
  );
  return result == true;
}

class _MatchCard extends StatelessWidget {
  final Map<String, dynamic> match;
  final NumberFormat currency;

  const _MatchCard({required this.match, required this.currency});

  @override
  Widget build(BuildContext context) {
    final state = (match['state'] ?? '').toString();
    final isCurrent = state == 'VIGENTE';
    final numbers = (match['numbers'] as List? ?? []).join(' - ');
    final rows = <(String, String)>[
      ('Rifa', '${match['raffleTitle'] ?? ''}'),
      ('Boleta N°', numbers),
      ('Comprador', '${match['buyerName'] ?? ''}'),
      ('Teléfono', '${match['buyerPhone'] ?? ''}'),
      ('Cédula', '${match['buyerDocument'] ?? ''}'),
      ('Asesor', '${match['advisorName'] ?? ''}'),
      ('Valor', currency.format((match['amount'] as num?) ?? 0)),
      ('Fecha transferencia', ColombiaTime.format(match['transferDate'])),
      ('Banco origen', '${match['originBank'] ?? ''}'),
      ('Cuenta destino', '${match['cuentaDestino'] ?? ''}'),
      ('Registrado', '${ColombiaTime.format(match['registeredAt'])} por ${match['registeredBy'] ?? ''}'),
      if ((match['voidReason'] ?? '').toString().isNotEmpty)
        ('Anulado', '${ColombiaTime.format(match['voidedAt'])}: ${match['voidReason']}'),
    ];
    final link = match['soporteWebViewUrl'] as String?;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrent ? Colors.orange.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isCurrent ? Colors.orange.shade300 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isCurrent ? Colors.orange.shade700 : Colors.grey.shade600,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(state, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            if (value.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$label: ', style: TextStyle(color: Colors.grey[700])),
                    TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
          if (link != null)
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.image_search, size: 18),
              label: const Text('Ver soporte'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
            ),
        ],
      ),
    );
  }
}
