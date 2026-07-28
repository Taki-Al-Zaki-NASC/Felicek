import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/f_avatar.dart';
import '../../core/widgets/f_pill.dart';
import '../../core/widgets/f_surface.dart';
import '../../data/models/app_user.dart';
import '../../data/models/review.dart';
import '../../data/models/user_role.dart';
import '../kyc/kyc_screen.dart';
import '../onboarding/role_card.dart';
import '../profile_setup/profile_setup_screen.dart';
import '../settings/settings_screen.dart';

/// The Profile tab: identity card, stats, portfolio placeholder, reviews,
/// verification entry point, role switcher and the settings block.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppUser? user =
        context.select<SessionController, AppUser?>((s) => s.user);
    if (user == null) return const FLoading();

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          _DarkHeader(user: user),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _IdentityCard(user: user),
                const SizedBox(height: FSpace.x2),
                Row(
                  children: <Widget>[
                    FStatTile(
                      value: '${user.jobSuccess}%',
                      label: 'Job Success',
                      valueColor: FColors.teal,
                    ),
                    const SizedBox(width: FSpace.lg),
                    FStatTile(
                        value: Fmt.compact(user.totalEarned),
                        label: 'Total Earned'),
                    const SizedBox(width: FSpace.lg),
                    FStatTile(
                      value: '${user.jobsDone}',
                      label: 'Jobs Done',
                      valueColor: FColors.blue,
                    ),
                  ],
                ),
                const SizedBox(height: FSpace.x3),
                const FSectionLabel('Portfolio'),
                const SizedBox(height: FSpace.lg),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  children: List<Widget>.generate(
                    3,
                    (int i) => Container(
                      decoration: const BoxDecoration(
                        color: FColors.hatchA,
                        borderRadius: FRadius.fieldR,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Project ${i + 1}',
                        style: FType.captionSm
                            .copyWith(fontSize: 9, color: FColors.hatchInk),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: FSpace.x3),
                const FSectionLabel('Work History & Reviews'),
                const SizedBox(height: FSpace.lg),
                _Reviews(uid: user.uid),
                const SizedBox(height: FSpace.x2),
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const KycScreen(fromProfile: true)),
                  ),
                  borderRadius: FRadius.cardR,
                  child: FCard(
                    radius: FRadius.card,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Text('Verification', style: FType.captionSm),
                            const SizedBox(height: 2),
                            Text(
                              user.kyc.isVerified
                                  ? 'KYC & Deposit · Verified'
                                  : 'KYC & Deposit',
                              style: FType.titleMd.copyWith(fontSize: 14),
                            ),
                          ],
                        ),
                        Text('Manage ›',
                            style: FType.pill.copyWith(
                                fontSize: 12, color: FColors.tealDeep)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: FSpace.x2),
                const FSectionLabel('Switch Account Type'),
                const SizedBox(height: FSpace.lg),
                for (final UserRole role in UserRole.values) ...<Widget>[
                  RoleCard(
                    role: role,
                    selected: user.role == role,
                    onTap: () async {
                      if (user.role == role) return;
                      final SessionController session =
                          context.read<SessionController>();
                      final bool ok = await AppFeedback.confirm(
                        context,
                        title: 'Switch to ${role.label}?',
                        message: role == UserRole.freelancer
                            ? 'This adds a mandatory profile photo requirement and a '
                                'refundable \$20 trust deposit.'
                            : 'This requires a \$${role.depositCents ~/ 100} job-posting '
                                'balance before you can publish listings.',
                        confirmLabel: 'Switch',
                      );
                      if (ok) await session.switchRole(role);
                    },
                  ),
                  const SizedBox(height: FSpace.md),
                ],
                const SizedBox(height: FSpace.lg),
                FCard(
                  radius: FRadius.card,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      _SettingsRow(
                        label: 'Notification preferences',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const SettingsScreen()),
                        ),
                      ),
                      _SettingsRow(
                        label: 'Privacy & data',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const SettingsScreen()),
                        ),
                      ),
                      _SettingsRow(
                        label: 'Log out',
                        color: FColors.danger,
                        showDivider: false,
                        onTap: () async {
                          final SessionController session =
                              context.read<SessionController>();
                          final bool ok = await AppFeedback.confirm(
                            context,
                            title: 'Log out?',
                            message:
                                "You'll need to sign in again to use Felicek.",
                            confirmLabel: 'Log out',
                            destructive: true,
                          );
                          if (ok) await session.signOut();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkHeader extends StatelessWidget {
  const _DarkHeader({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FColors.inkStrong,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text('Profile',
                style: FType.displaySm.copyWith(color: Colors.white)),
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProfileSetupScreen(isEditing: true),
                ),
              ),
              borderRadius: FRadius.chipR,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: const BoxDecoration(
                  color: FColors.fillOnDark,
                  borderRadius: FRadius.chipR,
                ),
                child: Text(
                  'Edit Profile',
                  style:
                      FType.pill.copyWith(fontSize: 11.5, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -18),
      child: FCard(
        radius: FRadius.cardLg,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FAvatar(
                  size: 64,
                  seed: user.uid,
                  photoBase64: user.profilePhotoBase64,
                  initials: FAvatar.initialsFor(user.displayName),
                  verified: user.kyc.isVerified,
                ),
                const SizedBox(width: FSpace.x2),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          user.displayName.isEmpty
                              ? 'Your name'
                              : user.displayName,
                          style: FType.titleLg,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (user.title.isNotEmpty)
                          Text(user.title,
                              style: FType.support,
                              overflow: TextOverflow.ellipsis),
                        if (user.location.isNotEmpty)
                          Text(
                            user.location,
                            style: FType.caption.copyWith(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
                FRoleBadge(user.role.shortLabel),
              ],
            ),
            if (user.bio.isNotEmpty) ...<Widget>[
              const SizedBox(height: FSpace.xl),
              Text(user.bio,
                  style: FType.bodySm.copyWith(color: FColors.inkBody)),
            ],
            if (user.skills.isNotEmpty) ...<Widget>[
              const SizedBox(height: FSpace.lg),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String s in user.skills) FTag(s, fontSize: 10.5)
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Reviews extends StatelessWidget {
  const _Reviews({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Review>>(
      stream: context.engagementRepo.watchReviewsFor(uid),
      builder: (BuildContext context, AsyncSnapshot<List<Review>> snap) {
        if (!snap.hasData) return const FLoading(padding: 16);
        final List<Review> reviews = snap.data!;
        if (reviews.isEmpty) {
          return const FEmptyState(
            icon: Icons.star_border_rounded,
            title: 'No reviews yet',
            message: 'Reviews from completed jobs will appear here.',
          );
        }
        return Column(
          children: <Widget>[
            for (final Review r in reviews) ...<Widget>[
              FCard(
                radius: FRadius.button,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            r.jobTitle,
                            style: FType.titleXs,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: FSpace.md),
                        Text(
                          r.stars,
                          style: FType.pill
                              .copyWith(fontSize: 12, color: FColors.amber),
                        ),
                      ],
                    ),
                    if (r.comment.isNotEmpty) ...<Widget>[
                      const SizedBox(height: FSpace.sm),
                      Text(r.comment, style: FType.support),
                    ],
                    const SizedBox(height: FSpace.sm),
                    Text(
                      '${r.authorName} · ${Fmt.money(r.amount)}',
                      style: FType.captionSm,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FSpace.lg),
            ],
          ],
        );
      },
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    required this.onTap,
    this.color = FColors.ink,
    this.showDivider = true,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          border: showDivider
              ? const Border(bottom: BorderSide(color: FColors.borderFaint))
              : null,
        ),
        child: Text(label,
            style: FType.titleSm
                .copyWith(color: color, fontWeight: FontWeight.w400)),
      ),
    );
  }
}
