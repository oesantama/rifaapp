/// Google ads banner by platform: AdSense on web; none elsewhere (Android/iOS/Windows show the
/// platform's own "upgrade to PRO" banner). AdMob was removed in 3.0.1 because it closed the Android
/// app at launch; add it back only after testing on a real device with the real AdMob app id.
export 'google_ad_stub.dart' if (dart.library.html) 'google_ad_web.dart';
