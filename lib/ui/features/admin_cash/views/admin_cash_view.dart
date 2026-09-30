import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/widgets/responsive_flex_child.dart';

class AdminCashView extends StatefulWidget {
  const AdminCashView({super.key});

  @override
  State<AdminCashView> createState() => _AdminCashViewState();
}

class _AdminCashViewState extends State<AdminCashView> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedAdvisorId = 'TODOS';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Consumer3<TicketViewModel, RaffleViewModel, AdvisorViewModel>(
      builder: (context, ticketVM, raffleVM, advisorVM, _) {
        final currentRaffle = raffleVM.selectedRaffle;

        // Pending unconfirmed tickets
        List<Ticket> pendingConfirmTickets = ticketVM.tickets.where((t) => t.totalPaid > 0 && !t.confirmedByAdmin).toList();

        // Apply search filter
        String search = _searchController.text.trim().toLowerCase();
        if (search.isNotEmpty) {
          pendingConfirmTickets = pendingConfirmTickets.where((t) {
            return t.ticketNumber.toString().contains(search) ||
                t.buyerName.toLowerCase().contains(search) ||
                t.buyerPhone.contains(search) ||
                t.advisorName.toLowerCase().contains(search) ||
                t.numbers.any((n) => n.contains(search));
          }).toList();
        }

        // Apply advisor filter
        if (_selectedAdvisorId != 'TODOS') {
          pendingConfirmTickets = pendingConfirmTickets.where((t) => t.advisorId == _selectedAdvisorId).toList();
        }

        double totalFilteredPending = pendingConfirmTickets.fold(0.0, (sum, t) => sum + t.totalPaid);

        final isMobile = MediaQuery.of(context).size.width < 600;

        final pendingCard = Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.amber.shade900, Colors.amber.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.pending_actions, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'DINERO PENDIENTE POR REVISION',
                      style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                currency.format(ticketVM.totalPendingTurnIn),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                '${ticketVM.tickets.where((t) => t.totalPaid > 0 && !t.confirmedByAdmin).length} boletas por auditar en caja',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        );
        final confirmedCard = Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade800, AppTheme.secondaryEmerald],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.verified_user, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'DINERO AUDITADO Y RECIBIDO EN CAJA',
                      style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                currency.format(ticketVM.totalConfirmed),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 4),
              const Text(
                'Efectivo verificado e ingresado a la caja admin',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        );

        return RefreshIndicator(
          onRefresh: () => ticketVM.loadTickets(raffleId: currentRaffle?.id),
          child: ListView(
            padding: EdgeInsets.all(isMobile ? 12 : 20),
            children: [
              // Summary Cards Header
              if (isMobile) ...[
                pendingCard,
                const SizedBox(height: 10),
                confirmedCard,
              ] else
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: pendingCard),
                      const SizedBox(width: 14),
                      Expanded(child: confirmedCard),
                    ],
                  ),
                ),

              SizedBox(height: isMobile ? 12 : 20),

              // Search & Filter Controls Toolbar
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: EdgeInsets.all(isMobile ? 12 : 16),
                  child: Column(
                    children: [
                      Flex(
                        direction: isMobile ? Axis.vertical : Axis.horizontal,
                        crossAxisAlignment: isMobile ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
                        children: [
                          ResponsiveFlexChild(
                            expand: !isMobile,
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: isMobile
                                    ? 'Buscar boleta, comprador o asesor...'
                                    : 'Buscar por N° boleta, comprador, teléfono o asesor...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () {
                                          setState(() => _searchController.clear());
                                        },
                                      )
                                    : null,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12, height: 12),
                          SizedBox(
                            width: isMobile ? null : 220,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _selectedAdvisorId,
                              decoration: const InputDecoration(
                                labelText: 'Filtrar por Asesor',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(value: 'TODOS', child: Text('Todos los Asesores')),
                                ...advisorVM.advisors
                                    .map((adv) => DropdownMenuItem(value: adv.id, child: Text(adv.name, overflow: TextOverflow.ellipsis))),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedAdvisorId = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      if (pendingConfirmTickets.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Text(
                              'Mostrando ${pendingConfirmTickets.length} cobro(s) pendiente(s) (${currency.format(totalFilteredPending)})',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                            ElevatedButton.icon(
                              onPressed: () async {
                                bool? confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Confirmar Cobros Filtrados'),
                                    content: Text(
                                      '¿Desea marcar como CONFIRMADOS en caja todos los ${pendingConfirmTickets.length} cobros mostrados por un total de ${currency.format(totalFilteredPending)}?',
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryEmerald),
                                        child: const Text('CONFIRMAR TODOS'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  for (var t in pendingConfirmTickets) {
                                    await ticketVM.confirmTicketPayment(t.id, raffleId: currentRaffle?.id);
                                  }
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Todos los cobros seleccionados han sido confirmados en caja.')),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.done_all, size: 18),
                              label: const Text('Confirmar Todo lo Filtrado'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryBlue,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Pending Tickets List
              pendingConfirmTickets.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.verified, size: 60, color: AppTheme.secondaryEmerald),
                            const SizedBox(height: 14),
                            Text(
                              search.isNotEmpty || _selectedAdvisorId != 'TODOS'
                                  ? 'No hay cobros pendientes con esos criterios de búsqueda'
                                  : '¡Excelente! No hay cobros pendientes por confirmar en caja.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            const Text('Todo el dinero recaudado de la rifa está auditado.',
                                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: pendingConfirmTickets.length,
                      itemBuilder: (context, i) {
                        final t = pendingConfirmTickets[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: AppTheme.accentAmber.withValues(alpha: 0.3)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Builder(
                              builder: (context) {
                                final avatar = CircleAvatar(
                                  radius: 24,
                                  backgroundColor: AppTheme.accentAmber.withValues(alpha: 0.15),
                                  child: Text(
                                    t.numbers.length == 1 ? t.displayNumber : '${t.numbers.length}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentAmber, fontSize: 13),
                                  ),
                                );
                                final info = Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Text('Boleta N° ${t.displayNumber}',
                                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text('Números: ${t.numbers.join(', ')}',
                                              style: const TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Comprador: ${t.buyerName.isNotEmpty ? t.buyerName : "Sin Nombre"} • Tel: ${t.buyerPhone.isNotEmpty ? t.buyerPhone : "Sin teléfono"}',
                                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Vendedor: ${t.advisorName.isNotEmpty ? t.advisorName : "General"} • Recaudado: ${currency.format(t.totalPaid)}',
                                      style: const TextStyle(fontSize: 12, color: AppTheme.secondaryEmerald, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                );
                                final confirmButton = ElevatedButton.icon(
                                  onPressed: () async {
                                    bool ok = await ticketVM.confirmTicketPayment(t.id, raffleId: currentRaffle?.id);
                                    if (ok && context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Pago de Boleta N° ${t.displayNumber} confirmado en caja.')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.check_circle_outline, size: 18),
                                  label: const Text('Confirmar Recibido'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.secondaryEmerald,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                );
                                if (isMobile) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [avatar, const SizedBox(width: 12), Expanded(child: info)],
                                      ),
                                      const SizedBox(height: 10),
                                      confirmButton,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    avatar,
                                    const SizedBox(width: 14),
                                    Expanded(child: info),
                                    const SizedBox(width: 12),
                                    confirmButton,
                                  ],
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        );
      },
    );
  }
}
