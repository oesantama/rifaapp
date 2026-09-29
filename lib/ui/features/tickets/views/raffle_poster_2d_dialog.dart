import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/raffle.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/file_picker_helper.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
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
  String? _bgImageBase64;
  bool _showCustomControls = false;

  // Custom positioning controls for custom uploaded background
  double _gridTopPercent = 0.42; // vertical position (0.0 to 1.0)
  double _gridWidthPercent = 0.90; // width relative to poster
  double _dotScale = 1.0; // scale for red dots
  final double _fontSize = 11.0;
  final bool _fillCellBg = true;
  final Color _cellBgColor = Colors.white.withOpacity(0.92);

  void _pickBgImage() async {
    try {
      String? imageStr = await pickImageBase64();
      if (imageStr != null) {
        setState(() {
          _bgImageBase64 = imageStr;
          _showCustomControls = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.secondaryEmerald,
              content: Text('✓ Imagen de plantilla / afiche cargada con éxito. Ajusta la grilla si es necesario.'),
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 900,
        height: MediaQuery.of(context).size.height * 0.92,
        padding: const EdgeInsets.all(20),
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
                      child: const Icon(Icons.grid_on_rounded, color: goldAccent, size: 28),
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
            const Divider(height: 24),

            // TOOLBAR ACTIONS
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: _pickBgImage,
                  icon: const Icon(Icons.upload_file, size: 20),
                  label: Text(_bgImageBase64 == null ? 'Subir Imagen de Plantilla' : 'Cambiar Imagen de Plantilla'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (_bgImageBase64 != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showCustomControls = !_showCustomControls;
                      });
                    },
                    icon: Icon(_showCustomControls ? Icons.tune : Icons.settings_suggest, size: 20),
                    label: Text(_showCustomControls ? 'Ocultar Ajustes Grilla' : 'Ajustar Grilla en Plantilla'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: _triggerPrint,
                  icon: const Icon(Icons.print, size: 20),
                  label: const Text('Imprimir / Guardar PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondaryEmerald,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),

            // OPTIONAL CONTROLS PANEL
            if (_showCustomControls && _bgImageBase64 != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '⚙️ Ajuste de Posición y Tamaño de la Grilla sobre tu Afiche:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.brown),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Posición Vertical (Top): ${(_gridTopPercent * 100).toInt()}%'),
                              Slider(
                                value: _gridTopPercent,
                                min: 0.10,
                                max: 0.80,
                                onChanged: (v) => setState(() => _gridTopPercent = v),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Ancho de Grilla: ${(_gridWidthPercent * 100).toInt()}%'),
                              Slider(
                                value: _gridWidthPercent,
                                min: 0.50,
                                max: 0.98,
                                onChanged: (v) => setState(() => _gridWidthPercent = v),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Tamaño Círculo Rojo: ${_dotScale.toStringAsFixed(1)}x'),
                              Slider(
                                value: _dotScale,
                                min: 0.6,
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

            const SizedBox(height: 12),

            // CANVAS / POSTER DISPLAY
            Expanded(
              child: Consumer<TicketViewModel>(
                builder: (context, ticketVM, _) {
                  final tickets = ticketVM.tickets;

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: SingleChildScrollView(
                        child: _bgImageBase64 != null
                            ? _buildCustomTemplatePoster(context, tickets)
                            : _buildDefaultLuxuryPoster(context, tickets, currency),
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
    ImageProvider imgProvider;
    if (_bgImageBase64!.startsWith('data:image')) {
      imgProvider = MemoryImage(base64Decode(_bgImageBase64!.split(',').last));
    } else {
      imgProvider = NetworkImage(_bgImageBase64!);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        double posterWidth = 600;
        double posterHeight = 900;

        return Container(
          width: posterWidth,
          height: posterHeight,
          margin: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 12)],
            image: DecorationImage(
              image: imgProvider,
              fit: BoxFit.cover,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: posterHeight * _gridTopPercent,
                left: posterWidth * ((1.0 - _gridWidthPercent) / 2),
                width: posterWidth * _gridWidthPercent,
                child: _build10x10NumbersGrid(tickets, isDarkTheme: false),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Built-in luxury template poster (matching the user's reference image structure!)
  Widget _buildDefaultLuxuryPoster(BuildContext context, List<Ticket> tickets, NumberFormat currency) {
    final raffle = widget.raffle;

    return Container(
      width: 580,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.symmetric(vertical: 16),
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
                margin: const EdgeInsets.all(2.0),
                height: 34,
                decoration: BoxDecoration(
                  color: _fillCellBg ? _cellBgColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
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
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.red.shade600.withOpacity(0.92),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.4),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 14,
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
