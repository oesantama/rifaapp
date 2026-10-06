import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

bool _initialized = false;

/// Android / iOS: Google AdMob banner. Other platforms (Windows, Linux, macOS): none.
Widget? buildGoogleAd(Map<String, dynamic> config) {
  if (!Platform.isAndroid && !Platform.isIOS) return null;
  final unitId = (Platform.isAndroid ? config['admobAndroidBannerId'] : config['admobIosBannerId'] ?? '').toString();
  if (unitId.isEmpty) return null;
  if (!_initialized) {
    _initialized = true;
    MobileAds.instance.initialize();
  }
  return _AdMobBanner(unitId: unitId);
}

class _AdMobBanner extends StatefulWidget {
  final String unitId;

  const _AdMobBanner({required this.unitId});

  @override
  State<_AdMobBanner> createState() => _AdMobBannerState();
}

class _AdMobBannerState extends State<_AdMobBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = BannerAd(
      adUnitId: widget.unitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => mounted ? setState(() => _loaded = true) : null,
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('AdMob: no se pudo cargar el anuncio: $error');
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}
