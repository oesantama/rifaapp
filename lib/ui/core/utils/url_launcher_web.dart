import 'dart:html' as html;

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
    html.window.location.reload();
  } catch (_) {}
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
