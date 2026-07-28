import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/image_codec.dart';
import '../../core/widgets/f_button.dart';
import '../../core/widgets/f_field.dart';
import '../../data/models/user_role.dart';
import '../../data/services/identity_check.dart';

/// What the capture sheet hands back once every check has passed.
class IdentityCapture {
  const IdentityCapture({
    required this.reference,
    required this.documentBase64,
    required this.selfieBase64,
    required this.autoCheck,
  });

  final String reference;
  final String documentBase64;
  final String selfieBase64;
  final Map<String, dynamic> autoCheck;
}

/// Captures a document number, a photo of the document, and a selfie — and
/// screens all three on the device before letting them be submitted.
///
/// The screening is [IdentityCheck]: sharpness, exposure, resolution and
/// number format. It is honest about its limits — it rejects input a reviewer
/// could not use, it does not and cannot confirm a document is genuine.
class IdentityCaptureSheet extends StatefulWidget {
  const IdentityCaptureSheet({super.key, required this.type});

  final IdDocumentType type;

  static Future<IdentityCapture?> show(
    BuildContext context,
    IdDocumentType type,
  ) =>
      showModalBottomSheet<IdentityCapture>(
        context: context,
        isScrollControlled: true,
        backgroundColor: FColors.canvas,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: IdentityCaptureSheet(type: type),
        ),
      );

  @override
  State<IdentityCaptureSheet> createState() => _IdentityCaptureSheetState();
}

class _IdentityCaptureSheetState extends State<IdentityCaptureSheet> {
  final TextEditingController _reference = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String? _referenceError;
  bool _busy = false;

  String? _documentBase64;
  String? _selfieBase64;
  IdentityCheckResult? _documentCheck;
  IdentityCheckResult? _selfieCheck;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  bool get _ready =>
      _documentBase64 != null &&
      _selfieBase64 != null &&
      (_documentCheck?.passed ?? false) &&
      (_selfieCheck?.passed ?? false) &&
      IdentityCheck.checkReference(widget.type, _reference.text) == null;

  Future<void> _capture({required bool isFace}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final XFile? shot = await _picker.pickImage(
        // Camera rather than gallery: a screenshot of someone else's document
        // is the easiest way to defeat this, and it is not much of a barrier,
        // but it is the one the platform gives us for free.
        source: ImageSource.camera,
        preferredCameraDevice:
            isFace ? CameraDevice.front : CameraDevice.rear,
        // No maxWidth here — the screening measures the original, and
        // downscaling first would measure the downscale instead.
        imageQuality: 100,
      );
      if (shot == null) return;

      final Uint8List bytes = await File(shot.path).readAsBytes();
      final IdentityCheckResult result =
          IdentityCheck.inspect(bytes, isFace: isFace);
      final String? encoded =
          result.passed ? ImageCodec.downsizeDocumentToBase64(bytes) : null;

      if (!mounted) return;
      setState(() {
        if (isFace) {
          _selfieCheck = result;
          _selfieBase64 = encoded;
        } else {
          _documentCheck = result;
          _documentBase64 = encoded;
        }
      });
    } on Object {
      if (mounted) {
        setState(() {
          const IdentityCheckResult failure = IdentityCheckResult(
            passed: false,
            reasons: <String>[
              'The camera could not be opened. Check the app has camera '
                  'permission in system settings.',
            ],
            sharpness: 0,
            brightness: 0,
            width: 0,
            height: 0,
          );
          if (isFace) {
            _selfieCheck = failure;
          } else {
            _documentCheck = failure;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() {
    final String? refError =
        IdentityCheck.checkReference(widget.type, _reference.text);
    if (refError != null) {
      setState(() => _referenceError = refError);
      return;
    }
    if (!_ready) return;

    Navigator.of(context).pop(
      IdentityCapture(
        reference: _reference.text.trim(),
        documentBase64: _documentBase64!,
        selfieBase64: _selfieBase64!,
        autoCheck: <String, dynamic>{
          'checkedAt': DateTime.now().toUtc().toIso8601String(),
          'method': 'on-device-screening-v1',
          'document': _documentCheck!.toMap(),
          'selfie': _selfieCheck!.toMap(),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (BuildContext context, ScrollController scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: <Widget>[
            Text(widget.type.label, style: FType.displayMd),
            const SizedBox(height: FSpace.sm),
            const Text(
              'Checked automatically on this device — nothing is uploaded '
              'until every check passes, and the photos are readable only by '
              'you.',
              style: FType.supportSm,
            ),
            const SizedBox(height: FSpace.x3),
            FField(
              controller: _reference,
              label: 'Document number',
              hint: widget.type.hint,
              errorText: _referenceError,
              onChanged: (_) {
                if (_referenceError != null) {
                  setState(() => _referenceError = null);
                } else {
                  setState(() {});
                }
              },
            ),
            const SizedBox(height: FSpace.x3),
            _CaptureTile(
              title: 'Photo of the document',
              hint: 'Flat surface, all four corners in frame.',
              icon: Icons.badge_outlined,
              busy: _busy,
              captured: _documentBase64 != null,
              result: _documentCheck,
              onTap: () => _capture(isFace: false),
            ),
            const SizedBox(height: FSpace.lg),
            _CaptureTile(
              title: 'Selfie',
              hint: 'Face the camera in good light.',
              icon: Icons.person_outline_rounded,
              busy: _busy,
              captured: _selfieBase64 != null,
              result: _selfieCheck,
              onTap: () => _capture(isFace: true),
            ),
            const SizedBox(height: FSpace.x4),
            FButton(
              label: 'Submit for verification',
              busy: _busy,
              variant: _ready ? FButtonVariant.primary : FButtonVariant.muted,
              onPressed: _ready ? _submit : null,
            ),
            const SizedBox(height: FSpace.lg),
            Text(
              'Automated screening confirms the photos are legible — it does '
              'not confirm the document is genuine. Submitting a document that '
              'is not yours costs you the account and the deposit.',
              style: FType.captionSm.copyWith(color: FColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureTile extends StatelessWidget {
  const _CaptureTile({
    required this.title,
    required this.hint,
    required this.icon,
    required this.busy,
    required this.captured,
    required this.result,
    required this.onTap,
  });

  final String title;
  final String hint;
  final IconData icon;
  final bool busy;
  final bool captured;
  final IdentityCheckResult? result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool failed = result != null && !result!.passed;

    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: FRadius.cardR,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: captured
              ? FColors.tealTint
              : failed
                  ? FColors.dangerTint
                  : FColors.surface,
          borderRadius: FRadius.cardR,
          border: Border.all(
            color: captured
                ? FColors.teal.withValues(alpha: 0.4)
                : failed
                    ? FColors.danger.withValues(alpha: 0.4)
                    : FColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  captured ? Icons.check_circle_rounded : icon,
                  size: 20,
                  color: captured
                      ? FColors.teal
                      : failed
                          ? FColors.danger
                          : FColors.inkMuted,
                ),
                const SizedBox(width: FSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title,
                          style: FType.bodyXs
                              .copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: FSpace.xxs),
                      Text(
                        captured ? 'Looks good' : hint,
                        style: FType.captionSm.copyWith(fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                Text(
                  captured ? 'Retake' : 'Take photo',
                  style: FType.buttonSm
                      .copyWith(fontSize: 12, color: FColors.tealDeep),
                ),
              ],
            ),
            // The point of screening on-device is that the reason is specific
            // and immediate — "blurred, rest it on a table" beats a rejection
            // email three days later.
            if (failed) ...<Widget>[
              const SizedBox(height: FSpace.md),
              for (final String reason in result!.reasons)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '• $reason',
                    style: FType.captionSm.copyWith(color: FColors.danger),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
