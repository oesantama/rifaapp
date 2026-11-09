import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:rifaapp/ui/core/widgets/responsive_flex_child.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/advisor.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/data/models/raffle.dart';
import 'package:rifaapp/ui/core/sale_channels.dart';
import 'package:rifaapp/ui/features/sale_channels/view_models/sale_channel_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/widgets/status_badge.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/core/utils/whatsapp_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rifaapp/ui/core/utils/file_picker_helper.dart';
import 'package:rifaapp/ui/core/utils/image_compress.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'ticket_print_dialog.dart';
import 'transfer_widgets.dart';
import 'package:rifaapp/ui/features/admin_cash/views/cash_widgets.dart' show showSoporte, askReason;
import 'package:rifaapp/ui/features/admin_cash/view_models/cash_view_model.dart';

class TicketDetailDialog extends StatefulWidget {
  final Ticket ticket;
  final String? raffleTitle;

  const TicketDetailDialog({super.key, required this.ticket, this.raffleTitle});

  @override
  State<TicketDetailDialog> createState() => _TicketDetailDialogState();
}

class _TicketDetailDialogState extends State<TicketDetailDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _buyerNameController;
  late TextEditingController _buyerPhoneController;
  late TextEditingController _buyerDocumentController;
  late TextEditingController _buyerEmailController;
  late TextEditingController _buyerCityController;
  String? _saleChannel; // how the buyer was reached
  bool _saving = false; // blocks repeated taps while the payment is being saved
  // One id per submission: if the same request reaches the server twice, it is applied once
  String _requestId = _newRequestId();

  static String _newRequestId() => '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 31)}';
  late TextEditingController _amountController;
  late TextEditingController _noteController;
  late TextEditingController _cuentaDestinoController;
  String _metodoPago = 'efectivo';
  String? _soporteBase64;
  bool _uploadingSoporte = false;
  // Bank transfer details
  String? _transferAccountId;
  DateTime? _transferDate; // day of the transfer (Colombian calendar)
  final _transferDateController = TextEditingController();
  final _originBankController = TextEditingController();
  final _approvalController = TextEditingController();
  final _approvalFocus = FocusNode();
  String? _approvalCheckedKey; // approval number already checked (or confirmed as repeated)
  String? _approvalCheckedSig; // número + valor del abono + valor leído del comprobante con los que se revisó
  bool _approvalDuplicateConfirmed = false;
  bool _supportDuplicateConfirmed = false;
  // Número de aprobación repetido que no se puede usar (esa transferencia no alcanza para otra boleta)
  String? _approvalBlockedKey;
  String _approvalBlockedReason = '';
  // Lectura automática del comprobante (referencia, valor, banco) y validación contra lo escrito
  Map<String, dynamic>? _proofRead;
  bool _readingProof = false;
  bool _referenceMismatchConfirmed = false;
  bool _checkingApproval = false;
  String? _selectedSellerId;
  String? _selectedSellerName;
  String? _saleZone; // OFICINA / CALLE (solo lo elige el asesor integral)

  @override
  void initState() {
    super.initState();
    _buyerNameController = TextEditingController(text: widget.ticket.buyerName);
    _buyerPhoneController = TextEditingController(text: widget.ticket.buyerPhone);
    _buyerDocumentController = TextEditingController(text: widget.ticket.buyerDocument);
    _buyerEmailController = TextEditingController(text: widget.ticket.buyerEmail);
    _buyerCityController = TextEditingController(text: widget.ticket.buyerCity);
    _saleChannel = widget.ticket.saleChannel.isNotEmpty ? widget.ticket.saleChannel : null;
    _amountController = TextEditingController(text: '0');
    _noteController = TextEditingController();
    _cuentaDestinoController = TextEditingController();
    // Leaving the approval field checks whether that number was already used
    _approvalFocus.addListener(() {
      if (!_approvalFocus.hasFocus) _checkApproval();
    });
    _selectedSellerId = widget.ticket.advisorId.isNotEmpty ? widget.ticket.advisorId : null;
    _saleZone = widget.ticket.saleZone.isNotEmpty ? widget.ticket.saleZone : null;
    _selectedSellerName = widget.ticket.advisorName;
  }

  @override
  void dispose() {
    _buyerNameController.dispose();
    _buyerPhoneController.dispose();
    _buyerDocumentController.dispose();
    _buyerEmailController.dispose();
    _buyerCityController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    _cuentaDestinoController.dispose();
    _transferDateController.dispose();
    _originBankController.dispose();
    _approvalController.dispose();
    _approvalFocus.dispose();
    super.dispose();
  }

  List<TransferAccount> get _transferAccounts =>
      context.read<RaffleViewModel>().raffles.where((r) => r.id == widget.ticket.raffleId).firstOrNull?.transferAccounts ?? const [];

  Future<void> _pickTransferDate() async {
    final today = ColombiaTime.today();
    final date = await showDatePicker(
      context: context,
      initialDate: _transferDate ?? today,
      firstDate: ColombiaTime.oldestTransferDay(),
      lastDate: today,
      helpText: 'Fecha de la transferencia',
    );
    if (date == null || !mounted) return;
    setState(() {
      _transferDate = date;
      _transferDateController.text = DateFormat('dd/MM/yyyy').format(date);
    });
  }

  String? _validateTransferDate(String? _) {
    final date = _transferDate;
    if (date == null) return 'Indique la fecha de la transferencia';
    if (date.isAfter(ColombiaTime.today())) return 'No puede ser posterior a hoy';
    if (date.isBefore(ColombiaTime.oldestTransferDay())) {
      return 'No puede tener más de ${ColombiaTime.maxTransferAgeDays} días de antigüedad';
    }
    return null;
  }

  /// Campo "Asesor / Vendedor" del administrador: abre una lista con buscador (por nombre, cédula, usuario o teléfono).
  Widget _sellerField(List<Advisor> advisors) {
    final id = _selectedSellerId;
    final selected = id == null || id == 'admin' ? null : advisors.where((a) => a.id == id).firstOrNull;
    final label = selected == null ? '🏢 Venta Directa (Administrador)' : '👤 ${selected.name} (${selected.code}) • ${selected.typeLabel}';
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final picked = await showDialog<String>(context: context, builder: (_) => _SellerPickerDialog(advisors: advisors, selectedId: id ?? 'admin'));
        if (picked == null || !mounted) return;
        setState(() {
          _selectedSellerId = picked;
          _selectedSellerName = picked == 'admin' ? 'Administrador' : (advisors.where((a) => a.id == picked).firstOrNull?.name ?? 'Asesor');
          // Si cambia de asesor, el tipo de venta (oficina/calle) se vuelve a elegir
          if (picked != id) _saleZone = null;
        });
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Asesor / Vendedor',
          prefixIcon: Icon(Icons.badge),
          suffixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
        ),
        child: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  /// Letras y números que el OCR confunde se comparan por igual (O/0, I/1, S/5, B/8…).
  static String _lookalike(String s) => s
      .toUpperCase()
      .replaceAll(RegExp(r'[^0-9A-Z]'), '')
      .replaceAll(RegExp(r'[OQD]'), '0')
      .replaceAll(RegExp(r'[IL]'), '1')
      .replaceAll('Z', '2')
      .replaceAll('S', '5')
      .replaceAll('B', '8');

  List<String> get _readReferences => ((_proofRead?['references'] as List?) ?? []).map((e) => '$e').toList();

  /// null = no se puede validar (comprobante ilegible o aún sin leer); true = coincide; false = no coincide.
  bool? get _referenceMatchesProof {
    if (_proofRead == null || _proofRead!['readable'] != true) return null;
    final typed = _lookalike(_approvalController.text);
    if (typed.length < 4) return null;
    return _readReferences.map(_lookalike).contains(typed);
  }

  /// Reads the proof on the server and fills the approval number when it is still empty (it can be edited; it is validated again).
  Future<void> _readProof(String dataUri) async {
    setState(() {
      _readingProof = true;
      _proofRead = null;
      _referenceMismatchConfirmed = false;
    });
    try {
      final read = await context.read<TicketViewModel>().readTransferProof(dataUri);
      if (!mounted || _soporteBase64 != dataUri) return;
      setState(() => _proofRead = read);
      if (read['readable'] == true && _readReferences.isNotEmpty && _approvalController.text.trim().isEmpty) {
        setState(() {
          _approvalController.text = _readReferences.first;
          _approvalCheckedKey = null;
          _approvalDuplicateConfirmed = false;
        });
        _checkApproval();
      }
    } catch (_) {
      // Sin lectura automática el usuario sigue escribiendo la referencia (el servidor igual la valida al guardar)
    } finally {
      if (mounted) setState(() => _readingProof = false);
    }
  }

  /// Looks for the approval number in other payments. Returns true when it is free or the user
  /// chose to continue anyway; false when they cancel to correct it or the check could not run.
  Future<bool> _checkApproval() async {
    final text = _approvalController.text.trim();
    final key = approvalKey(text);
    if (key.length < 3) return false;
    // Una transferencia puede pagar varias boletas: la revisión depende también del valor del abono y del valor leído del comprobante
    final amount = double.tryParse(_amountController.text) ?? 0;
    final proofAmounts = ((_proofRead?['amounts'] as List?) ?? []).whereType<num>().map((e) => e.toDouble()).toList();
    final proofAmount = proofAmounts.isEmpty ? 0.0 : proofAmounts.reduce((a, b) => a > b ? a : b);
    final sig = '$key|${amount.round()}|${proofAmount.round()}';
    if (key == _approvalCheckedKey && sig == _approvalCheckedSig) return true;
    if (_checkingApproval) return false;
    setState(() => _checkingApproval = true);
    try {
      final check = await context
          .read<TicketViewModel>()
          .checkTransferApproval(widget.ticket.raffleId, text, ticketId: widget.ticket.id, amount: amount, proofAmount: proofAmount);
      final matches = (check['matches'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
      final blocked = check['blocked'] == true;
      if (!mounted) return false;
      setState(() => _checkingApproval = false);
      if (matches.isEmpty) {
        setState(() {
          _approvalCheckedSig = sig;
          _approvalCheckedKey = key;
          _approvalDuplicateConfirmed = false;
          _approvalBlockedKey = null;
        });
        return true;
      }
      final proceed = await showApprovalMatchesDialog(context, text, matches, blocked: blocked, blockReason: '${check['blockReason'] ?? ''}');
      if (!mounted) return false;
      setState(() {
        _approvalCheckedSig = proceed && !blocked ? sig : null;
        _approvalCheckedKey = proceed && !blocked ? key : null;
        _approvalDuplicateConfirmed = proceed && !blocked;
        _approvalBlockedKey = blocked ? key : null;
        _approvalBlockedReason = blocked ? '${check['blockReason'] ?? ''}' : '';
      });
      if (!proceed || blocked) {
        // Back to the field so the user can correct the number
        _approvalController.selection = TextSelection(baseOffset: 0, extentOffset: _approvalController.text.length);
        _approvalFocus.requestFocus();
      }
      if (proceed && !blocked && '${check['note'] ?? ''}'.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 8), content: Text('${check['note']}')));
      }
      return proceed && !blocked;
    } catch (e) {
      if (mounted) {
        setState(() => _checkingApproval = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppTheme.dangerRose, content: Text('No se pudo verificar el número de aprobación: $e')),
        );
      }
      return false;
    }
  }

  Widget _transferAccountField() {
    final accounts = _transferAccounts;
    if (accounts.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Esta rifa no tiene cuentas configuradas. El administrador puede agregarlas en la configuración de la rifa '
            '(Cuentas para transferencias).',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _cuentaDestinoController,
            decoration: const InputDecoration(
              labelText: 'Cuenta de destino (opcional)',
              hintText: 'Ej. Nequi 3001234567',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              border: OutlineInputBorder(),
            ),
          ),
        ],
      );
    }
    final selected =
        accounts.any((a) => a.id == _transferAccountId) ? _transferAccountId : (accounts.length == 1 ? accounts.first.id : null);
    _transferAccountId = selected;

    void copyAccountsText() {
      final buffer = StringBuffer();
      buffer.writeln('🏦 *CUENTAS PARA TRANSFERENCIA - ${widget.raffleTitle ?? "RIFA"}*');
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: selected,
          decoration: const InputDecoration(
            labelText: 'Cuenta destino *',
            helperText: 'Cuenta de la rifa a la que llegó el dinero',
            prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            border: OutlineInputBorder(),
          ),
          items: [
            for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _transferAccountId = v),
          validator: (v) => v == null ? 'Seleccione la cuenta' : null,
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: copyAccountsText,
            icon: const Icon(Icons.copy_rounded, size: 14),
            label: const Text('Copiar cuentas para enviar por chat', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  void _showReceiptDialog(BuildContext context, Abono abono) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.receipt_long, color: AppTheme.primaryBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Soporte de Transferencia - \$${NumberFormat.currency(symbol: '', decimalDigits: 0).format(abono.amount)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (abono.cuentaDestino != null && abono.cuentaDestino!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Cuenta/Destino: ${abono.cuentaDestino}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              if (abono.soporteUrl != null || abono.soporteWebViewUrl != null)
                Container(
                  constraints: const BoxConstraints(maxHeight: 400),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InteractiveViewer(
                    child: Image.network(
                      abono.soporteUrl ?? abono.soporteWebViewUrl!,
                      fit: BoxFit.contain,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                      errorBuilder: (ctx, err, stack) {
                        return Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.broken_image, size: 48, color: Colors.grey),
                              const SizedBox(height: 8),
                              const Text('No se pudo cargar la imagen del soporte desde Google Drive.'),
                              if (abono.soporteWebViewUrl != null)
                                TextButton(
                                  onPressed: () => launchUrl(Uri.parse(abono.soporteWebViewUrl!), mode: LaunchMode.externalApplication),
                                  child: const Text('Abrir en Google Drive'),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (abono.soporteWebViewUrl != null || abono.soporteUrl != null)
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Abrir Enlace Web'),
              onPressed: () {
                final url = abono.soporteWebViewUrl ?? abono.soporteUrl;
                if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  /// After saving: shows what was stored and asks whether to send the receipt by WhatsApp.
  Future<bool> _askSendReceipt(Ticket saved) async {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final statusColor = AppTheme.getStatusColor(saved.status);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppTheme.secondaryEmerald, size: 44),
        title: Text(saved.totalPaid > 0 ? 'Pago registrado' : 'Boleta apartada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Boleta N° ${saved.displayNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            Text('Comprador: ${saved.buyerName.isNotEmpty ? saved.buyerName : 'Sin nombre'}'),
            Text('Pagado: ${currency.format(saved.totalPaid)} de ${currency.format(saved.price)}'),
            if (saved.balancePending > 0) Text('Saldo pendiente: ${currency.format(saved.balancePending)}'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: statusColor.withValues(alpha: 0.5)),
              ),
              child: Text(AppTheme.getStatusLabel(saved.status),
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const SizedBox(height: 12),
            Text(
              saved.buyerPhone.isNotEmpty
                  ? '¿Desea enviarle el comprobante por WhatsApp al ${saved.buyerPhone}?'
                  : 'El comprador no tiene celular registrado: WhatsApp se abrirá para elegir el contacto.',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cerrar')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded, color: Colors.white),
            label: const Text('Enviar comprobante por WhatsApp', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// True when the form has a payment or a new buyer that is not saved yet.
  bool _hasUnsavedSale(double amount) =>
      amount > 0 || (widget.ticket.status == 'DISPONIBLE' && _buyerNameController.text.trim().isNotEmpty);

  Future<bool> _confirmSaveBeforeReceipt(double amount) async {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.save_outlined, color: AppTheme.primaryBlue, size: 36),
        title: const Text('Este pago no está guardado'),
        content: Text(
          amount > 0
              ? 'Hay un pago de ${currency.format(amount)} escrito pero sin registrar. El comprobante solo se envía con lo que '
                  'está guardado; si no, el cliente recibiría un comprobante de una venta que no existe.'
              : 'Los datos del comprador están escritos pero sin guardar. El comprobante solo se envía con lo que está guardado.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded),
            label: const Text('Guardar y enviar'),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Sends the receipt of [ticket] as saved on the server (status, payments and verification code).
  Future<void> _sendReceipt(Ticket ticket) async {
    final name = ticket.buyerName.isNotEmpty ? ticket.buyerName : 'Pendiente';
    final phone = ticket.buyerPhone;
    final raffleVM = Provider.of<RaffleViewModel>(context, listen: false);
    final raffleMatches = raffleVM.raffles.where((r) => r.id == widget.ticket.raffleId);
    String localReceipt() => WhatsAppHelper.buildTicketReceipt(
          ticket: ticket,
          raffle: raffleMatches.isNotEmpty ? raffleMatches.first : null,
          raffleTitle: widget.raffleTitle ?? 'RIFA',
          buyerName: name,
          buyerPhone: phone,
          totalPaid: ticket.totalPaid,
          status: ticket.status,
        );

    // The company's message for this situation (apartada / abono / pagada), filled by the server
    String text;
    try {
      text = (await context.read<TicketViewModel>().fetchWhatsAppMessage(ticket.id))['message']?.toString() ?? '';
      if (text.isEmpty) text = localReceipt();
    } catch (_) {
      text = localReceipt();
    }

    Clipboard.setData(ClipboardData(text: text));

    if (phone.isNotEmpty) {
      bool launched = await WhatsAppHelper.sendWhatsAppMessage(phone: phone, message: text);
      if (launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppTheme.secondaryEmerald,
            content: Text('✓ Abriendo WhatsApp con el mensaje del comprador...'),
          ),
        );
        return;
      }
    }

    // No phone (or WhatsApp did not open): show the message to copy it or pick the contact
    if (mounted) await WhatsAppHelper.showShareMessageDialog(context, text);
  }

  Widget _cashStateLabel(Abono ab) {
    const labels = {
      'POR_VALIDAR': ('Transferencia por validar en caja', Colors.orange),
      'VALIDADA': ('✓ Transferencia validada en caja', Colors.green),
      'RECHAZADA': ('✗ Transferencia rechazada en caja', Colors.red),
      'EN_PODER_ASESOR': ('Efectivo en poder del asesor', Colors.orange),
      'EN_ENTREGA': ('Efectivo en entrega del asesor (por confirmar)', Colors.blue),
      'RECIBIDO': ('✓ Efectivo recibido en caja', Colors.green),
    };
    final (text, color) = labels[ab.cashState] ?? (ab.cashState, Colors.grey);
    return Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.shade800));
  }

  Future<void> _validateTransfer(Abono abono) async {
    final authVM = context.read<AuthViewModel>();
    if (!authVM.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solo los administradores pueden validar transferencias bancarias.')),
      );
      return;
    }
    final err = await context.read<CashViewModel>().verifyTransfer(
          widget.ticket.id,
          abono.id,
          'validar',
          raffleId: widget.ticket.raffleId,
        );
    if (err == null && mounted) {
      await context.read<TicketViewModel>().loadTickets(raffleId: widget.ticket.raffleId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.secondaryEmerald,
          content: Text('✓ Transferencia validada en caja y notificada al cliente por WhatsApp.'),
        ),
      );
      Navigator.of(context).pop();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppTheme.dangerRose, content: Text('Error: $err')),
      );
    }
  }

  Future<void> _rejectTransfer(Abono abono) async {
    final reason = await askReason(
      context,
      'Rechazar transferencia bancaria',
      hint: 'Ej: no llegó a la cuenta o comprobante ilegible',
    );
    if (reason == null || !mounted) return;
    final err = await context.read<CashViewModel>().verifyTransfer(
          widget.ticket.id,
          abono.id,
          'rechazar',
          note: reason,
          raffleId: widget.ticket.raffleId,
        );
    if (err == null && mounted) {
      await context.read<TicketViewModel>().loadTickets(raffleId: widget.ticket.raffleId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.dangerRose,
          content: Text('Transferencia rechazada y notificada por WhatsApp.'),
        ),
      );
      Navigator.of(context).pop();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppTheme.dangerRose, content: Text('Error: $err')),
      );
    }
  }

  Future<void> _showDistributeSurplusDialog(Abono pt, double surplus, NumberFormat currency) async {
    final currentTicketPrice = widget.ticket.price > 0 ? widget.ticket.price : 150000.0;
    final assignToCurrentCtrl = TextEditingController(text: currentTicketPrice.toStringAsFixed(0));
    final extraNumberCtrl = TextEditingController();
    final extraAmountCtrl = TextEditingController(text: surplus.toStringAsFixed(0));
    final justificationCtrl = TextEditingController();

    List<Map<String, dynamic>> distributions = [];
    double remaining = surplus;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            void recalcRemaining() {
              final curVal = double.tryParse(assignToCurrentCtrl.text) ?? 0.0;
              final sumDist = distributions.fold<double>(0.0, (s, d) => s + ((d['amount'] as num?)?.toDouble() ?? 0.0));
              remaining = pt.amount - curVal - sumDist;
              setDlgState(() {});
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.call_split, color: Colors.deepPurple),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Distribuir Transferencia con Excedente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.deepPurple.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('💵 Comprobante #${pt.approvalNumber ?? ""}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('• Total Transferido: ${currency.format(pt.amount)}', style: const TextStyle(fontSize: 13)),
                            Text('• Valor Boleta #${widget.ticket.displayNumber}: ${currency.format(currentTicketPrice)}', style: const TextStyle(fontSize: 13)),
                            const Divider(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Excedente por Distribuir:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text(
                                  currency.format(remaining),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: remaining == 0 ? Colors.green : (remaining < 0 ? Colors.red : Colors.deepPurple),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: assignToCurrentCtrl,
                        decoration: InputDecoration(
                          labelText: 'Monto a Asignar a la Boleta Actual (#${widget.ticket.displayNumber})',
                          prefixIcon: const Icon(Icons.confirmation_number_outlined),
                          border: const OutlineInputBorder(),
                          helperText: 'Por defecto cubre el 100% de esta boleta (${currency.format(currentTicketPrice)}).',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => recalcRemaining(),
                      ),
                      const SizedBox(height: 16),
                      const Text('Asignar Excedente a Otras Boletas / Números:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: extraNumberCtrl,
                              decoration: const InputDecoration(
                                labelText: 'N° Boleta / Cifras',
                                hintText: 'Ej: 3567',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: extraAmountCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Monto (\$ COP)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                            onPressed: () {
                              final numStr = extraNumberCtrl.text.trim();
                              final amt = double.tryParse(extraAmountCtrl.text) ?? 0.0;
                              if (numStr.isEmpty || amt <= 0) return;
                              distributions.add({'opportunity': numStr, 'amount': amt});
                              extraNumberCtrl.clear();
                              recalcRemaining();
                              if (remaining > 0) {
                                extraAmountCtrl.text = remaining.toStringAsFixed(0);
                              } else {
                                extraAmountCtrl.clear();
                              }
                            },
                            child: const Text('+ Asignar'),
                          ),
                        ],
                      ),
                      if (distributions.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (int idx = 0; idx < distributions.length; idx++)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.arrow_right, size: 18, color: Colors.deepPurple),
                                      Expanded(
                                        child: Text(
                                          'Boleta / Oportunidad #${distributions[idx]['opportunity']} ➔ ${currency.format(distributions[idx]['amount'])}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                        onPressed: () {
                                          distributions.removeAt(idx);
                                          recalcRemaining();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: justificationCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Observación / Justificación del Excedente (Opcional)',
                          hintText: 'Ej: Saldo a favor acordado con el cliente para el siguiente sorteo',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryEmerald, foregroundColor: Colors.white),
                  onPressed: () async {
                    final curVal = double.tryParse(assignToCurrentCtrl.text) ?? 0.0;
                    if (curVal <= 0) return;
                    try {
                      final res = await ApiService().distributeTransferSurplus(
                        widget.ticket.id,
                        pt.id,
                        currentTicketAmount: curVal,
                        distributions: distributions,
                        justification: justificationCtrl.text.trim(),
                      );
                      if (mounted) {
                        Navigator.pop(ctx);
                        Navigator.pop(context);
                        await context.read<TicketViewModel>().loadTickets(raffleId: widget.ticket.raffleId);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppTheme.secondaryEmerald,
                            content: Text(res['message']?.toString() ?? '✓ Transferencia distribuida con éxito.'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(backgroundColor: AppTheme.dangerRose, content: Text('Error: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('APLICAR DISTRIBUCIÓN'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Voids one payment (e.g. saved twice) after asking for the reason; it stays in the history.
  Future<void> _confirmVoidAbono(Abono abono, NumberFormat currency) async {
    final reasonCtrl = TextEditingController(text: 'Abono registrado dos veces por error');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('¿Anular este abono?'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${currency.format(abono.amount)} — ${abono.sellerName} — ${abono.date.split('T')[0]}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Dejará de sumar al total abonado. Quedará en el historial como abono anulado.', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 10),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Observación (obligatoria) *', helperText: 'Mínimo 10 caracteres.'),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose),
              onPressed: reasonCtrl.text.trim().length >= 10 ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Anular abono'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final ticketVM = Provider.of<TicketViewModel>(context, listen: false);
    final error = await ticketVM.voidAbono(widget.ticket.id, abono.id, reasonCtrl.text.trim(), raffleId: widget.ticket.raffleId);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppTheme.dangerRose, content: Text(error)));
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: AppTheme.secondaryEmerald, content: Text('Abono de ${currency.format(abono.amount)} anulado.')),
    );
  }

  /// Asks for the reason and voids the sale; the previous sale stays in the ticket history.
  Future<void> _confirmVoid(NumberFormat currency) async {
    final reasonCtrl = TextEditingController();
    final t = widget.ticket;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final valid = reasonCtrl.text.trim().length >= 10;
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.block, color: AppTheme.dangerRose),
                SizedBox(width: 10),
                Expanded(child: Text('Anular venta', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Boleta N° ${t.displayNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                    Text('Comprador: ${t.buyerName.isNotEmpty ? t.buyerName : "—"}${t.buyerPhone.isNotEmpty ? " (${t.buyerPhone})" : ""}'),
                    Text('Asesor: ${t.advisorName.isNotEmpty ? t.advisorName : "—"}'),
                    const SizedBox(height: 10),
                    const Text(
                      'La boleta quedará DISPONIBLE para venderla de nuevo. La venta anulada se conserva en el '
                      'historial de la boleta con su observación.',
                      style: TextStyle(fontSize: 12, height: 1.35),
                    ),
                    if (t.totalPaid > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.accentAmber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.accentAmber.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          '⚠️ Esta boleta tiene ${currency.format(t.totalPaid)} abonados'
                          '${t.confirmedByAdmin ? " y confirmados en caja" : ""}. Al anular, ese valor deja de contar en '
                          'caja y comisiones. Indique en la observación qué pasa con ese dinero (devuelto, pasa a otra boleta...).',
                          style: const TextStyle(fontSize: 12, height: 1.35),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonCtrl,
                      maxLines: 3,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Observación (obligatoria) *',
                        hintText: 'Ej: El asesor registró la venta en el número equivocado; era el 39.',
                        helperText: 'Mínimo 10 caracteres.',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose),
                onPressed: valid ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Anular venta'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !mounted) return;

    final ticketVM = Provider.of<TicketViewModel>(context, listen: false);
    final error = await ticketVM.voidTicket(t.id, reasonCtrl.text.trim(), raffleId: t.raffleId);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppTheme.dangerRose, content: Text(error)));
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.secondaryEmerald,
        content: Text('Venta de la boleta N° ${t.displayNumber} anulada. Quedó disponible y el historial se conservó.'),
      ),
    );
  }

  /// Libera el número apartado (fiado) mientras no tenga abonos: queda disponible para venderlo de nuevo.
  Future<void> _confirmRelease() async {
    final t = widget.ticket;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.lock_open, color: AppTheme.dangerRose),
          SizedBox(width: 10),
          Expanded(child: Text('Liberar este número', style: TextStyle(fontWeight: FontWeight.bold))),
        ]),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Boleta N° ${t.displayNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 6),
                Text('Apartada por: ${t.buyerName.isNotEmpty ? t.buyerName : "—"}${t.buyerPhone.isNotEmpty ? " (${t.buyerPhone})" : ""}'),
                Text('Asesor: ${t.advisorName.isNotEmpty ? t.advisorName : "—"}'),
                const SizedBox(height: 10),
                Row(children: [
                  Chip(label: const Text('APARTADA / FIADA'), backgroundColor: Colors.purple.withValues(alpha: 0.12)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward)),
                  Chip(label: const Text('DISPONIBLE'), backgroundColor: AppTheme.secondaryEmerald.withValues(alpha: 0.18)),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'Sin abonos: el total de la boleta sigue pendiente. Al liberarla quedará DISPONIBLE y cualquiera podrá apartarla o venderla de nuevo.',
                  style: TextStyle(fontSize: 12.5, height: 1.35),
                ),
                const SizedBox(height: 6),
                const Text(
                  'El histórico se conserva: quién la apartó, quién la liberó y cuándo quedan guardados en el historial de la boleta.',
                  style: TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // Segunda confirmación
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Está seguro?'),
        content: Text('Va a liberar la boleta N° ${t.displayNumber}. Quedará DISPONIBLE para venderla de nuevo. Esta acción queda registrada en el historial.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, volver')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, liberar número'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final error = await Provider.of<TicketViewModel>(context, listen: false).releaseTicket(t.id, raffleId: t.raffleId);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppTheme.dangerRose, content: Text(error)));
      return;
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: AppTheme.secondaryEmerald, content: Text('Número ${t.displayNumber} liberado: quedó disponible.')),
    );
  }

  Widget _buildAnnulmentsHistory(NumberFormat currency) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.dangerRose.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dangerRose.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, size: 18, color: AppTheme.dangerRose),
              const SizedBox(width: 6),
              Text('Historial de anulaciones (${widget.ticket.annulments.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          for (final a in widget.ticket.annulments.reversed) ...[
            const Divider(height: 16),
            Text(
              '${_formatDateTime(a.date)} • Anuló: ${a.by}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text('Motivo: ${a.reason}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 2),
            Text(
              'Venta anulada: ${a.previousBuyerName.isNotEmpty ? a.previousBuyerName : "—"}'
              '${a.previousBuyerPhone.isNotEmpty ? " (${a.previousBuyerPhone})" : ""}'
              ' • Asesor: ${a.previousAdvisorName.isNotEmpty ? a.previousAdvisorName : "—"}'
              '${a.previousSaleChannel.isNotEmpty ? " • ${a.previousSaleChannel}" : ""}'
              ' • Abonado: ${currency.format(a.previousTotalPaid)}',
              style: TextStyle(fontSize: 11.5, color: Colors.grey[700]),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDateTime(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    return d == null ? iso : DateFormat('dd/MM/yyyy hh:mm a').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final advisorVM = Provider.of<AdvisorViewModel>(context);
    final authVM = Provider.of<AuthViewModel>(context);

    if (authVM.isAsesor && authVM.activeAdvisor != null) {
      _selectedSellerId ??= authVM.activeAdvisor!.id;
      _selectedSellerName ??= authVM.activeAdvisor!.name;
    } else if (authVM.isIndependent) {
      _selectedSellerId ??= authVM.activeAdvisor?.id ?? 'ind_${authVM.currentUserName}';
      _selectedSellerName ??= authVM.currentUserName;
    }

    double amt = double.tryParse(_amountController.text) ?? 0;
    bool isDisponible = widget.ticket.status == 'DISPONIBLE';
    bool isApartada = widget.ticket.status == 'RESERVADA';
    bool isCompletePayment = amt > 0 && amt >= widget.ticket.balancePending;

    String buttonLabel;
    IconData buttonIcon;
    Color buttonColor;
    String defaultNoteText;
    String snackbarSuccessText;

    if (amt > 0) {
      if (isCompletePayment) {
        buttonLabel = 'COMPLETAR PAGO TOTAL (${currency.format(amt)})';
        buttonIcon = Icons.check_circle_outline;
        buttonColor = AppTheme.secondaryEmerald;
        defaultNoteText = 'Pago Total Registrado';
        snackbarSuccessText = 'Pago total registrado con éxito. Boleta PAGADA.';
      } else {
        buttonLabel = 'REGISTRAR ABONO DE ${currency.format(amt)}';
        buttonIcon = Icons.payments_outlined;
        buttonColor = AppTheme.secondaryEmerald;
        defaultNoteText = 'Abono Registrado';
        snackbarSuccessText = 'Abono de ${currency.format(amt)} registrado con éxito';
      }
    } else {
      if (isDisponible) {
        buttonLabel = 'APARTAR / FIAR BOLETA (\$0 ABONO)';
        buttonIcon = Icons.bookmark_add_outlined;
        buttonColor = Colors.purple;
        defaultNoteText = 'Boleta Apartada / Fiada';
        snackbarSuccessText = 'Boleta apartada exitosamente';
      } else if (isApartada) {
        buttonLabel = 'GUARDAR / ACTUALIZAR DATOS DE APARTADO';
        buttonIcon = Icons.save_outlined;
        buttonColor = Colors.indigo;
        defaultNoteText = 'Actualización de datos de apartado';
        snackbarSuccessText = 'Datos de apartado actualizados';
      } else {
        buttonLabel = 'ACTUALIZAR DATOS / NOTA';
        buttonIcon = Icons.edit_note;
        buttonColor = AppTheme.accentAmber;
        defaultNoteText = 'Actualización de nota de boleta';
        snackbarSuccessText = 'Datos actualizados con éxito';
      }
    }

    /// Validates and registers the sale / payment. Returns true when it was saved.
    Future<bool> saveSale() async {
      if (!_formKey.currentState!.validate()) return false;
      final newSellerId = authVM.isAsesor
          ? authVM.activeAdvisor?.id
          : (authVM.isIndependent
              ? (authVM.activeAdvisor?.id ?? 'ind_${authVM.currentUserName}')
              : (_selectedSellerId ?? 'admin'));
      final isChangingSeller = (widget.ticket.status != 'DISPONIBLE') && (newSellerId != null && newSellerId != widget.ticket.advisorId);
      // Asesor integral: cada venta debe indicar si fue en oficina o en calle
      final sellerAdvisor = (authVM.isAsesor ? authVM.activeAdvisor : advisorVM.advisors.where((a) => a.id == newSellerId).firstOrNull);
      if (sellerAdvisor != null && sellerAdvisor.isIntegral && _saleZone == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.red, content: Text('⚠️ Indique si la venta es en OFICINA (no comisiona) o en CALLE (comisiona).')),
        );
        return false;
      }

      if (isChangingSeller && _noteController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('⚠️ Debe ingresar una Nota/Observación obligatoria explicando por qué cambia el asesor de esta boleta.'),
          ),
        );
        return false;
      }

      // Transfers: the approval number must be checked (or confirmed as repeated) first
      final isTransfer = _metodoPago == 'transferencia' && amt > 0;
      if (isTransfer && _soporteBase64 == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('⚠️ El soporte (foto o captura del comprobante) es obligatorio en las transferencias.'),
          ),
        );
        return false;
      }
      if (isTransfer && !await _checkApproval()) return false;
      if (!context.mounted) return false;

      final ticketVM = Provider.of<TicketViewModel>(context, listen: false);
      setState(() => _saving = true);
      bool success = await ticketVM.addAbono(
        widget.ticket.id,
        {
          'requestId': _requestId,
          'expectedStatus': widget.ticket.status,
          'amount': amt,
          'buyerName': _buyerNameController.text.trim(),
          'buyerPhone': _buyerPhoneController.text.trim(),
          'buyerDocument': _buyerDocumentController.text.trim(),
          'buyerEmail': _buyerEmailController.text.trim(),
          'buyerCity': _buyerCityController.text.trim(),
          if (_saleChannel != null) 'saleChannel': _saleChannel,
          if (_saleZone != null) 'saleZone': _saleZone,
          'sellerId': newSellerId,
          'sellerName': authVM.isAsesor
              ? authVM.activeAdvisor?.name
              : (authVM.isIndependent ? authVM.currentUserName : (_selectedSellerName ?? 'Administrador')),
          'note': _noteController.text.trim().isNotEmpty
              ? _noteController.text.trim()
              : (widget.ticket.balancePending == 0 ? 'Actualización de datos del comprador' : defaultNoteText),
          'metodoPago': isTransfer ? 'transferencia' : 'efectivo',
          if (isTransfer) ...{
            'transferDate': ColombiaTime.toDay(_transferDate!),
            'approvalNumber': _approvalController.text.trim(),
            'originBank': _originBankController.text.trim(),
            if (_transferAccountId != null) 'transferAccountId': _transferAccountId,
            'cuentaDestino': _cuentaDestinoController.text.trim(),
            'allowDuplicateApproval': _approvalDuplicateConfirmed,
            'allowDuplicateSupport': _supportDuplicateConfirmed,
            'allowReferenceMismatch': _referenceMismatchConfirmed,
            if (_soporteBase64 != null) 'soporteImageBase64': _soporteBase64,
          },
        },
        raffleId: widget.ticket.raffleId,
      );
      if (!mounted) return false;
      setState(() => _saving = false);
      if (!success && ticketVM.lastErrorCode == 'REFERENCE_MISMATCH' && ticketVM.lastErrorData != null) {
        // La referencia escrita no aparece en el comprobante: corregirla o confirmar que es correcta (queda para revisión)
        final read = ((ticketVM.lastErrorData!['read'] as List?) ?? []).map((e) => '$e').toList();
        final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.rule, color: Colors.red, size: 40),
            title: const Text('La referencia no coincide'),
            content: Text(
              'Usted escribió "${_approvalController.text.trim()}" pero en el comprobante ${read.isEmpty ? 'no encontré esa referencia' : 'leí: ${read.take(3).join(', ')}'}.\n\n'
              'Corríjala para que sea la misma del comprobante. Si está seguro de que es correcta (por ejemplo, el comprobante se ve borroso), '
              'puede continuar y el pago quedará marcado para que el administrador lo revise.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Corregir')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
                child: const Text('Es correcta, continuar'),
              ),
            ],
          ),
        );
        if (!mounted) return false;
        if (proceed == true) {
          _referenceMismatchConfirmed = true;
          return saveSale();
        }
        _approvalFocus.requestFocus();
        return false;
      }
      if (!success && ticketVM.lastErrorCode == 'DUPLICATE_SUPPORT' && ticketVM.lastErrorData != null) {
        // The same proof image was used before: the user decides whether it is one transfer paying several tickets
        final proceed = await showSupportMatchesDialog(context, ticketVM.lastErrorData!);
        if (!mounted) return false;
        if (proceed) {
          _supportDuplicateConfirmed = true;
          return saveSale();
        }
        return false;
      }
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.dangerRose,
            content: Text(ticketVM.lastError ?? 'No se pudo guardar. Intente de nuevo.'),
          ),
        );
        return false;
      }
      _requestId = _newRequestId();
      return true;
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 550,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BOLETA N° ${widget.ticket.displayNumber}',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        StatusBadge(status: widget.ticket.status),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              const Divider(height: 24),

              for (final pt in widget.ticket.abonos.where((a) => a.isTransfer && a.cashState == 'POR_VALIDAR'))
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.amber.shade800, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'TRANSFERENCIA POR VALIDAR EN CAJA',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('• Valor Transferido: ${currency.format(pt.amount)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      if (pt.amount > (widget.ticket.price > 0 ? widget.ticket.price : 150000.0)) ...[
                        Text(
                          '  (Excedente a favor: ${currency.format(pt.amount - (widget.ticket.price > 0 ? widget.ticket.price : 150000.0))})',
                          style: TextStyle(fontSize: 12, color: Colors.amber.shade900, fontWeight: FontWeight.bold),
                        ),
                        if (authVM.isAdmin) ...[
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.deepPurple,
                              side: const BorderSide(color: Colors.deepPurple, width: 1.5),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            icon: const Icon(Icons.call_split, size: 16),
                            label: const Text(
                              '🔀 Distribuir Excedente en Otras Boletas / Justificar',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _showDistributeSurplusDialog(
                              pt,
                              pt.amount - (widget.ticket.price > 0 ? widget.ticket.price : 150000.0),
                              currency,
                            ),
                          ),
                        ],
                      ],
                      if ((pt.approvalNumber ?? '').isNotEmpty)
                        Text('• Comprobante No.: ${pt.approvalNumber}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      if ((pt.originBank ?? '').isNotEmpty)
                        Text('• Medio / Banco de Origen: ${pt.originBank}', style: const TextStyle(fontSize: 13)),
                      if (pt.soporteWebViewUrl != null || pt.soporteUrl != null) ...[
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.receipt_long, size: 16),
                          label: const Text('Ver Soporte / Comprobante'),
                          onPressed: () => showSoporte(
                            context,
                            driveId: pt.soporteDriveId,
                            url: pt.soporteUrl,
                            webViewUrl: pt.soporteWebViewUrl,
                            title: 'Comprobante #${pt.approvalNumber ?? ""}',
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (authVM.isAdmin)
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.secondaryEmerald,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(Icons.check_circle_outline, size: 18),
                                label: const Text('LEGALIZAR EN CAJA (CONFIRMAR EN BANCO)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                onPressed: () => _validateTransfer(pt),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade300),
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                              ),
                              icon: const Icon(Icons.cancel_outlined, size: 18),
                              label: const Text('RECHAZAR', style: TextStyle(fontSize: 12)),
                              onPressed: () => _rejectTransfer(pt),
                            ),
                          ],
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.hourglass_top, size: 16, color: Colors.orange.shade800),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Transferencia reportada: pendiente de legalizar por el Administrador en Caja.',
                                  style: TextStyle(fontSize: 11.5, color: Colors.orange.shade900, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              const Text('Números de Oportunidad (Boleta):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.ticket.numbers
                    .map((num) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.1),
                            border: Border.all(color: AppTheme.primaryBlue),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            num,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 16),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _infoTile('Precio Boleta', currency.format(widget.ticket.price), Colors.blueGrey),
                  _infoTile('Monto Pagado', currency.format(widget.ticket.totalPaid), AppTheme.secondaryEmerald),
                  _infoTile('Saldo Pendiente', currency.format((widget.ticket.price - widget.ticket.totalPaid).clamp(0, double.infinity)), AppTheme.dangerRose),
                ],
              ),
              // Apartada (fiada) sin ningún abono: se puede liberar el número (administrador o el asesor que la apartó)
              if (widget.ticket.status == 'RESERVADA' &&
                  widget.ticket.totalPaid <= 0 &&
                  widget.ticket.abonos.isEmpty &&
                  (authVM.isAdmin || (authVM.isAsesor && authVM.activeAdvisor?.id == widget.ticket.advisorId))) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _confirmRelease,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Liberar número'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.dangerRose,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '👤 Datos del Comprador:',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _buyerNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del Comprador *',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingrese nombre' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _buyerPhoneController,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono / WhatsApp (opcional)',
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _buyerDocumentController,
                      decoration: const InputDecoration(
                        labelText: 'Cédula / NIT (Facturación DIAN)',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.text,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]')), LengthLimitingTextInputFormatter(20)],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _buyerEmailController,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico (Facturación / DIAN)',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _buyerCityController,
                      decoration: const InputDecoration(
                        labelText: 'Ciudad y País (ej: San Martín, Meta)',
                        prefixIcon: Icon(Icons.location_city_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _saleChannel,
                      decoration: InputDecoration(
                        labelText: widget.ticket.status == 'DISPONIBLE' ? 'Medio de venta / contacto *' : 'Medio de venta / contacto',
                        prefixIcon: const Icon(Icons.campaign_outlined),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        // Active channels from the SuperAdmin's master list (plus this ticket's current one)
                        for (final channel
                            in context.watch<SaleChannelViewModel>().channels.where((c) => c.active || c.name == _saleChannel))
                          DropdownMenuItem(
                            value: channel.name,
                            child: Row(
                              children: [
                                Icon(SaleChannels.iconFor(channel.icon), size: 18, color: SaleChannels.colorFrom(channel.color)),
                                const SizedBox(width: 8),
                                Text(channel.name),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _saleChannel = v),
                      // Required for new sales (older sold tickets may not have it), but never blocks a sale
                      // when the channel list could not be loaded
                      validator: (v) => (widget.ticket.status == 'DISPONIBLE' &&
                              v == null &&
                              context.read<SaleChannelViewModel>().activeChannels.isNotEmpty)
                          ? 'Seleccione cómo se contactó o vendió'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    if (authVM.isAsesor || authVM.isIndependent)
                      TextFormField(
                        initialValue: authVM.isIndependent
                            ? '${authVM.currentUserName} (Vendedor Independiente)'
                            : '${authVM.currentUserName} (${authVM.currentUserCode})',
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Asesor / Vendedor (Asignado Automáticamente)',
                          prefixIcon: Icon(Icons.badge),
                          border: OutlineInputBorder(),
                          filled: true,
                        ),
                      )
                    else
                      _sellerField(advisorVM.advisors),
                    // Tipo de venta: solo para el asesor integral (punto = oficina y calle = calle se fijan solos)
                    Builder(builder: (context) {
                      final sellerAdv = authVM.isAsesor
                          ? authVM.activeAdvisor
                          : advisorVM.advisors.where((a) => a.id == _selectedSellerId).firstOrNull;
                      if (sellerAdv == null || !sellerAdv.isIntegral) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Tipo de venta *', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _saleZone == null ? Colors.red.shade700 : null)),
                          const SizedBox(height: 6),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            ChoiceChip(
                              label: const Text('🏢 Venta en oficina (no comisiona)'),
                              selected: _saleZone == 'OFICINA',
                              onSelected: (_) => setState(() => _saleZone = 'OFICINA'),
                            ),
                            ChoiceChip(
                              label: const Text('🛣️ Venta en calle (comisiona)'),
                              selected: _saleZone == 'CALLE',
                              onSelected: (_) => setState(() => _saleZone = 'CALLE'),
                            ),
                          ]),
                        ]),
                      );
                    }),
                    const SizedBox(height: 12),
                    if (widget.ticket.balancePending > 0) ...[
                      Text(
                        isDisponible
                            ? 'Apartar o Registrar Pago'
                            : isApartada
                                ? 'Boleta Apartada - Registrar Abono / Pago'
                                : 'Boleta con Abonos - Registrar Nuevo Abono',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Builder(
                        builder: (context) {
                          final amountField = TextFormField(
                            controller: _amountController,
                            decoration: InputDecoration(
                              labelText: 'Monto a Abonar (\$) *',
                              helperText: isDisponible
                                  ? 'Ingrese \$0 para registrar como Apartada / Fiada'
                                  : isApartada
                                      ? 'Boleta ya está Apartada. Ingrese monto > \$0 para abonar'
                                      : 'Boleta ya tiene abonos. Ingrese el monto del nuevo abono',
                              prefixIcon: const Icon(Icons.attach_money),
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            onChanged: (_) => setState(() {}),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Ingrese monto (0 para apartar/guardar)';
                              double? val = double.tryParse(v);
                              if (val == null || val < 0) return 'Monto inválido';
                              if (val > widget.ticket.balancePending) return 'Excede el saldo pendiente';
                              return null;
                            },
                          );
                          final pending = widget.ticket.balancePending;
                          final pendingText = NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(pending);
                          // One tap fills the whole pending balance (no typing for full payments)
                          void fillFull() => setState(() => _amountController.text = pending.round().toString());
                          final buttonStyle = OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            side: BorderSide(color: AppTheme.secondaryEmerald.withValues(alpha: 0.6)),
                            foregroundColor: AppTheme.secondaryEmerald,
                          );
                          if (MediaQuery.of(context).size.width < 600) {
                            // Phones: full-width button under the field, so the field keeps its width
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                amountField,
                                const SizedBox(height: 6),
                                OutlinedButton.icon(
                                  onPressed: pending > 0 ? fillFull : null,
                                  icon: const Icon(Icons.done_all, size: 18),
                                  label: Text('Pago completo ($pendingText)'),
                                  style: buttonStyle,
                                ),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: amountField),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Tooltip(
                                  message: 'Registrar el saldo completo: $pendingText',
                                  child: OutlinedButton.icon(
                                    onPressed: pending > 0 ? fillFull : null,
                                    icon: const Icon(Icons.done_all, size: 18),
                                    label: const Text('Pago\ncompleto',
                                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.1)),
                                    style: buttonStyle,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      const Text('Método de Pago:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        showSelectedIcon: false, // keeps "Transferencia" on one line on phones
                        segments: [
                          ButtonSegment<String>(
                            value: 'efectivo',
                            label: const Text('Efectivo'),
                            icon: isNarrowScreen(context) ? null : const Icon(Icons.payments_outlined),
                          ),
                          ButtonSegment<String>(
                            value: 'transferencia',
                            label: const Text('Transferencia'),
                            // Phones: text only, so "Transferencia" fits on one line
                            icon: isNarrowScreen(context) ? null : const Icon(Icons.account_balance_outlined),
                          ),
                        ],
                        selected: {_metodoPago},
                        onSelectionChanged: (val) {
                          setState(() {
                            _metodoPago = val.first;
                          });
                        },
                      ),
                      if (_metodoPago == 'transferencia' && amt <= 0) ...[
                        const SizedBox(height: 8),
                        Text('Ingrese el monto para registrar los datos de la transferencia.',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                      if (_metodoPago == 'transferencia' && amt > 0) ...[
                        const SizedBox(height: 12),
                        _transferAccountField(),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _transferDateController,
                          readOnly: true,
                          onTap: _pickTransferDate,
                          decoration: const InputDecoration(
                            labelText: 'Fecha de la transferencia *',
                            helperText: 'Máximo 15 días atrás',
                            helperMaxLines: 2,
                            prefixIcon: Icon(Icons.event),
                            suffixIcon: Icon(Icons.edit_calendar_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: _validateTransferDate,
                        ),
                        const SizedBox(height: 10),
                        BankField(
                          controller: _originBankController,
                          label: 'Banco origen *',
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Indique el banco' : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _approvalController,
                          focusNode: _approvalFocus,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: 'N° de aprobación *',
                            helperMaxLines: 2,
                            prefixIcon: const Icon(Icons.confirmation_number_outlined),
                            border: const OutlineInputBorder(),
                            helperText: _approvalBlockedKey != null && _approvalBlockedKey == approvalKey(_approvalController.text)
                                ? 'No se puede usar: $_approvalBlockedReason'
                                : _approvalDuplicateConfirmed && _approvalCheckedKey == approvalKey(_approvalController.text)
                                    ? 'Número repetido: usted decidió continuar'
                                    : _referenceMatchesProof == true
                                        ? '✓ Coincide con el comprobante'
                                        : _referenceMatchesProof == false
                                            ? '✗ No coincide con el comprobante (leí: ${_readReferences.take(2).join(', ')}). Corríjala.'
                                            : 'Se verifica que no esté registrado y que sea la del comprobante',
                            helperStyle: TextStyle(
                                color: _approvalBlockedKey != null && _approvalBlockedKey == approvalKey(_approvalController.text)
                                    ? Colors.red.shade800
                                    : _referenceMatchesProof == false
                                        ? Colors.red.shade700
                                        : _referenceMatchesProof == true
                                            ? AppTheme.secondaryEmerald
                                            : (_approvalDuplicateConfirmed && _approvalCheckedKey == approvalKey(_approvalController.text)
                                                ? Colors.orange.shade900
                                                : null)),
                            suffixIcon: _checkingApproval
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                  )
                                : _approvalCheckedKey != null && _approvalCheckedKey == approvalKey(_approvalController.text)
                                    ? (_approvalDuplicateConfirmed
                                        ? Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800)
                                        : const Icon(Icons.verified, color: AppTheme.secondaryEmerald))
                                    : null,
                          ),
                          onChanged: (_) => setState(() => _referenceMismatchConfirmed = false),
                          onFieldSubmitted: (_) => _checkApproval(),
                          validator: (v) => approvalKey(v ?? '').length < 3 ? 'Ingrese el número de aprobación' : null,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _uploadingSoporte
                                    ? null
                                    : () async {
                                        try {
                                          // El botón sigue activo mientras el selector está abierto (en iPhone puede no avisar al cancelar)
                                          final picked = await pickImageBase64(maxSide: 1600);
                                          if (picked != null) {
                                            if (mounted) setState(() => _uploadingSoporte = true);
                                            final compressed = compressImageDataUri(picked, maxSide: 1600);
                                            setState(() {
                                              _soporteBase64 = compressed;
                                              _supportDuplicateConfirmed = false;
                                            });
                                            _readProof(compressed);
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(backgroundColor: Colors.red, content: Text('Error al seleccionar la imagen: $e')),
                                            );
                                          }
                                        } finally {
                                          if (mounted) setState(() => _uploadingSoporte = false);
                                        }
                                      },
                                icon: _uploadingSoporte
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.attach_file),
                                label: Text(
                                    _soporteBase64 != null ? '✓ Soporte adjunto (Cambiar)' : 'Adjuntar soporte de pago * (obligatorio)'),
                              ),
                            ),
                            if (_soporteBase64 != null)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: 'Quitar soporte adjunto',
                                onPressed: () => setState(() {
                                  _soporteBase64 = null;
                                  _proofRead = null;
                                }),
                              ),
                          ],
                        ),
                        if (_readingProof)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Row(children: [
                              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                              SizedBox(width: 8),
                              Text('Leyendo el comprobante…', style: TextStyle(fontSize: 12.5)),
                            ]),
                          )
                        else if (_proofRead != null && _proofRead!['available'] == true)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (_proofRead!['readable'] == true ? AppTheme.secondaryEmerald : Colors.grey).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: _proofRead!['readable'] == true
                                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    const Text('🔎 Leído del comprobante', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                    const SizedBox(height: 4),
                                    if (_readReferences.isNotEmpty)
                                      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                        const Text('Referencia:', style: TextStyle(fontSize: 12.5)),
                                        for (final ref in _readReferences.take(3))
                                          ActionChip(
                                            label: Text(ref, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                            visualDensity: VisualDensity.compact,
                                            tooltip: 'Usar esta referencia',
                                            onPressed: () => setState(() {
                                              _approvalController.text = ref;
                                              _approvalCheckedKey = null;
                                              _approvalDuplicateConfirmed = false;
                                              _referenceMismatchConfirmed = false;
                                              _approvalBlockedKey = null;
                                            }),
                                          ),
                                      ])
                                    else
                                      const Text('No encontré una referencia clara: verifíquela a mano.', style: TextStyle(fontSize: 12.5)),
                                    if (((_proofRead!['amounts'] as List?) ?? []).isNotEmpty)
                                      Text('Valor en el comprobante: ${((_proofRead!['amounts'] as List).take(2)).map((a) => NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(a)).join(' / ')}',
                                          style: const TextStyle(fontSize: 12.5)),
                                    if ('${_proofRead!['bank'] ?? ''}'.isNotEmpty) Text('Banco: ${_proofRead!['bank']}', style: const TextStyle(fontSize: 12.5)),
                                  ])
                                : const Text('No pude leer el comprobante (imagen borrosa o con poca luz). Escriba la referencia a mano: el administrador la revisará.',
                                    style: TextStyle(fontSize: 12.5)),
                          ),
                        const SizedBox(height: 6),
                      ],
                    ] else ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.secondaryEmerald.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle, color: AppTheme.secondaryEmerald),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Esta boleta ya se encuentra pagada en su totalidad.',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    TextFormField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: 'Observaciones / Nota',
                        prefixIcon: Icon(Icons.notes),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                if (!await saveSale() || !mounted) return;
                                // Saved: offer the receipt right away, built from what the server stored
                                final saved = context.read<TicketViewModel>().tickets.where((t) => t.id == widget.ticket.id).firstOrNull;
                                if (saved != null && saved.status != 'DISPONIBLE') {
                                  final send = await _askSendReceipt(saved);
                                  if (!mounted) return;
                                  if (send) _sendReceipt(saved);
                                }
                                if (!mounted) return;
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(widget.ticket.balancePending == 0
                                        ? '✓ Datos del comprador actualizados correctamente.'
                                        : snackbarSuccessText),
                                  ),
                                );
                              },
                        icon: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(widget.ticket.balancePending == 0 ? Icons.save_outlined : buttonIcon),
                        label: Text(_saving
                            ? 'GUARDANDO...'
                            : (widget.ticket.balancePending == 0 ? 'GUARDAR / ACTUALIZAR DATOS DEL COMPRADOR' : buttonLabel)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.ticket.balancePending == 0 ? AppTheme.primaryBlue : buttonColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (widget.ticket.abonos.isNotEmpty) ...[
                const Text('Historial de Abonos:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.ticket.abonos.length,
                  itemBuilder: (context, i) {
                    final ab = widget.ticket.abonos[i];
                    final isTransfer = ab.metodoPago == 'transferencia';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          isTransfer ? Icons.account_balance : Icons.payments_outlined,
                          color: isTransfer ? Colors.deepPurple : AppTheme.secondaryEmerald,
                        ),
                        title: Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('${currency.format(ab.amount)} - ${ab.sellerName}'),
                            if (ab.amount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isTransfer ? Colors.deepPurple.shade50 : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: isTransfer ? Colors.deepPurple.shade200 : Colors.green.shade200),
                                ),
                                child: Text(
                                  isTransfer ? 'TRANSFERENCIA' : 'EFECTIVO',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isTransfer ? Colors.deepPurple : Colors.green.shade800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${ab.note.isNotEmpty ? ab.note : "Abono"} • ${ab.date.split('T')[0]}'),
                            if (ab.cuentaDestino != null && ab.cuentaDestino!.isNotEmpty)
                              Text('Cuenta: ${ab.cuentaDestino}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            if (isTransfer && (ab.approvalNumber ?? '').isNotEmpty)
                              Text(
                                'Aprobación ${ab.approvalNumber} • ${ab.originBank ?? ''} • ${ColombiaTime.format(ab.transferDate)}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            if (ab.amount > 0) _cashStateLabel(ab),
                            if (ab.duplicateApprovalConfirmed)
                              Text('⚠ Aprobación repetida, confirmada al registrar',
                                  style: TextStyle(fontSize: 11, color: Colors.orange.shade900, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (ab.soporteUrl != null || ab.soporteWebViewUrl != null)
                              IconButton(
                                icon: const Icon(Icons.image_search, color: AppTheme.primaryBlue),
                                tooltip: 'Ver Soporte (Google Drive)',
                                onPressed: () => showSoporte(
                                  context,
                                  driveId: ab.soporteDriveId,
                                  url: ab.soporteUrl,
                                  webViewUrl: ab.soporteWebViewUrl,
                                  title: 'Soporte de transferencia • ${currency.format(ab.amount)}',
                                ),
                              ),
                            // Reconciled payments are locked: voiding them would break the cash records
                            if (authVM.isAdmin && ab.amount > 0 && ab.voidBlocker != null)
                              Tooltip(
                                message: '${ab.voidBlocker}: no se puede anular',
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.lock_outline, color: Colors.grey),
                                ),
                              )
                            else if (authVM.isAdmin && ab.amount > 0)
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: AppTheme.dangerRose),
                                tooltip: 'Anular este abono (por ejemplo, si quedó repetido)',
                                onPressed: () => _confirmVoidAbono(ab, currency),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
              if (widget.ticket.voidedAbonos.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Abonos anulados (${widget.ticket.voidedAbonos.length}):',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                for (final v in widget.ticket.voidedAbonos)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${currency.format(v.amount)} (${v.sellerName}, ${v.date.split('T')[0]}) — anulado por ${v.voidedBy} '
                      'el ${_formatDateTime(v.voidedAt)}: ${v.voidReason}',
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.grey[600], decoration: TextDecoration.lineThrough, decorationColor: Colors.grey),
                    ),
                  ),
              ],
              if (widget.ticket.annulments.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildAnnulmentsHistory(currency),
              ],
              if (authVM.isAdmin && widget.ticket.status != 'DISPONIBLE' && widget.ticket.abonos.any((a) => a.voidBlocker != null)) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_outline, color: Colors.grey, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'La venta tiene pagos conciliados en caja (o en una entrega pendiente): no se puede anular.',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (authVM.isAdmin && widget.ticket.status != 'DISPONIBLE') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmVoid(currency),
                    icon: const Icon(Icons.block, color: AppTheme.dangerRose),
                    label: const Text('Anular venta de esta boleta', style: TextStyle(color: AppTheme.dangerRose)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.dangerRose.withValues(alpha: 0.6)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
              // Reserved or partially paid: remind the buyer what is owed (from the saved ticket)
              if (WhatsAppHelper.canRemind(widget.ticket)) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => WhatsAppHelper.sendPaymentReminder(
                      ticket: widget.ticket,
                      raffle: context.read<RaffleViewModel>().raffles.where((r) => r.id == widget.ticket.raffleId).firstOrNull,
                      raffleTitle: widget.raffleTitle ?? 'RIFA',
                      context: context,
                    ),
                    icon: const Icon(Icons.notifications_active_outlined, color: Color(0xFF128C7E)),
                    label: Text(
                      'Recordar pago por WhatsApp (debe ${currency.format(widget.ticket.balancePending)})',
                      style: const TextStyle(color: Color(0xFF128C7E), fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF25D366), width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Flex(
                direction: isNarrowScreen(context) ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: isNarrowScreen(context) ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
                children: [
                  ResponsiveFlexChild(
                    expand: !isNarrowScreen(context),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => TicketPrintDialog(
                            ticket: widget.ticket,
                            raffleTitle: widget.raffleTitle ?? "GRAN RIFA",
                          ),
                        );
                      },
                      icon: const Icon(Icons.print),
                      label: const Text('Imprimir Boleta'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10, height: 12),
                  ResponsiveFlexChild(
                    expand: !isNarrowScreen(context),
                    child: ElevatedButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              // A receipt is only sent for what is saved: a payment typed but not saved
                              // would reach the buyer as paid while the sale does not exist
                              if (!_hasUnsavedSale(amt)) {
                                _sendReceipt(widget.ticket);
                                return;
                              }
                              if (!await _confirmSaveBeforeReceipt(amt) || !await saveSale() || !mounted) return;
                              final saved = context.read<TicketViewModel>().tickets.where((t) => t.id == widget.ticket.id).firstOrNull;
                              // Opening WhatsApp may take a while: the saved sale closes the form right away
                              _sendReceipt(saved ?? widget.ticket);
                              if (mounted) Navigator.pop(context);
                            },
                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                      label: Text(
                        widget.ticket.balancePending > 0 ? 'Cobro por WhatsApp' : 'Enviar por WhatsApp',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoTile(String label, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}


/// Lista de asesores con buscador para elegir quién vende o reserva la boleta.
class _SellerPickerDialog extends StatefulWidget {
  final List<Advisor> advisors;
  final String selectedId;

  const _SellerPickerDialog({required this.advisors, required this.selectedId});

  @override
  State<_SellerPickerDialog> createState() => _SellerPickerDialogState();
}

class _SellerPickerDialogState extends State<_SellerPickerDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u');

  @override
  Widget build(BuildContext context) {
    final q = _norm(_search.text.trim());
    final list = widget.advisors.where((a) => q.isEmpty || _norm('${a.name} ${a.code} ${a.username} ${a.phone} ${a.email}').contains(q)).toList()
      ..sort((a, b) => _norm(a.name).compareTo(_norm(b.name)));
    return AlertDialog(
      title: const Text('Elegir asesor / vendedor', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 440,
        height: 420,
        child: Column(children: [
          TextField(
            controller: _search,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre, cédula, usuario o teléfono',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              if (q.isEmpty || _norm('venta directa administrador').contains(q))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.business),
                  title: const Text('Venta Directa (Administrador)'),
                  selected: widget.selectedId == 'admin',
                  onTap: () => Navigator.pop(context, 'admin'),
                ),
              for (final a in list)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 16, child: Text(a.name.isNotEmpty ? a.name[0].toUpperCase() : 'A')),
                  title: Text(a.name, style: TextStyle(decoration: a.isActive ? null : TextDecoration.lineThrough)),
                  subtitle: Text('${a.typeLabel} • ${a.code}${a.phone.isNotEmpty ? ' • ${a.phone}' : ''}${a.isActive ? '' : ' • INHABILITADO'}'),
                  selected: widget.selectedId == a.id,
                  onTap: () => Navigator.pop(context, a.id),
                ),
              if (list.isEmpty && q.isNotEmpty)
                Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Ningún asesor coincide con "${_search.text}".', style: TextStyle(color: Colors.grey[600])))),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
    );
  }
}
