import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/f_pill.dart';
import '../../core/widgets/f_surface.dart';
import '../../data/models/app_user.dart';
import '../../data/models/proposal.dart';
import '../job/job_detail_screen.dart';

/// "My Proposals" for freelancers, "Proposal Queue" for reviewers — including
/// the AI spam-filter banner from the design, now backed by the real
/// on-device [SpamFilter] score instead of a static count.
class ProposalsScreen extends StatelessWidget {
  const ProposalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppUser? user =
        context.select<SessionController, AppUser?>((s) => s.user);
    if (user == null) return const FLoading();
    final bool isReviewer = user.role.reviewsProposals;

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Container(
              color: FColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    isReviewer ? 'Proposal Queue' : 'My Proposals',
                    style: FType.displayMd,
                  ),
                  if (isReviewer) ...<Widget>[
                    const SizedBox(height: FSpace.lg),
                    _SpamBanner(ownerId: user.uid),
                  ],
                ],
              ),
            ),
            Expanded(
              child: isReviewer
                  ? _IncomingList(ownerId: user.uid)
                  : _MineList(freelancerId: user.uid),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpamBanner extends StatelessWidget {
  const _SpamBanner({required this.ownerId});

  final String ownerId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: context.proposalRepo.spamBlockedThisWeek(ownerId),
      builder: (BuildContext context, AsyncSnapshot<int> snap) {
        final int count = snap.data ?? 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: FColors.tealTint,
            borderRadius: FRadius.chipR,
            border: Border.all(color: FColors.teal.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: FColors.teal, shape: BoxShape.circle),
              ),
              const SizedBox(width: FSpace.md),
              Expanded(
                child: Text(
                  'AI spam filter blocked $count generic proposals this week',
                  style: FType.captionSm
                      .copyWith(fontSize: 10.5, color: FColors.tealDarker),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MineList extends StatelessWidget {
  const _MineList({required this.freelancerId});

  final String freelancerId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Proposal>>(
      stream: context.proposalRepo.watchMine(freelancerId),
      builder: (BuildContext context, AsyncSnapshot<List<Proposal>> snap) {
        if (!snap.hasData) return const FLoading();
        final List<Proposal> items = snap.data!;
        if (items.isEmpty) {
          return const FEmptyState(
            icon: Icons.description_outlined,
            title: 'No proposals yet',
            message: 'Bids you submit on listings will show up here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: FSpace.xl),
          itemBuilder: (BuildContext context, int i) => _ProposalRow(
            title: items[i].jobTitle,
            note: items[i].coverNote.isEmpty
                ? 'Awaiting client review'
                : items[i].coverNote,
            amount: items[i].bidLabel,
            time: Fmt.relative(items[i].createdAt),
            status: items[i].status,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => JobDetailScreen(jobId: items[i].jobId),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IncomingList extends StatelessWidget {
  const _IncomingList({required this.ownerId});

  final String ownerId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Proposal>>(
      stream: context.proposalRepo.watchIncoming(ownerId),
      builder: (BuildContext context, AsyncSnapshot<List<Proposal>> snap) {
        if (!snap.hasData) return const FLoading();
        final List<Proposal> items = snap.data!;
        if (items.isEmpty) {
          return const FEmptyState(
            icon: Icons.inbox_outlined,
            title: 'No proposals yet',
            message: 'Bids on your listings will appear here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: FSpace.xl),
          itemBuilder: (BuildContext context, int i) => _ProposalRow(
            title: items[i].jobTitle,
            note: items[i].status == ProposalStatus.flaggedSpam
                ? 'Generic copy-paste proposal detected — no project-specific details'
                : 'From ${items[i].freelancerName} · ${items[i].freelancerTrustScore}% trust score',
            amount: '${items[i].bidLabel} bid',
            time: Fmt.relative(items[i].createdAt),
            status: items[i].status,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => JobDetailScreen(jobId: items[i].jobId),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProposalRow extends StatelessWidget {
  const _ProposalRow({
    required this.title,
    required this.note,
    required this.amount,
    required this.time,
    required this.status,
    required this.onTap,
  });

  final String title;
  final String note;
  final String amount;
  final String time;
  final ProposalStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ({Color color, Color bg}) palette = switch (status) {
      ProposalStatus.accepted || ProposalStatus.completed => (
          color: FColors.teal,
          bg: FColors.tealTint
        ),
      ProposalStatus.flaggedSpam || ProposalStatus.declined => (
          color: FColors.danger,
          bg: FColors.dangerTint
        ),
      ProposalStatus.shortlisted => (color: FColors.blue, bg: FColors.blueTint),
      ProposalStatus.submitted || ProposalStatus.draft => (
          color: FColors.inkMuted,
          bg: FColors.neutralTint
        ),
    };
    final String label = switch (status) {
      ProposalStatus.flaggedSpam => 'Flagged Spam',
      _ => status.label,
    };

    return FCard(
      radius: FRadius.card,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: Text(title,
                    style: FType.titleXs, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: FSpace.md),
              FPill(label,
                  color: palette.color, background: palette.bg, fontSize: 10),
            ],
          ),
          const SizedBox(height: FSpace.md),
          Text(note,
              style: FType.supportSm,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: FSpace.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(amount,
                  style: FType.pill
                      .copyWith(fontSize: 11.5, color: FColors.tealDeep)),
              Text(time, style: FType.caption.copyWith(fontSize: 10.5)),
            ],
          ),
        ],
      ),
    );
  }
}
