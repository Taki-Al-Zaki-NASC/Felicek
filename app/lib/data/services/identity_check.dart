import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/user_role.dart';

/// Result of screening one captured identity photo.
class IdentityCheckResult {
  const IdentityCheckResult({
    required this.passed,
    required this.reasons,
    required this.sharpness,
    required this.brightness,
    required this.width,
    required this.height,
  });

  final bool passed;

  /// Why it failed, phrased as something the person can act on.
  final List<String> reasons;

  final double sharpness;
  final double brightness;
  final int width;
  final int height;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'passed': passed,
        'sharpness': double.parse(sharpness.toStringAsFixed(1)),
        'brightness': double.parse(brightness.toStringAsFixed(1)),
        'width': width,
        'height': height,
        if (reasons.isNotEmpty) 'reasons': reasons,
      };
}

/// On-device screening for identity photos and document numbers.
///
/// **This is screening, not identity proofing.** It rejects the failures that
/// make a human review pointless — a blurred frame, a dark frame, a thumbnail,
/// a number that cannot belong to the chosen document type — and it does so
/// instantly and for free, on the device.
///
/// It cannot tell you the document is genuine, unaltered, or the person's own.
/// Nothing running on the claimant's own phone can: the same device that
/// captures the photo can fabricate it. Real proofing needs a provider that
/// checks the document against an issuing authority and matches a live face
/// against it (Onfido, Persona, Stripe Identity). The hook for that is
/// [IdentityCheck.providerHook] — see docs/VERIFICATION.md.
///
/// Everything here is deliberately conservative: a false accept wastes a
/// reviewer's time, but a false reject blocks a real person from an account
/// they have paid for, so the thresholds sit where obviously-bad input fails
/// and marginal input passes.
class IdentityCheck {
  const IdentityCheck._();

  /// Below this the image is too soft to read a document number from.
  /// Variance-of-Laplacian on an 8-bit greyscale image; empirically a sharp
  /// document photo scores in the hundreds, a badly blurred one in single
  /// digits.
  static const double minSharpness = 22;

  /// Mean luminance, 0–255. Outside this band the photo is either a dark
  /// frame or blown out by flash on a laminated card.
  static const double minBrightness = 45;
  static const double maxBrightness = 232;

  /// A legible document needs real pixels behind it.
  static const int minLongEdge = 640;

  /// Screens a captured photo. [bytes] is the original camera output, before
  /// any downsizing — checking after a resize would measure the resize.
  static IdentityCheckResult inspect(Uint8List bytes, {bool isFace = false}) {
    // decodeImage does not merely return null on rubbish input — it probes
    // each format in turn, and several of those decoders read past the end of
    // a short buffer and throw RangeError. A truncated camera file would
    // otherwise crash the capture sheet outright.
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } on Object {
      decoded = null;
    }
    if (decoded == null) {
      return const IdentityCheckResult(
        passed: false,
        reasons: <String>['That file is not a readable image.'],
        sharpness: 0,
        brightness: 0,
        width: 0,
        height: 0,
      );
    }

    final img.Image oriented = img.bakeOrientation(decoded);
    final img.Image grey = img.grayscale(
      oriented.width > 900
          ? img.copyResize(oriented, width: 900, interpolation: img.Interpolation.average)
          : oriented,
    );

    final double sharpness = _varianceOfLaplacian(grey);
    final double brightness = _meanLuminance(grey);
    final int longEdge = math.max(oriented.width, oriented.height);

    final List<String> reasons = <String>[];
    if (longEdge < minLongEdge) {
      reasons.add('That image is too small to read — take the photo with the '
          'camera rather than picking a thumbnail.');
    }
    if (sharpness < minSharpness) {
      reasons.add(isFace
          ? 'That selfie is blurred. Hold still and try again.'
          : 'The photo is blurred. Rest the document on a flat surface and '
              'let the camera focus before you shoot.');
    }
    if (brightness < minBrightness) {
      reasons.add('Too dark to read. Move somewhere brighter.');
    } else if (brightness > maxBrightness) {
      reasons.add('Too bright — the glare is washing out the detail. Turn the '
          'flash off or tilt away from the light.');
    }

    return IdentityCheckResult(
      passed: reasons.isEmpty,
      reasons: reasons,
      sharpness: sharpness,
      brightness: brightness,
      width: oriented.width,
      height: oriented.height,
    );
  }

  /// Checks a document number against the shape that type actually has.
  ///
  /// Returns null when it looks acceptable, or a sentence explaining the
  /// mismatch. Format only — it cannot confirm the number was ever issued.
  static String? checkReference(IdDocumentType type, String raw) {
    final String value = raw.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (value.isEmpty) return 'Enter the document number.';
    if (value.length < type.minLength) {
      return 'That is shorter than a ${type.label.toLowerCase()} number.';
    }
    if (value.length > 30) return 'That is longer than any document number.';
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(value)) {
      return 'Use only the letters and digits printed on the document.';
    }
    // A single repeated character is the most common junk entry.
    if (RegExp(r'^(.)\1+$').hasMatch(value)) {
      return 'That does not look like a real document number.';
    }
    return switch (type) {
      // ICAO 9303: nine alphanumeric characters.
      IdDocumentType.passport => RegExp(r'^[A-Z0-9]{6,9}$').hasMatch(value)
          ? null
          : 'A passport number is 6–9 letters and digits.',
      IdDocumentType.nationalId ||
      IdDocumentType.drivingLicence ||
      IdDocumentType.governmentId ||
      IdDocumentType.birthCertificate =>
        null,
    };
  }

  /// Where a real verification provider is called.
  ///
  /// Deliberately unimplemented rather than faked. Wiring this up means
  /// posting the captured images to a provider and letting *their* verdict —
  /// arriving on a server the claimant does not control — set
  /// `kyc.stage = 'verified'`. Doing it from the client would mean the account
  /// being verified decides whether it is verified.
  static Future<Never> providerHook() =>
      throw UnimplementedError('See docs/VERIFICATION.md');

  /// Variance of the Laplacian — the standard cheap focus measure.
  static double _varianceOfLaplacian(img.Image grey) {
    final int w = grey.width, h = grey.height;
    if (w < 3 || h < 3) return 0;

    final List<double> response = <double>[];
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        // 4-neighbour Laplacian kernel.
        final double v = (-4 * grey.getPixel(x, y).luminance +
                grey.getPixel(x - 1, y).luminance +
                grey.getPixel(x + 1, y).luminance +
                grey.getPixel(x, y - 1).luminance +
                grey.getPixel(x, y + 1).luminance)
            .toDouble();
        response.add(v);
      }
    }
    if (response.isEmpty) return 0;

    final double mean =
        response.reduce((double a, double b) => a + b) / response.length;
    double sum = 0;
    for (final double v in response) {
      sum += (v - mean) * (v - mean);
    }
    return sum / response.length;
  }

  static double _meanLuminance(img.Image grey) {
    double total = 0;
    int count = 0;
    // Sampling every 4th pixel is plenty for a mean and keeps this off the
    // frame budget on a large capture.
    for (int y = 0; y < grey.height; y += 4) {
      for (int x = 0; x < grey.width; x += 4) {
        total += grey.getPixel(x, y).luminance;
        count++;
      }
    }
    return count == 0 ? 0 : total / count;
  }
}
