import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/models/cash_delivery.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/widgets/current_raffle_banner.dart';
import 'package:rifaapp/ui/features/admin_cash/view_models/cash_view_model.dart';
import 'package:rifaapp/ui/features/admin_cash/views/cash_widgets.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';

/// A ticket payment with its ticket, for the cash lists.
class CashPayment {
  final Ticket ticket;
  final Abono abono;

  const CashPayment(this.ticket, this.abono);
}

List<CashPayment> cashPaymentsOf(Iterable<Ticket> tickets) => [
      for (final t in tickets)
        for (final a in t.abonos)
          if (a.amount > 0) CashPayment(t, a),
    ];

/// Admin cash control for the current raffle:
///  - buyers' transfers: see the data and proof, validate or reject
///  - advisors' cash deliveries (cash or transfer with proof): confirm or reject
///  - cash still held by advisors (they report it from "Mi Caja"; the admin can also receive it in hand)
class AdminCashView extends StatefulWidget {
  const AdminCashView({super.key});

  @override
  State<AdminCashView> createState() => _AdminCashViewState();
}

class _AdminCashViewState extends State<AdminCashView> {
  String? _advisorId; // filter
  bool _showRejected = false;

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
  }

  Future<void> _after(String? error, String done) async {
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppTheme.dangerRose, content: Text(error)));
      return;
    }
    await context.read<TicketViewModel>().loadTickets(raffleId: _raffleId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppTheme.secondaryEmerald, content: Text(done)));
    }
  }

  bool _matchesAdvisor(String advisorId) => _advisorId == null || advisorId == _advisorId;

  @override
  Widget build(BuildContext context) {
    final tickets = context.watch<TicketViewModel>().tickets;
    final cashVM = context.watch<CashViewModel>();
    final advisors = context.watch<AdvisorViewModel>().advisors;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final payments = cashPaymentsOf(tickets);
    final transfers = payments
        .where((p) => p.abono.isTransfer && (p.abono.cashState == 'POR_VALIDAR' || (_showRejected && p.abono.cashState == 'RECHAZADA')))
        .where((p) => _matchesAdvisor(p.abono.sellerId))
        .toList();
    final withAdvisors = payments.where((p) => p.abono.cashState == 'EN_PODER_ASESOR' && _matchesAdvisor(p.abono.sellerId)).toList();
    final deliveries = cashVM.deliveries.where((d) => _matchesAdvisor(d.advisorId)).toList();
    final pendingDeliveries = deliveries.where((d) => d.isPending).toList();

    double sum(Iterable<CashPayment> list) => list.fold(0.0, (s, p) => s + p.abono.amount);
    final settledTotal = sum(payments.where((p) => p.abono.cashState == 'RECIBIDO' || p.abono.cashState == 'VALIDADA'));
    final transfersPending = payments.where((p) => p.abono.cashState == 'POR_VALIDAR');

    final kpis = [
      CashKpi(
        title: 'TRANSFERENCIAS POR VALIDAR',
        value: cashCurrency.format(sum(transfersPending)),
        subtitle: '${transfersPending.length} pago(s)',
        color: Colors.deepPurple,
        icon: Icons.account_balance,
      ),
      CashKpi(
        title: 'ENTREGAS POR CONFIRMAR',
        value: cashCurrency.format(cashVM.pendingDeliveries.fold(0.0, (s, d) => s + d.total)),
        subtitle: '${cashVM.pendingDeliveries.length} entrega(s) de asesores',
        color: Colors.blue.shade700,
        icon: Icons.move_to_inbox,
      ),
      CashKpi(
        title: 'EFECTIVO EN PODER DE ASESORES',
        value: cashCurrency.format(sum(payments.where((p) => p.abono.cashState == 'EN_PODER_ASESOR'))),
        subtitle: 'Aún no entregado',
        color: Colors.orange.shade800,
        icon: Icons.payments_outlined,
      ),
      CashKpi(
        title: 'CONCILIADO EN CAJA',
        value: cashCurrency.format(settledTotal),
        subtitle: 'Recibido y validado',
        color: AppTheme.secondaryEmerald,
        icon: Icons.verified,
      ),
    ];

    return DefaultTabController(
      length: 3,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(isMobile ? 12 : 20, 0, isMobile ? 12 : 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const CurrentRaffleBanner(),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, c) {
                      final perRow = c.maxWidth >= 900 ? 4 : 2;
                      final w = (c.maxWidth - (perRow - 1) * 10) / perRow;
                      return Wrap(spacing: 10, runSpacing: 10, children: [for (final k in kpis) SizedBox(width: w, child: k)]);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          isExpanded: true,
                          initialValue: _advisorId,
                          decoration: const InputDecoration(labelText: 'Asesor', isDense: true, border: OutlineInputBorder()),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Todos los asesores')),
                            for (final a in advisors) DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setState(() => _advisorId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Material(
              color: Theme.of(context).cardColor,
              child: TabBar(
                isScrollable: isMobile,
                tabs: [
                  Tab(text: 'Transferencias (${transfersPending.length})'),
                  Tab(text: 'Entregas (${pendingDeliveries.length})'),
                  Tab(text: 'En poder de asesores (${withAdvisors.length})'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          children: [
            _TransfersTab(
              payments: transfers,
              showRejected: _showRejected,
              onToggleRejected: (v) => setState(() => _showRejected = v),
              onValidate: (p) async => _after(
                await context.read<CashViewModel>().verifyTransfer(p.ticket.id, p.abono.id, 'validar', raffleId: _raffleId),
                'Transferencia validada.',
              ),
              onReject: (p) async {
                final reason = await askReason(context, 'Rechazar transferencia', hint: 'Ej: no llegó a la cuenta');
                if (reason == null || !mounted) return;
                _after(
                  await context
                      .read<CashViewModel>()
                      .verifyTransfer(p.ticket.id, p.abono.id, 'rechazar', note: reason, raffleId: _raffleId),
                  'Transferencia rechazada.',
                );
              },
            ),
            _DeliveriesTab(
              deliveries: deliveries,
              onConfirm: (d) async => _after(
                await context.read<CashViewModel>().reviewDelivery(d.id, 'confirmar', raffleId: _raffleId),
                'Entrega confirmada: el dinero quedó conciliado en caja.',
              ),
              onReject: (d) async {
                final reason = await askReason(context, 'Rechazar entrega de ${d.advisorName}', hint: 'Ej: el valor no coincide');
                if (reason == null || !mounted) return;
                _after(await context.read<CashViewModel>().reviewDelivery(d.id, 'rechazar', reason: reason, raffleId: _raffleId),
                    'Entrega rechazada.');
              },
            ),
            _WithAdvisorsTab(
              payments: withAdvisors,
              onReceive: (p) async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Recibir efectivo en mano'),
                    content: Text(
                      '¿Recibió ${cashCurrency.format(p.abono.amount)} de ${p.abono.sellerName} por la boleta ${p.ticket.displayNumber}? '
                      'Queda conciliado en caja y ya no se podrá anular.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, recibido')),
                    ],
                  ),
                );
                if (ok != true || !mounted) return;
                _after(await context.read<CashViewModel>().receiveCash(p.ticket.id, p.abono.id, raffleId: _raffleId), 'Efectivo recibido.');
              },
            ),
          ],
        ),
      ),
    );
  }
}

Widget _empty(String text) => ListView(children: [
      Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600]))),
      ),
    ]);

class _TransfersTab extends StatelessWidget {
  final List<CashPayment> payments;
  final bool showRejected;
  final ValueChanged<bool> onToggleRejected;
  final void Function(CashPayment) onValidate;
  final void Function(CashPayment) onReject;

  const _TransfersTab({
    required this.payments,
    required this.showRejected,
    required this.onToggleRejected,
    required this.onValidate,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          dense: true,
          title: const Text('Mostrar también las rechazadas'),
          value: showRejected,
          onChanged: onToggleRejected,
        ),
        Expanded(
          child: payments.isEmpty
              ? _empty('No hay transferencias de compradores por validar.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: payments.length,
                  itemBuilder: (context, i) {
                    final p = payments[i];
                    final a = p.abono;
                    final rejected = a.cashState == 'RECHAZADA';
                    final hasProof = a.soporteUrl != null || a.soporteWebViewUrl != null;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text('Boleta N° ${p.ticket.displayNumber}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                Text(cashCurrency.format(a.amount),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.deepPurple)),
                                if (rejected) CashChip('RECHAZADA', Colors.red.shade700),
                                if (!hasProof) CashChip('SIN SOPORTE', Colors.orange.shade800, icon: Icons.warning_amber),
                              ],
                            ),
                            const SizedBox(height: 6),
                            CashInfoLine('Comprador', p.ticket.buyerName),
                            CashInfoLine('Registró', '${a.sellerName} • ${cashDate(a.date)}'),
                            CashInfoLine('Fecha transferencia', cashDate(a.transferDate)),
                            CashInfoLine('Banco origen', a.originBank ?? ''),
                            CashInfoLine('N° aprobación', a.approvalNumber ?? ''),
                            CashInfoLine('Cuenta destino', a.cuentaDestino ?? ''),
                            if (a.duplicateApprovalConfirmed)
                              CashChip('APROBACIÓN REPETIDA (confirmada al registrar)', Colors.orange.shade800),
                            if (rejected) CashInfoLine('Motivo del rechazo', (a.verification?['note'] ?? '').toString()),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (hasProof)
                                  OutlinedButton.icon(
                                    onPressed: () => showSoporte(context,
                                        driveId: a.soporteDriveId,
                                        url: a.soporteUrl,
                                        webViewUrl: a.soporteWebViewUrl,
                                        title: 'Soporte de transferencia'),
                                    icon: const Icon(Icons.image_search, size: 18),
                                    label: const Text('Ver soporte'),
                                  ),
                                ElevatedButton.icon(
                                  onPressed: () => onValidate(p),
                                  icon: const Icon(Icons.verified, size: 18),
                                  label: const Text('Validar (llegó a la cuenta)'),
                                  style:
                                      ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryEmerald, foregroundColor: Colors.white),
                                ),
                                if (!rejected)
                                  TextButton.icon(
                                    onPressed: () => onReject(p),
                                    icon: const Icon(Icons.block, size: 18, color: AppTheme.dangerRose),
                                    label: const Text('Rechazar', style: TextStyle(color: AppTheme.dangerRose)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DeliveriesTab extends StatelessWidget {
  final List<CashDelivery> deliveries;
  final void Function(CashDelivery) onConfirm;
  final void Function(CashDelivery) onReject;

  const _DeliveriesTab({required this.deliveries, required this.onConfirm, required this.onReject});

  @override
  Widget build(BuildContext context) {
    if (deliveries.isEmpty) return _empty('Los asesores aún no han reportado entregas de dinero.\nLas reportan desde "Mi Caja" en su app.');
    final sorted = [...deliveries]
      ..sort((a, b) => (a.isPending == b.isPending) ? b.reportedAt.compareTo(a.reportedAt) : (a.isPending ? -1 : 1));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: sorted.length,
      itemBuilder: (context, i) => DeliveryCard(
        delivery: sorted[i],
        onConfirm: sorted[i].isPending ? () => onConfirm(sorted[i]) : null,
        onReject: sorted[i].isPending ? () => onReject(sorted[i]) : null,
      ),
    );
  }
}

/// A delivery with its tickets, transfer data and proof; admin actions when given.
class DeliveryCard extends StatelessWidget {
  final CashDelivery delivery;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;

  const DeliveryCard({super.key, required this.delivery, this.onConfirm, this.onReject});

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    final (statusText, statusColor) = switch (d.status) {
      'CONFIRMADA' => ('CONFIRMADA', AppTheme.secondaryEmerald),
      'RECHAZADA' => ('RECHAZADA', AppTheme.dangerRose),
      _ => ('POR CONFIRMAR', Colors.blue.shade700),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(d.advisorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(cashCurrency.format(d.total),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.primaryBlue)),
                CashChip(statusText, statusColor),
                CashChip(
                  d.isTransfer ? 'POR TRANSFERENCIA' : 'EN EFECTIVO',
                  d.isTransfer ? Colors.deepPurple : Colors.green.shade800,
                  icon: d.isTransfer ? Icons.account_balance : Icons.payments_outlined,
                ),
              ],
            ),
            const SizedBox(height: 6),
            CashInfoLine('Reportada', cashDate(d.reportedAt)),
            if (d.isTransfer) ...[
              CashInfoLine('Fecha transferencia', cashDate(d.transferDate)),
              CashInfoLine('Banco origen', d.originBank ?? ''),
              CashInfoLine('N° aprobación', d.approvalNumber ?? ''),
              CashInfoLine('Cuenta destino', d.destination ?? ''),
            ],
            CashInfoLine('Nota', d.note),
            if (!d.isPending)
              CashInfoLine(d.status == 'CONFIRMADA' ? 'Confirmó' : 'Rechazó', '${d.reviewedBy ?? ''} • ${cashDate(d.reviewedAt)}'),
            if ((d.reviewNote ?? '').isNotEmpty) CashInfoLine('Motivo', d.reviewNote!),
            const SizedBox(height: 6),
            Text('Boletas (${d.items.length}):', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
            for (final item in d.items)
              Text(
                '• N° ${((item['numbers'] as List?) ?? []).join('-')}  ${cashCurrency.format((item['amount'] as num?) ?? 0)}'
                '${(item['buyerName'] ?? '').toString().isNotEmpty ? '  — ${item['buyerName']}' : ''}'
                '${item['state'] == 'ANULADO' ? '  (pago anulado)' : ''}',
                style: const TextStyle(fontSize: 12.5),
              ),
            if (d.isTransfer || onConfirm != null) const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (d.isTransfer)
                  OutlinedButton.icon(
                    onPressed: () => showSoporte(context,
                        driveId: d.soporteDriveId, url: d.soporteUrl, webViewUrl: d.soporteWebViewUrl, title: 'Soporte de la entrega'),
                    icon: const Icon(Icons.image_search, size: 18),
                    label: const Text('Ver soporte'),
                  ),
                if (onConfirm != null)
                  ElevatedButton.icon(
                    onPressed: onConfirm,
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: Text(d.isTransfer ? 'Confirmar (llegó la transferencia)' : 'Confirmar recibido en efectivo'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryEmerald, foregroundColor: Colors.white),
                  ),
                if (onReject != null)
                  TextButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.block, size: 18, color: AppTheme.dangerRose),
                    label: const Text('Rechazar', style: TextStyle(color: AppTheme.dangerRose)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WithAdvisorsTab extends StatelessWidget {
  final List<CashPayment> payments;
  final void Function(CashPayment) onReceive;

  const _WithAdvisorsTab({required this.payments, required this.onReceive});

  @override
  Widget build(BuildContext context) {
    if (payments.isEmpty) return _empty('Ningún asesor tiene efectivo pendiente por entregar.');
    final byAdvisor = <String, List<CashPayment>>{};
    for (final p in payments) {
      byAdvisor.putIfAbsent(p.abono.sellerName, () => []).add(p);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Text(
          'Efectivo cobrado por los asesores que aún no han entregado. Ellos reportan la entrega desde "Mi Caja"; '
          'si le entregan el dinero en mano, márquelo como recibido.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
        ),
        const SizedBox(height: 10),
        for (final entry in byAdvisor.entries)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              initiallyExpanded: byAdvisor.length == 1,
              title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${entry.value.length} pago(s) • ${cashCurrency.format(entry.value.fold(0.0, (s, p) => s + p.abono.amount))}'),
              children: [
                for (final p in entry.value)
                  ListTile(
                    dense: true,
                    title: Text('Boleta N° ${p.ticket.displayNumber} • ${cashCurrency.format(p.abono.amount)}'),
                    subtitle: Text('${p.ticket.buyerName} • ${cashDate(p.abono.date)}'),
                    trailing: TextButton(onPressed: () => onReceive(p), child: const Text('Recibido en mano')),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
