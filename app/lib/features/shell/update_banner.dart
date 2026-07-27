import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/services/update_service.dart';

/// A slim, dismissible banner offering the auto-downloaded update, or a
/// blocking full-screen sheet when the build is mandatory.
///
/// This is the UI half of the self-hosted APK updater — see
/// `UpdateService` for the download/verify/install pipeline it drives.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final UpdateServiceNotifier notifier =
        context.watch<UpdateServiceNotifier>();
    final UpdateState state = notifier.service.state;

    if (!state.hasUpdate && state.phase != UpdatePhase.downloading) {
      return const SizedBox.shrink();
    }

    if (state.isMandatory) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _MandatoryUpdateDialog(),
        );
      });
    }

    return _Banner(state: state, service: notifier.service);
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.state, required this.service});

  final UpdateState state;
  final UpdateService service;

  @override
  Widget build(BuildContext context) {
    final bool downloading = state.phase == UpdatePhase.downloading ||
        state.phase == UpdatePhase.verifying;

    return Material(
      color: FColors.inkStrong,
      child: InkWell(
        onTap: downloading ? null : () => _openSheet(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: <Widget>[
              const Icon(Icons.system_update_alt_rounded,
                  size: 16, color: Colors.white),
              const SizedBox(width: FSpace.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      downloading
                          ? 'Downloading update… ${(state.progress * 100).round()}%'
                          : 'Felicek ${state.manifest?.versionName ?? ''} is available',
                      style: FType.bodyXs
                          .copyWith(color: Colors.white, fontSize: 12),
                    ),
                    if (downloading) ...<Widget>[
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: state.progress,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              FColors.accentOnDark),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!downloading)
                Text(
                  'Update',
                  style: FType.pill
                      .copyWith(fontSize: 11, color: FColors.accentOnDark),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isDismissible: !state.isMandatory,
      enableDrag: !state.isMandatory,
      builder: (_) => _UpdateSheet(state: state, service: service),
    );
  }
}

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet({required this.state, required this.service});

  final UpdateState state;
  final UpdateService service;

  @override
  Widget build(BuildContext context) {
    final String notes = state.manifest?.releaseNotes ?? '';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Felicek ${state.manifest?.versionName ?? ''}',
                style: FType.displaySm),
            const SizedBox(height: FSpace.sm),
            Text(
              state.manifest?.sizeBytes != null
                  ? 'Update size: ${Fmt.bytes(state.manifest!.sizeBytes)}'
                  : '',
              style: FType.caption,
            ),
            if (notes.isNotEmpty) ...<Widget>[
              const SizedBox(height: FSpace.x2),
              Text(notes, style: FType.supportSm),
            ],
            const SizedBox(height: FSpace.x3),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: FColors.inkStrong,
                padding: const EdgeInsets.all(15),
                shape:
                    const RoundedRectangleBorder(borderRadius: FRadius.buttonR),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                service.downloadAndInstall();
              },
              child: Text('Download & Install',
                  style: FType.buttonSm.copyWith(color: Colors.white)),
            ),
            if (!state.isMandatory) ...<Widget>[
              const SizedBox(height: FSpace.lg),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  service.skipVersion();
                },
                child: Text(
                  'Skip this version',
                  style: FType.buttonSm
                      .copyWith(fontSize: 13, color: FColors.inkMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MandatoryUpdateDialog extends StatelessWidget {
  const _MandatoryUpdateDialog();

  @override
  Widget build(BuildContext context) {
    return Consumer<UpdateServiceNotifier>(
      builder: (BuildContext context, UpdateServiceNotifier notifier, _) {
        final UpdateState state = notifier.service.state;
        final bool downloading = state.isBusy;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Update required', style: FType.titleMd),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'This version of Felicek is no longer supported. Please update '
                  'to continue.',
                  style: FType.bodySm,
                ),
                if (downloading) ...<Widget>[
                  const SizedBox(height: FSpace.x2),
                  LinearProgressIndicator(
                    value: state.phase == UpdatePhase.downloading
                        ? state.progress
                        : null,
                    color: FColors.teal,
                    backgroundColor: FColors.border,
                  ),
                ],
                if (state.error != null) ...<Widget>[
                  const SizedBox(height: FSpace.lg),
                  Text(state.error!,
                      style: FType.captionSm.copyWith(color: FColors.danger)),
                ],
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            actions: <Widget>[
              TextButton(
                onPressed:
                    downloading ? null : notifier.service.downloadAndInstall,
                child: Text(
                  downloading ? 'Updating…' : 'Update Now',
                  style: FType.buttonSm
                      .copyWith(fontSize: 13, color: FColors.tealDeep),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
