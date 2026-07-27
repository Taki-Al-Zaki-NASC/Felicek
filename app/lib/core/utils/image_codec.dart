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

  static Uint8List? decode(String? base64String) {
    if (base64String == null || base64String.isEmpty) return null;
    try {
      return base64Decode(base64String);
    } on FormatException {
      return null;
    }
  }
}
