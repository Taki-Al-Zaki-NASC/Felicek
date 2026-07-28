import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../utils/image_codec.dart';

/// The mandatory profile-photo capture control for individual freelancers.
///
/// A faceless "verified" freelancer defeats the point of verification, so
/// this widget is what the profile-setup and edit-profile screens use to
/// require a real photo before the account can be marked complete.
class FPhotoPicker extends StatefulWidget {
  const FPhotoPicker({
    super.key,
    required this.onChanged,
    this.initialBase64,
    this.required = true,
    this.size = 96,
  });

  final ValueChanged<String?> onChanged;
  final String? initialBase64;
  final bool required;
  final double size;

  @override
  State<FPhotoPicker> createState() => FPhotoPickerState();
}

class FPhotoPickerState extends State<FPhotoPicker> {
  String? _base64;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _base64 = widget.initialBase64;
  }

  /// Exposed so the enclosing form can block submit until a photo exists.
  bool get hasPhoto => _base64 != null && _base64!.isNotEmpty;

  String? get error => _error;

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1600,
        maxHeight: 1600,
        preferredCameraDevice: CameraDevice.front,
      );
      if (picked == null) return;

      setState(() => _busy = true);
      final String? encoded =
          await ImageCodec.downsizeToBase64(File(picked.path));
      if (!mounted) return;
      if (encoded == null) {
        setState(() {
          _busy = false;
          _error = "That file couldn't be read as a photo. Try another.";
        });
        return;
      }
      setState(() {
        _base64 = encoded;
        _busy = false;
      });
      widget.onChanged(encoded);
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Camera or gallery access was denied. Check app permissions.';
      });
    }
  }

  void _remove() {
    setState(() => _base64 = null);
    widget.onChanged(null);
  }

  Future<void> _showSourceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, size: 19),
              title: const Text('Take a photo', style: FType.bodyXs),
              onTap: () {
                Navigator.of(ctx).pop();
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, size: 19),
              title: const Text('Choose from gallery', style: FType.bodyXs),
              onTap: () {
                Navigator.of(ctx).pop();
                _pick(ImageSource.gallery);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    size: 19, color: FColors.danger),
                title: Text(
                  'Remove photo',
                  style: FType.bodyXs.copyWith(color: FColors.danger),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _remove();
                },
              ),
            const SizedBox(height: FSpace.md),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ImageProvider? provider =
        hasPhoto ? MemoryImage(ImageCodec.decode(_base64)!) : null;

    return Column(
      children: <Widget>[
        GestureDetector(
          onTap: _busy ? null : _showSourceSheet,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: FColors.neutralTint,
                  image: provider == null
                      ? null
                      : DecorationImage(image: provider, fit: BoxFit.cover),
                  border: Border.all(
                    color: widget.required && !hasPhoto
                        ? FColors.danger.withValues(alpha: 0.4)
                        : FColors.border,
                    width: widget.required && !hasPhoto ? 1.4 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: FColors.teal),
                      )
                    : provider == null
                        ? Icon(
                            Icons.person_outline_rounded,
                            size: widget.size * 0.42,
                            color: FColors.inkFaint,
                          )
                        : null,
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: FColors.inkStrong,
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                      BorderSide(color: FColors.canvas, width: 2.5),
                    ),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FSpace.lg),
        Text(
          hasPhoto ? 'Tap to change photo' : 'Add a profile photo',
          style: FType.captionSm.copyWith(
            color: widget.required && !hasPhoto
                ? FColors.danger
                : FColors.inkMuted,
          ),
        ),
        if (!hasPhoto)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              widget.required
                  ? 'Required for individual freelancer accounts'
                  : 'Optional, but people are likelier to reply',
              style: FType.captionSm.copyWith(
                fontSize: 10,
                color: widget.required ? FColors.danger : FColors.inkFaint,
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style:
                  FType.captionSm.copyWith(fontSize: 10, color: FColors.danger),
            ),
          ),
      ],
    );
  }
}
