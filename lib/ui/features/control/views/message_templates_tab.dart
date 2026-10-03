import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';

/// WhatsApp messages editor: one template per situation (apartada, abono, pagada, recordatorio).
/// The server fills them with the saved ticket; the placeholders that give the buyer confidence
/// are required and cannot be removed.
class MessageTemplatesTab extends StatefulWidget {
  const MessageTemplatesTab({super.key});

  @override
  State<MessageTemplatesTab> createState() => _MessageTemplatesTabState();
}

class _MessageTemplatesTabState extends State<MessageTemplatesTab> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _types = [];
  List<Map<String, dynamic>> _placeholders = [];
  String _type = 'reservada';
  String? _preview;
  String? _previewRaffle;
  bool _previewIsSample = false;
  bool _loading = true;
  bool _saving = false;

  static const _icons = {
    'reservada': Icons.bookmark_added_outlined,
    'abono': Icons.payments_outlined,
    'pagada': Icons.verified_outlined,
    'recordatorio': Icons.notifications_active_outlined,
  };

  Map<String, dynamic>? get _current => _types.where((t) => t['type'] == _type).firstOrNull;
  List<String> get _required => ((_current?['required'] as List?) ?? []).map((e) => e.toString()).toList();
  List<String> get _missing => _required.where((k) => !_controller.text.contains('{$k}')).toList();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await RaffleRepository().fetchMessageTemplates();
      if (!mounted) return;
      setState(() {
        _types = ((data['types'] as List?) ?? []).map((t) => Map<String, dynamic>.from(t)).toList();
        _placeholders = ((data['placeholders'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p)).toList();
      });
      _select(_type);
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(String type) {
    setState(() {
      _type = type;
      _controller.text = (_current?['template'] ?? '').toString();
      _preview = null;
    });
    _refreshPreview();
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
      final raffleId = context.read<RaffleViewModel>().selectedRaffle?.id;
      final data = await RaffleRepository().previewMessageTemplate(_type, _controller.text, raffleId: raffleId);
      if (!mounted) return;
      setState(() {
        _preview = data['preview'];
        _previewRaffle = data['previewRaffle'];
        _previewIsSample = data['sample'] == true;
      });
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  Future<void> _save({bool restoreDefault = false}) async {
    if (!restoreDefault && _missing.isNotEmpty) {
      _snack('Faltan datos obligatorios: ${_missing.map((k) => '{$k}').join(', ')}', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await RaffleRepository().saveMessageTemplate(_type, restoreDefault ? '' : _controller.text);
      await _load();
      _snack(restoreDefault ? 'Se restauró el mensaje predeterminado.' : 'Mensaje guardado.');
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
    final current = _current;
    final missing = _missing;

    final selector = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in _types)
          ChoiceChip(
            avatar: Icon(_icons[t['type']] ?? Icons.message_outlined, size: 18),
            label: Text('${t['label']}${t['isDefault'] == true ? '' : ' (editado)'}'),
            visualDensity: VisualDensity.compact,
            selected: t['type'] == _type,
            onSelected: (_) => _select(t['type']),
          ),
      ],
    );

    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${current?['description'] ?? ''} El mensaje se llena con los datos guardados de la boleta. '
          'Los campos en verde son obligatorios para dar confianza al comprador.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey[700], height: 1.4),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in _placeholders)
              Tooltip(
                message: '${p['description'] ?? ''}${_required.contains(p['key']) ? ' (obligatorio)' : ''}',
                child: ActionChip(
                  backgroundColor: _required.contains(p['key'])
                      ? (missing.contains(p['key']) ? AppTheme.dangerRose.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.12))
                      : null,
                  label: Text('{${p['key']}}', style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
                  onPressed: () => _insert(p['key']),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          minLines: 12,
          maxLines: 26,
          maxLength: 4000,
          decoration: InputDecoration(
            labelText: current?['isDefault'] == true ? 'Mensaje predeterminado' : 'Mensaje de su empresa',
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Faltan datos obligatorios: ${missing.map((k) => '{$k}').join(', ')}',
              style: const TextStyle(color: AppTheme.dangerRose, fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: _saving || missing.isNotEmpty ? null : () => _save(),
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: const Text('Guardar'),
            ),
            OutlinedButton.icon(onPressed: _refreshPreview, icon: const Icon(Icons.visibility_outlined), label: const Text('Vista previa')),
            TextButton.icon(
              onPressed: _saving ? null : () => _save(restoreDefault: true),
              icon: const Icon(Icons.restore),
              label: const Text('Restaurar predeterminado'),
            ),
          ],
        ),
      ],
    );

    final preview = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFDCF8C6).withValues(alpha: 0.5), // WhatsApp bubble
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vista previa${_previewRaffle != null ? ' — $_previewRaffle' : ''}${_previewIsSample ? ' (boleta de ejemplo)' : ''}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SelectableText(_preview ?? 'Cree una rifa para ver la vista previa.', style: const TextStyle(fontSize: 12.5, height: 1.45)),
        ],
      ),
    );

    return ListView(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      children: [
        selector,
        const SizedBox(height: 14),
        if (isMobile) ...[editor, const SizedBox(height: 16), preview] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: editor), const SizedBox(width: 20), Expanded(child: preview)],
          ),
      ],
    );
  }
}
