import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/date_formatter.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';

class IndependentDeliveriesView extends StatefulWidget {
  const IndependentDeliveriesView({super.key});

  @override
  State<IndependentDeliveriesView> createState() => _IndependentDeliveriesViewState();
}

class _IndependentDeliveriesViewState extends State<IndependentDeliveriesView> {
  final ApiService _api = ApiService();
  final NumberFormat _cop = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

  bool _loading = false;
  List<Map<String, dynamic>> _deliveries = [];
  List<Map<String, dynamic>> _summaryList = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final deliveries = await _api.getIndependentDeliveries();
      final summary = await _api.getIndependentSummary();
      if (mounted) {
        setState(() {
          _deliveries = deliveries;
          _summaryList = summary;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error al cargar datos: $e')),
        );
      }
    }
  }

  void _showAddDeliveryDialog(String defaultOwner, String defaultRaffleId, String defaultRaffleTitle) {
    final amountCtrl = TextEditingController();
    final ownerCtrl = TextEditingController(text: defaultOwner);
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: DateFormatterColombia.formatShort(DateTime.now().toIso8601String()));
    String method = 'EFECTIVO';
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.payments_rounded, color: Colors.teal, size: 24),
              ),
              const SizedBox(width: 10),
              const Text('Registrar Entrega de Dinero', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registra el dinero que le entregas o consignas al dueño de la rifa ($defaultOwner).',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ownerCtrl,
                  decoration: const InputDecoration(
                    labelText: 'A nombre de quién entregas *',
                    hintText: 'Ej: Don Wilo, William',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Monto Entregado (\$ COP) *',
                    hintText: 'Ej: 500000',
                    prefixIcon: Icon(Icons.attach_money, color: Colors.green),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: const InputDecoration(
                    labelText: 'Método de Entrega / Pago',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'EFECTIVO', child: Text('Efectivo en mano')),
                    DropdownMenuItem(value: 'NEQUI', child: Text('Consignación / Nequi')),
                    DropdownMenuItem(value: 'BANCOLOMBIA', child: Text('Bancolombia')),
                    DropdownMenuItem(value: 'DAVIPLATA', child: Text('Daviplata')),
                    DropdownMenuItem(value: 'OTRO', child: Text('Otro medio')),
                  ],
                  onChanged: (v) => setDialogState(() => method = v ?? 'EFECTIVO'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Comprobante / Referencia (Opcional)',
                    hintText: 'Ej: # Aprobación 48291',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones / Notas',
                    hintText: 'Ej: Primer corte de 30 boletas vendidas',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              onPressed: saving
                  ? null
                  : () async {
                      final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                      if (amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(backgroundColor: Colors.red, content: Text('Ingrese un monto válido mayor a 0')),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await _api.createIndependentDelivery({
                          'raffleId': defaultRaffleId,
                          'raffleTitle': defaultRaffleTitle,
                          'ownerName': ownerCtrl.text.trim(),
                          'amount': amount,
                          'paymentMethod': method,
                          'reference': refCtrl.text.trim(),
                          'notes': notesCtrl.text.trim(),
                          'date': DateFormatterColombia.toIsoString(dateCtrl.text),
                        });
                        if (mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(backgroundColor: AppTheme.secondaryEmerald, content: Text('✓ Entrega de ${_cop.format(amount)} registrada con éxito.')),
                          );
                          _loadData();
                        }
                      } catch (e) {
                        setDialogState(() => saving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('Error: $e')));
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('REGISTRAR ENTREGA'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteDelivery(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Anular Entrega?'),
        content: const Text('¿Está seguro de anular este registro de entrega? El saldo pendiente volverá a ajustarse.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anular', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await _api.deleteIndependentDelivery(id);
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('Error al anular: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final raffleVM = Provider.of<RaffleViewModel>(context);
    final selectedRaffle = raffleVM.selectedRaffle;
    final ownerName = selectedRaffle?.ownerName ?? 'Don Wilo';

    // Buscar resumen de la rifa seleccionada
    final rSummary = _summaryList.firstWhere(
      (s) => s['raffleId'] == selectedRaffle?.id,
      orElse: () => {
        'totalCollected': 0,
        'commissionEarned': 0,
        'totalDelivered': 0,
        'dueToOwner': 0,
        'totalTickets': 0,
        'soldCount': 0,
        'partialCount': 0,
      },
    );

    final totalRecaudado = (rSummary['totalCollected'] as num?)?.toDouble() ?? 0;
    final miComision = (rSummary['commissionEarned'] as num?)?.toDouble() ?? 0;
    final entregadoAlDueno = (rSummary['totalDelivered'] as num?)?.toDouble() ?? 0;
    final pendientePorEntregar = (rSummary['dueToOwner'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.teal, size: 24),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Auto-Conciliación y Liquidación',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Control de dinero recaudado, comisiones ganadas y entregas a organizadores externos ($ownerName).',
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _showAddDeliveryDialog(
                      ownerName,
                      selectedRaffle?.id ?? '',
                      selectedRaffle?.title ?? 'Sorteo Actual',
                    ),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('REGISTRAR ENTREGA AL DUEÑO'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Tarjetas de Resumen Financiero
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 700;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildSummaryCard(
                        title: 'Total Recaudado en Mano',
                        value: _cop.format(totalRecaudado),
                        subtitle: 'Boletas vendidas y abonos',
                        color: Colors.blue,
                        icon: Icons.savings_rounded,
                        width: isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2,
                      ),
                      _buildSummaryCard(
                        title: 'Mi Comisión Ganada',
                        value: _cop.format(miComision),
                        subtitle: 'Tu ganancia neta',
                        color: Colors.green,
                        icon: Icons.monetization_on_rounded,
                        width: isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2,
                      ),
                      _buildSummaryCard(
                        title: 'Entregado a $ownerName',
                        value: _cop.format(entregadoAlDueno),
                        subtitle: 'Efectivo / Consignado',
                        color: Colors.orange,
                        icon: Icons.check_circle_outline_rounded,
                        width: isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2,
                      ),
                      _buildSummaryCard(
                        title: 'Pendiente por Entregar',
                        value: _cop.format(pendientePorEntregar),
                        subtitle: 'Saldo actual a rendir',
                        color: pendientePorEntregar > 0 ? Colors.red : Colors.teal,
                        icon: Icons.pending_actions_rounded,
                        width: isWide ? (constraints.maxWidth - 36) / 4 : (constraints.maxWidth - 12) / 2,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),

              // Historial de Entregas
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Historial de Entregas y Consignaciones',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Recargar',
                    onPressed: _loadData,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (_loading)
                const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator(color: Colors.teal)))
              else if (_deliveries.isEmpty)
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_rounded, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text('No hay entregas registradas aún', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Cuando le entregues dinero a $ownerName, pulsa en "REGISTRAR ENTREGA AL DUEÑO".', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _deliveries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final d = _deliveries[i];
                      final amount = (d['amount'] as num?)?.toDouble() ?? 0;
                      final dateStr = d['date'] != null ? DateFormatterColombia.formatShort(d['date']) : 'Fecha no reg.';
                      final method = d['paymentMethod'] ?? 'EFECTIVO';
                      final owner = d['ownerName'] ?? ownerName;
                      final ref = d['reference'] != null && d['reference'].toString().isNotEmpty ? 'Ref: ${d['reference']}' : null;
                      final notes = d['notes'] != null && d['notes'].toString().isNotEmpty ? d['notes'] : null;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal.withValues(alpha: 0.15),
                          child: Icon(
                            method == 'EFECTIVO' ? Icons.payments_outlined : Icons.account_balance_outlined,
                            color: Colors.teal,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          '${_cop.format(amount)} entregados a $owner',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        subtitle: Text(
                          'Fecha: $dateStr • Método: $method${ref != null ? ' • $ref' : ''}${notes != null ? '\nNota: $notes' : ''}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        isThreeLine: notes != null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          tooltip: 'Anular esta entrega',
                          onPressed: () => _deleteDelivery(d['id']),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
