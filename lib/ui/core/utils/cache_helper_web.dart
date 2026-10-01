import 'dart:html' as html;

void clearAppCacheAndReload() {
  try {
    html.window.localStorage.clear();
    html.window.sessionStorage.clear();
  } catch (_) {}

  try {
    final sw = html.window.navigator.serviceWorker;
    if (sw != null) {
      sw.getRegistrations().then((registrations) {
        for (final registration in registrations) {
          registration.unregister();
        }
      });
    }
  } catch (_) {}

  try {
    html.window.location.reload();
  } catch (_) {}
}
