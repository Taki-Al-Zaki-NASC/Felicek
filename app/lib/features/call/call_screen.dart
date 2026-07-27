import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/f_avatar.dart';
import '../../data/models/call_session.dart';
import '../../data/services/call_service.dart';

/// The active-call surface: full-screen remote video with a picture-in-picture
/// local preview for video calls, or a calm avatar + waveform-less timer for
/// audio calls. Works identically for the caller and the callee once a call
/// is connecting or connected.
class CallScreen extends StatefulWidget {
  const CallScreen(
      {super.key, required this.otherName, required this.otherUid});

  final String otherName;
  final String otherUid;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<CallService>(
      builder: (BuildContext context, CallService call, _) {
        final CallSession? session = call.activeCall;
        final CallKind kind = session?.kind ?? CallKind.video;
        final bool ended =
            call.phase == CallPhase.ended || call.phase == CallPhase.failed;

        if (ended) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).maybePop();
          });
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (bool didPop, _) async {
            if (didPop) return;
            final NavigatorState navigator = Navigator.of(context);
            await call.hangUp();
            if (mounted) navigator.pop();
          },
          child: Scaffold(
            backgroundColor: FColors.inkStrong,
            body: SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (kind == CallKind.video &&
                      call.phase == CallPhase.connected)
                    RTCVideoView(
                      call.remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  else
                    _AudioBackdrop(
                        name: widget.otherName, uid: widget.otherUid),
                  Positioned(
                    top: 18,
                    left: 0,
                    right: 0,
                    child: _StatusHeader(name: widget.otherName, service: call),
                  ),
                  if (kind == CallKind.video &&
                      call.phase == CallPhase.connected &&
                      !call.cameraOff)
                    Positioned(
                      top: 90,
                      right: 16,
                      child: _LocalPreview(renderer: call.localRenderer),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 36,
                    child: _CallControls(kind: kind, service: call),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.name, required this.service});

  final String name;
  final CallService service;

  @override
  Widget build(BuildContext context) {
    final String status = switch (service.phase) {
      CallPhase.requestingPermissions => 'Requesting permissions…',
      CallPhase.dialing => 'Calling…',
      CallPhase.ringingIncoming => 'Incoming call…',
      CallPhase.connecting => 'Connecting…',
      CallPhase.connected => Fmt.countdown(service.elapsedSeconds),
      CallPhase.ended => service.error ?? 'Call ended',
      CallPhase.failed => service.error ?? 'Call failed',
      CallPhase.idle => '',
    };
    return Column(
      children: <Widget>[
        Text(
          name,
          style: FType.displaySm.copyWith(color: Colors.white, fontSize: 19),
        ),
        const SizedBox(height: FSpace.xs),
        Text(
          status,
          style: FType.supportSm
              .copyWith(color: Colors.white.withValues(alpha: 0.75)),
        ),
      ],
    );
  }
}

class _AudioBackdrop extends StatelessWidget {
  const _AudioBackdrop({required this.name, required this.uid});

  final String name;
  final String uid;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FColors.inkStrong,
      alignment: Alignment.center,
      child: FAvatar(
        size: 128,
        seed: uid,
        initials: FAvatar.initialsFor(name),
      ),
    );
  }
}

class _LocalPreview extends StatelessWidget {
  const _LocalPreview({required this.renderer});

  final RTCVideoRenderer renderer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 130,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FRadius.card),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
              color: Colors.black26, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: RTCVideoView(
        renderer,
        mirror: true,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({required this.kind, required this.service});

  final CallKind kind;
  final CallService service;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _CircleButton(
          icon: service.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          active: service.muted,
          onTap: service.toggleMute,
        ),
        const SizedBox(width: FSpace.x5),
        if (kind == CallKind.video) ...<Widget>[
          _CircleButton(
            icon: service.cameraOff
                ? Icons.videocam_off_rounded
                : Icons.videocam_rounded,
            active: service.cameraOff,
            onTap: service.toggleCamera,
          ),
          const SizedBox(width: FSpace.x5),
          _CircleButton(
            icon: Icons.cameraswitch_rounded,
            onTap: service.switchCamera,
          ),
          const SizedBox(width: FSpace.x5),
        ],
        _CircleButton(
          icon: Icons.call_end_rounded,
          background: FColors.danger,
          iconColor: Colors.white,
          size: 60,
          onTap: () async {
            await service.hangUp();
            if (context.mounted) Navigator.of(context).maybePop();
          },
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.background,
    this.iconColor,
    this.size = 54,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final Color? background;
  final Color? iconColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color bg = background ??
        (active ? Colors.white : Colors.white.withValues(alpha: 0.16));
    final Color fg = iconColor ?? (active ? FColors.inkStrong : Colors.white);
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: fg, size: size * 0.42),
        ),
      ),
    );
  }
}
