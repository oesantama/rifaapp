import 'dart:html' as html;
import 'dart:async';
import 'dart:convert';

Future<void> saveAndDownloadFile(String filename, String content, {String? mimeType}) async {
  final bytes = utf8.encode(content);
  await saveAndDownloadBytes(filename, bytes, mimeType: mimeType ?? 'text/csv;charset=utf-8');
}

Future<void> saveAndDownloadBytes(String filename, List<int> bytes, {String? mimeType}) async {
  final type = mimeType ?? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  final blob = html.Blob([bytes], type);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';

  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();

  // Delay revoking the Object URL so the browser download manager can extract the filename attribute
  Timer(const Duration(seconds: 4), () {
    html.Url.revokeObjectUrl(url);
  });
}
