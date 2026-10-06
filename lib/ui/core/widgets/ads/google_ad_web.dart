import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

final Set<String> _registered = {};

/// Web: Google AdSense banner (needs an approved AdSense account for the site's domain).
Widget? buildGoogleAd(Map<String, dynamic> config) {
  final client = (config['adsenseClient'] ?? '').toString();
  final slot = (config['adsenseSlot'] ?? '').toString();
  if (client.isEmpty || slot.isEmpty) return null;
  final viewType = 'adsense-$client-$slot';
  if (_registered.add(viewType)) {
    if (html.document.querySelector('script[data-adsense]') == null) {
      html.document.head!.append(html.ScriptElement()
        ..async = true
        ..src = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=$client'
        ..setAttribute('crossorigin', 'anonymous')
        ..setAttribute('data-adsense', '1'));
    }
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int id) {
      final ins = html.Element.tag('ins')
        ..className = 'adsbygoogle'
        ..style.display = 'block'
        ..style.width = '100%'
        ..style.height = '90px'
        ..setAttribute('data-ad-client', client)
        ..setAttribute('data-ad-slot', slot)
        ..setAttribute('data-ad-format', 'horizontal')
        ..setAttribute('data-full-width-responsive', 'true');
      final push = html.ScriptElement()..text = '(adsbygoogle = window.adsbygoogle || []).push({});';
      return html.DivElement()
        ..style.width = '100%'
        ..style.height = '90px'
        ..append(ins)
        ..append(push);
    });
  }
  return SizedBox(height: 90, child: HtmlElementView(viewType: viewType));
}
