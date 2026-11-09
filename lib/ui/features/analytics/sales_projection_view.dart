import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/theme.dart';

/// Proyección de ventas (solo administrador): qué día se vende más, ritmo promedio y cuánto se proyecta vender hasta el sorteo.
class SalesProjectionView extends StatefulWidget {
  final String raffleId;
  final String raffleTitle;
  const SalesProjectionView({super.key, required this.raffleId, required this.raffleTitle});

  static Future<void> open(BuildContext context, {required String raffleId, required String raffleTitle}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => SalesProjectionView(raffleId: raffleId, raffleTitle: raffleTitle)));

  @override
  State<SalesProjectionView> createState() => _SalesProjectionViewState();
}

class _SalesProjectionViewState extends State<SalesProjectionView> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _byMoney = false; // día de la semana: boletas o dinero
  final _money = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiService().getSalesAnalytics(widget.raffleId);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  num _n(dynamic v) => (v as num?) ?? 0;
  String _f1(num v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proyección de ventas'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Actualizar')],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : _content(),
    );
  }

  Widget _content() {
    final d = _data!;
    final sold = _n(d['soldCount']).toInt();
    final total = _n(d['totalTickets']).toInt();
    final daysLeft = d['daysLeft'] as int?;
    final needed = d['neededPerDay'] as num?;
    final best = d['bestWeekday'] as Map<String, dynamic>?;
    final avgAll = _n(d['avgAll']);
    final avg7 = _n(d['avg7']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.raffleTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text('Datos desde la primera venta (${d['firstSaleDay']}) hasta hoy. Días en hora de Colombia.', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _kpi('Boletas vendidas', '$sold de $total', Icons.confirmation_number_outlined, AppTheme.primaryBlue, '${total > 0 ? (sold / total * 100).toStringAsFixed(1) : 0}% de la rifa'),
            _kpi('Recaudado', _money.format(_n(d['collected'])), Icons.payments_outlined, AppTheme.secondaryEmerald, 'Precio boleta ${_money.format(_n(d['ticketPrice']))}'),
            _kpi('Promedio por día', _f1(double.parse(avgAll.toStringAsFixed(1))), Icons.speed, Colors.purple, 'Últimos 7 días: ${_f1(double.parse(avg7.toStringAsFixed(1)))} por día'),
            _kpi('Días para el sorteo', daysLeft == null ? '—' : '$daysLeft', Icons.event, Colors.orange,
                needed == null ? 'Sin fecha de sorteo' : 'Para agotar: ${_f1(double.parse(needed.toStringAsFixed(1)))} boletas por día'),
            _kpi('Mejor día', best == null ? '—' : best['name'] as String, Icons.emoji_events_outlined, Colors.teal,
                best == null ? 'Aún sin ventas' : 'Promedio ${_f1(double.parse(_n(best['avgTickets']).toStringAsFixed(1)))} boletas ese día'),
          ]),
          const SizedBox(height: 20),
          _section('¿Qué día de la semana se vende más?', trailing: SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('Boletas')), ButtonSegment(value: true, label: Text('Dinero'))],
            selected: {_byMoney},
            onSelectionChanged: (s) => setState(() => _byMoney = s.first),
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          )),
          _weekdayChart(d),
          const SizedBox(height: 20),
          _section('Boletas vendidas acumuladas y proyección'),
          SizedBox(height: 220, child: _card(CustomPaint(painter: _CumulativePainter(d), size: Size.infinite))),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              _legend(AppTheme.primaryBlue, 'Vendidas'),
              const SizedBox(width: 14),
              _legend(Colors.orange, 'Proyección (promedio 7 días)'),
              const SizedBox(width: 14),
              _legend(Colors.red.shade300, 'Total de la rifa'),
            ]),
          ),
          const SizedBox(height: 20),
          _section('Ventas de los últimos 30 días'),
          _dailyBars(d),
          const SizedBox(height: 20),
          _section('Proyección hasta el sorteo'),
          _projection('Con el promedio de toda la rifa', d['projectionAll'] as Map<String, dynamic>?, total),
          const SizedBox(height: 10),
          _projection('Con el ritmo de los últimos 7 días', d['projection7'] as Map<String, dynamic>?, total),
          const SizedBox(height: 6),
          Text(
            'La proyección supone que se mantiene el mismo ritmo de ventas hasta la fecha del sorteo, y que se cobra la misma proporción del valor de las boletas que hasta hoy (${(_n(d['collectRatio']) * 100).toStringAsFixed(0)}%).',
            style: TextStyle(fontSize: 11.5, color: Colors.grey[600], height: 1.35),
          ),
          const SizedBox(height: 20),
          _section('Asesores con más boletas'),
          _advisors(d),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ piezas
  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.withValues(alpha: 0.25))),
        child: child,
      );

  Widget _section(String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
          if (trailing != null) trailing,
        ]),
      );

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(t, style: const TextStyle(fontSize: 11)),
      ]);

  Widget _kpi(String title, String value, IconData icon, Color color, String sub) => SizedBox(
        width: 230,
        child: _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: 6), Expanded(child: Text(title, style: const TextStyle(fontSize: 12.5)))]),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ])),
      );

  Widget _weekdayChart(Map<String, dynamic> d) {
    final list = (d['weekday'] as List).cast<Map<String, dynamic>>();
    // Se muestra de lunes a domingo
    final order = [1, 2, 3, 4, 5, 6, 0];
    final rows = [for (final i in order) list[i]];
    double value(Map<String, dynamic> w) => (_byMoney ? _n(w['avgMoney']) : _n(w['avgTickets'])).toDouble();
    final maxV = rows.map(value).fold<double>(0, math.max);
    return _card(SizedBox(
      height: 190,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final w in rows)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(_byMoney ? NumberFormat.compact(locale: 'es').format(value(w)) : _f1(double.parse(value(w).toStringAsFixed(1))), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Container(
                  height: maxV > 0 ? math.max(3.0, 120 * value(w) / maxV) : 3,
                  decoration: BoxDecoration(
                    color: maxV > 0 && value(w) == maxV ? AppTheme.secondaryEmerald : AppTheme.primaryBlue.withValues(alpha: 0.7),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                ),
                const SizedBox(height: 5),
                Text((w['name'] as String).substring(0, 3), style: const TextStyle(fontSize: 11.5)),
              ]),
            ),
          ),
      ]),
    ));
  }

  Widget _dailyBars(Map<String, dynamic> d) {
    final daily = (d['daily'] as List).cast<Map<String, dynamic>>();
    final last = daily.length > 30 ? daily.sublist(daily.length - 30) : daily;
    final maxT = last.map((e) => _n(e['tickets']).toDouble()).fold<double>(0, math.max);
    return _card(SizedBox(
      height: 120,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final e in last)
          Expanded(
            child: Tooltip(
              message: '${e['date']}: ${e['tickets']} boletas • ${_money.format(_n(e['money']))}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  height: maxT > 0 ? math.max(2.0, 100 * _n(e['tickets']).toDouble() / maxT) : 2,
                  decoration: BoxDecoration(color: AppTheme.primaryBlue.withValues(alpha: 0.75), borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                ),
              ),
            ),
          ),
      ]),
    ));
  }

  Widget _projection(String title, Map<String, dynamic>? p, int total) {
    if (p == null) return _card(Text('$title: la rifa no tiene fecha de sorteo.'));
    final pct = _n(p['soldOutPct']).toDouble();
    final reaches = pct >= 99.5;
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text('Ritmo: ${_f1(double.parse(_n(p['avgPerDay']).toStringAsFixed(1)))} boletas por día'),
      Text('Boletas al día del sorteo: ${_n(p['tickets'])} de $total (${pct.toStringAsFixed(0)}%)'),
      Text('Ventas proyectadas: ${_money.format(_n(p['revenue']))}'),
      Text('Recaudo proyectado: ${_money.format(_n(p['collected']))}'),
      const SizedBox(height: 6),
      LinearProgressIndicator(value: (pct / 100).clamp(0, 1), minHeight: 8, borderRadius: BorderRadius.circular(6), color: reaches ? AppTheme.secondaryEmerald : Colors.orange),
      const SizedBox(height: 4),
      Text(reaches ? '✅ Con este ritmo se agota la rifa antes del sorteo.' : '⚠️ Con este ritmo no se alcanza a vender toda la rifa.', style: TextStyle(fontSize: 12, color: reaches ? Colors.green[700] : Colors.orange[800])),
    ]));
  }

  Widget _advisors(Map<String, dynamic> d) {
    final list = (d['topAdvisors'] as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return _card(const Text('Aún no hay ventas.'));
    final maxT = list.map((e) => _n(e['tickets']).toDouble()).fold<double>(1, math.max);
    return _card(Column(children: [
      for (final a in list)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 130, child: Text(a['name'] as String, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5))),
            Expanded(child: LinearProgressIndicator(value: _n(a['tickets']).toDouble() / maxT, minHeight: 10, borderRadius: BorderRadius.circular(6))),
            const SizedBox(width: 8),
            Text('${a['tickets']}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),
    ]));
  }
}

/// Línea de boletas acumuladas (azul), proyección (naranja, punteada) y tope de la rifa (rojo).
class _CumulativePainter extends CustomPainter {
  final Map<String, dynamic> d;
  _CumulativePainter(this.d);

  @override
  void paint(Canvas canvas, Size size) {
    final daily = (d['daily'] as List).cast<Map<String, dynamic>>();
    if (daily.isEmpty) return;
    final total = ((d['totalTickets'] as num?) ?? 0).toDouble();
    final soldNow = ((d['soldCount'] as num?) ?? 0).toDouble();
    final daysLeft = (d['daysLeft'] as int?) ?? 0;
    final avg7 = ((d['avg7'] as num?) ?? 0).toDouble();
    final n = daily.length;
    final totalDays = n - 1 + daysLeft;
    final maxY = math.max(total, soldNow).clamp(1, double.infinity).toDouble();
    const left = 34.0, bottom = 18.0, top = 6.0;
    final w = size.width - left - 4, h = size.height - bottom - top;
    Offset pt(num x, num y) => Offset(left + (totalDays <= 0 ? 0 : w * x / totalDays), top + h - h * y / maxY);

    final grid = Paint()..color = Colors.grey.withValues(alpha: 0.25)..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = top + h * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      final tp = TextPainter(text: TextSpan(text: '${(maxY * (4 - i) / 4).round()}', style: const TextStyle(fontSize: 9, color: Colors.grey)), textDirection: ui_td)..layout();
      tp.paint(canvas, Offset(0, y - 6));
    }
    // tope
    canvas.drawLine(pt(0, total), pt(totalDays, total), Paint()..color = Colors.red.shade300..strokeWidth = 1.2);
    // vendidas
    final path = Path()..moveTo(pt(0, daily[0]['cumTickets'] as num).dx, pt(0, daily[0]['cumTickets'] as num).dy);
    for (var i = 1; i < n; i++) {
      final o = pt(i, daily[i]['cumTickets'] as num);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, Paint()..color = AppTheme.primaryBlue..style = PaintingStyle.stroke..strokeWidth = 2.5);
    // proyección punteada
    if (daysLeft > 0) {
      final from = pt(n - 1, soldNow);
      final to = pt(totalDays, math.min(total, soldNow + avg7 * daysLeft));
      final paint = Paint()..color = Colors.orange..strokeWidth = 2.2;
      const dash = 7.0;
      final len = (to - from).distance;
      for (var t = 0.0; t < len; t += dash * 2) {
        canvas.drawLine(from + (to - from) * (t / len), from + (to - from) * (math.min(t + dash, len) / len), paint);
      }
    }
    // etiquetas de fechas
    void label(String text, double x, TextAlign align) {
      final tp = TextPainter(text: TextSpan(text: text, style: const TextStyle(fontSize: 9, color: Colors.grey)), textDirection: ui_td)..layout();
      tp.paint(canvas, Offset(align == TextAlign.right ? x - tp.width : x, size.height - 12));
    }
    label(daily.first['date'].toString().substring(5), left, TextAlign.left);
    if (d['drawDay'] != null && daysLeft > 0) label('Sorteo ${d['drawDay'].toString().substring(5)}', size.width - 2, TextAlign.right);
  }

  @override
  bool shouldRepaint(covariant _CumulativePainter old) => old.d != d;
}

const ui_td = ui.TextDirection.ltr;
