import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/models/lottery.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/lotteries/view_models/lottery_view_model.dart';

/// SuperAdmin master data: lotteries a raffle can play its main and weekly draws with.
/// Lotteries are deactivated instead of deleted so raffles keep the one they play with.
class LotteriesView extends StatefulWidget {
  const LotteriesView({super.key});

  @override
  State<LotteriesView> createState() => _LotteriesViewState();
}

class _LotteriesViewState extends State<LotteriesView> {
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<LotteryViewModel>().load());
  }

  Future<void> _edit(Lottery? lottery) async {
    final vm = context.read<LotteryViewModel>();
    final nameCtrl = TextEditingController(text: lottery?.name ?? '');
    bool active = lottery?.active ?? true;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(lottery == null ? 'Nueva lotería' : 'Editar lotería'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ej: Lotería de Boyacá'),
                ),
                if (lottery != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Activa'),
                    subtitle: const Text('Si se desactiva, deja de aparecer al configurar rifas. Las rifas que ya la tienen la conservan.'),
                    value: active,
                    onChanged: (v) => setDialogState(() => active = v),
                  ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppTheme.dangerRose, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final result = await vm.save(lottery?.id, {
                  'name': nameCtrl.text.trim(),
                  if (lottery != null) 'active': active,
                });
                if (result == null) {
                  if (ctx.mounted) Navigator.pop(ctx);
                } else {
                  setDialogState(() => error = result);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LotteryViewModel>();
    final isMobile = MediaQuery.of(context).size.width < 600;
    final query = _search.trim().toLowerCase();
    final shown = vm.lotteries.where((b) => query.isEmpty || b.name.toLowerCase().contains(query)).toList();
    final activeCount = vm.lotteries.where((b) => b.active).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_lottery',
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Nueva lotería'),
      ),
      body: RefreshIndicator(
        onRefresh: vm.load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(isMobile ? 12 : 24, isMobile ? 12 : 24, isMobile ? 12 : 24, 96),
          children: [
            Text('Loterías', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Loterías que las empresas eligen al configurar el sorteo principal y los sorteos semanales de cada rifa; '
              'aparecen en los mensajes de WhatsApp, los términos y la boleta impresa. '
              'Aplica a todas las empresas. $activeCount activas de ${vm.lotteries.length}.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar lotería...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 12),
            if (vm.isLoading && vm.lotteries.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (vm.error != null) Text(vm.error!, style: const TextStyle(color: AppTheme.dangerRose)),
            for (final b in shown)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepPurple.withValues(alpha: b.active ? 0.12 : 0.05),
                    child: Icon(Icons.confirmation_number, color: Colors.deepPurple.withValues(alpha: b.active ? 1 : 0.35)),
                  ),
                  title: Text(b.name, style: TextStyle(fontWeight: FontWeight.w600, color: b.active ? null : Colors.grey)),
                  subtitle: Text(b.active ? 'Activa' : 'Inactiva — no aparece al configurar rifas'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: b.active,
                        onChanged: (v) async {
                          final error = await vm.save(b.id, {'active': v});
                          if (error != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                          }
                        },
                      ),
                      IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: () => _edit(b)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
