import 'package:file_picker/file_picker.dart';
import 'dart:convert';

Future<String?> pickCsvTextContent() async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv', 'txt', 'xlsx', 'xls'],
    withData: true,
  );
  if (result != null && result.files.isNotEmpty) {
    final bytes = result.files.first.bytes;
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
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
    withData: true,
  );
  if (result != null && result.files.isNotEmpty) {
    return result.files.first.bytes;
  }
  return null;
}

Future<String?> pickImageBase64() async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
  );
  if (result != null && result.files.isNotEmpty) {
    final bytes = result.files.first.bytes;
    if (bytes != null) {
      String ext = result.files.first.extension?.toLowerCase() ?? 'png';
      String base64Str = base64Encode(bytes);
      return 'data:image/$ext;base64,$base64Str';
    }
  }
  return null;
}
