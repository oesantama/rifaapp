import 'package:excel/excel.dart';
import '../../../data/models/advisor.dart';
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
      instSheet.appendRow([TextCellValue('Numero_1..$opps'), TextCellValue('Números de oportunidad asignados a esa boleta (formato de $digits dígitos).')]);

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
      statesSheet.appendRow([
        TextCellValue('Estado'),
        TextCellValue('Etiqueta'),
        TextCellValue('Descripción / Cuándo Usar')
      ]);
      statesSheet.appendRow([
        TextCellValue('PAGADA'),
        TextCellValue('Pagada Total'),
        TextCellValue('La boleta ha sido cancelada al 100% por el comprador.')
      ]);
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
      advSheet.appendRow([
        TextCellValue('CedulaAsesor'),
        TextCellValue('NombreAsesor'),
        TextCellValue('Telefono'),
        TextCellValue('ModoTrabajo')
      ]);

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
        advSheet.appendRow([
          TextCellValue('ADV01'),
          TextCellValue('Carlos Mendoza'),
          TextCellValue('3001234567'),
          TextCellValue('Pool General')
        ]);
        advSheet.appendRow([
          TextCellValue('ADV02'),
          TextCellValue('Maria Fernanda Gomez'),
          TextCellValue('3159876543'),
          TextCellValue('Asignación Fija')
        ]);
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
      [
        'NumeroBoleta',
        'NombreComprador',
        'TelefonoComprador',
        'MontoAbonado',
        'NombreAsesor',
        'CedulaAsesor',
        'Estado',
        'Observaciones'
      ],
      [
        1,
        'Juan Pérez',
        '3114445566',
        50000,
        'Carlos Mendoza',
        'ADV01',
        'PAGADA',
        'Pago completo boleta 1'
      ],
      [
        2,
        'María Rodríguez',
        '3009876543',
        10000,
        'Carlos Mendoza',
        'ADV01',
        'ABONO_PARCIAL',
        'Abono inicial 10 mil pesos'
      ],
      [
        3,
        'Pedro Gómez',
        '3201112233',
        0,
        'María Gomez',
        'ADV02',
        'RESERVADA',
        'Boleta apartada sin abono'
      ],
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
}
