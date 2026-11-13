import 'package:rifaapp/ui/core/utils/text_search.dart';
import 'package:rifaapp/data/models/advisor.dart';
import 'package:rifaapp/ui/features/raffles/views/reactivate_advisors_dialog.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/features/raffles/views/winning_rule_fields.dart';
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
import 'package:rifaapp/ui/features/lotteries/views/lottery_field.dart';
import 'package:rifaapp/ui/features/tickets/views/transfer_widgets.dart';

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
  late TextEditingController _ticketPriceController;
  late TextEditingController _prizeImagesController;

  late bool _isActive;
  late List<String> _selectedAdvisorIds;

  late TextEditingController _mainDrawDateController;
  late TextEditingController _weeklyPrizesStartDateController;

  late String _commissionType;
  late TextEditingController _commissionValueController;
  late List<CommissionTier> _commissionTiers;

  late bool _hasWeeklyDraws;
  late String _winningPosition;
  late bool _allowCombined;
  late String _weeklyDrawDay;
  late String _lotteryName;
  late String _mainLotteryName;
  late String _weeklyMinAbonoType;
  late TextEditingController _weeklyMinAbonoValueController;
  late bool _isWeeklyPrizeAccumulative;
  late List<WeeklyPrize> _weeklyPrizes;
  late List<TransferAccount> _transferAccounts;

  List<Map<String, dynamic>>? _importedRecords;
  String? _importedFileName;
  bool _uploadingMedia = false;
  bool _advisorsInitialized = false;
  String _advisorSearch = '';

  List<Advisor> _filteredAdvisors(List<Advisor> all) => _advisorSearch.isEmpty
      ? all
      : all.where((a) => foldContains(a.name, _advisorSearch) || foldContains(a.code, _advisorSearch) || foldContains(a.username, _advisorSearch)).toList();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_advisorsInitialized) {
      _advisorsInitialized = true;
      if (_selectedAdvisorIds.isEmpty) {
        final advisors = context.read<AdvisorViewModel>().advisors;
        if (advisors.isNotEmpty) {
          _selectedAdvisorIds = advisors.map((a) => a.id).toList();
        }
      }
    }
  }

  Future<void> _uploadMediaFromDevice() async {
    try {
      final bytes = await pickFileBytes(allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'webm']);
      if (bytes == null || bytes.isEmpty) return;

      setState(() => _uploadingMedia = true);

      final base64Str = base64Encode(bytes);
      final filename = 'premio_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final uploadRes = await ApiService().uploadPrizeMedia(
        widget.raffle.id,
        base64Str,
        filename,
        'image/jpeg',
      );

      // El enlace DIRECTO de la imagen (no el de la página de Drive, que no es una imagen y se ve rota)
      final url = normalizeDriveImageUrl((uploadRes['url'] ?? uploadRes['file']?['url'] ?? uploadRes['webViewUrl'] ?? uploadRes['file']?['webViewUrl'] ?? '').toString());
      if (url.isNotEmpty) {
        final current = _prizeImagesController.text.trim();
        _prizeImagesController.text = current.isEmpty ? url : '$current\n$url';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.secondaryEmerald,
              content: Text('✓ Archivo subido exitosamente a Google Drive y agregado a la galería.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppTheme.dangerRose, content: Text('Error al subir: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingMedia = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.raffle.title);
    _descriptionController = TextEditingController(text: widget.raffle.description);
    _ticketPriceController = TextEditingController(text: widget.raffle.ticketPrice.toStringAsFixed(0));
    _prizeImagesController = TextEditingController(text: widget.raffle.prizeImages.join('\n'));
    _prizeImagesController.addListener(_refreshPrizeImages);
    _mainDrawDateController = TextEditingController(text: DateFormatterColombia.formatShort(widget.raffle.mainDrawDate));
    _weeklyPrizesStartDateController = TextEditingController(text: DateFormatterColombia.formatShort(widget.raffle.weeklyPrizesStartDate));
    _isActive = widget.raffle.status == 'ACTIVA';
    _selectedAdvisorIds = List.from(widget.raffle.assignedAdvisorIds);
    _commissionType = widget.raffle.commissionType;
    _commissionValueController = TextEditingController(text: widget.raffle.commissionValue.toStringAsFixed(0));
    _commissionTiers = widget.raffle.commissionTiers.isNotEmpty
        ? List.from(widget.raffle.commissionTiers)
        : [
            CommissionTier(min: 1, max: 20, rate: 10, type: 'PORCENTAJE'),
            CommissionTier(min: 21, max: 50, rate: 15, type: 'PORCENTAJE'),
            CommissionTier(min: 51, max: null, rate: 20, type: 'PORCENTAJE'),
          ];

    _hasWeeklyDraws = widget.raffle.hasWeeklyDraws;
    _winningPosition = widget.raffle.winningDigitsPosition;
    _allowCombined = widget.raffle.allowCombined;
    _weeklyDrawDay = widget.raffle.weeklyDrawDay;
    _lotteryName = widget.raffle.lotteryName;
    _mainLotteryName = widget.raffle.mainLotteryName;
    _weeklyMinAbonoType = widget.raffle.weeklyMinAbonoType;
    _weeklyMinAbonoValueController = TextEditingController(text: widget.raffle.weeklyMinAbonoValue.toStringAsFixed(0));
    _isWeeklyPrizeAccumulative = widget.raffle.isWeeklyPrizeAccumulative;
    // Del sorteo más antiguo al más reciente
    _weeklyPrizes = List.from(widget.raffle.weeklyPrizes)..sort((a, b) => compareDrawDates(a.drawDate, b.drawDate));
    _transferAccounts = List.from(widget.raffle.transferAccounts);
  }

  void _refreshPrizeImages() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _prizeImagesController.removeListener(_refreshPrizeImages);
    _titleController.dispose();
    _descriptionController.dispose();
    _ticketPriceController.dispose();
    _prizeImagesController.dispose();
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

  void _showAddPrizeDialog({WeeklyPrize? editPrize, int? editIndex}) {
    final nameCtrl = TextEditingController(text: editPrize?.name ?? 'Sorteo Anticipado #${_weeklyPrizes.length + 1}');
    final amountCtrl = TextEditingController(text: editPrize != null ? editPrize.amount.toStringAsFixed(0) : '1000000');
    final dateCtrl = TextEditingController(
      text: editPrize?.drawDate ??
          DateTime.now().add(Duration(days: 7 * (_weeklyPrizes.length + 1))).toIso8601String().substring(0, 10),
    );
    final lotteryCtrl = TextEditingController(
      text: (editPrize?.lotteryName ?? '').isNotEmpty
          ? editPrize!.lotteryName
          : (_lotteryName.isNotEmpty ? _lotteryName : (_mainLotteryName.isNotEmpty ? _mainLotteryName : 'Lotería del Meta')),
    );
    String minType = editPrize?.minAbonoType ?? 'VALOR_FIJO';
    final minValCtrl = TextEditingController(
      text: editPrize != null
          ? editPrize.minAbonoValue.toStringAsFixed(0)
          : (_weeklyMinAbonoValueController.text.isNotEmpty ? _weeklyMinAbonoValueController.text : '30000'),
    );
    bool accumulative = editPrize?.isAccumulative ?? _isWeeklyPrizeAccumulative;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.event_available, color: Colors.purple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      editPrize != null ? 'Editar Fecha y Abono Mínimo' : '📅 Agregar Fecha y Abono Mínimo',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple.shade200),
                      ),
                      child: const Text(
                        'Indique la fecha en la que se jugará el sorteo anticipado, qué se sortea y cuánto debe tener abonado el cliente para participar en esa fecha.',
                        style: TextStyle(fontSize: 11.5, color: Colors.purple),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: dateCtrl,
                      readOnly: true,
                      onTap: () => DateFormatterColombia.selectDate(context, dateCtrl),
                      decoration: InputDecoration(
                        labelText: 'Fecha del Sorteo (dd/mm/aaaa) *',
                        hintText: 'dd/mm/aaaa',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.event),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_month, color: Colors.purple),
                          onPressed: () => DateFormatterColombia.selectDate(context, dateCtrl),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Premio o Nombre del Sorteo *',
                        hintText: 'Ej: Sorteo Anticipado #1 o Moto Boxer CT100',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.card_giftcard),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Valor del Premio (\$ COP) *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: lotteryCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Lotería Oficial del Sorteo',
                        hintText: 'Ej: Lotería del Meta o Lotería de Medellín',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.casino),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Condición de Abono Mínimo a esta Fecha:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<String>(
                            value: 'VALOR_FIJO',
                            groupValue: minType,
                            title: const Text('Valor Fijo (\$ COP)', style: TextStyle(fontSize: 11)),
                            onChanged: (v) => setDlgState(() => minType = v!),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<String>(
                            value: 'PORCENTAJE',
                            groupValue: minType,
                            title: const Text('Porcentaje (%)', style: TextStyle(fontSize: 11)),
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
                        labelText: minType == 'PORCENTAJE'
                            ? 'Mínimo Abono (%) Requerido'
                            : 'Mínimo Abono (\$ COP) Requerido',
                        helperText: minType == 'PORCENTAJE'
                            ? 'Ej: 50% = Debe haber abonado el 50% o más de la boleta.'
                            : 'Ej: \$30.000 COP = Debe haber abonado \$30.000 o más a esta fecha.',
                        border: const OutlineInputBorder(),
                        prefixIcon: Icon(minType == 'PORCENTAJE' ? Icons.percent : Icons.attach_money),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      title: const Text('¿El Premio se Acumula?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      subtitle: Text(accumulative
                          ? 'Sí. Si el número ganador no cumplió el abono mínimo, el premio se acumula.'
                          : 'No se acumula.'),
                      value: accumulative,
                      activeColor: Colors.purple,
                      onChanged: (v) => setDlgState(() => accumulative = v),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty) return;
                    final prizeObj = WeeklyPrize(
                      id: editPrize?.id ?? 'wp-${DateTime.now().millisecondsSinceEpoch}',
                      name: nameCtrl.text.trim(),
                      amount: double.tryParse(amountCtrl.text) ?? 0.0,
                      drawDate: dateCtrl.text.trim(),
                      lotteryName: lotteryCtrl.text.trim(),
                      minAbonoType: minType,
                      minAbonoValue: double.tryParse(minValCtrl.text) ?? 30000.0,
                      isAccumulative: accumulative,
                      status: editPrize?.status ?? 'PENDIENTE',
                      winningTicketNumber: editPrize?.winningTicketNumber,
                      winnerName: editPrize?.winnerName,
                    );
                    setState(() {
                      if (editIndex != null && editIndex < _weeklyPrizes.length) {
                        _weeklyPrizes[editIndex] = prizeObj;
                      } else {
                        _weeklyPrizes.add(prizeObj);
                      }
                      _weeklyPrizes.sort((a, b) => compareDrawDates(a.drawDate, b.drawDate));
                    });
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(editPrize != null ? 'GUARDAR FECHA' : 'AGREGAR FECHA'),
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

  Future<void> _reshuffleNumbers(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Reorganizar números al azar?'),
        content: const Text(
            'Se mezclarán de nuevo, de forma aleatoria, los números de todas las boletas. Los números anteriores dejarán de ser válidos. Solo es posible mientras ninguna boleta esté vendida ni apartada.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reorganizar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final ticketVM = Provider.of<TicketViewModel>(context, listen: false);
    try {
      await ApiService().reshuffleRaffleNumbers(widget.raffle.id);
      await ticketVM.loadTickets(raffleId: widget.raffle.id);
      messenger.showSnackBar(const SnackBar(
          backgroundColor: AppTheme.secondaryEmerald, content: Text('Números reorganizados al azar.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(e.toString())));
    }
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
                  decoration: const InputDecoration(labelText: 'Descripción del Premio', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _ticketPriceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Valor de la boleta (COP) *',
                    helperText: 'El nuevo valor se aplica a todas las boletas. Solo conservan su valor las que ya tienen pagado un monto igual o mayor al nuevo precio.',
                    helperMaxLines: 3,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) <= 0 ? 'Ingrese un valor mayor a 0' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _prizeImagesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Fotos del Premio (Galería Web)',
                    hintText: 'Pega URLs de imágenes separadas por línea (ej: https://...jpg)',
                    helperText: 'Estas fotos aparecerán en el carrusel de la boleta web que ve el cliente.',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.photo_library_outlined),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: _uploadingMedia
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload_outlined, size: 18),
                    label: Text(_uploadingMedia ? 'Subiendo a Google Drive...' : 'Subir Foto / Video desde Dispositivo (Drive)'),
                    onPressed: _uploadingMedia ? null : _uploadMediaFromDevice,
                  ),
                ),
                Builder(
                  builder: (context) {
                    final prizeUrls = _prizeImagesController.text
                        .split('\n')
                        .map((u) => u.trim())
                        .where((u) => u.isNotEmpty)
                        .toList();
                    if (prizeUrls.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          '📷 Fotos cargadas (${prizeUrls.length}) - Toca ✖ para quitar:',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 90,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: prizeUrls.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (ctx, idx) {
                              final url = prizeUrls[idx];
                              final isVideo = url.toLowerCase().contains('.mp4') || url.toLowerCase().contains('.mov');
                              return Stack(
                                children: [
                                  Container(
                                    width: 90,
                                    height: 90,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3), width: 1.5),
                                      color: Colors.grey.shade100,
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: isVideo
                                        ? const Center(child: Icon(Icons.videocam, color: AppTheme.primaryBlue, size: 36))
                                        : Image.network(
                                            url,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Center(
                                              child: Icon(Icons.broken_image, color: Colors.grey, size: 28),
                                            ),
                                          ),
                                  ),
                                  Positioned(
                                    top: 3,
                                    right: 3,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          prizeUrls.removeAt(idx);
                                          _prizeImagesController.text = prizeUrls.join('\n');
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          color: Colors.black87,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close, color: Colors.white, size: 13),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),

                // Lottery of the main draw: shown in WhatsApp messages, terms and the printed ticket
                LotteryField(
                  value: _mainLotteryName,
                  label: 'Lotería del sorteo principal *',
                  helperText: _mainLotteryName.isEmpty
                      ? 'Sin elegir: los mensajes muestran "${widget.raffle.lotteryName}". Seleccione la lotería real.'
                      : 'Aparece en los mensajes de WhatsApp, los términos y la boleta impresa',
                  onChanged: (v) => setState(() => _mainLotteryName = v ?? ''),
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
                        title: const Text('Porcentaje Fijo (%)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
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
                        title: const Text('Valor Fijo (\$ COP)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
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
                    ResponsiveFlexChild(
                      expand: !isNarrowScreen(context),
                      child: RadioListTile<String>(
                        value: 'ESCALONADO',
                        groupValue: _commissionType,
                        title: const Text('Por Rangos / Metas', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        onChanged: (v) => setState(() => _commissionType = v!),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_commissionType != 'ESCALONADO')
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
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.stairs_outlined, color: AppTheme.primaryBlue, size: 20),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Escala de Comisiones por Cantidad de Boletas Vendidas:',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Agregar Rango', style: TextStyle(fontSize: 12)),
                              onPressed: () {
                                setState(() {
                                  int lastMax = _commissionTiers.isNotEmpty && _commissionTiers.last.max != null 
                                      ? _commissionTiers.last.max! + 1 
                                      : (_commissionTiers.length + 1) * 20;
                                  _commissionTiers.add(CommissionTier(min: lastMax, max: lastMax + 30, rate: 20, type: 'PORCENTAJE'));
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'El asesor ganará la comisión según la cantidad de boletas que logre vender (ej: 1 a 20 -> 10%, 21 a 50 -> 15%, más de 50 -> 20%).',
                          style: TextStyle(fontSize: 11, color: Colors.black87),
                        ),
                        const SizedBox(height: 10),
                        for (int i = 0; i < _commissionTiers.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 75,
                                  child: TextFormField(
                                    initialValue: _commissionTiers[i].min.toString(),
                                    decoration: const InputDecoration(labelText: 'Desde', isDense: true, border: OutlineInputBorder()),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    onChanged: (v) {
                                      int val = int.tryParse(v) ?? 1;
                                      final cur = _commissionTiers[i];
                                      _commissionTiers[i] = CommissionTier(min: val, max: cur.max, rate: cur.rate, type: cur.type);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 85,
                                  child: TextFormField(
                                    initialValue: _commissionTiers[i].max?.toString() ?? '',
                                    decoration: const InputDecoration(labelText: 'Hasta (+)', hintText: 'En adelante', isDense: true, border: OutlineInputBorder()),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    onChanged: (v) {
                                      int? val = int.tryParse(v.trim());
                                      final cur = _commissionTiers[i];
                                      _commissionTiers[i] = CommissionTier(min: cur.min, max: val, rate: cur.rate, type: cur.type);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 80,
                                  child: TextFormField(
                                    initialValue: _commissionTiers[i].rate.toStringAsFixed(0),
                                    decoration: InputDecoration(
                                      labelText: _commissionTiers[i].type == 'PORCENTAJE' ? 'Ganancia %' : 'Valor \$',
                                      isDense: true,
                                      border: const OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    onChanged: (v) {
                                      double val = double.tryParse(v) ?? 10.0;
                                      final cur = _commissionTiers[i];
                                      _commissionTiers[i] = CommissionTier(min: cur.min, max: cur.max, rate: val, type: cur.type);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 6),
                                DropdownButton<String>(
                                  value: _commissionTiers[i].type,
                                  underline: const SizedBox(),
                                  items: const [
                                    DropdownMenuItem(value: 'PORCENTAJE', child: Text('%', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DropdownMenuItem(value: 'VALOR_FIJO', child: Text('\$', style: TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                  onChanged: (nv) {
                                    if (nv == null) return;
                                    setState(() {
                                      final cur = _commissionTiers[i];
                                      _commissionTiers[i] = CommissionTier(min: cur.min, max: cur.max, rate: cur.rate, type: nv);
                                    });
                                  },
                                ),
                                if (_commissionTiers.length > 1)
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                    tooltip: 'Quitar rango',
                                    onPressed: () {
                                      setState(() => _commissionTiers.removeAt(i));
                                    },
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                // REORGANIZAR NÚMEROS AL AZAR (solo si todas las boletas siguen disponibles)
                Builder(builder: (context) {
                  final raffleTickets = Provider.of<TicketViewModel>(context)
                      .tickets
                      .where((t) => t.raffleId == widget.raffle.id)
                      .toList();
                  final allAvailable = raffleTickets.isNotEmpty && raffleTickets.every((t) => t.status == 'DISPONIBLE');
                  final canReshuffle = allAvailable && widget.raffle.opportunitiesPerTicket >= 2;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.shuffle, color: AppTheme.primaryBlue, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Reorganizar números al azar',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        canReshuffle
                            ? 'Ninguna boleta se ha vendido ni apartado: puedes volver a mezclar al azar los números de cada boleta si no te gusta la distribución actual.'
                            : widget.raffle.opportunitiesPerTicket < 2
                                ? 'Disponible solo cuando cada boleta tiene 2 o más oportunidades.'
                                : 'No disponible: ya hay boletas vendidas, apartadas o con abonos.',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.shuffle, size: 18),
                        label: const Text('Reorganizar al azar'),
                        onPressed: canReshuffle ? () => _reshuffleNumbers(context) : null,
                      ),
                    ],
                  );
                }),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                // ASIGNAR ASESORES
                Row(
                  children: [
                    const Icon(Icons.people, color: AppTheme.primaryBlue, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Asesores Autorizados para este Sorteo:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.select_all, size: 16),
                      label: const Text('Todos', style: TextStyle(fontSize: 12)),
                      onPressed: () => setState(() {
                        for (final a in _filteredAdvisors(advisorVM.advisors)) {
                          if (!_selectedAdvisorIds.contains(a.id)) _selectedAdvisorIds.add(a.id);
                        }
                      }),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.deselect, size: 16),
                      label: const Text('Ninguno', style: TextStyle(fontSize: 12)),
                      onPressed: () => setState(() {
                        final hidden = _filteredAdvisors(advisorVM.advisors).map((a) => a.id).toSet();
                        _selectedAdvisorIds.removeWhere(hidden.contains);
                        if (_advisorSearch.isEmpty) _selectedAdvisorIds.clear();
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Los asesores autorizados pueden ver y vender números disponibles. Si desmarcas a un asesor, no podrá ver disponibilidad de números libres (únicamente verá las boletas que ya haya vendido).',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                if (advisorVM.advisors.length > 1) ...[
                  TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 20),
                      hintText: 'Buscar asesor por nombre o cédula',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _advisorSearch = foldText(v)),
                  ),
                  const SizedBox(height: 8),
                ],

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
                          itemCount: _filteredAdvisors(advisorVM.advisors).length,
                          itemBuilder: (context, i) {
                            final adv = _filteredAdvisors(advisorVM.advisors)[i];
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
                WinningRuleFields(
                  digits: widget.raffle.digits,
                  position: _winningPosition,
                  allowCombined: _allowCombined,
                  onPositionChanged: (v) => setState(() => _winningPosition = v),
                  onCombinedChanged: (v) => setState(() => _allowCombined = v),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                TransferAccountsEditor(
                  accounts: _transferAccounts,
                  onChanged: (v) => setState(() => _transferAccounts = v),
                ),
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
                        child: LotteryField(
                          value: _lotteryName,
                          label: 'Lotería de los sorteos semanales',
                          required: false,
                          onChanged: (v) => setState(() => _lotteryName = v ?? ''),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // SECCIÓN CRONOGRAMA DE FECHAS Y ABONOS MÍNIMOS PARA PARTICIPAR
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50.withOpacity(0.35),
                      border: Border.all(color: Colors.purple.shade200, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_month, color: Colors.purple, size: 22),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '📅 Cronograma de Fechas y Abonos Mínimos para Participar',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.purple),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Configure las diferentes fechas de sorteos anticipados o semanales y cuánto debe tener abonado como mínimo el participante para entrar a jugar en cada fecha hasta llegar al sorteo del premio mayor.',
                          style: TextStyle(fontSize: 11.5, color: Colors.black87),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _showAddPrizeDialog(),
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            label: const Text(
                              '+ AGREGAR FECHA CON ABONO MÍNIMO Y PREMIO',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_weeklyPrizes.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.event_note, size: 36, color: Colors.grey.shade400),
                                const SizedBox(height: 6),
                                const Text(
                                  'Aún no has configurado fechas con abonos mínimos.',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Toca en "+ AGREGAR FECHA CON ABONO MÍNIMO Y PREMIO" para programar las fechas en que juegan los clientes (ej: 15 Nov -> \$30.000, 30 Nov -> \$60.000, etc.).',
                                  style: TextStyle(fontSize: 11, color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _weeklyPrizes.length,
                            separatorBuilder: (context, i) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final p = _weeklyPrizes[i];
                              final isPending = p.status == 'PENDIENTE';
                              final isWon = p.status == 'GANADO';
                              Color tagColor = isPending ? Colors.orange : (isWon ? Colors.green : Colors.purple);

                              final reqAbonoStr = p.minAbonoType == 'PORCENTAJE'
                                  ? '${p.minAbonoValue.toStringAsFixed(0)}% del valor de la boleta'
                                  : '\$${p.minAbonoValue.toStringAsFixed(0)} COP';

                              return Card(
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(color: Colors.purple.shade100),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.shade100,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '🗓️ ${p.drawDate}',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  color: Colors.purple.shade900),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              p.name,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                                color: tagColor.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(4)),
                                            child: Text(
                                              p.status,
                                              style: TextStyle(
                                                  fontSize: 10, fontWeight: FontWeight.bold, color: tagColor),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '💰 Abono Mínimo Requerido: $reqAbonoStr',
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.black87),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '🎁 Premio: \$${p.amount.toStringAsFixed(0)} COP • Lotería: ${p.lotteryName}${p.isAccumulative ? ' • Acumulable' : ''}',
                                                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                                                ),
                                                if (p.winnerName != null)
                                                  Text(
                                                    '🏆 Ganador: ${p.winnerName} (Boleta #${p.winningTicketNumber})',
                                                    style: const TextStyle(
                                                        fontSize: 11.5,
                                                        color: Colors.green,
                                                        fontWeight: FontWeight.bold),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isPending)
                                                IconButton(
                                                  icon: const Icon(Icons.emoji_events_outlined,
                                                      color: Colors.amber, size: 22),
                                                  tooltip: 'Evaluar / Marcar Ganador',
                                                  onPressed: () => _showEvaluateDrawWinnerDialog(p, i),
                                                ),
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined,
                                                    color: Colors.blue, size: 20),
                                                tooltip: 'Editar Fecha y Requisitos',
                                                onPressed: () => _showAddPrizeDialog(editPrize: p, editIndex: i),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline,
                                                    color: Colors.red, size: 20),
                                                tooltip: 'Eliminar Fecha',
                                                onPressed: () {
                                                  setState(() {
                                                    _weeklyPrizes.removeAt(i);
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
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

                          // Si estaba inactiva y se reactiva: se pregunta a quiénes se les reactivan las ventas
                          Map<String, dynamic>? reactivation;
                          if (_isActive && widget.raffle.status != 'ACTIVA') {
                            reactivation = await askReactivateAdvisors(context);
                            if (reactivation == null) return;
                          }
                          bool ok = await raffleVM.updateRaffle(widget.raffle.id, {
                            if (reactivation != null) ...reactivation,
                            'title': _titleController.text.trim(),
                            'description': _descriptionController.text.trim(),
                            'ticketPrice': double.tryParse(_ticketPriceController.text.trim()) ?? widget.raffle.ticketPrice,
                            'prizeImages': _prizeImagesController.text
                                .split(RegExp(r'[\n,]+'))
                                .map((e) => e.trim())
                                .where((e) => e.isNotEmpty)
                                .toList(),
                            'mainDrawDate': DateFormatterColombia.toIsoString(_mainDrawDateController.text),
                            'weeklyPrizesStartDate': DateFormatterColombia.toIsoString(_weeklyPrizesStartDateController.text),
                            'status': _isActive ? 'ACTIVA' : 'INACTIVA',
                            'assignedAdvisorIds': _selectedAdvisorIds,
                            'commissionType': _commissionType,
                            'commissionValue': double.tryParse(_commissionValueController.text) ?? 10.0,
                            'commissionTiers': _commissionTiers.map((t) => t.toJson()).toList(),
                            'hasWeeklyDraws': _hasWeeklyDraws,
                            'winningDigitsPosition': _winningPosition,
                            'allowCombined': _allowCombined,
                            'weeklyDrawDay': _weeklyDrawDay,
                            'lotteryName': _lotteryName,
                            'mainLotteryName': _mainLotteryName,
                            'weeklyMinAbonoType': _weeklyMinAbonoType,
                            'weeklyMinAbonoValue': double.tryParse(_weeklyMinAbonoValueController.text) ?? 50.0,
                            'isWeeklyPrizeAccumulative': _isWeeklyPrizeAccumulative,
                            'weeklyPrizes': _weeklyPrizes.map((p) => p.toJson()).toList(),
                            'transferAccounts': _transferAccounts.map((a) => a.toJson()).toList(),
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
                          if (!ok && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppTheme.dangerRose,
                                content: Text(raffleVM.errorMessage ?? 'No se pudo guardar el sorteo.'),
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
