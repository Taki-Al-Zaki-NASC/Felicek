import 'dart:math' as math;
import 'dart:typed_data';

import 'package:felicek/core/utils/watermark.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The watermark is the freelancer's only leverage before a milestone is
/// released, so "it ran without throwing" is not enough — it has to actually
/// change the picture, over the middle of it.
Uint8List _photo(int w, int h, {int shade = 120}) {
  final img.Image image = img.Image(width: w, height: h);
  final math.Random rng = math.Random(3);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final int v = (shade + rng.nextInt(40)).clamp(0, 255);
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}

double _centreDelta(img.Image a, img.Image b) {
  // Sample the middle third — a mark only at the edges would be cropped off.
  int changed = 0, total = 0;
  for (int y = a.height ~/ 3; y < a.height * 2 ~/ 3; y += 3) {
    for (int x = a.width ~/ 3; x < a.width * 2 ~/ 3; x += 3) {
      total++;
      if ((a.getPixel(x, y).luminance - b.getPixel(x, y).luminance).abs() > 6) {
        changed++;
      }
    }
  }
  return total == 0 ? 0 : changed / total;
}

void main() {
  test('a decodable photo comes back watermarked', () {
    final Uint8List original = _photo(1000, 700);
    expect(Watermark.applyToBase64(original), isNotNull);
  });

  test('the mark lands across the middle, not just the edges', () {
    final Uint8List original = _photo(1000, 700);
    final img.Image before = img.decodeImage(original)!;
    final img.Image after = Watermark.apply(original)!;
    // Same dimensions here (under the 1600px cap), so pixels are comparable.
    expect(after.width, before.width);
    expect(_centreDelta(before, after), greaterThan(0.5),
        reason: 'A crop of the centre must still be visibly marked.');
  });

  test('an oversized photo is capped rather than stamped at full size', () {
    final img.Image big = Watermark.apply(_photo(3000, 2000))!;
    expect(math.max(big.width, big.height), lessThanOrEqualTo(1600));
  });

  test('a small image still gets a legible mark', () {
    final Uint8List small = _photo(320, 240);
    final img.Image? out = Watermark.apply(small);
    expect(out, isNotNull);
    expect(_centreDelta(img.decodeImage(small)!, out!), greaterThan(0.3));
  });

  test('rubbish input returns null instead of throwing', () {
    // decodeImage throws RangeError on short buffers rather than returning
    // null, so this is a real crash path, not a hypothetical one.
    expect(Watermark.applyToBase64(Uint8List.fromList(<int>[1, 2, 3])), isNull);
    expect(Watermark.applyToBase64(Uint8List(0)), isNull);
  });

  test('custom text is honoured', () {
    expect(Watermark.applyToBase64(_photo(800, 600), text: 'DRAFT'), isNotNull);
  });
}
