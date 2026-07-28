import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/feedback.dart';
import '../../core/widgets/f_button.dart';
import '../../core/widgets/f_logo.dart';
import '../../data/models/user_role.dart';
import '../../data/services/firestore_refs.dart';
import 'role_card.dart';

/// "Choose your account" — the first screen in the design, rebuilt exactly:
/// mark, wordmark, promise line, four role cards, ink CTA, fine print.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  UserRole _selected = UserRole.freelancer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selected = context.read<SessionController>().role;
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<SessionController>().chooseRole(_selected);
    } on Object catch (e) {
      if (mounted) AppFeedback.error(context, describeFirestoreError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FColors.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) =>
              SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 32),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight - 64),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Center(child: FLogo()),
                  const SizedBox(height: FSpace.x6),
                  const Center(child: Text('Felicek', style: FType.displayXl)),
                  const SizedBox(height: FSpace.sm),
                  Center(
                    child: Text(
                      'Verified talent. Zero spam.\nFair fees, always.',
                      textAlign: TextAlign.center,
                      style: FType.bodySm.copyWith(
                        fontSize: 13,
                        color: FColors.inkMuted,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: FSpace.x6),
                  const Text(
                    'CHOOSE YOUR ACCOUNT',
                    style: FType.sectionLabel,
                  ),
                  const SizedBox(height: FSpace.lg),
                  for (final UserRole role in UserRole.values) ...<Widget>[
                    RoleCard(
                      role: role,
                      selected: _selected == role,
                      onTap: () {
                        AppFeedback.tap();
                        setState(() => _selected = role);
                      },
                    ),
                    if (role != UserRole.values.last)
                      const SizedBox(height: FSpace.lg),
                  ],
                  const SizedBox(height: FSpace.x6),
                  FButton(
                    label: 'Continue to Verification',
                    busy: _busy,
                    onPressed: _continue,
                    fontSize: 14,
                  ),
                  const SizedBox(height: FSpace.x6),
                  Text(
                    'Identity verification is required for every account. '
                    'Freelancer accounts additionally require a refundable '
                    r'$20 trust deposit.',
                    textAlign: TextAlign.center,
                    style: FType.caption.copyWith(fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
