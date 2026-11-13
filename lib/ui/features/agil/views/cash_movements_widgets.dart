import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/admin_cash/views/cash_widgets.dart';

/// Una caja: el efectivo o una cuenta de transferencia, con su saldo ("debe haber").
class CashBox {
  final String key;
  final String label;
  final num balance;
  const CashBox(this.key, this.label, this.balance);
}

/// Formulario para mover dinero de una caja a otra: origen, destino, valor, fecha, justificación y observación.
class MovementDialog extends StatefulWidget {
  final ApiService api;
  final List<CashBox> boxes;
  final String? initialFrom;

  const MovementDialog(
      {super.key, required this.api, required this.boxes, this.initialFrom});

  @override
  State<MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<MovementDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String? _from;
  String? _to;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _from = widget.boxes.any((b) => b.key == widget.initialFrom)
        ? widget.initialFrom
        : null;
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    _note.dispose();
    super.dispose();
  }

  num get _value =>
      num.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  CashBox? _box(String? key) =>
      widget.boxes.where((b) => b.key == key).firstOrNull;

  Future<void> _save() async {
    if (_from == null || _to == null)
      return setState(
          () => _error = 'Seleccione la caja de origen y la de destino.');
    if (_from == _to)
      return setState(
          () => _error = 'El origen y el destino deben ser distintos.');
    if (_value <= 0)
      return setState(() => _error = 'Escriba el valor del traslado.');
    if (_reason.text.trim().length < 5)
      return setState(
          () => _error = 'Escriba la justificación (mínimo 5 caracteres).');
    final src = _box(_from);
    if (src != null && _value > src.balance) {
      return setState(() => _error =
          'La caja de origen solo tiene ${cashCurrency.format(src.balance)}.');
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.agilCreateMovement(
        from: _from!,
        to: _to!,
        amount: _value,
        date: DateFormat('yyyy-MM-dd').format(_date),
        reason: _reason.text.trim(),
        note: _note.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  Widget _dropdown(String label, String? value, ValueChanged<String?> onChanged,
      {String? exclude}) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: value,
      decoration: InputDecoration(
          labelText: label, border: const OutlineInputBorder(), isDense: true),
      items: [
        for (final b in widget.boxes.where((b) => b.key != exclude))
          DropdownMenuItem(
              value: b.key,
              child: Text('${b.label}  (${cashCurrency.format(b.balance)})',
                  overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final src = _box(_from);
    return AlertDialog(
      title:
          const Text('Trasladar entre cajas', style: TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Mueve dinero de una caja a otra. Queda el registro con origen, destino, fecha, justificación y observación.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                const SizedBox(height: 12),
                _dropdown(
                    'Caja de origen *', _from, (v) => setState(() => _from = v),
                    exclude: _to),
                const SizedBox(height: 10),
                _dropdown(
                    'Caja de destino *', _to, (v) => setState(() => _to = v),
                    exclude: _from),
                const SizedBox(height: 10),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Valor a trasladar *',
                    prefixIcon: const Icon(Icons.attach_money),
                    border: const OutlineInputBorder(),
                    helperText: src == null
                        ? null
                        : 'Disponible en ${src.label}: ${cashCurrency.format(src.balance)}',
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now());
                    if (picked != null) setState(() => _date = picked);
                  },
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(
                      'Fecha del traslado: ${DateFormat('dd/MM/yyyy').format(_date)}'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _reason,
                  maxLines: 2,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Justificación *',
                    hintText:
                        'Ej: consignación del efectivo, retiro para pagar un premio…',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: _note,
                  maxLines: 2,
                  maxLength: 300,
                  decoration: const InputDecoration(
                      labelText: 'Observación (opcional)',
                      border: OutlineInputBorder()),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppTheme.dangerRose,
                            fontWeight: FontWeight.w600)),
                  ),
              ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.swap_horiz),
          label: const Text('Registrar traslado'),
        ),
      ],
    );
  }
}

/// Pestaña «Gastos y traslados»: consulta los gastos y los traslados entre cajas del rango de fechas (y de una caja si se elige).
class CashMovementsTab extends StatefulWidget {
  final ApiService api;
  final String from; // AAAA-MM-DD o vacío
  final String to;
  final List<CashBox> boxes;
  final bool readOnly;
  final VoidCallback
      onChanged; // para que el resumen se vuelva a cargar tras anular o crear
  final VoidCallback onNewMovement;

  const CashMovementsTab({
    super.key,
    required this.api,
    required this.from,
    required this.to,
    required this.boxes,
    required this.readOnly,
    required this.onChanged,
    required this.onNewMovement,
  });

  @override
  State<CashMovementsTab> createState() => CashMovementsTabState();
}

class CashMovementsTabState extends State<CashMovementsTab> {
  String _kind = 'traslados'; // 'traslados' | 'gastos'
  String _account = '';
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  num _total = 0;
  int _pageSize = 10;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void didUpdateWidget(covariant CashMovementsTab old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to) reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_kind == 'gastos') {
        final res = await widget.api
            .agilExpenses(account: _account, from: widget.from, to: widget.to);
        _rows = ((res['expenses'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _total = (res['total'] as num?) ?? 0;
      } else {
        final res = await widget.api.agilMovements({
          'account': _account,
          'from': widget.from,
          'to': widget.to,
          'q': _search.text.trim()
        });
        _rows = ((res['movements'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _total = (res['total'] as num?) ?? 0;
      }
      _page = 0;
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _void(Map<String, dynamic> row) async {
    final isExpense = _kind == 'gastos';
    final reason = await askReason(
        context, isExpense ? 'Anular gasto' : 'Anular traslado',
        hint: isExpense
            ? 'Ej: gasto registrado por error'
            : 'Ej: traslado registrado por error',
        confirmLabel: 'Anular');
    if (reason == null) return;
    try {
      if (isExpense) {
        await widget.api.agilVoidExpense('${row['id']}', reason);
      } else {
        await widget.api.agilVoidMovement('${row['id']}', reason);
      }
      await reload();
      widget.onChanged();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.red, content: Text('$e')));
    }
  }

  Widget _rowCard(Map<String, dynamic> r) {
    final voided = r['voided'] != null;
    final isExpense = _kind == 'gastos';
    final amount = cashCurrency.format((r['amount'] as num?) ?? 0);
    final muted = voided ? Colors.grey : null;
    final title = isExpense
        ? '${r['accountLabel'] ?? ''}'
        : '${r['fromLabel'] ?? ''}  →  ${r['toLabel'] ?? ''}';
    final detail = isExpense
        ? '${r['reason'] ?? ''}'
        : [
            if ('${r['reason'] ?? ''}'.isNotEmpty) '${r['reason']}',
            if ('${r['note'] ?? ''}'.isNotEmpty) 'Obs.: ${r['note']}'
          ].join('\n');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(isExpense ? Icons.receipt_long_outlined : Icons.swap_horiz,
              color: voided
                  ? Colors.grey
                  : (isExpense ? AppTheme.dangerRose : AppTheme.primaryBlue)),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: muted,
                            decoration:
                                voided ? TextDecoration.lineThrough : null)),
                    if (!isExpense && r['auto'] == true)
                      const CashChip('AUTOMÁTICO · ENTREGA POR TRANSFERENCIA',
                          AppTheme.secondaryEmerald),
                    if (voided) const CashChip('ANULADO', Colors.grey),
                  ]),
              const SizedBox(height: 2),
              Text(
                  '${cashDate(r['date']?.toString())} · ${r['createdBy'] ?? ''}${isExpense && r['advisorName'] != null ? ' · ${r['advisorName']}' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              if (detail.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(detail,
                        style: TextStyle(fontSize: 12.5, color: muted))),
              if (voided)
                Text('Anulado: ${(r['voided'] as Map)['reason'] ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(amount,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: muted,
                    decoration: voided ? TextDecoration.lineThrough : null)),
            if (!widget.readOnly && !voided && !(r['auto'] == true))
              TextButton(
                  onPressed: () => _void(r),
                  child: const Text('Anular',
                      style: TextStyle(color: AppTheme.dangerRose))),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = (_rows.length / _pageSize).ceil().clamp(1, 1 << 30);
    final cur = _page.clamp(0, pages - 1);
    final shown = _rows.skip(cur * _pageSize).take(_pageSize).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<String>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(
                      value: 'traslados', label: Text('Traslados entre cajas')),
                  ButtonSegment(value: 'gastos', label: Text('Gastos'))
                ],
                selected: {_kind},
                onSelectionChanged: (v) {
                  _kind = v.first;
                  reload();
                },
              ),
              SizedBox(
                width: 230,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _account,
                  decoration: const InputDecoration(
                      labelText: 'Caja',
                      isDense: true,
                      border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Todas')),
                    for (final b in widget.boxes)
                      DropdownMenuItem(
                          value: b.key,
                          child:
                              Text(b.label, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    _account = v ?? '';
                    reload();
                  },
                ),
              ),
              if (_kind == 'traslados')
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: 'Buscar (motivo, caja…)',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                          icon: const Icon(Icons.search), onPressed: reload),
                    ),
                    onSubmitted: (_) => reload(),
                  ),
                ),
              if (!widget.readOnly)
                FilledButton.icon(
                    onPressed: widget.onNewMovement,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Trasladar entre cajas')),
            ]),
        const SizedBox(height: 8),
        Text(
            '${_rows.where((r) => r['voided'] == null).length} registros vigentes · total ${cashCurrency.format(_total)}',
            style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey[700],
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(_error!,
                          style: const TextStyle(color: AppTheme.dangerRose)))
                  : _rows.isEmpty
                      ? Center(
                          child: Text(
                              _kind == 'gastos'
                                  ? 'No hay gastos con esos filtros.'
                                  : 'No hay traslados con esos filtros.',
                              style: TextStyle(color: Colors.grey[600])))
                      : ListView(
                          children: [for (final r in shown) _rowCard(r)]),
        ),
        if (!_loading && _rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('Filas:',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              const SizedBox(width: 6),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _pageSize,
                  isDense: true,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).textTheme.bodyMedium?.color),
                  items: const [
                    DropdownMenuItem(value: 10, child: Text('10')),
                    DropdownMenuItem(value: 25, child: Text('25')),
                    DropdownMenuItem(value: 50, child: Text('50'))
                  ],
                  onChanged: (v) => setState(() {
                    _pageSize = v ?? 10;
                    _page = 0;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                  '${cur * _pageSize + 1}–${(cur * _pageSize + shown.length)} de ${_rows.length}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left),
                  onPressed:
                      cur > 0 ? () => setState(() => _page = cur - 1) : null),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: cur < pages - 1
                      ? () => setState(() => _page = cur + 1)
                      : null),
            ]),
          ),
      ]),
    );
  }
}
