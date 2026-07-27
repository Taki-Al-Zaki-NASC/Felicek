import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/f_avatar.dart';
import '../../data/models/call_session.dart';
import '../../data/services/call_service.dart';
import 'call_screen.dart';

/// Full-screen incoming-call prompt, pushed the moment
/// `CallService.listenForIncomingCalls` fires.
class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({
    super.key,
    required this.call,
    required this.service,
  });

  final CallSession call;
  final CallService service;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: FColors.inkStrong,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              const Spacer(flex: 2),
              Text(
                call.kind == CallKind.video
                    ? 'Incoming video call'
                    : 'Incoming call',
                style: FType.captionSm.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: FSpace.x3),
              FAvatar(
                  size: 96,
                  seed: call.callerId,
                  initials: FAvatar.initialsFor(call.callerName)),
              const SizedBox(height: FSpace.x3),
              Text(
                call.callerName,
                style:
                    FType.displaySm.copyWith(color: Colors.white, fontSize: 22),
              ),
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _Action(
                      icon: Icons.call_end_rounded,
                      color: FColors.danger,
                      label: 'Decline',
                      onTap: () {
                        service.declineCall(call);
                        Navigator.of(context).maybePop();
                      },
                    ),
                    _Action(
                      icon: call.kind == CallKind.video
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      color: FColors.teal,
                      label: 'Accept',
                      onTap: () {
                        service.acceptCall(call);
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => CallScreen(
                              otherName: call.callerName,
                              otherUid: call.callerId,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FSpace.x6),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, color: Colors.white, size: 26),
            ),
          ),
        ),
        const SizedBox(height: FSpace.md),
        Text(label, style: FType.captionSm.copyWith(color: Colors.white70)),
      ],
    );
  }
}
