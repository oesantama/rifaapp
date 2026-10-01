import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/ui/features/lotteries/view_models/lottery_view_model.dart';

/// Lottery picker with the active lotteries of the SuperAdmin's master list. A value that is no
/// longer active (e.g. a raffle configured earlier) stays selectable so it is not lost.
class LotteryField extends StatelessWidget {
  final String? value;
  final String label;
  final ValueChanged<String?> onChanged;
  final String? helperText;
  final bool required;

  const LotteryField({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.helperText,
    this.required = true,
  });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LotteryViewModel>();
    final names = vm.activeLotteries.map((l) => l.name).toList();
    final current = (value ?? '').trim();
    if (current.isNotEmpty && !names.contains(current)) names.insert(0, current);

    return DropdownButtonFormField<String>(
      key: ValueKey('lottery-$label-$current-${names.length}'),
      isExpanded: true,
      initialValue: current.isEmpty ? null : current,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.confirmation_number_outlined),
        border: const OutlineInputBorder(),
        helperText: vm.error != null
            ? 'No se pudo cargar la lista de loterías'
            : (names.isEmpty && !vm.isLoading ? 'No hay loterías activas: el SuperAdmin debe agregarlas' : helperText),
        helperMaxLines: 2,
      ),
      items: [for (final name in names) DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis))],
      onChanged: onChanged,
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Seleccione la lotería' : null : null,
    );
  }
}
