import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/services/api_service.dart';
import 'package:rifaapp/ui/core/theme.dart';

/// Control → Entrenar Bot: el administrador mejora el chatbot sin tocar código.
///  • Respuestas: preguntas frecuentes con sus palabras clave (y un probador).
///  • Sin respuesta: lo que los clientes preguntaron y el bot no supo → se convierte en respuesta con un clic.
///  • Asesor y datos: chats que pidieron una persona, ajustes del pase a asesor y "¿cómo se enteró?".
class BotTrainingTab extends StatefulWidget {
  const BotTrainingTab({super.key});

  @override
  State<BotTrainingTab> createState() => _BotTrainingTabState();
}

class _BotTrainingTabState extends State<BotTrainingTab> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late final TabController _tabs = TabController(length: 3, vsync: this);

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _config = {};
  List<Map<String, dynamic>> _unanswered = [];
  List<Map<String, dynamic>> _handoffs = [];
  Map<String, dynamic> _howHeardStats = {};

  List<Map<String, dynamic>> get _faqs => ((_config['faqs'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
  int get _pendingHandoffs => _handoffs.where((h) => h['status'] == 'PENDIENTE').length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([_api.botFetchConfig(), _api.botFetchUnanswered(), _api.botFetchHandoffs()]);
      if (!mounted) return;
      setState(() {
        _config = Map<String, dynamic>.from(results[0]['config'] ?? {});
        _howHeardStats = Map<String, dynamic>.from(results[0]['howHeardStats'] ?? {});
        _unanswered = ((results[1]['unanswered'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
        _handoffs = ((results[2]['handoffs'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? Colors.red.shade700 : AppTheme.secondaryEmerald,
      content: Text(text),
    ));
  }

  /// Saves the whole config; returns true when it was accepted.
  Future<bool> _save(Map<String, dynamic> config, {String ok = 'Guardado'}) async {
    try {
      final res = await _api.botSaveConfig(config);
      if (!mounted) return true;
      setState(() => _config = Map<String, dynamic>.from(res['config'] ?? config));
      _toast(ok);
      return true;
    } catch (e) {
      if (mounted) _toast(e.toString(), error: true);
      return false;
    }
  }

  String _when(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '' : DateFormat('dd/MM HH:mm').format(d.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.dangerRose)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
          ]),
        ),
      );
    }
    return Column(
      children: [
        Material(
          color: Theme.of(context).cardColor,
          child: TabBar(
            controller: _tabs,
            tabs: [
              const Tab(text: 'Respuestas'),
              Tab(text: 'Sin respuesta${_unanswered.isEmpty ? '' : ' (${_unanswered.length})'}'),
              Tab(text: 'Asesor y datos${_pendingHandoffs == 0 ? '' : ' • $_pendingHandoffs por atender'}'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(controller: _tabs, children: [_buildFaqs(), _buildUnanswered(), _buildAdvisorAndData()]),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Respuestas
  // ---------------------------------------------------------------------------
  Widget _buildFaqs() {
    final faqs = _faqs;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _BotTester(api: _api),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(
            child: Text('Respuestas personalizadas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          FilledButton.icon(
            onPressed: () => _editFaq(null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nueva respuesta'),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Cuando el cliente escribe una de las palabras clave, el bot envía la respuesta. Tienen prioridad sobre las respuestas automáticas.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 10),
        if (faqs.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
            child: const Text('Aún no hay respuestas. Crea la primera, por ejemplo: "horario", "ubicación", "cómo reclamo el premio".'),
          ),
        for (final faq in faqs)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text('${faq['title']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                    Text('${faq['hits'] ?? 0} usos', style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
                    Switch(
                      value: faq['active'] != false,
                      onChanged: (v) => _save({
                        ..._config,
                        'faqs': [for (final f in _faqs) f['id'] == faq['id'] ? {...f, 'active': v} : f],
                      }, ok: v ? 'Respuesta activada' : 'Respuesta desactivada'),
                    ),
                    IconButton(icon: const Icon(Icons.edit_outlined, size: 20), tooltip: 'Editar', onPressed: () => _editFaq(faq)),
                    IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                        tooltip: 'Eliminar',
                        onPressed: () => _deleteFaq(faq)),
                  ]),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final k in (faq['keywords'] as List? ?? []))
                      Chip(label: Text('$k', style: const TextStyle(fontSize: 11.5)), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                  ]),
                  const SizedBox(height: 6),
                  Text('${faq['answer']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.grey[800])),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _deleteFaq(Map<String, dynamic> faq) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar respuesta?'),
        content: Text('Se eliminará "${faq['title']}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    await _save({..._config, 'faqs': _faqs.where((f) => f['id'] != faq['id']).toList()}, ok: 'Respuesta eliminada');
  }

  Future<void> _editFaq(Map<String, dynamic>? faq) async {
    final title = TextEditingController(text: faq == null ? '' : '${faq['title']}');
    final keywords = TextEditingController(text: faq == null ? '' : (faq['keywords'] as List).join(', '));
    final answer = TextEditingController(text: faq == null ? '' : '${faq['answer']}');
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(faq == null ? 'Nueva respuesta' : 'Editar respuesta'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Nombre (solo para ti)', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                  controller: keywords,
                  decoration: const InputDecoration(
                    labelText: 'Palabras clave (separadas por coma) *',
                    helperText: 'Ej: horario, a que hora abren, hasta que hora atienden',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: answer,
                  maxLines: 6,
                  maxLength: 1500,
                  decoration: const InputDecoration(
                    labelText: 'Respuesta que enviará el bot *',
                    helperText: 'Puedes usar {empresa}, {rifa}, {precio} y {fecha}.',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (error != null) Text(error!, style: const TextStyle(color: AppTheme.dangerRose, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                if (keywords.text.trim().isEmpty || answer.text.trim().isEmpty) {
                  setD(() => error = 'Escribe al menos una palabra clave y la respuesta.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final item = {
        if (faq != null) 'id': faq['id'],
        'title': title.text.trim(),
        'keywords': keywords.text.split(RegExp(r'[,\n]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'answer': answer.text.trim(),
        'active': faq == null ? true : faq['active'] != false,
      };
      final list = faq == null ? [..._faqs, item] : [for (final f in _faqs) f['id'] == faq['id'] ? {...f, ...item} : f];
      await _save({..._config, 'faqs': list}, ok: 'Respuesta guardada');
    }
    title.dispose();
    keywords.dispose();
    answer.dispose();
  }

  // ---------------------------------------------------------------------------
  // Sin respuesta
  // ---------------------------------------------------------------------------
  Widget _buildUnanswered() {
    if (_unanswered.isEmpty) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.check_circle_outline, size: 48, color: AppTheme.secondaryEmerald),
        const SizedBox(height: 10),
        const Text('Todo al día', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Aquí aparecerán los mensajes que el bot no supo responder, para que los conviertas en respuestas.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
      ]);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Estas preguntas no tenían respuesta. Conviértelas en una respuesta del bot o descártalas.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
          const SizedBox(height: 10),
          for (final u in _unanswered)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('"${u['text']}"', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                  const SizedBox(height: 4),
                  Text('${u['count'] ?? 1} ${(u['count'] ?? 1) == 1 ? 'vez' : 'veces'}  •  +${u['phone']}  •  ${_when(u['lastAt'])}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: () => _discard(u), child: const Text('Descartar')),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      onPressed: () => _unansweredToFaq(u),
                      icon: const Icon(Icons.add_comment_outlined, size: 18),
                      label: const Text('Crear respuesta'),
                    ),
                  ]),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _discard(Map<String, dynamic> u) async {
    try {
      await _api.botDeleteUnanswered('${u['id']}');
      if (mounted) setState(() => _unanswered = _unanswered.where((x) => x['id'] != u['id']).toList());
    } catch (e) {
      if (mounted) _toast(e.toString(), error: true);
    }
  }

  Future<void> _unansweredToFaq(Map<String, dynamic> u) async {
    final keywords = TextEditingController(text: '${u['text']}');
    final answer = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Crear respuesta'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('El cliente preguntó: "${u['text']}"', style: TextStyle(color: Colors.grey[700])),
                const SizedBox(height: 12),
                TextField(
                  controller: keywords,
                  decoration: const InputDecoration(
                    labelText: 'Palabras clave (separadas por coma)',
                    helperText: 'Deja solo lo esencial: "horario", "ubicación"…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: answer,
                  maxLines: 6,
                  maxLength: 1500,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Respuesta que enviará el bot *', border: OutlineInputBorder()),
                ),
                if (error != null) Text(error!, style: const TextStyle(color: AppTheme.dangerRose, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                if (answer.text.trim().isEmpty || keywords.text.trim().isEmpty) {
                  setD(() => error = 'Escribe las palabras clave y la respuesta.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await _api.botUnansweredToFaq(
          '${u['id']}',
          title: '${u['text']}',
          keywords: keywords.text.split(RegExp(r'[,\n]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
          answer: answer.text.trim(),
        );
        _toast('Respuesta creada. El bot ya la usa.');
        await _load();
      } catch (e) {
        if (mounted) _toast(e.toString(), error: true);
      }
    }
    keywords.dispose();
    answer.dispose();
  }

  // ---------------------------------------------------------------------------
  // Asesor y datos
  // ---------------------------------------------------------------------------
  Widget _buildAdvisorAndData() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Chats por atender', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          'Clientes que pidieron hablar con una persona (o que el bot no logró entender). Mientras estén aquí el bot se queda callado en ese chat. '
          'Respóndeles desde tu WhatsApp y márcalos como atendidos para que el bot vuelva a responder.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 10),
        if (_handoffs.isEmpty)
          Text('Nadie ha pedido un asesor todavía.', style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic)),
        for (final h in _handoffs.take(30))
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: h['status'] == 'PENDIENTE' ? Colors.orange.shade50 : null,
            child: ListTile(
              leading: Icon(h['status'] == 'PENDIENTE' ? Icons.support_agent : Icons.check_circle_outline,
                  color: h['status'] == 'PENDIENTE' ? Colors.orange.shade800 : AppTheme.secondaryEmerald),
              title: Text('${(h['name'] ?? '').toString().isEmpty ? 'Cliente' : h['name']}  •  +${h['phone']}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(
                '${h['reason'] == 'NO_ENTENDIDO' ? 'El bot no entendió' : 'Pidió un asesor'} • ${_when(h['updatedAt'] ?? h['at'])}\n"${h['lastMessage'] ?? ''}"',
                style: const TextStyle(fontSize: 12.5),
              ),
              isThreeLine: true,
              trailing: h['status'] == 'PENDIENTE'
                  ? FilledButton(
                      onPressed: () async {
                        try {
                          await _api.botResolveHandoff('${h['id']}');
                          await _load();
                        } catch (e) {
                          if (mounted) _toast(e.toString(), error: true);
                        }
                      },
                      child: const Text('Atendido'),
                    )
                  : const Text('Atendido', style: TextStyle(fontSize: 12)),
            ),
          ),
        const Divider(height: 32),
        _HandoffSettings(
          key: ValueKey('settings-${_config.hashCode}'),
          config: _config,
          howHeardStats: _howHeardStats,
          onSave: (c) => _save(c, ok: 'Ajustes guardados'),
        ),
      ],
    );
  }
}

/// Free-text box to try what the bot would answer (nothing is sent to WhatsApp).
class _BotTester extends StatefulWidget {
  final ApiService api;
  const _BotTester({required this.api});

  @override
  State<_BotTester> createState() => _BotTesterState();
}

class _BotTesterState extends State<_BotTester> {
  final _ctrl = TextEditingController();
  Map<String, dynamic>? _result;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await widget.api.botTest(_ctrl.text.trim());
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _result = {'type': 'error', 'answer': e.toString()});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = _result?['type'];
    return Card(
      color: AppTheme.primaryBlue.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.science_outlined, size: 20, color: AppTheme.primaryBlue),
            SizedBox(width: 8),
            Text('Probar el bot', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          Text('Escribe un mensaje como si fueras un cliente y mira qué respondería (no se envía nada).',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                decoration: const InputDecoration(hintText: 'Ej: ¿a qué hora atienden?', isDense: true, border: OutlineInputBorder()),
                onSubmitted: (_) => _run(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _run,
              child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Probar'),
            ),
          ]),
          if (_result != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: type == 'faq' ? Colors.green.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  type == 'faq'
                      ? 'Respondería con la respuesta "${_result!['title']}":'
                      : type == 'handoff'
                          ? 'Pasaría a un asesor'
                          : type == 'greeting'
                              ? 'Saludo'
                              : type == 'error'
                                  ? 'Error'
                                  : 'Sin respuesta personalizada',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                Text('${_result!['answer']}', style: const TextStyle(fontSize: 13)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Handoff, welcome message and "how did you hear about us" settings.
class _HandoffSettings extends StatefulWidget {
  final Map<String, dynamic> config;
  final Map<String, dynamic> howHeardStats;
  final Future<bool> Function(Map<String, dynamic>) onSave;
  const _HandoffSettings({super.key, required this.config, required this.howHeardStats, required this.onSave});

  @override
  State<_HandoffSettings> createState() => _HandoffSettingsState();
}

class _HandoffSettingsState extends State<_HandoffSettings> {
  late bool _handoffEnabled;
  late bool _howEnabled;
  late int _autoAfter;
  late final TextEditingController _notify;
  late final TextEditingController _keywords;
  late final TextEditingController _message;
  late final TextEditingController _greeting;
  late final TextEditingController _options;
  late final TextEditingController _resume;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final h = Map<String, dynamic>.from(widget.config['handoff'] ?? {});
    final how = Map<String, dynamic>.from(widget.config['howHeard'] ?? {});
    _handoffEnabled = h['enabled'] != false;
    _howEnabled = how['enabled'] != false;
    _autoAfter = (h['autoAfterFails'] as num?)?.toInt() ?? 2;
    _notify = TextEditingController(text: '${h['notifyNumber'] ?? ''}');
    _keywords = TextEditingController(text: ((h['keywords'] as List?) ?? []).join(', '));
    _message = TextEditingController(text: '${h['message'] ?? ''}');
    _greeting = TextEditingController(text: '${widget.config['greeting'] ?? ''}');
    _options = TextEditingController(text: ((how['options'] as List?) ?? []).join(', '));
    _resume = TextEditingController(text: '${h['resumeHours'] ?? 12}');
  }

  @override
  void dispose() {
    for (final c in [_notify, _keywords, _message, _greeting, _options, _resume]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _list(TextEditingController c) => c.text.split(RegExp(r'[,\n]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.onSave({
      ...widget.config,
      'greeting': _greeting.text.trim(),
      'handoff': {
        'enabled': _handoffEnabled,
        'keywords': _list(_keywords),
        'message': _message.text.trim(),
        'notifyNumber': _notify.text.trim(),
        'autoAfterFails': _autoAfter,
        'resumeHours': int.tryParse(_resume.text.trim()) ?? 12,
      },
      'howHeard': {'enabled': _howEnabled, 'options': _list(_options)},
    });
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.howHeardStats.entries.toList()..sort((a, b) => (b.value as num).compareTo(a.value as num));
    final total = stats.fold<num>(0, (s, e) => s + (e.value as num));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Pase a asesor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Permitir que el cliente hable con una persona'),
        subtitle: const Text('Si lo escribe ("asesor", "humano"…) el bot se calla en ese chat y te avisa.'),
        value: _handoffEnabled,
        onChanged: (v) => setState(() => _handoffEnabled = v),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: _notify,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
        decoration: const InputDecoration(
          labelText: 'Tu WhatsApp para recibir el aviso',
          hintText: '3001234567',
          helperText: 'Cuando un cliente pida un asesor, el bot te escribe a este número. Vacío = sin aviso.',
          helperMaxLines: 2,
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.notifications_active_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _keywords,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Palabras que piden un asesor',
          helperText: 'Separadas por coma. Ej: asesor, humano, persona, agente',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _message,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Mensaje al pasar a asesor (opcional)',
          helperText: 'Vacío = mensaje por defecto. Puedes usar {empresa}.',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            value: _autoAfter,
            decoration: const InputDecoration(labelText: 'Pasar a asesor si no entiende', border: OutlineInputBorder(), isDense: true),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Nunca')),
              DropdownMenuItem(value: 1, child: Text('1 mensaje sin entender')),
              DropdownMenuItem(value: 2, child: Text('2 mensajes seguidos')),
              DropdownMenuItem(value: 3, child: Text('3 mensajes seguidos')),
              DropdownMenuItem(value: 5, child: Text('5 mensajes seguidos')),
            ],
            onChanged: (v) => setState(() => _autoAfter = v ?? 2),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 150,
          child: TextField(
            controller: _resume,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Bot vuelve en (horas)', border: OutlineInputBorder(), isDense: true),
          ),
        ),
      ]),
      const Divider(height: 32),
      const Text('Mensaje de bienvenida', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      TextField(
        controller: _greeting,
        maxLines: 4,
        decoration: const InputDecoration(
          hintText: 'Vacío = menú por defecto',
          helperText: 'Se envía cuando el cliente saluda o escribe algo que el bot no entiende. Puedes usar {empresa}, {rifa}, {precio}, {fecha}.',
          helperMaxLines: 3,
          border: OutlineInputBorder(),
        ),
      ),
      const Divider(height: 32),
      const Text('¿Cómo se enteró de nosotros?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Preguntarlo al completar los datos de la compra'),
        subtitle: const Text('Se guarda en la boleta para saber qué publicidad funciona.'),
        value: _howEnabled,
        onChanged: (v) => setState(() => _howEnabled = v),
      ),
      TextField(
        controller: _options,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Opciones (separadas por coma, máx. 10)', border: OutlineInputBorder()),
      ),
      if (stats.isNotEmpty) ...[
        const SizedBox(height: 12),
        const Text('Resultados', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        for (final e in stats)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(width: 150, child: Text(e.key, overflow: TextOverflow.ellipsis)),
              Expanded(
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : (e.value as num) / total,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Text('${e.value}'),
            ]),
          ),
      ],
      const SizedBox(height: 20),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined, size: 18),
          label: const Text('Guardar ajustes'),
        ),
      ),
      const SizedBox(height: 24),
    ]);
  }
}
