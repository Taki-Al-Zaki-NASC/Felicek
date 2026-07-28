import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/feedback.dart';
import '../../core/widgets/f_button.dart';
import '../../core/widgets/f_field.dart';
import '../../core/widgets/f_pill.dart';
import '../../core/widgets/f_surface.dart';
import '../../data/models/app_user.dart';
import '../../data/repositories/auth_repository.dart';

/// Account and security: email verification state, blocked users, and account
/// deletion.
///
/// Deletion is not optional polish — Google Play requires an in-app path to
/// delete your account and data for any app that lets you create one. It is
/// also the honest counterpart to asking for identity documents up front.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppUser? user =
        context.select<SessionController, AppUser?>((s) => s.user);
    if (user == null) return const Scaffold(body: FLoading());

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: Column(
        children: <Widget>[
          const FTopBar(title: 'Account & security'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              children: <Widget>[
                const FSectionLabel('Email'),
                const SizedBox(height: FSpace.lg),
                _EmailCard(user: user),
                const SizedBox(height: FSpace.x3),
                const FSectionLabel('Blocked people'),
                const SizedBox(height: FSpace.lg),
                _BlockedList(user: user),
                const SizedBox(height: FSpace.x3),
                const FSectionLabel('Danger zone'),
                const SizedBox(height: FSpace.lg),
                const _DeleteAccountCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailCard extends StatefulWidget {
  const _EmailCard({required this.user});

  final AppUser user;

  @override
  State<_EmailCard> createState() => _EmailCardState();
}

class _EmailCardState extends State<_EmailCard> {
  bool _busy = false;
  bool? _verified;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final AuthRepository auth = context.authRepo;
    final bool verified = await auth.refreshEmailVerified();
    if (mounted) setState(() => _verified = verified);
  }

  Future<void> _resend() async {
    if (_busy) return;
    final AuthRepository auth = context.authRepo;
    setState(() => _busy = true);
    try {
      await auth.resendVerificationEmail();
      if (mounted) {
        AppFeedback.success(context, 'Verification email sent.');
      }
    } on AuthFailure catch (e) {
      if (mounted) AppFeedback.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool verified = _verified ?? false;

    return FCard(
      radius: FRadius.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.user.email,
                  style: FType.titleXs,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: FSpace.md),
              if (_verified == null)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: FColors.teal),
                )
              else if (verified)
                FPill.teal('Verified')
              else
                FPill.amber('Unverified'),
            ],
          ),
          if (_verified != null && !verified) ...<Widget>[
            const SizedBox(height: FSpace.lg),
            const Text(
              'Confirming your email protects password resets and payout '
              'notices. Check your inbox, then tap refresh.',
              style: FType.supportSm,
            ),
            const SizedBox(height: FSpace.xl),
            Row(
              children: <Widget>[
                Expanded(
                  child: FButton.compact(
                    label: 'Resend email',
                    busy: _busy,
                    onPressed: _resend,
                  ),
                ),
                const SizedBox(width: FSpace.lg),
                Expanded(
                  child: FButton.compact(
                    label: 'Refresh',
                    variant: FButtonVariant.secondary,
                    onPressed: _refresh,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BlockedList extends StatelessWidget {
  const _BlockedList({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    if (user.blockedUserIds.isEmpty) {
      return const FCard(
        radius: FRadius.card,
        child: Text(
          "You haven't blocked anyone. Blocking someone from a conversation "
          'stops messages and calls in both directions.',
          style: FType.supportSm,
        ),
      );
    }

    return FCard(
      radius: FRadius.card,
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          for (final String blocked in user.blockedUserIds)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: FColors.borderFaint)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: FutureBuilder<String>(
                      future: context.userRepo
                          .fetchProfile(blocked)
                          .then((p) => p?.displayName ?? 'Felicek user'),
                      builder:
                          (BuildContext context, AsyncSnapshot<String> s) =>
                              Text(s.data ?? '…', style: FType.bodyXs),
                    ),
                  ),
                  FTextAction(
                    label: 'Unblock',
                    onPressed: () =>
                        context.userRepo.unblockUser(user.uid, blocked),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DeleteAccountCard extends StatefulWidget {
  const _DeleteAccountCard();

  @override
  State<_DeleteAccountCard> createState() => _DeleteAccountCardState();
}

class _DeleteAccountCardState extends State<_DeleteAccountCard> {
  bool _busy = false;

  Future<void> _delete() async {
    final bool sure = await AppFeedback.confirm(
      context,
      title: 'Delete your account?',
      message:
          'Your profile, photo and identity reference are removed immediately. '
          'Messages already delivered to other people, and financial records we '
          'are legally required to keep, are retained. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!sure || !mounted) return;

    // Firebase requires a recent login before deletion, so ask for the
    // password rather than failing with a confusing error afterwards.
    final TextEditingController password = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Confirm your password', style: FType.titleMd),
        content: FField(
          controller: password,
          hint: 'Your password',
          obscure: true,
          autofocus: true,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: FType.buttonSm
                  .copyWith(fontSize: 13, color: FColors.inkMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete account',
              style:
                  FType.buttonSm.copyWith(fontSize: 13, color: FColors.danger),
            ),
          ),
        ],
      ),
    );

    final String secret = password.text;
    password.dispose();
    if (confirmed != true || secret.isEmpty || !mounted) return;

    final AuthRepository auth = context.authRepo;
    setState(() => _busy = true);
    try {
      await auth.deleteAccount(password: secret);
      // The session gate drops to the sign-in screen on its own.
    } on AuthFailure catch (e) {
      if (mounted) AppFeedback.error(context, e.message);
    } on Object {
      if (mounted) {
        AppFeedback.error(context, 'Could not delete the account. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FCard(
      radius: FRadius.card,
      background: FColors.dangerTint,
      border: FColors.danger.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Delete account',
            style: FType.titleXs.copyWith(color: FColors.danger),
          ),
          const SizedBox(height: FSpace.sm),
          const Text(
            'Permanently removes your profile and identity reference. Any '
            'refundable deposit you are owed is returned to your payout method '
            'first — close open engagements before deleting.',
            style: FType.supportSm,
          ),
          const SizedBox(height: FSpace.xl),
          FButton.compact(
            label: 'Delete my account',
            variant: FButtonVariant.danger,
            busy: _busy,
            onPressed: _delete,
          ),
        ],
      ),
    );
  }
}
