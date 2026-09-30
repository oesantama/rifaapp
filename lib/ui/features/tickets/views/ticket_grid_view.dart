import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/sale_channels.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/widgets/current_raffle_banner.dart';
import 'package:rifaapp/ui/core/widgets/status_badge.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';

import 'package:rifaapp/ui/features/raffles/views/raffle_edit_dialog.dart';
import 'package:rifaapp/ui/core/utils/excel_csv_helper.dart';
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

  bool _isRefreshing = false;

  /// Reloads the raffle's tickets from the server so sold / available reflect other users' sales.
  Future<void> _refreshTickets(TicketViewModel ticketVM, String? raffleId, {bool showSummary = true}) async {
    setState(() => _isRefreshing = true);
    await ticketVM.loadTickets(raffleId: raffleId);
    if (!mounted) return;
    setState(() => _isRefreshing = false);
    if (!showSummary) return;
    final sold = ticketVM.tickets.where((t) => t.status != 'DISPONIBLE').length;
    final available = ticketVM.tickets.length - sold;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Lista actualizada: $sold vendidas • $available disponibles')),
    );
  }

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

        List<Ticket> displayTickets = ticketVM.searchedTickets;
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

        // Counts per status reflect exactly what this user can see (before the status filter)
        final statusCounts = TicketViewModel.countByStatus(displayTickets);
        displayTickets = displayTickets.where((t) => TicketViewModel.matchesStatus(t, ticketVM.selectedStatusFilter)).toList()
          ..sort((a, b) => a.sortNumber.compareTo(b.sortNumber));

        return Column(
          children: [
            const CurrentRaffleBanner(),
            Container(
              padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 12 : 16),
              color: Theme.of(context).cardColor,
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 560;
                      final searchField = TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: authVM.isAsesor ? 'Buscar en mis boletas...' : 'Buscar N° boleta, número o comprador...',
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
                      );
                      final actionButtons = <Widget>[
                        IconButton.filledTonal(
                          icon: _isRefreshing
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh_rounded),
                          onPressed: _isRefreshing ? null : () => _refreshTickets(ticketVM, currentRaffle?.id),
                          tooltip: 'Actualizar lista (vendidas y disponibles)',
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
                          icon: const Icon(Icons.file_download_outlined, color: Colors.green),
                          onPressed: () {
                            final ticketsToExport = displayTickets;
                            if (ticketsToExport.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('No hay boletas disponibles para exportar.')),
                              );
                              return;
                            }
                            ExcelCsvHelper.exportTicketsToExcel(
                              ticketsToExport,
                              title: 'Boletas_${currentRaffle?.title ?? "Rifa"}',
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppTheme.secondaryEmerald,
                                content: Text('✓ Descargando ${ticketsToExport.length} boletas en Excel (.xlsx)...'),
                              ),
                            );
                          },
                          tooltip: 'Descargar Información de Boletas a Excel (.xlsx)',
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                          onPressed: () => setState(() => _isGridView = !_isGridView),
                          tooltip: _isGridView ? 'Ver Lista' : 'Ver Cuadrícula',
                        ),
                      ];
                      if (isNarrow) {
                        return Column(
                          children: [
                            searchField,
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Row(mainAxisSize: MainAxisSize.min, children: actionButtons),
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: searchField),
                          const SizedBox(width: 8),
                          ...actionButtons,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip(context, ticketVM, 'TODOS', statusCounts['TODOS'] ?? 0),
                        const SizedBox(width: 8),
                        _buildFilterChip(context, ticketVM, 'DISPONIBLE', statusCounts['DISPONIBLE'] ?? 0),
                        const SizedBox(width: 8),
                        _buildFilterChip(context, ticketVM, 'RESERVADA', statusCounts['RESERVADA'] ?? 0),
                        const SizedBox(width: 8),
                        _buildFilterChip(context, ticketVM, 'ABONO_PARCIAL', statusCounts['ABONO_PARCIAL'] ?? 0),
                        const SizedBox(width: 8),
                        _buildFilterChip(context, ticketVM, 'PAGADA', statusCounts['PAGADA'] ?? 0),
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
                                authVM.isAsesor ? 'No tienes boletas en este filtro' : 'No se encontraron boletas',
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          // Pull down to reload sold / available tickets from the server
                          onRefresh: () => _refreshTickets(ticketVM, currentRaffle?.id, showSummary: false),
                          child: _isGridView
                              ? _buildGrid(context, displayTickets, currentRaffle?.title, currency)
                              : _buildList(context, displayTickets, currentRaffle?.title, currency),
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(BuildContext context, TicketViewModel ticketVM, String status, int count) {
    bool isSelected = ticketVM.selectedStatusFilter == status;
    String label = status == 'TODOS' ? 'Todas' : AppTheme.getStatusLabel(status);

    return FilterChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      onSelected: (_) {
        ticketVM.setStatusFilter(status);
      },
      selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
      checkmarkColor: AppTheme.primaryBlue,
    );
  }

  Widget _buildGrid(BuildContext context, List<Ticket> tickets, String? raffleTitle, NumberFormat currency) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(isMobile ? 10 : 16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 186,
        crossAxisSpacing: isMobile ? 8 : 12,
        mainAxisSpacing: isMobile ? 8 : 12,
      ),
      itemCount: tickets.length,
      itemBuilder: (context, i) {
        final ticket = tickets[i];
        Color borderCol = AppTheme.getStatusColor(ticket.status);

        return Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: borderCol.withValues(alpha: 0.4), width: 1.5),
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
                    children: [
                      Expanded(
                        child: Text(
                          'N° ${ticket.displayNumber}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryBlue),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.print_outlined, size: 18),
                        padding: const EdgeInsets.all(4),
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
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      StatusBadge(status: ticket.status, isSmall: true),
                      if (ticket.saleChannel.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(child: _buildChannelChip(ticket.saleChannel)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (ticket.buyerName.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (ticket.status == 'PAGADA' || ticket.status == 'CONFIRMADA')
                            ? AppTheme.secondaryEmerald.withValues(alpha: 0.12)
                            : (ticket.status == 'ABONO_PARCIAL'
                                ? AppTheme.accentAmber.withValues(alpha: 0.15)
                                : Colors.purple.withValues(alpha: 0.12)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (ticket.status == 'PAGADA' || ticket.status == 'CONFIRMADA')
                              ? AppTheme.secondaryEmerald.withValues(alpha: 0.4)
                              : (ticket.status == 'ABONO_PARCIAL'
                                  ? AppTheme.accentAmber.withValues(alpha: 0.5)
                                  : Colors.purple.withValues(alpha: 0.3)),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_rounded,
                            size: 13,
                            color: (ticket.status == 'PAGADA' || ticket.status == 'CONFIRMADA')
                                ? AppTheme.secondaryEmerald
                                : (ticket.status == 'ABONO_PARCIAL' ? Colors.amber.shade900 : Colors.purple.shade700),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              ticket.buyerName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: (ticket.status == 'PAGADA' || ticket.status == 'CONFIRMADA')
                                    ? Colors.green.shade900
                                    : (ticket.status == 'ABONO_PARCIAL' ? Colors.amber.shade900 : Colors.purple.shade900),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const Text('Disponible para venta', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
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
                      ),
                      const SizedBox(width: 6),
                      // Who handled the ticket (hidden while nobody has taken it)
                      if (ticket.advisorName.trim().isNotEmpty)
                        Expanded(
                          child: Tooltip(
                            message: 'Asesor: ${ticket.advisorName.trim()}',
                            child: Text(
                              'Asesor: ${ticket.advisorName.trim()}',
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10.5, color: Colors.grey[700], fontWeight: FontWeight.w600),
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
      },
    );
  }

  /// Small label with how the buyer was reached (Facebook, WhatsApp, ...).
  Widget _buildChannelChip(String channel) {
    final color = SaleChannels.color(channel);
    return Tooltip(
      message: 'Medio de venta: $channel',
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Narrow cards (phones) show only the colored icon; wider ones show the name too
          if (constraints.maxWidth < 64) {
            if (constraints.maxWidth < 20) return const SizedBox.shrink();
            return Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(SaleChannels.icon(channel), size: 12, color: color),
            );
          }
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(SaleChannels.icon(channel), size: 11, color: color),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    channel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, List<Ticket> tickets, String? raffleTitle, NumberFormat currency) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 10 : 16),
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
              backgroundColor: AppTheme.getStatusColor(ticket.status).withValues(alpha: 0.2),
              child: Text(
                ticket.numbers.length == 1 ? ticket.displayNumber : '${ticket.numbers.length}',
                style: TextStyle(
                  color: AppTheme.getStatusColor(ticket.status),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            title: Text('N° ${ticket.displayNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ticket.buyerName.isNotEmpty
                  ? Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (ticket.status == 'PAGADA' || ticket.status == 'CONFIRMADA')
                                ? AppTheme.secondaryEmerald.withValues(alpha: 0.12)
                                : (ticket.status == 'ABONO_PARCIAL'
                                    ? AppTheme.accentAmber.withValues(alpha: 0.15)
                                    : Colors.purple.withValues(alpha: 0.12)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_rounded,
                                size: 13,
                                color: (ticket.status == 'PAGADA' || ticket.status == 'CONFIRMADA')
                                    ? AppTheme.secondaryEmerald
                                    : (ticket.status == 'ABONO_PARCIAL' ? Colors.amber.shade900 : Colors.purple.shade700),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                ticket.buyerName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: (ticket.status == 'PAGADA' || ticket.status == 'CONFIRMADA')
                                      ? Colors.green.shade900
                                      : (ticket.status == 'ABONO_PARCIAL' ? Colors.amber.shade900 : Colors.purple.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (ticket.buyerPhone.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '• Tel: ${ticket.buyerPhone}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                          ),
                        ]
                      ],
                    )
                  : Text(
                      'Sin Vender • Asesor: ${ticket.advisorName.isNotEmpty ? ticket.advisorName : "General"}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
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
