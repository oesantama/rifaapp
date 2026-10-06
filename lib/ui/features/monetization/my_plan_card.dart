import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';
import 'package:rifaapp/ui/core/utils/whatsapp_helper.dart';
import 'package:rifaapp/ui/features/admin_cash/views/cash_widgets.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';

String _day(String? value) {
  final d = DateTime.tryParse(value ?? '');
  return d == null ? '' : DateFormat('dd/MM/yyyy').format(d);
}

/// Company admin: its plan (Gratis / PRO and until when), its payments and how to renew.
class MyPlanCard extends StatefulWidget {
  const MyPlanCard({super.key});

  @override
  State<MyPlanCard> createState() => _MyPlanCardState();
}

class _MyPlanCardState extends State<MyPlanCard> {
  Map<String, dynamic>? _plan;

  @override
  void initState() {
    super.initState();
    RaffleRepository().fetchMyPlan().then((p) {
      if (mounted) setState(() => _plan = p);
    }).catchError((_) {});
  }

  void _contact(String text) {
    final p = _plan!;
    final company = context.read<AuthViewModel>().companyName;
    if ((p['contactWhatsApp'] ?? '').toString().isNotEmpty) {
      WhatsAppHelper.sendWhatsAppMessage(phone: p['contactWhatsApp'], message: '$text${company.isNotEmpty ? ' (empresa $company)' : ''}.');
    }
  }

  void _showPayments() {
    final payments = [for (final x in (_plan!['payments'] as List? ?? [])) Map<String, dynamic>.from(x)];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mis pagos del plan'),
        content: SizedBox(
          width: 420,
          child: payments.isEmpty
              ? const Text('Aún no hay pagos registrados.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in payments)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.receipt_long),
                        title: Text('${cashCurrency.format(p['amount'])} • ${p['months']} mes(es)'),
                        subtitle: Text('Pagado ${_day(p['paidOn'])} • período ${_day(p['periodStart'])} → ${_day(p['periodEnd'])}'),
                      ),
                  ],
                ),
        ),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _plan;
    if (p == null || p['isDemo'] == true) return const SizedBox.shrink();
    final status = p['status'] as String? ?? 'GRATIS';
    final isPro = status == 'PRO' || status == 'POR_VENCER';
    final until = p['proUntil'] as String?;
    final daysLeft = until == null ? null : DateTime.parse(until).difference(DateUtils.dateOnly(DateTime.now())).inDays;
    final (color, title, subtitle) = switch (status) {
      'POR_VENCER' => (
          Colors.orange.shade800,
          'Plan PRO por vencer',
          'Vence el ${_day(until)} (${daysLeft ?? 0} día(s)). Renueve para no ver anuncios.'
        ),
      'PRO' => (
          Colors.amber.shade800,
          'Plan PRO',
          until == null ? 'Sin anuncios • sin fecha de vencimiento' : 'Sin anuncios • vigente hasta ${_day(until)}'
        ),
      'VENCIDO' => (Colors.red.shade700, 'Plan PRO vencido', 'Venció el ${_day(until)}. Su empresa volvió al plan Gratis, con anuncios.'),
      _ => (Colors.blueGrey, 'Plan Gratis', 'Con anuncios. Pásese a PRO para quitarlos.'),
    };
    final price = [
      for (final (key, label) in [
        ('monthlyPrice', '1 mes'),
        ('quarterlyPrice', '3 meses'),
        ('semiannualPrice', '6 meses'),
        ('yearlyPrice', '1 año')
      ])
        if (((p[key] ?? 0) as num) > 0) '$label ${cashCurrency.format(p[key])}',
    ].join(' • ');
    final canContact = (p['contactWhatsApp'] ?? '').toString().isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: color.withValues(alpha: 0.5))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(isPro ? Icons.workspace_premium : Icons.campaign_outlined, color: color, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
                  Text(subtitle, style: const TextStyle(fontSize: 12.5)),
                  if (price.isNotEmpty && status != 'PRO') Text('Precio: $price', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  Wrap(
                    spacing: 4,
                    children: [
                      if (canContact && status != 'PRO')
                        TextButton.icon(
                          onPressed: () => _contact(isPro || status == 'VENCIDO'
                              ? 'Hola, quiero renovar el plan PRO de RifaApp'
                              : 'Hola, quiero activar el plan PRO de RifaApp'),
                          icon: const Icon(Icons.chat, size: 16),
                          label: Text(status == 'GRATIS' ? 'Quiero el PRO' : 'Renovar'),
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        ),
                      if ((p['payments'] as List? ?? []).isNotEmpty)
                        TextButton.icon(
                          onPressed: _showPayments,
                          icon: const Icon(Icons.receipt_long, size: 16),
                          label: const Text('Mis pagos'),
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
