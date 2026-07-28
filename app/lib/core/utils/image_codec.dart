import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Downsizes a photo to something that fits comfortably inside a Firestore
/// document (1 MiB hard limit) without needing a paid Storage plan.
///
/// A 480px-square, quality-78 JPEG lands around 20–45 KB for a typical face
/// photo — small enough that embedding it directly on the profile document
/// costs nothing extra to read.
class ImageCodec {
  const ImageCodec._();

  static const int maxDimension = 480;
  static const int jpegQuality = 78;

  /// Reads, EXIF-corrects, center-crops to square, downsizes and re-encodes.
  /// Returns `null` if the file cannot be decoded as an image.
  static Future<String?> downsizeToBase64(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    return downsizeBytesToBase64(bytes);
  }

  static String? downsizeBytesToBase64(Uint8List bytes) {
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    decoded = img.bakeOrientation(decoded);

    final int side =
        decoded.width < decoded.height ? decoded.width : decoded.height;
    final int x = (decoded.width - side) ~/ 2;
    final int y = (decoded.height - side) ~/ 2;
    img.Image square =
        img.copyCrop(decoded, x: x, y: y, width: side, height: side);

    if (square.width > maxDimension) {
      square = img.copyResize(
        square,
        width: maxDimension,
        height: maxDimension,
        interpolation: img.Interpolation.average,
      );
    }

    final List<int> jpeg = img.encodeJpg(square, quality: jpegQuality);
    return base64Encode(jpeg);
  }

  /// Longest edge for a stored identity document.
  ///
  /// Larger than [maxDimension] because a document has to stay *readable* —
  /// a 480px square crop of a passport is useless to a reviewer. Also never
  /// square-cropped, for the same reason.
  static const int documentMaxDimension = 1280;
  static const int documentJpegQuality = 82;

  /// Downsizes a document photo while preserving its aspect ratio.
  ///
  /// Lands around 120–260 KB, which is why these are written to their own
  /// subcollection document rather than onto the profile: the profile doc is
  /// streamed live by SessionController, so anything stored on it is
  /// re-downloaded on every unrelated profile change.
  static String? downsizeDocumentToBase64(Uint8List bytes) {
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    decoded = img.bakeOrientation(decoded);

    final int longEdge =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    if (longEdge > documentMaxDimension) {
      decoded = decoded.width >= decoded.height
          ? img.copyResize(decoded,
              width: documentMaxDimension,
              interpolation: img.Interpolation.average)
          : img.copyResize(decoded,
              height: documentMaxDimension,
              interpolation: img.Interpolation.average);
    }

    return base64Encode(img.encodeJpg(decoded, quality: documentJpegQuality));
  }

  static Uint8List? decode(String? base64String) {
    if (base64String == null || base64String.isEmpty) return null;
    try {
      return base64Decode(base64String);
    } on FormatException {
      return null;
    }
  }
}
