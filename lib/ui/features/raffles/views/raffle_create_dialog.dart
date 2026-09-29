
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/core/utils/excel_csv_helper.dart';
import 'package:rifaapp/ui/core/utils/file_picker_helper.dart';
import 'package:rifaapp/ui/core/theme.dart';

class RaffleCreateDialog extends StatefulWidget {
  const RaffleCreateDialog({super.key});

  @override
  State<RaffleCreateDialog> createState() => _RaffleCreateDialogState();
}

class _RaffleCreateDialogState extends State<RaffleCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController(text: 'Gran Rifa Especial');
  final _descriptionController = TextEditingController(text: 'Sorteo con múltiples oportunidades por boleta');
  final _priceController = TextEditingController(text: '50000');
  final _totalTicketsController = TextEditingController(text: '2500');
  final _commissionValueController = TextEditingController(text: '10');

  int _digits = 4;
  String _generationMode = 'SECUENCIAL'; // SECUENCIAL, ALEATORIO, EXCEL
  String _commissionType = 'PORCENTAJE'; // PORCENTAJE or VALOR_FIJO

  Map<int, List<String>>? _customNumbersMap;
  String? _customNumbersFileName;

  List<Map<String, dynamic>>? _preSoldTicketsList;
  String? _preSoldFileName;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _totalTicketsController.dispose();
    _commissionValueController.dispose();
    super.dispose();
  }

  void _pickCustomNumbersFile(int opps) async {
    try {
      List<int>? bytes = await pickFileBytes(allowedExtensions: ['xlsx', 'xls', 'csv', 'txt']);
      if (bytes != null && bytes.isNotEmpty) {
        Map<int, List<String>> parsedMap = ExcelCsvHelper.parseNumbersFromBytes(bytes, _digits);

        if (parsedMap.isNotEmpty) {
          setState(() {
            _customNumbersMap = parsedMap;
            _customNumbersFileName = 'numeros_personalizados.xlsx';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.secondaryEmerald,
                content: Text('✓ Se cargaron ${parsedMap.length} boletas con números personalizados desde Excel.'),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.red,
                content: Text('⚠️ No se encontraron números válidos en el archivo Excel/CSV seleccionado.'),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error al leer archivo: $e')),
        );
      }
    }
  }

  void _pickPreSoldTicketsFile() async {
    try {
      List<int>? bytes = await pickFileBytes(allowedExtensions: ['xlsx', 'xls', 'csv', 'txt']);
      if (bytes != null && bytes.isNotEmpty) {
        List<Map<String, dynamic>> parsedList = ExcelCsvHelper.parseSoldTicketsFromBytes(bytes);

        if (parsedList.isNotEmpty) {
          setState(() {
            _preSoldTicketsList = parsedList;
            _preSoldFileName = 'boletas_vendidas.xlsx';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.secondaryEmerald,
                content: Text('✓ Se cargaron ${parsedList.length} registros de boletas desde Excel.'),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.red,
                content: Text('⚠️ No se encontraron registros válidos de boletas en el archivo Excel.'),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error al leer archivo: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalNumbers = 10000;
    if (_digits == 2) totalNumbers = 100;
    if (_digits == 3) totalNumbers = 1000;
    if (_digits == 5) totalNumbers = 100000;

    int totalTicketsInput = int.tryParse(_totalTicketsController.text) ?? 2500;
    int seriesCalculated = totalTicketsInput > 0 ? (totalNumbers ~/ totalTicketsInput) : 1;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 580,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.confirmation_number, color: AppTheme.primaryBlue, size: 28),
                    const SizedBox(width: 10),
                    const Text(
                      'Configurar Nuevo Sorteo / Rifa',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Configura los parámetros principales, distribución de números y datos iniciales.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Divider(height: 24),

                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Título del Sorteo *', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingrese un título' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Descripción / Asunto del Sorteo', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _digits,
                        decoration: const InputDecoration(labelText: 'Cantidad de Dígitos', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 2, child: Text('2 Dígitos (100 números)')),
                          DropdownMenuItem(value: 3, child: Text('3 Dígitos (1.000 números)')),
                          DropdownMenuItem(value: 4, child: Text('4 Dígitos (10.000 números)')),
                          DropdownMenuItem(value: 5, child: Text('5 Dígitos (100.000 números)')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _digits = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _totalTicketsController,
                        decoration: const InputDecoration(labelText: 'Cantidad de Boletas *', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => setState(() {}),
                        validator: (v) => (v == null || v.isEmpty || int.tryParse(v) == null) ? 'Ingrese cantidad de boletas' : null,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.08),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calculate, color: Colors.blue, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Números Calculados: $seriesCalculated por boleta',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Para $totalNumbers números repartidos en $totalTicketsInput boletas.',
                              style: const TextStyle(fontSize: 11, color: Colors.black87),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(labelText: 'Precio por Boleta (\$) *', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => (v == null || v.isEmpty || double.tryParse(v) == null) ? 'Ingrese precio' : null,
                ),

                const SizedBox(height: 14),

                // SECCIÓN COMISIÓN DE ASESORES
                const Text(
                  '💰 Esquema de Comisión / Ganancia para los Asesores:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Aplica por igual a todos los asesores que vendan boletas de este sorteo.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'PORCENTAJE',
                        groupValue: _commissionType,
                        title: const Text('Porcentaje (%)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onChanged: (v) => setState(() {
                          _commissionType = v!;
                          if (_commissionValueController.text == '5000') {
                            _commissionValueController.text = '10';
                          }
                        }),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'VALOR_FIJO',
                        groupValue: _commissionType,
                        title: const Text('Valor Fijo (\$ COP)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onChanged: (v) => setState(() {
                          _commissionType = v!;
                          if (_commissionValueController.text == '10') {
                            _commissionValueController.text = '5000';
                          }
                        }),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _commissionValueController,
                  decoration: InputDecoration(
                    labelText: _commissionType == 'PORCENTAJE' ? 'Porcentaje de Ganancia (%) *' : 'Valor Fijo por Boleta (\$ COP) *',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(_commissionType == 'PORCENTAJE' ? Icons.percent : Icons.attach_money),
                    helperText: _commissionType == 'PORCENTAJE'
                        ? 'Ejemplo: 10% de \$50.000 = \$5.000 COP de comisión por boleta.'
                        : 'Ejemplo: \$5.000 COP de comisión fija por cada boleta vendida.',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => (v == null || v.isEmpty || double.tryParse(v) == null) ? 'Ingrese valor de comisión' : null,
                ),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 6),

                // SECCIÓN MODO DE ASIGNACIÓN DE NÚMEROS
                const Text(
                  '🎲 Modo de Asignación de Números / Oportunidades:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),

                RadioListTile<String>(
                  value: 'SECUENCIAL',
                  groupValue: _generationMode,
                  title: const Text('Matemático / Secuencial (Recomendado)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Distribución uniforme matemática ordenada (Ej: 0000, 1000, 2000, 3000...).', style: TextStyle(fontSize: 11)),
                  onChanged: (v) => setState(() => _generationMode = v!),
                  dense: true,
                ),

                RadioListTile<String>(
                  value: 'ALEATORIO',
                  groupValue: _generationMode,
                  title: const Text('Aleatorio (Sorteo al Azar por Boleta)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Mezcla todos los números del 0000 al 9999 y asigna oportunidades completamente al azar.', style: TextStyle(fontSize: 11)),
                  onChanged: (v) => setState(() => _generationMode = v!),
                  dense: true,
                ),

                RadioListTile<String>(
                  value: 'EXCEL',
                  groupValue: _generationMode,
                  title: const Text('Importar Números Personalizados desde Excel / CSV', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Sube una matriz de números específicos por boleta asignados externamente.', style: TextStyle(fontSize: 11)),
                  onChanged: (v) => setState(() => _generationMode = v!),
                  dense: true,
                ),

                if (_generationMode == 'EXCEL') ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4, bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                ExcelCsvHelper.downloadNumbersTemplate(totalTicketsInput, _digits, seriesCalculated);
                              },
                              icon: const Icon(Icons.download, size: 16),
                              label: const Text('Descargar Plantilla Excel (.xlsx)', style: TextStyle(fontSize: 12)),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed: () => _pickCustomNumbersFile(seriesCalculated),
                              icon: const Icon(Icons.upload_file, size: 16),
                              label: Text(_customNumbersMap != null ? 'Cambiar Archivo' : 'Subir Archivo Excel', style: const TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade700),
                            ),
                          ],
                        ),
                        if (_customNumbersMap != null && _customNumbersMap!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50.withOpacity(0.5),
                              border: Border.all(color: Colors.purple.shade200),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '📋 Vista Previa de Números Asignados (${_customNumbersMap!.length} boletas):',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.purple.shade900),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _customNumbersMap = null;
                                          _customNumbersFileName = null;
                                        });
                                      },
                                      icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                                      label: const Text('Descartar', style: TextStyle(color: Colors.red, fontSize: 11)),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  constraints: const BoxConstraints(maxHeight: 140),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: _customNumbersMap!.length > 50 ? 50 : _customNumbersMap!.length,
                                    separatorBuilder: (context, i) => const Divider(height: 1),
                                    itemBuilder: (context, i) {
                                      int ticketNum = _customNumbersMap!.keys.elementAt(i);
                                      List<String> nums = _customNumbersMap![ticketNum] ?? [];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        child: Row(
                                          children: [
                                            Text(
                                              'Boleta #$ticketNum:',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                nums.join(' • '),
                                                style: TextStyle(fontSize: 11, color: Colors.purple.shade800, fontWeight: FontWeight.w500),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'ℹ️ Solo se crearán estos números al hacer clic en "CREAR Y GENERAR BOLETAS".',
                                  style: TextStyle(fontSize: 10, color: Colors.purple.shade900, fontStyle: FontStyle.italic),
                                )
                              ],
                            ),
                          )
                        ]
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 6),

                // SECCIÓN CARGA DE BOLETAS YA VENDIDAS / APARTADAS
                Row(
                  children: [
                    const Icon(Icons.file_upload_outlined, color: Colors.orange, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '📥 Inicio de Evento con Boletas Ya Vendidas / Apartadas (Excel .xlsx):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Si la rifa ya inició previamente en talonarios o redes, puedes cargar un archivo Excel (.xlsx) con las boletas apartadas/pagadas y sus compradores.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => ExcelCsvHelper.downloadSoldTicketsTemplate(),
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Plantilla Excel (.xlsx)', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: _pickPreSoldTicketsFile,
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: Text(_preSoldTicketsList != null ? 'Cambiar Archivo' : 'Cargar Boletas Excel', style: const TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
                    ),
                  ],
                ),

                if (_preSoldTicketsList != null && _preSoldTicketsList!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50.withOpacity(0.5),
                      border: Border.all(color: Colors.amber.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '📋 Registros de Boletas a Importar (${_preSoldTicketsList!.length} boletas):',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber.shade900),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _preSoldTicketsList = null;
                                  _preSoldFileName = null;
                                });
                              },
                              icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                              label: const Text('Descartar', style: TextStyle(color: Colors.red, fontSize: 11)),
                            )
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 160),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _preSoldTicketsList!.length,
                            separatorBuilder: (context, i) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final rec = _preSoldTicketsList![i];
                              final statusColor = AppTheme.getStatusColor(rec['status'] ?? 'DISPONIBLE');
                              final buyerName = (rec['buyerName'] != null && rec['buyerName'].toString().trim().isNotEmpty)
                                  ? rec['buyerName'].toString()
                                  : "Sin Nombre";
                              final sellerName = (rec['sellerName'] != null && rec['sellerName'].toString().trim().isNotEmpty)
                                  ? rec['sellerName'].toString()
                                  : "N/A";

                              return ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                leading: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: statusColor.withOpacity(0.15),
                                  child: Text(
                                    '#${rec['ticketNumber']}',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor),
                                  ),
                                ),
                                title: Text(
                                  'Boleta #${rec['ticketNumber']} — $buyerName',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                                subtitle: Text(
                                  'Tel: ${rec['buyerPhone'] ?? "N/A"} • Asesor: $sellerName',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                trailing: Text(
                                  rec['status'] ?? 'PENDIENTE',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ℹ️ Revise los datos. Se asignarán a la rifa al hacer clic en "CREAR Y GENERAR BOLETAS".',
                          style: TextStyle(fontSize: 10, color: Colors.amber.shade900, fontStyle: FontStyle.italic),
                        )
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          if (_generationMode == 'EXCEL' && (_customNumbersMap == null || _customNumbersMap!.isEmpty)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Colors.red,
                                content: Text('⚠️ Debe subir la plantilla CSV de números o seleccionar otro modo de generación.'),
                              ),
                            );
                            return;
                          }

                          final raffleVM = Provider.of<RaffleViewModel>(context, listen: false);
                          bool success = await raffleVM.createRaffle({
                            'title': _titleController.text.trim(),
                            'description': _descriptionController.text.trim(),
                            'digits': _digits,
                            'totalTickets': int.parse(_totalTicketsController.text),
                            'ticketPrice': double.parse(_priceController.text),
                            'commissionType': _commissionType,
                            'commissionValue': double.parse(_commissionValueController.text),
                            'generationMode': _generationMode,
                            'customNumbersMap': _customNumbersMap,
                            'preSoldTickets': _preSoldTicketsList,
                          });

                          if (success && mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: AppTheme.secondaryEmerald,
                                content: Text('¡Sorteo y boletas creados exitosamente!'),
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                      child: const Text('CREAR Y GENERAR BOLETAS', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
