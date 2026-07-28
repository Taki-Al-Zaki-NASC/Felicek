import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Stamps a preview watermark across delivered images.
///
/// The point is leverage, not secrecy: a client can always screenshot what
/// they can see, so this does not try to make the image unusable. It makes the
/// *watermarked* copy obviously unusable as a finished deliverable, so there
/// is a real reason to release the milestone and collect the clean file.
///
/// That means the mark has to be diagonal, repeated, and drawn over the middle
/// of the picture. A discreet corner logo is trivially cropped out and would
/// give the freelancer nothing.
class Watermark {
  const Watermark._();

  static const String defaultText = 'FELICEK — PREVIEW';

  /// Applies the watermark and returns base64 JPEG, or null if [bytes] is not
  /// a decodable image.
  static String? applyToBase64(Uint8List bytes, {String text = defaultText}) {
    final img.Image? stamped = apply(bytes, text: text);
    if (stamped == null) return null;
    return base64Encode(img.encodeJpg(stamped, quality: 80));
  }

  static img.Image? apply(Uint8List bytes, {String text = defaultText}) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } on Object {
      // decodeImage probes formats and several decoders read past the end of a
      // short buffer rather than returning null.
      return null;
    }
    if (decoded == null) return null;

    img.Image canvas = img.bakeOrientation(decoded);
    // Cap the working size: a 12 MP phone photo is pointless to preview and
    // slow to stamp.
    if (math.max(canvas.width, canvas.height) > 1600) {
      canvas = canvas.width >= canvas.height
          ? img.copyResize(canvas, width: 1600, interpolation: img.Interpolation.average)
          : img.copyResize(canvas, height: 1600, interpolation: img.Interpolation.average);
    }

    final img.BitmapFont font = canvas.width >= 700
        ? img.arial48
        : canvas.width >= 380
            ? img.arial24
            : img.arial14;

    // A translucent scrim first. Without it the text disappears into a busy
    // photo, and a watermark that cannot be seen is not a watermark.
    img.compositeImage(
      canvas,
      img.Image(width: canvas.width, height: canvas.height)
        ..clear(img.ColorRgba8(0, 0, 0, 46)),
      blend: img.BlendMode.alpha,
    );

    final int stepX = (font.size * text.length * 0.62).round().clamp(80, 4000);
    final int stepY = (font.size * 3.4).round().clamp(40, 2000);

    // Drawn on a transparent layer and rotated as one piece — rotating each
    // string individually would leave them out of alignment with each other.
    final img.Image layer = img.Image(
      width: canvas.width * 2,
      height: canvas.height * 2,
      numChannels: 4,
    )..clear(img.ColorRgba8(0, 0, 0, 0));

    for (int y = 0; y < layer.height; y += stepY) {
      // Offset alternate rows so the tiling does not read as a grid the eye
      // can edit around.
      final int row = y ~/ stepY;
      for (int x = (row.isEven ? 0 : -stepX ~/ 2);
          x < layer.width;
          x += stepX) {
        img.drawString(layer, text,
            font: font, x: x, y: y, color: img.ColorRgba8(255, 255, 255, 92));
      }
    }

    final img.Image rotated = img.copyRotate(layer, angle: -30);
    // Centre the rotated layer over the picture.
    img.compositeImage(
      canvas,
      rotated,
      dstX: (canvas.width - rotated.width) ~/ 2,
      dstY: (canvas.height - rotated.height) ~/ 2,
      blend: img.BlendMode.alpha,
    );

    return canvas;
  }
}
