import 'package:flutter/material.dart';

/// Icons and colors for sale channels. The list of channels itself comes from the server
/// (SuperAdmin master data); these helpers only turn its icon key / hex color into widgets.
class SaleChannels {
  static const Map<String, IconData> icons = {
    'facebook': Icons.facebook,
    'chat': Icons.chat,
    'family': Icons.family_restroom,
    'handshake': Icons.handshake_outlined,
    'voice': Icons.record_voice_over_outlined,
    'instagram': Icons.camera_alt_outlined,
    'tiktok': Icons.music_note,
    'phone': Icons.phone_in_talk_outlined,
    'store': Icons.storefront_outlined,
    'email': Icons.email_outlined,
    'web': Icons.language,
    'more': Icons.more_horiz,
  };

  static const Map<String, String> iconLabels = {
    'facebook': 'Facebook',
    'chat': 'Chat / WhatsApp',
    'family': 'Familia',
    'handshake': 'Conocido',
    'voice': 'Voz a voz',
    'instagram': 'Instagram',
    'tiktok': 'TikTok',
    'phone': 'Llamada',
    'store': 'Punto físico',
    'email': 'Correo',
    'web': 'Página web',
    'more': 'Otro',
  };

  static IconData iconFor(String key) => icons[key] ?? Icons.more_horiz;

  static Color colorFrom(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return value == null ? const Color(0xFF64748B) : Color(0xFF000000 | value);
  }
}
