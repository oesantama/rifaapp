import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/sale_channels.dart';
import 'package:rifaapp/ui/features/sale_channels/view_models/sale_channel_view_model.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/widgets/current_raffle_banner.dart';
import 'package:rifaapp/ui/core/widgets/status_badge.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/features/advisors/views/assigned_numbers_widgets.dart';

import 'package:rifaapp/ui/features/raffles/views/raffle_create_dialog.dart';
import 'package:rifaapp/ui/features/raffles/views/raffle_edit_dialog.dart';
import 'package:rifaapp/ui/core/utils/excel_csv_helper.dart';
import 'package:rifaapp/ui/core/utils/whatsapp_helper.dart';
import 'ticket_detail_dialog.dart';
import 'package:rifaapp/ui/features/raffles/views/sales_blocked_dialog.dart';
import 'ticket_print_dialog.dart';
import 'import_sold_tickets_dialog.dart';
import 'raffle_poster_2d_dialog.dart';
import 'available_numbers_dialog.dart';

class TicketGridView extends StatefulWidget {
  const TicketGridView({super.key});

  @override
  State<TicketGridView> createState() => _TicketGridViewState();
}

class _TicketGridViewState extends State<TicketGridView> {
  final TextEditingController _searchController = TextEditingController();
  bool _isGridView = true;

  bool _isRefreshing = false;
  Timer? _liveSyncTimer;

  @override
  void initState() {
    super.initState();
    _startLiveSync();
  }

  void _startLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
      final raffleVM = Provider.of<RaffleViewModel>(context, listen: false);
      final currentRaffle = raffleVM.selectedRaffle;
      if (currentRaffle != null) {
        final ticketVM = Provider.of<TicketViewModel>(context, listen: false);
        ticketVM.syncIfChanged(raffleId: currentRaffle.id);
      }
    });
  }

  /// Reloads the raffle's tickets from the server so sold / available reflect other users' sales.
  Future<void> _refreshTickets(TicketViewModel ticketVM, String? raffleId,
      {bool showSummary = true}) async {
    setState(() => _isRefreshing = true);
    // Also reloads the advisor's numbers, in case the admin assigned more
    await Future.wait([
      ticketVM.loadTickets(raffleId: raffleId),
      context.read<AuthViewModel>().refreshActiveAdvisor()
    ]);
    if (!mounted) return;
    setState(() => _isRefreshing = false);
    if (!showSummary) return;
    final sold = ticketVM.tickets.where((t) => t.status != 'DISPONIBLE').length;
    final available = ticketVM.tickets.length - sold;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Lista actualizada: $sold vendidas • $available disponibles')),
    );
  }

  @override
  void dispose() {
    _liveSyncTimer?.cancel();
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

        // Auto-fix if tickets in memory belong to another raffle (e.g. loaded without raffleId in another view)
        if (currentRaffle != null &&
            !ticketVM.isLoading &&
            ticketVM.tickets.isNotEmpty &&
            ticketVM.tickets.any((t) => t.raffleId != currentRaffle.id)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted)
              ticketVM.loadTickets(raffleId: currentRaffle.id);
          });
        }

        List<Ticket> displayTickets = ticketVM.searchedTickets;
        if (currentRaffle != null) {
          displayTickets = displayTickets
              .where((t) => t.raffleId == currentRaffle.id)
              .toList();
        }

        // El ayudante del administrador (oficina/integral con permiso) ve las boletas de todos los asesores
        if (authVM.isAsesor && authVM.activeAdvisor != null && authVM.activeAdvisor!.canManageAllTickets != true) {
          final adv = authVM.activeAdvisor!;
          displayTickets = displayTickets.where((t) {
            if (t.status != 'DISPONIBLE') {
              // Only see tickets sold by themselves!
              return t.advisorId == adv.id ||
                  t.advisorName.trim().toLowerCase() ==
                      adv.name.trim().toLowerCase() ||
                  (adv.code.isNotEmpty && t.advisorName.contains(adv.code));
            }
            return adv.coversTicket(t,
                independent: currentRaffle?.isIndependentBook ?? true);
          }).toList();
        }

        // Counts per status reflect exactly what this user can see (before the status filter)
        final statusCounts = TicketViewModel.countByStatus(displayTickets);
        displayTickets = displayTickets
            .where((t) =>
                TicketViewModel.matchesStatus(t, ticketVM.selectedStatusFilter))
            .toList()
          ..sort((a, b) => a.sortNumber.compareTo(b.sortNumber));

        return Column(
          children: [
            const CurrentRaffleBanner(),
            const AdvisorNumbersBar(),
            Container(
              padding: EdgeInsets.all(
                  MediaQuery.of(context).size.width < 600 ? 12 : 16),
              color: Theme.of(context).cardColor,
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 560;
                      final searchField = TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: authVM.isAsesor
                              ? 'Buscar en mis boletas...'
                              : 'Buscar oportunidad, comprador, celular, cédula, correo o asesor...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    ticketVM.setSearchQuery('',
                                        raffleId: currentRaffle?.id);
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 16),
                        ),
                        onChanged: (val) {
                          ticketVM.setSearchQuery(val,
                              raffleId: currentRaffle?.id);
                        },
                      );
                      final actionButtons = <Widget>[
                        IconButton.filledTonal(
                          icon: _isRefreshing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh_rounded),
                          onPressed: _isRefreshing
                              ? null
                              : () =>
                                  _refreshTickets(ticketVM, currentRaffle?.id),
                          tooltip: 'Actualizar lista (vendidas y disponibles)',
                        ),
                        const SizedBox(width: 8),
                        if (authVM.isAdmin && currentRaffle != null) ...[
                          IconButton.filledTonal(
                            icon: const Icon(Icons.settings),
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) =>
                                  RaffleEditDialog(raffle: currentRaffle),
                            ),
                            tooltip:
                                'Gestionar Sorteo (Asesores, Estado, Importar)',
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
                            tooltip:
                                'Importar Boletas Vendidas desde Excel (.xlsx)',
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Cambiar de rifa: el asesor solo si tiene más de una activa; el administrador si hay más de una (activa o inactiva)
                        if (currentRaffle != null &&
                            (authVM.isAdmin
                                ? raffleVM.raffles.length > 1
                                : raffleVM.raffles
                                        .where((r) =>
                                            r.status != 'INACTIVA' &&
                                            !r.isClosed)
                                        .length >
                                    1)) ...[
                          IconButton.filledTonal(
                            icon: const Icon(Icons.swap_horiz_rounded),
                            onPressed: () => CurrentRaffleBanner.showPicker(
                                context, raffleVM, authVM.isAdmin),
                            tooltip: 'Cambiar de rifa',
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (currentRaffle != null) ...[
                          // La plantilla 2D es de 100 números: solo con rifas de 2 dígitos
                          if (currentRaffle.digits <= 2) ...[
                            IconButton.filledTonal(
                              icon: const Icon(Icons.grid_on_rounded,
                                  color: AppTheme.accentAmber),
                              onPressed: () => showDialog(
                                context: context,
                                builder: (_) =>
                                    RafflePoster2dDialog(raffle: currentRaffle),
                              ),
                              tooltip:
                                  'Plantilla / Afiche Rifa 2D (100 Números)',
                            ),
                            const SizedBox(width: 8),
                          ],
                          IconButton.filledTonal(
                            icon: const Icon(Icons.mark_chat_read_outlined,
                                color: AppTheme.secondaryEmerald),
                            onPressed: () => AvailableNumbersDialog.show(
                              context,
                              raffle: currentRaffle,
                              initialAdvisor:
                                  authVM.isAsesor ? authVM.activeAdvisor : null,
                            ),
                            tooltip:
                                'Números Disponibles (Ver / Descargar en Imagen o Excel)',
                          ),
                          const SizedBox(width: 8),
                        ],
                        IconButton.filledTonal(
                          icon: const Icon(Icons.file_download_outlined,
                              color: Colors.green),
                          onPressed: () {
                            final ticketsToExport = displayTickets;
                            if (ticketsToExport.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'No hay boletas disponibles para exportar.')),
                              );
                              return;
                            }
                            ExcelCsvHelper.exportTicketsToExcel(
                              ticketsToExport,
                              title:
                                  'Boletas_${currentRaffle?.title ?? "Rifa"}',
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppTheme.secondaryEmerald,
                                content: Text(
                                    '✓ Descargando ${ticketsToExport.length} boletas en Excel (.xlsx)...'),
                              ),
                            );
                          },
                          tooltip:
                              'Descargar Información de Boletas a Excel (.xlsx)',
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          icon: Icon(
                              _isGridView ? Icons.view_list : Icons.grid_view),
                          onPressed: () =>
                              setState(() => _isGridView = !_isGridView),
                          tooltip: _isGridView ? 'Ver Lista' : 'Ver Cuadrícula',
                        ),
                      ];
                      // Áreas táctiles mínimas de 44x44 en todos los botones de acción
                      final touchTheme = Theme.of(context).copyWith(
                        iconButtonTheme: IconButtonThemeData(
                            style: IconButton.styleFrom(
                                minimumSize: const Size(44, 44))),
                      );
                      if (isNarrow) {
                        return Theme(
                          data: touchTheme,
                          child: Column(
                            children: [
                              searchField,
                              const SizedBox(height: 10),
                              // Wrap: con 7 botones de 44 px no caben en una sola fila a 320-412 px
                              Align(
                                alignment: Alignment.centerRight,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.end,
                                  children: actionButtons
                                      .where((w) => w is! SizedBox)
                                      .toList(),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return Theme(
                        data: touchTheme,
                        child: Row(
                          children: [
                            Expanded(child: searchField),
                            const SizedBox(width: 8),
                            ...actionButtons,
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Stack(
                    children: [
                      // Desvanecido en el borde derecho: indica que hay más fichas al deslizar
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(right: 32),
                        child: Row(
                          children: [
                            _buildFilterChip(context, ticketVM, 'TODOS',
                                statusCounts['TODOS'] ?? 0),
                            const SizedBox(width: 8),
                            _buildFilterChip(context, ticketVM, 'DISPONIBLE',
                                statusCounts['DISPONIBLE'] ?? 0),
                            const SizedBox(width: 8),
                            _buildFilterChip(context, ticketVM, 'RESERVADA',
                                statusCounts['RESERVADA'] ?? 0),
                            const SizedBox(width: 8),
                            _buildFilterChip(context, ticketVM, 'ABONO_PARCIAL',
                                statusCounts['ABONO_PARCIAL'] ?? 0),
                            const SizedBox(width: 8),
                            _buildFilterChip(context, ticketVM, 'PAGADA',
                                statusCounts['PAGADA'] ?? 0),
                            // Pagadas que el administrador ya validó (legalizadas): antes solo se veían en "Todas"
                            const SizedBox(width: 8),
                            _buildFilterChip(context, ticketVM, 'CONFIRMADA',
                                statusCounts['CONFIRMADA'] ?? 0),
                            if ((statusCounts['POR_VALIDAR'] ?? 0) > 0) ...[
                              const SizedBox(width: 8),
                              _buildFilterChip(context, ticketVM, 'POR_VALIDAR',
                                  statusCounts['POR_VALIDAR'] ?? 0),
                            ],
                          ],
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: 36,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Theme.of(context)
                                      .cardColor
                                      .withValues(alpha: 0),
                                  Theme.of(context).cardColor
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.confirmation_number_outlined,
                                    size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  raffleVM.raffles.isEmpty
                                      ? '¡Aún no has creado ninguna rifa!'
                                      : (authVM.isAsesor
                                          ? 'No tienes boletas en este filtro'
                                          : 'No se encontraron boletas'),
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                if (raffleVM.raffles.isEmpty &&
                                    authVM.isAdmin) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Crea tu primer sorteo para comenzar a vender boletas y asignar números a tus asesores.',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.add),
                                    label: const Text('Crear Primer Sorteo'),
                                    onPressed: () => showDialog(
                                      context: context,
                                      builder: (_) =>
                                          const RaffleCreateDialog(),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          // Pull down to reload sold / available tickets from the server
                          onRefresh: () => _refreshTickets(
                              ticketVM, currentRaffle?.id,
                              showSummary: false),
                          child: _isGridView
                              ? _buildGrid(context, displayTickets,
                                  currentRaffle?.title, currency)
                              : _buildList(context, displayTickets,
                                  currentRaffle?.title, currency),
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(BuildContext context, TicketViewModel ticketVM,
      String status, int count) {
    bool isSelected = ticketVM.selectedStatusFilter == status;
    bool isPorValidar = status == 'POR_VALIDAR';
    String label = status == 'TODOS'
        ? 'Todas'
        : (isPorValidar
            ? '⚠️ Transferencias por Validar'
            : AppTheme.getStatusLabel(status));

    return FilterChip(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      avatar: isPorValidar
          ? Icon(Icons.warning_amber_rounded,
              size: 16,
              color: AppTheme.readable(context, Colors.amber.shade900))
          : null,
      label: Text(
        '$label ($count)',
        style: TextStyle(
          fontWeight: isPorValidar ? FontWeight.bold : FontWeight.normal,
          color: isPorValidar
              ? AppTheme.readable(context, Colors.amber.shade900)
              : null,
        ),
      ),
      selected: isSelected,
      onSelected: (_) {
        ticketVM.setStatusFilter(status);
      },
      backgroundColor: isPorValidar ? Colors.amber.shade50 : null,
      side: isPorValidar
          ? BorderSide(color: Colors.amber.shade800, width: 1.2)
          : null,
      selectedColor: isPorValidar
          ? Colors.amber.shade200
          : AppTheme.primaryBlue.withValues(alpha: 0.2),
      checkmarkColor: isPorValidar
          ? AppTheme.readable(context, Colors.amber.shade900)
          : AppTheme.primaryBlue,
    );
  }

  Widget _buildGrid(BuildContext context, List<Ticket> tickets,
      String? raffleTitle, NumberFormat currency) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(isMobile ? 10 : 16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: (isMobile ? 268 : 246) +
            (MediaQuery.textScalerOf(context).scale(1) - 1) * 160,
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
            side:
                BorderSide(color: borderCol.withValues(alpha: 0.4), width: 1.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(
            onTap: () {
              // Rifa cerrada, inactiva o con el sorteo final vencido: no se vende, ni el administrador ni el asesor
              final blocked = ticket.status == 'DISPONIBLE'
                  ? context
                      .read<RaffleViewModel>()
                      .selectedRaffle
                      ?.salesBlockedReason
                  : null;
              if (blocked != null) {
                showSalesBlockedDialog(context, blocked);
                return;
              }
              showDialog(
                context: context,
                builder: (_) => TicketDetailDialog(
                    ticket: ticket, raffleTitle: raffleTitle),
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
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppTheme.primaryBlue),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.print_outlined, size: 18),
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap),
                            constraints: const BoxConstraints(
                                minWidth: 44, minHeight: 44),
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
                          if (WhatsAppHelper.canRemind(ticket)) ...[
                            const SizedBox(height: 0),
                            IconButton(
                              icon: const Icon(
                                  Icons.notifications_active_outlined,
                                  size: 18,
                                  color: Color(0xFF128C7E)),
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap),
                              constraints: const BoxConstraints(
                                  minWidth: 44, minHeight: 44),
                              tooltip: 'Recordar pago por WhatsApp',
                              onPressed: () =>
                                  WhatsAppHelper.sendPaymentReminder(
                                ticket: ticket,
                                raffle: context
                                    .read<RaffleViewModel>()
                                    .raffles
                                    .where((r) => r.id == ticket.raffleId)
                                    .firstOrNull,
                                raffleTitle: raffleTitle ?? 'RIFA',
                                context: context,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusBadge(status: ticket.status, isSmall: true),
                      if (ticket.abonos.any((a) =>
                          a.isTransfer && a.cashState == 'POR_VALIDAR')) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.amber.shade800),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  size: 12,
                                  color: AppTheme.readable(
                                      context, Colors.amber.shade900)),
                              const SizedBox(width: 2),
                              Text('Validar',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.readable(
                                          context, Colors.amber.shade900))),
                            ],
                          ),
                        ),
                      ],
                      if (ticket.isSoldByBot ||
                          ticket.saleChannel.toLowerCase().contains('bot')) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: const Color(0xFF6366F1), width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.smart_toy_rounded,
                                  size: 11, color: Color(0xFF4F46E5)),
                              SizedBox(width: 2),
                              Text('Bot',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF4F46E5))),
                            ],
                          ),
                        ),
                      ],
                      if (ticket.saleChannel.isNotEmpty &&
                          !ticket.saleChannel
                              .toLowerCase()
                              .contains('bot')) ...[
                        _buildChannelChip(ticket.saleChannel),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (ticket.buyerName.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: (ticket.status == 'PAGADA' ||
                                ticket.status == 'CONFIRMADA')
                            ? AppTheme.secondaryEmerald.withValues(alpha: 0.12)
                            : (ticket.status == 'ABONO_PARCIAL'
                                ? AppTheme.accentAmber.withValues(alpha: 0.15)
                                : Colors.purple.withValues(alpha: 0.12)),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (ticket.status == 'PAGADA' ||
                                  ticket.status == 'CONFIRMADA')
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
                            color: (ticket.status == 'PAGADA' ||
                                    ticket.status == 'CONFIRMADA')
                                ? AppTheme.secondaryEmerald
                                : (ticket.status == 'ABONO_PARCIAL'
                                    ? AppTheme.readable(
                                        context, Colors.amber.shade900)
                                    : AppTheme.readable(
                                        context, Colors.purple.shade700)),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              ticket.buyerName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: (ticket.status == 'PAGADA' ||
                                        ticket.status == 'CONFIRMADA')
                                    ? AppTheme.readable(
                                        context, Colors.green.shade900)
                                    : (ticket.status == 'ABONO_PARCIAL'
                                        ? AppTheme.readable(
                                            context, Colors.amber.shade900)
                                        : AppTheme.readable(
                                            context, Colors.purple.shade900)),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    if (ticket.advisorName.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.blue.shade300, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.badge_outlined,
                                size: 12,
                                color: AppTheme.readable(
                                    context, Colors.blue.shade800)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Asignada: ${ticket.advisorName.trim()}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.readable(
                                      context, Colors.blue.shade900),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Text('Disponible para venta',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.readable(context, Colors.black87),
                              fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            currency.format(ticket.price),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          if (ticket.balancePending > 0 && ticket.totalPaid > 0)
                            Text(
                              'Abonado: ${currency.format(ticket.totalPaid)}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.accentAmber,
                                  fontWeight: FontWeight.bold),
                            ),
                        ],
                      )),
                      const SizedBox(width: 6),
                      // Who handled or owns the ticket: ALWAYS SHOW IF ASSIGNED
                      if (ticket.advisorName.trim().isNotEmpty)
                        Expanded(
                          child: Tooltip(
                            message: 'Asesor: ${ticket.advisorName.trim()}',
                            child: Text(
                              'Asesor: ${ticket.advisorName.trim()}',
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: ticket.status == 'DISPONIBLE'
                                    ? AppTheme.readable(
                                        context, Colors.blue.shade800)
                                    : Colors.grey[700],
                                fontWeight: FontWeight.bold,
                              ),
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
    final master = context.read<SaleChannelViewModel>().byName(channel);
    final color = SaleChannels.colorFrom(master?.color ?? '#64748B');
    final icon = SaleChannels.iconFor(master?.icon ?? 'more');
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
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 12, color: color),
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
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    channel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: color),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, List<Ticket> tickets,
      String? raffleTitle, NumberFormat currency) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding:
          EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 10 : 16),
      itemCount: tickets.length,
      itemBuilder: (context, i) {
        final ticket = tickets[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            onTap: () {
              // Rifa cerrada, inactiva o con el sorteo final vencido: no se vende, ni el administrador ni el asesor
              final blocked = ticket.status == 'DISPONIBLE'
                  ? context
                      .read<RaffleViewModel>()
                      .selectedRaffle
                      ?.salesBlockedReason
                  : null;
              if (blocked != null) {
                showSalesBlockedDialog(context, blocked);
                return;
              }
              showDialog(
                context: context,
                builder: (_) => TicketDetailDialog(
                    ticket: ticket, raffleTitle: raffleTitle),
              );
            },
            leading: CircleAvatar(
              backgroundColor:
                  AppTheme.getStatusColor(ticket.status).withValues(alpha: 0.2),
              child: Text(
                ticket.numbers.length == 1
                    ? ticket.displayNumber
                    : '${ticket.numbers.length}',
                style: TextStyle(
                  color: AppTheme.getStatusColor(ticket.status),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            title: Text('N° ${ticket.displayNumber}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ticket.buyerName.isNotEmpty
                  ? Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (ticket.status == 'PAGADA' ||
                                    ticket.status == 'CONFIRMADA')
                                ? AppTheme.secondaryEmerald
                                    .withValues(alpha: 0.12)
                                : (ticket.status == 'ABONO_PARCIAL'
                                    ? AppTheme.accentAmber
                                        .withValues(alpha: 0.15)
                                    : Colors.purple.withValues(alpha: 0.12)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_rounded,
                                size: 13,
                                color: (ticket.status == 'PAGADA' ||
                                        ticket.status == 'CONFIRMADA')
                                    ? AppTheme.secondaryEmerald
                                    : (ticket.status == 'ABONO_PARCIAL'
                                        ? AppTheme.readable(
                                            context, Colors.amber.shade900)
                                        : AppTheme.readable(
                                            context, Colors.purple.shade700)),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                ticket.buyerName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: (ticket.status == 'PAGADA' ||
                                          ticket.status == 'CONFIRMADA')
                                      ? AppTheme.readable(
                                          context, Colors.green.shade900)
                                      : (ticket.status == 'ABONO_PARCIAL'
                                          ? AppTheme.readable(
                                              context, Colors.amber.shade900)
                                          : AppTheme.readable(
                                              context, Colors.purple.shade900)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (ticket.buyerPhone.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '• Tel: ${ticket.buyerPhone}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black87),
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
                Text(currency.format(ticket.price),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      },
    );
  }
}
