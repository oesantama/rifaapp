import 'package:rifaapp/ui/core/utils/text_search.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/models/advisor.dart';
import 'package:rifaapp/data/models/raffle.dart';
import 'package:rifaapp/data/models/ticket.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/available_numbers_pdf.dart';
import 'package:rifaapp/ui/core/utils/excel_csv_helper.dart';
import 'package:rifaapp/ui/core/utils/file_saver.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';
import 'package:rifaapp/ui/features/tickets/view_models/ticket_view_model.dart';
import 'package:rifaapp/ui/shared/widgets/searchable_picker.dart';

/// Modal dialog to preview and download available raffle numbers
/// as a high-definition image (PNG) or structured Excel (.xlsx) file,
/// filtered either generally (all raffle) or by assigned advisor.
///
/// Specially optimized for 2, 3, and 4 digits and multiple opportunities per ticket.
class AvailableNumbersDialog extends StatefulWidget {
  final Raffle raffle;
  final Advisor? initialAdvisor;

  const AvailableNumbersDialog({
    super.key,
    required this.raffle,
    this.initialAdvisor,
  });

  static Future<void> show(
    BuildContext context, {
    required Raffle raffle,
    Advisor? initialAdvisor,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AvailableNumbersDialog(
        raffle: raffle,
        initialAdvisor: initialAdvisor,
      ),
    );
  }

  @override
  State<AvailableNumbersDialog> createState() => _AvailableNumbersDialogState();
}

class _AvailableNumbersDialogState extends State<AvailableNumbersDialog> {
  final GlobalKey _exportBoundaryKey = GlobalKey();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  double _zoomScale = 1.0;

  Advisor? _selectedAdvisor;
  bool _isGeneral = true;
  bool _showFullBoard = false; // false = solo disponibles, true = tablero completo
  bool _darkTheme = true; // true = luxury dark, false = clean light
  bool _isExporting = false;
  bool _isExportingPdf = false;
  // Paginación de la vista (y de la imagen que se descarga): cuántas boletas por página y cuál se ve
  static const _pageSizes = [100, 200, 500, 1000];
  int _pageSize = 200;
  int _page = 0;
  String _searchFilter = '';
  int? _userSelectedColumns; // null = auto based on digits and opportunities

  @override
  void initState() {
    super.initState();
    if (widget.initialAdvisor != null) {
      _selectedAdvisor = widget.initialAdvisor;
      _isGeneral = false;
    }
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  /// Calculates the best column count based on opportunities per ticket, digits and count
  int _calculateAutoColumns({required int totalCount, required int maxOpportunities}) {
    if (maxOpportunities >= 4) {
      return 4; // Generous space for 4 numbers (e.g. 0002, 0102, 0202, 0302)
    } else if (maxOpportunities >= 2) {
      return 5; // Clean space for 2 numbers
    } else if (widget.raffle.digits >= 4) {
      return totalCount <= 30 ? 5 : 6;
    } else if (widget.raffle.digits == 3) {
      return totalCount <= 50 ? 6 : 8;
    }
    // 2-digit single opportunity
    return totalCount <= 50 ? 8 : 10;
  }

  /// Helper to filter tickets covered by an advisor or general pool
  static List<Ticket> filterTicketsByAdvisorScope({
    required List<Ticket> allRaffleTickets,
    required Advisor? advisor,
    required List<Advisor> allAdvisors,
    bool independent = true,
  }) {
    // Los números asignados por asesor solo existen en rifas independientes
    if (advisor == null || !independent) {
      return allRaffleTickets;
    }

    if (advisor.worksWithAssignedNumbers) {
      return allRaffleTickets.where((t) => advisor.coversTicket(t) || t.advisorId == advisor.id).toList();
    }

    // Pool general advisor: tickets not assigned to any fixed-range advisor
    final assignedAdvisors = allAdvisors.where((a) => a.id != advisor.id && a.worksWithAssignedNumbers).toList();
    if (assignedAdvisors.isEmpty) {
      return allRaffleTickets;
    }

    return allRaffleTickets.where((t) {
      if (t.advisorId == advisor.id) return true;
      final takenByOthers = assignedAdvisors.any((a) => a.coversTicket(t));
      return !takenByOthers;
    }).toList();
  }

  /// Filters tickets to only those covered by the selected scope
  List<Ticket> _filterByScope(List<Ticket> allTickets, List<Advisor> allAdvisors) {
    if (_isGeneral || _selectedAdvisor == null) {
      return allTickets;
    }
    return filterTicketsByAdvisorScope(
      allRaffleTickets: allTickets,
      advisor: _selectedAdvisor,
      allAdvisors: allAdvisors,
      independent: widget.raffle.isIndependentBook,
    );
  }

  /// Downloads the available numbers board as a high-resolution PNG image
  Future<void> _downloadImage() async {
    setState(() => _isExporting = true);
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      final boundary = _exportBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('No se pudo encontrar el lienzo para generar la imagen.');
      }

      // Safe pixel ratio calculation to guarantee WebGL / HTML5 canvas limits (max 10000px)
      final size = boundary.size;
      double targetRatio = 2.0;
      final maxDim = math.max(size.width, size.height);
      if (maxDim * targetRatio > 9500) {
        targetRatio = 9500 / maxDim;
      }
      if (targetRatio < 0.4) targetRatio = 0.4;

      final image = await boundary.toImage(pixelRatio: targetRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Error al codificar la imagen en formato PNG.');
      }

      final pngBytes = byteData.buffer.asUint8List();

      await saveAndDownloadBytes(
        'numeros_disponibles_${widget.raffle.id}.png',
        pngBytes,
        mimeType: 'image/png',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppTheme.secondaryEmerald,
            content: Text(
              kIsWeb
                  ? '✓ Imagen de números disponibles descargada exitosamente en Alta Resolución.'
                  : '✓ Imagen lista: elija dónde guardarla o compartirla.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.dangerRose,
            content: Text('Error al descargar la imagen: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  /// PDF con TODAS las boletas del filtro actual (no solo la página visible), en bloques de 100 números.
  Future<void> _downloadPdf({required List<Ticket> scopedTickets, required List<Ticket> availableTickets}) async {
    setState(() => _isExportingPdf = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(duration: Duration(seconds: 3), content: Text('Generando el PDF con todas las boletas, un momento...')));
    try {
      await Future.delayed(const Duration(milliseconds: 150)); // deja pintar el aviso antes del trabajo pesado
      final isAdv = !_isGeneral && _selectedAdvisor != null;
      await AvailableNumbersPdf.download(
        raffle: widget.raffle,
        tickets: _showFullBoard ? scopedTickets : availableTickets,
        fullBoard: _showFullBoard,
        scopeTitle: isAdv ? 'ASESOR ASIGNADO: ${_selectedAdvisor!.name.toUpperCase()}' : 'DISPONIBILIDAD GENERAL',
        scopeSub: isAdv
            ? (_selectedAdvisor!.phone.isNotEmpty ? 'Telefono: ${_selectedAdvisor!.phone}' : '')
            : 'Toda la rifa  |  Boletas libres para reserva y venta inmediata',
        contactLine: isAdv && _selectedAdvisor!.phone.isNotEmpty
            ? 'Elige tu numero de la suerte! Para apartar comunicate al: ${_selectedAdvisor!.phone}'
            : 'Elige tu numero de la suerte antes de que se agote!',
        totalScoped: scopedTickets.length,
        totalAvailable: scopedTickets.where((t) => t.status == 'DISPONIBLE').length,
      );
      if (mounted) {
        messenger.showSnackBar(const SnackBar(backgroundColor: AppTheme.secondaryEmerald, content: Text('✓ PDF descargado con todas las boletas.')));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(backgroundColor: AppTheme.dangerRose, content: Text('Error al generar el PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  /// Opens the configuration modal for Excel export (Matrix sheet like Image 3, advisor filtering, column count)
  void _openExcelExportModal({
    required BuildContext context,
    required List<Ticket> allRaffleTickets,
    required List<Advisor> advisors,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        String contentMode = 'ONLY_AVAILABLE'; // 'ONLY_AVAILABLE' or 'ALL_STATUS'
        int matrixCols = 20; // 20 as in Image 3
        int? countLimit; // null = all
        Advisor? targetAdvisor = _selectedAdvisor;
        bool filterBySpecificAdvisor = !_isGeneral && _selectedAdvisor != null;
        bool includeMatrix = true;
        bool includeDetail = true;

        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            final Advisor? currentAdvisor = filterBySpecificAdvisor ? targetAdvisor : null;
            final scopedForExport = filterTicketsByAdvisorScope(
              allRaffleTickets: allRaffleTickets,
              advisor: currentAdvisor,
              allAdvisors: advisors,
              independent: widget.raffle.isIndependentBook,
            );
            final availableForExport = scopedForExport.where((t) => t.status == 'DISPONIBLE').toList();
            final activeTotal = contentMode == 'ALL_STATUS' ? scopedForExport.length : availableForExport.length;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: 580,
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.secondaryEmerald.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.table_chart_rounded, color: AppTheme.secondaryEmerald, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Descargar Excel (numeros_disponibles.xlsx)',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                Text(
                                  'Configura la sábana (como Imagen 3) y el alcance de los números',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const Divider(height: 24),

                      // Section 1: ¿Qué números incluir?
                      const Text(
                        '1. ¿Qué números incluir en el reporte?',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text('🟢 Solo Disponibles (${availableForExport.length})'),
                            selected: contentMode == 'ONLY_AVAILABLE',
                            selectedColor: AppTheme.secondaryEmerald.withValues(alpha: 0.2),
                            onSelected: (val) {
                              if (val) setModalState(() => contentMode = 'ONLY_AVAILABLE');
                            },
                          ),
                          ChoiceChip(
                            label: Text('🟡 Todos con Estado (Matriz Imagen 3: ${scopedForExport.length})'),
                            selected: contentMode == 'ALL_STATUS',
                            selectedColor: Colors.amber.shade200,
                            onSelected: (val) {
                              if (val) setModalState(() => contentMode = 'ALL_STATUS');
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Section 2: Filtro de Asesor
                      const Text(
                        '2. Alcance por Asesor',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('🌐 Toda la Rifa (General)'),
                            selected: !filterBySpecificAdvisor,
                            selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
                            onSelected: (val) {
                              if (val) {
                                setModalState(() {
                                  filterBySpecificAdvisor = false;
                                  targetAdvisor = null;
                                });
                              }
                            },
                          ),
                          if (advisors.isNotEmpty)
                            ChoiceChip(
                              label: Text(targetAdvisor != null ? '👤 ${targetAdvisor!.name}' : '👤 Elegir Asesor'),
                              selected: filterBySpecificAdvisor,
                              selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
                              onSelected: (val) {
                                if (val) {
                                  setModalState(() {
                                    filterBySpecificAdvisor = true;
                                    targetAdvisor ??= advisors.first;
                                  });
                                }
                              },
                            ),
                        ],
                      ),
                      if (filterBySpecificAdvisor && advisors.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () async {
                            final chosen = await showSearchablePicker<Advisor>(
                              context: context,
                              title: 'Seleccionar Asesor',
                              searchHint: 'Buscar por nombre o cédula...',
                              items: advisors,
                              labelBuilder: (a) => '${a.name} (${a.code})',
                              selectedValue: targetAdvisor,
                            );
                            if (chosen != null) {
                              setModalState(() => targetAdvisor = chosen);
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              suffixIcon: const Icon(Icons.arrow_drop_down),
                            ),
                            child: Text(
                              targetAdvisor?.name ?? 'Seleccionar Asesor',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Section 3: Columnas de la Sábana Matriz (como Imagen 3)
                      const Text(
                        '3. Columnas en la Sábana Matriz (Estilo Imagen 3)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [10, 15, 20, 25].map((cols) {
                          return ChoiceChip(
                            label: Text(cols == 20 ? '$cols columnas (Recomendado)' : '$cols columnas'),
                            selected: matrixCols == cols,
                            selectedColor: AppTheme.accentAmber.withValues(alpha: 0.3),
                            onSelected: (val) {
                              if (val) setModalState(() => matrixCols = cols);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Section 4: Cantidad de números a mostrar / límite
                      const Text(
                        '4. Cantidad de boletas a incluir',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text('Todas ($activeTotal)'),
                            selected: countLimit == null,
                            selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
                            onSelected: (val) {
                              if (val) setModalState(() => countLimit = null);
                            },
                          ),
                          ...[100, 500, 1000].map((limit) {
                            return ChoiceChip(
                              label: Text('Primeras $limit'),
                              selected: countLimit == limit,
                              selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
                              onSelected: (val) {
                                if (val) setModalState(() => countLimit = limit);
                              },
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Section 5: Hojas en el Excel
                      const Text(
                        '5. Hojas a incluir en el archivo Excel',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      CheckboxListTile(
                        dense: true,
                        title: const Text('Hoja 1: Sábana Matriz (Cuadrícula con colores como Imagen 3)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Cuadrícula continua con números y fondos amarillo/blanco/rojo', style: TextStyle(fontSize: 11)),
                        value: includeMatrix,
                        onChanged: (val) => setModalState(() => includeMatrix = val ?? true),
                      ),
                      CheckboxListTile(
                        dense: true,
                        title: const Text('Hoja 2: Listado Detallado (Tabla por Boleta)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Tabla con número real de boleta, oportunidades 1..N, precio y asesor', style: TextStyle(fontSize: 11)),
                        value: includeDetail,
                        onChanged: (val) => setModalState(() => includeDetail = val ?? true),
                      ),
                      const SizedBox(height: 20),

                      // Download Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.secondaryEmerald,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.file_download, size: 18),
                            label: const Text('Descargar numeros_disponibles.xlsx', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Navigator.of(ctx).pop();

                              ExcelCsvHelper.exportAvailableNumbersToExcel(
                                availableTickets: availableForExport,
                                raffleTitle: widget.raffle.title,
                                allTickets: scopedForExport,
                                advisorName: currentAdvisor?.name,
                                ticketPrice: widget.raffle.ticketPrice,
                                drawDate: widget.raffle.mainDrawDate,
                                lotteryName: widget.raffle.mainLottery,
                                matrixColumns: matrixCols,
                                contentMode: contentMode,
                                maxNumbersCount: countLimit,
                                includeMatrixSheet: includeMatrix,
                                includeDetailedList: includeDetail,
                              );

                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: AppTheme.secondaryEmerald,
                                  content: Text('✓ Descargando numeros_disponibles.xlsx con la sábana matriz configurada...'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Copies available numbers formatted as a WhatsApp-ready text message
  void _copyNumbersText(List<Ticket> availableTickets) {
    if (availableTickets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay números disponibles para copiar.')),
      );
      return;
    }

    final currency = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
    final sorted = [...availableTickets]..sort((a, b) => a.sortNumber.compareTo(b.sortNumber));
    final numbersList = sorted.map((t) => t.displayNumber).join('\n• ');

    final advisorHeader = _isGeneral || _selectedAdvisor == null
        ? '🌐 *Disponibilidad General*'
        : '👤 *Asesor:* ${_selectedAdvisor!.name}${_selectedAdvisor!.phone.isNotEmpty ? " • 📱 ${_selectedAdvisor!.phone}" : ""}';

    final text = '''
🎟️ *NÚMEROS DISPONIBLES - ${widget.raffle.title.toUpperCase()}*
$advisorHeader
📅 *Sorteo:* ${_dateOnly(widget.raffle.mainDrawDate)} con ${widget.raffle.mainLottery}
💰 *Valor Boleta:* ${_money(widget.raffle.ticketPrice)}
✅ *Total Disponibles:* ${availableTickets.length} boletas libres

*Boletas y Números disponibles:*
• $numbersList

✨ _¡Aparta el tuyo antes de que juegue!_
''';

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.primaryBlue,
        content: Text('✓ ${availableTickets.length} números copiados al portapapeles listos para WhatsApp.'),
      ),
    );
  }

  /// Si el número buscado ya no está disponible, se avisa: «ya fue vendido por otro asesor» (o «ya lo vendió usted»).
  /// A un asesor nunca se le muestran datos del comprador ni quién lo vendió.
  Widget _soldNumberNotice(List<Ticket> raffleTickets, AuthViewModel authVM) {
    final raw = _searchFilter.trim();
    if (raw.isEmpty) return const SizedBox.shrink();
    final q = foldText(raw);
    final me = authVM.isAsesor ? authVM.activeAdvisor : null;
    // El aviso es solo para el asesor: el administrador y quien ve todas las boletas no lo necesitan
    if (me == null || me.canManageAllTickets) return const SizedBox.shrink();
    final sold = raffleTickets
        .where((t) => t.status != 'DISPONIBLE' && t.numbers.any((n) => n == q || (q.length >= 3 && n.contains(q))))
        .take(4)
        .toList();
    if (sold.isEmpty) return const SizedBox.shrink();
    bool mine(Ticket t) =>
        me != null &&
        (t.advisorId == me.id ||
            t.advisorName.trim().toLowerCase() == me.name.trim().toLowerCase() ||
            (me.code.isNotEmpty && t.advisorName.contains(me.code)));
    String stateOf(Ticket t) => AppTheme.getStatusLabel(t.status).toLowerCase();
    String line(Ticket t) {
      final number = t.numbers.firstWhere((n) => n == q || n.contains(q), orElse: () => q);
      return mine(t)
          ? 'El N° $number ya lo vendió usted (${stateOf(t)}).'
          : 'El N° $number ya fue vendido por otro asesor: no está disponible.';
    }

    return Container(
      width: double.infinity,
      color: Colors.orange.withValues(alpha: 0.14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 18, color: Colors.orange.shade800),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final t in sold)
              Text(line(t), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.orange.shade900)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ticketVM = context.watch<TicketViewModel>();
    final advVM = context.watch<AdvisorViewModel>();
    final authVM = context.watch<AuthViewModel>();

    // Restrict advisor if logged in as advisor
    if (authVM.isAsesor && authVM.activeAdvisor != null && _isGeneral) {
      _selectedAdvisor = authVM.activeAdvisor;
      _isGeneral = false;
    }

    // Tickets belonging to this raffle
    final raffleTickets = ticketVM.tickets.where((t) => t.raffleId == widget.raffle.id).toList();

    // Tickets in the selected scope
    final scopedTickets = _filterByScope(raffleTickets, advVM.advisors);

    // Available tickets in the selected scope
    List<Ticket> availableTickets = scopedTickets.where((t) => t.status == 'DISPONIBLE').toList();

    // Apply quick search filter if any
    if (_searchFilter.trim().isNotEmpty) {
      final query = foldText(_searchFilter);
      availableTickets = availableTickets.where((t) {
        return t.numbers.any((n) => n.contains(query));
      }).toList();
    }

    final totalScoped = scopedTickets.length;
    final totalAvailable = availableTickets.length;
    final percentAvailable = totalScoped > 0 ? (totalAvailable / totalScoped * 100).toStringAsFixed(1) : '0';

    final maxOpps = scopedTickets.fold<int>(1, (max, t) => t.numbers.length > max ? t.numbers.length : max);
    final autoColumns = _calculateAutoColumns(
      totalCount: _showFullBoard ? totalScoped : totalAvailable,
      maxOpportunities: maxOpps,
    );
    final activeColumns = _userSelectedColumns ?? autoColumns;

    final isNarrow = MediaQuery.of(context).size.width < 900;
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 10 : 24,
        vertical: isNarrow ? 12 : 24,
      ),
      backgroundColor: Colors.transparent,
      child: Container(
        width: 1300,
        height: screenHeight * 0.94,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // TOP TOOLBAR & CONTROLS
            _buildDialogHeader(
              context: context,
              authVM: authVM,
              advVM: advVM,
              totalAvailable: totalAvailable,
              totalScoped: totalScoped,
              percentAvailable: percentAvailable,
              scopedTickets: scopedTickets,
              availableTickets: availableTickets,
              allRaffleTickets: raffleTickets,
              autoColumns: autoColumns,
              activeColumns: activeColumns,
              maxOpps: maxOpps,
            ),
            const Divider(height: 1),
            _soldNumberNotice(raffleTickets, authVM),

            // MAIN PREVIEW & CANVAS AREA (SMOOTH MOUSE/TOUCH SCROLLING + ZOOM)
            Expanded(
              child: Stack(
                children: [
                  Container(
                    color: _darkTheme ? const Color(0xFF0A0F1D) : const Color(0xFFF1F5F9),
                    child: Scrollbar(
                      controller: _verticalScrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _verticalScrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 70),
                        child: Center(
                          child: SingleChildScrollView(
                            controller: _horizontalScrollController,
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Transform.scale(
                              scale: _zoomScale,
                              alignment: Alignment.topCenter,
                              child: RepaintBoundary(
                                key: _exportBoundaryKey,
                                child: _buildPosterCanvas(
                                  scopedTickets: scopedTickets,
                                  availableTickets: availableTickets,
                                  columns: activeColumns,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Páginas: barra flotante abajo, para no gastar alto de pantalla arriba
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Center(child: _buildPaginationBar(total: _showFullBoard ? scopedTickets.length : availableTickets.length)),
                  ),

                  // Floating Zoom Controls
                  Positioned(
                    right: 18,
                    bottom: 18,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove, size: 20),
                            tooltip: 'Alejar',
                            onPressed: () {
                              setState(() {
                                _zoomScale = (_zoomScale - 0.12).clamp(0.40, 2.0);
                              });
                            },
                          ),
                          InkWell(
                            onTap: () => setState(() => _zoomScale = 1.0),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Text(
                                '${(_zoomScale * 100).toInt()}%',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 18),
                            tooltip: 'Restablecer Zoom (100%)',
                            onPressed: () => setState(() => _zoomScale = 1.0),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add, size: 20),
                            tooltip: 'Acercar',
                            onPressed: () {
                              setState(() {
                                _zoomScale = (_zoomScale + 0.12).clamp(0.40, 2.0);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (_isExporting)
                    Container(
                      color: Colors.black54,
                      child: const Center(
                        child: Card(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(width: 18),
                                Text(
                                  'Generando imagen de alta resolución...',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Top dialog controls: filter by advisor, view mode, columns, theme, download buttons
  Widget _buildDialogHeader({
    required BuildContext context,
    required AuthViewModel authVM,
    required AdvisorViewModel advVM,
    required int totalAvailable,
    required int totalScoped,
    required String percentAvailable,
    required List<Ticket> scopedTickets,
    required List<Ticket> availableTickets,
    required List<Ticket> allRaffleTickets,
    required int autoColumns,
    required int activeColumns,
    required int maxOpps,
  }) {
    final isMobile = MediaQuery.of(context).size.width < 750;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Title & Scope selector
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryEmerald.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.grid_on_rounded, color: AppTheme.secondaryEmerald, size: 22),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Números Disponibles',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${widget.raffle.digits} cifras${maxOpps > 1 ? " • $maxOpps oportunidades" : ""}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '$totalAvailable disponibles de $totalScoped ($percentAvailable%)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(width: 14),

              // Advisor filter dropdown (if admin)
              if (authVM.isAdmin) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _isGeneral ? 'GENERAL' : (_selectedAdvisor?.id ?? 'GENERAL'),
                      isDense: true,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'GENERAL',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.public, size: 16, color: AppTheme.primaryBlue),
                              SizedBox(width: 6),
                              Text('🌐 Toda la Rifa (General)'),
                            ],
                          ),
                        ),
                        ...advVM.advisors.map(
                          (adv) => DropdownMenuItem(
                            value: adv.id,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person, size: 16, color: Colors.orange),
                                SizedBox(width: 6),
                                Text('👤 ${adv.name}${adv.worksWithAssignedNumbers ? " (${adv.assignedTicketRanges.join(',')})" : ""}'),
                              ],
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val == null) return;
                        setState(() {
                          if (val == 'GENERAL') {
                            _isGeneral = true;
                            _selectedAdvisor = null;
                          } else {
                            _isGeneral = false;
                            _selectedAdvisor = advVM.advisors.firstWhere((a) => a.id == val);
                          }
                        });
                      },
                    ),
                  ),
                ),
              ] else if (authVM.isAsesor && authVM.activeAdvisor != null) ...[
                Chip(
                  avatar: const Icon(Icons.person, size: 16, color: Colors.orange),
                  label: Text('Asesor: ${authVM.activeAdvisor!.name}', style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),

          // Toggles and Action Buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Quick search field
              SizedBox(
                width: 130,
                height: 36,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar N°...',
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (val) => setState(() {
                    _searchFilter = val;
                    _page = 0;
                  }),
                ),
              ),

              // Columns selector
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    value: _userSelectedColumns,
                    hint: Text('$activeColumns cols', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    isDense: true,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Auto ($autoColumns cols)'),
                      ),
                      const DropdownMenuItem<int?>(value: 3, child: Text('3 columnas (Extra Grande)')),
                      const DropdownMenuItem<int?>(value: 4, child: Text('4 columnas (Grande)')),
                      const DropdownMenuItem<int?>(value: 5, child: Text('5 columnas (Mediano)')),
                      const DropdownMenuItem<int?>(value: 6, child: Text('6 columnas')),
                      const DropdownMenuItem<int?>(value: 8, child: Text('8 columnas')),
                      const DropdownMenuItem<int?>(value: 10, child: Text('10 columnas (Compacto)')),
                    ],
                    onChanged: (val) => setState(() => _userSelectedColumns = val),
                  ),
                ),
              ),

              // Display mode toggle: Solo Disponibles vs Tablero Completo
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Disponibles', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.filter_alt_outlined, size: 14),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Todo el tablero', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.grid_view_rounded, size: 14),
                  ),
                ],
                selected: {_showFullBoard},
                onSelectionChanged: (set) => setState(() {
                  _showFullBoard = set.first;
                  _page = 0;
                }),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),

              // Theme toggle: Dark / Light
              IconButton.filledTonal(
                tooltip: _darkTheme ? 'Cambiar a Tema Claro (Imprimible)' : 'Cambiar a Tema Oscuro (Luxury)',
                icon: Icon(_darkTheme ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 18),
                onPressed: () => setState(() => _darkTheme = !_darkTheme),
              ),

              // Copy WhatsApp Text
              IconButton.outlined(
                tooltip: 'Copiar texto para WhatsApp',
                onPressed: () => _copyNumbersText(availableTickets),
                icon: const Icon(Icons.content_copy_rounded, size: 18),
                style: IconButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: const Color(0xFF128C7E),
                  side: const BorderSide(color: Color(0xFF128C7E)),
                ),
              ),

              // Download Excel
              IconButton.filled(
                tooltip: 'Descargar Excel (.xlsx)',
                onPressed: () => _openExcelExportModal(
                  context: context,
                  allRaffleTickets: allRaffleTickets,
                  advisors: advVM.advisors,
                ),
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
              ),

              // Download PDF (todas las boletas, en bloques)
              IconButton.filled(
                tooltip: 'Descargar PDF con todas las boletas',
                onPressed: _isExportingPdf ? null : () => _downloadPdf(scopedTickets: scopedTickets, availableTickets: availableTickets),
                icon: _isExportingPdf
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
              ),

              // Download Image PNG
              IconButton.filled(
                tooltip: 'Descargar imagen de esta página (PNG)',
                onPressed: _isExporting ? null : _downloadImage,
                icon: const Icon(Icons.image_outlined, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
              ),

              // Close dialog
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Solo la fecha (dd/MM/yyyy), sin hora: "2027-03-06T12:00:00.000" -> "06/03/2027"
  static String _dateOnly(String raw) {
    final d = DateTime.tryParse(raw);
    if (d != null) return DateFormat('dd/MM/yyyy').format(d);
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  /// $150.000 (con el signo al inicio)
  static String _money(num v) => '\$${NumberFormat('#,##0', 'es_CO').format(v)}';

  int _pagesFor(int total) => total <= 0 ? 1 : (total / _pageSize).ceil();

  /// Barra de páginas: cuántas boletas por página y navegación. La imagen que se descarga es la página visible;
  /// el PDF trae todas.
  Widget _buildPaginationBar({required int total}) {
    final pages = _pagesFor(total);
    final page = _page.clamp(0, pages - 1);
    final from = total == 0 ? 0 : page * _pageSize + 1;
    final to = math.min(total, (page + 1) * _pageSize);
    void go(int p) => setState(() {
          _page = p.clamp(0, pages - 1);
          if (_verticalScrollController.hasClients) _verticalScrollController.jumpTo(0);
        });
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Primera página',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.first_page, size: 20),
            onPressed: page > 0 ? () => go(0) : null,
          ),
          IconButton(
            tooltip: 'Página anterior',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left, size: 22),
            onPressed: page > 0 ? () => go(page - 1) : null,
          ),
          Flexible(
            child: Text(
              '${page + 1} / $pages  •  $from-$to de $total',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Página siguiente',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right, size: 22),
            onPressed: page < pages - 1 ? () => go(page + 1) : null,
          ),
          IconButton(
            tooltip: 'Última página',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.last_page, size: 20),
            onPressed: page < pages - 1 ? () => go(pages - 1) : null,
          ),
          const SizedBox(height: 22, child: VerticalDivider(width: 10)),
          PopupMenuButton<int>(
            tooltip: 'Boletas por página',
            initialValue: _pageSize,
            onSelected: (n) => setState(() {
              _pageSize = n;
              _page = 0;
            }),
            itemBuilder: (_) => [for (final n in _pageSizes) PopupMenuItem(value: n, child: Text('$n por página'))],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('$_pageSize', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const Icon(Icons.arrow_drop_down, size: 18),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// High-resolution visual poster canvas that gets exported as PNG
  Widget _buildPosterCanvas({
    required List<Ticket> scopedTickets,
    required List<Ticket> availableTickets,
    required int columns,
  }) {
    final currency = NumberFormat.currency(locale: 'es_CO', symbol: r'$', decimalDigits: 0);
    final sortedAvailable = [...availableTickets]..sort((a, b) => a.sortNumber.compareTo(b.sortNumber));
    final sortedScoped = [...scopedTickets]..sort((a, b) => a.sortNumber.compareTo(b.sortNumber));

    final totalAvailable = availableTickets.length;
    final totalScoped = scopedTickets.length;

    final bgColor1 = _darkTheme ? const Color(0xFF0D1B2A) : const Color(0xFFFFFFFF);
    final bgColor2 = _darkTheme ? const Color(0xFF1B263B) : const Color(0xFFF8FAFC);
    final textColor = _darkTheme ? Colors.white : const Color(0xFF0F172A);
    final textMuted = _darkTheme ? Colors.grey.shade400 : Colors.grey.shade600;
    final borderColor = _darkTheme ? Colors.white.withValues(alpha: 0.12) : Colors.grey.shade300;

    // Scope title & badge
    final isAdv = !_isGeneral && _selectedAdvisor != null;
    final scopeTitle = isAdv ? 'ASESOR ASIGNADO: ${_selectedAdvisor!.name.toUpperCase()}' : 'DISPONIBILIDAD GENERAL';
    final scopeSub = isAdv
        ? (_selectedAdvisor!.phone.isNotEmpty ? 'Teléfono: ${_selectedAdvisor!.phone}' : '')
        : 'Toda la rifa • Boletas libres para reserva y venta inmediata';

    // Canvas width
    const canvasWidth = 1140.0;

    final allTickets = _showFullBoard ? sortedScoped : sortedAvailable;
    final pages = _pagesFor(allTickets.length);
    final page = _page.clamp(0, pages - 1);
    final hasTruncated = pages > 1;
    final ticketsToRender = allTickets.skip(page * _pageSize).take(_pageSize).toList();

    return Container(
      width: canvasWidth,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bgColor1, bgColor2],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. BRAND & RAFFLE HEADER
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.accentAmber,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.confirmation_number, color: Colors.black, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'RIFA MASTER',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryEmerald.withValues(alpha: 0.18),
                            border: Border.all(color: AppTheme.secondaryEmerald, width: 1.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            scopeTitle,
                            style: const TextStyle(
                              color: AppTheme.secondaryEmerald,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.raffle.title,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 26,
                        height: 1.15,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      scopeSub,
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Decorative Counter Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryEmerald.withValues(alpha: _darkTheme ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.secondaryEmerald, width: 1.5),
                ),
                child: Column(
                  children: [
                    Text(
                      '$totalAvailable',
                      style: const TextStyle(
                        color: AppTheme.secondaryEmerald,
                        fontWeight: FontWeight.w900,
                        fontSize: 32,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'DISPONIBLES',
                      style: TextStyle(
                        color: _darkTheme ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          // 2. KEY METRICS BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: _darkTheme ? Colors.white.withValues(alpha: 0.05) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Wrap(
              spacing: 24,
              runSpacing: 10,
              alignment: WrapAlignment.spaceAround,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildMetricItem(
                  icon: Icons.calendar_month_rounded,
                  label: 'Sorteo',
                  value: _dateOnly(widget.raffle.mainDrawDate),
                  sub: widget.raffle.mainLottery,
                  textColor: textColor,
                  textMuted: textMuted,
                ),
                _buildMetricItem(
                  icon: Icons.attach_money_rounded,
                  label: 'Valor Boleta',
                  value: _money(widget.raffle.ticketPrice),
                  sub: 'Pago único',
                  textColor: textColor,
                  textMuted: textMuted,
                ),
                _buildMetricItem(
                  icon: Icons.analytics_outlined,
                  label: 'Disponibilidad',
                  value: '$totalAvailable de $totalScoped',
                  sub: '${(totalAvailable / (totalScoped > 0 ? totalScoped : 1) * 100).toStringAsFixed(0)}% libre',
                  textColor: textColor,
                  textMuted: textMuted,
                ),
                _buildMetricItem(
                  icon: Icons.pin_outlined,
                  label: 'Formato Rifa',
                  value: '${widget.raffle.digits} cifras',
                  sub: '${widget.raffle.opportunitiesPerTicket} oportunidades',
                  textColor: textColor,
                  textMuted: textMuted,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 3. NUMBERS GRID (Handles 2, 3, 4 digits and multiple opportunities)
          if (ticketsToRender.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: _darkTheme ? Colors.white.withValues(alpha: 0.03) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.sentiment_dissatisfied, size: 48, color: textMuted),
                    const SizedBox(height: 12),
                    Text(
                      'No hay números disponibles con el filtro actual.',
                      style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            )
          else
            _buildAdaptiveGrid(
              tickets: ticketsToRender,
              crossAxisCount: columns,
              textColor: textColor,
              textMuted: textMuted,
              borderColor: borderColor,
              isFullBoard: _showFullBoard,
            ),

          if (hasTruncated)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.accentAmber.withValues(alpha: _darkTheme ? 0.15 : 0.1),
                border: Border.all(color: AppTheme.accentAmber.withValues(alpha: 0.6), width: 1.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppTheme.accentAmber, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Página ${page + 1} de $pages: boletas ${page * _pageSize + 1} a ${math.min(allTickets.length, (page + 1) * _pageSize)} de ${allTickets.length}. Para tener todas en un solo archivo descargue el PDF o el Excel (.xlsx).',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 28),

          // 4. FOOTER
          Container(
            padding: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: AppTheme.accentAmber, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isAdv && _selectedAdvisor!.phone.isNotEmpty
                              ? '¡Elige tu número de la suerte! Para apartar comunícate al: ${_selectedAdvisor!.phone}'
                              : '¡Elige tu número de la suerte antes de que se agote! Consulta disponibilidad actualizada.',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  'Generado el ${DateFormat("dd/MM/yyyy HH:mm").format(DateTime.now())} • Rifa Master',
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required Color textColor,
    required Color textMuted,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.primaryBlue, size: 20),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(color: textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
            Text(value, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  /// Adaptive grid: formats single-number or multi-opportunity numbers cleanly
  Widget _buildAdaptiveGrid({
    required List<Ticket> tickets,
    required int crossAxisCount,
    required Color textColor,
    required Color textMuted,
    required Color borderColor,
    required bool isFullBoard,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 8.0;
        final totalSpacing = spacing * (crossAxisCount - 1);
        final itemWidth = (constraints.maxWidth - totalSpacing) / crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: tickets.map((t) {
            return _buildTicketCard(
              ticket: t,
              width: itemWidth,
              textColor: textColor,
              textMuted: textMuted,
              borderColor: borderColor,
              isFullBoard: isFullBoard,
            );
          }).toList(),
        );
      },
    );
  }

  /// Individual ticket card with clear visibility for 2, 3, 4 digits and multi-opportunities
  Widget _buildTicketCard({
    required Ticket ticket,
    required double width,
    required Color textColor,
    required Color textMuted,
    required Color borderColor,
    required bool isFullBoard,
  }) {
    final isAvailable = ticket.status == 'DISPONIBLE';
    final numbers = ticket.numbers.isNotEmpty
        ? ticket.numbers
        : [ticket.ticketNumber.toString().padLeft(widget.raffle.digits, '0')];
    final hasMultiple = numbers.length > 1;

    final cardBg = isAvailable
        ? (_darkTheme ? const Color(0xFF132238) : Colors.white)
        : (_darkTheme ? const Color(0xFF111827) : const Color(0xFFF1F5F9));

    final cardBorder = isAvailable
        ? (_darkTheme ? const Color(0xFF10B981) : const Color(0xFF059669))
        : (_darkTheme ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade300);

    final numColor = isAvailable
        ? (_darkTheme ? const Color(0xFF4ADE80) : const Color(0xFF047857))
        : (_darkTheme ? Colors.grey.shade600 : Colors.grey.shade400);

    // SIMPLE CARD: Single opportunity and not in full board
    if (!hasMultiple && !isFullBoard) {
      return Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cardBorder, width: 1.3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _darkTheme ? 0.2 : 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              numbers.first,
              style: TextStyle(
                color: numColor,
                fontSize: widget.raffle.digits >= 4 ? 15 : 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }

    // Con muchas columnas la tarjeta es angosta: sin textos ("2 Oportunidades", "LIBRE"), solo los números
    final compact = width < 118;

    // MULTI-OPPORTUNITY or FULL-BOARD CARD
    return Container(
      width: width,
      padding: compact ? const EdgeInsets.symmetric(horizontal: 4, vertical: 6) : const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder, width: isAvailable ? 1.5 : 1),
        boxShadow: [
          if (isAvailable)
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: _darkTheme ? 0.15 : 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Opportunities count or Boleta label + State badge
          if (!compact) Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                numbers.length > 1 ? '${numbers.length} Oportunidades' : 'Boleta Disponible',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: isAvailable ? textMuted : Colors.grey.shade500,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isAvailable
                      ? AppTheme.secondaryEmerald.withValues(alpha: 0.18)
                      : Colors.grey.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isAvailable ? 'LIBRE' : 'OCUPADA',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    color: isAvailable ? AppTheme.secondaryEmerald : textMuted,
                  ),
                ),
              ),
            ],
          ),
          if (!compact) const SizedBox(height: 6),

          // Numbers list/grid: each opportunity has its own badge with large font
          Wrap(
            spacing: compact ? 3 : 5,
            runSpacing: compact ? 3 : 4,
            alignment: WrapAlignment.center,
            children: numbers.map((n) {
              return Container(
                padding: compact ? const EdgeInsets.symmetric(horizontal: 4, vertical: 3) : const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isAvailable
                      ? (_darkTheme ? const Color(0xFF064E3B).withValues(alpha: 0.5) : const Color(0xFFDCFCE7))
                      : (_darkTheme ? Colors.black26 : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: isAvailable
                        ? AppTheme.secondaryEmerald.withValues(alpha: 0.45)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  n,
                  style: TextStyle(
                    color: numColor,
                    fontSize: compact ? (widget.raffle.digits >= 4 ? 11 : 12.5) : (widget.raffle.digits >= 4 ? 13.5 : 15),
                    fontWeight: FontWeight.w900,
                    letterSpacing: compact ? 0.2 : 0.6,
                    fontFamily: 'monospace',
                    decoration: isAvailable ? TextDecoration.none : TextDecoration.lineThrough,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
