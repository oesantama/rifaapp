import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rifaapp/ui/core/utils/image_compress.dart';

String _noisyPng(int w, int h) {
  final rnd = math.Random(7);
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      // texto simulado + ruido, como una captura con fondo detallado
      final v = ((x ~/ 6 + y ~/ 9) % 2 == 0 ? 30 : 225) + rnd.nextInt(30);
      image.setPixelRgb(x, y, v.clamp(0, 255), v.clamp(0, 255), v.clamp(0, 255));
    }
  }
  return 'data:image/png;base64,${base64Encode(img.encodePng(image))}';
}

void main() {
  test('una captura pesada se reduce al peso objetivo conservando el tamaño legible', () {
    final big = _noisyPng(1200, 2600);
    expect(big.length, greaterThan(proofTargetChars));
    final out = prepareProofImage(big, maxSide: 1600);
    expect(out.startsWith('data:image/jpeg'), isTrue);
    expect(out.length, lessThanOrEqualTo(proofTargetChars + 50000));
    final decoded = img.decodeImage(base64Decode(out.substring(out.indexOf(',') + 1)))!;
    // el lado mayor no baja de 1000 px: el texto sigue legible
    expect(math.max(decoded.width, decoded.height), greaterThanOrEqualTo(1000));
  });

  test('una imagen liviana no se toca', () {
    final small = _noisyPng(200, 300);
    final jpg = 'data:image/jpeg;base64,${base64Encode(img.encodeJpg(img.decodeImage(base64Decode(small.substring(small.indexOf(',') + 1)))!, quality: 90))}';
    expect(prepareProofImage(jpg), jpg);
  });

  test('si no se puede reducir y pasa el límite, avisa', () {
    final heavy = 'data:image/heic;base64,${'A' * (proofMaxChars + 10)}';
    expect(() => prepareProofImage(heavy), throwsA(isA<ImageTooHeavyException>()));
  });
}
