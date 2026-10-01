import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/raffle.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/file_picker_helper.dart';
import 'package:rifaapp/ui/core/utils/image_compress.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/core/utils/file_saver.dart';
import 'package:rifaapp/ui/core/utils/url_launcher_helper.dart' as web_launcher;

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
  bool _colorByStatus = false; // false = unicolor, true = color per status
  String _singleCircleColorHex = '#DC2626'; // Default red

  // Circle color per ticket status (used when _colorByStatus is on); editable and saved with the template
  Map<String, String> _statusCircleColors = Map.of(_defaultStatusCircleColors);
  static const Map<String, String> _defaultStatusCircleColors = {
    'PAGADA': '#10B981',
    'ABONO_PARCIAL': '#F59E0B',
    'RESERVADA': '#8B5CF6',
  };
  static const Map<String, String> _statusColorLabels = {
    'PAGADA': 'Pagada',
    'ABONO_PARCIAL': 'Abono',
    'RESERVADA': 'Reservada',
  };

  static const List<String> _colorPalette = [
    '#DC2626',
    '#EF4444',
    '#F97316',
    '#F59E0B',
    '#EAB308',
    '#FACC15',
    '#84CC16',
    '#22C55E',
    '#10B981',
    '#14B8A6',
    '#06B6D4',
    '#0EA5E9',
    '#2563EB',
    '#4F46E5',
    '#8B5CF6',
    '#A855F7',
    '#D946EF',
    '#EC4899',
    '#1F2937',
    '#FFFFFF',
  ];

  final bool _fillCellBg = true;
  final Color _cellBgColor = Colors.white.withValues(alpha: 0.92);

  final ScrollController _scrollController = ScrollController();

  List<Ticket> _allRaffleTickets = [];

  // Template image is stored apart from the raffle data and loaded on demand
  String? _templateStatus; // non-null while loading / compressing / saving the image
  bool _templateChanged = false; // new image picked but not uploaded yet

  @override
  void initState() {
    super.initState();
    final config = widget.raffle.templateConfig;
    if (config != null) {
      // Older data kept the image inside the settings; newer data keeps it in the template store
      _bgImageBase64 = config['templateImageBase64'];
      _gridTopPercent = (config['gridTopPercent'] as num?)?.toDouble() ?? 0.50;
      _gridLeftPercent = (config['gridLeftPercent'] as num?)?.toDouble() ?? 0.05;
      _gridWidthPercent = (config['gridWidthPercent'] as num?)?.toDouble() ?? 0.90;
      _cellHeight = (config['cellHeight'] as num?)?.toDouble() ?? 24.0;
      _fontSize = (config['fontSize'] as num?)?.toDouble() ?? 10.0;
      _dotScale = (config['dotScale'] as num?)?.toDouble() ?? 1.0;
      _colorByStatus = (config['colorByStatus'] as bool?) ?? false;
      _singleCircleColorHex = (config['singleCircleColorHex'] as String?) ?? '#DC2626';
      final savedStatusColors = config['statusCircleColors'];
      if (savedStatusColors is Map) {
        savedStatusColors.forEach((k, v) {
          if (_defaultStatusCircleColors.containsKey(k) && v is String) _statusCircleColors[k.toString()] = v;
        });
      }
    }

    _loadRaffleTickets();
    if (_bgImageBase64 == null && widget.raffle.templates.containsKey('poster')) _loadPosterTemplate();
  }

  Future<void> _loadPosterTemplate() async {
    setState(() => _templateStatus = 'Cargando plantilla del afiche...');
    try {
      if (widget.raffle.aficheUrl != null) {
        if (mounted) setState(() => _bgImageBase64 = widget.raffle.aficheUrl);
      } else {
        final dataUri = await RaffleRepository().fetchRaffleTemplate(widget.raffle.id, 'poster');
        if (mounted) setState(() => _bgImageBase64 = dataUri);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('No se pudo cargar la plantilla: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _templateStatus = null);
    }
  }

  /// Swatch button that opens the color picker.
  Widget _buildColorButton({required String label, required String hex, required ValueChanged<String> onPicked}) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () async {
        final picked = await _showColorPicker(label, hex);
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: _parseHexColor(hex),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black26),
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
            const SizedBox(width: 4),
            const Icon(Icons.edit, size: 12, color: Colors.black45),
          ],
        ),
      ),
    );
  }

  /// Palette plus exact hex code; returns the chosen color as #RRGGBB or null if cancelled.
  Future<String?> _showColorPicker(String title, String currentHex) {
    String selected = currentHex.toUpperCase();
    final hexController = TextEditingController(text: selected);
    final hexPattern = RegExp(r'^#?[0-9A-Fa-f]{6}$');

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final valid = hexPattern.hasMatch(hexController.text.trim());
          return AlertDialog(
            title: Text('Color: $title'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final hex in _colorPalette)
                        GestureDetector(
                          onTap: () => setDialogState(() {
                            selected = hex;
                            hexController.text = hex;
                          }),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _parseHexColor(hex),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected == hex ? Colors.black : Colors.black26,
                                width: selected == hex ? 3 : 1,
                              ),
                            ),
                            child:
                                selected == hex ? Icon(Icons.check, size: 16, color: hex == '#FFFFFF' ? Colors.black : Colors.white) : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: valid ? _parseHexColor(hexController.text.trim()) : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black26),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: hexController,
                          decoration: InputDecoration(
                            labelText: 'Código exacto (#RRGGBB)',
                            errorText: valid ? null : 'Ejemplo: #FF5722',
                            isDense: true,
                          ),
                          onChanged: (v) => setDialogState(() {
                            if (hexPattern.hasMatch(v.trim())) selected = _normalizeHex(v.trim());
                          }),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: valid ? () => Navigator.pop(ctx, _normalizeHex(hexController.text.trim())) : null,
                child: const Text('Aplicar'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _normalizeHex(String value) => '#${value.replaceFirst('#', '').toUpperCase()}';

  Color _parseHexColor(String hexString) {
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return Colors.red.shade600;
    }
  }

  Color _getCircleColorForTicket(Ticket matchedTicket) {
    if (_colorByStatus) {
      switch (matchedTicket.status) {
        case 'CONFIRMADA':
        case 'PAGADA':
          return _parseHexColor(_statusCircleColors['PAGADA']!);
        case 'ABONO_PARCIAL':
          return _parseHexColor(_statusCircleColors['ABONO_PARCIAL']!);
        case 'RESERVADA':
          return _parseHexColor(_statusCircleColors['RESERVADA']!);
        default:
          return _parseHexColor(_singleCircleColorHex);
      }
    } else {
      return _parseHexColor(_singleCircleColorHex);
    }
  }

  void _loadRaffleTickets() async {
    try {
      final repo = RaffleRepository();
      final fetched = await repo.fetchTickets(raffleId: widget.raffle.id);
      if (mounted) {
        setState(() {
          _allRaffleTickets = fetched;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _saveTemplateConfig() async {
    final raffleVM = Provider.of<RaffleViewModel>(context, listen: false);
    if (_templateChanged && _bgImageBase64 != null) {
      setState(() => _templateStatus = 'Guardando imagen del afiche en Google Drive...');
      try {
        final updatedRaffle = await ApiService().uploadRaffleAfiche(widget.raffle.id, _bgImageBase64!);
        raffleVM.updateRaffleInList(updatedRaffle);
        await RaffleRepository().saveRaffleTemplate(widget.raffle.id, 'poster', _bgImageBase64!);
        _templateChanged = false;
      } catch (e) {
        if (mounted) {
          setState(() => _templateStatus = null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.red, content: Text('No se pudo guardar la imagen en Google Drive: $e')),
          );
        }
        return;
      }
      if (mounted) setState(() => _templateStatus = null);
    }
    // Only the settings travel with the raffle; the image lives in the template store
    final newConfig = {
      'gridTopPercent': _gridTopPercent,
      'gridLeftPercent': _gridLeftPercent,
      'gridWidthPercent': _gridWidthPercent,
      'cellHeight': _cellHeight,
      'fontSize': _fontSize,
      'dotScale': _dotScale,
      'colorByStatus': _colorByStatus,
      'singleCircleColorHex': _singleCircleColorHex,
      'statusCircleColors': _statusCircleColors,
    };

    bool ok = await raffleVM.updateRaffleTemplateConfig(widget.raffle.id, newConfig);
    if (ok) await raffleVM.loadRaffles();
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
      String? picked = await pickImageBase64();
      if (picked != null) {
        setState(() => _templateStatus = 'Optimizando imagen...');
        await Future.delayed(const Duration(milliseconds: 50)); // let the progress bar paint
        final imageStr = compressImageDataUri(picked, maxSide: 2400);
        if (!mounted) return;
        setState(() {
          _templateStatus = null;
          _templateChanged = true;
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
              content: Text('✓ Plantilla cargada. Ajuste la grilla y pulse "Guardar Plantilla" para conservarla.'),
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
          await saveAndDownloadBytes(
            'afiche_rifa_2d_${widget.raffle.id}.png',
            pngBytes,
            mimeType: 'image/png',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppTheme.secondaryEmerald,
                content: Text(kIsWeb
                    ? '✓ Afiche ajustado descargado exitosamente como imagen PNG (Alta Definición).'
                    : '✓ Afiche listo: elija dónde guardarlo o a quién enviarlo.'),
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
    // Printing from the page only exists in the browser; in the app the poster goes to the
    // share sheet, from where it can be printed, saved as a file or sent.
    if (!kIsWeb) {
      _downloadPosterAsImage();
      return;
    }
    try {
      web_launcher.printPage();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Para imprimir o guardar como PDF, presione Ctrl+P en su navegador.')),
      );
    }
  }

  /// Check if a 2-digit number ("00" to "99") is sold/taken (FIADO, APARTADO, ABONADO, PAGADO, CONFIRMADO, RESERVADO)
  Ticket? _getTicketForNumber(String numStr, List<Ticket> ticketsList) {
    final tickets = _allRaffleTickets.isNotEmpty ? _allRaffleTickets : ticketsList;
    final cleanTarget = numStr.trim();
    final targetInt = int.tryParse(cleanTarget);

    for (var ticket in tickets) {
      if (ticket.status != 'DISPONIBLE' && ticket.status.isNotEmpty) {
        for (var n in ticket.numbers) {
          final cleanN = n.trim();
          // 1. Exact string match (e.g. '58' == '58')
          if (cleanN == cleanTarget) return ticket;
          // 2. Padded 2-digit match (e.g. '8' -> '08')
          if (cleanN.padLeft(2, '0') == cleanTarget) return ticket;
          // 3. Last 2 digits match (e.g. '0058' -> '58', '2558' -> '58')
          if (cleanN.length >= 2 && cleanN.substring(cleanN.length - 2) == cleanTarget) return ticket;
          // 4. Integer numeric match (e.g. 58 == 58 or 2558 % 100 == 58)
          final nInt = int.tryParse(cleanN);
          if (targetInt != null && nInt != null) {
            if (nInt == targetInt || nInt % 100 == targetInt) return ticket;
          }
        }
      }
    }
    return null;
  }

  bool _isNumberSold(String numStr, List<Ticket> tickets) {
    return _getTicketForNumber(numStr, tickets) != null;
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
        padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 10 : 16),
        child: Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.42),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // HEADER DIALOG
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: goldAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.grid_on_rounded, color: goldAccent, size: 26),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Plantilla Afiche Rifa 2D (100 Números)',
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
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
                              ),
                            ],
                          ),
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
                        Wrap(
                          alignment: WrapAlignment.start,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 8,
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
                        Wrap(
                          alignment: WrapAlignment.start,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isExportingImage ? null : _downloadPosterAsImage,
                              icon: _isExportingImage
                                  ? const SizedBox(
                                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.download, size: 18),
                              label: const Text('Descargar Imagen PNG (HD)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF8B5CF6), // Purple accent
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
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

                    if (_templateStatus != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 8),
                          Text(_templateStatus!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const LinearProgressIndicator(minHeight: 3),
                    ],
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
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text(
                                  '⚙️ Controles de Alto, Ancho, Posición y Zoom de la Grilla:',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.brown),
                                ),
                                Wrap(
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
                                      Text('🔍 Zoom Vista: ${(_posterScale * 100).toInt()}%',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                                        Text('↕️ Posición Vertical (Top): ${(_gridTopPercent * 100).toInt()}%',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                                        Text('↔️ Posición Horizontal (Left): ${(_gridLeftPercent * 100).toInt()}%',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                                      Text('📏 Alto de Grilla / Celdas: ${_cellHeight.toInt()} px',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
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
                                      Text('📐 Ancho de Grilla: ${(_gridWidthPercent * 100).toInt()}%',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                                      Text('🔤 Tamaño Texto: ${_fontSize.toStringAsFixed(1)} px',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                                      Text('🔴 Círculo Rojo: ${_dotScale.toStringAsFixed(1)}x',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                            const Divider(height: 16),

                            // ROW 3: Circle colors (one color for all, or one editable color per status)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text(
                                  '🎨 Color de Círculos:',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown),
                                ),
                                ChoiceChip(
                                  label: const Text('Todos iguales', style: TextStyle(fontSize: 11)),
                                  selected: !_colorByStatus,
                                  selectedColor: Colors.amber.shade200,
                                  onSelected: (val) {
                                    if (val) setState(() => _colorByStatus = false);
                                  },
                                ),
                                ChoiceChip(
                                  label: const Text('Por estado', style: TextStyle(fontSize: 11)),
                                  selected: _colorByStatus,
                                  selectedColor: Colors.amber.shade200,
                                  onSelected: (val) {
                                    if (val) setState(() => _colorByStatus = true);
                                  },
                                ),
                                if (!_colorByStatus)
                                  _buildColorButton(
                                    label: 'Color',
                                    hex: _singleCircleColorHex,
                                    onPicked: (hex) => setState(() => _singleCircleColorHex = hex),
                                  )
                                else
                                  for (final status in _statusColorLabels.keys)
                                    _buildColorButton(
                                      label: _statusColorLabels[status]!,
                                      hex: _statusCircleColors[status]!,
                                      onPicked: (hex) => setState(() => _statusCircleColors[status] = hex),
                                    ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Toque un color para cambiarlo. Pulse "Guardar Plantilla" para conservar la configuración.',
                              style: TextStyle(fontSize: 11, color: Colors.brown.shade400),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
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
                            // Scaled down to fit phones; the PNG export still captures full size.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
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
        border: Border.all(color: goldAccent.withValues(alpha: 0.6), width: 2),
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
              boxShadow: [BoxShadow(color: goldAccent.withValues(alpha: 0.4), blurRadius: 10)],
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
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: goldAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: goldAccent.withValues(alpha: 0.2),
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
              color: Colors.white.withValues(alpha: 0.08),
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
    final activeTickets = _allRaffleTickets.isNotEmpty ? _allRaffleTickets : tickets;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(10, (rowIndex) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(10, (colIndex) {
            int numInt = rowIndex * 10 + colIndex;
            String numStr = numInt.toString().padLeft(2, '0');
            Ticket? matchedTicket = _getTicketForNumber(numStr, activeTickets);
            bool isSold = matchedTicket != null;

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

                    // Dynamic Circle Overlay for TAKEN numbers (Fiadas, Apartadas, Abonadas, Pagadas, Reservadas)
                    if (isSold)
                      Builder(
                        builder: (_) {
                          final circleColor = _getCircleColorForTicket(matchedTicket);
                          return Transform.scale(
                            scale: _dotScale,
                            child: Container(
                              width: _cellHeight * 0.78,
                              height: _cellHeight * 0.78,
                              decoration: BoxDecoration(
                                color: circleColor.withValues(alpha: 0.95),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: _cellHeight * 0.50,
                                ),
                              ),
                            ),
                          );
                        },
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
