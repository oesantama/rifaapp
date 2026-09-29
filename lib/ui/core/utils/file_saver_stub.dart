import 'dart:developer';

void saveAndDownloadFile(String filename, String content, {String? mimeType}) {
  log('File download for $filename (stub): ${content.length} bytes');
}

void saveAndDownloadBytes(String filename, List<int> bytes, {String? mimeType}) {
  log('Bytes download for $filename (stub): ${bytes.length} bytes');
}
