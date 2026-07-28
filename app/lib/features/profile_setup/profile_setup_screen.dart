import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/f_button.dart';
import '../../core/widgets/f_field.dart';
import '../../core/widgets/f_photo_picker.dart';
import '../../data/models/app_user.dart';
import '../../data/models/user_role.dart';
import 'profile_questions.dart';

/// "Build Your Profile" — the role-dependent question set from the design.
///
/// It doubles as Edit Profile: pass [isEditing] and the screen gets a back
/// chevron, pre-filled answers and a Save action instead of Continue.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, this.isEditing = false});

  final bool isEditing;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, String?> _errors = <String, String?>{};
  bool _busy = false;
  String? _photoBase64;

  List<ProfileQuestion> get _questions {
    final UserRole role = context.read<SessionController>().role;
    return profileQuestionsByRole[role] ?? const <ProfileQuestion>[];
  }

  @override
  void initState() {
    super.initState();
    final AppUser? user = context.read<SessionController>().user;
    for (final ProfileQuestion q in _questions) {
      _controllers[q.key] =
          TextEditingController(text: _initialValue(q.key, user));
    }
    _photoBase64 = user?.profilePhotoBase64;
  }

  bool get _requiresPhoto =>
      context.read<SessionController>().role == UserRole.freelancer;

  String _initialValue(String key, AppUser? user) {
    if (user == null) return '';
    return switch (key) {
      'fullName' => user.displayName,
      'title' => user.title,
      'bio' => user.bio,
      'location' => user.location,
      'skills' => user.role == UserRole.agency
          ? (user.teamSize ?? '')
          : user.skills.join(', '),
      'rate' => user.hourlyRate?.toStringAsFixed(0) ?? '',
      _ => '',
    };
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _value(String key) => _controllers[key]?.text.trim() ?? '';

  bool _validate() {
    final Map<String, String?> errors = <String, String?>{
      'fullName': Validate.name(_value('fullName')),
      'title': Validate.required(_value('title'), field: 'This'),
      'bio': _value('bio').length < 20
          ? 'Tell people a bit more — at least 20 characters.'
          : null,
      'location': Validate.required(_value('location'), field: 'Location'),
    };
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    return errors.values.every((String? e) => e == null);
  }

  Future<void> _save() async {
    final bool photoMissing =
        _requiresPhoto && (_photoBase64 == null || _photoBase64!.isEmpty);
    if (_busy || !_validate() || photoMissing) {
      if (photoMissing) {
        AppFeedback.error(
          context,
          'Add a profile photo to continue — it is required for individual '
          'freelancer accounts.',
        );
      }
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    final SessionController session = context.read<SessionController>();
    final bool isAgency = session.role == UserRole.agency;
    final String skillsRaw = _value('skills');

    try {
      await session.completeProfile(
        displayName: _value('fullName'),
        title: _value('title'),
        bio: _value('bio'),
        location: _value('location'),
        skills: isAgency
            ? const <String>[]
            : skillsRaw
                .split(',')
                .map((String s) => s.trim())
                .where((String s) => s.isNotEmpty)
                .take(12)
                .toList(growable: false),
        hourlyRate: double.tryParse(_value('rate')),
        teamSize: isAgency ? skillsRaw : null,
        profilePhotoBase64: _photoBase64,
      );
      if (!mounted) return;
      if (widget.isEditing) {
        AppFeedback.success(context, 'Profile updated.');
        Navigator.of(context).maybePop();
      }
      // Otherwise the session gate advances to verification on its own.
    } on Object {
      if (mounted) {
        AppFeedback.error(context, 'Could not save your profile. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<ProfileQuestion> questions = _questions;

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: Column(
        children: <Widget>[
          Container(
            decoration: const BoxDecoration(
              color: FColors.canvas,
              border: Border(bottom: BorderSide(color: FColors.border)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: <Widget>[
                    if (widget.isEditing) ...<Widget>[
                      InkResponse(
                        onTap: () => Navigator.of(context).maybePop(),
                        radius: 22,
                        child: const SizedBox(
                          width: 24,
                          height: 24,
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 15,
                            color: FColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: FSpace.x2),
                    ],
                    Text(
                      widget.isEditing ? 'Edit Profile' : 'Build Your Profile',
                      style: FType.titleSm,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              children: <Widget>[
                const Text(
                  "A few quick questions so clients and freelancers know who they're working with.",
                  style: FType.support,
                ),
                const SizedBox(height: FSpace.x3),
                // Shown to everyone. Only individual freelancers are *required*
                // to have one, but a client or agency with no avatar is a
                // worse counterparty to message, and hiding the control
                // entirely left most accounts with no way to add a picture at
                // all.
                Center(
                  child: FPhotoPicker(
                    initialBase64: _photoBase64,
                    required: _requiresPhoto,
                    onChanged: (String? value) =>
                        setState(() => _photoBase64 = value),
                  ),
                ),
                const SizedBox(height: FSpace.x3),
                for (final ProfileQuestion q in questions) ...<Widget>[
                  FField(
                    controller: _controllers[q.key],
                    label: q.label,
                    hint: q.placeholder,
                    multiline: q.multiline,
                    height: 70,
                    keyboardType: q.numeric
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : null,
                    errorText: _errors[q.key],
                    textInputAction: q.multiline
                        ? TextInputAction.newline
                        : TextInputAction.next,
                  ),
                  const SizedBox(height: FSpace.x2),
                ],
                const SizedBox(height: FSpace.sm),
                FButton(
                  label: widget.isEditing
                      ? 'Save Changes'
                      : 'Continue to Verification',
                  busy: _busy,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
