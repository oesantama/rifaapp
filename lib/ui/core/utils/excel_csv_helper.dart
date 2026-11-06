import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import '../../../data/models/advisor.dart';
import '../../../data/models/ticket.dart';
import 'file_saver.dart';

class ExcelCsvHelper {
  /// Pure Dart CSV generator fallback
  static String _rowsToCsv(List<List<dynamic>> rows) {
    return rows.map((row) {
      return row.map((cell) {
        String str = cell.toString().replaceAll('"', '""');
        if (str.contains(',') || str.contains('\n') || str.contains('"')) {
          return '"$str"';
        }
        return str;
      }).join(',');
    }).join('\n');
  }

  /// Pure Dart CSV parser fallback
  static List<List<String>> _csvToRows(String csvContent) {
    List<List<String>> rows = [];
    List<String> lines = csvContent.split(RegExp(r'\r?\n'));
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      List<String> cells = [];
      StringBuffer current = StringBuffer();
      bool inQuotes = false;
      for (int i = 0; i < line.length; i++) {
        String char = line[i];
        if (char == '"') {
          inQuotes = !inQuotes;
        } else if (char == ',' && !inQuotes) {
          cells.add(current.toString().trim());
          current.clear();
        } else {
          current.write(char);
        }
      }
      cells.add(current.toString().trim());
      rows.add(cells);
    }
    return rows;
  }

  /// Downloads native Excel (.xlsx) template for custom ticket numbers
  static void downloadNumbersTemplate(int totalTickets, int digits, int opps) {
    try {
      var excel = Excel.createExcel();
      String defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      excel.rename(defaultSheet, 'Asignacion_Numeros');
      Sheet mainSheet = excel['Asignacion_Numeros'];

      List<CellValue> header = [TextCellValue('NumeroBoleta')];
      for (int k = 1; k <= opps; k++) {
        header.add(TextCellValue('Numero_$k'));
      }
      mainSheet.appendRow(header);

      int sampleCount = totalTickets > 10 ? 10 : totalTickets;
      for (int i = 1; i <= sampleCount; i++) {
        List<CellValue> row = [IntCellValue(i)];
        for (int k = 0; k < opps; k++) {
          int numVal = (i - 1) + (k * totalTickets);
          row.add(TextCellValue(numVal.toString().padLeft(digits, '0')));
        }
        mainSheet.appendRow(row);
      }

      // HOJA 2: Instrucciones
      Sheet instSheet = excel['Instrucciones_Uso'];
      instSheet.appendRow([TextCellValue('Parametro'), TextCellValue('Detalle')]);
      instSheet.appendRow([TextCellValue('NumeroBoleta'), TextCellValue('Número consecutivo de la boleta (1, 2, 3...)')]);
      instSheet.appendRow(
          [TextCellValue('Numero_1..$opps'), TextCellValue('Números de oportunidad asignados a esa boleta (formato de $digits dígitos).')]);

      var fileBytes = excel.save();
      if (fileBytes != null) {
        saveAndDownloadBytes('plantilla_numeros_rifa_${digits}digitos.xlsx', fileBytes);
      }
    } catch (_) {
      String csv = _generateNumbersTemplateCsvString(totalTickets, digits, opps);
      saveAndDownloadFile('plantilla_numeros_rifa_${digits}digitos.csv', csv);
    }
  }

  static String _generateNumbersTemplateCsvString(int totalTickets, int digits, int opportunitiesPerTicket) {
    List<List<dynamic>> rows = [];
    List<String> header = ['NumeroBoleta'];
    for (int k = 1; k <= opportunitiesPerTicket; k++) {
      header.add('Numero_$k');
    }
    rows.add(header);

    int sampleCount = totalTickets > 5 ? 5 : totalTickets;
    for (int i = 1; i <= sampleCount; i++) {
      List<dynamic> row = [i];
      for (int k = 0; k < opportunitiesPerTicket; k++) {
        int numVal = (i - 1) + (k * totalTickets);
        row.add(numVal.toString().padLeft(digits, '0'));
      }
      rows.add(row);
    }
    return _rowsToCsv(rows);
  }

  /// Downloads native Excel (.xlsx) template for sold/reserved tickets with master sheets
  static void downloadSoldTicketsTemplate({List<Advisor>? advisors}) {
    try {
      var excel = Excel.createExcel();
      String defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      excel.rename(defaultSheet, 'Boletas_Vendidas');
      Sheet mainSheet = excel['Boletas_Vendidas'];

      // HOJA 1: Boletas_Vendidas
      List<CellValue> header = [
        TextCellValue('NumeroBoleta'),
        TextCellValue('NombreComprador'),
        TextCellValue('TelefonoComprador'),
        TextCellValue('MontoAbonado'),
        TextCellValue('NombreAsesor'),
        TextCellValue('CedulaAsesor'),
        TextCellValue('Estado'),
        TextCellValue('Observaciones')
      ];
      mainSheet.appendRow(header);

      mainSheet.appendRow([
        IntCellValue(1),
        TextCellValue('Juan Pérez'),
        TextCellValue('3114445566'),
        IntCellValue(50000),
        TextCellValue('Carlos Mendoza'),
        TextCellValue('ADV01'),
        TextCellValue('PAGADA'),
        TextCellValue('Pago completo boleta 1')
      ]);

      mainSheet.appendRow([
        IntCellValue(2),
        TextCellValue('María Rodríguez'),
        TextCellValue('3009876543'),
        IntCellValue(10000),
        TextCellValue('Carlos Mendoza'),
        TextCellValue('ADV01'),
        TextCellValue('ABONO_PARCIAL'),
        TextCellValue('Abono inicial 10 mil pesos')
      ]);

      mainSheet.appendRow([
        IntCellValue(3),
        TextCellValue('Pedro Gómez'),
        TextCellValue('3201112233'),
        IntCellValue(0),
        TextCellValue('María Gomez'),
        TextCellValue('ADV02'),
        TextCellValue('RESERVADA'),
        TextCellValue('Boleta apartada sin abono')
      ]);

      // HOJA 2: Estados_Permitidos (Maestra de Estados)
      Sheet statesSheet = excel['Estados_Permitidos'];
      statesSheet.appendRow([TextCellValue('Estado'), TextCellValue('Etiqueta'), TextCellValue('Descripción / Cuándo Usar')]);
      statesSheet.appendRow(
          [TextCellValue('PAGADA'), TextCellValue('Pagada Total'), TextCellValue('La boleta ha sido cancelada al 100% por el comprador.')]);
      statesSheet.appendRow([
        TextCellValue('ABONO_PARCIAL'),
        TextCellValue('Abono Parcial'),
        TextCellValue('La boleta tiene un pago parcial (mayor a \$0 y menor al precio total).')
      ]);
      statesSheet.appendRow([
        TextCellValue('RESERVADA'),
        TextCellValue('Apartada / Fiada'),
        TextCellValue('La boleta está separada a nombre del comprador pero aún no se ha abonado dinero (\$0).')
      ]);

      // HOJA 3: Asesores_Registrados (Maestra de Asesores)
      Sheet advSheet = excel['Asesores_Registrados'];
      advSheet.appendRow(
          [TextCellValue('CedulaAsesor'), TextCellValue('NombreAsesor'), TextCellValue('Telefono'), TextCellValue('ModoTrabajo')]);

      if (advisors != null && advisors.isNotEmpty) {
        for (var adv in advisors) {
          advSheet.appendRow([
            TextCellValue(adv.code),
            TextCellValue(adv.name),
            TextCellValue(adv.phone),
            TextCellValue(adv.mode == 'POOL_GENERAL' ? 'Pool General' : 'Asignación Fija')
          ]);
        }
      } else {
        advSheet.appendRow(
            [TextCellValue('ADV01'), TextCellValue('Carlos Mendoza'), TextCellValue('3001234567'), TextCellValue('Pool General')]);
        advSheet.appendRow(
            [TextCellValue('ADV02'), TextCellValue('Maria Fernanda Gomez'), TextCellValue('3159876543'), TextCellValue('Asignación Fija')]);
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        saveAndDownloadBytes('plantilla_boletas_vendidas.xlsx', fileBytes);
      }
    } catch (_) {
      String csv = _generateSoldTicketsTemplateCsvString();
      saveAndDownloadFile('plantilla_boletas_vendidas.csv', csv);
    }
  }

  static String _generateSoldTicketsTemplateCsvString() {
    List<List<dynamic>> rows = [
      ['NumeroBoleta', 'NombreComprador', 'TelefonoComprador', 'MontoAbonado', 'NombreAsesor', 'CedulaAsesor', 'Estado', 'Observaciones'],
      [1, 'Juan Pérez', '3114445566', 50000, 'Carlos Mendoza', 'ADV01', 'PAGADA', 'Pago completo boleta 1'],
      [2, 'María Rodríguez', '3009876543', 10000, 'Carlos Mendoza', 'ADV01', 'ABONO_PARCIAL', 'Abono inicial 10 mil pesos'],
      [3, 'Pedro Gómez', '3201112233', 0, 'María Gomez', 'ADV02', 'RESERVADA', 'Boleta apartada sin abono'],
    ];
    return _rowsToCsv(rows);
  }

  /// Parses bytes from an Excel (.xlsx) or CSV file containing custom numbers
  static Map<int, List<String>> parseNumbersFromBytes(List<int> bytes, int digits) {
    Map<int, List<String>> result = {};
    try {
      var excel = Excel.decodeBytes(bytes);
      for (var table in excel.tables.keys) {
        // Only process main sheet (skip instructions sheet if present)
        if (table.toLowerCase().contains('instruccion')) continue;

        var sheet = excel.tables[table];
        if (sheet == null || sheet.maxRows == 0) continue;

        int startRow = 0;
        var firstCell = sheet.rows.first.isNotEmpty ? sheet.rows.first[0]?.value?.toString() : null;
        if (firstCell != null && firstCell.toLowerCase().contains('boleta')) {
          startRow = 1;
        }

        for (int i = startRow; i < sheet.rows.length; i++) {
          var row = sheet.rows[i];
          if (row.isEmpty) continue;

          String firstVal = row[0]?.value?.toString().trim() ?? '';
          int? tktNum = int.tryParse(firstVal);
          if (tktNum == null) continue;

          List<String> series = [];
          for (int c = 1; c < row.length; c++) {
            String val = row[c]?.value?.toString().trim() ?? '';
            if (val.isNotEmpty) {
              String clean = val.replaceAll(RegExp(r'\D'), '');
              if (clean.isNotEmpty) {
                series.add(clean.padLeft(digits, '0'));
              }
            }
          }
          if (series.isNotEmpty) {
            result[tktNum] = series;
          }
        }
        if (result.isNotEmpty) break;
      }
      if (result.isNotEmpty) return result;
    } catch (_) {}

    // Fallback to text string CSV parsing
    try {
      String textContent = String.fromCharCodes(bytes);
      return parseNumbersCsv(textContent, digits);
    } catch (_) {}

    return result;
  }

  /// Parses CSV string text containing custom numbers per ticket
  static Map<int, List<String>> parseNumbersCsv(String csvContent, int digits) {
    Map<int, List<String>> result = {};
    List<List<String>> rows = _csvToRows(csvContent);
    if (rows.isEmpty) return result;

    int startRow = 0;
    if (rows.first.isNotEmpty && rows.first[0].toLowerCase().contains('boleta')) {
      startRow = 1;
    }

    for (int i = startRow; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      int? tktNum = int.tryParse(row[0].trim());
      if (tktNum == null) continue;

      List<String> series = [];
      for (int c = 1; c < row.length; c++) {
        String rawVal = row[c].trim();
        if (rawVal.isNotEmpty) {
          final splitVals = rawVal.split(RegExp(r'[,;]'));
          for (var item in splitVals) {
            String clean = item.trim().replaceAll(RegExp(r'\D'), '');
            if (clean.isNotEmpty) {
              series.add(clean.padLeft(digits, '0'));
            }
          }
        }
      }

      if (series.isNotEmpty) {
        result[tktNum] = series;
      }
    }

    return result;
  }

  /// Parses bytes from an Excel (.xlsx) or CSV file containing sold/reserved tickets
  static List<Map<String, dynamic>> parseSoldTicketsFromBytes(List<int> bytes) {
    List<Map<String, dynamic>> records = [];
    try {
      var excel = Excel.decodeBytes(bytes);
      for (var table in excel.tables.keys) {
        // Skip master reference sheets
        if (table.toLowerCase().contains('estado') || table.toLowerCase().contains('asesor')) continue;

        var sheet = excel.tables[table];
        if (sheet == null || sheet.maxRows == 0) continue;

        int startRow = 0;
        var firstCell = sheet.rows.first.isNotEmpty ? sheet.rows.first[0]?.value?.toString() : null;
        if (firstCell != null && firstCell.toLowerCase().contains('boleta')) {
          startRow = 1;
        }

        for (int i = startRow; i < sheet.rows.length; i++) {
          var row = sheet.rows[i];
          if (row.isEmpty) continue;

          String firstVal = row[0]?.value?.toString().trim() ?? '';
          int? ticketNumber = int.tryParse(firstVal);
          if (ticketNumber == null) continue;

          String buyerName = row.length > 1 ? (row[1]?.value?.toString().trim() ?? '') : '';
          String buyerPhone = row.length > 2 ? (row[2]?.value?.toString().replaceAll(RegExp(r'\D'), '').trim() ?? '') : '';
          double amountPaid = row.length > 3 ? (double.tryParse(row[3]?.value?.toString().trim() ?? '0') ?? 0.0) : 0.0;
          String sellerName = row.length > 4 ? (row[4]?.value?.toString().trim() ?? '') : '';
          String sellerCode = row.length > 5 ? (row[5]?.value?.toString().trim() ?? '') : '';
          String statusRaw = row.length > 6 ? (row[6]?.value?.toString().trim().toUpperCase() ?? '') : '';
          String note = row.length > 7 ? (row[7]?.value?.toString().trim() ?? '') : '';

          String status = 'DISPONIBLE';
          if (statusRaw == 'PAGADA' || statusRaw == 'PAGADO' || statusRaw == 'CONFIRMADA') {
            status = 'PAGADA';
          } else if (statusRaw == 'ABONADA' || statusRaw == 'ABONO_PARCIAL' || statusRaw == 'ABONO') {
            status = 'ABONO_PARCIAL';
          } else if (statusRaw == 'APARTADA' || statusRaw == 'RESERVADA' || statusRaw == 'FIADA') {
            status = 'RESERVADA';
          } else if (amountPaid > 0) {
            status = 'ABONO_PARCIAL';
          } else if (buyerName.isNotEmpty) {
            status = 'RESERVADA';
          }

          records.add({
            'ticketNumber': ticketNumber,
            'buyerName': buyerName,
            'buyerPhone': buyerPhone,
            'amountPaid': amountPaid,
            'sellerName': sellerName,
            'sellerCode': sellerCode,
            'status': status,
            'note': note,
          });
        }

        if (records.isNotEmpty) break;
      }
      if (records.isNotEmpty) return records;
    } catch (_) {}

    try {
      String textContent = String.fromCharCodes(bytes);
      return parseSoldTicketsCsv(textContent);
    } catch (_) {}

    return records;
  }

  /// Parses CSV string text containing sold/reserved ticket details
  static List<Map<String, dynamic>> parseSoldTicketsCsv(String csvContent) {
    List<Map<String, dynamic>> records = [];
    List<List<String>> rows = _csvToRows(csvContent);
    if (rows.isEmpty) return records;

    int startRow = 0;
    if (rows.first.isNotEmpty && rows.first[0].toLowerCase().contains('boleta')) {
      startRow = 1;
    }

    for (int i = startRow; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      int? ticketNumber = int.tryParse(row[0].trim());
      if (ticketNumber == null) continue;

      String buyerName = row.length > 1 ? row[1].trim() : '';
      String buyerPhone = row.length > 2 ? row[2].replaceAll(RegExp(r'\D'), '').trim() : '';
      double amountPaid = row.length > 3 ? (double.tryParse(row[3].trim()) ?? 0.0) : 0.0;
      String sellerName = row.length > 4 ? row[4].trim() : '';
      String sellerCode = row.length > 5 ? row[5].trim() : '';
      String statusRaw = row.length > 6 ? row[6].trim().toUpperCase() : '';
      String note = row.length > 7 ? row[7].trim() : '';

      String status = 'DISPONIBLE';
      if (statusRaw == 'PAGADA' || statusRaw == 'PAGADO' || statusRaw == 'CONFIRMADA') {
        status = 'PAGADA';
      } else if (statusRaw == 'ABONADA' || statusRaw == 'ABONO_PARCIAL' || statusRaw == 'ABONO') {
        status = 'ABONO_PARCIAL';
      } else if (statusRaw == 'APARTADA' || statusRaw == 'RESERVADA' || statusRaw == 'FIADA') {
        status = 'RESERVADA';
      } else if (amountPaid > 0) {
        status = 'ABONO_PARCIAL';
      } else if (buyerName.isNotEmpty) {
        status = 'RESERVADA';
      }

      records.add({
        'ticketNumber': ticketNumber,
        'buyerName': buyerName,
        'buyerPhone': buyerPhone,
        'amountPaid': amountPaid,
        'sellerName': sellerName,
        'sellerCode': sellerCode,
        'status': status,
        'note': note,
      });
    }

    return records;
  }

  /// Exports a list of [Ticket] objects to an Excel (.xlsx) file with fallback to CSV
  /// History of voided sales and payments (admin "Control" screen).
  static void exportVoidHistoryToExcel(List<Map<String, dynamic>> entries) {
    const headers = ['Fecha anulación', 'Tipo', 'Rifa', 'Número(s)', 'Comprador', 'Teléfono', 'Cédula', 'Asesor', 'Medio', 'Valor', 'Anulado por', 'Motivo'];
    String fmt(dynamic iso) {
      final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
      return d == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(d);
    }

    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(sheetName, 'Anulaciones');
    final sheet = excel['Anulaciones'];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    for (final e in entries) {
      sheet.appendRow([
        TextCellValue(fmt(e['date'])),
        TextCellValue(e['type'] == 'VENTA' ? 'Venta anulada' : 'Abono anulado'),
        TextCellValue('${e['raffleTitle'] ?? ''}'),
        TextCellValue(((e['numbers'] as List?) ?? []).join(' - ')),
        TextCellValue('${e['buyerName'] ?? ''}'),
        TextCellValue('${e['buyerPhone'] ?? ''}'),
        TextCellValue('${e['buyerDocument'] ?? ''}'),
        TextCellValue('${e['advisorName'] ?? ''}'),
        TextCellValue('${e['saleChannel'] ?? ''}'),
        IntCellValue(((e['amount'] as num?) ?? 0).round()),
        TextCellValue('${e['by'] ?? ''}'),
        TextCellValue('${e['reason'] ?? ''}'),
      ]);
    }
    final bytes = excel.save();
    if (bytes != null) saveAndDownloadBytes('historial_anulaciones_${DateTime.now().millisecondsSinceEpoch}.xlsx', bytes);
  }

  static void exportTicketsToExcel(List<Ticket> tickets, {String title = 'Reporte_Boletas'}) {
    // Ordered by the opportunity number the buyer plays; the internal ticket index is not exported.
    // Money values are whole pesos (no decimals).
    final rowsSource = [...tickets]..sort((a, b) => a.sortNumber.compareTo(b.sortNumber));
    const headers = [
      'Número(s) Oportunidad',
      'Estado',
      'Comprador',
      'Teléfono',
      'Cédula',
      'Precio Boleta',
      'Total Abonado',
      'Saldo Pendiente',
      'Asesor / Vendedor',
      'Medio de Venta',
      'Confirmada Admin',
    ];

    try {
      var excel = Excel.createExcel();
      String defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      excel.rename(defaultSheet, 'Boletas');
      Sheet sheet = excel['Boletas'];

      sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

      for (var t in rowsSource) {
        sheet.appendRow([
          // Text keeps leading zeros (e.g. 02)
          TextCellValue(t.displayNumber),
          TextCellValue(t.status),
          TextCellValue(t.buyerName.isNotEmpty ? t.buyerName : 'N/A'),
          TextCellValue(t.buyerPhone.isNotEmpty ? t.buyerPhone : 'N/A'),
          TextCellValue(t.buyerDocument.isNotEmpty ? t.buyerDocument : 'N/A'),
          IntCellValue(t.price.round()),
          IntCellValue(t.totalPaid.round()),
          IntCellValue(t.balancePending.round()),
          TextCellValue(t.advisorName.isNotEmpty ? t.advisorName : 'N/A'),
          TextCellValue(t.saleChannel.isNotEmpty ? t.saleChannel : 'N/A'),
          TextCellValue(t.confirmedByAdmin ? 'SI' : 'NO'),
        ]);
      }

      var fileBytes = excel.save();
      if (fileBytes != null) {
        String cleanTitle = title.replaceAll(RegExp(r'[^\w\-]'), '_');
        saveAndDownloadBytes('${cleanTitle}_${DateTime.now().millisecondsSinceEpoch}.xlsx', fileBytes);
      }
    } catch (_) {
      List<List<dynamic>> rows = [
        headers,
        ...rowsSource.map((t) => [
              t.displayNumber,
              t.status,
              t.buyerName.isNotEmpty ? t.buyerName : 'N/A',
              t.buyerPhone.isNotEmpty ? t.buyerPhone : 'N/A',
              t.buyerDocument.isNotEmpty ? t.buyerDocument : 'N/A',
              t.price.round(),
              t.totalPaid.round(),
              t.balancePending.round(),
              t.advisorName.isNotEmpty ? t.advisorName : 'N/A',
              t.saleChannel.isNotEmpty ? t.saleChannel : 'N/A',
              t.confirmedByAdmin ? 'SI' : 'NO',
            ]),
      ];
      String cleanTitle = title.replaceAll(RegExp(r'[^\w\-]'), '_');
      saveAndDownloadFile('${cleanTitle}_${DateTime.now().millisecondsSinceEpoch}.csv', _rowsToCsv(rows));
    }
  }

  /// Exports available or all numbers to Excel (.xlsx) with:
  /// 1. 'Sabana_Matriz': Grid matrix of numbers (e.g. 20 columns like in Image 3) with status colors (Yellow for reserved, White for available, Red for sold).
  /// 2. 'Listado_Detallado': Table by ticket with actual opportunity numbers (no confusing sequential IDs).
  /// 3. Guaranteed file name 'numeros_disponibles.xlsx'.
  static void exportAvailableNumbersToExcel({
    required List<Ticket> availableTickets,
    required String raffleTitle,
    List<Ticket>? allTickets,
    String? advisorName,
    double? ticketPrice,
    String? drawDate,
    String? lotteryName,
    int matrixColumns = 20,
    String contentMode = 'ONLY_AVAILABLE', // 'ONLY_AVAILABLE', 'ALL_STATUS', 'BY_ADVISOR'
    int? maxNumbersCount,
    bool includeMatrixSheet = true,
    bool includeDetailedList = true,
  }) {
    final currency = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
    final scopeLabel = (advisorName != null && advisorName.trim().isNotEmpty) ? advisorName.trim() : 'General (Toda la Rifa)';

    // Source tickets based on mode
    List<Ticket> ticketsToProcess;
    if (contentMode == 'ALL_STATUS' && allTickets != null && allTickets.isNotEmpty) {
      ticketsToProcess = [...allTickets]..sort((a, b) => a.sortNumber.compareTo(b.sortNumber));
    } else {
      ticketsToProcess = [...availableTickets]..sort((a, b) => a.sortNumber.compareTo(b.sortNumber));
    }

    if (maxNumbersCount != null && maxNumbersCount > 0 && ticketsToProcess.length > maxNumbersCount) {
      ticketsToProcess = ticketsToProcess.take(maxNumbersCount).toList();
    }

    const String exportFileName = 'numeros_disponibles.xlsx';

    try {
      var excel = Excel.createExcel();
      String defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';

      // -------------------------------------------------------------
      // HOJA 1: SABANA MATRIZ (ESTILO IMAGEN 3)
      // -------------------------------------------------------------
      if (includeMatrixSheet) {
        excel.rename(defaultSheet, 'Sabana_Matriz');
        Sheet matrixSheet = excel['Sabana_Matriz'];

        // Header
        matrixSheet.appendRow([TextCellValue('SÁBANA DE NÚMEROS - ${raffleTitle.toUpperCase()}')]);
        matrixSheet.appendRow([
          TextCellValue('Alcance: $scopeLabel'),
          TextCellValue('Modo: ${contentMode == "ALL_STATUS" ? "Todos con Estado" : "Solo Disponibles"}'),
          TextCellValue('Fecha: ${DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now())}'),
        ]);

        // Color Legend row
        matrixSheet.appendRow([
          TextCellValue('🟢 BLANCO/VERDE = DISPONIBLE'),
          TextCellValue('🟡 AMARILLO = APARTADO / RESERVADO'),
          TextCellValue('🔴 ROJO = PAGADO / VENDIDO'),
        ]);
        matrixSheet.appendRow([]); // Espaciador

        // Gather all individual numbers with their ticket status
        // A ticket may have multiple opportunities; each is placed in the grid
        final List<Map<String, dynamic>> numberItems = [];
        for (var t in ticketsToProcess) {
          final st = t.status.toUpperCase();
          final isAvail = st == 'DISPONIBLE';
          final isReserved = st == 'RESERVADA' || st == 'ABONO_PARCIAL';
          final isSold = st == 'PAGADA' || st == 'VENDIDA' || st == 'CONFIRMADA';
          final numStatus = isAvail
              ? 'AVAILABLE'
              : (isReserved ? 'RESERVED' : (isSold ? 'SOLD' : 'OTHER'));

          if (t.numbers.isNotEmpty) {
            for (var n in t.numbers) {
              numberItems.add({
                'number': n,
                'status': numStatus,
                'ticket': t,
              });
            }
          } else {
            numberItems.add({
              'number': t.displayNumber,
              'status': numStatus,
              'ticket': t,
            });
          }
        }

        // Apply number limit if requested on individual items
        final itemsToGrid = (maxNumbersCount != null && maxNumbersCount > 0 && numberItems.length > maxNumbersCount)
            ? numberItems.take(maxNumbersCount).toList()
            : numberItems;

        // Build matrix header (Col 1, Col 2, ... Col N)
        final cols = matrixColumns > 0 ? matrixColumns : 20;
        final matrixHeader = <CellValue>[];
        for (int c = 1; c <= cols; c++) {
          matrixHeader.add(TextCellValue('C$c'));
        }
        matrixSheet.appendRow(matrixHeader);

        // Predefine cell styles
        CellStyle? styleAvailable;
        CellStyle? styleReserved;
        CellStyle? styleSold;

        try {
          styleAvailable = CellStyle(
            backgroundColorHex: ExcelColor.fromHexString('FFFFFF'),
            fontColorHex: ExcelColor.black,
            horizontalAlign: HorizontalAlign.Center,
            verticalAlign: VerticalAlign.Center,
            bold: false,
            fontSize: 10,
          );
          styleReserved = CellStyle(
            backgroundColorHex: ExcelColor.fromHexString('FFFF00'), // Yellow as in Image 3
            fontColorHex: ExcelColor.black,
            horizontalAlign: HorizontalAlign.Center,
            verticalAlign: VerticalAlign.Center,
            bold: true,
            fontSize: 10,
          );
          styleSold = CellStyle(
            backgroundColorHex: ExcelColor.fromHexString('FEE2E2'), // Light red
            fontColorHex: ExcelColor.black,
            horizontalAlign: HorizontalAlign.Center,
            verticalAlign: VerticalAlign.Center,
            bold: false,
            fontSize: 10,
          );
        } catch (_) {}

        if (itemsToGrid.isEmpty) {
          matrixSheet.appendRow([TextCellValue('No hay números disponibles o asignados con este alcance.')]);
        } else {
          for (int r = 0; r < itemsToGrid.length; r += cols) {
            final end = (r + cols > itemsToGrid.length) ? itemsToGrid.length : r + cols;
            final chunk = itemsToGrid.sublist(r, end);

            final rowCells = <CellValue>[];
            for (var item in chunk) {
              rowCells.add(TextCellValue(item['number'] as String));
            }
            matrixSheet.appendRow(rowCells);

            final rowIndex = matrixSheet.maxRows - 1;
            for (int c = 0; c < chunk.length; c++) {
              final status = chunk[c]['status'] as String;
              try {
                final cell = matrixSheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex));
                if (status == 'RESERVED' && styleReserved != null) {
                  cell.cellStyle = styleReserved;
                } else if (status == 'SOLD' && styleSold != null) {
                  cell.cellStyle = styleSold;
                } else if (styleAvailable != null) {
                  cell.cellStyle = styleAvailable;
                }
              } catch (_) {}
            }
          }
        }
      }

      // -------------------------------------------------------------
      // HOJA 2: LISTADO DETALLADO
      // -------------------------------------------------------------
      if (includeDetailedList || !includeMatrixSheet) {
        final detailSheetName = includeMatrixSheet ? 'Listado_Detallado' : 'Disponibles';
        if (!includeMatrixSheet) {
          excel.rename(defaultSheet, detailSheetName);
        }
        Sheet detailSheet = excel[detailSheetName];

        detailSheet.appendRow([TextCellValue('REPORTE DETALLADO - ${raffleTitle.toUpperCase()}')]);
        detailSheet.appendRow([TextCellValue('Alcance:'), TextCellValue(scopeLabel)]);
        detailSheet.appendRow([TextCellValue('Total Boletas:'), IntCellValue(ticketsToProcess.length)]);
        if (ticketPrice != null) {
          detailSheet.appendRow([TextCellValue('Valor Boleta:'), TextCellValue(currency.format(ticketPrice))]);
        }
        if (drawDate != null && drawDate.isNotEmpty) {
          detailSheet.appendRow([TextCellValue('Fecha Sorteo:'), TextCellValue(drawDate), TextCellValue('Lotería:'), TextCellValue(lotteryName ?? '')]);
        }
        detailSheet.appendRow([TextCellValue('Fecha Generación:'), TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()))]);
        detailSheet.appendRow([]); // Espacio

        final maxOpps = ticketsToProcess.fold<int>(1, (max, t) => t.numbers.length > max ? t.numbers.length : max);

        // HEADERS: Actual primary number first, NOT confusing ticketNumber index
        final headers = <String>[];
        if (maxOpps > 1) {
          for (int k = 1; k <= maxOpps; k++) {
            headers.add('Oportunidad $k');
          }
        } else {
          headers.add('Número Boleta');
        }
        headers.addAll([
          'Número Completo',
          'Precio',
          'Estado',
          'Asesor Asignado',
        ]);
        detailSheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

        for (var t in ticketsToProcess) {
          final row = <CellValue>[];
          if (maxOpps > 1) {
            for (int k = 0; k < maxOpps; k++) {
              final oppVal = k < t.numbers.length ? t.numbers[k] : '';
              row.add(TextCellValue(oppVal));
            }
          } else {
            row.add(TextCellValue(t.displayNumber));
          }
          row.addAll([
            TextCellValue(t.displayNumber),
            IntCellValue(t.price.round()),
            TextCellValue(t.status.toUpperCase()),
            TextCellValue(t.advisorName.isNotEmpty ? t.advisorName : (advisorName ?? 'Sin asignar / Pool')),
          ]);
          detailSheet.appendRow(row);
        }
      }

      // Encode bytes without invoking the default web save that forces 'FlutterExcel.xlsx'
      final fileBytes = excel.encode() ?? excel.save(fileName: exportFileName);
      if (fileBytes != null) {
        saveAndDownloadBytes(exportFileName, fileBytes);
      }
    } catch (_) {
      // CSV Fallback with proper primary number headers
      final maxOpps = ticketsToProcess.fold<int>(1, (max, t) => t.numbers.length > max ? t.numbers.length : max);
      final headers = <dynamic>[];
      if (maxOpps > 1) {
        for (int k = 1; k <= maxOpps; k++) {
          headers.add('Oportunidad $k');
        }
      } else {
        headers.add('Número Boleta');
      }
      headers.addAll(['Número Completo', 'Precio', 'Estado', 'Asesor Asignado']);

      List<List<dynamic>> rows = [
        ['REPORTE DE NÚMEROS DISPONIBLES'],
        ['Rifa:', raffleTitle],
        ['Alcance:', scopeLabel],
        ['Total Boletas:', ticketsToProcess.length],
        if (ticketPrice != null) ['Valor Boleta:', currency.format(ticketPrice)],
        ['Fecha Generación:', DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())],
        [],
        headers,
        ...ticketsToProcess.map((t) {
          final row = <dynamic>[];
          if (maxOpps > 1) {
            for (int k = 0; k < maxOpps; k++) {
              row.add(k < t.numbers.length ? t.numbers[k] : '');
            }
          } else {
            row.add(t.displayNumber);
          }
          row.addAll([
            t.displayNumber,
            t.price.round(),
            t.status.toUpperCase(),
            t.advisorName.isNotEmpty ? t.advisorName : (advisorName ?? 'Sin asignar / Pool'),
          ]);
          return row;
        }),
      ];
      saveAndDownloadFile('numeros_disponibles.csv', _rowsToCsv(rows));
    }
  }

}

