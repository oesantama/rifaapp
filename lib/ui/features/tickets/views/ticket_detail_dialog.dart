import 'package:flutter/material.dart';
import 'package:rifaapp/ui/core/widgets/responsive_flex_child.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/widgets/status_badge.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
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
  late TextEditingController _amountController;
  late TextEditingController _noteController;
  String? _selectedSellerId;
  String? _selectedSellerName;

  @override
  void initState() {
    super.initState();
    _buyerNameController = TextEditingController(text: widget.ticket.buyerName);
    _buyerPhoneController = TextEditingController(text: widget.ticket.buyerPhone);
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

  void _copyReceiptToClipboard(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

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

    final text = '''
🎟️ *COMPROBANTE DE BOLETA - ${widget.raffleTitle ?? "RIFA"}*
----------------------------------------
📌 *Boleta N°:* ${widget.ticket.ticketNumber}
🔢 *Números de Oportunidad:* ${widget.ticket.numbers.join(', ')}
👤 *Comprador:* $name
📱 *Celular:* $phone
💰 *Valor Boleta:* ${currency.format(widget.ticket.price)}
✅ *Total Abonado:* ${currency.format(currentPaid)}
🔴 *Saldo Pendiente:* ${currency.format(pending)}
📊 *Estado:* ${AppTheme.getStatusLabel(calculatedStatus)}
----------------------------------------
¡Gracias por tu compra y buena suerte! 🍀
''';

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Comprobante digital copiado al portapapeles (Listo para WhatsApp)')),
    );
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BOLETA N° ${widget.ticket.ticketNumber.toString().padLeft(4, '0')}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      StatusBadge(status: widget.ticket.status),
                    ],
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
              if (widget.ticket.balancePending > 0) ...[
                Text(
                  isDisponible
                      ? 'Apartar o Registrar Pago'
                      : isApartada
                          ? 'Boleta Apartada - Registrar Abono / Pago'
                          : 'Boleta con Abonos - Registrar Nuevo Abono',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
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
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _selectedSellerId,
                          decoration: const InputDecoration(
                            labelText: 'Asesor / Vendedor',
                            prefixIcon: Icon(Icons.badge),
                            border: OutlineInputBorder(),
                          ),
                          items: advisorVM.advisors.map((adv) {
                            return DropdownMenuItem(
                              value: adv.id,
                              child: Text('${adv.name} (${adv.code})'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedSellerId = val;
                              _selectedSellerName = advisorVM.advisors.firstWhere((a) => a.id == val).name;
                            });
                          },
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
                          onPressed: () async {
                            if (_formKey.currentState!.validate()) {
                              final newSellerId = authVM.isAsesor ? authVM.activeAdvisor?.id : (_selectedSellerId ?? 'admin');
                              final isChangingSeller =
                                  (widget.ticket.status != 'DISPONIBLE') && (newSellerId != null && newSellerId != widget.ticket.advisorId);

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
                              bool success = await ticketVM.addAbono(
                                widget.ticket.id,
                                {
                                  'amount': amt,
                                  'buyerName': _buyerNameController.text.trim(),
                                  'buyerPhone': _buyerPhoneController.text.trim(),
                                  'sellerId': newSellerId,
                                  'sellerName': authVM.isAsesor ? authVM.activeAdvisor?.name : (_selectedSellerName ?? 'Administrador'),
                                  'note': _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : defaultNoteText,
                                },
                                raffleId: widget.ticket.raffleId,
                              );
                              if (success && mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(snackbarSuccessText),
                                  ),
                                );
                              }
                            }
                          },
                          icon: Icon(buttonIcon),
                          label: Text(buttonLabel),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonColor,
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ] else ...[
                Container(
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
                          child:
                              Text('Esta boleta ya se encuentra pagada en su totalidad.', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
              ],
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
                      ),
                    );
                  },
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
                    child: OutlinedButton.icon(
                      onPressed: () => _copyReceiptToClipboard(context),
                      icon: const Icon(Icons.share),
                      label: const Text('Recibo WhatsApp'),
                      style: OutlinedButton.styleFrom(
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
