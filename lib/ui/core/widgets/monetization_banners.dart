import 'package:flutter/material.dart';
import 'package:rifaapp/ui/core/widgets/ads/google_ad.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rifaapp/ui/core/utils/whatsapp_helper.dart';
import 'package:rifaapp/ui/features/monetization/app_config_view_model.dart';
import 'package:provider/provider.dart';
import 'package:rifaapp/ui/core/theme.dart';
import 'package:rifaapp/ui/features/auth/view_models/auth_view_model.dart';

/// Banner que se muestra en la parte superior cuando el usuario está en Modo Demo.
class DemoBannerWidget extends StatelessWidget {
  const DemoBannerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final authVM = Provider.of<AuthViewModel>(context);
    if (!authVM.isDemo) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: Colors.amber.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.science_outlined, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'MODO DEMO DE PRUEBA: Esta cuenta se restablece automáticamente cada 48 horas.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget de publicidad / banner de upgrade a versión PRO.
class AdBannerWidget extends StatelessWidget {
  const AdBannerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final authVM = Provider.of<AuthViewModel>(context);
    if (!authVM.showAds) return const SizedBox.shrink();
    final config = context.watch<AppConfigViewModel>();
    // Google ads (AdMob on phones, AdSense on web) when the SuperAdmin configured them
    final googleAd = config.googleAds != null ? buildGoogleAd(config.googleAds!) : null;
    if (googleAd != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: googleAd),
          TextButton.icon(
            onPressed: () => _showUpgradeDialog(context),
            icon: const Icon(Icons.workspace_premium, size: 16, color: Colors.amber),
            label: const Text('Quitar anuncios con PRO', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E293B),
            const Color(0xFF0F172A),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.star_rounded, color: Colors.amber, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  config.adTitle,
                  style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  config.adText,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              _showUpgradeDialog(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('PRO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  static void _showUpgradeDialog(BuildContext context) {
    final config = context.read<AppConfigViewModel>();
    final company = context.read<AuthViewModel>().companyName;
    final benefits = config.upgradeText.trim();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.workspace_premium, color: Colors.amber, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(config.upgradeTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (benefits.isNotEmpty)
              Text(benefits, style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4))
            else ...[
              _buildFeatureRow('🚫 Sin anuncios publicitarios'),
              _buildFeatureRow('🎟️ Rifas y boletas ilimitadas'),
              _buildFeatureRow('👥 Asesores ilimitados'),
            ],
            if (config.priceText.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(config.priceText, style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
            if (config.contactWhatsApp.isEmpty && config.contactUrl.isEmpty) ...[
              const SizedBox(height: 14),
              const Text('Comuníquese con el administrador de la plataforma para activar el plan PRO.',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar', style: TextStyle(color: Colors.grey)),
          ),
          if (config.contactUrl.isNotEmpty)
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(config.contactUrl), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, color: Colors.amber),
              label: const Text('Ver planes', style: TextStyle(color: Colors.amber)),
            ),
          if (config.contactWhatsApp.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                WhatsAppHelper.sendWhatsAppMessage(
                  phone: config.contactWhatsApp,
                  message: 'Hola, quiero activar el plan PRO de RifaApp${company.isNotEmpty ? ' para $company' : ''}.',
                );
              },
              icon: const Icon(Icons.chat),
              label: const Text('Quiero el PRO'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
            ),
        ],
      ),
    );
  }

  static Widget _buildFeatureRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
    );
  }
}
