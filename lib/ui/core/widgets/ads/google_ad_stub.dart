import 'package:flutter/widgets.dart';

/// Platforms without Google ads support (e.g. Windows): nothing; the caller shows its own banner.
Widget? buildGoogleAd(Map<String, dynamic> config) => null;
