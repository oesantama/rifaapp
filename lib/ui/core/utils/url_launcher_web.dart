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
