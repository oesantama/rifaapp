import 'package:flutter/material.dart';

/// Which lottery digits decide the winner (last / first / middle) and whether "combinado"
/// (same digits in any order) also wins. Shared by the create and edit raffle dialogs.
class WinningRuleFields extends StatelessWidget {
  final int digits;
  final String position; // ULTIMAS, PRIMERAS, MEDIO
  final bool allowCombined;
  final ValueChanged<String> onPositionChanged;
  final ValueChanged<bool> onCombinedChanged;

  const WinningRuleFields({
    super.key,
    required this.digits,
    required this.position,
    required this.allowCombined,
    required this.onPositionChanged,
    required this.onCombinedChanged,
  });

  /// Positions that make sense for the number of digits (lottery results have 4 digits).
  static List<String> positionsFor(int digits) =>
      digits == 2 ? const ['ULTIMAS', 'PRIMERAS', 'MEDIO'] : (digits == 3 ? const ['ULTIMAS', 'PRIMERAS'] : const ['ULTIMAS']);

  static String label(String position, int digits) => switch (position) {
        'PRIMERAS' => 'Las $digits primeras cifras de la lotería',
        'MEDIO' => 'Las $digits cifras del medio de la lotería',
        _ => 'Las $digits últimas cifras de la lotería',
      };

  static String example(String position, int digits) {
    const result = '4567';
    final value = switch (position) {
      'PRIMERAS' => result.substring(0, digits),
      'MEDIO' => result.substring(1, 1 + digits),
      _ => result.substring(result.length - digits),
    };
    return 'Ej: si la lotería sale $result, gana el $value';
  }

  @override
  Widget build(BuildContext context) {
    final options = positionsFor(digits);
    final current = options.contains(position) ? position : options.first;
    final combinedExample = digits == 2
        ? 'si gana el 12, también gana el 21'
        : (digits == 3 ? 'si gana el 123, también ganan 132, 213, 231, 312 y 321' : 'las mismas cifras en otro orden también ganan');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('🏆 ¿Con qué cifras de la lotería se gana?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 10),
          if (digits < 4) ...[
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: current,
              decoration: const InputDecoration(labelText: 'Cifras ganadoras', border: OutlineInputBorder()),
              items: [for (final p in options) DropdownMenuItem(value: p, child: Text(label(p, digits)))],
              onChanged: (v) {
                if (v != null) onPositionChanged(v);
              },
            ),
            const SizedBox(height: 4),
            Text(example(current, digits), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ] else
            Text('Rifa de $digits cifras: gana el número completo de la lotería.', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          // Own Material layer so the tap effect shows over the tinted background
          Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: allowCombined,
              onChanged: (v) => onCombinedChanged(v ?? false),
              title: const Text('Combinado ganador', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text('Las cifras en cualquier orden también ganan: $combinedExample.', style: const TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }
}
