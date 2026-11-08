import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rifaapp/data/models/raffle.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/utils/file_saver.dart';

/// PDF del inventario de números: todas las boletas, ordenadas y agrupadas en bloques de 100,
/// cada una como una tarjeta con sus oportunidades. Diseño claro (se imprime bien) con encabezado azul marino.
/// Solo usa caracteres Latin-1 (la fuente estándar del PDF no dibuja otros).
class AvailableNumbersPdf {
  static const _navy = PdfColor.fromInt(0xFF0D1B2A);
  static const _amber = PdfColor.fromInt(0xFFF59E0B);
  static const _emerald = PdfColor.fromInt(0xFF059669);
  static const _emeraldSoft = PdfColor.fromInt(0xFFD1FAE5);
  static const _slate = PdfColor.fromInt(0xFF64748B);
  static const _line = PdfColor.fromInt(0xFFE2E8F0);

  /// (color de borde, fondo de chips, color del número) según el estado de la boleta
  static (PdfColor, PdfColor, PdfColor) _palette(String status) => switch (status) {
        'DISPONIBLE' => (_emerald, _emeraldSoft, const PdfColor.fromInt(0xFF065F46)),
        'RESERVADA' => (_amber, const PdfColor.fromInt(0xFFFEF3C7), const PdfColor.fromInt(0xFF92400E)),
        'ABONO_PARCIAL' => (const PdfColor.fromInt(0xFF3B82F6), const PdfColor.fromInt(0xFFDBEAFE), const PdfColor.fromInt(0xFF1E40AF)),
        _ => (const PdfColor.fromInt(0xFFCBD5E1), const PdfColor.fromInt(0xFFF1F5F9), const PdfColor.fromInt(0xFF94A3B8)),
      };

  static int _columnsFor(int digits, int maxOpportunities) {
    if (maxOpportunities >= 5) return 2;
    if (maxOpportunities == 4) return 3;
    if (maxOpportunities == 3) return 4;
    if (maxOpportunities == 2) return 6;
    if (digits >= 4) return 10;
    if (digits == 3) return 12;
    return 14;
  }

  static String _dateOnly(String raw) {
    final d = DateTime.tryParse(raw);
    if (d != null) return DateFormat('dd/MM/yyyy').format(d);
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  static List<String> _numbersOf(Ticket t, int digits) =>
      t.numbers.isNotEmpty ? t.numbers : [t.ticketNumber.toString().padLeft(digits, '0')];

  /// Arma el PDF. [tickets] ya viene filtrado (alcance del asesor, solo disponibles o tablero completo, búsqueda).
  static Future<Uint8List> build({
    required Raffle raffle,
    required List<Ticket> tickets,
    required bool fullBoard,
    required String scopeTitle,
    required String scopeSub,
    required String contactLine,
    required int totalScoped,
    required int totalAvailable,
  }) async {
    final sorted = [...tickets]..sort((a, b) => a.ticketNumber.compareTo(b.ticketNumber));
    final digits = raffle.digits;
    final maxOpps = sorted.fold<int>(1, (m, t) => _numbersOf(t, digits).length > m ? _numbersOf(t, digits).length : m);
    final columns = _columnsFor(digits, maxOpps);
    const margin = 28.0;
    final pageFormat = PdfPageFormat.a4.copyWith(marginLeft: margin, marginRight: margin, marginTop: 24, marginBottom: 30);
    const gap = 4.5;
    final contentWidth = PdfPageFormat.a4.width - margin * 2;
    final cardWidth = (contentWidth - gap * (columns - 1)) / columns - 0.01;
    final percent = totalScoped > 0 ? (totalAvailable / totalScoped * 100).toStringAsFixed(1) : '0';
    final price = '\$${NumberFormat('#,##0', 'es_CO').format(raffle.ticketPrice)}';

    pw.Widget chip(String text, PdfColor bg, PdfColor fg, {double fontSize = 11, double hPad = 5}) => pw.Container(
          padding: pw.EdgeInsets.symmetric(horizontal: hPad, vertical: 3),
          decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(5)),
          child: pw.Text(text, style: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold, color: fg)),
        );

    pw.Widget card(Ticket t) {
      final nums = _numbersOf(t, digits);
      final (border, chipBg, numColor) = _palette(t.status);
      final fontSize = columns >= 10 ? 9.5 : (columns >= 6 ? 10.5 : (columns >= 4 ? 11.5 : 12.5));
      return pw.Container(
        width: cardWidth,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3.5),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: border, width: 1),
        ),
        child: pw.Wrap(
          alignment: pw.WrapAlignment.center,
          spacing: 2.5,
          runSpacing: 2.5,
          children: [for (final n in nums) chip(n, chipBg, numColor, fontSize: fontSize, hPad: 3.5)],
        ),
      );
    }

    pw.Widget legendDot(String label, PdfColor color) => pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
          pw.Container(width: 8, height: 8, decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(2))),
          pw.SizedBox(width: 4),
          pw.Text(label, style: const pw.TextStyle(fontSize: 7.5, color: _slate)),
          pw.SizedBox(width: 12),
        ]);

    final hero = pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 9, 14, 7),
      decoration: pw.BoxDecoration(color: _navy, borderRadius: pw.BorderRadius.circular(10)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              chip('RIFA MASTER', _amber, PdfColors.black, fontSize: 7.5, hPad: 6),
              pw.SizedBox(width: 10),
              pw.Expanded(child: pw.Text(raffle.title, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
              pw.Text(fullBoard ? '${sorted.length} boletas' : '${sorted.length} disponibles',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _amber)),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            [
              scopeTitle,
              if (scopeSub.isNotEmpty) scopeSub,
              'Sorteo: ${_dateOnly(raffle.mainDrawDate)}',
              'Valor: $price',
              '$digits cifras',
              maxOpps > 1 ? '$maxOpps oportunidades' : '1 oportunidad',
              '$percent% disponible ($totalAvailable de $totalScoped)',
            ].join('  |  '),
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey300),
          ),
          pw.SizedBox(height: 5),
          pw.Container(height: 2.5, decoration: pw.BoxDecoration(color: _amber, borderRadius: pw.BorderRadius.circular(2))),
        ],
      ),
    );

    final legend = fullBoard
        ? pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Row(children: [
              legendDot('Libre', _emerald),
              legendDot('Apartada', _amber),
              legendDot('Abono', const PdfColor.fromInt(0xFF3B82F6)),
              legendDot('Vendida', const PdfColor.fromInt(0xFFCBD5E1)),
            ]),
          )
        : pw.SizedBox();

    final doc = pw.Document(title: 'Numeros - ${raffle.title}', author: 'Rifa Master');
    doc.addPage(
      pw.MultiPage(
        // Un solo bloque de tarjetas puede ocupar decenas de páginas (el límite por defecto es 20)
        maxPages: 2000,
        pageFormat: pageFormat,
        footer: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(child: pw.Text(contactLine, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _navy))),
              pw.Text('${raffle.title}  |  Pagina ${ctx.pageNumber} de ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: _slate)),
            ],
          ),
        ),
        build: (ctx) => [
          hero,
          legend,
          if (sorted.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 30),
              child: pw.Center(child: pw.Text('No hay numeros para mostrar con este filtro.', style: const pw.TextStyle(fontSize: 12, color: _slate))),
            ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Wrap(spacing: gap, runSpacing: gap, children: [for (final t in sorted) card(t)]),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static Future<void> download({
    required Raffle raffle,
    required List<Ticket> tickets,
    required bool fullBoard,
    required String scopeTitle,
    required String scopeSub,
    required String contactLine,
    required int totalScoped,
    required int totalAvailable,
  }) async {
    final bytes = await build(
      raffle: raffle,
      tickets: tickets,
      fullBoard: fullBoard,
      scopeTitle: scopeTitle,
      scopeSub: scopeSub,
      contactLine: contactLine,
      totalScoped: totalScoped,
      totalAvailable: totalAvailable,
    );
    await saveAndDownloadBytes('numeros_${fullBoard ? 'tablero' : 'disponibles'}_${raffle.id}.pdf', bytes, mimeType: 'application/pdf');
  }
}
