import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/models/raffle.dart';
import 'package:rifaapp/data/models/winner.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/features/winners/view_models/winner_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/lotteries/views/lottery_field.dart';
import 'package:rifaapp/ui/features/admin_cash/views/cash_widgets.dart' show askReason;

String _day(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : DateFormat('dd/MM/yyyy').format(d.isUtc ? d.subtract(const Duration(hours: 5)) : d);
}

/// Grand prize (main draw) of the selected raffle: register the lottery result, see the winner and
/// record who received the prize. Advisors only see it.
class MainDrawCard extends StatelessWidget {
  final Raffle raffle;

  const MainDrawCard({super.key, required this.raffle});

  Future<void> _register(BuildContext context) async {
    final numberCtrl = TextEditingController();
    final prizeCtrl = TextEditingController(text: raffle.description);
    final amountCtrl = TextEditingController();
    String? error;
    final digits = raffle.digits;
    final vm = context.read<WinnerViewModel>();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Resultado del gran premio'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Juega el ${_day(raffle.mainDrawDate)}${raffle.mainLottery.isNotEmpty ? ' con la ${raffle.mainLottery}' : ''}. '
                    'Gana con ${raffle.winningRuleText}. Para ganar, la boleta debe estar pagada en su totalidad.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: numberCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    decoration: InputDecoration(
                      labelText: 'Resultado de la lotería *',
                      helperText: 'El número de $digits cifras o el resultado completo de la lotería',
                      prefixIcon: const Icon(Icons.pin),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: prizeCtrl,
                    maxLines: 2,
                    decoration:
                        const InputDecoration(labelText: 'Premio', hintText: 'Ej: Casa + \$1.000.000', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Valor del premio en dinero (opcional)',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
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
                final number = numberCtrl.text.trim();
                if (number.length < digits) {
                  setDialogState(() => error = 'Ingrese al menos $digits cifras.');
                  return;
                }
                final rec = await vm.registerWinner({
                  'raffleId': raffle.id,
                  'drawType': 'PRINCIPAL',
                  'winningNumber': number,
                  'prizeDescription': prizeCtrl.text.trim(),
                  'prizeAmount': amountCtrl.text.trim(),
                  'drawDate': raffle.mainDrawDate,
                });
                if (rec == null) {
                  setDialogState(() => error = vm.lastError ?? 'No se pudo registrar.');
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              icon: const Icon(Icons.emoji_events),
              label: const Text('Verificar y registrar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WinnerViewModel>();
    final isAdmin = context.watch<AuthViewModel>().isAdmin;
    final draws = vm.mainDrawsOf(raffle.id);
    // The latest result counts; a rescheduled one leaves room for a new attempt on the new date
    final latest = draws.firstOrNull;
    final result = latest != null && latest.decisionType != 'REPROGRAMADO' ? latest : null;
    final earlier = result == null ? draws : draws.skip(1).toList();
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    const gold = Color(0xFFB45309);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.amber.shade400, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.emoji_events, color: gold, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('GRAN PREMIO • SORTEO PRINCIPAL',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: gold, letterSpacing: 0.8)),
                      Text(
                        '${_day(raffle.mainDrawDate)}${raffle.mainLottery.isNotEmpty ? ' • ${raffle.mainLottery}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (result == null) ...[
              if (latest != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '🔁 El intento anterior quedó sin ganador y se vuelve a jugar el ${_day(latest.decision?['newDate'])}'
                    '${(latest.decision?['newLottery'] ?? '').toString().isNotEmpty ? ' con la ${latest.decision!['newLottery']}' : ''}.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              Text(
                isAdmin
                    ? 'Cuando juegue la lotería, registre aquí el resultado. El sistema busca la boleta ganadora (debe estar pagada en su totalidad) y deja el registro.'
                    : 'El resultado del gran premio aún no se ha registrado.',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              if (isAdmin) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _register(context),
                  icon: const Icon(Icons.emoji_events),
                  label: const Text('Registrar resultado del gran premio'),
                  style: ElevatedButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.white),
                ),
              ],
            ] else
              _MainDrawResult(record: result, currency: currency, isAdmin: isAdmin, raffle: raffle),
            if (earlier.isNotEmpty) ...[
              const Divider(height: 24),
              Text('Intentos anteriores (${earlier.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              for (final e in earlier)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• ${_day(e.drawDate)}: resultado ${e.lotteryResult.isNotEmpty ? e.lotteryResult : e.winningNumber} → ${e.noWinnerReason}'
                    '${e.decisionType == 'REPROGRAMADO' ? ' Reprogramado para ${_day(e.decision?['newDate'])}.' : ''}'
                    '${(e.decision?['note'] ?? '').toString().isNotEmpty ? ' (${e.decision!['note']})' : ''}',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MainDrawResult extends StatelessWidget {
  final WinnerRecord record;
  final NumberFormat currency;
  final bool isAdmin;
  final Raffle raffle;

  const _MainDrawResult({required this.record, required this.currency, required this.isAdmin, required this.raffle});

  Future<void> _reschedule(BuildContext context) async {
    DateTime? date;
    String? lottery = raffle.mainLottery.isNotEmpty ? raffle.mainLottery : null;
    final noteCtrl = TextEditingController();
    String? error;
    final vm = context.read<WinnerViewModel>();
    final raffleVM = context.read<RaffleViewModel>();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Volver a jugar el gran premio'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      'El resultado ${record.lotteryResult} quedó sin ganador. Elija la nueva fecha del sorteo; los compradores siguen participando.',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: Text(date == null ? 'Nueva fecha del sorteo *' : 'Nueva fecha: ${DateFormat('dd/MM/yyyy').format(date!)}'),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: () async {
                      final tomorrow = DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1));
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date ?? tomorrow.add(const Duration(days: 6)),
                        firstDate: tomorrow,
                        lastDate: DateTime(tomorrow.year + 2),
                      );
                      if (picked != null) setD(() => date = picked);
                    },
                  ),
                  LotteryField(
                    value: lottery,
                    label: 'Lotería',
                    helperText: 'Puede cambiarla si la nueva fecha juega con otra lotería',
                    onChanged: (v) => setD(() => lottery = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: noteCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Observación (opcional)')),
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
                if (date == null) {
                  setD(() => error = 'Elija la nueva fecha.');
                  return;
                }
                final (err, raffleJson) = await vm.saveMainDrawDecision(record.id, {
                  'decision': 'REPROGRAMAR',
                  'newDate': DateFormat('yyyy-MM-dd').format(date!),
                  if (lottery != null) 'lotteryName': lottery,
                  'note': noteCtrl.text.trim(),
                });
                if (err != null) {
                  setD(() => error = err);
                  return;
                }
                if (raffleJson != null) raffleVM.updateRaffleInList(Raffle.fromJson(raffleJson));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              icon: const Icon(Icons.replay),
              label: const Text('Reprogramar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _close(BuildContext context) async {
    final vm = context.read<WinnerViewModel>();
    final reason = await askReason(context, 'Cerrar el gran premio sin ganador', hint: 'Ej: así lo indican las condiciones de la rifa', confirmLabel: 'Cerrar sorteo');
    if (reason == null) return;
    final (err, _) = await vm.saveMainDrawDecision(record.id, {'decision': 'CERRAR', 'note': reason});
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppTheme.dangerRose, content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = record.winnerDetails;
    final rows = <(String, String)>[
      ('Resultado lotería', record.lotteryResult.isNotEmpty ? record.lotteryResult : record.winningNumber),
      ('Número ganador', record.winningNumber),
      if (record.prizeDescription.isNotEmpty) ('Premio', record.prizeDescription),
      if (record.totalPrizePaid > 0) ('Valor', currency.format(record.totalPrizePaid)),
      if (record.isWinner && w != null) ...[
        ('Ganador', w.buyerName),
        if (w.buyerPhone.isNotEmpty) ('Teléfono', w.buyerPhone),
        ('Asesor', w.advisorName),
        ('Pagado', currency.format(w.totalPaid)),
        if (record.matchType == 'COMBINADO') ('Tipo', 'Combinado'),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (record.isWinner ? AppTheme.secondaryEmerald : Colors.grey).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            record.isWinner ? '🎉 Hay ganador' : 'Sin ganador: ${record.noWinnerReason}',
            style: TextStyle(fontWeight: FontWeight.bold, color: record.isWinner ? Colors.green.shade800 : Colors.grey.shade800),
          ),
        ),
        const SizedBox(height: 8),
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$label: ', style: TextStyle(color: Colors.grey[700])),
              TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ])),
          ),
        if (record.isWinner) ...[
          const SizedBox(height: 8),
          PrizeDeliveryInfo(record: record, isAdmin: isAdmin),
        ],
        if (!record.isWinner && record.decisionType == 'CERRADO') ...[
          const SizedBox(height: 8),
          Text('🔒 Sorteo cerrado sin ganador: ${record.decision?['note'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('Decidió ${record.decision?['by'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
        if (!record.isWinner && record.decision == null) ...[
          const SizedBox(height: 10),
          Text(
            isAdmin ? '¿Qué hacer con el gran premio?' : 'La administración definirá si el gran premio se vuelve a jugar.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _reschedule(context),
                  icon: const Icon(Icons.replay),
                  label: const Text('Volver a jugar en otra fecha'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _close(context),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Cerrar sin ganador'),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

/// Who received a prize; admins register (or undo) the delivery. Used for main and weekly draws.
class PrizeDeliveryInfo extends StatelessWidget {
  final WinnerRecord record;
  final bool isAdmin;

  const PrizeDeliveryInfo({super.key, required this.record, required this.isAdmin});

  Future<void> _register(BuildContext context) async {
    final w = record.winnerDetails;
    final nameCtrl = TextEditingController(text: w?.buyerName ?? '');
    final docCtrl = TextEditingController();
    final methodCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime date = DateTime.now();
    String? error;
    final vm = context.read<WinnerViewModel>();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Registrar entrega del premio'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: nameCtrl, decoration: const InputDecoration(labelText: 'Recibió *', prefixIcon: Icon(Icons.person))),
                  const SizedBox(height: 10),
                  TextField(
                    controller: docCtrl,
                    decoration: const InputDecoration(labelText: 'Cédula de quien recibió', prefixIcon: Icon(Icons.badge_outlined)),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: Text('Fecha de entrega: ${DateFormat('dd/MM/yyyy').format(date)}'),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setDialogState(() => date = picked);
                    },
                  ),
                  TextField(
                    controller: methodCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Forma de entrega', hintText: 'Ej: Efectivo, transferencia, entrega física'),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: noteCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Observación')),
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
            ElevatedButton(
              onPressed: () async {
                final result = await vm.savePrizeDelivery(record.id, {
                  'receivedBy': nameCtrl.text.trim(),
                  'receivedDocument': docCtrl.text.trim(),
                  'deliveredOn': DateFormat('yyyy-MM-dd').format(date),
                  'method': methodCtrl.text.trim(),
                  'note': noteCtrl.text.trim(),
                });
                if (result != null) {
                  setDialogState(() => error = result);
                } else if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Guardar entrega'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = record.prizeDelivery;
    if (d == null) {
      return Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
            child: Text('Premio pendiente de entrega',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
          ),
          if (isAdmin)
            OutlinedButton.icon(
              onPressed: () => _register(context),
              icon: const Icon(Icons.handshake_outlined, size: 18),
              label: const Text('Registrar entrega'),
            ),
        ],
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.secondaryEmerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.secondaryEmerald.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('✅ Premio entregado el ${_day(d['deliveredOn'] ?? '')}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
              'Recibió: ${d['receivedBy'] ?? ''}${(d['receivedDocument'] ?? '').toString().isNotEmpty ? ' • C.C. ${d['receivedDocument']}' : ''}'),
          if ((d['method'] ?? '').toString().isNotEmpty) Text('Forma: ${d['method']}'),
          if ((d['note'] ?? '').toString().isNotEmpty) Text('Obs.: ${d['note']}'),
          Text('Registró: ${d['registeredBy'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          if (isAdmin)
            TextButton(
              onPressed: () async {
                final err = await context.read<WinnerViewModel>().savePrizeDelivery(record.id, {'cancel': true});
                if (err != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                }
              },
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
              child: const Text('Deshacer entrega'),
            ),
        ],
      ),
    );
  }
}
