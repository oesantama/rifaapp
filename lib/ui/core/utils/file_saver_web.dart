import 'dart:html' as html;
import 'dart:convert';

void saveAndDownloadFile(String filename, String content, {String? mimeType}) {
  final bytes = utf8.encode(content);
  saveAndDownloadBytes(filename, bytes, mimeType: mimeType ?? 'text/csv;charset=utf-8');
}

void saveAndDownloadBytes(String filename, List<int> bytes, {String? mimeType}) {
  final type = mimeType ?? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  final blob = html.Blob([bytes], type);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';

  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
