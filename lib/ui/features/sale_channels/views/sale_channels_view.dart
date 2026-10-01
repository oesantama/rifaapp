import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/models/sale_channel.dart';
import 'package:rifaapp/ui/core/sale_channels.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/sale_channels/view_models/sale_channel_view_model.dart';

/// SuperAdmin master data: sale / contact channels offered when registering a sale.
/// Channels are deactivated instead of deleted so sold tickets keep their history.
class SaleChannelsView extends StatefulWidget {
  const SaleChannelsView({super.key});

  @override
  State<SaleChannelsView> createState() => _SaleChannelsViewState();
}

class _SaleChannelsViewState extends State<SaleChannelsView> {
  static const List<String> _palette = [
    '#1877F2',
    '#25D366',
    '#E1306C',
    '#000000',
    '#EC4899',
    '#8B5CF6',
    '#F59E0B',
    '#EF4444',
    '#10B981',
    '#0EA5E9',
    '#64748B',
    '#B45309',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<SaleChannelViewModel>().load());
  }

  Future<void> _edit(SaleChannel? channel) async {
    final vm = context.read<SaleChannelViewModel>();
    final nameCtrl = TextEditingController(text: channel?.name ?? '');
    String icon = channel?.icon ?? 'more';
    String color = channel?.color ?? '#64748B';
    bool active = channel?.active ?? true;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(channel == null ? 'Nuevo medio de venta' : 'Editar medio de venta'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ej: Instagram, TikTok, Feria'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Ícono', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final key in SaleChannels.icons.keys)
                        Tooltip(
                          message: SaleChannels.iconLabels[key] ?? key,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setDialogState(() => icon = key),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: icon == key ? SaleChannels.colorFrom(color).withValues(alpha: 0.15) : null,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: icon == key ? SaleChannels.colorFrom(color) : Colors.black12, width: icon == key ? 2 : 1),
                              ),
                              child: Icon(SaleChannels.iconFor(key), size: 20, color: SaleChannels.colorFrom(color)),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Color', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final hex in _palette)
                        GestureDetector(
                          onTap: () => setDialogState(() => color = hex),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: SaleChannels.colorFrom(hex),
                              shape: BoxShape.circle,
                              border: Border.all(color: color == hex ? Colors.black : Colors.black12, width: color == hex ? 3 : 1),
                            ),
                            child: color == hex ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                          ),
                        ),
                    ],
                  ),
                  if (channel != null) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Activo'),
                      subtitle: const Text('Si se desactiva, deja de aparecer al registrar ventas. Las boletas ya vendidas lo conservan.'),
                      value: active,
                      onChanged: (v) => setDialogState(() => active = v),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: AppTheme.dangerRose, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final result = await vm.save(channel?.id, {
                  'name': nameCtrl.text.trim(),
                  'icon': icon,
                  'color': color,
                  if (channel != null) 'active': active,
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
    final vm = context.watch<SaleChannelViewModel>();
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_sale_channel',
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo medio'),
      ),
      body: RefreshIndicator(
        onRefresh: vm.load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(isMobile ? 12 : 24, isMobile ? 12 : 24, isMobile ? 12 : 24, 96),
          children: [
            Text('Medios de venta', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Lista que ven los asesores y administradores al registrar una venta (cómo se contactó al comprador). '
              'Aplica a todas las empresas.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (vm.isLoading && vm.channels.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
            if (vm.error != null) Text(vm.error!, style: const TextStyle(color: AppTheme.dangerRose)),
            for (final c in vm.channels)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: SaleChannels.colorFrom(c.color).withValues(alpha: c.active ? 0.15 : 0.06),
                    child: Icon(SaleChannels.iconFor(c.icon), color: SaleChannels.colorFrom(c.color).withValues(alpha: c.active ? 1 : 0.4)),
                  ),
                  title: Text(
                    c.name,
                    style: TextStyle(fontWeight: FontWeight.w600, color: c.active ? null : Colors.grey),
                  ),
                  subtitle: Text(c.active ? 'Activo' : 'Inactivo — no aparece al vender'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: c.active,
                        onChanged: (v) async {
                          final error = await vm.save(c.id, {'active': v});
                          if (error != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                          }
                        },
                      ),
                      IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: () => _edit(c)),
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
