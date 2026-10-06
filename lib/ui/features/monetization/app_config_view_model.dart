import 'package:flutter/foundation.dart';
import 'package:rifaapp/data/repositories/raffle_repository.dart';

/// Public settings set by the SuperAdmin: whether the demo mode is offered on the login screen and
/// the texts / contact of the "upgrade to PRO" banner. Loaded without a session.
class AppConfigViewModel extends ChangeNotifier {
  final RaffleRepository _repository;

  AppConfigViewModel({RaffleRepository? repository}) : _repository = repository ?? RaffleRepository();

  bool _demoEnabled = false;
  bool get demoEnabled => _demoEnabled;

  /// Download link of the latest Android app (GitHub release, later Google Play).
  String _androidApkUrl = 'https://github.com/oesantama/rifaapp/releases/latest/download/rifa-master.apk';
  String get androidApkUrl => _androidApkUrl;

  Map<String, dynamic> _ad = const {};
  String _adValue(String key, String fallback) {
    final v = (_ad[key] ?? '').toString().trim();
    return v.isEmpty ? fallback : v;
  }

  String get adTitle => _adValue('title', 'Publicidad • Versión Gratuita');
  String get adText => _adValue('text', 'Pasa a la versión PRO para eliminar anuncios y desbloquear rifas ilimitadas.');
  String get upgradeTitle => _adValue('upgradeTitle', 'Actualizar a RifaApp PRO');
  String get upgradeText => _adValue('upgradeText', '');
  String get priceText => _adValue('priceText', '');
  String get contactWhatsApp => _adValue('contactWhatsApp', '');
  String get contactUrl => _adValue('contactUrl', '');

  /// Google ads ids set by the SuperAdmin (null = only the platform's own banner).
  Map<String, dynamic>? _googleAds;
  Map<String, dynamic>? get googleAds => _googleAds;

  Future<void> load() async {
    try {
      final data = await _repository.fetchAppConfig();
      _demoEnabled = data['demoEnabled'] == true;
      if ((data['androidApkUrl'] ?? '').toString().isNotEmpty) _androidApkUrl = data['androidApkUrl'].toString();
      _ad = data['ad'] is Map ? Map<String, dynamic>.from(data['ad']) : const {};
      _googleAds = data['googleAds'] is Map ? Map<String, dynamic>.from(data['googleAds']) : null;
      notifyListeners();
    } catch (e) {
      debugPrint('No se pudo cargar la configuración pública: $e');
    }
  }
}
