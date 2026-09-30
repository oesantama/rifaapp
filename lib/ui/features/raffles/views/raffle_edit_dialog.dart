import 'package:flutter/material.dart';
import 'package:rifaapp/ui/core/widgets/responsive_flex_child.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/models/raffle.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/ui/core/utils/excel_csv_helper.dart';
import 'package:rifaapp/ui/core/utils/file_picker_helper.dart';
import 'package:rifaapp/ui/core/utils/date_formatter.dart';
import 'package:rifaapp/ui/core/theme.dart';

class RaffleEditDialog extends StatefulWidget {
  final Raffle raffle;

  const RaffleEditDialog({super.key, required this.raffle});

  @override
  State<RaffleEditDialog> createState() => _RaffleEditDialogState();
}

class _RaffleEditDialogState extends State<RaffleEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;

  late bool _isActive;
  late List<String> _selectedAdvisorIds;

  late TextEditingController _mainDrawDateController;
  late TextEditingController _weeklyPrizesStartDateController;

  late String _commissionType;
  late TextEditingController _commissionValueController;

  late bool _hasWeeklyDraws;
  late String _weeklyDrawDay;
  late String _lotteryName;
  late String _weeklyMinAbonoType;
  late TextEditingController _weeklyMinAbonoValueController;
  late bool _isWeeklyPrizeAccumulative;
  late List<WeeklyPrize> _weeklyPrizes;

  List<Map<String, dynamic>>? _importedRecords;
  String? _importedFileName;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.raffle.title);
    _descriptionController = TextEditingController(text: widget.raffle.description);
    _mainDrawDateController = TextEditingController(text: DateFormatterColombia.formatShort(widget.raffle.mainDrawDate));
    _weeklyPrizesStartDateController = TextEditingController(text: DateFormatterColombia.formatShort(widget.raffle.weeklyPrizesStartDate));
    _isActive = widget.raffle.status == 'ACTIVA';
    _selectedAdvisorIds = List.from(widget.raffle.assignedAdvisorIds);
    _commissionType = widget.raffle.commissionType;
    _commissionValueController = TextEditingController(text: widget.raffle.commissionValue.toStringAsFixed(0));

    _hasWeeklyDraws = widget.raffle.hasWeeklyDraws;
    _weeklyDrawDay = widget.raffle.weeklyDrawDay;
    _lotteryName = widget.raffle.lotteryName;
    _weeklyMinAbonoType = widget.raffle.weeklyMinAbonoType;
    _weeklyMinAbonoValueController = TextEditingController(text: widget.raffle.weeklyMinAbonoValue.toStringAsFixed(0));
    _isWeeklyPrizeAccumulative = widget.raffle.isWeeklyPrizeAccumulative;
    _weeklyPrizes = List.from(widget.raffle.weeklyPrizes);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _mainDrawDateController.dispose();
    _weeklyPrizesStartDateController.dispose();
    _commissionValueController.dispose();
    _weeklyMinAbonoValueController.dispose();
    super.dispose();
  }

  void _pickPreSoldTicketsFile() async {
    try {
      List<int>? bytes = await pickFileBytes(allowedExtensions: ['xlsx', 'xls', 'csv', 'txt']);
      if (bytes != null && bytes.isNotEmpty) {
        List<Map<String, dynamic>> parsedList = ExcelCsvHelper.parseSoldTicketsFromBytes(bytes);

        if (parsedList.isNotEmpty) {
          setState(() {
            _importedRecords = parsedList;
            _importedFileName = 'boletas_importadas.xlsx';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.secondaryEmerald,
                content: Text('✓ Se cargaron ${parsedList.length} registros de boletas desde el archivo Excel.'),
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

  void _showAddPrizeDialog() {
    final nameCtrl = TextEditingController(text: 'Sorteo Semanal #${_weeklyPrizes.length + 1}');
    final amountCtrl = TextEditingController(text: '1000000');
    final dateCtrl =
        TextEditingController(text: DateTime.now().add(Duration(days: 7 * (_weeklyPrizes.length + 1))).toIso8601String().substring(0, 10));
    final lotteryCtrl = TextEditingController(text: _lotteryName);
    String minType = _weeklyMinAbonoType;
    final minValCtrl = TextEditingController(text: _weeklyMinAbonoValueController.text);
    bool accumulative = _isWeeklyPrizeAccumulative;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.stars, color: Colors.purple),
                  SizedBox(width: 8),
                  Text('Agregar Nuevo Sorteo / Premio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre del Sorteo / Premio *', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: amountCtrl,
                      decoration: const InputDecoration(labelText: 'Valor del Premio (\$ COP) *', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: dateCtrl,
                      readOnly: true,
                      onTap: () => DateFormatterColombia.selectDate(context, dateCtrl),
                      decoration: InputDecoration(
                        labelText: 'Fecha del Sorteo (dd/mm/aaaa) *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.event),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_month, color: Colors.purple),
                          onPressed: () => DateFormatterColombia.selectDate(context, dateCtrl),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: lotteryCtrl,
                      decoration: const InputDecoration(labelText: 'Lotería o Mecánica del Sorteo', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Flex(
                      direction: isNarrowScreen(context) ? Axis.vertical : Axis.horizontal,
                      crossAxisAlignment: isNarrowScreen(context) ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
                      children: [
                        ResponsiveFlexChild(
                          expand: !isNarrowScreen(context),
                          child: RadioListTile<String>(
                            value: 'PORCENTAJE',
                            groupValue: minType,
                            title: const Text('Porcentaje %', style: TextStyle(fontSize: 11)),
                            onChanged: (v) => setDlgState(() => minType = v!),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        ResponsiveFlexChild(
                          expand: !isNarrowScreen(context),
                          child: RadioListTile<String>(
                            value: 'VALOR_FIJO',
                            groupValue: minType,
                            title: const Text('Valor Fijo \$', style: TextStyle(fontSize: 11)),
                            onChanged: (v) => setDlgState(() => minType = v!),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                    TextField(
                      controller: minValCtrl,
                      decoration: InputDecoration(
                        labelText: minType == 'PORCENTAJE' ? 'Mínimo Abono (%) Requerido' : 'Mínimo Abono (\$ COP) Requerido',
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('¿El Premio se Acumula?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: Text(accumulative ? 'Sí. Se acumula si no cumple abonado.' : 'No se acumula.'),
                      value: accumulative,
                      activeColor: Colors.purple,
                      onChanged: (v) => setDlgState(() => accumulative = v),
                      dense: true,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty) return;
                    final newPrize = WeeklyPrize(
                      id: 'wp-${DateTime.now().millisecondsSinceEpoch}',
                      name: nameCtrl.text.trim(),
                      amount: double.tryParse(amountCtrl.text) ?? 0.0,
                      drawDate: dateCtrl.text.trim(),
                      lotteryName: lotteryCtrl.text.trim(),
                      minAbonoType: minType,
                      minAbonoValue: double.tryParse(minValCtrl.text) ?? 50.0,
                      isAccumulative: accumulative,
                      status: 'PENDIENTE',
                    );
                    setState(() {
                      _weeklyPrizes.add(newPrize);
                    });
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                  child: const Text('AGREGAR SORTEO'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEvaluateDrawWinnerDialog(WeeklyPrize prize, int index) {
    final numCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final ticketVM = Provider.of<TicketViewModel>(context, listen: false);
            String winningNum = numCtrl.text.trim();
            final matchedTicket = winningNum.isNotEmpty
                ? ticketVM.tickets.firstWhere(
                    (t) => t.numbers.contains(winningNum),
                    orElse: () => Ticket(
                      id: '',
                      raffleId: '',
                      ticketNumber: 0,
                      numbers: [],
                      price: 0,
                      status: '',
                      advisorId: '',
                      advisorName: '',
                      buyerName: '',
                      buyerPhone: '',
                      totalPaid: 0,
                      balancePending: 0,
                      confirmedByAdmin: false,
                      abonos: const [],
                    ),
                  )
                : null;

            double reqAbono =
                prize.minAbonoType == 'PORCENTAJE' ? (widget.raffle.ticketPrice * (prize.minAbonoValue / 100)) : prize.minAbonoValue;

            bool ticketExists = matchedTicket != null && matchedTicket.id.isNotEmpty;
            bool meetsCondition = ticketExists && matchedTicket.totalPaid >= reqAbono;

            return AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.emoji_events, color: Colors.amber, size: 24),
                  SizedBox(width: 8),
                  Text('Evaluar Ganador del Sorteo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sorteo: ${prize.name} • Prem: \$${prize.amount.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                        'Condición: Abono mín. de ${prize.minAbonoType == 'PORCENTAJE' ? '${prize.minAbonoValue}%' : '\$${prize.minAbonoValue.toStringAsFixed(0)}'} (\$${reqAbono.toStringAsFixed(0)} COP)',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: numCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Número Ganador (Ej: 0123) *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.numbers),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setDlgState(() {}),
                    ),
                    const SizedBox(height: 12),
                    if (winningNum.isNotEmpty) ...[
                      if (!ticketExists) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade300)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('⚠️ El número $winningNum NO pertenece a boleta vendida.',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange)),
                              const SizedBox(height: 4),
                              Text(
                                prize.isAccumulative
                                    ? 'El premio de \$${prize.amount.toStringAsFixed(0)} COP SE ACUMULA para el próximo sorteo semanal.'
                                    : 'El premio queda desierto.',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        )
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: meetsCondition ? Colors.green.shade50 : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: meetsCondition ? Colors.green.shade300 : Colors.red.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Boleta Ganadora #${matchedTicket.ticketNumber} — ${matchedTicket.buyerName}',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: meetsCondition ? Colors.green.shade900 : Colors.red.shade900),
                              ),
                              Text(
                                  'Abonado Actual: \$${matchedTicket.totalPaid.toStringAsFixed(0)} COP (Requerido: \$${reqAbono.toStringAsFixed(0)})',
                                  style: const TextStyle(fontSize: 11)),
                              const SizedBox(height: 6),
                              if (meetsCondition)
                                const Text('🎉 ¡CUMPLE LA CONDICIÓN! El comprador califica para reclamar el premio.',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green))
                              else ...[
                                Text(
                                  '❌ NO CUMPLE LA CONDICIÓN DE ABONO.\n${prize.isAccumulative ? "✓ Como 'El premio se acumula' está activo, este premio SE ACUMULA." : "El premio queda desierto."}',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade900),
                                ),
                              ],
                            ],
                          ),
                        )
                      ]
                    ]
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                if (winningNum.isNotEmpty && (!ticketExists || !meetsCondition))
                  ElevatedButton(
                    onPressed: () {
                      final updatedPrize = WeeklyPrize(
                        id: prize.id,
                        name: prize.name,
                        amount: prize.amount,
                        drawDate: prize.drawDate,
                        lotteryName: prize.lotteryName,
                        minAbonoType: prize.minAbonoType,
                        minAbonoValue: prize.minAbonoValue,
                        isAccumulative: prize.isAccumulative,
                        status: 'ACUMULADO',
                        winningTicketNumber: winningNum,
                        winnerName: ticketExists ? '${matchedTicket.buyerName} (No acumuló abono)' : 'Desierto',
                      );
                      setState(() {
                        _weeklyPrizes[index] = updatedPrize;
                      });
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                    child: const Text('MARCAR ACUMULADO'),
                  ),
                if (winningNum.isNotEmpty && ticketExists)
                  ElevatedButton(
                    onPressed: () {
                      final updatedPrize = WeeklyPrize(
                        id: prize.id,
                        name: prize.name,
                        amount: prize.amount,
                        drawDate: prize.drawDate,
                        lotteryName: prize.lotteryName,
                        minAbonoType: prize.minAbonoType,
                        minAbonoValue: prize.minAbonoValue,
                        isAccumulative: prize.isAccumulative,
                        status: 'GANADO',
                        winningTicketNumber: winningNum,
                        winnerName: matchedTicket.buyerName,
                      );
                      setState(() {
                        _weeklyPrizes[index] = updatedPrize;
                      });
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondaryEmerald),
                    child: const Text('DECLARAR GANADOR'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final advisorVM = Provider.of<AdvisorViewModel>(context);

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
                    const Icon(Icons.settings, color: AppTheme.primaryBlue, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Gestionar Sorteo: ${widget.raffle.title}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Modifica el estado del sorteo, asigna asesores autorizados o actualiza boletas vendidas.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Divider(height: 24),

                // ESTADO ACTIVO / INACTIVO
                SwitchListTile(
                  title: const Text('Sorteo Activo', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(_isActive
                      ? 'El sorteo está visible y operativo para venta.'
                      : '🔴 Sorteo INACTIVO. Los asesores NO podrán ver este sorteo ni registrar ventas.'),
                  value: _isActive,
                  activeColor: AppTheme.secondaryEmerald,
                  onChanged: (val) => setState(() => _isActive = val),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Título del Sorteo *', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingrese un título' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Descripción', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),

                Flex(
                  direction: isNarrowScreen(context) ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: isNarrowScreen(context) ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
                  children: [
                    ResponsiveFlexChild(
                      expand: !isNarrowScreen(context),
                      child: TextFormField(
                        controller: _mainDrawDateController,
                        readOnly: true,
                        onTap: () => DateFormatterColombia.selectDate(context, _mainDrawDateController),
                        decoration: InputDecoration(
                          labelText: '📅 Fecha Sorteo Principal (Colombia) *',
                          hintText: 'dd/mm/aaaa',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.event),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_month, color: AppTheme.primaryBlue),
                            onPressed: () => DateFormatterColombia.selectDate(context, _mainDrawDateController),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingrese fecha principal' : null,
                      ),
                    ),
                    const SizedBox(width: 12, height: 12),
                    ResponsiveFlexChild(
                      expand: !isNarrowScreen(context),
                      child: TextFormField(
                        controller: _weeklyPrizesStartDateController,
                        readOnly: true,
                        onTap: () => DateFormatterColombia.selectDate(context, _weeklyPrizesStartDateController),
                        decoration: InputDecoration(
                          labelText: '🗓️ Fecha Inicio Premios Semanales *',
                          hintText: 'dd/mm/aaaa',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.date_range),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.calendar_month, color: AppTheme.primaryBlue),
                            onPressed: () => DateFormatterColombia.selectDate(context, _weeklyPrizesStartDateController),
                          ),
                        ),
                      ),
                    ),
                  ],
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
                Flex(
                  direction: isNarrowScreen(context) ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: isNarrowScreen(context) ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
                  children: [
                    ResponsiveFlexChild(
                      expand: !isNarrowScreen(context),
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
                    ResponsiveFlexChild(
                      expand: !isNarrowScreen(context),
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
                const SizedBox(height: 8),

                // ASIGNAR ASESORES
                Row(
                  children: [
                    const Icon(Icons.people, color: AppTheme.primaryBlue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: const Text('Asesores Autorizados para este Sorteo:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Si no seleccionas ninguno, todos los asesores tendrán acceso. Si seleccionas asesores específicos, solo ellos podrán vender boletas de este sorteo.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 8),

                advisorVM.advisors.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No hay asesores registrados aún.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                      )
                    : Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: advisorVM.advisors.length,
                          itemBuilder: (context, i) {
                            final adv = advisorVM.advisors[i];
                            bool isSelected = _selectedAdvisorIds.contains(adv.id);
                            return CheckboxListTile(
                              title: Text('${adv.name} (${adv.code})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              subtitle: Text('Teléfono: ${adv.phone}'),
                              value: isSelected,
                              dense: true,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedAdvisorIds.add(adv.id);
                                  } else {
                                    _selectedAdvisorIds.remove(adv.id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                // IMPORTAR BOLETAS VENDIDAS PARA SORTEO EXISTENTE
                Row(
                  children: [
                    const Icon(Icons.upload_file, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                        child: const Text('Actualizar / Importar Boletas Vendidas desde Excel (.xlsx):',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.start,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => ExcelCsvHelper.downloadSoldTicketsTemplate(),
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Plantilla Excel (.xlsx)', style: TextStyle(fontSize: 12)),
                    ),
                    ElevatedButton.icon(
                      onPressed: _pickPreSoldTicketsFile,
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: Text(_importedRecords != null ? 'Cambiar Archivo Excel' : 'Cargar Boletas Excel',
                          style: const TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
                    ),
                  ],
                ),

                if (_importedRecords != null && _importedRecords!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50.withOpacity(0.5),
                      border: Border.all(color: Colors.amber.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '📋 Registros a cargar desde Excel (${_importedRecords!.length} boletas):',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade900),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _importedRecords = null;
                                  _importedFileName = null;
                                });
                              },
                              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                              label: const Text('Descartar', style: TextStyle(color: Colors.red, fontSize: 12)),
                            )
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _importedRecords!.length,
                            separatorBuilder: (context, i) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final rec = _importedRecords![i];
                              final statusColor = AppTheme.getStatusColor(rec['status'] ?? 'DISPONIBLE');
                              final buyerName = (rec['buyerName'] != null && rec['buyerName'].toString().trim().isNotEmpty)
                                  ? rec['buyerName'].toString()
                                  : "Sin Nombre";
                              final buyerPhone = (rec['buyerPhone'] != null && rec['buyerPhone'].toString().trim().isNotEmpty)
                                  ? rec['buyerPhone'].toString()
                                  : "N/A";
                              final sellerName = (rec['sellerName'] != null && rec['sellerName'].toString().trim().isNotEmpty)
                                  ? rec['sellerName'].toString()
                                  : "N/A";
                              final note = (rec['note'] != null && rec['note'].toString().trim().isNotEmpty) ? " • ${rec['note']}" : "";

                              return ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                leading: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: statusColor.withOpacity(0.15),
                                  child: Text(
                                    '#${rec['ticketNumber']}',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                                  ),
                                ),
                                title: Text(
                                  'Boleta #${rec['ticketNumber']} — $buyerName',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                subtitle: Text(
                                  'Tel: $buyerPhone • Asesor: $sellerName$note',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        rec['status'] ?? 'PENDIENTE',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '\$${(rec['amountPaid'] ?? 0).toStringAsFixed(0)}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: const [
                            Icon(Icons.info_outline, size: 14, color: Colors.amber),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Confirme que los datos son correctos. Se cargarán únicamente al hacer clic en "GUARDAR CAMBIOS".',
                                style: TextStyle(fontSize: 11, color: Colors.black87, fontStyle: FontStyle.italic),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ],

                // SECCIÓN CONFIGURACIÓN Y GESTIÓN DE SORTEOS SEMANALES / EXTRA
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.stars, color: Colors.purple, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                        child: const Text(
                      '🎁 Sorteos Semanales y Premios Adicionales:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    )),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Configura la condición de abono mínimo, acumulación de premios y gestiona nuevos sorteos adicionales.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 8),

                SwitchListTile(
                  title:
                      const Text('Habilitar Sorteos Semanales / Adicionales', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(_hasWeeklyDraws
                      ? 'Las boletas participan en sorteos recurrentes según abonado acumulado.'
                      : 'Deshabilitado para este sorteo.'),
                  value: _hasWeeklyDraws,
                  activeColor: Colors.purple,
                  onChanged: (val) => setState(() => _hasWeeklyDraws = val),
                ),

                if (_hasWeeklyDraws) ...[
                  const SizedBox(height: 8),
                  Flex(
                    direction: isNarrowScreen(context) ? Axis.vertical : Axis.horizontal,
                    crossAxisAlignment: isNarrowScreen(context) ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
                    children: [
                      ResponsiveFlexChild(
                        expand: !isNarrowScreen(context),
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _weeklyDrawDay,
                          decoration: const InputDecoration(labelText: 'Día Habitual del Sorteo', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'Lunes', child: Text('Lunes')),
                            DropdownMenuItem(value: 'Martes', child: Text('Martes')),
                            DropdownMenuItem(value: 'Miércoles', child: Text('Miércoles')),
                            DropdownMenuItem(value: 'Jueves', child: Text('Jueves')),
                            DropdownMenuItem(value: 'Viernes', child: Text('Viernes')),
                            DropdownMenuItem(value: 'Sábado', child: Text('Sábado')),
                            DropdownMenuItem(value: 'Domingo', child: Text('Domingo')),
                          ],
                          onChanged: (v) => setState(() => _weeklyDrawDay = v!),
                        ),
                      ),
                      const SizedBox(width: 12, height: 12),
                      ResponsiveFlexChild(
                        expand: !isNarrowScreen(context),
                        child: TextFormField(
                          initialValue: _lotteryName,
                          decoration: const InputDecoration(labelText: 'Lotería Principal', border: OutlineInputBorder()),
                          onChanged: (v) => _lotteryName = v,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // REQUISITO MÍNIMO DE ABONO
                  const Text('📊 Condición Mínima de Abono para Participar:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Flex(
                    direction: isNarrowScreen(context) ? Axis.vertical : Axis.horizontal,
                    crossAxisAlignment: isNarrowScreen(context) ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
                    children: [
                      ResponsiveFlexChild(
                        expand: !isNarrowScreen(context),
                        child: RadioListTile<String>(
                          value: 'PORCENTAJE',
                          groupValue: _weeklyMinAbonoType,
                          title: const Text('Porcentaje (%)', style: TextStyle(fontSize: 12)),
                          onChanged: (v) => setState(() => _weeklyMinAbonoType = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      ResponsiveFlexChild(
                        expand: !isNarrowScreen(context),
                        child: RadioListTile<String>(
                          value: 'VALOR_FIJO',
                          groupValue: _weeklyMinAbonoType,
                          title: const Text('Valor Fijo (\$ COP)', style: TextStyle(fontSize: 12)),
                          onChanged: (v) => setState(() => _weeklyMinAbonoType = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: _weeklyMinAbonoValueController,
                    decoration: InputDecoration(
                      labelText: _weeklyMinAbonoType == 'PORCENTAJE' ? 'Mínimo Pago / Abono (%) *' : 'Mínimo Pago / Abono (\$ COP) *',
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(_weeklyMinAbonoType == 'PORCENTAJE' ? Icons.percent : Icons.attach_money),
                      helperText: _weeklyMinAbonoType == 'PORCENTAJE'
                          ? 'Ejemplo: 50% de \$50.000 = Debe haber abonado \$25.000 o más para participar.'
                          : 'Ejemplo: \$50.000 COP = Debe haber abonado \$50.000 o más para participar.',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 10),

                  // ACUMULACIÓN DEL PREMIO
                  SwitchListTile(
                    title: const Text('¿El Premio Semanal se Acumula?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(_isWeeklyPrizeAccumulative
                        ? '✓ Sí. Si la boleta ganadora no ha abonado el mínimo o no se ha vendido, el valor se acumula para el próximo sorteo.'
                        : '❌ No. Si el ganador no califica, el premio no se acumula.'),
                    value: _isWeeklyPrizeAccumulative,
                    activeColor: Colors.amber.shade800,
                    onChanged: (val) => setState(() => _isWeeklyPrizeAccumulative = val),
                  ),
                  const SizedBox(height: 12),

                  // LISTADO Y GESTIÓN DE PREMIOS ADICIONALES
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      Text('Premios / Sorteos Registrados (${_weeklyPrizes.length}):',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ElevatedButton.icon(
                        onPressed: _showAddPrizeDialog,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Aplicar Más Sorteos / Premios', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_weeklyPrizes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No hay premios o sorteos adicionales configurados.',
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
                    )
                  else
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50.withOpacity(0.3),
                        border: Border.all(color: Colors.purple.shade200),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _weeklyPrizes.length,
                        separatorBuilder: (context, i) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final p = _weeklyPrizes[i];
                          final isPending = p.status == 'PENDIENTE';
                          final isWon = p.status == 'GANADO';

                          Color tagColor = isPending ? Colors.orange : (isWon ? Colors.green : Colors.purple);

                          return ListTile(
                            dense: true,
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text('${p.name} — \$${p.amount.toStringAsFixed(0)} COP',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: tagColor.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                  child: Text(
                                    p.status,
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: tagColor),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              'Fecha: ${p.drawDate} • Lotería: ${p.lotteryName} • Mín. Abono: ${p.minAbonoType == 'PORCENTAJE' ? '${p.minAbonoValue}%' : '\$${p.minAbonoValue.toStringAsFixed(0)}'}${p.isAccumulative ? ' • Acumulable' : ''}${p.winnerName != null ? '\n🏆 Ganador: ${p.winnerName} (Boleta #${p.winningTicketNumber})' : ''}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isPending)
                                  IconButton(
                                    icon: const Icon(Icons.emoji_events_outlined, color: Colors.amber, size: 20),
                                    tooltip: 'Evaluar / Marcar Ganador o Acumulado',
                                    onPressed: () => _showEvaluateDrawWinnerDialog(p, i),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                  tooltip: 'Eliminar Sorteo',
                                  onPressed: () {
                                    setState(() {
                                      _weeklyPrizes.removeAt(i);
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],

                const SizedBox(height: 24),

                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                    ElevatedButton(
                      onPressed: () async {
                        if (_formKey.currentState!.validate()) {
                          final raffleVM = Provider.of<RaffleViewModel>(context, listen: false);
                          final ticketVM = Provider.of<TicketViewModel>(context, listen: false);

                          bool ok = await raffleVM.updateRaffle(widget.raffle.id, {
                            'title': _titleController.text.trim(),
                            'description': _descriptionController.text.trim(),
                            'mainDrawDate': DateFormatterColombia.toIsoString(_mainDrawDateController.text),
                            'weeklyPrizesStartDate': DateFormatterColombia.toIsoString(_weeklyPrizesStartDateController.text),
                            'status': _isActive ? 'ACTIVA' : 'INACTIVA',
                            'assignedAdvisorIds': _selectedAdvisorIds,
                            'commissionType': _commissionType,
                            'commissionValue': double.parse(_commissionValueController.text),
                            'hasWeeklyDraws': _hasWeeklyDraws,
                            'weeklyDrawDay': _weeklyDrawDay,
                            'lotteryName': _lotteryName,
                            'weeklyMinAbonoType': _weeklyMinAbonoType,
                            'weeklyMinAbonoValue': double.tryParse(_weeklyMinAbonoValueController.text) ?? 50.0,
                            'isWeeklyPrizeAccumulative': _isWeeklyPrizeAccumulative,
                            'weeklyPrizes': _weeklyPrizes.map((p) => p.toJson()).toList(),
                          });

                          if (_importedRecords != null && _importedRecords!.isNotEmpty) {
                            await ticketVM.importTickets(widget.raffle.id, _importedRecords!);
                          }

                          if (ok && mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: AppTheme.secondaryEmerald,
                                content: Text('¡Sorteo actualizado correctamente!'),
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                      child: const Text('GUARDAR CAMBIOS', style: TextStyle(fontWeight: FontWeight.bold)),
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
