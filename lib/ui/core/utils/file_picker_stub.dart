import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> _getFileBytes(PlatformFile file) async {
  try {
    return await file.readAsBytes();
  } catch (_) {}
  if (file.path != null) {
    try {
      return await File(file.path!).readAsBytes();
    } catch (_) {}
  }
  return null;
}

Future<String?> pickCsvTextContent() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv', 'txt', 'xlsx', 'xls'],
  );
  if (files.isNotEmpty) {
    final bytes = await _getFileBytes(files.first);
    if (bytes != null) {
      try {
        return utf8.decode(bytes);
      } catch (_) {
        return String.fromCharCodes(bytes);
      }
    }
  }
  return null;
}

Future<List<int>?> pickFileBytes({List<String> allowedExtensions = const ['xlsx', 'xls', 'csv', 'txt']}) async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
  );
  if (files.isNotEmpty) {
    return await _getFileBytes(files.first);
  }
  return null;
}

Future<String?> pickImageBase64() async {
  final files = await FilePicker.pickFiles(
    type: FileType.image,
  );
  if (files.isNotEmpty) {
    final bytes = await _getFileBytes(files.first);
    if (bytes != null) {
      String ext = files.first.extension?.toLowerCase() ?? 'png';
      String base64Str = base64Encode(bytes);
      return 'data:image/$ext;base64,$base64Str';
    }
  }
  return null;
}
