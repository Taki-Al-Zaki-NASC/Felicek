import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// The Felicek mark: an ink rounded-square with a hollow ring inside, exactly
/// as the onboarding screen draws it.
class FLogo extends StatelessWidget {
  const FLogo({super.key, this.size = 64, this.background = FColors.inkStrong});

  final double size;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final double ring = size * 0.40625; // 26/64
    final double stroke = size * 0.046875; // 3/64
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      alignment: Alignment.center,
      child: Container(
        width: ring,
        height: ring,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: FColors.canvas, width: stroke),
        ),
      ),
    );
  }
}
