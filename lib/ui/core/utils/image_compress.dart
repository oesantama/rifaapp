import 'dart:convert';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Peso objetivo de una foto de soporte (caracteres en base64, ≈1.1 MB) y peso máximo aceptado (≈6 MB).
const int proofTargetChars = 1500000;
const int proofMaxChars = 8000000;

/// La foto sigue pesando demasiado aun después de reducirla: hay que bajarle la calidad o el tamaño antes de adjuntarla.
class ImageTooHeavyException implements Exception {
  const ImageTooHeavyException();
  String get message => 'La imagen pesa demasiado (máximo unos 6 MB). Bájele la calidad o el tamaño, o tome una captura de pantalla del comprobante, e intente de nuevo.';
  @override
  String toString() => message;
}

/// Prepara una foto de soporte: la reduce sin perder legibilidad y, si todavía pasa el límite, avisa con [ImageTooHeavyException].
String prepareProofImage(String dataUri, {int maxSide = 1600}) {
  final out = compressImageDataUri(dataUri, maxSide: maxSide, quality: 90);
  if (out.length > proofMaxChars) throw const ImageTooHeavyException();
  return out;
}

/// Reduces an uploaded template image before saving it: scales the longest side down to
/// [maxSide] pixels and re-encodes it as JPEG. Keeps the original when it is already smaller.
/// A 3 MB photo typically ends up around 300-600 KB with no visible loss when printing.
String compressImageDataUri(String dataUri, {int maxSide = 2400, int quality = 85}) {
  final comma = dataUri.indexOf(',');
  if (!dataUri.startsWith('data:image') || comma < 0) return dataUri;
  // Ya viene reducida por el navegador y es liviana: no hace falta decodificarla otra vez en Dart
  if (dataUri.startsWith('data:image/jpeg') && dataUri.length < 700000) return dataUri;
  try {
    final original = base64Decode(dataUri.substring(comma + 1));
    final decoded = img.decodeImage(original);
    if (decoded == null) return dataUri;

    var image = decoded;
    final longest = math.max(image.width, image.height);
    if (longest > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
    }
    // Peso objetivo ≈1.1 MB: solo si hace falta se baja la calidad poco a poco (hasta 70) y, si aun así pesa, el tamaño
    var q = quality;
    var jpg = img.encodeJpg(image, quality: q);
    while (jpg.length * 4 / 3 > proofTargetChars && q > 70) {
      q = math.max(70, q - 7);
      jpg = img.encodeJpg(image, quality: q);
    }
    while (jpg.length * 4 / 3 > proofTargetChars && math.max(image.width, image.height) > 1000) {
      image = image.width >= image.height
          ? img.copyResize(image, width: (image.width * 0.88).round(), interpolation: img.Interpolation.average)
          : img.copyResize(image, height: (image.height * 0.88).round(), interpolation: img.Interpolation.average);
      jpg = img.encodeJpg(image, quality: q);
    }
    if (jpg.length >= original.length) return dataUri;
    return 'data:image/jpeg;base64,${base64Encode(jpg)}';
  } catch (_) {
    return dataUri;
  }
}
