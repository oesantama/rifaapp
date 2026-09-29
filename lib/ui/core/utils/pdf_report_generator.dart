import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rifaapp/data/models/winner.dart';
import 'package:rifaapp/ui/core/utils/file_saver.dart';

class PdfReportGenerator {
  static Future<void> generateAndDownloadDrawAuditPdf({
    required WinnerRecord winner,
    required String reason,
    required String adminUser,
  }) async {
    final pdf = pw.Document();
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final nowStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    final det = winner.winnerDetails;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue900,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'RIFA MASTER — CONTROL DE RIFAS Y ESPECTÁCULOS',
                          style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 13),
                        ),
                        pw.Text(
                          'INFORME OFICIAL DE AUDITORÍA Y ANULACIÓN DE SORTEO',
                          style: pw.TextStyle(color: PdfColors.white, fontSize: 10),
                        ),
                      ],
                    ),
                    pw.Text(
                      nowStr,
                      style: pw.TextStyle(color: PdfColors.white, fontSize: 9),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Title banner
              pw.Text(
                'DOCUMENTO DE AUDITORÍA PREVIO A LA ELIMINACIÓN',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Este informe certifica el registro histórico del sorteo antes de ser removido del sistema contable.',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
              pw.SizedBox(height: 16),

              // Draw Details Card
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('DATOS DEL SORTEO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.Divider(thickness: 0.5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Nombre del Sorteo: ${winner.drawName}'),
                        pw.Text('Número Ganador Jugado: #${winner.winningNumber}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('ID del Sorteo: ${winner.id}'),
                    pw.Text('Fecha de Registro del Sorteo: ${winner.drawDate}'),
                    pw.Text('Estado del Sorteo: ${winner.isWinner ? "GANADOR ENTREGADO" : "SORTEO ACUMULADO"}'),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),

              // Financial Breakdown
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('DESGLOSE FINANCIERO Y PREMIACIÓN', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.Divider(thickness: 0.5),
                    pw.Text('• Premio Base Sorteo: ${currency.format(winner.basePrizeAmount)} COP'),
                    pw.Text('• Pozo Acumulado Anterior: ${currency.format(winner.previousAccumulatedAmount)} COP'),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '• TOTAL PREMIO ENTREGADO / EVALUADO: ${currency.format(winner.totalPrizePaid)} COP',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.green900),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),

              // Winner Details (if winner exists)
              if (winner.isWinner && det != null) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.green800),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('DATOS DEL GANADOR DE LA BOLETA', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.green900)),
                      pw.Divider(thickness: 0.5),
                      pw.Text('• Boleta Ganadora N°: #${det.ticketNumber}'),
                      pw.Text('• Comprador: ${det.buyerName} (Tel: ${det.buyerPhone})'),
                      pw.Text('• Asesor de Venta: ${det.advisorName}'),
                      pw.Text('• Total Abonado / Pagado: ${currency.format(det.totalPaid)}'),
                      pw.SizedBox(height: 6),
                      pw.Text('Historial de Abonos / Pagos Registrados:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      if (det.abonosSummary.isEmpty)
                        pw.Text('  • Fecha de Venta: ${det.assignedDate ?? "N/A"}')
                      else
                        ...det.abonosSummary.map(
                          (a) => pw.Text('  • ${a['date']}: ${currency.format(a['amount'])} (${a['note'] ?? "Abono"}) — Asesor: ${a['sellerName'] ?? det.advisorName}'),
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 14),
              ],

              // Audit Reason and Deletion Stamp
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.red50,
                  border: pw.Border.all(color: PdfColors.red300),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('MOTIVO Y REGISTRO DE ELIMINACIÓN', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.red900)),
                    pw.Divider(thickness: 0.5),
                    pw.Text('• Administrador Responsable: $adminUser'),
                    pw.Text('• Motivo de Eliminación Especificado: "$reason"', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('• Fecha y Hora de Descarga/Anulación: $nowStr'),
                  ],
                ),
              ),
              pw.Spacer(),

              // Footer Stamp
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Certificado Contable RIFA MASTER', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                  pw.Text('Página 1 de 1', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                ],
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    final filename = 'Informe_Cierre_Sorteo_${winner.winningNumber}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    saveAndDownloadBytes(filename, bytes, mimeType: 'application/pdf');
  }
}
