import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/widgets/status_badge.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';

import 'package:rifaapp/ui/features/raffles/views/raffle_edit_dialog.dart';
import 'ticket_detail_dialog.dart';
import 'ticket_print_dialog.dart';
import 'import_sold_tickets_dialog.dart';
import 'raffle_poster_2d_dialog.dart';

class TicketGridView extends StatefulWidget {
  const TicketGridView({super.key});

  @override
  State<TicketGridView> createState() => _TicketGridViewState();
}

class _TicketGridViewState extends State<TicketGridView> {
  final TextEditingController _searchController = TextEditingController();
  bool _isGridView = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final authVM = Provider.of<AuthViewModel>(context);

    return Consumer3<TicketViewModel, RaffleViewModel, AdvisorViewModel>(
      builder: (context, ticketVM, raffleVM, advisorVM, _) {
        final currentRaffle = raffleVM.selectedRaffle;

        List<Ticket> displayTickets = ticketVM.tickets;
        if (authVM.isAsesor && authVM.activeAdvisor != null) {
          final adv = authVM.activeAdvisor!;
          displayTickets = displayTickets.where((t) {
            if (t.status != 'DISPONIBLE') {
              // Only see tickets sold by themselves!
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

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).cardColor,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: authVM.isAsesor
                                ? 'Buscar en mis boletas asignadas o vendidas...'
                                : 'Buscar por N° boleta, número (ej: 0001) o comprador...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      ticketVM.setSearchQuery('', raffleId: currentRaffle?.id);
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                          ),
                          onChanged: (val) {
                            ticketVM.setSearchQuery(val, raffleId: currentRaffle?.id);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (authVM.isAdmin && currentRaffle != null) ...[
                        IconButton.filledTonal(
                          icon: const Icon(Icons.settings),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => RaffleEditDialog(raffle: currentRaffle),
                          ),
                          tooltip: 'Gestionar Sorteo (Asesores, Estado, Importar)',
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.file_upload_outlined),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => ImportSoldTicketsDialog(
                              raffleId: currentRaffle.id,
                              raffleTitle: currentRaffle.title,
                            ),
                          ),
                          tooltip: 'Importar Boletas Vendidas desde Excel (.xlsx)',
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (currentRaffle != null) ...[
                        IconButton.filledTonal(
                          icon: const Icon(Icons.grid_on_rounded, color: AppTheme.accentAmber),
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => RafflePoster2dDialog(raffle: currentRaffle),
                          ),
                          tooltip: 'Plantilla / Afiche Rifa 2D (100 Números)',
                        ),
                        const SizedBox(width: 8),
                      ],
                      IconButton.filledTonal(
                        icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                        onPressed: () => setState(() => _isGridView = !_isGridView),
                        tooltip: _isGridView ? 'Ver Lista' : 'Ver Cuadrícula',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip(context, ticketVM, 'TODOS', currentRaffle?.id),
                        const SizedBox(width: 8),
                        _buildFilterChip(context, ticketVM, 'DISPONIBLE', currentRaffle?.id),
                        const SizedBox(width: 8),
                        _buildFilterChip(context, ticketVM, 'RESERVADA', currentRaffle?.id),
                        const SizedBox(width: 8),
                        _buildFilterChip(context, ticketVM, 'ABONO_PARCIAL', currentRaffle?.id),
                        const SizedBox(width: 8),
                        _buildFilterChip(context, ticketVM, 'PAGADA', currentRaffle?.id),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ticketVM.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : displayTickets.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.confirmation_number_outlined, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                authVM.isAsesor
                                    ? 'No tienes boletas en este filtro'
                                    : 'No se encontraron boletas',
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        )
                      : _isGridView
                          ? _buildGrid(context, displayTickets, currentRaffle?.title, currency)
                          : _buildList(context, displayTickets, currentRaffle?.title, currency),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(BuildContext context, TicketViewModel ticketVM, String status, String? raffleId) {
    bool isSelected = ticketVM.selectedStatusFilter == status;
    String label = status == 'TODOS' ? 'Todas' : AppTheme.getStatusLabel(status);

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        ticketVM.setStatusFilter(status, raffleId: raffleId);
      },
      selectedColor: AppTheme.primaryBlue.withOpacity(0.2),
      checkmarkColor: AppTheme.primaryBlue,
    );
  }

  Widget _buildGrid(BuildContext context, List<Ticket> tickets, String? raffleTitle, NumberFormat currency) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        childAspectRatio: 1.15,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: tickets.length,
      itemBuilder: (context, i) {
        final ticket = tickets[i];
        Color borderCol = AppTheme.getStatusColor(ticket.status);

        return Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: borderCol.withOpacity(0.4), width: 1.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => TicketDetailDialog(ticket: ticket, raffleTitle: raffleTitle),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'BOLETA #${ticket.ticketNumber}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.print_outlined, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Imprimir Boleta',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => TicketPrintDialog(
                                  ticket: ticket,
                                  raffleTitle: raffleTitle ?? 'GRAN RIFA',
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          StatusBadge(status: ticket.status, isSmall: true),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Números: ${ticket.numbers.join(', ')}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryBlue),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (ticket.buyerName.isNotEmpty)
                    Text(
                      'Comprador: ${ticket.buyerName}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    const Text('Disponible para venta', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        currency.format(ticket.price),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      if (ticket.balancePending > 0 && ticket.totalPaid > 0)
                        Text(
                          'Abonado: ${currency.format(ticket.totalPaid)}',
                          style: const TextStyle(fontSize: 10, color: AppTheme.accentAmber, fontWeight: FontWeight.bold),
                        ),
                    ],
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildList(BuildContext context, List<Ticket> tickets, String? raffleTitle, NumberFormat currency) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tickets.length,
      itemBuilder: (context, i) {
        final ticket = tickets[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => TicketDetailDialog(ticket: ticket, raffleTitle: raffleTitle),
              );
            },
            leading: CircleAvatar(
              backgroundColor: AppTheme.getStatusColor(ticket.status).withOpacity(0.2),
              child: Text(
                '#${ticket.ticketNumber}',
                style: TextStyle(
                  color: AppTheme.getStatusColor(ticket.status),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            title: Text('Números: ${ticket.numbers.join(', ')}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              ticket.buyerName.isNotEmpty
                  ? 'Comprador: ${ticket.buyerName} • Tel: ${ticket.buyerPhone}'
                  : 'Sin Vender • Asesor: ${ticket.advisorName.isNotEmpty ? ticket.advisorName : "General"}',
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusBadge(status: ticket.status, isSmall: true),
                const SizedBox(height: 4),
                Text(currency.format(ticket.price), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      },
    );
  }
}
