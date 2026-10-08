import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/models/raffle.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';

/// Prominent header with the raffle the user is working on, shown on every screen that acts
/// on a single raffle (tickets, cash, winners) to avoid selling or registering in the wrong one.
class CurrentRaffleBanner extends StatelessWidget {
  const CurrentRaffleBanner({super.key});

  static const List<Color> _palette = [
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF059669),
    Color(0xFFDB2777),
    Color(0xFFEA580C),
    Color(0xFF0891B2),
    Color(0xFF4F46E5),
    Color(0xFFB45309),
  ];

  /// Same raffle -> same color everywhere, so different raffles are easy to tell apart.
  static Color colorFor(String raffleId) {
    var hash = 0;
    for (final unit in raffleId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  static void _select(BuildContext context, Raffle raffle) {
    Provider.of<RaffleViewModel>(context, listen: false).selectRaffle(raffle);
    Provider.of<TicketViewModel>(context, listen: false).loadTickets(raffleId: raffle.id);
  }

  void _showPicker(BuildContext context, RaffleViewModel raffleVM, bool isAdmin) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Seleccione la rifa', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              for (final raffle in raffleVM.raffles)
                ListTile(
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: colorFor(raffle.id),
                    child: const Icon(Icons.confirmation_number, size: 15, color: Colors.white),
                  ),
                  title: Text(raffle.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(isAdmin && raffle.status == 'INACTIVA' ? 'Inactiva' : '${raffle.totalTickets} boletas'),
                  trailing: raffle.id == raffleVM.selectedRaffle?.id ? Icon(Icons.check_circle, color: colorFor(raffle.id)) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _select(context, raffle);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final raffleVM = Provider.of<RaffleViewModel>(context);
    final isAdmin = Provider.of<AuthViewModel>(context, listen: false).isAdmin;
    final raffle = raffleVM.selectedRaffle;
    if (raffle == null) return const SizedBox.shrink();

    final color = colorFor(raffle.id);
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final drawDate = DateTime.tryParse(raffle.mainDrawDate);
    final isInactive = raffle.status == 'INACTIVA';
    final details = [
      if (drawDate != null) 'Sorteo: ${DateFormat('dd/MM/yyyy').format(drawDate.toLocal())}',
      currency.format(raffle.ticketPrice),
      '${raffle.totalTickets} boletas',
      'Gana con ${raffle.winningRuleText}',
    ].join('  •  ');

    final banner = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(left: BorderSide(color: color, width: 5), bottom: BorderSide(color: color.withValues(alpha: 0.25))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.confirmation_number, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'RIFA ACTUAL',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1, color: color),
                    ),
                    if (raffle.isClosed) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          'CERRADA • SE ELIMINA EN ${raffle.daysUntilDeletion} DÍA(S)',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ] else if (isInactive && isAdmin) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(6)),
                        child: const Text('INACTIVA', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  raffle.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, height: 1.2),
                ),
                const SizedBox(height: 2),
                Text(details, style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
              ],
            ),
          ),
          if (raffleVM.raffles.length > 1) ...[
            const SizedBox(width: 8),
            // Phones: icon only, so the raffle name keeps the space
            if (MediaQuery.of(context).size.width < 600)
              IconButton.outlined(
                onPressed: () => _showPicker(context, raffleVM, isAdmin),
                icon: Icon(Icons.swap_horiz, color: color),
                tooltip: 'Cambiar rifa',
                style: IconButton.styleFrom(side: BorderSide(color: color.withValues(alpha: 0.6))),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _showPicker(context, raffleVM, isAdmin),
                icon: Icon(Icons.swap_horiz, size: 18, color: color),
                label: Text('Cambiar rifa', style: TextStyle(color: color)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: color.withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
          ],
        ],
      ),
    );

    // Advisors: the admin stopped their sales in this raffle
    final block = isAdmin ? null : raffle.advisorSalesBlock;
    if (block == null) return banner;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        banner,
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: Colors.red.shade700,
          child: Row(
            children: [
              const Icon(Icons.lock, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'VENTAS CERRADAS: $block No puede vender ni apartar boletas nuevas; sí puede registrar abonos de las que ya vendió.',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
