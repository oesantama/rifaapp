import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/models/advisor.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';

/// Joins sorted numbers into compact ranges: [1,2,3,7] -> ["1-3", "7"].
List<String> compressNumbers(List<int> numbers) {
  final sorted = numbers.toSet().toList()..sort();
  final result = <String>[];
  for (var i = 0; i < sorted.length;) {
    var j = i;
    while (j + 1 < sorted.length && sorted[j + 1] == sorted[j] + 1) {
      j++;
    }
    result.add(sorted[i] == sorted[j] ? '${sorted[i]}' : '${sorted[i]}-${sorted[j]}');
    i = j + 1;
  }
  return result;
}

String _rangeLabel((int, int) r) => r.$1 == r.$2 ? '${r.$1}' : '${r.$1}-${r.$2}';

/// Admin dialog to give an advisor more numbers (or remove some), e.g. when they ask for more.
class AssignNumbersDialog extends StatefulWidget {
  final Advisor advisor;

  const AssignNumbersDialog({super.key, required this.advisor});

  static Future<void> show(BuildContext context, Advisor advisor) =>
      showDialog(context: context, builder: (_) => AssignNumbersDialog(advisor: advisor));

  @override
  State<AssignNumbersDialog> createState() => _AssignNumbersDialogState();
}

class _AssignNumbersDialogState extends State<AssignNumbersDialog> {
  late List<(int, int)> _ranges = widget.advisor.mode == 'ASSIGNED' ? [...widget.advisor.parsedRanges] : [];
  late final _quantityCtrl = TextEditingController(text: '${widget.advisor.rangeRequest?.quantity ?? 10}');
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  int get _total => _ranges.fold(0, (sum, r) => sum + r.$2 - r.$1 + 1);

  /// Numbers already given to other advisors of the company.
  List<(int, int)> get _takenByOthers => [
        for (final a in context.read<AdvisorViewModel>().advisors)
          if (a.id != widget.advisor.id && a.mode == 'ASSIGNED') ...a.parsedRanges,
      ];

  bool _inAny(int n, List<(int, int)> ranges) => ranges.any((r) => n >= r.$1 && n <= r.$2);

  void _add(List<(int, int)> added) {
    final sorted = [..._ranges, ...added]..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final r in sorted) {
      if (merged.isNotEmpty && r.$1 <= merged.last.$2 + 1) {
        final last = merged.removeLast();
        merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
      } else {
        merged.add(r);
      }
    }
    setState(() {
      _ranges = merged;
      _error = null;
    });
  }

  /// Adds the next free numbers of the current raffle (not assigned to anyone yet).
  void _suggestNext() {
    final quantity = int.tryParse(_quantityCtrl.text.trim()) ?? 0;
    if (quantity < 1) {
      setState(() => _error = 'Indique cuántos números quiere agregar.');
      return;
    }
    final tickets = context.read<TicketViewModel>().tickets;
    final allNumbers = <int>{
      for (final t in tickets)
        if (t.numbers.isEmpty) t.ticketNumber else ...t.numbers.map(int.tryParse).whereType<int>(),
    }.toList()
      ..sort();
    if (allNumbers.isEmpty) {
      setState(() => _error = 'No hay boletas cargadas en la rifa actual para sugerir números.');
      return;
    }
    final taken = [..._takenByOthers, ..._ranges];
    final free = allNumbers.where((n) => !_inAny(n, taken)).take(quantity).toList();
    if (free.isEmpty) {
      setState(() => _error = 'Ya no quedan números libres en la rifa actual.');
      return;
    }
    _add(compressNumbers(free).map(Advisor.parseRange).whereType<(int, int)>().toList());
    if (free.length < quantity) {
      setState(() => _error = 'Solo quedaban ${free.length} números libres; se agregaron todos.');
    }
  }

  void _addManual() {
    final from = int.tryParse(_fromCtrl.text.trim());
    final to = int.tryParse(_toCtrl.text.trim()) ?? from;
    if (from == null || to == null || to < from) {
      setState(() => _error = 'Escriba un número inicial y uno final válidos (ej: 100 hasta 149).');
      return;
    }
    final clash = _takenByOthers.where((r) => from <= r.$2 && r.$1 <= to).firstOrNull;
    if (clash != null) {
      final owner = context
          .read<AdvisorViewModel>()
          .advisors
          .firstWhere((a) => a.id != widget.advisor.id && a.parsedRanges.contains(clash));
      setState(() => _error = 'Los números ${_rangeLabel(clash)} ya son de ${owner.name}.');
      return;
    }
    _fromCtrl.clear();
    _toCtrl.clear();
    _add([(from, to)]);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final vm = context.read<AdvisorViewModel>();
    final ok = await vm.updateAdvisor(widget.advisor.id, {
      'mode': 'ASSIGNED',
      'assignedTicketRanges': _ranges.map(_rangeLabel).toList(),
    });
    if (!mounted) return;
    if (ok) {
      await vm.loadAdvisors(); // refresh stats and the pending request badge
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Números de ${widget.advisor.name} actualizados: $_total en total')),
      );
    } else {
      setState(() {
        _saving = false;
        _error = vm.lastError ?? 'No se pudo guardar.';
      });
    }
  }

  Future<void> _dismissRequest() async {
    final ok = await context.read<AdvisorViewModel>().dismissRangeRequest(widget.advisor.id);
    if (!mounted) return;
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.advisor.rangeRequest;
    final digitsOnly = [FilteringTextInputFormatter.digitsOnly];

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Asignar números'),
          Text(widget.advisor.name, style: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.normal)),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (request != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Solicita ${request.quantity} boletas más',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                      if (request.note.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('"${request.note}"', style: const TextStyle(fontSize: 13)),
                      ],
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _saving ? null : _dismissRequest,
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: Colors.orange.shade900),
                          child: const Text('Descartar solicitud'),
                        ),
                      ),
                    ],
                  ),
                ),
              const Text('Números asignados', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if (_ranges.isEmpty)
                Text('Aún no tiene números. Agréguelos abajo.', style: TextStyle(color: Colors.grey[600], fontSize: 13))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in _ranges)
                      InputChip(
                        label: Text(_rangeLabel(r), style: const TextStyle(fontWeight: FontWeight.w600)),
                        onDeleted: () => setState(() => _ranges = [..._ranges]..remove(r)),
                        deleteButtonTooltipMessage: 'Quitar',
                      ),
                  ],
                ),
              const SizedBox(height: 6),
              Text('Total: $_total números', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              const Divider(height: 28),
              const Text('Agregar los siguientes números libres', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _quantityCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: digitsOnly,
                      decoration: const InputDecoration(labelText: 'Cantidad', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: _suggestNext,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Agregar libres'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('O un rango específico', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fromCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: digitsOnly,
                      decoration: const InputDecoration(labelText: 'Desde', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _toCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: digitsOnly,
                      decoration: const InputDecoration(labelText: 'Hasta', isDense: true, border: OutlineInputBorder()),
                      onSubmitted: (_) => _addManual(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(onPressed: _addManual, icon: const Icon(Icons.add), tooltip: 'Agregar rango'),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Son los números impresos en las boletas. El asesor solo ve y vende las boletas que tengan alguno de estos números.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: AppTheme.dangerRose, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Admin: advisors waiting for more numbers, shown on top of the advisors list.
class RangeRequestsBanner extends StatelessWidget {
  const RangeRequestsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final pending = context.watch<AdvisorViewModel>().pendingRangeRequests;
    if (pending.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Colors.orange.shade50,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active, color: Colors.orange.shade800, size: 20),
                const SizedBox(width: 8),
                Text('Solicitudes de más boletas',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
              ],
            ),
            for (final adv in pending)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('${adv.name} pide ${adv.rangeRequest!.quantity} boletas más',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: adv.rangeRequest!.note.isNotEmpty ? Text(adv.rangeRequest!.note) : null,
                trailing: FilledButton(
                  onPressed: () => AssignNumbersDialog.show(context, adv),
                  child: const Text('Asignar'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Assigned numbers on the advisor card (admin view).
class AdvisorNumbersSummary extends StatelessWidget {
  final Advisor advisor;

  const AdvisorNumbersSummary({super.key, required this.advisor});

  @override
  Widget build(BuildContext context) {
    final request = advisor.rangeRequest;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.pin_outlined, size: 16, color: Colors.grey[600]),
          Text(
            advisor.worksWithAssignedNumbers
                ? 'Números: ${advisor.assignedTicketRanges.join(', ')} (${advisor.assignedNumbersCount})'
                : advisor.mode == 'ASSIGNED'
                    ? 'Sin números asignados'
                    : 'Vende todas las boletas (pool general)',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          if (request != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
              child: Text('Pide ${request.quantity} más',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
            ),
          if (advisor.mode == 'ASSIGNED')
            TextButton.icon(
              onPressed: () => AssignNumbersDialog.show(context, advisor),
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Asignar más'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
        ],
      ),
    );
  }
}

/// Advisor view (Boletas): their numbers, how many are still free, and a button to ask for more.
class AdvisorNumbersBar extends StatelessWidget {
  const AdvisorNumbersBar({super.key});

  Future<void> _request(BuildContext context) async {
    final quantityCtrl = TextEditingController(text: '10');
    final noteCtrl = TextEditingController();
    String? error;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Solicitar más boletas'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: quantityCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: '¿Cuántas boletas más necesita?'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLength: 300,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Mensaje para el administrador (opcional)'),
                ),
                if (error != null) Text(error!, style: const TextStyle(color: AppTheme.dangerRose)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final quantity = int.tryParse(quantityCtrl.text.trim()) ?? 0;
                if (quantity < 1) {
                  setDialogState(() => error = 'Indique cuántas boletas necesita.');
                  return;
                }
                final result = await context.read<AuthViewModel>().requestMoreTickets(quantity, noteCtrl.text.trim());
                if (result != null) {
                  setDialogState(() => error = result);
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Solicitud enviada. El administrador le asignará más números.')),
                  );
                }
              },
              child: const Text('Enviar solicitud'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authVM = context.watch<AuthViewModel>();
    final adv = authVM.activeAdvisor;
    if (!authVM.isAsesor || adv == null || adv.mode != 'ASSIGNED') return const SizedBox.shrink();
    final available =
        context.watch<TicketViewModel>().tickets.where((t) => t.status == 'DISPONIBLE' && adv.coversTicket(t)).length;
    final request = adv.rangeRequest;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      color: AppTheme.primaryBlue.withValues(alpha: 0.06),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Sus números: ', style: TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: adv.assignedTicketRanges.isEmpty ? 'ninguno aún' : adv.assignedTicketRanges.join(', ')),
              TextSpan(text: '  •  $available disponibles', style: TextStyle(color: Colors.grey[700])),
            ]),
            style: const TextStyle(fontSize: 13),
          ),
          if (request != null)
            Chip(
              avatar: Icon(Icons.hourglass_top, size: 16, color: Colors.orange.shade800),
              label: Text('Pidió ${request.quantity} más • esperando'),
              visualDensity: VisualDensity.compact,
            )
          else
            FilledButton.tonalIcon(
              onPressed: () => _request(context),
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Solicitar más'),
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
        ],
      ),
    );
  }
}
