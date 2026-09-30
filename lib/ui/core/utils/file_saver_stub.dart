import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Android / iOS / desktop app: there is no browser download, so the file is written to a
// temporary folder and the system share sheet opens. From there the user saves it
// (Files, Drive, Photos) or sends it (WhatsApp, email).

Future<void> saveAndDownloadFile(String filename, String content, {String? mimeType}) {
  return saveAndDownloadBytes(filename, utf8.encode(content), mimeType: mimeType ?? 'text/csv');
}

Future<void> saveAndDownloadBytes(String filename, List<int> bytes, {String? mimeType}) async {
  try {
    final dir = await getTemporaryDirectory();
    final safeName = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType, name: safeName)],
        subject: safeName,
        title: safeName,
      ),
    );
  } catch (e) {
    log('No se pudo guardar/compartir $filename: $e');
    rethrow;
  }
}
