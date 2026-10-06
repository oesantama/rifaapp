import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/file_picker_helper.dart';
import 'package:rifaapp/ui/core/utils/image_compress.dart';
import 'package:rifaapp/ui/core/widgets/current_raffle_banner.dart';
import 'package:rifaapp/ui/features/admin_cash/view_models/cash_view_model.dart';
import 'package:rifaapp/ui/features/admin_cash/views/admin_cash_view.dart';
import 'package:rifaapp/ui/features/admin_cash/views/cash_widgets.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/ui/features/tickets/views/transfer_widgets.dart';

/// Advisor's cash: the cash he collected and still holds, reporting its delivery to the admin
/// (in cash or by a transfer with proof, one or several tickets at once) and his deliveries' status.
class AdvisorCashView extends StatefulWidget {
  const AdvisorCashView({super.key});

  @override
  State<AdvisorCashView> createState() => _AdvisorCashViewState();
}

class _AdvisorCashViewState extends State<AdvisorCashView> {
  final Set<String> _selected = {}; // abono ids

  String? get _raffleId => context.read<RaffleViewModel>().selectedRaffle?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final raffleId = _raffleId;
    await Future.wait([
      context.read<CashViewModel>().loadDeliveries(raffleId: raffleId),
      context.read<TicketViewModel>().loadTickets(raffleId: raffleId),
    ]);
    if (mounted) setState(() => _selected.clear());
  }

  Future<void> _report(List<CashPayment> chosen) async {
    final total = chosen.fold(0.0, (s, p) => s + p.abono.amount);
    final raffle = context.read<RaffleViewModel>().selectedRaffle;
    final accounts = raffle?.transferAccounts ?? const [];
    String method = 'efectivo';
    DateTime? date;
    final bankCtrl = TextEditingController();
    final approvalCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? destination = accounts.length == 1 ? accounts.first.label : null;
    final destinationCtrl = TextEditingController();
    String? proof;
    String? error;
    bool sending = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Entregar ${cashCurrency.format(total)}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${chosen.length} boleta(s): ${chosen.map((p) => p.ticket.displayNumber).join(', ')}',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'efectivo', label: Text('En efectivo'), icon: Icon(Icons.payments_outlined)),
                      ButtonSegment(value: 'transferencia', label: Text('Transferí'), icon: Icon(Icons.account_balance)),
                    ],
                    selected: {method},
                    onSelectionChanged: (v) => setD(() => method = v.first),
                  ),
                  const SizedBox(height: 12),
                  if (method == 'transferencia') ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event),
                      title: Text(date == null ? 'Fecha de la transferencia *' : 'Fecha: ${DateFormat('dd/MM/yyyy').format(date!)}'),
                      trailing: const Icon(Icons.edit_calendar),
                      onTap: () async {
                        final today = ColombiaTime.today();
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: date ?? today,
                          firstDate: today.subtract(const Duration(days: 30)),
                          lastDate: today,
                        );
                        if (picked != null) setD(() => date = picked);
                      },
                    ),
                    const SizedBox(height: 8),
                    BankField(controller: bankCtrl, label: 'Banco desde el que transfirió *'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: approvalCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'N° de aprobación *',
                        prefixIcon: Icon(Icons.confirmation_number_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (accounts.isNotEmpty)
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: destination,
                        decoration: const InputDecoration(labelText: 'Cuenta a la que transfirió', border: OutlineInputBorder()),
                        items: [
                          for (final a in accounts) DropdownMenuItem(value: a.label, child: Text(a.label, overflow: TextOverflow.ellipsis))
                        ],
                        onChanged: (v) => setD(() => destination = v),
                      )
                    else
                      TextField(
                        controller: destinationCtrl,
                        decoration: const InputDecoration(labelText: 'Cuenta a la que transfirió', border: OutlineInputBorder()),
                      ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await pickImageBase64();
                        if (picked != null) setD(() => proof = compressImageDataUri(picked, maxSide: 1600));
                      },
                      icon: Icon(proof == null ? Icons.attach_file : Icons.check_circle,
                          color: proof == null ? null : AppTheme.secondaryEmerald),
                      label: Text(proof == null ? 'Adjuntar soporte de la transferencia *' : 'Soporte adjunto (cambiar)'),
                    ),
                    const SizedBox(height: 10),
                  ] else
                    Text(
                      'Indica que le entregó el efectivo al administrador. Él lo confirmará al recibirlo.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
                    ),
                  const SizedBox(height: 10),
                  TextField(controller: noteCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: AppTheme.dangerRose, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: sending ? null : () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton.icon(
              onPressed: sending
                  ? null
                  : () async {
                      if (method == 'transferencia') {
                        if (date == null || bankCtrl.text.trim().isEmpty || approvalKey(approvalCtrl.text).length < 3) {
                          setD(() => error = 'Complete la fecha, el banco y el número de aprobación.');
                          return;
                        }
                        if (proof == null) {
                          setD(() => error = 'Adjunte el soporte de la transferencia.');
                          return;
                        }
                      }
                      setD(() {
                        sending = true;
                        error = null;
                      });
                      final result = await context.read<CashViewModel>().reportDelivery({
                        'raffleId': _raffleId,
                        'method': method,
                        'items': [
                          for (final p in chosen) {'ticketId': p.ticket.id, 'abonoId': p.abono.id}
                        ],
                        'note': noteCtrl.text.trim(),
                        if (method == 'transferencia') ...{
                          'transferDate': ColombiaTime.toDay(date!),
                          'originBank': bankCtrl.text.trim(),
                          'approvalNumber': approvalCtrl.text.trim(),
                          'destination': destination ?? destinationCtrl.text.trim(),
                          'soporteImageBase64': proof,
                        },
                      }, raffleId: _raffleId);
                      if (result != null) {
                        setD(() {
                          sending = false;
                          error = result;
                        });
                        return;
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: AppTheme.secondaryEmerald,
                            content: Text('Entrega reportada. El administrador la confirmará.'),
                          ),
                        );
                        _refresh();
                      }
                    },
              icon: sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: const Text('Reportar entrega'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthViewModel>().activeAdvisor;
    final tickets = context.watch<TicketViewModel>().tickets;
    final cashVM = context.watch<CashViewModel>();
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (me == null) return const SizedBox.shrink();

    final mine = cashPaymentsOf(tickets).where((p) => p.abono.sellerId == me.id).toList();
    final holding = mine.where((p) => p.abono.cashState == 'EN_PODER_ASESOR').toList();
    double sum(Iterable<CashPayment> l) => l.fold(0.0, (s, p) => s + p.abono.amount);
    final chosen = holding.where((p) => _selected.contains(p.abono.id)).toList();

    final kpis = [
      CashKpi(
        title: 'EN MI PODER',
        value: cashCurrency.format(sum(holding)),
        subtitle: 'Efectivo por entregar',
        color: Colors.orange.shade800,
        icon: Icons.account_balance_wallet,
      ),
      CashKpi(
        title: 'ENTREGADO, POR CONFIRMAR',
        value: cashCurrency.format(sum(mine.where((p) => p.abono.cashState == 'EN_ENTREGA'))),
        subtitle: 'Esperando al administrador',
        color: Colors.blue.shade700,
        icon: Icons.hourglass_top,
      ),
      CashKpi(
        title: 'CONCILIADO EN CAJA',
        value: cashCurrency.format(sum(mine.where((p) => p.abono.cashState == 'RECIBIDO' || p.abono.cashState == 'VALIDADA'))),
        subtitle: 'Recibido por la empresa',
        color: AppTheme.secondaryEmerald,
        icon: Icons.verified,
      ),
    ];

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: EdgeInsets.fromLTRB(isMobile ? 12 : 20, 0, isMobile ? 12 : 20, 32),
        children: [
          const CurrentRaffleBanner(),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final perRow = c.maxWidth >= 700 ? 3 : 1;
              final w = (c.maxWidth - (perRow - 1) * 10) / perRow;
              return Wrap(spacing: 10, runSpacing: 10, children: [for (final k in kpis) SizedBox(width: w, child: k)]);
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Text('Efectivo por entregar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              if (holding.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    if (_selected.length == holding.length) {
                      _selected.clear();
                    } else {
                      _selected
                        ..clear()
                        ..addAll(holding.map((p) => p.abono.id));
                    }
                  }),
                  child: Text(_selected.length == holding.length ? 'Quitar todas' : 'Seleccionar todas'),
                ),
            ],
          ),
          if (holding.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No tiene efectivo pendiente por entregar.', style: TextStyle(color: Colors.grey[600])),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final p in holding)
                    CheckboxListTile(
                      value: _selected.contains(p.abono.id),
                      onChanged: (v) => setState(() => v == true ? _selected.add(p.abono.id) : _selected.remove(p.abono.id)),
                      title: Text('Boleta N° ${p.ticket.displayNumber} • ${cashCurrency.format(p.abono.amount)}'),
                      subtitle: Text('${p.ticket.buyerName} • cobrado ${cashDate(p.abono.date)}'),
                      dense: true,
                    ),
                ],
              ),
            ),
          if (holding.isNotEmpty) ...[
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: chosen.isEmpty ? null : () => _report(chosen),
              icon: const Icon(Icons.send),
              label:
                  Text(chosen.isEmpty ? 'Seleccione las boletas que entrega' : 'Reportar entrega de ${cashCurrency.format(sum(chosen))}'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
          const SizedBox(height: 20),
          const Text('Mis entregas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          if (cashVM.deliveries.isEmpty)
            Text('Aún no ha reportado entregas.', style: TextStyle(color: Colors.grey[600]))
          else
            for (final d in cashVM.deliveries) DeliveryCard(delivery: d),
        ],
      ),
    );
  }
}
