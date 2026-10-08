import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/raffle.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/widgets/error_alert.dart';
import 'package:rifaapp/ui/features/admin_cash/views/cash_widgets.dart';

String _hour12(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return hhmm;
  final h = int.tryParse(parts[0]) ?? 0;
  return '${(h + 11) % 12 + 1}:${parts[1]} ${h < 12 ? 'a. m.' : 'p. m.'}';
}

String _drawDay(String? day) {
  final d = DateTime.tryParse(day ?? '');
  return d == null ? 'el día del sorteo' : 'el ${DateFormat('dd/MM/yyyy').format(d)}';
}

/// Admin: stop advisors from selling new tickets of the raffle — all of them or one by one, right away
/// or automatically from a time on the draw day. Admins keep selling, and advisors can still register
/// payments of tickets they already sold.
class SalesLockCard extends StatefulWidget {
  final Raffle raffle;

  const SalesLockCard({super.key, required this.raffle});

  @override
  State<SalesLockCard> createState() => _SalesLockCardState();
}

class _SalesLockCardState extends State<SalesLockCard> {
  final _repo = RaffleRepository();
  Map<String, dynamic>? _lock;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SalesLockCard old) {
    super.didUpdateWidget(old);
    if (old.raffle.id != widget.raffle.id) {
      _lock = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final lock = await _repo.fetchSalesLock(widget.raffle.id);
      if (mounted) setState(() => (_lock = lock, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<Map<String, dynamic>> get _advisors =>
      [for (final a in (_lock?['advisors'] as List? ?? [])) Map<String, dynamic>.from(a as Map)];

  @override
  Widget build(BuildContext context) {
    if (widget.raffle.isClosed) return const SizedBox.shrink();
    final lock = _lock;
    if (lock == null) {
      return _error == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('No se pudo leer el bloqueo de ventas: $_error', style: const TextStyle(color: AppTheme.dangerRose)),
            );
    }
    final general = lock['locked'] == true;
    final autoTime = (lock['autoLockTime'] ?? '').toString();
    final autoActive = lock['autoLockActive'] == true;
    final lockedAdvisors = _advisors.where((a) => a['locked'] == true).length;
    final allBlocked = general || autoActive;
    final color = allBlocked ? AppTheme.dangerRose : (lockedAdvisors > 0 ? Colors.orange.shade800 : AppTheme.secondaryEmerald);

    final status = general
        ? 'Ventas de asesores CERRADAS para todos'
        : autoActive
            ? 'Ventas de asesores cerradas automáticamente (${_hour12(autoTime)})'
            : lockedAdvisors > 0
                ? 'Ventas abiertas • $lockedAdvisors asesor(es) bloqueado(s)'
                : 'Ventas de asesores abiertas';
    final details = [
      'Sin vender: ${lock['totalAvailable']} de ${lock['totalTickets']} boletas',
      if (autoTime.isNotEmpty && !autoActive) 'Cierre automático ${_drawDay(lock['drawDay'])} a las ${_hour12(autoTime)}',
    ].join('  •  ');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14), side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.2)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(allBlocked ? Icons.lock : Icons.storefront, color: color, size: 28),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(status, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
                        const SizedBox(height: 2),
                        Text(details, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: _openManager,
              icon: const Icon(Icons.lock_person, size: 18),
              label: const Text('Bloquear / desbloquear ventas'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openManager() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _SalesLockSheet(raffle: widget.raffle, initial: _lock!, onChanged: (l) => setState(() => _lock = l)),
    );
    _load();
  }
}

class _SalesLockSheet extends StatefulWidget {
  final Raffle raffle;
  final Map<String, dynamic> initial;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const _SalesLockSheet({required this.raffle, required this.initial, required this.onChanged});

  @override
  State<_SalesLockSheet> createState() => _SalesLockSheetState();
}

class _SalesLockSheetState extends State<_SalesLockSheet> {
  final _repo = RaffleRepository();
  late Map<String, dynamic> _lock = widget.initial;
  bool _busy = false;

  Future<void> _save(Map<String, dynamic> changes, {String? advisorId}) async {
    setState(() => _busy = true);
    try {
      final lock = await _repo.updateSalesLock(widget.raffle.id, changes, advisorId: advisorId);
      widget.onChanged(lock);
      if (mounted) setState(() => _lock = lock);
    } catch (e) {
      if (mounted) await showErrorAlert(context, 'No se pudo guardar', e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleGeneral(bool lock) async {
    if (!lock) return _save({'locked': false});
    final reason = await askReason(context, 'Bloquear ventas a todos los asesores',
        hint: 'Ej.: faltan pocas horas para el sorteo', confirmLabel: 'Bloquear');
    if (reason != null) await _save({'locked': true, 'reason': reason});
  }

  Future<void> _toggleAdvisor(Map<String, dynamic> advisor, bool lock) async {
    final id = advisor['advisorId'].toString();
    if (!lock) return _save({'locked': false}, advisorId: id);
    final reason = await askReason(context, 'Bloquear ventas de ${advisor['name']}',
        hint: 'Ej.: no ha entregado el dinero recaudado', confirmLabel: 'Bloquear');
    if (reason != null) await _save({'locked': true, 'reason': reason}, advisorId: id);
  }

  Future<void> _pickTime() async {
    final current = (_lock['autoLockTime'] ?? '').toString().split(':');
    final picked = await showTimePicker(
      context: context,
      helpText: 'Hora de cierre el día del sorteo',
      initialTime: current.length == 2
          ? TimeOfDay(hour: int.tryParse(current[0]) ?? 18, minute: int.tryParse(current[1]) ?? 0)
          : const TimeOfDay(hour: 18, minute: 0),
    );
    if (picked == null) return;
    final hhmm = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    await _save({'autoLockTime': hhmm});
  }

  @override
  Widget build(BuildContext context) {
    final general = _lock['locked'] == true;
    final autoTime = (_lock['autoLockTime'] ?? '').toString();
    final autoActive = _lock['autoLockActive'] == true;
    final advisors = [for (final a in (_lock['advisors'] as List? ?? [])) Map<String, dynamic>.from(a as Map)];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Text('Ventas de asesores', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Un asesor bloqueado no puede vender ni apartar boletas nuevas de "${widget.raffle.title}". Sí puede registrar '
              'abonos de las boletas que ya vendió. Usted (administrador) sigue vendiendo normalmente. '
              'Quedan ${_lock['totalAvailable']} de ${_lock['totalTickets']} boletas sin vender.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey[700], height: 1.4),
            ),
            if (_busy) const LinearProgressIndicator(),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: general,
              onChanged: _busy ? null : _toggleGeneral,
              activeThumbColor: AppTheme.dangerRose,
              title: const Text('Bloquear a TODOS los asesores', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(general
                  ? 'Bloqueado por ${_lock['lockedBy'] ?? ''}: ${_lock['reason'] ?? ''}'
                  : 'Cierra las ventas de inmediato, hasta que usted las vuelva a abrir.'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.schedule, color: autoActive ? AppTheme.dangerRose : null),
              title: const Text('Cierre automático el día del sorteo', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(autoTime.isEmpty
                  ? 'Desactivado. Elija la hora a la que se cierran solas las ventas ${_drawDay(_lock['drawDay'])}.'
                  : autoActive
                      ? 'Ventas cerradas desde las ${_hour12(autoTime)} ${_drawDay(_lock['drawDay'])}.'
                      : 'Se cierran solas ${_drawDay(_lock['drawDay'])} a las ${_hour12(autoTime)} (hora de Colombia).'),
              trailing: Wrap(
                children: [
                  IconButton(onPressed: _busy ? null : _pickTime, icon: const Icon(Icons.edit_calendar), tooltip: 'Elegir hora'),
                  if (autoTime.isNotEmpty)
                    IconButton(
                      onPressed: _busy ? null : () => _save({'autoLockTime': ''}),
                      icon: const Icon(Icons.close),
                      tooltip: 'Quitar cierre automático',
                    ),
                ],
              ),
            ),
            const Divider(height: 24),
            const Text('Asesor por asesor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            if (advisors.isEmpty) const Text('Esta rifa no tiene asesores activos.'),
            for (final a in advisors)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: a['locked'] == true,
                onChanged: _busy ? null : (v) => _toggleAdvisor(a, v),
                activeThumbColor: AppTheme.dangerRose,
                title: Text('${a['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  [
                    a['availableInRanges'] == null
                        ? 'Vende de todas las boletas'
                        : 'Sin vender en sus números: ${a['availableInRanges']} (${(a['assignedRanges'] as List).join(', ')})',
                    'Vendidas/apartadas: ${a['sold']}',
                    if (a['locked'] == true) 'Bloqueado: ${a['reason']}'
                    else if (a['blockedNow'] != null) 'No puede vender (bloqueo general)',
                  ].join('\n'),
                  style: TextStyle(color: a['locked'] == true ? AppTheme.dangerRose : null),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
