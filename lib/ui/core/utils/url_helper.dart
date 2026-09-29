import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'url_launcher_helper.dart' as web_launcher;

class UrlHelper {
  /// Opens a URL in a new browser tab or external application
  static void openUrl(String url) {
    if (url.trim().isEmpty) return;
    String cleanUrl = url.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'https://$cleanUrl';
    }

    if (kIsWeb) {
      try {
        web_launcher.openWebWindow(cleanUrl);
      } catch (e) {
        debugPrint('Error opening window on web: $e');
      }
    } else {
      // Mobile / Desktop fallback via Clipboard if url_launcher is not native
      Clipboard.setData(ClipboardData(text: cleanUrl));
    }
  }

  /// Copy text to clipboard
  static Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Detect platform type from URL
  static String getLinkType(String url) {
    final lower = url.toLowerCase().trim();
    if (lower.contains('drive.google.com') || lower.contains('docs.google.com')) {
      return 'google_drive';
    } else if (lower.contains('photos.google.com') || lower.contains('photos.app.goo.gl')) {
      return 'google_photos';
    } else if (lower.contains('1drv.ms') || lower.contains('onedrive.live.com') || lower.contains('sharepoint.com')) {
      return 'onedrive';
    } else if (lower.contains('dropbox.com')) {
      return 'dropbox';
    } else if (lower.contains('imgur.com')) {
      return 'imgur';
    } else if (lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.png') ||
        lower.contains('.webp') ||
        lower.contains('.gif')) {
      return 'direct_image';
    }
    return 'generic_web';
  }

  /// Returns user-friendly name of the platform
  static String getLinkTypeName(String url) {
    switch (getLinkType(url)) {
      case 'google_drive':
        return 'Google Drive';
      case 'google_photos':
        return 'Google Photos';
      case 'onedrive':
        return 'Microsoft OneDrive';
      case 'dropbox':
        return 'Dropbox';
      case 'imgur':
        return 'Imgur';
      case 'direct_image':
        return 'Imagen Directa';
      default:
        return 'Enlace Web';
    }
  }

  /// Convert cloud URLs to direct viewable image URLs if possible
  static String? getDirectImageUrl(String url) {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return null;

    final type = getLinkType(cleanUrl);

    if (type == 'google_drive') {
      // Extract Google Drive File ID
      // Patterns: /file/d/FILE_ID/view , id=FILE_ID
      RegExp regExp1 = RegExp(r'/file/d/([a-zA-Z0-9_-]+)');
      RegExp regExp2 = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)');

      Match? match = regExp1.firstMatch(cleanUrl) ?? regExp2.firstMatch(cleanUrl);
      if (match != null && match.groupCount >= 1) {
        String fileId = match.group(1)!;
        // Google's direct CDN image URL
        return 'https://lh3.googleusercontent.com/d/$fileId';
      }
    } else if (type == 'dropbox') {
      // Convert dl=0 to raw=1 for direct image streaming
      if (cleanUrl.contains('dl=0')) {
        return cleanUrl.replaceAll('dl=0', 'raw=1');
      } else if (!cleanUrl.contains('raw=1')) {
        return cleanUrl.contains('?') ? '$cleanUrl&raw=1' : '$cleanUrl?raw=1';
      }
      return cleanUrl;
    } else if (type == 'imgur') {
      if (!cleanUrl.contains('i.imgur.com') && cleanUrl.contains('imgur.com/')) {
        final id = cleanUrl.split('imgur.com/').last.split('.').first.split('?').first;
        if (id.isNotEmpty) {
          return 'https://i.imgur.com/$id.png';
        }
      }
      return cleanUrl;
    } else if (type == 'direct_image' || cleanUrl.startsWith('data:image')) {
      return cleanUrl;
    }

    return null;
  }

  /// Returns Google Drive iframe embed URL if applicable
  static String? getGoogleDriveEmbedUrl(String url) {
    final cleanUrl = url.trim();
    if (getLinkType(cleanUrl) == 'google_drive') {
      RegExp regExp1 = RegExp(r'/file/d/([a-zA-Z0-9_-]+)');
      RegExp regExp2 = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)');

      Match? match = regExp1.firstMatch(cleanUrl) ?? regExp2.firstMatch(cleanUrl);
      if (match != null && match.groupCount >= 1) {
        String fileId = match.group(1)!;
        return 'https://drive.google.com/file/d/$fileId/preview';
      }
    }
    return null;
  }
}
