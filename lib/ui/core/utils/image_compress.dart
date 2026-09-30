import 'dart:convert';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Reduces an uploaded template image before saving it: scales the longest side down to
/// [maxSide] pixels and re-encodes it as JPEG. Keeps the original when it is already smaller.
/// A 3 MB photo typically ends up around 300-600 KB with no visible loss when printing.
String compressImageDataUri(String dataUri, {int maxSide = 2400, int quality = 85}) {
  final comma = dataUri.indexOf(',');
  if (!dataUri.startsWith('data:image') || comma < 0) return dataUri;
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
    final jpg = img.encodeJpg(image, quality: quality);
    if (jpg.length >= original.length) return dataUri;
    return 'data:image/jpeg;base64,${base64Encode(jpg)}';
  } catch (_) {
    return dataUri;
  }
}
