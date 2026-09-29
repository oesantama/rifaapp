import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/raffle.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/file_picker_helper.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/core/utils/file_saver_web.dart' if (dart.library.io) 'package:rifaapp/ui/core/utils/file_saver_stub.dart';
import 'dart:html' if (dart.library.io) 'file_saver_stub.dart' as html_shim;

const Color goldAccent = Color(0xFFD4AF37);

class RafflePoster2dDialog extends StatefulWidget {
  final Raffle raffle;

  const RafflePoster2dDialog({
    super.key,
    required this.raffle,
  });

  @override
  State<RafflePoster2dDialog> createState() => _RafflePoster2dDialogState();
}

class _RafflePoster2dDialogState extends State<RafflePoster2dDialog> {
  final GlobalKey _posterKey = GlobalKey();
  String? _bgImageBase64;
  bool _showCustomControls = true;
  bool _isExportingImage = false;

  // Custom positioning & sizing controls for background & grid
  double _gridTopPercent = 0.50; // vertical position (0.10 to 0.85)
  double _gridLeftPercent = 0.05; // horizontal position offset (0.0 to 0.20)
  double _gridWidthPercent = 0.90; // width relative to poster (0.50 to 0.98)
  double _cellHeight = 24.0; // height of each cell/row (16.0 to 45.0)
  double _fontSize = 10.0; // font size of number text (8.0 to 16.0)
  double _dotScale = 1.0; // scale for red dots (0.5 to 1.8)
  double _posterScale = 0.75; // Zoom scale for poster preview (0.40 to 1.20)

  final bool _fillCellBg = true;
  final Color _cellBgColor = Colors.white.withOpacity(0.92);

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final config = widget.raffle.templateConfig;
    if (config != null) {
      _bgImageBase64 = config['templateImageBase64'];
      _gridTopPercent = (config['gridTopPercent'] as num?)?.toDouble() ?? 0.50;
      _gridLeftPercent = (config['gridLeftPercent'] as num?)?.toDouble() ?? 0.05;
      _gridWidthPercent = (config['gridWidthPercent'] as num?)?.toDouble() ?? 0.90;
      _cellHeight = (config['cellHeight'] as num?)?.toDouble() ?? 24.0;
      _fontSize = (config['fontSize'] as num?)?.toDouble() ?? 10.0;
      _dotScale = (config['dotScale'] as num?)?.toDouble() ?? 1.0;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _saveTemplateConfig() async {
    final raffleVM = Provider.of<RaffleViewModel>(context, listen: false);
    final newConfig = {
      'templateImageBase64': _bgImageBase64,
      'gridTopPercent': _gridTopPercent,
      'gridLeftPercent': _gridLeftPercent,
      'gridWidthPercent': _gridWidthPercent,
      'cellHeight': _cellHeight,
      'fontSize': _fontSize,
      'dotScale': _dotScale,
    };

    bool ok = await raffleVM.updateRaffleTemplateConfig(widget.raffle.id, newConfig);
    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppTheme.secondaryEmerald,
            content: Text('✓ Configuración e imagen de plantilla guardadas con éxito en la rifa.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(raffleVM.errorMessage ?? 'Error al guardar la plantilla.'),
          ),
        );
      }
    }
  }

  void _pickBgImage() async {
    try {
      String? imageStr = await pickImageBase64();
      if (imageStr != null) {
        setState(() {
          _bgImageBase64 = imageStr;
          _showCustomControls = true;
          // Optimize defaults for custom image template
          _gridTopPercent = 0.52;
          _cellHeight = 22.0;
          _fontSize = 9.5;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.secondaryEmerald,
              content: Text('✓ Plantilla de afiche cargada. Ajusta el Alto y Ancho de la grilla si es necesario.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error al cargar imagen: $e')),
        );
      }
    }
  }

  void _downloadPosterAsImage() async {
    setState(() => _isExportingImage = true);
    try {
      await Future.delayed(const Duration(milliseconds: 150));
      RenderRepaintBoundary? boundary = _posterKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        ui.Image image = await boundary.toImage(pixelRatio: 3.0);
        ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          Uint8List pngBytes = byteData.buffer.asUint8List();
          saveAndDownloadBytes(
            'afiche_rifa_2d_${widget.raffle.id}.png',
            pngBytes,
            mimeType: 'image/png',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: AppTheme.secondaryEmerald,
                content: Text('✓ Afiche ajustado descargado exitosamente como imagen PNG (Alta Definición).'),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error al descargar imagen: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingImage = false);
      }
    }
  }

  void _triggerPrint() {
    try {
      // ignore: undefined_prefix_name
      html_shim.window.print();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Para imprimir o guardar como PDF, presione Ctrl+P en su navegador.')),
      );
    }
  }

  /// Check if a 2-digit number ("00" to "99") is sold/taken (FIADO, ABONADO, PAGADO, CONFIRMADO, RESERVADO)
  bool _isNumberSold(String numStr, List<Ticket> tickets) {
    for (var ticket in tickets) {
      if (ticket.status != 'DISPONIBLE') {
        if (ticket.numbers.contains(numStr)) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 1020,
        height: MediaQuery.of(context).size.height * 0.95,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // HEADER DIALOG
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: goldAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.grid_on_rounded, color: goldAccent, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Plantilla Afiche Rifa 2D (100 Números)',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryDark,
                              ),
                        ),
                        Text(
                          '${widget.raffle.title} • Estado de Celdas (Vendidas / Disponibles)',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: 'Cerrar',
                ),
              ],
            ),
            const Divider(height: 14),

            // TOOLBAR ACTIONS
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickBgImage,
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: Text(_bgImageBase64 == null ? 'Subir Imagen de Plantilla' : 'Cambiar Plantilla'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _showCustomControls = !_showCustomControls;
                        });
                      },
                      icon: Icon(_showCustomControls ? Icons.expand_less : Icons.tune, size: 18),
                      label: Text(_showCustomControls ? 'Ocultar Ajustes' : 'Ajustar Grilla (Alto/Ancho) y Zoom'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _saveTemplateConfig,
                      icon: const Icon(Icons.save, size: 18),
                      label: const Text('Guardar Plantilla'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentAmber,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isExportingImage ? null : _downloadPosterAsImage,
                      icon: _isExportingImage
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.download, size: 18),
                      label: const Text('Descargar Imagen PNG (HD)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6), // Purple accent
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _triggerPrint,
                      icon: const Icon(Icons.print, size: 18),
                      label: const Text('Imprimir / Guardar PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondaryEmerald,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // CONTROLS PANEL (COLLAPSIBLE WITH FULL DIMENSION SLIDERS)
            if (_showCustomControls) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '⚙️ Controles de Alto, Ancho, Posición y Zoom de la Grilla:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.brown),
                        ),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => setState(() => _posterScale = 0.55),
                              icon: const Icon(Icons.fit_screen, size: 16),
                              label: const Text('Encajar en Pantalla', style: TextStyle(fontSize: 12)),
                            ),
                            TextButton.icon(
                              onPressed: () => setState(() => _posterScale = 1.0),
                              icon: const Icon(Icons.zoom_in, size: 16),
                              label: const Text('Tamaño Real (100%)', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // ROW 1: Zoom, Posición Vertical (Top), Posición Horizontal (Left)
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('🔍 Zoom Vista: ${(_posterScale * 100).toInt()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              Slider(
                                value: _posterScale,
                                min: 0.40,
                                max: 1.20,
                                onChanged: (v) => setState(() => _posterScale = v),
                              ),
                            ],
                          ),
                        ),
                        if (_bgImageBase64 != null) ...[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('↕️ Posición Vertical (Top): ${(_gridTopPercent * 100).toInt()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                Slider(
                                  value: _gridTopPercent,
                                  min: 0.10,
                                  max: 0.85,
                                  onChanged: (v) => setState(() => _gridTopPercent = v),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('↔️ Posición Horizontal (Left): ${(_gridLeftPercent * 100).toInt()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                Slider(
                                  value: _gridLeftPercent,
                                  min: 0.0,
                                  max: 0.20,
                                  onChanged: (v) => setState(() => _gridLeftPercent = v),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),

                    // ROW 2: Alto Grilla/Celdas, Ancho Grilla, Tamaño Texto, Tamaño Círculo Rojo
                    Row(
                      children: [
                        // Alto Celdas / Grilla
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('📏 Alto de Grilla / Celdas: ${_cellHeight.toInt()} px', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                              Slider(
                                value: _cellHeight,
                                min: 16.0,
                                max: 45.0,
                                activeColor: Colors.indigo,
                                onChanged: (v) => setState(() => _cellHeight = v),
                              ),
                            ],
                          ),
                        ),
                        // Ancho Grilla
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('📐 Ancho de Grilla: ${(_gridWidthPercent * 100).toInt()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              Slider(
                                value: _gridWidthPercent,
                                min: 0.50,
                                max: 0.98,
                                onChanged: (v) => setState(() => _gridWidthPercent = v),
                              ),
                            ],
                          ),
                        ),
                        // Tamaño Texto
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('🔤 Tamaño Texto: ${_fontSize.toStringAsFixed(1)} px', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              Slider(
                                value: _fontSize,
                                min: 8.0,
                                max: 16.0,
                                onChanged: (v) => setState(() => _fontSize = v),
                              ),
                            ],
                          ),
                        ),
                        // Círculo Rojo
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('🔴 Círculo Rojo: ${_dotScale.toStringAsFixed(1)}x', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              Slider(
                                value: _dotScale,
                                min: 0.5,
                                max: 1.8,
                                onChanged: (v) => setState(() => _dotScale = v),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            // CANVAS / POSTER DISPLAY (SCROLLABLE & ZOOMABLE WITH REPAINTBOUNDARY)
            Expanded(
              child: Consumer<TicketViewModel>(
                builder: (context, ticketVM, _) {
                  final tickets = ticketVM.tickets;

                  return Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                        child: Center(
                          child: Transform.scale(
                            scale: _posterScale,
                            alignment: Alignment.topCenter,
                            child: RepaintBoundary(
                              key: _posterKey,
                              child: _bgImageBase64 != null
                                  ? _buildCustomTemplatePoster(context, tickets)
                                  : _buildDefaultLuxuryPoster(context, tickets, currency),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds custom template background with dynamic grid overlay
  Widget _buildCustomTemplatePoster(BuildContext context, List<Ticket> tickets) {
    Uint8List? bgBytes;
    if (_bgImageBase64 != null) {
      if (_bgImageBase64!.startsWith('data:image')) {
        try {
          bgBytes = base64Decode(_bgImageBase64!.split(',').last);
        } catch (_) {}
      } else {
        try {
          bgBytes = base64Decode(_bgImageBase64!);
        } catch (_) {}
      }
    }

    double posterWidth = 600;
    double posterHeight = 900;

    return Container(
      width: posterWidth,
      height: posterHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // 1. Background Image Widget (explicit RenderImage for RepaintBoundary PNG capture)
            if (bgBytes != null)
              Positioned.fill(
                child: Image.memory(
                  bgBytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (ctx, err, stack) => Container(color: Colors.grey.shade400),
                ),
              )
            else if (_bgImageBase64 != null)
              Positioned.fill(
                child: Image.network(
                  _bgImageBase64!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (ctx, err, stack) => Container(color: Colors.grey.shade400),
                ),
              ),

            // 2. Grid Overlay
            Positioned(
              top: posterHeight * _gridTopPercent,
              left: posterWidth * _gridLeftPercent,
              width: posterWidth * _gridWidthPercent,
              child: _build10x10NumbersGrid(tickets, isDarkTheme: false),
            ),
          ],
        ),
      ),
    );
  }

  /// Built-in luxury template poster (matching the user's reference image structure!)
  Widget _buildDefaultLuxuryPoster(BuildContext context, List<Ticket> tickets, NumberFormat currency) {
    final raffle = widget.raffle;

    return Container(
      width: 580,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F141C), Color(0xFF1E2638), Color(0xFF0F141C)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 10)),
        ],
        border: Border.all(color: goldAccent.withOpacity(0.6), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // BANNER CORONA Y TITULO
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.emoji_events_rounded, color: goldAccent, size: 36),
              const SizedBox(width: 8),
              Text(
                'GRAN RIFA',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  foreground: Paint()
                    ..shader = const LinearGradient(
                      colors: [Color(0xFFFFDF7A), Color(0xFFD4AF37), Color(0xFF997A15)],
                    ).createShader(const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.emoji_events_rounded, color: goldAccent, size: 36),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            raffle.title.toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // PUESTO / PRECIO BANNER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFD4AF37), Color(0xFFFFF1B0), Color(0xFFD4AF37)],
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [BoxShadow(color: goldAccent.withOpacity(0.4), blurRadius: 10)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'VALOR DE CADA PUESTO: ',
                  style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  currency.format(raffle.ticketPrice),
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // PREMIO BANNER
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: goldAccent.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: goldAccent.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.card_giftcard, color: goldAccent, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PREMIO PRINCIPAL',
                        style: TextStyle(color: goldAccent, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        raffle.description.isNotEmpty ? raffle.description : 'Sorteo con múltiples números por boleta',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // CONTENEDOR BLANCO CON MATRIX DE 100 NUMEROS (00 al 99)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)],
            ),
            child: _build10x10NumbersGrid(tickets, isDarkTheme: false),
          ),
          const SizedBox(height: 16),

          // SORTEO / FECHA
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_month, color: goldAccent, size: 24),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('JUEGA EL DÍA:', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                        Text(
                          raffle.mainDrawDate.length >= 10 ? raffle.mainDrawDate.substring(0, 10) : raffle.mainDrawDate,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.casino, color: AppTheme.secondaryEmerald, size: 24),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('SORTEO OFICIAL:', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                        const Text(
                          'Últimas 2 cifras',
                          style: TextStyle(color: goldAccent, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '¡Buena Suerte! ♡',
            style: TextStyle(color: goldAccent, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5),
          ),
        ],
      ),
    );
  }

  /// 10x10 Grid representation of 100 numbers (00 to 99)
  Widget _build10x10NumbersGrid(List<Ticket> tickets, {required bool isDarkTheme}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(10, (rowIndex) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(10, (colIndex) {
            int numInt = rowIndex * 10 + colIndex;
            String numStr = numInt.toString().padLeft(2, '0');
            bool isSold = _isNumberSold(numStr, tickets);

            return Expanded(
              child: Container(
                margin: const EdgeInsets.all(1.0),
                height: _cellHeight,
                decoration: BoxDecoration(
                  color: _fillCellBg ? _cellBgColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300, width: 1),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Clean Number Text
                    Text(
                      numStr,
                      style: TextStyle(
                        fontSize: _fontSize,
                        fontWeight: FontWeight.bold,
                        color: isDarkTheme ? Colors.white : Colors.black87,
                      ),
                    ),

                    // Red Circle Overlay for SOLD numbers (Fiado, Abonado, Pagado, Reservado)
                    if (isSold)
                      Transform.scale(
                        scale: _dotScale,
                        child: Container(
                          width: _cellHeight * 0.75,
                          height: _cellHeight * 0.75,
                          decoration: BoxDecoration(
                            color: Colors.red.shade600.withOpacity(0.92),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.4),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: _cellHeight * 0.45,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
        );
      }),
    );
  }
}
