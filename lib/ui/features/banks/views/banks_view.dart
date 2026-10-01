import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/models/bank.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/banks/view_models/bank_view_model.dart';

/// SuperAdmin master data: banks and wallets offered in transfer payments and raffle accounts.
/// Banks are deactivated instead of deleted so registered payments keep their history.
class BanksView extends StatefulWidget {
  const BanksView({super.key});

  @override
  State<BanksView> createState() => _BanksViewState();
}

class _BanksViewState extends State<BanksView> {
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<BankViewModel>().load());
  }

  Future<void> _edit(Bank? bank) async {
    final vm = context.read<BankViewModel>();
    final nameCtrl = TextEditingController(text: bank?.name ?? '');
    bool active = bank?.active ?? true;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(bank == null ? 'Nuevo banco' : 'Editar banco'),
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
                  decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ej: Banco de Bogotá, Nequi'),
                ),
                if (bank != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Activo'),
                    subtitle: const Text(
                        'Si se desactiva, deja de aparecer al registrar pagos y cuentas. Los pagos ya registrados lo conservan.'),
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
                final result = await vm.save(bank?.id, {
                  'name': nameCtrl.text.trim(),
                  if (bank != null) 'active': active,
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
    final vm = context.watch<BankViewModel>();
    final isMobile = MediaQuery.of(context).size.width < 600;
    final query = _search.trim().toLowerCase();
    final shown = vm.banks.where((b) => query.isEmpty || b.name.toLowerCase().contains(query)).toList();
    final activeCount = vm.banks.where((b) => b.active).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_bank',
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo banco'),
      ),
      body: RefreshIndicator(
        onRefresh: vm.load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(isMobile ? 12 : 24, isMobile ? 12 : 24, isMobile ? 12 : 24, 96),
          children: [
            Text('Bancos', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Lista de bancos y billeteras que ven las empresas y asesores al registrar transferencias y las cuentas de cada rifa. '
              'Aplica a todas las empresas. $activeCount activos de ${vm.banks.length}.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar banco...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 12),
            if (vm.isLoading && vm.banks.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (vm.error != null) Text(vm.error!, style: const TextStyle(color: AppTheme.dangerRose)),
            for (final b in shown)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepPurple.withValues(alpha: b.active ? 0.12 : 0.05),
                    child: Icon(Icons.account_balance, color: Colors.deepPurple.withValues(alpha: b.active ? 1 : 0.35)),
                  ),
                  title: Text(b.name, style: TextStyle(fontWeight: FontWeight.w600, color: b.active ? null : Colors.grey)),
                  subtitle: Text(b.active ? 'Activo' : 'Inactivo — no aparece al registrar pagos'),
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
