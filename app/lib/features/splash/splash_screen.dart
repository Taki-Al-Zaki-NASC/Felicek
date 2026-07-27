import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/f_logo.dart';

/// Shown while Firebase restores the session. Deliberately the same mark and
/// wordmark as onboarding so the first frame after cold start is continuous.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: FColors.canvas,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FLogo(size: 56),
            SizedBox(height: FSpace.x4),
            Text('Felicek', style: FType.displayMd),
            SizedBox(height: FSpace.x6),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: FColors.teal),
            ),
          ],
        ),
      ),
    );
  }
}
