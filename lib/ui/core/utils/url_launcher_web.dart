import 'dart:html' as html;
import 'dart:js' as js;

void openWebWindow(String url) {
  try {
    html.window.open(url, '_blank');
  } catch (_) {}
}

void printPage() {
  try {
    html.window.print();
  } catch (_) {}
}

void reloadPage() {
  try {
    // hardReload (index.html) borra service workers y cachés antes de recargar
    js.context.callMethod('hardReload');
  } catch (_) {
    try {
      html.window.location.reload();
    } catch (_) {}
  }
}

void promptPwaInstall() {
  try {
    js.context.callMethod('promptPWAInstall');
  } catch (_) {}
}

void downloadApk() {
  try {
    final anchor = html.AnchorElement(href: '/descargar-apk')
      ..setAttribute('download', 'RifaMaster.apk')
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  } catch (_) {
    html.window.open('/descargar-apk', '_self');
  }
}

/// Opens the WhatsApp app without leaving a blank tab behind (wa.me in a new tab only redirects to
/// the app and stays empty). Desktop: the app is launched from a hidden frame; phones: from this
/// page (the browser asks to open WhatsApp and the app stays here). If the page never loses focus
/// (no app installed), [fallbackUrl] (WhatsApp Web / wa.me) opens in one reusable tab.
void openWhatsAppApp(String appUrl, String fallbackUrl) {
  try {
    final ua = html.window.navigator.userAgent.toLowerCase();
    final isPhone = ua.contains('android') || ua.contains('iphone') || ua.contains('ipad');
    var appOpened = false;
    void markOpened(html.Event _) => appOpened = true;
    final blurSub = html.window.onBlur.listen(markOpened);
    final hiddenSub = html.document.onVisibilityChange.listen((e) {
      if (html.document.hidden == true) markOpened(e);
    });

    html.IFrameElement? frame;
    if (isPhone) {
      html.window.location.href = appUrl;
    } else {
      frame = html.IFrameElement()
        ..style.display = 'none'
        ..src = appUrl;
      html.document.body?.append(frame);
    }

    Future.delayed(const Duration(milliseconds: 2500), () {
      blurSub.cancel();
      hiddenSub.cancel();
      frame?.remove();
      if (!appOpened) html.window.open(fallbackUrl, 'rifamaster_whatsapp');
    });
  } catch (_) {
    html.window.open(fallbackUrl, 'rifamaster_whatsapp');
  }
}
