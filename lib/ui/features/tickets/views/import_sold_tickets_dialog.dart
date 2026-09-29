import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/excel_csv_helper.dart';
import 'package:rifaapp/ui/core/utils/file_picker_helper.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';

class ImportSoldTicketsDialog extends StatefulWidget {
  final String raffleId;
  final String? raffleTitle;

  const ImportSoldTicketsDialog({
    super.key,
    required this.raffleId,
    this.raffleTitle,
  });

  @override
  State<ImportSoldTicketsDialog> createState() => _ImportSoldTicketsDialogState();
}

class _ImportSoldTicketsDialogState extends State<ImportSoldTicketsDialog> {
  List<Map<String, dynamic>>? _loadedRecords;
  String? _loadedFileName;
  bool _isProcessing = false;

  void _pickExcelFile() async {
    try {
      List<int>? bytes = await pickFileBytes(allowedExtensions: ['xlsx', 'xls', 'csv', 'txt']);
      if (bytes != null && bytes.isNotEmpty) {
        List<Map<String, dynamic>> records = ExcelCsvHelper.parseSoldTicketsFromBytes(bytes);

        if (records.isNotEmpty) {
          setState(() {
            _loadedRecords = records;
            _loadedFileName = 'archivo_boletas.xlsx';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.secondaryEmerald,
                content: Text('✓ Se cargaron ${records.length} registros del archivo Excel.'),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.red,
                content: Text('⚠️ No se encontraron registros de boletas válidos en el archivo.'),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error al leer archivo Excel: $e')),
        );
      }
    }
  }

  void _executeImport() async {
    if (_loadedRecords == null || _loadedRecords!.isEmpty) return;

    setState(() => _isProcessing = true);
    final ticketVM = Provider.of<TicketViewModel>(context, listen: false);

    bool ok = await ticketVM.importTickets(widget.raffleId, _loadedRecords!);

    if (mounted) {
      setState(() => _isProcessing = false);
      if (ok) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.secondaryEmerald,
            content: Text('¡Importación masiva completada! ${_loadedRecords!.length} boletas actualizadas.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('Error al procesar la importación en el servidor.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 650,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // HEADER
              Row(
                children: [
                  const Icon(Icons.file_upload_outlined, color: AppTheme.primaryBlue, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Importar / Actualizar Boletas desde Excel (.xlsx)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          widget.raffleTitle != null ? 'Sorteo: ${widget.raffleTitle}' : 'Sorteo Activo',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const Divider(height: 20),

              // CAJA EXPLICATIVA
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '¿Para qué sirve esta función?',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Esta herramienta te permite cargar o actualizar masivamente el estado de las boletas (Apartadas, Abonadas o Pagadas) con sus compradores y asesores correspondientes.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '📋 Campos requeridos en la plantilla Excel (.xlsx):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blueGrey),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '• NumeroBoleta (ej: 1, 2, 100)\n• NombreComprador y TelefonoComprador\n• MontoAbonado (ej: 50000)\n• NombreAsesor y CedulaAsesor\n• Estado (PAGADA, ABONO_PARCIAL, RESERVADA)',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // BOTONES DE PLANTILLA Y CARGA
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => ExcelCsvHelper.downloadSoldTicketsTemplate(),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Descargar Plantilla Excel (.xlsx)'),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _pickExcelFile,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Seleccionar Archivo Excel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // VISTA PREVIA DE REGISTROS CARGADOS
              if (_loadedRecords != null && _loadedRecords!.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Vista Previa de Registros a Importar (${_loadedRecords!.length} boletas):',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Chip(
                      avatar: const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      label: Text('📄 Archivo listo'),
                      backgroundColor: Colors.green.withValues(alpha: 0.1),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _loadedRecords!.length,
                    itemBuilder: (context, i) {
                      final rec = _loadedRecords![i];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: AppTheme.getStatusColor(rec['status']).withValues(alpha: 0.2),
                          child: Text(
                            '#${rec['ticketNumber']}',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.getStatusColor(rec['status'])),
                          ),
                        ),
                        title: Text(
                          'Boleta #${rec['ticketNumber']} - ${rec['buyerName'].isNotEmpty ? rec['buyerName'] : "Sin comprador"}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        subtitle: Text(
                          'Tel: ${rec['buyerPhone']} • Asesor: ${rec['sellerName']} (${rec['sellerCode']}) • ${rec['note']}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              rec['status'],
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.getStatusColor(rec['status'])),
                            ),
                            Text(
                              currency.format(rec['amountPaid']),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const Divider(),
              const SizedBox(height: 10),

              // BOTONES DE ACCIÓN
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isProcessing ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: (_loadedRecords != null && _loadedRecords!.isNotEmpty && !_isProcessing)
                        ? _executeImport
                        : null,
                    icon: _isProcessing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: Text(_isProcessing ? 'PROCESANDO...' : 'CONFIRMAR E IMPORTAR BOLETAS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
