import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/ui/features/lotteries/view_models/lottery_view_model.dart';
import 'package:rifaapp/ui/shared/widgets/searchable_picker.dart';

/// Lottery picker with searchable dialog.
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

  Future<void> _pickLottery(BuildContext context, List<String> names, String current) async {
    final selected = await showSearchablePicker<String>(
      context: context,
      title: 'Seleccionar Lotería',
      searchHint: 'Buscar lotería (ej: Medellín, Cruz Roja, Boyacá)...',
      items: names,
      labelBuilder: (name) => name,
      selectedValue: current.isEmpty ? null : current,
      allowCustom: true,
      customBuilder: (custom) => custom,
    );
    if (selected != null) {
      onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LotteryViewModel>();
    final names = vm.activeLotteries.map((l) => l.name).toList();
    final current = (value ?? '').trim();
    if (current.isNotEmpty && !names.contains(current)) names.insert(0, current);

    final displayCtrl = TextEditingController(text: current);

    return InkWell(
      onTap: () => _pickLottery(context, names, current),
      borderRadius: BorderRadius.circular(10),
      child: IgnorePointer(
        child: TextFormField(
          key: ValueKey('lottery-$label-$current-${names.length}'),
          controller: displayCtrl,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.confirmation_number_outlined),
            suffixIcon: const Icon(Icons.arrow_drop_down),
            border: const OutlineInputBorder(),
            helperText: vm.error != null
                ? 'No se pudo cargar la lista de loterías'
                : (names.isEmpty && !vm.isLoading
                    ? 'No hay loterías activas: el SuperAdmin debe agregarlas'
                    : (helperText ?? 'Toca para buscar y seleccionar lotería')),
            helperMaxLines: 2,
          ),
          validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Seleccione la lotería' : null : null,
        ),
      ),
    );
  }
}
