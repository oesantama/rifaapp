import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/widgets/responsive_flex_child.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';
import 'package:rifaapp/ui/core/utils/file_picker_helper.dart';
import 'package:rifaapp/ui/core/utils/image_compress.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/core/utils/url_launcher_helper.dart' as web_launcher;

class TicketPrintDialog extends StatefulWidget {
  final Ticket ticket;
  final String raffleTitle;

  const TicketPrintDialog({
    super.key,
    required this.ticket,
    required this.raffleTitle,
  });

  @override
  State<TicketPrintDialog> createState() => _TicketPrintDialogState();
}

class _TicketPrintDialogState extends State<TicketPrintDialog> {
  Color _themeColor = AppTheme.primaryBlue;
  String? _bgImageBase64;
  bool _showTalonario = true;

  String? _templateStatus; // non-null while loading / saving the ticket design

  @override
  void initState() {
    super.initState();
    _loadTicketTemplate();
  }

  /// The ticket design is saved per raffle, so it is ready every time a ticket is printed.
  Future<void> _loadTicketTemplate() async {
    setState(() => _templateStatus = 'Cargando diseño de la boleta...');
    try {
      final dataUri = await RaffleRepository().fetchRaffleTemplate(widget.ticket.raffleId, 'ticket');
      if (mounted) setState(() => _bgImageBase64 = dataUri);
    } catch (_) {
      // Printing still works without the design
    } finally {
      if (mounted) setState(() => _templateStatus = null);
    }
  }

  void _pickBgImage() async {
    try {
      String? picked = await pickImageBase64();
      if (picked == null) return;
      setState(() => _templateStatus = 'Optimizando y guardando el diseño...');
      await Future.delayed(const Duration(milliseconds: 50)); // let the progress indicator paint
      final imageStr = compressImageDataUri(picked, maxSide: 2000);
      await RaffleRepository().saveRaffleTemplate(widget.ticket.raffleId, 'ticket', imageStr);
      if (!mounted) return;
      setState(() => _bgImageBase64 = imageStr);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.secondaryEmerald,
          content: Text('✓ Diseño de boleta guardado para esta rifa. Se usará en todas las impresiones.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('No se pudo guardar el diseño: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _templateStatus = null);
    }
  }

  void _removeBgImage() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quitar el diseño de la boleta?'),
        content: const Text('Se quitará para todas las boletas de esta rifa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await RaffleRepository().deleteRaffleTemplate(widget.ticket.raffleId, 'ticket');
      if (mounted) setState(() => _bgImageBase64 = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('No se pudo quitar el diseño: $e')),
        );
      }
    }
  }

  String get _companyName {
    final name = Provider.of<AuthViewModel>(context, listen: false).companyName;
    return name.startsWith('🏢') ? 'RIFA MASTER' : name.toUpperCase();
  }

  /// Faint diagonal text repeated over the whole receipt (company name + ORIGINAL).
  Widget _buildWatermark() {
    final text = '$_companyName • ORIGINAL • ';
    return ClipRect(
      child: Center(
        child: Transform.rotate(
          angle: -0.32,
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < 9; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      List.filled(6, text).join(),
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: _themeColor.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tiny repeated text line: printed it looks like a solid line, a photocopy blurs it.
  Widget _buildMicroText() {
    final code = widget.ticket.verificationCode ?? 'SIN-VENDER';
    return Text(
      List.filled(12, 'RIFA MASTER · DOCUMENTO VERIFICABLE · $code · ').join(),
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
      style: TextStyle(fontSize: 4.5, letterSpacing: 0.4, color: _themeColor.withValues(alpha: 0.55)),
    );
  }

  /// Seal + verification code + QR that opens the public verification page.
  Widget _buildSecurityStrip() {
    final code = widget.ticket.verificationCode;
    if (code == null) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
        child: const Text('Boleta sin vender: este documento NO es válido como comprobante.',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
      );
    }
    final url = ApiService.verificationUrl(code);
    final issued = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _themeColor.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Row(
        children: [
          _buildSeal(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('VERIFIQUE LA AUTENTICIDAD',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: Colors.black87)),
                const SizedBox(height: 2),
                const Text('Escanee el código QR con la cámara del celular.', style: TextStyle(fontSize: 9.5, color: Colors.black54)),
                const SizedBox(height: 6),
                Text('Código: $code',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: _themeColor, fontFamily: 'monospace')),
                Text('Emitido: $issued', style: const TextStyle(fontSize: 9, color: Colors.black54)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(4),
            color: Colors.white,
            // Painted directly (QrImageView uses a LayoutBuilder, which breaks the receipt's IntrinsicHeight)
            child: CustomPaint(
              size: const Size.square(86),
              painter: QrPainter(
                data: url,
                version: QrVersions.auto,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: _themeColor),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0F172A)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Circular security seal with the company name.
  Widget _buildSeal() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _themeColor, width: 2),
        gradient: RadialGradient(colors: [_themeColor.withValues(alpha: 0.12), _themeColor.withValues(alpha: 0.02)]),
      ),
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _themeColor.withValues(alpha: 0.6), width: 0.8)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified, size: 18, color: _themeColor),
            Text('ORIGINAL', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 0.6, color: _themeColor)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _companyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 5.5, fontWeight: FontWeight.bold, color: _themeColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _triggerPrint() {
    try {
      web_launcher.printPage();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Para imprimir, presione Ctrl+P en su navegador.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    ImageProvider? bgDecorationImage;
    if (_bgImageBase64 != null) {
      if (_bgImageBase64!.startsWith('data:image')) {
        String base64Content = _bgImageBase64!.split(',').last;
        bgDecorationImage = MemoryImage(base64Decode(base64Content));
      } else {
        bgDecorationImage = NetworkImage(_bgImageBase64!);
      }
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 820,
        padding: EdgeInsets.all(isNarrowScreen(context) ? 14 : 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // HEADER DIALOG
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.print, color: _themeColor, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Impresión de Boleta - N° ${widget.ticket.displayNumber}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Text(
                          'Diseño con Talonario de Control y espacio para plantilla personalizada del administrador.',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 20),

              // BARRA DE HERRAMIENTAS DE DISEÑO
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _triggerPrint,
                    icon: const Icon(Icons.print),
                    label: const Text('IMPRIMIR'),
                    style: ElevatedButton.styleFrom(backgroundColor: _themeColor),
                  ),
                  // Only administrators change the raffle's ticket design; advisors print with it
                  if (Provider.of<AuthViewModel>(context, listen: false).isAdmin)
                    OutlinedButton.icon(
                      onPressed: _templateStatus != null ? null : _pickBgImage,
                      icon: const Icon(Icons.image, size: 16),
                      label: Text(_bgImageBase64 == null ? 'Subir Diseño/Fondo de Boleta' : 'Cambiar Imagen de Fondo'),
                    ),
                  if (_templateStatus != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 6),
                        Text(_templateStatus!, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  if (_bgImageBase64 != null && Provider.of<AuthViewModel>(context, listen: false).isAdmin) ...[
                    TextButton.icon(
                      onPressed: _removeBgImage,
                      icon: const Icon(Icons.delete, color: Colors.red, size: 16),
                      label: const Text('Quitar Fondo', style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Mostrar Talonario:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Switch(
                        value: _showTalonario,
                        activeColor: _themeColor,
                        onChanged: (val) => setState(() => _showTalonario = val),
                      ),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 14),

              // CANVAS IMPRESO DE LA BOLETA (se escala en pantallas pequeñas)
              LayoutBuilder(
                builder: (context, constraints) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: constraints.maxWidth < 772 ? 772 : constraints.maxWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _themeColor.withOpacity(0.4), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          )
                        ],
                        image: bgDecorationImage != null
                            ? DecorationImage(
                                image: bgDecorationImage,
                                fit: BoxFit.cover,
                                colorFilter: ColorFilter.mode(
                                  Colors.white.withOpacity(0.82),
                                  BlendMode.lighten,
                                ),
                              )
                            : null,
                      ),
                      child: Stack(
                        children: [
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // TALONARIO / STUB DE CONTROL (IZQUIERDA)
                                if (_showTalonario)
                                  Container(
                                    width: 230,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: bgDecorationImage != null ? Colors.white.withOpacity(0.7) : Colors.grey.shade50,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(14),
                                        bottomLeft: Radius.circular(14),
                                      ),
                                      border: Border(
                                        right: BorderSide(color: Colors.grey.shade400, width: 2, style: BorderStyle.solid),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _themeColor.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'TALONARIO DE CONTROL',
                                                style: TextStyle(
                                                    fontSize: 9, fontWeight: FontWeight.bold, color: _themeColor, letterSpacing: 0.8),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'BOLETA N° ${widget.ticket.displayNumber}',
                                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _themeColor),
                                            ),
                                            const Divider(height: 14),
                                            const Text('Comprador:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                            Text(
                                              widget.ticket.buyerName.isNotEmpty ? widget.ticket.buyerName : 'Pendiente',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 6),
                                            const Text('Teléfono:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                            Text(
                                              widget.ticket.buyerPhone.isNotEmpty ? widget.ticket.buyerPhone : 'N/A',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                            if (widget.ticket.buyerDocument.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              const Text('Cédula:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                              Text(widget.ticket.buyerDocument,
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                            ],
                                            const SizedBox(height: 6),
                                            const Text('Vendedor / Asesor:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                            Text(
                                              widget.ticket.advisorName.isNotEmpty ? widget.ticket.advisorName : 'Admin',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 6),
                                            const Text('Monto Abonado:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                            Text(
                                              currency.format(widget.ticket.totalPaid),
                                              style: const TextStyle(
                                                  fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.secondaryEmerald),
                                            ),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            const SizedBox(height: 12),
                                            Container(
                                              height: 35,
                                              decoration: BoxDecoration(
                                                border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                'Firma / Sello Recibido',
                                                style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                                              ),
                                            ),
                                          ],
                                        )
                                      ],
                                    ),
                                  ),

                                // BOLETA PRINCIPAL PARA EL COMPRADOR (DERECHA)
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(20),
                                    color: bgDecorationImage != null ? Colors.white.withOpacity(0.65) : Colors.transparent,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    widget.raffleTitle.toUpperCase(),
                                                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _themeColor),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  const Text(
                                                    'COMPROBANTE OFICIAL DE BOLETA',
                                                    style: TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w600),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: _themeColor,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              constraints: const BoxConstraints(maxWidth: 260),
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  'N° ${widget.ticket.displayNumber}',
                                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            )
                                          ],
                                        ),
                                        const Divider(height: 20),

                                        // NÚMEROS DE OPORTUNIDAD
                                        Text(
                                          'NÚMEROS DE OPORTUNIDAD (${widget.ticket.numbers.length} NÚMEROS):',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: widget.ticket.numbers.map((numStr) {
                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: _themeColor.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: _themeColor.withOpacity(0.5), width: 1.5),
                                              ),
                                              child: Text(
                                                numStr,
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 2,
                                                  color: _themeColor,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),

                                        const SizedBox(height: 16),

                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('Valor Boleta:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                                Text(
                                                  currency.format(widget.ticket.price),
                                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('Total Abonado:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                                Text(
                                                  currency.format(widget.ticket.totalPaid),
                                                  style: const TextStyle(
                                                      fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.secondaryEmerald),
                                                ),
                                              ],
                                            ),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('Saldo Pendiente:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                                                Text(
                                                  currency.format(widget.ticket.balancePending),
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        widget.ticket.balancePending > 0 ? AppTheme.dangerRose : AppTheme.secondaryEmerald,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 12),
                                        const Divider(),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text('¡Gracias por tu compra y buena suerte! 🍀',
                                                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                                            Text(
                                              'Estado: ${AppTheme.getStatusLabel(widget.ticket.status)}',
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _themeColor),
                                            )
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        _buildSecurityStrip(),
                                      ],
                                    ),
                                  ),
                                )
                              ],
                            ),
                          ),
                          // Security layers: diagonal watermark and micro-text border (hard to reproduce cleanly)
                          Positioned.fill(child: IgnorePointer(child: _buildWatermark())),
                          Positioned(left: 8, right: 8, top: 2, child: IgnorePointer(child: _buildMicroText())),
                          Positioned(left: 8, right: 8, bottom: 2, child: IgnorePointer(child: _buildMicroText())),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
