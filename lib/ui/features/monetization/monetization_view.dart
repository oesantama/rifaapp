import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/monetization/app_config_view_model.dart';
import 'package:rifaapp/ui/features/monetization/monetization_tabs.dart';
import 'package:rifaapp/ui/features/legal/legal_widgets.dart';

/// SuperAdmin monetization: income from subscriptions, companies' plans and payments, and the
/// settings (prices, demo mode, "upgrade to PRO" banner and Google ads).
class MonetizationView extends StatelessWidget {
  const MonetizationView({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).cardColor,
            child: TabBar(
              tabs: [
                const Tab(icon: Icon(Icons.insights, size: 18), text: 'Ingresos', iconMargin: EdgeInsets.zero),
                Tab(
                    icon: const Icon(Icons.apartment, size: 18),
                    text: isMobile ? 'Pagos' : 'Empresas y pagos',
                    iconMargin: EdgeInsets.zero),
                Tab(icon: const Icon(Icons.tune, size: 18), text: isMobile ? 'Ajustes' : 'Configuración', iconMargin: EdgeInsets.zero),
              ],
            ),
          ),
          const Expanded(child: TabBarView(children: [IncomeTab(), CompanyPlansTab(), MonetizationSettingsTab()])),
        ],
      ),
    );
  }
}

/// Prices, demo mode, the "upgrade to PRO" banner and Google ads.
class MonetizationSettingsTab extends StatefulWidget {
  const MonetizationSettingsTab({super.key});

  @override
  State<MonetizationSettingsTab> createState() => _MonetizationSettingsTabState();
}

class _MonetizationSettingsTabState extends State<MonetizationSettingsTab> {
  final _fields = <String, TextEditingController>{
    for (final k in [
      'adTitle',
      'adText',
      'upgradeTitle',
      'upgradeText',
      'priceText',
      'contactWhatsApp',
      'contactUrl',
      'monthlyPrice',
      'quarterlyPrice',
      'semiannualPrice',
      'yearlyPrice',
      'admobAndroidBannerId',
      'admobIosBannerId',
      'adsenseClient',
      'adsenseSlot',
    ])
      k: TextEditingController(),
  };
  bool _demoEnabled = true;
  bool _adsEnabled = false;
  String? _lastDemoReset;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply(Map<String, dynamic> data) {
    for (final e in _fields.entries) {
      e.value.text = (data[e.key] ?? '').toString();
    }
    _demoEnabled = data['demoEnabled'] != false;
    _adsEnabled = data['adsEnabled'] == true;
    for (final k in ['monthlyPrice', 'quarterlyPrice', 'semiannualPrice', 'yearlyPrice']) {
      if (_fields[k]!.text == '0') _fields[k]!.text = '';
    }
    _lastDemoReset = data['lastDemoReset'];
  }

  Future<void> _load() async {
    try {
      final data = await RaffleRepository().fetchMonetization();
      if (mounted) setState(() => _apply(data));
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: error ? AppTheme.dangerRose : AppTheme.secondaryEmerald, content: Text(text)),
    );
  }

  Future<void> _save(Map<String, dynamic> data, String done) async {
    setState(() => _saving = true);
    try {
      final saved = await RaffleRepository().saveMonetization(data);
      if (!mounted) return;
      setState(() => _apply(saved));
      context.read<AppConfigViewModel>().load();
      _snack(done);
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetDemo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Reiniciar la demo?'),
        content: const Text('Se borran los cambios hechos en la Empresa Demo y se vuelven a cargar los datos de ejemplo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reiniciar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final data = await RaffleRepository().resetDemo();
      if (mounted) setState(() => _lastDemoReset = data['lastDemoReset']);
      _snack('Demo reiniciada con datos de ejemplo.');
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  /// "Equivale a $44.967/mes • ahorra 10 %" against the 1-month price.
  String? _priceHelp(String key, int months) {
    final price = int.tryParse(_fields[key]!.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (price <= 0 || months == 1) return null;
    final perMonth = price / months;
    final monthly = int.tryParse(_fields['monthlyPrice']!.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final money = NumberFormat.currency(locale: 'es_CO', symbol: '\$', decimalDigits: 0);
    final saving = monthly > 0 ? (1 - perMonth / monthly) * 100 : 0;
    return 'Equivale a ${money.format(perMonth)}/mes${saving > 0.5 ? ' • ahorra ${saving.round()} %' : ''}';
  }

  Widget _field(String key, String label, {String? hint, int maxLines = 1, TextInputType? keyboard}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _fields[key],
          maxLines: maxLines,
          keyboardType: keyboard,
          decoration:
              InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), alignLabelWithHint: maxLines > 1),
        ),
      );

  Widget _section(IconData icon, String title, String subtitle, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(icon, color: AppTheme.primaryBlue),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              ]),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final isMobile = MediaQuery.of(context).size.width < 600;
    final lastReset = DateTime.tryParse(_lastDemoReset ?? '');

    return ListView(
      padding: EdgeInsets.fromLTRB(isMobile ? 12 : 24, isMobile ? 12 : 24, isMobile ? 12 : 24, 40),
      children: [
        const LegalAdminSection(),
        _section(Icons.sell_outlined, 'Precios del plan PRO', 'Se proponen al registrar pagos y se muestran a las empresas.', [
          for (final (key, label, months) in [
            ('monthlyPrice', '1 mes', 1),
            ('quarterlyPrice', '3 meses', 3),
            ('semiannualPrice', '6 meses', 6),
            ('yearlyPrice', '1 año', 12),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _fields[key],
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Precio $label',
                  prefixText: '\$ ',
                  border: const OutlineInputBorder(),
                  helperText: _priceHelp(key, months),
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: _saving
                  ? null
                  : () => _save({
                        for (final k in ['monthlyPrice', 'quarterlyPrice', 'semiannualPrice', 'yearlyPrice'])
                          k: _fields[k]!.text.replaceAll(RegExp(r'[^0-9]'), ''),
                      }, 'Precios guardados.'),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar precios'),
            ),
          ),
        ]),
        _section(Icons.science_outlined, 'Modo demo', 'Empresa de prueba con datos de ejemplo; se reinicia sola cada 48 horas.', [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar "Probar modo demo" en el inicio de sesión'),
            subtitle: Text(_demoEnabled
                ? 'Activo: cualquiera puede entrar a la Empresa Demo.'
                : 'Apagado: no aparece el botón y se cierran las sesiones de la demo.'),
            value: _demoEnabled,
            onChanged: _saving ? null : (v) => _save({'demoEnabled': v}, v ? 'Modo demo activado.' : 'Modo demo apagado.'),
          ),
          if (lastReset != null)
            Text('Último reinicio: ${DateFormat('dd/MM/yyyy hh:mm a').format(lastReset.toLocal())}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child:
                OutlinedButton.icon(onPressed: _resetDemo, icon: const Icon(Icons.restart_alt), label: const Text('Reiniciar demo ahora')),
          ),
        ]),
        _section(Icons.campaign_outlined, 'Anuncio "Pásate a PRO"', 'Lo ven las empresas con plan Gratis (abajo en la app) y la demo.', [
          _field('adTitle', 'Título del anuncio'),
          _field('adText', 'Texto del anuncio', maxLines: 2),
          _field('upgradeTitle', 'Título de la ventana "Actualizar a PRO"'),
          _field('upgradeText', 'Beneficios del plan PRO', maxLines: 3),
          _field('priceText', 'Precio (opcional)', hint: 'Ej: \$49.900 al mes'),
          _field('contactWhatsApp', 'WhatsApp para contratar (opcional)', hint: 'Ej: 3001234567', keyboard: TextInputType.phone),
          _field('contactUrl', 'Enlace para contratar (opcional)', hint: 'https://...', keyboard: TextInputType.url),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: _saving
                  ? null
                  : () => _save({
                        for (final k in ['adTitle', 'adText', 'upgradeTitle', 'upgradeText', 'priceText', 'contactWhatsApp', 'contactUrl'])
                          k: _fields[k]!.text,
                      }, 'Anuncio guardado.'),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar anuncio'),
            ),
          ),
        ]),
        _section(
          Icons.ads_click,
          'Publicidad de Google',
          'Anuncios reales para las empresas con plan Gratis. Hoy funcionan en la web (AdSense); en Android e iOS (AdMob) se activarán '
              'en una próxima versión, y en Windows no existen. Mientras tanto se muestra el anuncio "Pásate a PRO". '
              'Las ganancias se consultan en los paneles de Google.',
          [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar anuncios de Google'),
              value: _adsEnabled,
              onChanged: (v) => setState(() => _adsEnabled = v),
            ),
            _field('admobAndroidBannerId', 'AdMob • ID de bloque de anuncios Android', hint: 'ca-app-pub-XXXX/YYYY'),
            _field('admobIosBannerId', 'AdMob • ID de bloque de anuncios iOS', hint: 'ca-app-pub-XXXX/YYYY'),
            _field('adsenseClient', 'AdSense • ID de editor (web)', hint: 'ca-pub-XXXXXXXX'),
            _field('adsenseSlot', 'AdSense • ID del bloque (web)', hint: '1234567890'),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton.icon(
                onPressed: _saving
                    ? null
                    : () => _save({
                          'adsEnabled': _adsEnabled,
                          for (final k in ['admobAndroidBannerId', 'admobIosBannerId', 'adsenseClient', 'adsenseSlot']) k: _fields[k]!.text,
                        }, 'Publicidad de Google guardada.'),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Guardar publicidad'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
