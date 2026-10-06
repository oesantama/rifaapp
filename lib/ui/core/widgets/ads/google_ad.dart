/// Google ads banner by platform: AdMob (Android/iOS), AdSense (web), none elsewhere (Windows).
export 'google_ad_stub.dart' if (dart.library.html) 'google_ad_web.dart' if (dart.library.io) 'google_ad_mobile.dart';
