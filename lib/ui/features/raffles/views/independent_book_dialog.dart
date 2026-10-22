import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/date_formatter.dart';
import 'package:rifaapp/ui/core/utils/excel_csv_helper.dart';
import 'package:rifaapp/ui/core/utils/file_picker_helper.dart';
import 'package:rifaapp/ui/features/lotteries/views/lottery_field.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';

class IndependentBookDialog extends StatefulWidget {
  const IndependentBookDialog({super.key});

  @override
  State<IndependentBookDialog> createState() => _IndependentBookDialogState();
}

class _IndependentBookDialogState extends State<IndependentBookDialog> {
  final _formKey = GlobalKey<FormState>();
  final _ownerController = TextEditingController(text: 'Don Wilo');
  final _titleController = TextEditingController(text: 'Talonario Don Wilo');
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController(text: '20000');
  final _commissionValueController = TextEditingController(text: '20');
  late TextEditingController _drawDateController;

  String _lotteryName = '';
  int _digits = 4;
  int _opportunitiesPerTicket = 1; // 1, 2, 4, 5, etc.
  String _commissionType = 'PORCENTAJE'; // PORCENTAJE or VALOR_FIJO

  // Métodos para agregar: 'RANGE' (Rango), 'TEXT' (Pegar), 'FILE' (Excel/CSV)
  String _addMode = 'RANGE';

  // Modo Rango
  final _rangeStartController = TextEditingController(text: '1');
  final _rangeEndController = TextEditingController(text: '100');
  final _rangeStepController = TextEditingController(text: '5000');
  String _rangeDistribution = 'BLOCK'; // 'BLOCK' (con salto) or 'CONSECUTIVE'

  // Modo Pegar
  final _pasteNumbersController = TextEditingController();

  // Acumulador de boletas: cada boleta es una lista de números [num1, num2...]
  final List<List<String>> _accumulatedTickets = [];

  bool _isSaving = false;

  int get _totalNumbersCount => _accumulatedTickets.fold(0, (acc, t) => acc + t.length);

  @override
  void initState() {
    super.initState();
    _drawDateController = TextEditingController(
      text: DateFormatterColombia.formatShort(DateTime.now().add(const Duration(days: 30)).toIso8601String()),
    );
  }

  @override
  void dispose() {
    _ownerController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _commissionValueController.dispose();
    _drawDateController.dispose();
    _rangeStartController.dispose();
    _rangeEndController.dispose();
    _rangeStepController.dispose();
    _pasteNumbersController.dispose();
    super.dispose();
  }

  // --- LÓGICA DE ADICIÓN ACUMULATIVA ---

  void _addRange() {
    final start = int.tryParse(_rangeStartController.text.trim()) ?? 0;
    final end = int.tryParse(_rangeEndController.text.trim()) ?? 0;

    if (start <= 0 || end < start) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('⚠️ Ingrese un rango válido (el número inicial debe ser mayor a 0 y menor o igual al final).'),
        ),
      );
      return;
    }

    final newTickets = <List<String>>[];

    if (_opportunitiesPerTicket == 1) {
      for (int i = start; i <= end; i++) {
        newTickets.add([i.toString().padLeft(_digits, '0')]);
      }
    } else {
      if (_rangeDistribution == 'CONSECUTIVE') {
        final allNums = <String>[];
        for (int i = start; i <= end; i++) {
          allNums.add(i.toString().padLeft(_digits, '0'));
        }
        for (int i = 0; i < allNums.length; i += _opportunitiesPerTicket) {
          final chunk = allNums.sublist(
            i,
            (i + _opportunitiesPerTicket > allNums.length) ? allNums.length : i + _opportunitiesPerTicket,
          );
          newTickets.add(chunk);
        }
      } else {
        // Modo Salto / Bloque (ej. Salto 5000: boleta 1 -> 0001 y 5001)
        final step = int.tryParse(_rangeStepController.text.trim()) ?? 5000;
        for (int i = start; i <= end; i++) {
          final tkt = <String>[];
          for (int k = 0; k < _opportunitiesPerTicket; k++) {
            final val = i + (k * step);
            tkt.add(val.toString().padLeft(_digits, '0'));
          }
          newTickets.add(tkt);
        }
      }
    }

    setState(() {
      _accumulatedTickets.addAll(newTickets);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.secondaryEmerald,
        content: Text('✓ Se añadieron ${newTickets.length} boletas del rango $start al $end (Total: ${_accumulatedTickets.length} boletas)'),
      ),
    );
  }

  void _addPastedNumbers() {
    final raw = _pasteNumbersController.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.red, content: Text('⚠️ Ingrese números o boletas en el campo de texto.')),
      );
      return;
    }

    final newTickets = <List<String>>[];
    final lines = raw.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // Verificamos si el usuario ingresó con guiones o barras por línea (ej: 0125-5125)
    bool hasLineSeparators = lines.any((l) => l.contains('-') || l.contains('/') || l.contains(';'));

    if (hasLineSeparators) {
      for (final line in lines) {
        final parts = line.split(RegExp(r'[-/;,]')).map((p) => p.replaceAll(RegExp(r'\D'), '')).where((p) => p.isNotEmpty).toList();
        if (parts.isNotEmpty) {
          newTickets.add(parts.map((p) => p.padLeft(_digits, '0')).toList());
        }
      }
    } else {
      // Lista continua separada por espacios, comas o saltos de línea
      final parts = raw.split(RegExp(r'[,;\s\n\r]+')).map((s) => s.replaceAll(RegExp(r'\D'), '')).where((s) => s.isNotEmpty).toList();
      final formatted = parts.map((p) => p.padLeft(_digits, '0')).toList();

      if (_opportunitiesPerTicket > 1) {
        for (int i = 0; i < formatted.length; i += _opportunitiesPerTicket) {
          final chunk = formatted.sublist(
            i,
            (i + _opportunitiesPerTicket > formatted.length) ? formatted.length : i + _opportunitiesPerTicket,
          );
          newTickets.add(chunk);
        }
      } else {
        for (final num in formatted) {
          newTickets.add([num]);
        }
      }
    }

    if (newTickets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.red, content: Text('⚠️ No se pudieron extraer números válidos.')),
      );
      return;
    }

    setState(() {
      _accumulatedTickets.addAll(newTickets);
      _pasteNumbersController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.secondaryEmerald,
        content: Text('✓ Se añadieron ${newTickets.length} boletas sueltas (Total acumulado: ${_accumulatedTickets.length} boletas)'),
      ),
    );
  }

  void _pickExcelFile() async {
    try {
      final bytes = await pickFileBytes(allowedExtensions: ['xlsx', 'xls', 'csv', 'txt']);
      if (bytes != null && bytes.isNotEmpty) {
        final map = ExcelCsvHelper.parseNumbersFromBytes(bytes, _digits);
        final list = <List<String>>[];
        for (final entry in map.values) {
          if (entry.isNotEmpty) {
            list.add(entry);
          }
        }
        if (list.isNotEmpty) {
          setState(() {
            _accumulatedTickets.addAll(list);
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.secondaryEmerald,
                content: Text('✓ Se añadieron ${list.length} boletas desde el archivo Excel (Total: ${_accumulatedTickets.length} boletas)'),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(backgroundColor: Colors.red, content: Text('⚠️ No se encontraron números válidos en el archivo.')),
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

  void _removeTicket(int index) {
    setState(() {
      _accumulatedTickets.removeAt(index);
    });
  }

  void _clearAllTickets() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar Talonario'),
        content: const Text('¿Desea vaciar todas las boletas acumuladas para comenzar de nuevo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _accumulatedTickets.clear();
              });
            },
            child: const Text('Sí, Vaciar Todo', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _saveBook() async {
    if (!_formKey.currentState!.validate()) return;

    if (_accumulatedTickets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('⚠️ Debe añadir al menos un rango o boleta a la lista acumulada antes de guardar.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final raffleVM = Provider.of<RaffleViewModel>(context, listen: false);

    final success = await raffleVM.createRaffle({
      'title': _titleController.text.trim(),
      'ownerName': _ownerController.text.trim(),
      'description': _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : 'Talonario de ${_ownerController.text.trim()} (${_accumulatedTickets.length} boletas)',
      'mainDrawDate': DateFormatterColombia.toIsoString(_drawDateController.text),
      'mainLotteryName': _lotteryName,
      'lotteryName': _lotteryName,
      'digits': _digits,
      'opportunitiesPerTicket': _opportunitiesPerTicket,
      'totalTickets': _accumulatedTickets.length,
      'ticketPrice': double.tryParse(_priceController.text) ?? 20000,
      'commissionType': _commissionType,
      'commissionValue': double.tryParse(_commissionValueController.text) ?? 20,
      'isIndependentBook': true,
      'customTicketsList': _accumulatedTickets,
    });

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.secondaryEmerald,
            content: Text('✓ ¡Talonario de "${_ownerController.text}" con ${_accumulatedTickets.length} boletas guardado exitosamente!'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 780),
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.menu_book_rounded, color: Colors.teal, size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cargar Talonario de Rifa Externa',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Registra las boletas y números entregados por Don Wilo, William u otro dueño',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Cerrar',
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Dueño y Título
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _ownerController,
                        decoration: const InputDecoration(
                          labelText: 'Dueño / Organizador *',
                          hintText: 'Ej: Don Wilo, William',
                          prefixIcon: Icon(Icons.person_outline, color: Colors.teal),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Título del Sorteo *',
                          hintText: 'Ej: Talonario Don Wilo',
                          prefixIcon: Icon(Icons.confirmation_number_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Fecha de juego y Lotería
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _drawDateController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: '¿Cuándo Juega? *',
                          prefixIcon: Icon(Icons.calendar_today_rounded, color: Colors.blue),
                          border: OutlineInputBorder(),
                        ),
                        onTap: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: now.add(const Duration(days: 30)),
                            firstDate: now.subtract(const Duration(days: 365)),
                            lastDate: now.add(const Duration(days: 365 * 3)),
                          );
                          if (picked != null) {
                            setState(() {
                              _drawDateController.text = DateFormatterColombia.formatShort(picked.toIso8601String());
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LotteryField(
                        value: _lotteryName,
                        label: 'Lotería de referencia',
                        onChanged: (v) => setState(() => _lotteryName = v ?? ''),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Precio y Comisión
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Precio Boleta (\$ COP) *',
                          prefixIcon: Icon(Icons.attach_money_rounded, color: Colors.green),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _commissionValueController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _commissionType == 'PORCENTAJE' ? 'Mi Comisión (%) *' : 'Mi Comisión (\$ COP) *',
                          prefixIcon: Icon(_commissionType == 'PORCENTAJE' ? Icons.percent : Icons.monetization_on_outlined, color: Colors.amber.shade800),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.swap_horiz_rounded),
                            tooltip: 'Cambiar a ${_commissionType == 'PORCENTAJE' ? 'Valor Fijo (\$)' : 'Porcentaje (%)'}',
                            onPressed: () {
                              setState(() {
                                _commissionType = _commissionType == 'PORCENTAJE' ? 'VALOR_FIJO' : 'PORCENTAJE';
                                _commissionValueController.text = _commissionType == 'PORCENTAJE' ? '20' : '5000';
                              });
                            },
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Cifras y Oportunidades por boleta
                Row(
                  children: [
                    // Cifras
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cifras de los números:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Row(
                            children: [2, 3, 4].map((d) {
                              final isSel = _digits == d;
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Center(child: Text('$d Cifras', style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal))),
                                    selected: isSel,
                                    selectedColor: Colors.teal.withValues(alpha: 0.25),
                                    onSelected: (_) => setState(() => _digits = d),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Oportunidades por Boleta
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Números por boleta:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Row(
                            children: [1, 2, 4].map((opp) {
                              final isSel = _opportunitiesPerTicket == opp;
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: ChoiceChip(
                                    label: Center(
                                      child: Text(
                                        opp == 1 ? '1 Núm' : '$opp Núms',
                                        style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal),
                                      ),
                                    ),
                                    selected: isSel,
                                    selectedColor: Colors.amber.withValues(alpha: 0.25),
                                    onSelected: (_) => setState(() => _opportunitiesPerTicket = opp),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // SECCIÓN ADICIÓN ACUMULATIVA DE BOLETAS
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.add_circle_outline_rounded, color: Colors.teal, size: 20),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Adicionar Boletas (Rangos o Sueltos):',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.teal,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_accumulatedTickets.length} Boletas Cargadas',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Botones de Modo
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('⇥ Por Rango')),
                              selected: _addMode == 'RANGE',
                              selectedColor: Colors.teal,
                              labelStyle: TextStyle(color: _addMode == 'RANGE' ? Colors.white : null, fontWeight: FontWeight.bold),
                              onSelected: (_) => setState(() => _addMode = 'RANGE'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('✍ Sueltos / Pegar')),
                              selected: _addMode == 'TEXT',
                              selectedColor: Colors.teal,
                              labelStyle: TextStyle(color: _addMode == 'TEXT' ? Colors.white : null, fontWeight: FontWeight.bold),
                              onSelected: (_) => setState(() => _addMode = 'TEXT'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('📥 Subir Excel')),
                              selected: _addMode == 'FILE',
                              selectedColor: Colors.teal,
                              labelStyle: TextStyle(color: _addMode == 'FILE' ? Colors.white : null, fontWeight: FontWeight.bold),
                              onSelected: (_) => setState(() => _addMode = 'FILE'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Contenido según Modo
                      if (_addMode == 'RANGE') ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _rangeStartController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: const InputDecoration(
                                  labelText: 'Desde # *',
                                  hintText: 'Ej: 1',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _rangeEndController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: const InputDecoration(
                                  labelText: 'Hasta # *',
                                  hintText: 'Ej: 50',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            if (_opportunitiesPerTicket > 1) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: _rangeStepController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                  decoration: const InputDecoration(
                                    labelText: 'Salto / Bloque',
                                    hintText: 'Ej: 5000',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (_opportunitiesPerTicket > 1) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('Distribución de oportunidades:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              const SizedBox(width: 10),
                              InkWell(
                                onTap: () => setState(() => _rangeDistribution = 'BLOCK'),
                                child: Row(
                                  children: [
                                    Radio<String>(
                                      value: 'BLOCK',
                                      groupValue: _rangeDistribution,
                                      onChanged: (v) => setState(() => _rangeDistribution = v!),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    const Text('Salto de bloque (1 y 5001)', style: TextStyle(fontSize: 11)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              InkWell(
                                onTap: () => setState(() => _rangeDistribution = 'CONSECUTIVE'),
                                child: Row(
                                  children: [
                                    Radio<String>(
                                      value: 'CONSECUTIVE',
                                      groupValue: _rangeDistribution,
                                      onChanged: (v) => setState(() => _rangeDistribution = v!),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    const Text('Consecutivo (1 y 2)', style: TextStyle(fontSize: 11)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Añadir este Rango a la Lista', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: _addRange,
                          ),
                        ),
                      ] else if (_addMode == 'TEXT') ...[
                        TextFormField(
                          controller: _pasteNumbersController,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: _opportunitiesPerTicket == 1
                                ? 'Escribe o pega los números (separados por coma o salto de línea)'
                                : 'Escribe o pega boletas (ej: 0125-5125 por renglón o lista continua)',
                            hintText: _opportunitiesPerTicket == 1
                                ? '0125, 0842, 1923, 4810, 5500...'
                                : '0125-5125\n0842-5842\n1923-6923...',
                            border: const OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _opportunitiesPerTicket > 1
                                  ? 'Si pegas lista continua, se agrupan de $_opportunitiesPerTicket en $_opportunitiesPerTicket.'
                                  : 'Puedes pegar desde WhatsApp o bloc de notas.',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Añadir estos Números', style: TextStyle(fontWeight: FontWeight.bold)),
                              onPressed: _addPastedNumbers,
                            ),
                          ],
                        ),
                      ] else ...[
                        Center(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.teal,
                              side: const BorderSide(color: Colors.teal),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            icon: const Icon(Icons.upload_file_rounded),
                            label: const Text('Seleccionar Archivo Excel (.xlsx, .csv)'),
                            onPressed: _pickExcelFile,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // BANDEJA DE BOLETAS ACUMULADAS
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 18, color: Colors.teal),
                        const SizedBox(width: 6),
                        Text(
                          'Boletas en este Talonario: ${_accumulatedTickets.length} (${_totalNumbersCount} números)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    if (_accumulatedTickets.isNotEmpty)
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                        label: const Text('Limpiar todo', style: TextStyle(fontSize: 12)),
                        onPressed: _clearAllTickets,
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_accumulatedTickets.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                    ),
                    child: const Center(
                      child: Text(
                        'Aún no has añadido boletas. Agrega uno o varios rangos o números sueltos arriba.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
                    ),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: List.generate(_accumulatedTickets.length, (idx) {
                          final tkt = _accumulatedTickets[idx];
                          final label = tkt.join(' - ');
                          return Chip(
                            backgroundColor: Colors.white,
                            side: BorderSide(color: Colors.teal.withValues(alpha: 0.3)),
                            label: Text(
                              '#${idx + 1}: $label',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 14, color: Colors.red),
                            onDeleted: () => _removeTicket(idx),
                            visualDensity: VisualDensity.compact,
                          );
                        }),
                      ),
                    ),
                  ),

                const SizedBox(height: 22),

                // BOTONES FINALES
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondaryEmerald,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded, size: 20),
                      label: Text(
                        _isSaving
                            ? 'Cargando Talonario...'
                            : 'CARGAR Y GUARDAR TALONARIO (${_accumulatedTickets.length} BOLETAS)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: _isSaving ? null : _saveBook,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
