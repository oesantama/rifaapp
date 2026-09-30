import 'package:flutter/material.dart';

/// How the buyer was reached or the ticket was sold. Must match SALE_CHANNELS in backend/server.js.
class SaleChannels {
  static const List<String> all = ['Facebook', 'WhatsApp', 'Familiar', 'Conocido', 'Voz a voz', 'Otro'];

  static IconData icon(String channel) {
    switch (channel) {
      case 'Facebook':
        return Icons.facebook;
      case 'WhatsApp':
        return Icons.chat;
      case 'Familiar':
        return Icons.family_restroom;
      case 'Conocido':
        return Icons.handshake_outlined;
      case 'Voz a voz':
        return Icons.record_voice_over_outlined;
      default:
        return Icons.more_horiz;
    }
  }

  static Color color(String channel) {
    switch (channel) {
      case 'Facebook':
        return const Color(0xFF1877F2);
      case 'WhatsApp':
        return const Color(0xFF25D366);
      case 'Familiar':
        return const Color(0xFFEC4899);
      case 'Conocido':
        return const Color(0xFF8B5CF6);
      case 'Voz a voz':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF64748B);
    }
  }
}
