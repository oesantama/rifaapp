import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/file_picker_helper.dart';
import 'package:rifaapp/ui/core/utils/file_saver.dart';
import 'package:rifaapp/ui/core/utils/text_search.dart';
import 'package:rifaapp/ui/core/utils/image_compress.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/widgets/current_raffle_banner.dart';
import 'package:rifaapp/ui/features/agil/views/agil_payments_view.dart';
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
  String _methodFilter = 'TODOS'; // historial: TODOS / efectivo / transferencia
  String _historySearch = ''; // historial: boleta, valor o número de aprobación
  final _historySearchCtrl = TextEditingController();
  // Gastos en efectivo del asesor por justificar con el administrador (se descuentan de lo que entrega)
  num _pendingExpenses = 0;

  String? get _raffleId => context.read<RaffleViewModel>().selectedRaffle?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _historySearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final raffleId = _raffleId;
    await Future.wait([
      context.read<CashViewModel>().loadDeliveries(raffleId: raffleId),
      context.read<TicketViewModel>().loadTickets(raffleId: raffleId),
    ]);
    if (mounted) setState(() => _selected.clear());
    await _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    final me = context.read<AuthViewModel>().activeAdvisor;
    if (me == null || !me.canRegisterExpenses) return;
    try {
      final res = await ApiService().agilExpenses();
      if (mounted) setState(() => _pendingExpenses = (res['pendingTotal'] as num?) ?? 0);
    } catch (_) {}
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
                  if (method == 'efectivo' && _pendingExpenses > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        'Se descontarán ${cashCurrency.format(_pendingExpenses)} de gastos que usted registró. '
                        'Entrega en mano: ${cashCurrency.format(total - _pendingExpenses)}.',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
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
                        try {
                          final picked = await pickImageBase64(maxSide: 1600);
                          if (picked != null) setD(() => proof = prepareProofImage(picked, maxSide: 1600));
                        } on ImageTooHeavyException catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(e.message)));
                          }
                        }
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
    final reconciled = mine.where((p) => p.abono.cashState == 'RECIBIDO' || p.abono.cashState == 'VALIDADA').toList();
    final history = mine.where((p) => (_methodFilter == 'TODOS' || (_methodFilter == 'transferencia') == p.abono.isTransfer) && _matchesHistory(p)).toList()
      ..sort((a, b) => b.abono.date.compareTo(a.abono.date));
    final canExpenses = me.canRegisterExpenses;

    final kpis = [
      CashKpi(
        title: 'EN MI PODER',
        value: cashCurrency.format(sum(holding)),
        subtitle: 'Efectivo por entregar',
        color: Colors.orange.shade800,
        icon: Icons.account_balance_wallet,
      ),
      if (canExpenses && _pendingExpenses > 0)
        CashKpi(
          title: 'A ENTREGAR (menos gastos)',
          value: cashCurrency.format(sum(holding) - _pendingExpenses),
          subtitle: 'En mi poder − ${cashCurrency.format(_pendingExpenses)} de gastos',
          color: Colors.deepPurple,
          icon: Icons.calculate_outlined,
        ),
      CashKpi(
        title: 'ENTREGADO, POR CONFIRMAR',
        value: cashCurrency.format(sum(mine.where((p) => p.abono.cashState == 'EN_ENTREGA'))),
        subtitle: 'Esperando al administrador',
        color: Colors.blue.shade700,
        icon: Icons.hourglass_top,
      ),
      CashKpi(
        title: 'TRANSFERENCIAS POR VALIDAR',
        value: cashCurrency.format(sum(mine.where((p) => p.abono.isTransfer && p.abono.cashState == 'POR_VALIDAR'))),
        subtitle: 'Esperando validación del administrador',
        color: Colors.indigo,
        icon: Icons.account_balance,
      ),
      CashKpi(
        title: 'CONCILIADO EN CAJA',
        value: cashCurrency.format(sum(reconciled)),
        // Aclara de qué es: efectivo ya recibido por la empresa y transferencias ya validadas
        subtitle: 'Efectivo ${cashCurrency.format(sum(reconciled.where((p) => !p.abono.isTransfer)))} • '
            'Transferencias ${cashCurrency.format(sum(reconciled.where((p) => p.abono.isTransfer)))}',
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
          if (canExpenses) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Text('Mis gastos en efectivo', style: TextStyle(fontWeight: FontWeight.bold)),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final saved = await showDialog<bool>(
                        context: context,
                        builder: (_) => ExpenseDialog(api: ApiService(), account: 'efectivo', label: 'Efectivo en mi poder', balance: sum(holding) - _pendingExpenses),
                      );
                      if (saved == true) {
                        await _loadExpenses();
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gasto registrado. Se descontará de lo que entregue.')));
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Registrar gasto'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await showDialog<bool>(
                        context: context,
                        builder: (_) => ExpensesListDialog(api: ApiService(), account: 'efectivo', label: 'Efectivo (mis gastos)', allowVoid: false),
                      );
                      await _loadExpenses();
                    },
                    icon: const Icon(Icons.list_alt, size: 18),
                    label: const Text('Ver mis gastos'),
                  ),
                ]),
              ),
            ),
          ],
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
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Text('Historial de mis cobros', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              Text('${history.length} pago(s)', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: 'Buscar por N° de boleta, valor o aprobación',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: _historySearch.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() { _historySearchCtrl.clear(); _historySearch = ''; })),
                  ),
                  controller: _historySearchCtrl,
                  onChanged: (v) => setState(() => _historySearch = v),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: history.isEmpty ? null : () => _exportHistory(history),
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('Excel'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.green.shade800, side: BorderSide(color: Colors.green.shade700), padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final f in const [('TODOS', 'Todos'), ('efectivo', 'Efectivo'), ('transferencia', 'Transferencias')])
                ChoiceChip(
                  label: Text(f.$2),
                  selected: _methodFilter == f.$1,
                  onSelected: (_) => setState(() => _methodFilter = f.$1),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Aún no tiene cobros registrados.', style: TextStyle(color: Colors.grey[600])),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final p in history.take(200)) ...[
                    _historyTile(p),
                    if (p != history.take(200).last) const Divider(height: 1),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Búsqueda del historial: número de boleta (cualquiera de sus oportunidades), valor (con o sin puntos) o número de aprobación.
  bool _matchesHistory(CashPayment p) {
    final q = foldText(_historySearch).replaceAll(RegExp(r'[\s.,\$]'), '');
    if (q.isEmpty) return true;
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    final approval = foldText(p.abono.approvalNumber ?? '').replaceAll(RegExp(r'[^0-9a-z]'), '');
    return p.ticket.numbers.any((n) => n.contains(q)) ||
        (digits.isNotEmpty && p.abono.amount.round().toString().contains(digits)) ||
        (approval.isNotEmpty && approval.contains(q)) ||
        p.ticket.ticketNumber.toString() == q;
  }

  /// Excel con lo que se ve en el historial (ya filtrado).
  Future<void> _exportHistory(List<CashPayment> rows) async {
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['Mis cobros'];
      excel.delete('Sheet1');
      const headers = ['Fecha', 'Boleta', 'Comprador', 'Valor', 'Método', 'Banco origen', 'Aprobación', 'Cuenta destino', 'Estado'];
      sheet.appendRow([for (final h in headers) xl.TextCellValue(h)]);
      for (final p in rows) {
        final (state, _) = _stateOf(p);
        sheet.appendRow([
          xl.TextCellValue(cashDate(p.abono.date)),
          xl.TextCellValue(p.ticket.displayNumber),
          xl.TextCellValue(p.ticket.buyerName),
          xl.DoubleCellValue(p.abono.amount),
          xl.TextCellValue(p.abono.isTransfer ? 'Transferencia' : 'Efectivo'),
          xl.TextCellValue(p.abono.isTransfer ? (p.abono.originBank ?? '') : ''),
          xl.TextCellValue(p.abono.isTransfer ? (p.abono.approvalNumber ?? '') : ''),
          xl.TextCellValue(p.abono.isTransfer ? (p.abono.cuentaDestino ?? '') : ''),
          xl.TextCellValue(state),
        ]);
      }
      final total = rows.fold<double>(0, (s, p) => s + p.abono.amount);
      sheet.appendRow([xl.TextCellValue('TOTAL'), xl.TextCellValue(''), xl.TextCellValue(''), xl.DoubleCellValue(total)]);
      final bytes = excel.save();
      if (bytes == null) throw Exception('No se pudo generar el archivo.');
      final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await saveAndDownloadBytes('mis_cobros_$day.xlsx', bytes, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Excel descargado con ${rows.length} pago(s).')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppTheme.dangerRose, content: Text('No se pudo exportar: $e')));
    }
  }

  /// Estado del pago visto por el asesor: (texto, color)
  (String, Color) _stateOf(CashPayment p) => switch (p.abono.cashState) {
        'EN_PODER_ASESOR' => ('En mi poder', Colors.orange.shade800),
        'EN_ENTREGA' => ('Entregado, por confirmar', Colors.blue.shade700),
        'RECIBIDO' => ('Recibido en caja', AppTheme.secondaryEmerald),
        'POR_VALIDAR' => ('Por validar', Colors.indigo),
        'VALIDADA' => ('Validada en caja', AppTheme.secondaryEmerald),
        'RECHAZADA' => ('Rechazada', AppTheme.dangerRose),
        _ => (p.abono.cashState, Colors.grey),
      };

  Widget _historyTile(CashPayment p) {
    final (label, color) = _stateOf(p);
    final isTransfer = p.abono.isTransfer;
    final details = <String>[
      'Boleta N° ${p.ticket.displayNumber}',
      if (p.ticket.buyerName.isNotEmpty) p.ticket.buyerName,
      cashDate(p.abono.date),
      if (isTransfer && (p.abono.originBank ?? '').isNotEmpty) p.abono.originBank!,
      if (isTransfer && (p.abono.approvalNumber ?? '').isNotEmpty) 'Aprob. ${p.abono.approvalNumber}',
    ];
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: (isTransfer ? Colors.indigo : Colors.green).withValues(alpha: 0.12),
        child: Icon(isTransfer ? Icons.account_balance : Icons.payments_outlined, size: 18, color: isTransfer ? Colors.indigo : Colors.green.shade700),
      ),
      title: Text('${cashCurrency.format(p.abono.amount)} • ${isTransfer ? 'Transferencia' : 'Efectivo'}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(details.join(' • '), style: const TextStyle(fontSize: 11.5)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
      ),
    );
  }
}
