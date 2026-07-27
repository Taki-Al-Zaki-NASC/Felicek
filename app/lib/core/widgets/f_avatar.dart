import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../utils/image_codec.dart';

/// The verified-user avatar from the design:
/// `conic-gradient(from 210deg, #0d9488, #2f5fa8, #0d9488)`.
///
/// [seed] rotates the sweep so different people are visually distinct while
/// still sitting inside the brand's teal→blue range. When [photoBase64] is
/// present it renders that instead — real profile photos win over the
/// generated gradient wherever they exist.
class FAvatar extends StatelessWidget {
  const FAvatar({
    super.key,
    this.size = 30,
    this.initials,
    this.seed,
    this.verified = false,
    this.photoBase64,
  });

  final double size;
  final String? initials;
  final String? seed;
  final bool verified;
  final String? photoBase64;

  static String initialsFor(String name) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first
          .substring(0, math.min(2, parts.first.length))
          .toUpperCase();
    }
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  double get _startAngle {
    // 210deg in the design; the seed nudges it deterministically.
    const double base = 210;
    if (seed == null || seed!.isEmpty) return base * math.pi / 180;
    final int h = seed!.codeUnits
        .fold<int>(7, (int a, int c) => (a * 31 + c) & 0x7fffffff);
    return (base + (h % 120)) * math.pi / 180;
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List? photo = ImageCodec.decode(photoBase64);

    final Widget circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: photo == null
            ? SweepGradient(
                transform: GradientRotation(_startAngle),
                colors: FColors.avatarSweep,
                stops: const <double>[0.0, 0.5, 1.0],
              )
            : null,
        image: photo == null
            ? null
            : DecorationImage(image: MemoryImage(photo), fit: BoxFit.cover),
      ),
      child: photo != null || initials == null
          ? null
          : Text(
              initials!,
              style: FType.titleXs.copyWith(
                color: Colors.white,
                fontSize: size * 0.36,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
    );

    if (!verified) return circle;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          circle,
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: size * 0.38,
              height: size * 0.38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: FColors.teal,
                border: Border.fromBorderSide(
                  BorderSide(color: FColors.surface, width: 1.5),
                ),
              ),
              child: Icon(Icons.check, size: size * 0.22, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
