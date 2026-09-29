import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';

Future<String?> pickCsvTextContent() async {
  final uploadInput = html.FileUploadInputElement();
  uploadInput.accept = '.csv,.txt,.xlsx,.xls';
  uploadInput.click();

  final completer = Completer<String?>();
  uploadInput.onChange.listen((e) {
    final files = uploadInput.files;
    if (files != null && files.isNotEmpty) {
      final reader = html.FileReader();
      reader.readAsText(files[0]);
      reader.onLoadEnd.listen((e) {
        completer.complete(reader.result as String?);
      });
    } else {
      completer.complete(null);
    }
  });

  return completer.future;
}

Future<List<int>?> pickFileBytes({List<String> allowedExtensions = const ['xlsx', 'xls', 'csv', 'txt']}) async {
  final uploadInput = html.FileUploadInputElement();
  uploadInput.accept = allowedExtensions.map((e) => '.$e').join(',');
  uploadInput.click();

  final completer = Completer<List<int>?>();
  uploadInput.onChange.listen((e) {
    final files = uploadInput.files;
    if (files != null && files.isNotEmpty) {
      final reader = html.FileReader();
      reader.readAsArrayBuffer(files[0]);
      reader.onLoadEnd.listen((e) {
        final res = reader.result;
        if (res is Uint8List) {
          completer.complete(res.toList());
        } else if (res is ByteBuffer) {
          completer.complete(res.asUint8List().toList());
        } else {
          completer.complete(null);
        }
      });
    } else {
      completer.complete(null);
    }
  });

  return completer.future;
}

Future<String?> pickImageBase64() async {
  final uploadInput = html.FileUploadInputElement();
  uploadInput.accept = 'image/*';
  uploadInput.click();

  final completer = Completer<String?>();
  uploadInput.onChange.listen((e) {
    final files = uploadInput.files;
    if (files != null && files.isNotEmpty) {
      final reader = html.FileReader();
      reader.readAsDataUrl(files[0]);
      reader.onLoadEnd.listen((e) {
        completer.complete(reader.result as String?);
      });
    } else {
      completer.complete(null);
    }
  });

  return completer.future;
}
