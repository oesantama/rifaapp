import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/ui/core/widgets/stat_card.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/raffles/views/raffle_edit_dialog.dart';
import 'package:rifaapp/ui/features/winners/view_models/winner_view_model.dart';
import 'package:rifaapp/ui/features/advisors/views/commission_dashboard_view.dart';
import 'package:rifaapp/data/models/ticket.dart';

class DashboardScreen extends StatelessWidget {
  final Function(int index) onNavigateTab;

  const DashboardScreen({super.key, required this.onNavigateTab});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final authVM = Provider.of<AuthViewModel>(context);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Consumer3<RaffleViewModel, TicketViewModel, WinnerViewModel>(
      builder: (context, raffleVM, ticketVM, winnerVM, _) {
        final currentRaffle = raffleVM.selectedRaffle;

        // Determine ticket pool for calculations
        List<Ticket> targetTickets = ticketVM.tickets;
        if (authVM.isAsesor && authVM.activeAdvisor != null) {
          final adv = authVM.activeAdvisor!;
          targetTickets = targetTickets.where((t) {
            if (t.status != 'DISPONIBLE') {
              return t.advisorId == adv.id ||
                  t.advisorName.trim().toLowerCase() == adv.name.trim().toLowerCase() ||
                  (adv.code.isNotEmpty && t.advisorName.contains(adv.code));
            }
            if (adv.mode == 'ASSIGNED' && adv.assignedTicketRanges.isNotEmpty) {
              for (var range in adv.assignedTicketRanges) {
                var parts = range.split('-');
                if (parts.length == 2) {
                  int start = int.tryParse(parts[0].trim()) ?? 0;
                  int end = int.tryParse(parts[1].trim()) ?? 99999;
                  if (t.ticketNumber >= start && t.ticketNumber <= end) {
                    return true;
                  }
                }
              }
              return false;
            }
            return true;
          }).toList();
        }

        int countTotal = targetTickets.length;
        int countDisponibles = targetTickets.where((t) => t.status == 'DISPONIBLE').length;
        int countReservadas = targetTickets.where((t) => t.status == 'RESERVADA').length;
        int countAbonadas = targetTickets.where((t) => t.status == 'ABONO_PARCIAL').length;
        int countPagadas = targetTickets.where((t) => t.status == 'PAGADA' || t.status == 'CONFIRMADA').length;

        double totalCollected = targetTickets.fold(0.0, (sum, t) => sum + t.totalPaid);
        double totalConfirmed = targetTickets.where((t) => t.confirmedByAdmin).fold(0.0, (sum, t) => sum + t.totalPaid);
        double pendingTurnIn = totalCollected - totalConfirmed;

        int soldTicketsCount = targetTickets.where((t) => t.status != 'DISPONIBLE').length;
        double commissionPerTicket = currentRaffle != null
            ? (currentRaffle.commissionType == 'PORCENTAJE'
                ? (currentRaffle.ticketPrice * (currentRaffle.commissionValue / 100))
                : currentRaffle.commissionValue)
            : 0.0;
        double totalAdvisorsCommission = soldTicketsCount * commissionPerTicket;

        double progress = countTotal > 0 ? ((countPagadas + countAbonadas + countReservadas) / countTotal) : 0.0;

        return RefreshIndicator(
          onRefresh: () async {
            await raffleVM.loadRaffles();
            await ticketVM.loadTickets(raffleId: currentRaffle?.id);
            await winnerVM.loadWinners();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(isMobile ? 12 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentRaffle != null)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isMobile ? 16 : 20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                authVM.isAdmin ? 'SORTEO ACTIVO (VISTA ADMIN)' : 'MIS VENTAS (${authVM.currentUserName})',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Text(
                              '${currentRaffle.digits} Dígitos • ${currentRaffle.opportunitiesPerTicket} Números/Boleta',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          currentRaffle.title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 20 : 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          currentRaffle.description,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.stars, color: AppTheme.accentAmber, size: 20),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Precio por Boleta: ${currency.format(currentRaffle.ticketPrice)}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (authVM.isAdmin)
                              OutlinedButton.icon(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => RaffleEditDialog(raffle: currentRaffle),
                                  );
                                },
                                icon: const Icon(Icons.settings, color: Colors.white, size: 18),
                                label: const Text('Gestionar Sorteo', style: TextStyle(color: Colors.white)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white54),
                                ),
                              ),
                            ElevatedButton.icon(
                              onPressed: () => onNavigateTab(1),
                              icon: const Icon(Icons.confirmation_number),
                              label: Text(authVM.isAsesor ? 'Mis Boletas' : 'Ver Boletas'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.secondaryEmerald,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                SizedBox(height: isMobile ? 16 : 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 12.0;
                    int crossAxisCount = constraints.maxWidth > 1000 ? 3 : (constraints.maxWidth > 340 ? 2 : 1);
                    final itemWidth = (constraints.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
                    final cards = <Widget>[
                      StatCard(
                        title: authVM.isAsesor ? 'Mi Recaudo Total' : 'Total Recaudado Global',
                        value: currency.format(totalCollected),
                        subtitle: authVM.isAsesor ? 'Abonos y ventas mías' : 'Abonos y pagos de todos los asesores',
                        icon: Icons.attach_money,
                        iconColor: AppTheme.secondaryEmerald,
                      ),
                      StatCard(
                        title: authVM.isAsesor ? 'Mi Dinero Confirmado' : 'Confirmado por Admin',
                        value: currency.format(totalConfirmed),
                        subtitle: authVM.isAsesor ? 'Recibido en caja admin' : 'Dinero auditado en caja',
                        icon: Icons.verified,
                        iconColor: AppTheme.primaryBlue,
                      ),
                      StatCard(
                        title: authVM.isAsesor ? 'Mi Saldo por Entregar' : 'Pendiente Entrega Total',
                        value: currency.format(pendingTurnIn),
                        subtitle: authVM.isAsesor ? 'Por rendir al administrador' : 'En manos de asesores',
                        icon: Icons.account_balance_wallet,
                        iconColor: AppTheme.accentAmber,
                      ),
                      StatCard(
                        title: 'Valor Pagado en Premios',
                        value: currency.format(winnerVM.totalPrizesPaid),
                        subtitle: '${winnerVM.totalWinnersCount} Ganadores oficiales',
                        icon: Icons.card_giftcard,
                        iconColor: AppTheme.secondaryEmerald,
                      ),
                      StatCard(
                        title: authVM.isAsesor ? 'Mis Ganancias Generadas' : 'Comisiones Pagadas a Asesores',
                        value: currency.format(totalAdvisorsCommission),
                        subtitle: authVM.isAsesor ? 'Ganancia por mi gestión' : 'Comisiones totales liquidadas',
                        icon: Icons.workspace_premium,
                        iconColor: Colors.purple,
                      ),
                      StatCard(
                        title: 'Pozo Acumulado',
                        value: currency.format(winnerVM.totalAccumulatedAmount),
                        subtitle: '${winnerVM.accumulatedCount} Sorteos sin ganador',
                        icon: Icons.emoji_events,
                        iconColor: AppTheme.dangerRose,
                      ),
                    ];
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: cards.map((c) => SizedBox(width: itemWidth, child: c)).toList(),
                    );
                  },
                ),
                SizedBox(height: isMobile ? 16 : 24),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(isMobile ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                authVM.isAsesor ? 'Mi Avance de Ventas' : 'Avance de Ventas Global',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Text(
                              '${(progress * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 14,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          alignment: WrapAlignment.spaceAround,
                          spacing: 16,
                          runSpacing: 10,
                          children: [
                            _buildProgressLegend('Disponibles', countDisponibles, Colors.grey),
                            _buildProgressLegend('Apartadas', countReservadas, Colors.purple),
                            _buildProgressLegend('Abonadas', countAbonadas, AppTheme.accentAmber),
                            _buildProgressLegend('Pagadas', countPagadas, AppTheme.secondaryEmerald),
                            _buildProgressLegend('Total', countTotal, AppTheme.primaryDark),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: isMobile ? 16 : 24),
                Row(
                  children: [
                    if (authVM.isAdmin)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => onNavigateTab(2),
                          icon: const Icon(Icons.people),
                          label: const Text('Gestionar Asesores', textAlign: TextAlign.center),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8)),
                        ),
                      )
                    else
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => onNavigateTab(1),
                          icon: const Icon(Icons.grid_on),
                          label: const Text('Ver Mis Boletas', textAlign: TextAlign.center),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8)),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => onNavigateTab(authVM.isAdmin ? 4 : 2),
                        icon: const Icon(Icons.emoji_events),
                        label: const Text('Consultar Ganadores', textAlign: TextAlign.center),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8)),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isMobile ? 16 : 24),
                const CommissionDashboardView(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressLegend(String label, int count, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 4),
        Text('$count', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
