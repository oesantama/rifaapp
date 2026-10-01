import 'package:flutter/material.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/ui/features/advisors/views/advisor_sales_breakdown.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';

class CommissionDashboardView extends StatefulWidget {
  const CommissionDashboardView({super.key});

  @override
  State<CommissionDashboardView> createState() => _CommissionDashboardViewState();
}

class _CommissionDashboardViewState extends State<CommissionDashboardView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadCommissions();
    });
  }

  void _reloadCommissions() {
    final raffleVM = Provider.of<RaffleViewModel>(context, listen: false);
    final advVM = Provider.of<AdvisorViewModel>(context, listen: false);
    advVM.loadCommissions(raffleId: raffleVM.selectedRaffle?.id);
  }

  void _showPayoutDialog(BuildContext context, {required String advisorId, required String advisorName, required double maxPending}) {
    final amountCtrl = TextEditingController(text: maxPending > 0 ? maxPending.toStringAsFixed(0) : '0');
    final noteCtrl = TextEditingController(text: advisorId == 'ALL' ? 'Liquidación masiva de comisiones' : 'Pago de comisión por ventas');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.payments_outlined, color: Colors.green, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  advisorId == 'ALL' ? 'Liquidar a TODOS los Asesores' : 'Liquidar Comisión: $advisorName',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              )
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (advisorId == 'ALL')
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      border: Border.all(color: Colors.amber.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber.shade900, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Se registrará el pago completo del saldo pendiente a cada asesor que tenga ganancias por cobrar.',
                            style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                          ),
                        )
                      ],
                    ),
                  )
                else ...[
                  Text('Saldo Pendiente por Cobrar: \$${maxPending.toStringAsFixed(0)} COP',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Monto a Pagar / Liquidar (\$ COP) *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Observación / Referencia de Pago',
                    hintText: 'Ej: Transferencia Nequi #12345',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note_alt_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('CONFIRMAR PAGO'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryEmerald),
              onPressed: () async {
                double amt = double.tryParse(amountCtrl.text.trim()) ?? maxPending;
                if (amt <= 0 && advisorId != 'ALL') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(backgroundColor: Colors.red, content: Text('Ingrese un monto válido mayor a \$0')),
                  );
                  return;
                }

                final advVM = Provider.of<AdvisorViewModel>(context, listen: false);
                final raffleVM = Provider.of<RaffleViewModel>(context, listen: false);

                bool ok = await advVM.registerPayout(
                  advisorId: advisorId,
                  amount: amt,
                  note: noteCtrl.text.trim(),
                  raffleId: raffleVM.selectedRaffle?.id,
                );

                if (ok && ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppTheme.secondaryEmerald,
                      content: Text('¡Pago de comisión registrado exitosamente!'),
                    ),
                  );
                }
              },
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final authVM = Provider.of<AuthViewModel>(context);
    final advVM = Provider.of<AdvisorViewModel>(context);
    final raffleVM = Provider.of<RaffleViewModel>(context);

    final currentRaffle = raffleVM.selectedRaffle;
    final commData = advVM.commissionsData;

    String commTypeStr = currentRaffle?.commissionType ?? 'PORCENTAJE';
    double commVal = currentRaffle?.commissionValue ?? 10.0;
    String commBadgeText = commTypeStr == 'PORCENTAJE'
        ? '${commVal.toStringAsFixed(0)}% por boleta vendida'
        : '\$${commVal.toStringAsFixed(0)} COP por boleta vendida';

    if (commData == null) {
      return const Center(child: CircularProgressIndicator());
    }

    double globalEarned = (commData['globalCommissionEarned'] as num?)?.toDouble() ?? 0.0;
    double globalPaid = (commData['globalCommissionPaid'] as num?)?.toDouble() ?? 0.0;
    double globalPending = (commData['globalPendingCommission'] as num?)?.toDouble() ?? 0.0;

    List advisorsList = commData['advisors'] as List? ?? [];
    List payoutsHistory = commData['payoutsHistory'] as List? ?? [];

    // Filter for advisor view if logged in as advisor
    Map<String, dynamic>? myAdvisorStat;
    if (authVM.isAsesor && authVM.activeAdvisor != null) {
      final advId = authVM.activeAdvisor!.id;
      final advCode = authVM.activeAdvisor!.code;
      final advName = authVM.activeAdvisor!.name.toLowerCase().trim();

      myAdvisorStat = advisorsList.firstWhere(
        (a) => a['advisorId'] == advId || a['advisorCode'] == advCode || a['advisorName'].toString().toLowerCase().trim() == advName,
        orElse: () => {
          'advisorId': advId,
          'advisorName': authVM.currentUserName,
          'totalTicketsSold': 0,
          'totalCollected': 0.0,
          'commissionEarned': 0.0,
          'commissionPaid': 0.0,
          'pendingCommission': 0.0,
        },
      );
    }

    double myEarned = 0.0;
    double myPaid = 0.0;
    double myPending = 0.0;
    int mySold = 0;

    if (myAdvisorStat != null) {
      myEarned = (myAdvisorStat['commissionEarned'] as num?)?.toDouble() ?? 0.0;
      myPaid = (myAdvisorStat['commissionPaid'] as num?)?.toDouble() ?? 0.0;
      myPending = (myAdvisorStat['pendingCommission'] as num?)?.toDouble() ?? 0.0;
      mySold = (myAdvisorStat['totalTicketsSold'] as num?)?.toInt() ?? 0;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // BANNER DEL SORTEO Y ESQUEMA DE COMISION
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: authVM.isAdmin
                    ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                    : [const Color(0xFF065F46), const Color(0xFF047857)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    authVM.isAdmin ? Icons.monetization_on_outlined : Icons.account_balance_wallet_outlined,
                    color: Colors.amber,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authVM.isAdmin ? 'DASHBOARD DE COMISIONES Y GANANCIAS (ADMIN)' : 'MI PANEL DE GANANCIAS Y LIQUIDACIONES',
                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentRaffle?.title ?? 'Sorteo Activo',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.percent, color: Colors.white70, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Esquema de Comisión Activo: $commBadgeText',
                              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: 'Actualizar Datos',
                  onPressed: _reloadCommissions,
                )
              ],
            ),
          ),

          const SizedBox(height: 16),

          // TARJETAS METRICAS PRINCIPALES
          if (authVM.isAdmin) ...[
            // VISTA ADMIN METRICS
            _metricsGrid([
              _buildMetricCard(
                title: 'Total Comisiones Ganadas',
                val: currency.format(globalEarned),
                icon: Icons.savings_outlined,
                color: AppTheme.primaryBlue,
                subtitle: 'Acumulado por ventas de asesores',
              ),
              _buildMetricCard(
                title: 'Comisiones Liquidadas',
                val: currency.format(globalPaid),
                icon: Icons.check_circle_outline,
                color: AppTheme.secondaryEmerald,
                subtitle: 'Total ya pagado a asesores',
              ),
              _buildMetricCard(
                title: 'Pendiente por Pagar',
                val: currency.format(globalPending),
                icon: Icons.pending_actions,
                color: Colors.orange.shade800,
                subtitle: 'Saldo actual a liquidar',
              ),
            ]),

            const SizedBox(height: 20),

            // BOTON ACCION GLOBAL ADMIN
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                const Text(
                  'Detalle de Ganancias por Asesor:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: globalPending > 0
                      ? () => _showPayoutDialog(context, advisorId: 'ALL', advisorName: 'Todos los Asesores', maxPending: globalPending)
                      : null,
                  icon: const Icon(Icons.payments, size: 18),
                  label: const Text('Liquidar a TODOS los Asesores'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondaryEmerald,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // TABLA DE ASESORES PARA ADMIN
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: advisorsList.length,
                separatorBuilder: (context, i) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final adv = advisorsList[i];
                  double earned = (adv['commissionEarned'] as num?)?.toDouble() ?? 0.0;
                  double paid = (adv['commissionPaid'] as num?)?.toDouble() ?? 0.0;
                  double pending = (adv['pendingCommission'] as num?)?.toDouble() ?? 0.0;
                  double collected = (adv['totalCollected'] as num?)?.toDouble() ?? 0.0;

                  final avatar = CircleAvatar(
                    radius: 20,
                    backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                    child: Text(
                      adv['advisorName'] != null && adv['advisorName'].toString().isNotEmpty ? adv['advisorName'][0].toUpperCase() : 'A',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                    ),
                  );
                  final identity = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        adv['advisorName'] ?? 'Sin Nombre',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Cédula/Código: ${adv['advisorCode'] ?? "N/A"} • Tel: ${adv['phone'] ?? "N/A"}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  );
                  final sales = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Breakdown by status in the current raffle (reserved / partial / paid = sold)
                      AdvisorSalesBreakdown(
                        sales: context.watch<TicketViewModel>().salesByAdvisor()[adv['advisorId']] ?? AdvisorSales(),
                        compact: true,
                      ),
                      const SizedBox(height: 2),
                      Text('Recaudado: ${currency.format(collected)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  );
                  final earnings = Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Ganancia: ${currency.format(earned)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.primaryBlue)),
                      Text('Pagado: ${currency.format(paid)} | Pendiente: ${currency.format(pending)}',
                          textAlign: TextAlign.end,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: pending > 0 ? Colors.red : Colors.green)),
                    ],
                  );
                  final payButton = ElevatedButton.icon(
                    onPressed: pending > 0
                        ? () => _showPayoutDialog(
                              context,
                              advisorId: adv['advisorId'],
                              advisorName: adv['advisorName'],
                              maxPending: pending,
                            )
                        : null,
                    icon: const Icon(Icons.attach_money, size: 16),
                    label: Text(pending > 0 ? 'Liquidar' : 'Al día', style: const TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pending > 0 ? Colors.orange.shade800 : Colors.grey,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  );

                  return Padding(
                    padding: const EdgeInsets.all(14),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 560) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  avatar,
                                  const SizedBox(width: 12),
                                  Expanded(child: identity),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: sales),
                                  const SizedBox(width: 8),
                                  Expanded(child: earnings),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(alignment: Alignment.centerRight, child: payButton),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            avatar,
                            const SizedBox(width: 12),
                            Expanded(flex: 3, child: identity),
                            Expanded(flex: 2, child: sales),
                            Expanded(flex: 3, child: earnings),
                            const SizedBox(width: 12),
                            payButton,
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ] else if (myAdvisorStat != null) ...[
            // VISTA ASESOR INDIVIDUAL METRICS
            _metricsGrid([
              _buildMetricCard(
                title: 'Boletas Vendidas',
                val: '$mySold',
                icon: Icons.confirmation_number_outlined,
                color: AppTheme.primaryBlue,
                subtitle: 'Ventas registradas',
              ),
              _buildMetricCard(
                title: 'Tu Ganancia Total',
                val: currency.format(myEarned),
                icon: Icons.savings_outlined,
                color: Colors.purple,
                subtitle: 'Calculado según esquema',
              ),
              _buildMetricCard(
                title: 'Ganancia Pagada / Cobrada',
                val: currency.format(myPaid),
                icon: Icons.check_circle_outline,
                color: AppTheme.secondaryEmerald,
                subtitle: 'Entregado por el administrador',
              ),
              _buildMetricCard(
                title: 'Saldo Pendiente por Cobrar',
                val: currency.format(myPending),
                icon: Icons.hourglass_top_outlined,
                color: myPending > 0 ? Colors.red : Colors.green,
                subtitle: myPending > 0 ? 'Por cobrar al administrador' : '¡Estás al día sin saldos!',
              ),
            ]),
          ],

          const SizedBox(height: 24),

          // HISTORIAL CRONOLOGICO DE LIQUIDACIONES
          const Text(
            '📜 Histórico de Liquidaciones / Pagos Recibidos:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          payoutsHistory.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text('No hay registros de liquidaciones o pagos de comisiones todavía.', style: TextStyle(color: Colors.grey)),
                  ),
                )
              : Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: payoutsHistory.length,
                    separatorBuilder: (context, i) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final pay = payoutsHistory[i];
                      double amt = (pay['amount'] as num?)?.toDouble() ?? 0.0;
                      String dateStr =
                          pay['date'] != null ? DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.parse(pay['date'])) : 'Reciente';

                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: Colors.green.withValues(alpha: 0.15),
                          child: const Icon(Icons.receipt_long, color: Colors.green, size: 20),
                        ),
                        title: Text(
                          'Pago a: ${pay['advisorName'] ?? "Asesor"}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        subtitle: Text(
                          'Fecha: $dateStr • ${pay['note'] ?? "Sin observación"}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Text(
                          currency.format(amt),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.secondaryEmerald),
                        ),
                      );
                    },
                  ),
                )
        ],
      ),
    );
  }

  /// Lays out metric cards in a single row on wide screens and two per row on phones.
  Widget _metricsGrid(List<Widget> cards) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final perRow = constraints.maxWidth >= 600 ? cards.length : 2;
        final width = (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (int i = 0; i < cards.length; i++)
              SizedBox(
                // On phones an odd last card takes the full row
                width: (perRow == 2 && i == cards.length - 1 && cards.length.isOdd) ? constraints.maxWidth : width,
                child: cards[i],
              ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String val,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              val,
              maxLines: 1,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
