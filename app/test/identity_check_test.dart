import 'dart:math' as math;
import 'dart:typed_data';

import 'package:felicek/data/models/user_role.dart';
import 'package:felicek/data/services/identity_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The screening decides whether a real person who has paid a deposit gets an
/// account. A false reject is worse than a false accept here, so the tests
/// pin both ends: obvious junk fails, and plausible input is not rejected.
Uint8List _jpeg(img.Image image) =>
    Uint8List.fromList(img.encodeJpg(image, quality: 92));

/// Random noise — high-frequency detail, so it reads as sharp.
img.Image _sharp(int w, int h) {
  final img.Image image = img.Image(width: w, height: h);
  final math.Random rng = math.Random(7);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final int v = 40 + rng.nextInt(180);
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return image;
}

img.Image _flat(int w, int h, int value) {
  final img.Image image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(value, value, value));
  return image;
}

void main() {
  group('Photo screening', () {
    test('a sharp, well-exposed, large enough photo passes', () {
      final IdentityCheckResult r = IdentityCheck.inspect(_jpeg(_sharp(1000, 700)));
      expect(r.passed, isTrue, reason: r.reasons.join(' | '));
    });

    test('a thumbnail is rejected for size', () {
      final IdentityCheckResult r = IdentityCheck.inspect(_jpeg(_sharp(320, 200)));
      expect(r.passed, isFalse);
      expect(r.reasons.join(), contains('too small'));
    });

    test('a flat mid-grey frame is rejected as blurred', () {
      // No edges at all — the degenerate case of an out-of-focus photo.
      final IdentityCheckResult r =
          IdentityCheck.inspect(_jpeg(_flat(1000, 700, 128)));
      expect(r.passed, isFalse);
      expect(r.sharpness, lessThan(IdentityCheck.minSharpness));
    });

    test('a dark frame says it is dark, not that it is blurred', () {
      final IdentityCheckResult r =
          IdentityCheck.inspect(_jpeg(_flat(1000, 700, 8)));
      expect(r.passed, isFalse);
      expect(r.reasons.join(), contains('dark'));
    });

    test('a blown-out frame says it is too bright', () {
      final IdentityCheckResult r =
          IdentityCheck.inspect(_jpeg(_flat(1000, 700, 252)));
      expect(r.passed, isFalse);
      expect(r.reasons.join(), contains('bright'));
    });

    test('a non-image is refused rather than throwing', () {
      final IdentityCheckResult r =
          IdentityCheck.inspect(Uint8List.fromList(<int>[1, 2, 3, 4]));
      expect(r.passed, isFalse);
      expect(r.reasons.single, contains('not a readable image'));
    });

    test('the selfie wording differs from the document wording', () {
      final Uint8List blurred = _jpeg(_flat(1000, 700, 128));
      expect(
        IdentityCheck.inspect(blurred, isFace: true).reasons.join(),
        contains('selfie'),
      );
      expect(
        IdentityCheck.inspect(blurred).reasons.join(),
        contains('flat surface'),
      );
    });
  });

  group('Document number format', () {
    test('a plausible passport number is accepted', () {
      expect(IdentityCheck.checkReference(IdDocumentType.passport, 'A1234567'),
          isNull);
    });

    test('spaces and dashes are tolerated rather than punished', () {
      // People copy the number off the document as it is printed.
      expect(
        IdentityCheck.checkReference(IdDocumentType.nationalId, '1234 5678 9012'),
        isNull,
      );
    });

    test('empty is refused', () {
      expect(IdentityCheck.checkReference(IdDocumentType.passport, '   '),
          contains('Enter'));
    });

    test('a repeated single character is refused', () {
      expect(
        IdentityCheck.checkReference(IdDocumentType.nationalId, '0000000000'),
        contains('does not look like'),
      );
    });

    test('punctuation is refused with a specific reason', () {
      expect(
        IdentityCheck.checkReference(IdDocumentType.passport, 'A123!@#4'),
        contains('letters and digits'),
      );
    });

    test('an over-long passport number is refused', () {
      expect(
        IdentityCheck.checkReference(IdDocumentType.passport, 'A12345678901'),
        contains('6–9'),
      );
    });
  });

  group('Honesty of the verdict', () {
    test('the provider hook is unimplemented rather than a fake pass', () {
      // If this ever starts returning "verified", real identity proofing has
      // been replaced by something that only looks like it.
      expect(IdentityCheck.providerHook, throwsUnimplementedError);
    });

    test('a failed result carries reasons, a passed one does not', () {
      final IdentityCheckResult ok = IdentityCheck.inspect(_jpeg(_sharp(1000, 700)));
      expect(ok.reasons, isEmpty);
      expect(ok.toMap()['passed'], isTrue);
      expect(ok.toMap().containsKey('reasons'), isFalse);
    });
  });
}
