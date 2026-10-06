import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/models/raffle.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/core/utils/file_saver.dart';
import 'package:rifaapp/ui/core/widgets/error_alert.dart';
import 'package:rifaapp/ui/features/raffles/view_models/raffle_view_model.dart';
import 'package:rifaapp/ui/features/winners/view_models/winner_view_model.dart';

String _day(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  return d == null ? '' : DateFormat('dd/MM/yyyy').format(d.toLocal());
}

/// Downloads the raffle's ZIP (Excel workbook + proof images).
Future<void> downloadRaffleExport(BuildContext context, Raffle raffle) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(
    duration: Duration(seconds: 30),
    content: Text('Preparando el archivo (Excel y soportes)… puede tardar si hay muchas fotos.'),
  ));
  try {
    final bytes = await RaffleRepository().exportRaffle(raffle.id);
    final name = 'rifa_${raffle.title.replaceAll(RegExp(r'[^\w]+'), '_')}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.zip';
    await saveAndDownloadBytes(name, bytes, mimeType: 'application/zip');
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(backgroundColor: AppTheme.secondaryEmerald, content: Text('Descargado: $name')));
  } catch (e) {
    messenger.hideCurrentSnackBar();
    if (context.mounted) await showErrorAlert(context, 'No se pudo descargar', e.toString());
  }
}

/// Admin: once the main draw date has passed, close the raffle (it is deleted with all its data
/// 7 days later), download its information, or reopen it during those 7 days.
class RaffleCloseCard extends StatelessWidget {
  final Raffle raffle;

  const RaffleCloseCard({super.key, required this.raffle});

  /// Pending things that should be done before closing.
  List<String> _pending(BuildContext context) {
    final draws = context.read<WinnerViewModel>().mainDrawsOf(raffle.id);
    final latest = draws.firstOrNull;
    if (latest == null) return ['No se ha registrado el resultado del gran premio.'];
    if (latest.isWinner && latest.prizeDelivery == null)
      return ['El premio del gran premio aún no se ha entregado (no está registrada la entrega).'];
    if (!latest.isWinner && latest.decision == null)
      return ['El gran premio quedó sin ganador y no se ha decidido si se vuelve a jugar o se cierra.'];
    if (latest.decisionType == 'REPROGRAMADO') return ['El gran premio fue reprogramado para otra fecha.'];
    return [];
  }

  Future<void> _close(BuildContext context) async {
    final pending = _pending(context);
    bool understood = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: AppTheme.dangerRose, size: 40),
          title: const Text('Cerrar la rifa'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('"${raffle.title}" quedará INACTIVA.', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'Estará disponible 7 días más para consultar y descargar su información. Pasado ese tiempo se ELIMINARÁ '
                    'TODA su información: boletas, compradores, pagos, ganadores, entregas de caja y soportes en Google Drive. '
                    'Esto no se puede deshacer.',
                    style: TextStyle(height: 1.4),
                  ),
                  if (pending.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Text('Atención: ${pending.join(' ')}',
                          style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w600)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => downloadRaffleExport(ctx, raffle),
                    icon: const Icon(Icons.download),
                    label: const Text('Descargar información primero (Excel + soportes)'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: understood,
                    onChanged: (v) => setD(() => understood = v == true),
                    title: const Text('Entiendo que en 7 días se eliminará toda la información de esta rifa.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: understood ? () => Navigator.pop(ctx, true) : null,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRose, foregroundColor: Colors.white),
              child: const Text('Cerrar rifa'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await _save(context, reopen: false);
  }

  Future<void> _save(BuildContext context, {required bool reopen}) async {
    final raffleVM = context.read<RaffleViewModel>();
    try {
      final updated = await RaffleRepository().closeRaffle(raffle.id, reopen: reopen);
      raffleVM.updateRaffleInList(updated);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: reopen ? AppTheme.secondaryEmerald : Colors.orange.shade800,
          content: Text(reopen
              ? 'Rifa reactivada: ya no se eliminará.'
              : 'Rifa cerrada. Se eliminará el ${_day(updated.scheduledDeletionAt)}. Descargue su información antes.'),
        ));
      }
    } catch (e) {
      if (context.mounted) await showErrorAlert(context, 'No se pudo completar', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<WinnerViewModel>();
    if (!raffle.isClosed && !raffle.drawDatePassed) return const SizedBox.shrink();
    final closed = raffle.isClosed;
    final color = closed ? AppTheme.dangerRose : Colors.orange.shade800;
    final days = raffle.daysUntilDeletion;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14), side: BorderSide(color: color.withValues(alpha: 0.6), width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(closed ? Icons.delete_forever : Icons.event_available, color: color, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    closed ? 'Rifa cerrada: se eliminará el ${_day(raffle.scheduledDeletionAt)}' : 'El sorteo de esta rifa ya pasó',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              closed
                  ? 'Faltan $days día(s). Cerrada el ${_day(raffle.closedAt)} por ${raffle.closedBy ?? ''}. Descargue su información (Excel y '
                      'soportes) antes de esa fecha: después se borrará todo y no se podrá recuperar.'
                  : 'Cuando termine (premios entregados y caja al día), ciérrela. Quedará 7 días disponible para descargar su información '
                      'y luego se eliminará.',
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => downloadRaffleExport(context, raffle),
                  icon: const Icon(Icons.download),
                  label: const Text('Descargar información'),
                ),
                if (closed)
                  ElevatedButton.icon(
                    onPressed: () => _save(context, reopen: true),
                    icon: const Icon(Icons.restore),
                    label: const Text('Reactivar rifa'),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: () => _close(context),
                    icon: const Icon(Icons.lock_clock),
                    label: const Text('Cerrar rifa'),
                    style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
