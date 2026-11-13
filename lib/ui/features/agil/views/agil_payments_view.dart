import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/file_picker_helper.dart';
import 'package:rifaapp/ui/core/utils/image_compress.dart';
import 'package:rifaapp/ui/core/utils/file_saver.dart';
import 'package:rifaapp/ui/features/admin_cash/views/cash_widgets.dart';

const _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Menú "Pagos" (solo administrador):
///  • Resumen por cuenta: cuánto hay en cada cuenta, cuánto está legalizado y cuánto falta, y el efectivo.
///  • Detalle: pagos y abonos con filtros, estado AGIL, Excel, lotes y carga del Excel devuelto (SUBIDO).
class AgilPaymentsView extends StatefulWidget {
  /// true = la ve un asesor de punto/integral con permiso: solo el resumen de la caja (sin AGIL ni Excel).
  final bool advisorMode;

  /// Solo lectura (asesor con la parte «Pagos» del menú): sin descargas, lotes, marcas ni gastos.
  final bool readOnly;
  final bool canRegisterExpenses;

  const AgilPaymentsView(
      {super.key,
      this.advisorMode = false,
      this.canRegisterExpenses = false,
      this.readOnly = false});

  @override
  State<AgilPaymentsView> createState() => _AgilPaymentsViewState();
}

class _AgilPaymentsViewState extends State<AgilPaymentsView>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _search = TextEditingController();
  late final TabController _tabs = TabController(length: 2, vsync: this);

  DateTime? _from;
  DateTime? _to;
  String _agil = '';
  String _method = '';
  String _settled = '';
  String _account = '';
  String _accountLabel = '';

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _payments = [];
  Map<String, dynamic> _totals = {};
  Map<String, dynamic> _summary = {};
  int _total = 0;
  bool _truncated = false;
  final Set<String> _selected = {};
  bool _busy = false;

  /// Bloque de filtros y acciones del detalle: cerrado por defecto para darle el espacio a la tabla.
  bool _filtersOpen = false;

  static final _day = DateFormat('yyyy-MM-dd');
  static final _shown = DateFormat('dd/MM/yyyy');

  // Solo lo de la rifa actual (sus cuentas y sus pagos)
  String _raffleId = '';

  Map<String, String> get _dateFilters => {
        if (_raffleId.isNotEmpty) 'raffleId': _raffleId,
        if (_from != null) 'from': _day.format(_from!),
        if (_to != null) 'to': _day.format(_to!),
      };

  Map<String, String> get _filters => {
        ..._dateFilters,
        'agil': _agil,
        'method': _method,
        'settled': _settled,
        'account': _account,
        'q': _search.text.trim(),
      };

  @override
  void initState() {
    super.initState();
    _raffleId = context.read<RaffleViewModel>().selectedRaffle?.id ?? '';
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.advisorMode
            ? Future.value(<String, dynamic>{})
            : _api.agilPayments(_filters),
        _api.agilSummary(_dateFilters),
      ]);
      if (!mounted) return;
      final res = results[0];
      setState(() {
        _payments = ((res['payments'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _totals = Map<String, dynamic>.from(res['totals'] ?? {});
        _total = (res['total'] as num?)?.toInt() ?? _payments.length;
        _truncated = res['truncated'] == true;
        _summary = Map<String, dynamic>.from(results[1]);
        _selected.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor:
            error ? AppTheme.dangerRose : AppTheme.secondaryEmerald,
        content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? now,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() => isFrom ? _from = picked : _to = picked);
    _load();
  }

  /// Desde una tarjeta del resumen: abre el detalle ya filtrado.
  void _openDetail(
      {String account = '', String accountLabel = '', String method = ''}) {
    setState(() {
      _account = account;
      _accountLabel = accountLabel;
      _method = method;
      _agil = '';
      _settled = '';
      _search.clear();
    });
    _tabs.animateTo(1);
    _load();
  }

  Future<void> _export() => _run(() async {
        final bytes = await _api.agilExport(_filters);
        await saveAndDownloadBytes(
            'Pagos_${_day.format(DateTime.now())}.xlsx', bytes,
            mimeType: _xlsxMime);
        _toast('Excel descargado ($_total pagos).');
      });

  /// Crea el lote con los pagos legalizados aún no enviados y descarga su Excel.
  Future<void> _createBatch() async {
    final ready = (_totals['readyToSend'] as num?)?.toInt() ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generar lote para AGIL'),
        content: Text(
          'Se creará un lote con los pagos legalizados por el administrador que aún no se han enviado'
          '${_from != null || _to != null ? ' dentro del rango de fechas elegido' : ''}.\n\n'
          'Se descargará el Excel. Cuando lo suban a AGIL, el archivo devuelto con "SUBIDO" en el nombre los marca como subidos.'
          '${ready > 0 ? '\n\nEn el filtro actual hay $ready pago(s) listos.' : ''}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Generar y descargar')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final res = await _api.agilCreateBatch(
        from: _from != null ? _day.format(_from!) : '',
        to: _to != null ? _day.format(_to!) : '',
      );
      final batch = Map<String, dynamic>.from(res['batch'] ?? {});
      final bytes = await _api.agilBatchFile('${batch['id']}');
      await saveAndDownloadBytes('${batch['fileName']}', bytes,
          mimeType: _xlsxMime);
      _toast('Lote ${batch['number']} generado: ${batch['count']} pagos.');
      await _load();
    });
  }

  Future<void> _uploadReturned() async {
    final bytes = await pickFileBytes(allowedExtensions: const ['xlsx']);
    if (bytes == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar pagos como SUBIDOS'),
        content: const Text(
          'Todos los pagos que estén en este archivo se marcarán como SUBIDOS en AGIL.\n\n'
          'Use únicamente el Excel que descargó o recibió por WhatsApp y que ya subieron a AGIL.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí, marcar como subidos')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final res = await _api.agilUpload('manual_SUBIDO.xlsx', bytes);
      _toast('${res['marked'] ?? 0} pagos marcados como SUBIDO'
          '${(res['already'] ?? 0) > 0 ? ' • ${res['already']} ya lo estaban' : ''}'
          '${(res['notFound'] ?? 0) > 0 ? ' • ${res['notFound']} no encontrados' : ''}');
      await _load();
    });
  }

  Future<void> _markSelected(String status) async {
    if (_selected.isEmpty) return;
    await _run(() async {
      final res = await _api.agilMark(_selected.toList(), status);
      _toast(
          '${res['changed'] ?? 0} pagos marcados como ${status == 'SUBIDO' ? 'SUBIDOS' : 'PENDIENTES'}.');
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    // Al cambiar de rifa se recarga con las cuentas y pagos de la nueva
    final currentRaffleId =
        context.watch<RaffleViewModel>().selectedRaffle?.id ?? '';
    if (currentRaffleId != _raffleId) {
      _raffleId = currentRaffleId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
          isMobile ? 10 : 16, isMobile ? 10 : 14, isMobile ? 10 : 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.advisorMode) ...[
            Row(children: [
              const Icon(Icons.receipt_long, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              Text('Caja',
                  style: TextStyle(
                      fontSize: isMobile ? 18 : 20,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Actualizar'),
            ]),
            _dateButtons(),
          ] else ...[
            // Título, totales, fechas, actualizar y filtros: todo en un solo bloque expandible
            _controlsBlock(isMobile),
            TabBar(
              controller: _tabs,
              dividerHeight: 0.5,
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              tabs: const [
                Tab(
                    height: 34,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.account_balance_outlined, size: 16),
                      SizedBox(width: 6),
                      Text('Resumen por cuenta')
                    ])),
                Tab(
                    height: 34,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.table_rows_outlined, size: 16),
                      SizedBox(width: 6),
                      Text('Detalle de pagos')
                    ])),
              ],
            ),
          ],
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!,
                              style:
                                  const TextStyle(color: AppTheme.dangerRose),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar')),
                        ]),
                      )
                    : (widget.advisorMode
                        ? _summaryTab()
                        : TabBarView(
                            controller: _tabs,
                            children: [_summaryTab(), _detailTab(isMobile)])),
          ),
        ],
      ),
    );
  }

  /// Rango de fechas (aplica al resumen y al detalle).
  Widget _dateButtons() {
    final compact = ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 10)));
    return Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            style: compact,
            onPressed: () => _pickDate(true),
            icon: const Icon(Icons.event, size: 16),
            label: Text(
                _from == null ? 'Desde' : 'Desde ${_shown.format(_from!)}'),
          ),
          OutlinedButton.icon(
            style: compact,
            onPressed: () => _pickDate(false),
            icon: const Icon(Icons.event, size: 16),
            label: Text(
                _to == null ? 'Hasta hoy' : 'Hasta ${_shown.format(_to!)}'),
          ),
          if (_from != null || _to != null)
            IconButton(
              tooltip: 'Quitar fechas',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                setState(() {
                  _from = null;
                  _to = null;
                });
                _load();
              },
            ),
        ]);
  }

  // ---------------------------------------------------------------------------
  // Resumen por cuenta
  // ---------------------------------------------------------------------------
  num _n(dynamic v) => (v as num?) ?? 0;

  /// Gastos y saldo de una cuenta (o del efectivo) con los botones para registrarlos y verlos.
  List<Widget> _expenseBlock(Map<String, dynamic> m,
      {required String account, required String label}) {
    final expenses = Map<String, dynamic>.from(m['expenses'] ?? {});
    final count = _n(expenses['count']).toInt();
    final balance = _n(m['balance']);
    return [
      const Divider(height: 20),
      _line('Gastos', _n(expenses['amount']), count, AppTheme.dangerRose),
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: (balance >= 0 ? Colors.indigo : AppTheme.dangerRose)
              .withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Expanded(
              child: Text('Debe haber (legalizado − gastos)',
                  style:
                      TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
          Text(cashCurrency.format(balance),
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: balance >= 0 ? Colors.indigo : AppTheme.dangerRose)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 8, runSpacing: 4, children: [
          if (!widget.readOnly &&
              (!widget.advisorMode || widget.canRegisterExpenses))
            OutlinedButton.icon(
              onPressed: () => _openExpenseDialog(
                  account: account, label: label, balance: balance),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Registrar gasto'),
            ),
          if (count > 0)
            TextButton.icon(
              onPressed: () =>
                  _openExpensesList(account: account, label: label),
              icon: const Icon(Icons.list_alt, size: 18),
              label: Text('Ver gastos ($count)'),
            ),
        ]),
      ),
    ];
  }

  Future<void> _openExpenseDialog(
      {required String account,
      required String label,
      required num balance}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ExpenseDialog(
          api: _api, account: account, label: label, balance: balance),
    );
    if (saved == true) {
      _toast('Gasto registrado.');
      await _load();
    }
  }

  Future<void> _openExpensesList(
      {required String account, required String label}) async {
    final changed = await showDialog<bool>(
        context: context,
        builder: (_) => ExpensesListDialog(
            api: _api,
            account: account,
            label: label,
            allowVoid: !widget.advisorMode && !widget.readOnly));
    if (changed == true) await _load();
  }

  Widget _summaryTab() {
    final grand = Map<String, dynamic>.from(_summary['grand'] ?? {});
    final accounts = ((_summary['accounts'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final cash = Map<String, dynamic>.from(_summary['cash'] ?? {});
    return LayoutBuilder(builder: (context, c) {
      const gap = 12.0;
      final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
      final cardW = (c.maxWidth - 32 - gap * (cols - 1)) / cols;
      final kCols = c.maxWidth >= 1000 ? 5 : (c.maxWidth >= 640 ? 3 : 2);
      return ListView(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
        children: [
          Wrap(spacing: gap, runSpacing: gap, children: [
            _bigKpi('TOTAL GENERAL', _n(grand['total']), AppTheme.primaryBlue,
                Icons.account_balance_wallet_outlined, c.maxWidth, kCols),
            _bigKpi(
                'LEGALIZADO',
                _n(grand['legalized']),
                AppTheme.secondaryEmerald,
                Icons.verified_outlined,
                c.maxWidth,
                kCols),
            _bigKpi(
                'POR LEGALIZAR',
                _n(grand['pending']),
                Colors.orange.shade800,
                Icons.hourglass_bottom,
                c.maxWidth,
                kCols),
            _bigKpi('GASTOS', _n(grand['expenses']), AppTheme.dangerRose,
                Icons.receipt_long_outlined, c.maxWidth, kCols),
            _bigKpi(
                'DEBE HABER (legalizado − gastos)',
                _n(grand['balance']),
                _n(grand['balance']) >= 0 ? Colors.indigo : AppTheme.dangerRose,
                Icons.savings_outlined,
                c.maxWidth,
                kCols),
          ]),
          const SizedBox(height: 18),
          const Text('Cuentas de transferencia',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
              'Lo que ha llegado a cada cuenta hasta la fecha, lo que el administrador ya validó en Caja y lo que falta por validar.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 10),
          if (accounts.isEmpty)
            Text('Aún no hay transferencias ni cuentas configuradas.',
                style: TextStyle(
                    color: Colors.grey[600], fontStyle: FontStyle.italic)),
          Wrap(spacing: gap, runSpacing: gap, children: [
            for (final a in accounts)
              SizedBox(width: cardW, child: _accountCard(a))
          ]),
          const SizedBox(height: 18),
          const Text('Efectivo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
              'Legalizado = el administrador ya lo recibió. Pendiente = sigue en poder de cada asesor o en una entrega por confirmar.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 10),
          SizedBox(
              width: math.min(c.maxWidth - 32, cols == 1 ? cardW : cardW * 1.6),
              child: _cashCard(cash)),
        ],
      );
    });
  }

  Widget _bigKpi(String title, num value, Color color, IconData icon,
      double maxW, int cols) {
    final w = (maxW - 32 - 12 * (cols - 1)) / cols;
    return Container(
      width: w,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
            FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(cashCurrency.format(value),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold))),
          ]),
        ),
      ]),
    );
  }

  Widget _line(String label, num amount, int count, Color color,
          {bool small = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(label, style: TextStyle(fontSize: small ? 12 : 13.5))),
          Text('${cashCurrency.format(amount)}  ',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: small ? 12.5 : 14,
                  color: color)),
          SizedBox(
              width: 62,
              child: Text('$count pago${count == 1 ? '' : 's'}',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
        ]),
      );

  Widget _accountCard(Map<String, dynamic> a) {
    final total = _n(a['total']);
    final legalized = Map<String, dynamic>.from(a['legalized'] ?? {});
    final pending = Map<String, dynamic>.from(a['pending'] ?? {});
    final rejected = Map<String, dynamic>.from(a['rejected'] ?? {});
    final uploaded = Map<String, dynamic>.from(a['uploaded'] ?? {});
    final progress = total <= 0
        ? 0.0
        : (_n(legalized['amount']) / total).clamp(0, 1).toDouble();
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.advisorMode
            ? null
            : () => _openDetail(
                account: '${a['key']}',
                accountLabel: '${a['label']}',
                method: 'TRANSFERENCIA'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.account_balance,
                  size: 20, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('${a['label']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14.5))),
              Icon(Icons.chevron_right, color: Colors.grey[500]),
            ]),
            const SizedBox(height: 8),
            Text(cashCurrency.format(total),
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            Text(
                'total hasta la fecha • ${a['count']} pago${a['count'] == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.orange.shade100,
                  color: AppTheme.secondaryEmerald),
            ),
            _line('Legalizado', _n(legalized['amount']),
                _n(legalized['count']).toInt(), AppTheme.secondaryEmerald),
            _line('Por legalizar', _n(pending['amount']),
                _n(pending['count']).toInt(), Colors.orange.shade800),
            if (_n(rejected['count']) > 0)
              _line('Rechazado (no suma)', _n(rejected['amount']),
                  _n(rejected['count']).toInt(), AppTheme.dangerRose,
                  small: true),
            if (_n(uploaded['count']) > 0)
              _line('Ya subido a AGIL', _n(uploaded['amount']),
                  _n(uploaded['count']).toInt(), Colors.blueGrey,
                  small: true),
            ..._expenseBlock(a, account: '${a['key']}', label: '${a['label']}'),
          ]),
        ),
      ),
    );
  }

  Widget _cashCard(Map<String, dynamic> cash) {
    final legalized = Map<String, dynamic>.from(cash['legalized'] ?? {});
    final pending = Map<String, dynamic>.from(cash['pending'] ?? {});
    final uploaded = Map<String, dynamic>.from(cash['uploaded'] ?? {});
    final total = _n(cash['total']);
    final progress = total <= 0
        ? 0.0
        : (_n(legalized['amount']) / total).clamp(0, 1).toDouble();
    final advisors = ((cash['byAdvisor'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap:
            widget.advisorMode ? null : () => _openDetail(method: 'EFECTIVO'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.payments_outlined,
                  size: 20, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Efectivo',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14.5))),
              Icon(Icons.chevron_right, color: Colors.grey[500]),
            ]),
            const SizedBox(height: 8),
            Text(cashCurrency.format(total),
                style:
                    const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            Text('total hasta la fecha • ${cash['count'] ?? 0} pagos',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.orange.shade100,
                  color: AppTheme.secondaryEmerald),
            ),
            _line(
                'Legalizado (recibido por el administrador)',
                _n(legalized['amount']),
                _n(legalized['count']).toInt(),
                AppTheme.secondaryEmerald),
            _line('Por legalizar (en poder de asesores)', _n(pending['amount']),
                _n(pending['count']).toInt(), Colors.orange.shade800),
            if (_n(uploaded['count']) > 0)
              _line('Ya subido a AGIL', _n(uploaded['amount']),
                  _n(uploaded['count']).toInt(), Colors.blueGrey,
                  small: true),
            if (_n(cash['advisorExpenses']) > 0)
              _line(
                  'Gastos de asesores por justificar',
                  _n(cash['advisorExpenses']),
                  advisors.fold<int>(
                      0, (sum, a) => sum + _n(a['expensesCount']).toInt()),
                  Colors.orange.shade800,
                  small: true),
            ..._expenseBlock(cash, account: 'efectivo', label: 'Efectivo'),
            if (advisors
                .any((a) => _n(a['pending']) > 0 || _n(a['expenses']) > 0)) ...[
              const Divider(height: 22),
              const Text(
                  'Debe entregar cada asesor (en poder − gastos por justificar)',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
              for (final adv in advisors
                  .where((a) => _n(a['pending']) > 0 || _n(a['expenses']) > 0)
                  .take(8)) ...[
                _line('${adv['name']}', _n(adv['toDeliver']),
                    _n(adv['pendingCount']).toInt(), Colors.orange.shade800,
                    small: true),
                if (_n(adv['expenses']) > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 17, top: 2),
                    child: Text(
                        'en poder ${cashCurrency.format(_n(adv['pending']))} − gastos ${cashCurrency.format(_n(adv['expenses']))}',
                        style:
                            TextStyle(fontSize: 10.5, color: Colors.grey[700])),
                  ),
              ],
            ],
          ]),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Detalle
  // ---------------------------------------------------------------------------
  Widget _detailTab(bool isMobile) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Con pagos marcados las acciones quedan a la vista aunque el bloque esté cerrado
        if (!widget.readOnly && _selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${_selected.length} seleccionados',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  OutlinedButton(
                      onPressed: _busy ? null : () => _markSelected('SUBIDO'),
                      child: const Text('Marcar SUBIDO')),
                  OutlinedButton(
                      onPressed:
                          _busy ? null : () => _markSelected('PENDIENTE'),
                      child: const Text('Marcar PENDIENTE')),
                ]),
          ),
        const SizedBox(height: 6),
        Expanded(
          child: _payments.isEmpty
              ? Center(
                  child: Text('No hay pagos con esos filtros.',
                      style: TextStyle(color: Colors.grey[600])))
              : _PaymentsList(
                  payments: _payments,
                  selected: _selected,
                  mobile: isMobile,
                  footer:
                      'Mostrando ${_payments.length} de $_total${_truncated ? ' (el Excel trae todos)' : ''}',
                  onChanged: () => setState(() {}),
                ),
        ),
      ]),
    );
  }

  /// Un solo bloque expandible con los totales, los filtros y las acciones. Cerrado muestra los totales en una línea
  /// (y cuántos filtros hay activos); abierto muestra los filtros y los botones.
  Widget _controlsBlock(bool isMobile) {
    final pending = Map<String, dynamic>.from(_totals['pending'] ?? {});
    final uploaded = Map<String, dynamic>.from(_totals['uploaded'] ?? {});
    final inDetail = _tabs.index == 1;
    final activeFilters = [
          _agil,
          _method,
          _settled,
          _search.text.trim(),
          _account
        ].where((v) => v.isNotEmpty).length +
        (_from != null || _to != null ? 1 : 0);
    Widget stat(String label, String value, Color color) => RichText(
          text: TextSpan(
              style: TextStyle(
                  fontSize: isMobile ? 12 : 13,
                  color: Theme.of(context).textTheme.bodyMedium?.color),
              children: [
                TextSpan(
                    text: '$label ',
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.w600)),
                TextSpan(
                    text: value,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ]),
        );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => _filtersOpen = !_filtersOpen),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: 12, vertical: isMobile ? 8 : 10),
            child: Row(children: [
              const Icon(Icons.receipt_long,
                  size: 20, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              Text('Pagos y abonos',
                  style: TextStyle(
                      fontSize: isMobile ? 15 : 17,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 14),
              Expanded(
                child: Wrap(
                    spacing: 14,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      stat(
                          'Total',
                          '${cashCurrency.format(_n(_totals['amount']))} · $_total pagos',
                          AppTheme.primaryBlue),
                      stat(
                          'Pend. AGIL',
                          cashCurrency.format(_n(pending['amount'])),
                          Colors.orange.shade800),
                      stat(
                          'Subidos',
                          cashCurrency.format(_n(uploaded['amount'])),
                          AppTheme.secondaryEmerald),
                    ]),
              ),
              if (activeFilters > 0)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(
                      '$activeFilters filtro${activeFilters == 1 ? '' : 's'}',
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryBlue)),
                ),
              Icon(_filtersOpen ? Icons.expand_less : Icons.expand_more),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !_filtersOpen
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        // Fechas y actualizar (aplican al resumen y al detalle)
                        Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _dateButtons(),
                              OutlinedButton.icon(
                                style: ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                    padding: WidgetStateProperty.all(
                                        const EdgeInsets.symmetric(
                                            horizontal: 10))),
                                onPressed: _loading ? null : _load,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Actualizar'),
                              ),
                            ]),
                        if (inDetail) ...[
                          const SizedBox(height: 10),
                          _filtersBar(isMobile),
                        ],
                        if (inDetail && !widget.readOnly) ...[
                          const SizedBox(height: 10),
                          Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                FilledButton.icon(
                                    onPressed: _busy ? null : _export,
                                    icon: const Icon(Icons.download, size: 18),
                                    label: const Text('Descargar Excel')),
                                FilledButton.tonalIcon(
                                    onPressed: _busy ? null : _createBatch,
                                    icon: const Icon(Icons.inventory_2_outlined,
                                        size: 18),
                                    label: const Text('Generar lote AGIL')),
                                OutlinedButton.icon(
                                    onPressed: _busy ? null : _uploadReturned,
                                    icon:
                                        const Icon(Icons.upload_file, size: 18),
                                    label: Text(isMobile
                                        ? 'Subir Excel devuelto'
                                        : 'Subir Excel devuelto (SUBIDO)')),
                                if (_busy)
                                  const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)),
                              ]),
                        ],
                      ]),
                ),
        ),
      ]),
    );
  }

  Widget _filtersBar(bool isMobile) {
    InputDecoration deco(String label) => InputDecoration(
        labelText: label, isDense: true, border: const OutlineInputBorder());
    Widget drop(String label, String value, Map<String, String> options,
            ValueChanged<String> onChanged,
            {double? width}) =>
        SizedBox(
          width: width ??
              (isMobile ? (MediaQuery.of(context).size.width - 66) / 2 : 150),
          child: DropdownButtonFormField<String>(
            value: value,
            decoration: deco(label),
            isExpanded: true,
            items: [
              for (final e in options.entries)
                DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis))
            ],
            onChanged: (v) {
              onChanged(v ?? '');
              _load();
            },
          ),
        );
    return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_account.isNotEmpty)
            InputChip(
              avatar: const Icon(Icons.account_balance, size: 16),
              label: Text('Cuenta: $_accountLabel'),
              onDeleted: () {
                setState(() {
                  _account = '';
                  _accountLabel = '';
                });
                _load();
              },
            ),
          drop(
              'Estado AGIL',
              _agil,
              const {'': 'Todos', 'PENDIENTE': 'Pendiente', 'SUBIDO': 'Subido'},
              (v) => _agil = v),
          drop(
              'Método',
              _method,
              const {
                '': 'Todos',
                'TRANSFERENCIA': 'Transferencia',
                'EFECTIVO': 'Efectivo'
              },
              (v) => _method = v),
          drop(
              'Caja',
              _settled,
              const {'': 'Todos', 'SI': 'Legalizados', 'NO': 'Sin legalizar'},
              (v) => _settled = v),
          SizedBox(
            width: isMobile ? double.infinity : 250,
            child: TextField(
              controller: _search,
              decoration: deco('Buscar (boleta, comprador, referencia…)')
                  .copyWith(
                      suffixIcon: IconButton(
                          icon: const Icon(Icons.search), onPressed: _load)),
              onSubmitted: (_) => _load(),
            ),
          ),
        ]);
  }
}

/// Tabla de pagos. En pantallas anchas: columnas fijas con encabezado, scroll vertical y una barra de scroll horizontal
/// siempre visible. En celular: una tarjeta por pago.
class _PaymentsList extends StatefulWidget {
  final List<Map<String, dynamic>> payments;
  final Set<String> selected;
  final bool mobile;
  final String footer;
  final VoidCallback onChanged;

  const _PaymentsList(
      {required this.payments,
      required this.selected,
      required this.mobile,
      required this.footer,
      required this.onChanged});

  @override
  State<_PaymentsList> createState() => _PaymentsListState();
}

class _PaymentsListState extends State<_PaymentsList> {
  final _h = ScrollController();
  final _v = ScrollController();
  // Paginación (0 = todos)
  int _pageSize = 10;
  int _page = 0;

  int get _pages => _pageSize == 0 ? 1 : math.max(1, (widget.payments.length / _pageSize).ceil());
  int get _curPage => math.min(_page, _pages - 1);
  List<Map<String, dynamic>> get _visible => _pageSize == 0
      ? widget.payments
      : widget.payments.skip(_curPage * _pageSize).take(_pageSize).toList();

  // (título, ancho, alineado a la derecha)
  static const _cols = <(String, double, bool)>[
    ('Fecha', 150, false),
    ('Boleta', 120, false),
    ('Comprador', 170, false),
    ('Asesor', 140, false),
    ('Valor', 110, true),
    ('Método', 125, false),
    ('Banco origen', 150, false),
    ('Cuenta destino', 210, false),
    ('Referencia', 130, false),
    ('Caja', 130, false),
    ('AGIL', 170, false),
    ('Soporte', 80, false),
  ];
  static const _checkW = 52.0;
  static const _rowH = 54.0;
  static double get _tableW =>
      _checkW + _cols.fold<double>(0, (s, c) => s + c.$2);

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    super.dispose();
  }

  bool _isSel(Map<String, dynamic> p) => widget.selected.contains('${p['id']}');

  void _toggle(Map<String, dynamic> p, bool? v) {
    v == true
        ? widget.selected.add('${p['id']}')
        : widget.selected.remove('${p['id']}');
    widget.onChanged();
  }

  void _toggleAll(bool? v) {
    for (final p in _visible) {
      v == true
          ? widget.selected.add('${p['id']}')
          : widget.selected.remove('${p['id']}');
    }
    widget.onChanged();
  }

  void _openSupport(Map<String, dynamic> p) =>
      launchUrl(Uri.parse('${p['soporteLink']}'),
          mode: LaunchMode.externalApplication);

  Widget _cajaChip(Map<String, dynamic> p) => p['settled'] == true
      ? const CashChip('LEGALIZADO', AppTheme.secondaryEmerald)
      : CashChip(
          '${p['cashState']}'.replaceAll('_', ' '), Colors.orange.shade800);

  Widget _agilChip(Map<String, dynamic> p) => p['agilStatus'] == 'SUBIDO'
      ? const CashChip('SUBIDO', AppTheme.secondaryEmerald,
          icon: Icons.cloud_done_outlined)
      : CashChip(
          'PENDIENTE${p['batchNumber'] != null ? ' • lote ${p['batchNumber']}' : ''}',
          Colors.orange.shade800);

  bool _hasSupport(Map<String, dynamic> p) =>
      ((p['soporteLink'] ?? '') as String).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final total = widget.payments.length;
    final from = total == 0 ? 0 : (_pageSize == 0 ? 1 : _curPage * _pageSize + 1);
    final to = _pageSize == 0 ? total : math.min(total, (_curPage + 1) * _pageSize);
    final small = TextStyle(fontSize: 12, color: Colors.grey[700]);
    final footer = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 0,
        children: [
          Text(widget.footer, style: small),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Filas:', style: small),
            const SizedBox(width: 6),
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _pageSize,
                isDense: true,
                style: TextStyle(fontSize: 12.5, color: Theme.of(context).textTheme.bodyMedium?.color),
                items: const [
                  DropdownMenuItem(value: 10, child: Text('10')),
                  DropdownMenuItem(value: 25, child: Text('25')),
                  DropdownMenuItem(value: 50, child: Text('50')),
                  DropdownMenuItem(value: 100, child: Text('100')),
                  DropdownMenuItem(value: 0, child: Text('Todas')),
                ],
                onChanged: (v) => setState(() {
                  _pageSize = v ?? 10;
                  _page = 0;
                }),
              ),
            ),
            const SizedBox(width: 10),
            Text('$from–$to de $total', style: small),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Página anterior',
              icon: const Icon(Icons.chevron_left),
              onPressed: _curPage > 0 ? () => setState(() => _page = _curPage - 1) : null,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Página siguiente',
              icon: const Icon(Icons.chevron_right),
              onPressed: _curPage < _pages - 1 ? () => setState(() => _page = _curPage + 1) : null,
            ),
          ]),
        ],
      ),
    );
    return Column(children: [
      Expanded(child: widget.mobile ? _cards() : _grid()),
      footer,
    ]);
  }

  // --- tarjetas (celular) ---
  Widget _cards() {
    return Scrollbar(
      controller: _v,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _v,
        padding: const EdgeInsets.only(bottom: 8, right: 6),
        itemCount: _visible.length,
        itemBuilder: (context, i) {
          final p = _visible[i];
          final nums = (p['numbers'] as List? ?? []).join(' - ');
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                leading:
                    Checkbox(value: _isSel(p), onChanged: (v) => _toggle(p, v)),
                title: Row(children: [
                  Expanded(
                      child: Text(cashDate('${p['date']}'),
                          style: const TextStyle(fontSize: 12.5))),
                  Text(cashCurrency.format((p['amount'] as num?) ?? 0),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ]),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Boleta $nums • ${p['buyerName']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          CashChip('${p['method']}', Colors.blueGrey),
                          _cajaChip(p),
                          _agilChip(p)
                        ]),
                      ]),
                ),
                children: [
                  _info('Asesor', '${p['advisorName']}'),
                  _info('Banco origen', '${p['originBank']}'),
                  _info('Cuenta destino', '${p['cuentaDestino']}'),
                  _info('Referencia', '${p['approvalNumber']}'),
                  if (_hasSupport(p))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                          onPressed: () => _openSupport(p),
                          icon: const Icon(Icons.image_search, size: 18),
                          label: const Text('Ver soporte')),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _info(String label, String value) => value.trim().isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '$label: ',
                      style: TextStyle(color: Colors.grey[700])),
                  TextSpan(
                      text: value,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
                style: const TextStyle(fontSize: 13)),
          ),
        );

  // --- tabla (pantallas anchas) ---
  Widget _grid() {
    return LayoutBuilder(builder: (context, c) {
      final width = math.max(c.maxWidth, _tableW);
      final visible = _visible;
      final allSelected = visible.isNotEmpty && visible.every(_isSel);
      final someSelected = visible.any(_isSel);
      return Container(
        decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: Scrollbar(
          controller: _h,
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
            controller: _h,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: c.maxHeight - 1,
              child: Column(children: [
                Container(
                  height: 44,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.08),
                  child: Row(children: [
                    SizedBox(
                        width: _checkW,
                        child: Checkbox(
                            tristate: true,
                            value: allSelected
                                ? true
                                : (someSelected ? null : false),
                            onChanged: (v) =>
                                _toggleAll(allSelected ? false : true))),
                    for (final col in _cols)
                      SizedBox(
                        width: col.$2 +
                            (width - _tableW) *
                                (col.$1 == 'Cuenta destino' ? 1 : 0),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(col.$1,
                              textAlign:
                                  col.$3 ? TextAlign.right : TextAlign.left,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                  ]),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Scrollbar(
                    controller: _v,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _v,
                      itemExtent: _rowH,
                      itemCount: visible.length,
                      itemBuilder: (context, i) => _row(visible[i], i, width),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }

  Widget _row(Map<String, dynamic> p, int i, double width) {
    final extra = width - _tableW;
    Widget cell(int index, Widget child) => SizedBox(
          width: _cols[index].$2 +
              (_cols[index].$1 == 'Cuenta destino' ? extra : 0),
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                  alignment: _cols[index].$3
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: child)),
        );
    Text t(String s, {bool bold = false}) => Text(s,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal));
    final selected = _isSel(p);
    return Container(
      color: selected
          ? AppTheme.primaryBlue.withValues(alpha: 0.08)
          : (i.isEven ? null : Colors.grey.withValues(alpha: 0.05)),
      child: Row(children: [
        SizedBox(
            width: _checkW,
            child: Checkbox(value: selected, onChanged: (v) => _toggle(p, v))),
        cell(0, t(cashDate('${p['date']}'))),
        cell(1, t((p['numbers'] as List? ?? []).join(' - '))),
        cell(2, t('${p['buyerName']}')),
        cell(3, t('${p['advisorName']}')),
        cell(4, t(cashCurrency.format((p['amount'] as num?) ?? 0), bold: true)),
        cell(5, t('${p['method']}')),
        cell(6, t('${p['originBank']}')),
        cell(7, t('${p['cuentaDestino']}')),
        cell(8, t('${p['approvalNumber']}')),
        cell(9, _cajaChip(p)),
        cell(10, _agilChip(p)),
        cell(
            11,
            _hasSupport(p)
                ? IconButton(
                    tooltip: 'Ver soporte',
                    icon: const Icon(Icons.image_search,
                        size: 20, color: AppTheme.primaryBlue),
                    onPressed: () => _openSupport(p))
                : const Text('—')),
      ]),
    );
  }
}

/// Registrar un gasto de una cuenta o del efectivo: valor, fecha, motivo y foto opcional.
class ExpenseDialog extends StatefulWidget {
  final ApiService api;
  final String account;
  final String label;
  final num balance;

  const ExpenseDialog(
      {required this.api,
      required this.account,
      required this.label,
      required this.balance});

  @override
  State<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<ExpenseDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  DateTime _date = DateTime.now();
  String? _image;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  num get _value =>
      num.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  Future<void> _pickPhoto() async {
    try {
      final picked = await pickImageBase64(maxSide: 1600);
      if (picked != null && mounted)
        setState(() => _image = prepareProofImage(picked, maxSide: 1600));
    } catch (e) {
      if (mounted) setState(() => _error = e is ImageTooHeavyException ? e.message : 'No se pudo cargar la foto: $e');
    }
  }

  Future<void> _save() async {
    if (_value <= 0)
      return setState(() => _error = 'Escriba el valor del gasto.');
    if (_reason.text.trim().length < 3)
      return setState(() => _error = 'Escriba el motivo del gasto.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.agilCreateExpense(
        account: widget.account,
        accountLabel: widget.label,
        amount: _value,
        date: DateFormat('yyyy-MM-dd').format(_date),
        reason: _reason.text.trim(),
        imageBase64: _image,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final exceeds = _value > 0 && _value > widget.balance;
    return AlertDialog(
      title: Text('Registrar gasto\n${widget.label}',
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Saldo legalizado disponible: ${cashCurrency.format(widget.balance)}',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
                const SizedBox(height: 12),
                TextField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Valor del gasto *',
                      prefixIcon: Icon(Icons.attach_money),
                      border: OutlineInputBorder()),
                ),
                if (exceeds)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        '⚠️ Supera el saldo legalizado: el saldo quedará en negativo.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w600)),
                  ),
                const SizedBox(height: 12),
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
                      'Fecha del gasto: ${DateFormat('dd/MM/yyyy').format(_date)}'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reason,
                  maxLines: 2,
                  maxLength: 300,
                  decoration: const InputDecoration(
                      labelText: 'Motivo del gasto *',
                      hintText: 'Ej: pago de publicidad, transporte, premios…',
                      border: OutlineInputBorder()),
                ),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _pickPhoto,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(_image == null
                          ? 'Foto del gasto (opcional)'
                          : '✓ Foto adjunta (cambiar)'),
                    ),
                  ),
                  if (_image != null)
                    IconButton(
                        onPressed: () => setState(() => _image = null),
                        icon: const Icon(Icons.close, color: Colors.red),
                        tooltip: 'Quitar foto'),
                ]),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppTheme.dangerRose,
                              fontWeight: FontWeight.w600))),
              ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar gasto'),
        ),
      ],
    );
  }
}

/// Gastos de una cuenta o del efectivo, con su foto y la opción de anularlos (con motivo).
class ExpensesListDialog extends StatefulWidget {
  final ApiService api;
  final String account;
  final String label;

  /// allowVoid: solo el administrador anula gastos.
  final bool allowVoid;

  const ExpensesListDialog(
      {required this.api,
      required this.account,
      required this.label,
      this.allowVoid = true});

  @override
  State<ExpensesListDialog> createState() => _ExpensesListDialogState();
}

class _ExpensesListDialogState extends State<ExpensesListDialog> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _expenses = [];
  num _total = 0;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.agilExpenses(account: widget.account);
      if (!mounted) return;
      setState(() {
        _expenses = ((res['expenses'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _total = (res['total'] as num?) ?? 0;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  Future<void> _void(Map<String, dynamic> e) async {
    final reason = await askReason(context,
        'Anular gasto de ${cashCurrency.format((e['amount'] as num?) ?? 0)}',
        hint: 'Ej: se registró dos veces', confirmLabel: 'Anular gasto');
    if (reason == null || !mounted) return;
    try {
      await widget.api.agilVoidExpense('${e['id']}', reason);
      _changed = true;
      await _load();
    } catch (err) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: AppTheme.dangerRose,
            content: Text(err.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text('Gastos\n${widget.label}', style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 460,
        child: _loading
            ? const SizedBox(
                height: 80, child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? Text(_error!,
                    style: const TextStyle(color: AppTheme.dangerRose))
                : ListView(shrinkWrap: true, children: [
                    Text('Total gastado: ${cashCurrency.format(_total)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    for (final e in _expenses)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color:
                            e['voided'] != null ? Colors.grey.shade100 : null,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                      child: Text(cashDate('${e['date']}'),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600))),
                                  Text(
                                      cashCurrency
                                          .format((e['amount'] as num?) ?? 0),
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: AppTheme.dangerRose,
                                          decoration: e['voided'] != null
                                              ? TextDecoration.lineThrough
                                              : null)),
                                ]),
                                const SizedBox(height: 2),
                                Text('${e['reason']}',
                                    style: TextStyle(
                                        fontSize: 13,
                                        decoration: e['voided'] != null
                                            ? TextDecoration.lineThrough
                                            : null)),
                                Text(
                                    'Registró ${e['createdBy']}${e['applied'] != null ? ' • conciliado con el administrador' : ''}',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey[600])),
                                if (e['voided'] != null)
                                  Text(
                                      'ANULADO por ${(e['voided'] as Map)['by']}: ${(e['voided'] as Map)['reason']}',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.red.shade700,
                                          fontWeight: FontWeight.w600)),
                                Row(children: [
                                  if (e['hasSupport'] == true)
                                    TextButton.icon(
                                      onPressed: () => showSoporte(context,
                                          driveId:
                                              e['soporteDriveId'] as String?,
                                          webViewUrl:
                                              e['soporteWebViewUrl'] as String?,
                                          title: 'Foto del gasto'),
                                      icon: const Icon(Icons.image_search,
                                          size: 18),
                                      label: const Text('Ver foto'),
                                    ),
                                  const Spacer(),
                                  if (e['voided'] == null && widget.allowVoid)
                                    TextButton(
                                        onPressed: () => _void(e),
                                        child: const Text('Anular',
                                            style: TextStyle(
                                                color: AppTheme.dangerRose))),
                                ]),
                              ]),
                        ),
                      ),
                    if (_expenses.isEmpty)
                      Text('No hay gastos registrados.',
                          style: TextStyle(color: Colors.grey[600])),
                  ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, _changed),
            child: const Text('Cerrar'))
      ],
    );
  }
}
