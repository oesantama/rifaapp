import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/admin_cash/views/cash_widgets.dart';

const _monthNames = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

String _monthLabel(String ym) {
  final parts = ym.split('-');
  return parts.length == 2 ? '${_monthNames[int.parse(parts[1]) - 1]} ${parts[0].substring(2)}' : ym;
}

String _day(String? value) {
  final d = DateTime.tryParse(value ?? '');
  return d == null ? '' : DateFormat('dd/MM/yyyy').format(d);
}

const _statusInfo = {
  'PRO': ('PRO al día', Color(0xFF059669)),
  'POR_VENCER': ('Vence en ≤ 7 días', Color(0xFFD97706)),
  'VENCIDO': ('PRO vencido', Color(0xFFDC2626)),
  'GRATIS': ('Gratis', Color(0xFF64748B)),
  'DEMO': ('Demo', Color(0xFF7C3AED)),
};

/// Subscription income: this month, total, monthly recurring revenue, last 12 months and plans.
class IncomeTab extends StatefulWidget {
  const IncomeTab({super.key});

  @override
  State<IncomeTab> createState() => _IncomeTabState();
}

class _IncomeTabState extends State<IncomeTab> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await RaffleRepository().fetchMonetizationSummary();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    final d = _data;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final isMobile = MediaQuery.of(context).size.width < 600;
    final months = [for (final m in (d['months'] as List)) Map<String, dynamic>.from(m)];
    final maxValue = months.fold<double>(1, (mx, m) => ((m['total'] as num).toDouble() > mx ? (m['total'] as num).toDouble() : mx));
    final counts = Map<String, dynamic>.from(d['counts'] ?? {});
    final companies = [for (final c in (d['companies'] as List)) Map<String, dynamic>.from(c)];
    final expiring = companies.where((c) => c['status'] == 'POR_VENCER' || c['status'] == 'VENCIDO').toList();

    final kpis = [
      CashKpi(
        title: 'INGRESOS ESTE MES',
        value: cashCurrency.format(d['thisMonth'] ?? 0),
        subtitle: 'Pagos de suscripciones',
        color: AppTheme.secondaryEmerald,
        icon: Icons.trending_up,
      ),
      CashKpi(
        title: 'INGRESO MENSUAL RECURRENTE',
        value: cashCurrency.format(d['mrr'] ?? 0),
        subtitle: 'Promedio mensual de los PRO activos',
        color: AppTheme.primaryBlue,
        icon: Icons.autorenew,
      ),
      CashKpi(
        title: 'TOTAL RECAUDADO',
        value: cashCurrency.format(d['total'] ?? 0),
        subtitle: 'Desde el primer pago',
        color: Colors.deepPurple,
        icon: Icons.savings_outlined,
      ),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(isMobile ? 12 : 20),
        children: [
          LayoutBuilder(builder: (context, c) {
            final perRow = c.maxWidth >= 700 ? 3 : 1;
            final w = (c.maxWidth - (perRow - 1) * 10) / perRow;
            return Wrap(spacing: 10, runSpacing: 10, children: [for (final k in kpis) SizedBox(width: w, child: k)]);
          }),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ingresos por mes (últimos 12 meses)', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 170,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final m in months)
                          Expanded(
                            child: Tooltip(
                              message: '${_monthLabel(m['month'])}: ${cashCurrency.format(m['total'])}',
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Container(
                                      height: 2 + 130 * (m['total'] as num).toDouble() / maxValue,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryBlue.withValues(alpha: (m['total'] as num) > 0 ? 0.85 : 0.2),
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    FittedBox(child: Text(_monthLabel(m['month']), style: const TextStyle(fontSize: 10))),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in {
                'PRO': counts['pro'],
                'POR_VENCER': counts['porVencer'],
                'VENCIDO': counts['vencido'],
                'GRATIS': counts['gratis'],
                'DEMO': counts['demo'],
              }.entries)
                CashChip('${_statusInfo[e.key]!.$1}: ${e.value ?? 0}', _statusInfo[e.key]!.$2),
            ],
          ),
          if (expiring.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Requieren atención', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            for (final c in expiring)
              Card(
                child: ListTile(
                  leading: Icon(Icons.warning_amber_rounded, color: _statusInfo[c['status']]!.$2),
                  title: Text(c['name'] ?? ''),
                  subtitle: Text('${_statusInfo[c['status']]!.$1} • vence ${_day(c['proUntil'])}'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Each company's plan and its subscription payments: register a payment (extends PRO), see and void them.
class CompanyPlansTab extends StatefulWidget {
  const CompanyPlansTab({super.key});

  @override
  State<CompanyPlansTab> createState() => _CompanyPlansTabState();
}

class _CompanyPlansTabState extends State<CompanyPlansTab> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = RaffleRepository();
      final results = await Future.wait([repo.fetchMonetizationSummary(), repo.fetchMonetization()]);
      if (mounted) {
        setState(() {
          _summary = results[0];
          _settings = results[1];
        });
      }
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: error ? AppTheme.dangerRose : AppTheme.secondaryEmerald, content: Text(text)),
    );
  }

  Future<void> _registerPayment(Map<String, dynamic> company) async {
    int priceFor(int m) {
      final key = {1: 'monthlyPrice', 3: 'quarterlyPrice', 6: 'semiannualPrice', 12: 'yearlyPrice'}[m]!;
      final direct = ((_settings?[key] ?? 0) as num).toInt();
      if (direct > 0) return direct;
      return ((_settings?['monthlyPrice'] ?? 0) as num).toInt() * m;
    }

    int months = 1;
    final amountCtrl = TextEditingController(text: priceFor(1) > 0 ? '${priceFor(1)}' : '');
    final methodCtrl = TextEditingController(text: 'Transferencia');
    final refCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime paidOn = DateTime.now();
    String? error;

    void suggest(int m) {
      final p = priceFor(m);
      if (p > 0) amountCtrl.text = '$p';
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Registrar pago • ${company['name']}'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    company['proUntil'] != null && company['status'] != 'VENCIDO'
                        ? 'PRO actual hasta ${_day(company['proUntil'])}: el pago se suma a partir del día siguiente.'
                        : 'El PRO empieza hoy.',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final m in [1, 3, 6, 12])
                        ChoiceChip(
                          label: Text(m == 12 ? '1 año' : '$m ${m == 1 ? 'mes' : 'meses'}'),
                          selected: months == m,
                          onSelected: (_) => setD(() {
                            months = m;
                            suggest(m);
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Valor pagado *', prefixText: '\$ ', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                      controller: methodCtrl, decoration: const InputDecoration(labelText: 'Medio de pago', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(labelText: 'Referencia / N° aprobación', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 4),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: Text('Fecha de pago: ${DateFormat('dd/MM/yyyy').format(paidOn)}'),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: () async {
                      final picked =
                          await showDatePicker(context: ctx, initialDate: paidOn, firstDate: DateTime(2024), lastDate: DateTime.now());
                      if (picked != null) setD(() => paidOn = picked);
                    },
                  ),
                  TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Nota')),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: AppTheme.dangerRose, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  final r = await RaffleRepository().registerSubscriptionPayment({
                    'companyId': company['id'],
                    'amount': int.tryParse(amountCtrl.text) ?? 0,
                    'months': months,
                    'method': methodCtrl.text.trim(),
                    'reference': refCtrl.text.trim(),
                    'paidOn': DateFormat('yyyy-MM-dd').format(paidOn),
                    'note': noteCtrl.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  _snack('Pago registrado: PRO hasta ${_day(r['company']?['proUntil'])}.');
                  _load();
                } catch (e) {
                  setD(() => error = e.toString());
                }
              },
              icon: const Icon(Icons.check),
              label: const Text('Registrar pago'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPayments(Map<String, dynamic> company) async {
    List<Map<String, dynamic>> payments;
    try {
      payments = await RaffleRepository().fetchSubscriptionPayments(companyId: company['id']);
    } catch (e) {
      _snack(e.toString(), error: true);
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pagos • ${company['name']}'),
        content: SizedBox(
          width: 480,
          child: payments.isEmpty
              ? const Text('Sin pagos registrados.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in payments)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${cashCurrency.format(p['amount'])} • ${p['months']} mes(es)',
                          style: TextStyle(decoration: p['voided'] != null ? TextDecoration.lineThrough : null),
                        ),
                        subtitle: Text(
                          'Pagado ${_day(p['paidOn'])} • ${p['method'] ?? ''}${(p['reference'] ?? '').toString().isNotEmpty ? ' (${p['reference']})' : ''}\n'
                          'Período ${_day(p['periodStart'])} → ${_day(p['periodEnd'])} • registró ${p['registeredBy'] ?? ''}'
                          '${p['voided'] != null ? '\nANULADO: ${p['voided']['reason']}' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: p['voided'] == null
                            ? IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: AppTheme.dangerRose),
                                tooltip: 'Anular pago',
                                onPressed: () async {
                                  final reason = await askReason(ctx, 'Anular pago', hint: 'Ej: registrado por error');
                                  if (reason == null) return;
                                  try {
                                    await RaffleRepository().voidSubscriptionPayment(p['id'], reason);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    _snack('Pago anulado.');
                                    _load();
                                  } catch (e) {
                                    _snack(e.toString(), error: true);
                                  }
                                },
                              )
                            : null,
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
    final s = _summary;
    if (s == null) return const Center(child: CircularProgressIndicator());
    final companies = [for (final c in (s['companies'] as List)) Map<String, dynamic>.from(c)].where((c) => c['status'] != 'DEMO').toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'Registre aquí los pagos de cada empresa: el plan PRO se extiende solo según los meses pagados. '
            'El plan también se puede cambiar a mano en Empresas → Editar.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
          ),
          const SizedBox(height: 10),
          for (final c in companies)
            Card(
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
                        Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        CashChip(_statusInfo[c['status']]?.$1 ?? c['status'], _statusInfo[c['status']]?.$2 ?? Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 6),
                    CashInfoLine('Vence', c['proUntil'] != null ? _day(c['proUntil']) : (c['tier'] == 'PRO' ? 'Sin vencimiento' : '—')),
                    CashInfoLine(
                      'Último pago',
                      c['lastPayment'] != null
                          ? '${cashCurrency.format(c['lastPayment']['amount'])} (${c['lastPayment']['months']} mes(es)) el ${_day(c['lastPayment']['paidOn'])}'
                          : 'Ninguno',
                    ),
                    CashInfoLine('Total pagado', cashCurrency.format(c['totalPaid'] ?? 0)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _registerPayment(c),
                          icon: const Icon(Icons.add_card, size: 18),
                          label: const Text('Registrar pago'),
                        ),
                        TextButton.icon(
                            onPressed: () => _showPayments(c),
                            icon: const Icon(Icons.receipt_long, size: 18),
                            label: const Text('Ver pagos')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
