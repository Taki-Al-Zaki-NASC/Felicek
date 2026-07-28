import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/f_avatar.dart';
import '../../core/widgets/f_button.dart';
import '../../core/widgets/f_field.dart';
import '../../core/widgets/f_pill.dart';
import '../../core/widgets/f_surface.dart';
import '../../data/models/app_user.dart';
import '../../data/models/job.dart';
import '../../data/models/team_seat.dart';
import '../../data/models/user_role.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/firestore_refs.dart';
import '../job/job_card.dart';
import '../job/job_detail_screen.dart';
import '../job/post_job_screen.dart';
import '../kyc/kyc_screen.dart';
import '../notifications/notifications_screen.dart';
import '../search/search_screen.dart';

/// The Home tab: freelancers get the browse feed, everyone else gets their
/// posting dashboard — exactly the split the design draws with
/// `isBrowseHome` / `isDashboardHome`.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final AppUser? user = context.select<SessionController, AppUser?>(
      (SessionController s) => s.user,
    );
    if (user == null) return const FLoading();

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _Header(
              user: user,
              showFilters: user.role.browsesListings,
              filter: _filter,
              onFilter: (String f) => setState(() => _filter = f),
            ),
            Expanded(
              child: user.role.browsesListings
                  ? _BrowseFeed(filter: _filter)
                  : _Dashboard(user: user),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.showFilters,
    required this.filter,
    required this.onFilter,
  });

  final AppUser user;
  final bool showFilters;
  final String filter;
  final ValueChanged<String> onFilter;

  static const List<(String, String)> _filters = <(String, String)>[
    ('all', 'All'),
    ('freelance', 'Freelance'),
    ('agency', 'Agency'),
    ('startup', 'Startup'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FColors.surface,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('Felicek', style: FType.displayMd.copyWith(fontSize: 20)),
              Row(
                children: <Widget>[
                  FRoleBadge(user.role.shortLabel),
                  const SizedBox(width: FSpace.md),
                  const NotificationBell(),
                  const SizedBox(width: FSpace.sm),
                  InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const KycScreen(fromProfile: true),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(15),
                    child: FAvatar(
                      size: 30,
                      photoBase64: user.profilePhotoBase64,
                      initials: FAvatar.initialsFor(user.displayName),
                      verified: user.kyc.isVerified,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (user.role == UserRole.freelancer) ...<Widget>[
            const SizedBox(height: FSpace.xl),
            _VaultBar(user: user),
          ],
          const SizedBox(height: FSpace.xl),
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
            ),
            borderRadius: FRadius.buttonR,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: FColors.neutralTint,
                borderRadius: FRadius.buttonR,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.search_rounded,
                      size: 15, color: FColors.inkFaint),
                  const SizedBox(width: FSpace.md),
                  Text(
                    showFilters
                        ? 'Search jobs, skills, or clients...'
                        : 'Search freelancers or listings...',
                    style: FType.bodyXs
                        .copyWith(fontSize: 12.5, color: FColors.inkFaint),
                  ),
                ],
              ),
            ),
          ),
          if (showFilters) ...<Widget>[
            const SizedBox(height: FSpace.xl),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: FSpace.md),
                itemBuilder: (BuildContext context, int i) {
                  final (String key, String label) = _filters[i];
                  return FChoiceChip(
                    label: label,
                    selected: filter == key,
                    onTap: () => onFilter(key),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VaultBar extends StatelessWidget {
  const _VaultBar({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final bool locked = user.vaultLocked;
    return InkWell(
      onTap: () => AppFeedback.toast(
        context,
        'Open the Payment tab to view your Trust Fund Vault.',
      ),
      borderRadius: FRadius.buttonR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: FColors.tealTint,
          borderRadius: FRadius.buttonR,
          border: Border.all(color: FColors.teal.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: locked ? FColors.amber : FColors.teal,
                  ),
                ),
                const SizedBox(width: FSpace.lg),
                RichText(
                  text: TextSpan(
                    style: FType.captionSm
                        .copyWith(fontSize: 11.5, color: FColors.tealDarker),
                    children: <InlineSpan>[
                      const TextSpan(text: 'Trust Fund Vault · '),
                      TextSpan(
                        text: '\$20.00',
                        style: FType.pill
                            .copyWith(fontSize: 11.5, color: FColors.ink),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Text(
              '${locked ? 'Locked' : 'Withdrawable'} ›',
              style: FType.pill.copyWith(fontSize: 10.5, color: FColors.teal),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowseFeed extends StatelessWidget {
  const _BrowseFeed({required this.filter});

  final String filter;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Job>>(
      stream: context.jobRepo.watchOpenJobs(type: filter),
      builder: (BuildContext context, AsyncSnapshot<List<Job>> snap) {
        if (snap.hasError) {
          return FErrorState(message: describeFirestoreError(snap.error!));
        }
        if (!snap.hasData) return const FLoading();
        final List<Job> jobs = snap.data!;
        if (jobs.isEmpty) {
          return const FEmptyState(
            icon: Icons.work_outline_rounded,
            title: 'No listings yet',
            message: 'New jobs will show up here as soon as they are posted.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
          itemCount: jobs.length,
          separatorBuilder: (_, __) => const SizedBox(height: FSpace.xl),
          itemBuilder: (BuildContext context, int i) => JobCard(
            job: jobs[i],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => JobDetailScreen(jobId: jobs[i].id),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Job>>(
      stream: context.jobRepo.watchMyJobs(user.uid),
      builder: (BuildContext context, AsyncSnapshot<List<Job>> snap) {
        // A failed read must not render as "$0 funded, 0 proposals" — that is
        // a confident, wrong answer about the client's own money.
        if (snap.hasError) {
          return FErrorState(message: describeFirestoreError(snap.error!));
        }
        final List<Job> jobs = snap.data ?? const <Job>[];
        final int escrowFunded = jobs.fold<int>(
          0,
          (int sum, Job j) => sum + ((j.budgetValue ?? 0).round()),
        );
        final int proposals =
            jobs.fold<int>(0, (int sum, Job j) => sum + j.proposalsCount);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
          children: <Widget>[
            Row(
              children: <Widget>[
                FStatTile(value: '${jobs.length}', label: 'Active Listings'),
                const SizedBox(width: FSpace.lg),
                FStatTile(
                  value: '\$$escrowFunded',
                  label: 'Escrow Funded',
                  valueColor: FColors.teal,
                ),
                const SizedBox(width: FSpace.lg),
                FStatTile(
                  value: '$proposals',
                  label: 'Proposals',
                  valueColor: FColors.blue,
                ),
              ],
            ),
            const SizedBox(height: FSpace.x3),
            FButton(
              label: '+ Post a New Job',
              padding: const EdgeInsets.all(14),
              fontSize: 13.5,
              onPressed: () {
                if (!user.canPostJob) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const KycScreen(fromProfile: true),
                    ),
                  );
                  AppFeedback.error(
                    context,
                    'Finish verification and your posting balance before publishing a job.',
                  );
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const PostJobScreen()),
                );
              },
            ),
            if (user.role == UserRole.agency) ...<Widget>[
              const SizedBox(height: FSpace.x3),
              const FSectionLabel('Team Seats'),
              const SizedBox(height: FSpace.lg),
              _TeamSeats(agency: user),
            ],
            if (user.role == UserRole.startup) ...<Widget>[
              const SizedBox(height: FSpace.x3),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: FColors.violetTint,
                  borderRadius: FRadius.cardR,
                  border:
                      Border.all(color: FColors.violet.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'FAST-TRACK HIRING & EQUITY',
                      style: FType.sectionLabel.copyWith(
                        color: FColors.violet,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: FSpace.sm),
                    const Text(
                      'Your Startup Verification Badge is active — listings get '
                      'priority placement and can offer equity-based milestone pay.',
                      style: FType.bodySm,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: FSpace.x3),
            const FSectionLabel('Your Listings'),
            const SizedBox(height: FSpace.lg),
            if (jobs.isEmpty)
              const FEmptyState(
                icon: Icons.post_add_rounded,
                title: 'Nothing posted yet',
                message: 'Publish your first job to start receiving proposals.',
              )
            else
              Column(
                children: <Widget>[
                  for (final Job job in jobs) ...<Widget>[
                    JobCard(
                      job: job,
                      compact: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => JobDetailScreen(jobId: job.id),
                        ),
                      ),
                    ),
                    const SizedBox(height: FSpace.xl),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }
}

/// Agency team seats.
///
/// The design showed a static roster. A seat here is a real invite: the agency
/// records the teammate's email, and when that person signs up with it their
/// account is linked to the agency. Until then the seat reads "Invited", which
/// is the honest state rather than a name that implies someone is on board.
class _TeamSeats extends StatelessWidget {
  const _TeamSeats({required this.agency});

  final AppUser agency;

  Future<void> _invite(BuildContext context) async {
    final TextEditingController email = TextEditingController();
    final TextEditingController role = TextEditingController();
    final UserRepository users = context.userRepo;

    final bool? send = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Invite a teammate', style: FType.titleMd),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FField(
              controller: email,
              label: 'Email',
              hint: 'teammate@example.com',
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
            ),
            const SizedBox(height: FSpace.xl),
            FField(controller: role, label: 'Role', hint: 'e.g. Backend Lead'),
          ],
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
              'Send invite',
              style: FType.buttonSm
                  .copyWith(fontSize: 13, color: FColors.tealDeep),
            ),
          ),
        ],
      ),
    );

    final String address = email.text.trim();
    final String seatRole = role.text.trim();
    email.dispose();
    role.dispose();

    if (send != true || address.isEmpty) return;
    if (Validate.email(address) != null) {
      if (context.mounted) {
        AppFeedback.error(context, 'That email address does not look right.');
      }
      return;
    }

    try {
      await users.inviteTeamSeat(
        agencyUid: agency.uid,
        email: address,
        role: seatRole.isEmpty ? 'Team member' : seatRole,
      );
      if (context.mounted) AppFeedback.success(context, 'Invite recorded.');
    } on Object {
      if (context.mounted) {
        AppFeedback.error(context, 'Could not save that invite. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TeamSeat>>(
      stream: context.userRepo.watchTeamSeats(agency.uid),
      builder: (BuildContext context, AsyncSnapshot<List<TeamSeat>> snap) {
        if (snap.hasError) {
          return FErrorState(message: describeFirestoreError(snap.error!));
        }
        final List<TeamSeat> seats = snap.data ?? const <TeamSeat>[];
        return Column(
          children: <Widget>[
            for (final TeamSeat seat in seats) ...<Widget>[
              FCard(
                radius: FRadius.button,
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                child: Row(
                  children: <Widget>[
                    FAvatar(
                      size: 30,
                      seed: seat.email,
                      initials: FAvatar.initialsFor(
                        seat.displayName ?? seat.email,
                      ),
                      verified: seat.accepted,
                    ),
                    const SizedBox(width: FSpace.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            seat.displayName ?? seat.email,
                            style: FType.titleXs,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(seat.role, style: FType.captionSm),
                        ],
                      ),
                    ),
                    seat.accepted
                        ? FPill.teal('Active', fontSize: 10)
                        : FPill.amber('Invited', fontSize: 10),
                    IconButton(
                      onPressed: () => AppFeedback.guard(
                        context,
                        () => context.userRepo.removeTeamSeat(
                            agencyUid: agency.uid, seatId: seat.id),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 15),
                      color: FColors.inkFaint,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Remove seat',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FSpace.md),
            ],
            FButton(
              label: '+ Invite a teammate',
              variant: FButtonVariant.secondary,
              padding: const EdgeInsets.all(12),
              fontSize: 12.5,
              onPressed: () => _invite(context),
            ),
          ],
        );
      },
    );
  }
}
