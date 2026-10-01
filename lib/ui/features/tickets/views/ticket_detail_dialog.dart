import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:rifaapp/ui/core/widgets/responsive_flex_child.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/sale_channels.dart';
import 'package:rifaapp/ui/features/sale_channels/view_models/sale_channel_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/widgets/status_badge.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/core/utils/whatsapp_helper.dart';
import 'ticket_print_dialog.dart';

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
  String? _saleChannel; // how the buyer was reached
  bool _saving = false; // blocks repeated taps while the payment is being saved
  // One id per submission: if the same request reaches the server twice, it is applied once
  String _requestId = _newRequestId();

  static String _newRequestId() => '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 31)}';
  late TextEditingController _amountController;
  late TextEditingController _noteController;
  String? _selectedSellerId;
  String? _selectedSellerName;

  @override
  void initState() {
    super.initState();
    _buyerNameController = TextEditingController(text: widget.ticket.buyerName);
    _buyerPhoneController = TextEditingController(text: widget.ticket.buyerPhone);
    _saleChannel = widget.ticket.saleChannel.isNotEmpty ? widget.ticket.saleChannel : null;
    _amountController = TextEditingController(text: '0');
    _noteController = TextEditingController();
    _selectedSellerId = widget.ticket.advisorId.isNotEmpty ? widget.ticket.advisorId : null;
    _selectedSellerName = widget.ticket.advisorName;
  }

  @override
  void dispose() {
    _buyerNameController.dispose();
    _buyerPhoneController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _copyReceiptToClipboard(BuildContext context) async {

    String name = _buyerNameController.text.trim().isNotEmpty
        ? _buyerNameController.text.trim()
        : (widget.ticket.buyerName.isNotEmpty ? widget.ticket.buyerName : "Pendiente");

    String phone = _buyerPhoneController.text.trim().isNotEmpty ? _buyerPhoneController.text.trim() : widget.ticket.buyerPhone;

    double addAmt = double.tryParse(_amountController.text) ?? 0;
    double currentPaid = widget.ticket.totalPaid + addAmt;
    double pending = (widget.ticket.price - currentPaid).clamp(0, double.infinity);

    String calculatedStatus = widget.ticket.status;
    if (widget.ticket.status == 'DISPONIBLE') {
      if (pending <= 0 && currentPaid > 0) {
        calculatedStatus = 'PAGADA';
      } else if (currentPaid > 0) {
        calculatedStatus = 'ABONO_PARCIAL';
      } else if (name != 'Pendiente') {
        calculatedStatus = 'RESERVADA';
      } else {
        calculatedStatus = 'DISPONIBLE';
      }
    } else {
      if (addAmt > 0) {
        if (pending <= 0) {
          calculatedStatus = widget.ticket.confirmedByAdmin ? 'CONFIRMADA' : 'PAGADA';
        } else {
          calculatedStatus = 'ABONO_PARCIAL';
        }
      }
    }

    final raffleVM = Provider.of<RaffleViewModel>(context, listen: false);
    final raffleMatches = raffleVM.raffles.where((r) => r.id == widget.ticket.raffleId);
    final text = WhatsAppHelper.buildTicketReceipt(
      ticket: widget.ticket,
      raffle: raffleMatches.isNotEmpty ? raffleMatches.first : null,
      raffleTitle: widget.raffleTitle ?? 'RIFA',
      buyerName: name,
      buyerPhone: phone,
      totalPaid: currentPaid,
      status: calculatedStatus,
    );

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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comprobante digital copiado al portapapeles (Listo para pegar en WhatsApp)'),
        ),
      );
    }
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
                  _infoTile('Saldo Pendiente', currency.format(widget.ticket.balancePending), AppTheme.dangerRose),
                ],
              ),
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
                        labelText: 'Teléfono / WhatsApp *',
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingrese teléfono' : null,
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
                      // Required for new sales; older sold tickets may not have it recorded
                      validator: (v) => (widget.ticket.status == 'DISPONIBLE' && v == null) ? 'Seleccione cómo se contactó o vendió' : null,
                    ),
                    const SizedBox(height: 10),
                    if (authVM.isAsesor)
                      TextFormField(
                        initialValue: '${authVM.currentUserName} (${authVM.currentUserCode})',
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Asesor / Vendedor (Asignado Automáticamente)',
                          prefixIcon: Icon(Icons.badge),
                          border: OutlineInputBorder(),
                          filled: true,
                        ),
                      )
                    else
                      () {
                        final List<DropdownMenuItem<String>> sellerDropdownItems = [
                          const DropdownMenuItem<String>(
                            value: 'admin',
                            child: Text('🏢 Venta Directa (Administrador)'),
                          ),
                          ...advisorVM.advisors.map((adv) {
                            return DropdownMenuItem<String>(
                              value: adv.id,
                              child: Text('👤 ${adv.name} (${adv.code})'),
                            );
                          }),
                        ];
                        final validSellerIds = sellerDropdownItems.map((e) => e.value).toSet();
                        final currentSellerValue = validSellerIds.contains(_selectedSellerId) ? _selectedSellerId : 'admin';

                        return DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: currentSellerValue,
                          decoration: const InputDecoration(
                            labelText: 'Asesor / Vendedor',
                            prefixIcon: Icon(Icons.badge),
                            border: OutlineInputBorder(),
                          ),
                          items: sellerDropdownItems,
                          onChanged: (val) {
                            if (val == null) return;
                            setState(() {
                              _selectedSellerId = val;
                              if (val == 'admin') {
                                _selectedSellerName = 'Administrador';
                              } else {
                                final found = advisorVM.advisors.where((a) => a.id == val).firstOrNull;
                                _selectedSellerName = found?.name ?? 'Asesor';
                              }
                            });
                          },
                        );
                      }(),
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
                      TextFormField(
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
                      ),
                      const SizedBox(height: 10),
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
                                if (_formKey.currentState!.validate()) {
                                  final newSellerId = authVM.isAsesor ? authVM.activeAdvisor?.id : (_selectedSellerId ?? 'admin');
                                  final isChangingSeller = (widget.ticket.status != 'DISPONIBLE') &&
                                      (newSellerId != null && newSellerId != widget.ticket.advisorId);

                                  if (isChangingSeller && _noteController.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        backgroundColor: Colors.red,
                                        content: Text(
                                            '⚠️ Debe ingresar una Nota/Observación obligatoria explicando por qué cambia el asesor de esta boleta.'),
                                      ),
                                    );
                                    return;
                                  }

                                  final ticketVM = Provider.of<TicketViewModel>(context, listen: false);
                                  setState(() => _saving = true);
                                  bool success = await ticketVM.addAbono(
                                    widget.ticket.id,
                                    {
                                      'requestId': _requestId,
                                      'amount': amt,
                                      'buyerName': _buyerNameController.text.trim(),
                                      'buyerPhone': _buyerPhoneController.text.trim(),
                                      if (_saleChannel != null) 'saleChannel': _saleChannel,
                                      'sellerId': newSellerId,
                                      'sellerName': authVM.isAsesor ? authVM.activeAdvisor?.name : (_selectedSellerName ?? 'Administrador'),
                                      'note': _noteController.text.trim().isNotEmpty
                                          ? _noteController.text.trim()
                                          : (widget.ticket.balancePending == 0 ? 'Actualización de datos del comprador' : defaultNoteText),
                                    },
                                    raffleId: widget.ticket.raffleId,
                                  );
                                  if (!mounted) return;
                                  setState(() => _saving = false);
                                  if (!success) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: AppTheme.dangerRose,
                                        content: Text(ticketVM.lastError ?? 'No se pudo guardar. Intente de nuevo.'),
                                      ),
                                    );
                                    return;
                                  }
                                  _requestId = _newRequestId();
                                  if (success && mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(widget.ticket.balancePending == 0
                                            ? '✓ Datos del comprador actualizados correctamente.'
                                            : snackbarSuccessText),
                                      ),
                                    );
                                  }
                                }
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
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.receipt, color: AppTheme.primaryBlue),
                        title: Text('${currency.format(ab.amount)} - ${ab.sellerName}'),
                        subtitle: Text('${ab.note.isNotEmpty ? ab.note : "Abono"} • ${ab.date.split('T')[0]}'),
                        trailing: authVM.isAdmin && ab.amount > 0
                            ? IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: AppTheme.dangerRose),
                                tooltip: 'Anular este abono (por ejemplo, si quedó repetido)',
                                onPressed: () => _confirmVoidAbono(ab, currency),
                              )
                            : null,
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
              if (authVM.isAdmin && widget.ticket.status != 'DISPONIBLE') ...[
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
                      onPressed: () => _copyReceiptToClipboard(context),
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
