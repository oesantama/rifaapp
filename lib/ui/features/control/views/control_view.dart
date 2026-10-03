import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/excel_csv_helper.dart';
import 'package:rifaapp/ui/core/widgets/current_raffle_banner.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/control/views/message_templates_tab.dart';

/// Admin control panel: history of voided sales / payments, the company's terms & conditions and
/// its WhatsApp messages.
class ControlView extends StatelessWidget {
  const ControlView({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const CurrentRaffleBanner(),
          Material(
            color: Theme.of(context).cardColor,
            child: TabBar(
              tabs: [
                Tab(
                    icon: const Icon(Icons.history, size: 18),
                    text: isMobile ? 'Anulaciones' : 'Historial de anulaciones',
                    iconMargin: EdgeInsets.zero),
                Tab(
                    icon: const Icon(Icons.gavel, size: 18),
                    text: isMobile ? 'Términos' : 'Términos y condiciones',
                    iconMargin: EdgeInsets.zero),
                Tab(
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    text: isMobile ? 'Mensajes' : 'Mensajes WhatsApp',
                    iconMargin: EdgeInsets.zero),
              ],
            ),
          ),
          const Expanded(child: TabBarView(children: [_VoidHistoryTab(), _TermsTab(), MessageTemplatesTab()])),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History of voided sales and payments
// ---------------------------------------------------------------------------
class _VoidHistoryTab extends StatefulWidget {
  const _VoidHistoryTab();

  @override
  State<_VoidHistoryTab> createState() => _VoidHistoryTabState();
}

class _VoidHistoryTabState extends State<_VoidHistoryTab> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;
  String _type = 'TODOS'; // TODOS, VENTA, ABONO
  bool _onlyCurrentRaffle = true;
  String _search = '';
  String? _loadedRaffleId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raffleId = _onlyCurrentRaffle ? context.read<RaffleViewModel>().selectedRaffle?.id : null;
      _loadedRaffleId = context.read<RaffleViewModel>().selectedRaffle?.id;
      final entries = await RaffleRepository().fetchVoidHistory(raffleId: raffleId);
      if (mounted) setState(() => _entries = entries);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    return _entries.where((e) {
      if (_type != 'TODOS' && e['type'] != _type) return false;
      if (q.isEmpty) return true;
      final text = [
        e['buyerName'],
        e['buyerPhone'],
        e['buyerDocument'],
        e['advisorName'],
        e['reason'],
        e['by'],
        ((e['numbers'] as List?) ?? []).join(' ')
      ].join(' ').toLowerCase();
      return text.contains(q);
    }).toList();
  }

  String _fmt(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    return d == null ? '—' : DateFormat('dd/MM/yyyy hh:mm a').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    // Reload when the user switches raffle in the header
    final currentRaffleId = context.watch<RaffleViewModel>().selectedRaffle?.id;
    if (_onlyCurrentRaffle && !_loading && currentRaffleId != _loadedRaffleId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final items = _filtered;
    final ventas = _entries.where((e) => e['type'] == 'VENTA').length;
    final abonos = _entries.length - ventas;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(isMobile ? 12 : 20),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                  label: Text('Todo (${_entries.length})'), selected: _type == 'TODOS', onSelected: (_) => setState(() => _type = 'TODOS')),
              ChoiceChip(
                  label: Text('Ventas anuladas ($ventas)'), selected: _type == 'VENTA', onSelected: (_) => setState(() => _type = 'VENTA')),
              ChoiceChip(
                  label: Text('Abonos anulados ($abonos)'), selected: _type == 'ABONO', onSelected: (_) => setState(() => _type = 'ABONO')),
              FilterChip(
                label: Text(_onlyCurrentRaffle ? 'Solo rifa actual' : 'Todas las rifas'),
                selected: _onlyCurrentRaffle,
                onSelected: (v) {
                  setState(() => _onlyCurrentRaffle = v);
                  _load();
                },
              ),
              OutlinedButton.icon(
                onPressed: items.isEmpty ? null : () => ExcelCsvHelper.exportVoidHistoryToExcel(items),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Excel'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar por número, comprador, asesor o motivo',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 12),
          if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (_error != null) Text(_error!, style: const TextStyle(color: AppTheme.dangerRose)),
          if (!_loading && _error == null && items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.verified_outlined, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text('No hay anulaciones registradas${_onlyCurrentRaffle ? ' en esta rifa' : ''}.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          for (final e in items)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (e['type'] == 'VENTA' ? AppTheme.dangerRose : AppTheme.accentAmber).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            e['type'] == 'VENTA' ? 'VENTA ANULADA' : 'ABONO ANULADO',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: e['type'] == 'VENTA' ? AppTheme.dangerRose : Colors.orange.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'N° ${((e['numbers'] as List?) ?? []).join(' - ')}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(currency.format((e['amount'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Motivo: ${e['reason'] ?? ''}', style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if ('${e['buyerName'] ?? ''}'.isNotEmpty)
                          'Comprador: ${e['buyerName']}${'${e['buyerPhone'] ?? ''}'.isNotEmpty ? ' (${e['buyerPhone']})' : ''}'
                              '${'${e['buyerDocument'] ?? ''}'.isNotEmpty ? ' • CC ${e['buyerDocument']}' : ''}',
                        if ('${e['advisorName'] ?? ''}'.isNotEmpty) 'Asesor: ${e['advisorName']}',
                        if ('${e['saleChannel'] ?? ''}'.isNotEmpty) 'Medio: ${e['saleChannel']}',
                      ].join(' • '),
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Anuló ${e['by'] ?? '—'} el ${_fmt(e['date'])}${_onlyCurrentRaffle ? '' : ' • ${e['raffleTitle'] ?? ''}'}',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Terms and conditions editor (template with placeholders filled per raffle)
// ---------------------------------------------------------------------------
class _TermsTab extends StatefulWidget {
  const _TermsTab();

  @override
  State<_TermsTab> createState() => _TermsTabState();
}

class _TermsTabState extends State<_TermsTab> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _placeholders = [];
  String _defaultTemplate = '';
  bool _isDefault = true;
  String? _preview;
  String? _previewRaffle;
  bool _loading = true;
  bool _saving = false;

  String? get _raffleId => context.read<RaffleViewModel>().selectedRaffle?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await RaffleRepository().fetchTerms(raffleId: _raffleId);
      if (!mounted) return;
      setState(() {
        _controller.text = data['template'] ?? '';
        _defaultTemplate = data['defaultTemplate'] ?? '';
        _isDefault = data['isDefault'] == true;
        _placeholders = ((data['placeholders'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p)).toList();
        _preview = data['preview'];
        _previewRaffle = data['previewRaffle'];
      });
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: error ? AppTheme.dangerRose : AppTheme.secondaryEmerald, content: Text(text)),
    );
  }

  /// Inserts {placeholder} where the cursor is.
  void _insert(String key) {
    final text = _controller.text;
    final sel = _controller.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final token = '{$key}';
    _controller.value = TextEditingValue(
      text: text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
  }

  Future<void> _refreshPreview() async {
    try {
      final preview = await RaffleRepository().previewTerms(_controller.text, raffleId: _raffleId);
      if (mounted) setState(() => _preview = preview);
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  Future<void> _save({bool restoreDefault = false}) async {
    setState(() => _saving = true);
    try {
      await RaffleRepository().saveTerms(restoreDefault ? '' : _controller.text);
      if (restoreDefault) _controller.text = _defaultTemplate;
      _isDefault = restoreDefault;
      await _refreshPreview();
      _snack(restoreDefault ? 'Se restauró la plantilla genérica.' : 'Términos y condiciones guardados.');
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (_loading) return const Center(child: CircularProgressIndicator());

    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Estos términos aparecen en la página de verificación (QR) de cada boleta de su empresa. '
          'Los campos entre llaves se reemplazan automáticamente con los datos de cada rifa.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey[700], height: 1.4),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in _placeholders)
              Tooltip(
                message: p['description'] ?? '',
                child: ActionChip(
                  label: Text('{${p['key']}}', style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
                  onPressed: () => _insert(p['key']),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          minLines: 10,
          maxLines: 22,
          maxLength: 8000,
          decoration: InputDecoration(
            labelText: _isDefault ? 'Términos (plantilla genérica)' : 'Términos de su empresa',
            alignLabelWithHint: true,
          ),
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: _saving ? null : () => _save(),
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: const Text('Guardar'),
            ),
            OutlinedButton.icon(onPressed: _refreshPreview, icon: const Icon(Icons.visibility_outlined), label: const Text('Vista previa')),
            TextButton.icon(
              onPressed: _saving ? null : () => _save(restoreDefault: true),
              icon: const Icon(Icons.restore),
              label: const Text('Restaurar plantilla genérica'),
            ),
          ],
        ),
      ],
    );

    final preview = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vista previa${_previewRaffle != null ? ' — $_previewRaffle' : ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_preview ?? 'Cree una rifa para ver la vista previa.', style: const TextStyle(fontSize: 12.5, height: 1.5)),
        ],
      ),
    );

    return ListView(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      children: [
        if (isMobile) ...[editor, const SizedBox(height: 16), preview] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: editor), const SizedBox(width: 20), Expanded(child: preview)],
          ),
      ],
    );
  }
}
