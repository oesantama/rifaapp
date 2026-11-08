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
  static const _navy2 = PdfColor.fromInt(0xFF1B263B);
  static const _amber = PdfColor.fromInt(0xFFF59E0B);
  static const _emerald = PdfColor.fromInt(0xFF059669);
  static const _emeraldSoft = PdfColor.fromInt(0xFFD1FAE5);
  static const _slate = PdfColor.fromInt(0xFF64748B);
  static const _line = PdfColor.fromInt(0xFFE2E8F0);
  static const _paper = PdfColor.fromInt(0xFFF8FAFC);

  static const _statusLabel = {
    'DISPONIBLE': 'LIBRE',
    'RESERVADA': 'APARTADA',
    'ABONO_PARCIAL': 'ABONO',
    'PAGADA': 'VENDIDA',
    'CONFIRMADA': 'VENDIDA',
  };

  /// (color de borde, fondo de chips, color del número) según el estado de la boleta
  static (PdfColor, PdfColor, PdfColor) _palette(String status) => switch (status) {
        'DISPONIBLE' => (_emerald, _emeraldSoft, const PdfColor.fromInt(0xFF065F46)),
        'RESERVADA' => (_amber, const PdfColor.fromInt(0xFFFEF3C7), const PdfColor.fromInt(0xFF92400E)),
        'ABONO_PARCIAL' => (const PdfColor.fromInt(0xFF3B82F6), const PdfColor.fromInt(0xFFDBEAFE), const PdfColor.fromInt(0xFF1E40AF)),
        _ => (const PdfColor.fromInt(0xFFCBD5E1), const PdfColor.fromInt(0xFFF1F5F9), const PdfColor.fromInt(0xFF94A3B8)),
      };

  static int _columnsFor(int digits, int maxOpportunities) {
    if (maxOpportunities >= 4) return 2;
    if (maxOpportunities == 3) return 3;
    if (maxOpportunities == 2) return 5;
    if (digits >= 4) return 6;
    if (digits == 3) return 8;
    return 10;
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
    final sorted = [...tickets]..sort((a, b) => a.sortNumber.compareTo(b.sortNumber));
    final digits = raffle.digits;
    final maxOpps = sorted.fold<int>(1, (m, t) => _numbersOf(t, digits).length > m ? _numbersOf(t, digits).length : m);
    final columns = _columnsFor(digits, maxOpps);
    const margin = 28.0;
    final pageFormat = PdfPageFormat.a4.copyWith(marginLeft: margin, marginRight: margin, marginTop: 24, marginBottom: 30);
    const gap = 6.0;
    final contentWidth = PdfPageFormat.a4.width - margin * 2;
    final cardWidth = (contentWidth - gap * (columns - 1)) / columns - 0.01;
    final percent = totalScoped > 0 ? (totalAvailable / totalScoped * 100).toStringAsFixed(1) : '0';
    final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final price = '\$${NumberFormat('#,##0', 'es_CO').format(raffle.ticketPrice)}';

    pw.Widget chip(String text, PdfColor bg, PdfColor fg, {double fontSize = 11, double hPad = 5}) => pw.Container(
          padding: pw.EdgeInsets.symmetric(horizontal: hPad, vertical: 3),
          decoration: pw.BoxDecoration(color: bg, borderRadius: pw.BorderRadius.circular(5)),
          child: pw.Text(text, style: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold, color: fg)),
        );

    pw.Widget card(Ticket t) {
      final nums = _numbersOf(t, digits);
      final (border, chipBg, numColor) = _palette(t.status);
      final multi = nums.length > 1;
      final fontSize = columns >= 8 ? 10.0 : (columns >= 5 ? 10.5 : 12.5);
      return pw.Container(
        width: cardWidth,
        padding: const pw.EdgeInsets.fromLTRB(5, 4, 5, 5),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(7),
          border: pw.Border.all(color: border, width: 1),
        ),
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (multi || fullBoard)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    if (multi)
                      pw.Text('${nums.length} OPORTUNIDADES', style: pw.TextStyle(fontSize: 5.5, color: _slate, fontWeight: pw.FontWeight.bold))
                    else
                      pw.SizedBox(),
                    if (fullBoard) pw.Text(_statusLabel[t.status] ?? t.status, style: pw.TextStyle(fontSize: 5.5, color: border, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            pw.Wrap(
              alignment: pw.WrapAlignment.center,
              spacing: 3,
              runSpacing: 3,
              children: [for (final n in nums) chip(n, chipBg, numColor, fontSize: fontSize)],
            ),
          ],
        ),
      );
    }

    // Bloques de 100 números: "0400 - 0499"
    final blocks = <int, List<Ticket>>{};
    for (final t in sorted) {
      blocks.putIfAbsent(t.sortNumber ~/ 100, () => []).add(t);
    }

    String pad(int n) => n.toString().padLeft(digits, '0');

    pw.Widget blockHeader(int block, int count) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 10, bottom: 6),
          decoration: pw.BoxDecoration(color: _paper, borderRadius: pw.BorderRadius.circular(5)),
          child: pw.Row(
            children: [
              pw.Container(width: 4, height: 20, decoration: pw.BoxDecoration(color: _amber, borderRadius: pw.BorderRadius.circular(2))),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Text('BLOQUE ${pad(block * 100)} - ${pad(block * 100 + 99)}',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _navy)),
              ),
              pw.Text('$count ${fullBoard ? 'boletas' : (count == 1 ? 'disponible' : 'disponibles')}',
                  style: const pw.TextStyle(fontSize: 8, color: _slate)),
              pw.SizedBox(width: 8),
            ],
          ),
        );

    pw.Widget metric(String label, String value, PdfColor accent) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 8),
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: pw.BoxDecoration(color: _navy2, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey400)),
                pw.SizedBox(height: 2),
                pw.Text(value, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                pw.SizedBox(height: 4),
                pw.Container(height: 2.5, decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(2))),
              ],
            ),
          ),
        );

    pw.Widget legendDot(String label, PdfColor color) => pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
          pw.Container(width: 8, height: 8, decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(2))),
          pw.SizedBox(width: 4),
          pw.Text(label, style: const pw.TextStyle(fontSize: 7.5, color: _slate)),
          pw.SizedBox(width: 12),
        ]);

    final hero = pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: pw.BoxDecoration(color: _navy, borderRadius: pw.BorderRadius.circular(14)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              chip('RIFA MASTER', _amber, PdfColors.black, fontSize: 9, hPad: 9),
              pw.Text('Generado el $now', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey400)),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(raffle.title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
          pw.SizedBox(height: 3),
          pw.Text(scopeTitle, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _amber)),
          pw.SizedBox(height: 2),
          pw.Text(scopeSub, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey400)),
          pw.SizedBox(height: 12),
          pw.Row(children: [
            metric(fullBoard ? 'BOLETAS EN EL TABLERO' : 'NUMEROS DISPONIBLES', '${sorted.length}', _emerald),
            metric('TOTAL DE BOLETAS', '$totalScoped', _amber),
            metric('% DISPONIBLE', '$percent%', const PdfColor.fromInt(0xFF3B82F6)),
            metric('VALOR DE LA BOLETA', price, PdfColors.pink300),
          ]),
          pw.SizedBox(height: 8),
          pw.Text(
            '$digits cifras  |  ${maxOpps > 1 ? '$maxOpps oportunidades por boleta' : '1 oportunidad por boleta'}  |  Sorteo: ${_dateOnly(raffle.mainDrawDate)}',
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey300),
          ),
          pw.SizedBox(height: 10),
          pw.Container(height: 4, decoration: pw.BoxDecoration(color: _amber, borderRadius: pw.BorderRadius.circular(2))),
        ],
      ),
    );

    final legend = fullBoard
        ? pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
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
          for (final entry in (blocks.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) ...[
            blockHeader(entry.key, entry.value.length),
            pw.Wrap(spacing: gap, runSpacing: gap, children: [for (final t in entry.value) card(t)]),
          ],
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
