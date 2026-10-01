import 'package:flutter/material.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';

/// "5 reservadas · 3 abonadas · 9 pagadas = 17 vendidas" for one advisor in the current raffle.
class AdvisorSalesBreakdown extends StatelessWidget {
  final AdvisorSales sales;
  final bool compact;

  const AdvisorSalesBreakdown({super.key, required this.sales, this.compact = false});

  Widget _chip(String label, int value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: compact ? 2 : 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$value $label',
        style: TextStyle(fontSize: compact ? 10.5 : 12, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _chip(sales.reservadas == 1 ? 'reservada' : 'reservadas', sales.reservadas, Colors.purple),
        _chip(sales.abonadas == 1 ? 'abonada' : 'abonadas', sales.abonadas, AppTheme.accentAmber),
        _chip(sales.pagadas == 1 ? 'pagada' : 'pagadas', sales.pagadas, AppTheme.secondaryEmerald),
        Text('=', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600])),
        _chip(sales.total == 1 ? 'vendida' : 'vendidas', sales.total, AppTheme.primaryBlue),
      ],
    );
  }
}
