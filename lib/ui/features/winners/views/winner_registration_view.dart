import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/winner.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/pdf_report_generator.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/features/winners/view_models/winner_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';

class WinnerRegistrationView extends StatefulWidget {
  const WinnerRegistrationView({super.key});

  @override
  State<WinnerRegistrationView> createState() => _WinnerRegistrationViewState();
}

class _WinnerRegistrationViewState extends State<WinnerRegistrationView> {
  final _numberController = TextEditingController();
  final _drawNameController = TextEditingController(text: 'Sorteo Semanal');
  final _prizeAmountController = TextEditingController(text: '1000000');
  final _photoUrlController = TextEditingController();

  WinnerRecord? _lastResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<WinnerViewModel>(context, listen: false).loadWinners();
      Provider.of<TicketViewModel>(context, listen: false).loadTickets();
    });
  }

  @override
  void dispose() {
    _numberController.dispose();
    _drawNameController.dispose();
    _prizeAmountController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  void _showDeleteDrawDialog(WinnerRecord winner) {
    final reasonController = TextEditingController();
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final winnerVM = Provider.of<WinnerViewModel>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.delete_forever, color: AppTheme.dangerRose, size: 28),
              SizedBox(width: 10),
              Text('Eliminar / Anular Sorteo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerRose.withValues(alpha: 0.1),
                    border: Border.all(color: AppTheme.dangerRose.withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📄 GENERACIÓN AUTOMÁTICA DE INFORME DE AUDITORÍA PDF',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.dangerRose),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Antes de eliminar el sorteo "${winner.drawName}" (Número #${winner.winningNumber}), el sistema descargará un informe en PDF de todo lo ocurrido para conservar la trazabilidad contable.',
                        style: const TextStyle(fontSize: 11, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Motivo de Eliminación / Anulación del Sorteo *',
                    hintText: 'Ej: Error al digitar el número ganador o fallo de lotería',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.orange,
                      content: Text('Debe especificar el motivo de eliminación para la auditoría.'),
                    ),
                  );
                  return;
                }

                Navigator.pop(ctx);

                // 1. Generate & download audit PDF report
                await PdfReportGenerator.generateAndDownloadDrawAuditPdf(
                  winner: winner,
                  reason: reason,
                  adminUser: authVM.currentUserName,
                );

                // 2. Delete winner record from system
                bool ok = await winnerVM.deleteWinner(winner.id, reason);

                if (ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppTheme.secondaryEmerald,
                      content: Text(' Sorteo eliminado del sistema e informe de auditoría PDF descargado.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('DESCARGAR INFORME PDF Y ELIMINAR'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.dangerRose,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        );
      },
    );
  }

  void _verifyAndConfirmDraw() {
    final winningNum = _numberController.text.trim();
    final raffleVM = Provider.of<RaffleViewModel>(context, listen: false);
    final ticketVM = Provider.of<TicketViewModel>(context, listen: false);
    final winnerVM = Provider.of<WinnerViewModel>(context, listen: false);
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    final currentRaffle = raffleVM.selectedRaffle;
    final requiredDigits = currentRaffle?.digits ?? 4;

    if (winningNum.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ingrese el número ganador')));
      return;
    }

    if (winningNum.length != requiredDigits) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade800,
          content: Text('⚠️ El número ganador debe tener exactamente $requiredDigits dígitos (ingresó ${winningNum.length} dígitos).'),
        ),
      );
      return;
    }

    double basePrizeAmount = double.tryParse(_prizeAmountController.text) ?? 1000000.0;
    double prevAccumulatedPot = winnerVM.totalAccumulatedAmount;
    String drawName = _drawNameController.text.trim();

    // Find ticket with winning number
    Ticket? matchedTicket;
    try {
      matchedTicket = ticketVM.tickets.firstWhere((t) => t.numbers.contains(winningNum));
    } catch (_) {
      matchedTicket = null;
    }

    double reqAbono = 0.0;
    if (currentRaffle != null) {
      reqAbono = currentRaffle.weeklyMinAbonoType == 'PORCENTAJE'
          ? (currentRaffle.ticketPrice * (currentRaffle.weeklyMinAbonoValue / 100))
          : currentRaffle.weeklyMinAbonoValue;
    }

    final tkt = matchedTicket;
    bool ticketExists = tkt != null && tkt.id.isNotEmpty && tkt.status != 'DISPONIBLE';
    bool meetsAbonoCondition = ticketExists && tkt.totalPaid >= reqAbono;

    double totalPrizeToDeliver = meetsAbonoCondition ? (basePrizeAmount + prevAccumulatedPot) : basePrizeAmount;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                meetsAbonoCondition ? Icons.emoji_events : Icons.verified_user,
                color: meetsAbonoCondition ? AppTheme.secondaryEmerald : Colors.amber.shade900,
                size: 26,
              ),
              const SizedBox(width: 10),
              const Text('Verificación Previa del Sorteo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Sorteo: $drawName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text('Premio Base Sorteo: ${currency.format(basePrizeAmount)} COP', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                            if (prevAccumulatedPot > 0)
                              Text('🔥 Pozo Acumulado Anterior: ${currency.format(prevAccumulatedPot)} COP', style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade800, fontWeight: FontWeight.bold)),
                            Text('💰 TOTAL EN JUEGO: ${currency.format(basePrizeAmount + prevAccumulatedPot)} COP', style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: AppTheme.primaryBlue, borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          '#$winningNum',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                if (ticketExists && meetsAbonoCondition) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryEmerald.withOpacity(0.12),
                      border: Border.all(color: AppTheme.secondaryEmerald),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.check_circle, color: AppTheme.secondaryEmerald, size: 20),
                            SizedBox(width: 8),
                            Text('¡BOLETA GANADORA CALIFICADA!', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.secondaryEmerald, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('• Boleta N°: #${tkt.ticketNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('• Comprador: ${tkt.buyerName} (${tkt.buyerPhone})'),
                        Text('• Asesor de Venta: ${tkt.advisorName}'),
                        Text('• Total Abonado: ${currency.format(tkt.totalPaid)} (Mínimo Requerido: ${currency.format(reqAbono)})'),
                        
                        const SizedBox(height: 10),
                        const Text('📅 Fechas de Pago y/o Abono Registradas:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        const SizedBox(height: 4),
                        if (tkt.abonos.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              '  • Fecha de Venta / Registro: ${tkt.assignedDate != null && tkt.assignedDate!.length >= 10 ? tkt.assignedDate!.substring(0, 10) : (tkt.assignedDate ?? "N/A")} — Monto: ${currency.format(tkt.totalPaid)} (Asesor: ${tkt.advisorName})',
                              style: const TextStyle(fontSize: 11, color: Colors.black87),
                            ),
                          )
                        else
                          ...tkt.abonos.map((a) => Padding(
                                padding: const EdgeInsets.only(left: 6, top: 2),
                                child: Text(
                                  '  • ${a.date.length >= 10 ? a.date.substring(0, 10) : a.date}: ${currency.format(a.amount)} (${a.note.isNotEmpty ? a.note : "Abono / Pago"}) — Asesor: ${a.sellerName}',
                                  style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w500),
                                ),
                              )),

                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.secondaryEmerald)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Desglose del Premio a Entregar:',
                                style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '• Premio Base Sorteo: ${currency.format(basePrizeAmount)} COP',
                                style: const TextStyle(fontSize: 11, color: Colors.black87),
                              ),
                              if (prevAccumulatedPot > 0)
                                Text(
                                  '• Pozo Acumulado Anterior: ${currency.format(prevAccumulatedPot)} COP',
                                  style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade800, fontWeight: FontWeight.bold),
                                ),
                              const Divider(height: 10),
                              Row(
                                children: [
                                  const Icon(Icons.card_giftcard, color: AppTheme.secondaryEmerald, size: 20),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'TOTAL GANADO A ENTREGAR: ${currency.format(totalPrizeToDeliver)} COP',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.secondaryEmerald),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                ] else if (ticketExists && !meetsAbonoCondition) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      border: Border.all(color: Colors.amber.shade800),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 22),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text('⚠️ BOLETA VENDIDA PERO ABONO INSUFICIENTE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('• Boleta N°: #${tkt.ticketNumber} — ${tkt.buyerName}'),
                        Text('• Abonado Actual: ${currency.format(tkt.totalPaid)} (Requerido: ${currency.format(reqAbono)})'),
                        
                        const SizedBox(height: 8),
                        const Text('📅 Fechas de Abono Registradas:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        if (tkt.abonos.isEmpty)
                          Text('  • Fecha de Venta: ${tkt.assignedDate != null && tkt.assignedDate!.length >= 10 ? tkt.assignedDate!.substring(0, 10) : (tkt.assignedDate ?? "N/A")}', style: const TextStyle(fontSize: 11))
                        else
                          ...tkt.abonos.map((a) => Padding(
                                padding: const EdgeInsets.only(left: 6, top: 2),
                                child: Text(
                                  '  • ${a.date.length >= 10 ? a.date.substring(0, 10) : a.date}: ${currency.format(a.amount)} (${a.note.isNotEmpty ? a.note : "Abono"}) — Asesor: ${a.sellerName}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              )),

                        const SizedBox(height: 8),
                        Text(
                          currentRaffle?.isWeeklyPrizeAccumulative == true
                              ? '✓ La regla de acumulación está activa. El premio de ${currency.format(basePrizeAmount)} COP SE ACUMULA para el próximo sorteo.'
                              : ' El premio queda desierto.',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerRose.withOpacity(0.1),
                      border: Border.all(color: AppTheme.dangerRose),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.history_toggle_off, color: AppTheme.dangerRose, size: 20),
                            SizedBox(width: 8),
                            Text('NÚMERO NO VENDIDO / DISPONIBLE', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.dangerRose, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('El número $winningNum no pertenece a ninguna boleta reservada o pagada.'),
                        const SizedBox(height: 6),
                        Text(
                          'El premio de ${currency.format(basePrizeAmount)} COP SE ACUMULA para el siguiente sorteo semanal.',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.dangerRose),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_photoUrlController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.camera_alt, size: 16, color: AppTheme.primaryBlue),
                            SizedBox(width: 6),
                            Text('Evidencia / URL Foto de Entrega Adjunta:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.primaryBlue)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          _photoUrlController.text.trim(),
                          style: const TextStyle(fontSize: 11, color: Colors.blue, decoration: TextDecoration.underline),
                        ),
                        if (_photoUrlController.text.trim().startsWith('http')) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              _photoUrlController.text.trim(),
                              height: 120,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) => Padding(
                                padding: const EdgeInsets.all(6),
                                child: Text('📷 Enlace de Evidencia: ${_photoUrlController.text.trim()}', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                              ),
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar / Corregir'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);

                WinnerRecord? rec = await winnerVM.registerWinner({
                  'raffleId': currentRaffle?.id,
                  'winningNumber': winningNum,
                  'drawName': drawName,
                  'prizeAmount': basePrizeAmount,
                  'photoUrl': _photoUrlController.text.trim(),
                  'drawDate': DateTime.now().toIso8601String(),
                });

                if (rec != null && mounted) {
                  setState(() {
                    _lastResult = rec;
                  });
                  _numberController.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppTheme.secondaryEmerald,
                      content: Text('¡Resultado confirmado! Premio total a entregar: ${currency.format(rec.totalPrizePaid)} COP.'),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: meetsAbonoCondition ? AppTheme.secondaryEmerald : AppTheme.primaryBlue,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              child: Text(
                meetsAbonoCondition ? 'CONFIRMAR Y REGISTRAR GANADOR' : 'CONFIRMAR Y MARCAR ACUMULADO',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final authVM = Provider.of<AuthViewModel>(context);

    return Consumer2<WinnerViewModel, RaffleViewModel>(
      builder: (context, winnerVM, raffleVM, _) {
        final currentRaffle = raffleVM.selectedRaffle;
        final isAsesor = authVM.isAsesor;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // VISTA REGISTRO SOLO PARA ADMINISTRADOR / LECTURA PARA ASESORES
              if (isAsesor) ...[
                Card(
                  color: AppTheme.primaryBlue.withOpacity(0.06),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        const Icon(Icons.stars, color: AppTheme.primaryBlue, size: 36),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Consulta de Premios y Ganadores',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '👁️ Modo Lectura (Asesor). Consulta los ganadores oficiales de cada sorteo semanal o premio acumulado registrado por la administración.',
                                style: TextStyle(fontSize: 12, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.casino, color: AppTheme.primaryBlue, size: 28),
                            SizedBox(width: 10),
                            Text(
                              'Registrar Sorteo / Ganador (Administrador)',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Ingresa el número jugado en la lotería o sorteo. El sistema verificará automáticamente el abono mínimo y sumará el pozo acumulado anterior si aplica.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _drawNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre / Tipo de Sorteo',
                                  hintText: 'Ej: Sorteo Semanal 1',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _prizeAmountController,
                                decoration: const InputDecoration(
                                  labelText: 'Premio Base en Dinero (\$ COP)',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _numberController,
                                maxLength: currentRaffle?.digits ?? 4,
                                decoration: InputDecoration(
                                  labelText: 'Número Ganador (${currentRaffle?.digits ?? 4} dígitos) *',
                                  hintText: 'Ej: 2501',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.numbers),
                                  counterText: '',
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(currentRaffle?.digits ?? 4),
                                ],
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _photoUrlController,
                                decoration: const InputDecoration(
                                  labelText: 'URL / Foto Entregas (Opcional)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.photo_camera),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _verifyAndConfirmDraw,
                            icon: const Icon(Icons.fact_check),
                            label: const Text('VERIFICAR NÚMERO GANADOR'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // RESULTADO RECIENTE DESTACADO
              if (_lastResult != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _lastResult!.isWinner
                        ? AppTheme.secondaryEmerald.withOpacity(0.15)
                        : AppTheme.dangerRose.withOpacity(0.15),
                    border: Border.all(
                      color: _lastResult!.isWinner ? AppTheme.secondaryEmerald : AppTheme.dangerRose,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _lastResult!.isWinner ? Icons.emoji_events : Icons.history_edu,
                        size: 48,
                        color: _lastResult!.isWinner ? AppTheme.secondaryEmerald : AppTheme.dangerRose,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _lastResult!.isWinner
                            ? '¡¡TENEMOS GANADOR DE LA RIFA Y DEL POZO ACUMULADO!!'
                            : '¡¡NO HUBO GANADOR - PREMIO ACUMULADO!!',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _lastResult!.isWinner ? AppTheme.secondaryEmerald : AppTheme.dangerRose,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Número Ganador: ${_lastResult!.winningNumber}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),

                      // MONTO / PREMIO ENTREGADO HIGHLIGHT
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _lastResult!.isWinner ? AppTheme.secondaryEmerald : AppTheme.dangerRose,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _lastResult!.isWinner
                                  ? '🏆 TOTAL PREMIO ENTREGADO: ${currency.format(_lastResult!.totalPrizePaid)} COP'
                                  : '💰 Valor Acumulado: ${currency.format(_lastResult!.basePrizeAmount)} COP',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            if (_lastResult!.isWinner && _lastResult!.previousAccumulatedAmount > 0)
                              Text(
                                '(Base Sorteo: ${currency.format(_lastResult!.basePrizeAmount)} + Pozo Acumulado: ${currency.format(_lastResult!.previousAccumulatedAmount)})',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),
                      if (_lastResult!.isWinner && _lastResult!.winnerDetails != null) ...[
                        Text('Boleta N°: #${_lastResult!.winnerDetails!.ticketNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Ganador: ${_lastResult!.winnerDetails!.buyerName} (${_lastResult!.winnerDetails!.buyerPhone})'),
                        Text('Vendido por Asesor: ${_lastResult!.winnerDetails!.advisorName}'),
                        if (_lastResult!.winnerDetails!.abonosSummary.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          const Text('📅 Fechas de Pago y/o Abono Registradas:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          ..._lastResult!.winnerDetails!.abonosSummary.map((a) => Text(
                                '• ${a['date'].toString().length >= 10 ? a['date'].toString().substring(0, 10) : a['date']}: ${currency.format(a['amount'])} (${a['note'] != null && a['note'].toString().isNotEmpty ? a['note'] : "Abono / Pago"}) — Asesor: ${a['sellerName'] ?? ""}',
                                style: const TextStyle(fontSize: 11),
                              )),
                        ]
                      ] else ...[
                        const Text('El número jugado no pertenece a boleta vendida o no acumuló el pago mínimo.'),
                        Text('El premio de ${currency.format(_lastResult!.basePrizeAmount)} pasa a formar parte del Pozo Acumulado.'),
                      ]
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              const Text('Historial de Sorteos Realizados:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              winnerVM.winners.isEmpty
                  ? const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Aún no se han registrado sorteos.')),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: winnerVM.winners.length,
                      itemBuilder: (context, i) {
                        final w = winnerVM.winners[i];
                        final det = w.winnerDetails;
                        List<Widget> abonoDetailWidgets = [];
                        if (w.isWinner && det != null) {
                          if (det.abonosSummary.isNotEmpty) {
                            abonoDetailWidgets = det.abonosSummary.map((a) {
                              String dateStr = a['date']?.toString() ?? '';
                              if (dateStr.length >= 10) dateStr = dateStr.substring(0, 10);
                              return Text(
                                '• $dateStr: ${currency.format(a['amount'])} (${a['note'] != null && a['note'].toString().isNotEmpty ? a['note'] : "Abono / Pago"}) — Asesor: ${a['sellerName'] ?? det.advisorName}',
                                style: const TextStyle(fontSize: 11, color: Colors.black87),
                              );
                            }).toList();
                          } else if (det.assignedDate != null) {
                            String dateStr = det.assignedDate!;
                            if (dateStr.length >= 10) dateStr = dateStr.substring(0, 10);
                            abonoDetailWidgets = [
                              Text(
                                '• $dateStr: ${currency.format(det.totalPaid)} (Pago de venta) — Asesor: ${det.advisorName}',
                                style: const TextStyle(fontSize: 11, color: Colors.black87),
                              )
                            ];
                          }
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: w.isWinner
                                          ? AppTheme.secondaryEmerald.withOpacity(0.2)
                                          : AppTheme.dangerRose.withOpacity(0.2),
                                      child: Icon(
                                        w.isWinner ? Icons.emoji_events : Icons.history,
                                        color: w.isWinner ? AppTheme.secondaryEmerald : AppTheme.dangerRose,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${w.drawName} • Número Ganador: ${w.winningNumber}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          const SizedBox(height: 2),
                                          if (w.isWinner) ...[
                                            Text(
                                              'Ganador: ${w.winnerDetails?.buyerName} (Boleta #${w.winnerDetails?.ticketNumber})',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                            ),
                                            Text(
                                              '🏆 Premio Entregado: ${currency.format(w.totalPrizePaid)}${w.previousAccumulatedAmount > 0 ? " (Base Sorteo: ${currency.format(w.basePrizeAmount)} + Acumulado Anterior: ${currency.format(w.previousAccumulatedAmount)})" : ""}',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.secondaryEmerald),
                                            ),
                                          ] else ...[
                                            Text(
                                              'Sorteo sin ganador • ACUMULADO (${currency.format(w.basePrizeAmount)})',
                                              style: const TextStyle(fontSize: 12, color: AppTheme.dangerRose, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: w.isWinner ? AppTheme.secondaryEmerald : AppTheme.dangerRose,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        w.isWinner ? 'GANADOR' : 'ACUMULADO',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    if (!isAsesor) ...[
                                      const SizedBox(width: 6),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: AppTheme.dangerRose),
                                        tooltip: 'Eliminar Sorteo y Descargar Informe PDF',
                                        onPressed: () => _showDeleteDrawDialog(w),
                                      ),
                                    ]
                                  ],
                                ),
                                if (w.isWinner && abonoDetailWidgets.isNotEmpty) ...[
                                  const Divider(height: 14),
                                  const Text('📅 Fechas y Registro de Pagos/Abonos:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                  const SizedBox(height: 2),
                                  ...abonoDetailWidgets,
                                ],
                                if (w.photoUrl != null && w.photoUrl!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  InkWell(
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          title: const Text('Evidencia / Foto de Entrega de Premio'),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SelectableText('Link: ${w.photoUrl!}'),
                                              const SizedBox(height: 10),
                                              if (w.photoUrl!.startsWith('http'))
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: Image.network(
                                                    w.photoUrl!,
                                                    height: 220,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (c, e, s) => const Text('📷 No se pudo cargar la vista previa directa de la imagen.'),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context),
                                              child: const Text('Cerrar'),
                                            )
                                          ],
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryBlue.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.photo_library, size: 15, color: AppTheme.primaryBlue),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '📷 Ver Foto de Entrega / Evidencia: ${w.photoUrl}',
                                              style: const TextStyle(fontSize: 11, color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    )
            ],
          ),
        );
      },
    );
  }
}
