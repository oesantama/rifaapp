import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/advisors/view_models/advisor_view_model.dart';

/// Al reactivar una rifa se pregunta a quién se le reactivan las ventas: todos los asesores o solo algunos.
/// Devuelve {'advisorMode': 'ALL' | 'SOME', 'advisorIds': [...]} o null si se cancela.
Future<Map<String, dynamic>?> askReactivateAdvisors(BuildContext context) {
  final advisors = context.read<AdvisorViewModel>().advisors.where((a) => a.isActive).toList();
  String mode = 'ALL';
  final selected = <String>{for (final a in advisors) a.id};

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.restore, color: AppTheme.secondaryEmerald),
          SizedBox(width: 10),
          Expanded(child: Text('Reactivar ventas de asesores', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
        ]),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Al cerrar o inactivar la rifa se bloquearon las ventas de todos los asesores. ¿A quiénes se las reactiva ahora?',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: 'ALL',
                  groupValue: mode,
                  title: const Text('A todos los asesores'),
                  onChanged: (v) => setD(() => mode = v!),
                ),
                RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: 'SOME',
                  groupValue: mode,
                  title: const Text('Solo a algunos'),
                  onChanged: (v) => setD(() => mode = v!),
                ),
                if (mode == 'SOME') ...[
                  const Divider(),
                  if (advisors.isEmpty)
                    const Text('No hay asesores activos.', style: TextStyle(color: Colors.grey))
                  else
                    for (final a in advisors)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: selected.contains(a.id),
                        title: Text('${a.name} (${a.code})', style: const TextStyle(fontSize: 13)),
                        onChanged: (v) => setD(() => v == true ? selected.add(a.id) : selected.remove(a.id)),
                      ),
                ],
                const SizedBox(height: 6),
                Text('Los asesores no reactivados siguen bloqueados; puede cambiarlo después en "Ventas de asesores".',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600])),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, {'advisorMode': mode, 'advisorIds': selected.toList()}),
            child: const Text('Reactivar'),
          ),
        ],
      ),
    ),
  );
}
