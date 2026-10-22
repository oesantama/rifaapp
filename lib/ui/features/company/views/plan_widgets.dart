import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rifaapp/data/models/company.dart';

/// "30/09/2026" from "2026-09-30".
String formatPlanDate(String? day) {
  final parsed = DateTime.tryParse(day ?? '');
  return parsed == null ? '' : DateFormat('dd/MM/yyyy').format(parsed);
}

/// Plan selector for the company dialogs: FREE (with ads) or PRO (no ads) with an optional end date and active raffles limit.
class PlanFields extends StatelessWidget {
  final String tier;
  final String? proUntil;
  final int maxActiveRaffles;
  final void Function(String tier, String? proUntil, int maxActiveRaffles) onChanged;

  const PlanFields({
    super.key,
    required this.tier,
    required this.proUntil,
    this.maxActiveRaffles = 0,
    required this.onChanged,
  });

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final current = DateTime.tryParse(proUntil ?? '');
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null && current.isAfter(now) ? current : now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 5),
      helpText: 'Último día del plan PRO',
    );
    if (picked != null) onChanged('PRO', DateFormat('yyyy-MM-dd').format(picked), maxActiveRaffles);
  }

  @override
  Widget build(BuildContext context) {
    final expired = tier == 'PRO' &&
        proUntil != null &&
        (DateTime.tryParse(proUntil!)?.isBefore(DateTime.now().subtract(const Duration(days: 1))) ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('💎 Plan de la empresa:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'FREE', label: Text('Gratis'), icon: Icon(Icons.campaign_outlined)),
            ButtonSegment(value: 'PRO', label: Text('PRO'), icon: Icon(Icons.workspace_premium_outlined)),
          ],
          selected: {tier},
          onSelectionChanged: (v) => onChanged(v.first, v.first == 'PRO' ? proUntil : null, maxActiveRaffles),
        ),
        const SizedBox(height: 4),
        Text(tier == 'PRO' ? 'Sin anuncios en la app de la empresa.' : 'La empresa ve el anuncio "Pásate a PRO".',
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        if (tier == 'PRO') ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Vence el (opcional)',
                    prefixIcon: const Icon(Icons.event_available),
                    helperText: proUntil == null
                        ? 'Sin fecha: el PRO no vence'
                        : (expired ? 'Venció: la empresa ya está en Gratis' : 'Al día siguiente pasa sola a Gratis'),
                    helperStyle: TextStyle(color: expired ? Colors.red.shade700 : null),
                    helperMaxLines: 2,
                  ),
                  child: Text(proUntil == null ? 'Sin vencimiento' : formatPlanDate(proUntil)),
                ),
              ),
              IconButton(icon: const Icon(Icons.edit_calendar), tooltip: 'Elegir fecha', onPressed: () => _pickDate(context)),
              if (proUntil != null)
                IconButton(icon: const Icon(Icons.clear), tooltip: 'Quitar vencimiento', onPressed: () => onChanged('PRO', null, maxActiveRaffles)),
            ],
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          initialValue: maxActiveRaffles.toString(),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Cupo total de rifas contratadas',
            prefixIcon: const Icon(Icons.confirmation_number_outlined),
            helperText: maxActiveRaffles == 0
                ? '0 = Ilimitadas (Modalidad Suscripción Mensual)'
                : 'Cupo: $maxActiveRaffles rifa(s). Aunque se cierre o elimine, no podrá crear más sin recarga de cupo.',
            helperMaxLines: 2,
          ),
          onChanged: (val) {
            final parsed = int.tryParse(val.trim()) ?? 0;
            onChanged(tier, proUntil, parsed < 0 ? 0 : parsed);
          },
        ),
      ],
    );
  }
}

/// Badge with the company's plan in force (and its end date) for the company card.
class PlanBadge extends StatelessWidget {
  final Company company;

  const PlanBadge({super.key, required this.company});

  @override
  Widget build(BuildContext context) {
    if (company.isDemo) return _chip('DEMO', Colors.purple);
    final limit = company.maxActiveRaffles == 0
        ? 'Ilimitadas'
        : 'Cupo: ${company.rafflesCreatedCount}/${company.maxActiveRaffles}';
    if (company.effectiveTier == 'PRO') {
      final text = company.proUntil == null ? 'PRO ($limit)' : 'PRO hasta ${formatPlanDate(company.proUntil)} ($limit)';
      return _chip(text, Colors.amber.shade800);
    }
    final expired = company.tier == 'PRO';
    final text = expired ? 'GRATIS (PRO vencido ${formatPlanDate(company.proUntil)})' : 'GRATIS ($limit)';
    return _chip(text, Colors.blueGrey);
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
      );
}
