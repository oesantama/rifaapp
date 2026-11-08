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

/// Elige una imagen y la devuelve como data URL JPEG con el lado mayor limitado a [maxSide].
///
/// Pensado para Safari/iPhone y celulares en general:
///  • el <input type="file"> se agrega al documento (en iOS, si queda suelto el evento "change" puede no llegar
///    y el selector parece "no hacer nada");
///  • se detecta la cancelación del selector para no dejar la pantalla esperando;
///  • la foto se reduce con el propio navegador (canvas): una foto de 12 MP no se decodifica en Dart (en iOS
///    esto congelaba o cerraba la pestaña) y se corrige la orientación automáticamente.
Future<String?> pickImageBase64({int maxSide = 2400}) async {
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..style.display = 'none';
  html.document.body?.append(input);

  final completer = Completer<String?>();
  void finish(String? value) {
    if (!completer.isCompleted) completer.complete(value);
    input.remove();
  }

  input.onChange.listen((_) async {
    final files = input.files;
    if (files == null || files.isEmpty) return finish(null);
    try {
      finish(await _readImageFile(files.first, maxSide));
    } catch (_) {
      finish(null);
    }
  });
  // El usuario cerró el selector sin elegir nada (Safari y Chrome recientes emiten "cancel")
  input.addEventListener('cancel', (_) => finish(null));
  input.click();

  return completer.future;
}

Future<String?> _readImageFile(html.File file, int maxSide) async {
  final url = html.Url.createObjectUrlFromBlob(file);
  try {
    final image = html.ImageElement()..src = url;
    await image.onLoad.first.timeout(const Duration(seconds: 25));
    final w = image.naturalWidth;
    final h = image.naturalHeight;
    if (w > 0 && h > 0) {
      final scale = (maxSide / (w > h ? w : h)).clamp(0.0, 1.0);
      final cw = (w * scale).round();
      final ch = (h * scale).round();
      final canvas = html.CanvasElement(width: cw, height: ch);
      canvas.context2D.drawImageScaled(image, 0, 0, cw, ch);
      final dataUrl = canvas.toDataUrl('image/jpeg', 0.85);
      if (dataUrl.startsWith('data:image/jpeg')) return dataUrl;
    }
  } catch (_) {
    // El navegador no pudo decodificarla: se usa el archivo tal cual
  } finally {
    html.Url.revokeObjectUrl(url);
  }
  final reader = html.FileReader()..readAsDataUrl(file);
  await reader.onLoadEnd.first;
  return reader.result as String?;
}
