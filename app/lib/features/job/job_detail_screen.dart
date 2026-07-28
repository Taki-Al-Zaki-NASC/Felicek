import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/f_button.dart';
import '../../core/widgets/f_field.dart';
import '../../core/widgets/f_pill.dart';
import '../../core/widgets/f_surface.dart';
import '../../data/models/app_user.dart';
import '../../data/models/call_session.dart';
import '../../data/models/job.dart';
import '../../data/models/proposal.dart';
import '../../data/models/public_profile.dart';
import '../../data/models/wallet.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/engagement_repository.dart';
import '../../data/repositories/job_repository.dart';
import '../../data/repositories/proposal_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/call_service.dart';
import '../../data/services/firestore_refs.dart';
import '../call/call_screen.dart';
import '../chat/chat_screen.dart';
import '../kyc/kyc_screen.dart';
import 'challenge_sheet.dart';
import 'post_job_screen.dart';
import 'review_sheet.dart';

class JobDetailScreen extends StatefulWidget {
  const JobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  bool _viewCounted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FColors.canvas,
      body: Column(
        children: <Widget>[
          const FTopBar(title: 'Job Details'),
          Expanded(
            child: StreamBuilder<Job?>(
              stream: context.jobRepo.watch(widget.jobId),
              builder: (BuildContext context, AsyncSnapshot<Job?> snap) {
                if (!snap.hasData && !snap.hasError) return const FLoading();
                final Job? job = snap.data;
                if (job == null) {
                  return const FEmptyState(
                    icon: Icons.work_off_outlined,
                    title: 'Listing unavailable',
                    message: 'This job may have been closed or removed.',
                  );
                }
                if (!_viewCounted) {
                  _viewCounted = true;
                  final String? myUid = context.read<SessionController>().uid;
                  if (myUid != job.ownerId) context.jobRepo.recordView(job.id);
                }

                final AppUser? me = context.watch<SessionController>().user;
                final bool isOwner = me != null && me.uid == job.ownerId;
                return isOwner
                    ? _OwnerView(job: job, owner: me)
                    : _FreelancerView(job: job, user: me);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Freelancer view ─────────────────────────────────────────────────────────

class _FreelancerView extends StatefulWidget {
  const _FreelancerView({required this.job, required this.user});

  final Job job;
  final AppUser? user;

  @override
  State<_FreelancerView> createState() => _FreelancerViewState();
}

class _FreelancerViewState extends State<_FreelancerView> {
  final TextEditingController _bid = TextEditingController();
  final TextEditingController _note = TextEditingController();
  bool _busy = false;
  String? _bidError;

  @override
  void dispose() {
    _bid.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _takeChallenge(Proposal? existing) async {
    final AppUser? user = widget.user;
    if (user == null) return;
    final SkillChallenge challenge = widget.job.challenge;

    if (challenge.mode == ChallengeMode.liveInterview) {
      final DateTime? when = await showDatePicker(
        context: context,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 30)),
      );
      if (when == null || !mounted) return;
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time == null || !mounted) return;
      final DateTime scheduled =
          DateTime(when.year, when.month, when.day, time.hour, time.minute);
      final String proposalId = '${widget.job.id}__${user.uid}';
      await AppFeedback.guard(
        context,
        () => context.proposalRepo
            .scheduleInterview(proposalId: proposalId, scheduledAt: scheduled),
        onSuccess:
            'Interview requested for ${Fmt.dayHeader(scheduled)} · ${Fmt.clock(scheduled)}.',
      );
      return;
    }

    final String proposalId = '${widget.job.id}__${user.uid}';
    // A challenge answer is work the person just spent real time on, so a
    // failed submission must never look like a successful one.
    final bool ok;
    if (challenge.mode == ChallengeMode.quiz) {
      final List<int>? answers =
          await ChallengeSheet.showQuiz(context, challenge);
      if (answers == null || !mounted) return;
      ok = await AppFeedback.guard(
        context,
        () => context.proposalRepo.submitQuizAnswers(
          proposalId: proposalId,
          answers: answers,
          elapsedSeconds: challenge.durationSeconds,
        ),
      );
    } else {
      final String? answer =
          await ChallengeSheet.showWritten(context, challenge);
      if (answer == null || !mounted) return;
      ok = await AppFeedback.guard(
        context,
        () => context.proposalRepo.submitWrittenAnswer(
          proposalId: proposalId,
          fullAnswer: answer,
          elapsedSeconds: challenge.durationSeconds,
        ),
      );
    }
    if (ok && mounted) {
      AppFeedback.success(context, 'Challenge submitted.');
    }
  }

  /// Places the live-interview call and, when it ends, links the call to the
  /// proposal so the challenge registers as completed. Without this the
  /// interview would happen and the proposal would still read "not taken".
  Future<void> _startInterview(BuildContext context, Proposal mine) async {
    final SessionController session = context.read<SessionController>();
    final CallService calls = context.callService;
    final ProposalRepository proposals = context.proposalRepo;
    if (calls.inCall) {
      AppFeedback.error(context, 'You are already on a call.');
      return;
    }

    final Future<void> pushed = Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(
          otherName: widget.job.ownerName,
          otherUid: widget.job.ownerId,
        ),
      ),
    );

    final String? callId = await calls.startCall(
      myUid: session.uid ?? '',
      myName: session.user?.displayName ?? 'You',
      otherUid: widget.job.ownerId,
      otherName: widget.job.ownerName,
      kind: CallKind.video,
    );
    await pushed;

    if (callId != null) {
      if (!context.mounted) return;
      await AppFeedback.guard(
        context,
        () =>
            proposals.recordInterviewCall(proposalId: mine.id, callId: callId),
        onSuccess: 'Interview recorded against your proposal.',
        // The interview already happened; if the link fails, the proposal
        // still reads "not taken" and the person needs to know that.
        onError: 'The interview finished, but it could not be recorded '
            'against your proposal. Try again from the listing.',
      );
    } else if (context.mounted) {
      AppFeedback.error(context, calls.error ?? 'Could not start the call.');
    }
  }

  /// Shows the freelancer their own full answer. Firestore rules scope this
  /// subcollection to its author, so this read succeeds for them and would
  /// fail for the job owner — the privacy boundary is the same one the server
  /// enforces, not a UI decision.
  Future<void> _showMySubmission(BuildContext context, Proposal mine) async {
    final ProposalRepository proposals = context.proposalRepo;
    final String? answer;
    try {
      answer = await proposals.fetchMyFullAnswer(mine.id);
    } on Object catch (e) {
      // Previously unguarded, so a failed read meant the sheet simply never
      // opened — indistinguishable from a dead button.
      if (context.mounted) AppFeedback.error(context, describeFirestoreError(e));
      return;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (BuildContext context, ScrollController scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: <Widget>[
            const Text('Your submission', style: FType.displaySm),
            const SizedBox(height: FSpace.sm),
            const Text(
              'Only you can read this. The client sees a score and a short '
              'excerpt — never the full text.',
              style: FType.caption,
            ),
            const SizedBox(height: FSpace.x3),
            SelectableText(
              answer?.isNotEmpty == true ? answer! : 'Nothing saved yet.',
              style: FType.bodySm,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitProposal(Proposal? existing) async {
    final AppUser? user = widget.user;
    if (user == null) return;

    if (!user.canBid) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
            builder: (_) => const KycScreen(fromProfile: true)),
      );
      AppFeedback.error(
          context, 'Finish verification before submitting proposals.');
      return;
    }

    final String? err = Validate.bid(_bid.text);
    setState(() => _bidError = err);
    if (err != null || _busy) return;

    setState(() => _busy = true);
    try {
      final double amount =
          double.parse(_bid.text.trim().replaceAll(RegExp(r'[$,\s]'), ''));
      await context.proposalRepo.submit(
        job: widget.job,
        freelancer: PublicProfile.fromUser(user),
        bidAmountCents: (amount * 100).round(),
        bidLabel: Fmt.money(amount),
        coverNote: _note.text,
        challenge: existing?.challenge ??
            ChallengeResult(mode: widget.job.challenge.mode),
      );
      if (mounted) {
        AppFeedback.success(context, 'Proposal submitted.');
      }
    } on Object {
      if (mounted) {
        AppFeedback.error(context, 'Could not submit that proposal.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Job job = widget.job;
    final String? myUid = widget.user?.uid;

    return StreamBuilder<Proposal?>(
      stream: myUid == null
          ? const Stream<Proposal?>.empty()
          : context.proposalRepo
              .watchMineForJob(jobId: job.id, freelancerId: myUid),
      builder: (BuildContext context, AsyncSnapshot<Proposal?> snap) {
        // A failed read must not read as "you have not applied": that offers
        // the apply form to someone who already applied, and a second submit
        // is a duplicate proposal the owner then has to untangle. Say the
        // state is unknown instead.
        if (snap.hasError) {
          return FErrorState(message: describeFirestoreError(snap.error!));
        }
        final Proposal? mine = snap.data;
        final bool submitted =
            mine != null && mine.status != ProposalStatus.draft;
        final bool challengeDone = mine?.challenge.completed ?? false;

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: <Widget>[
            FPill.violet(job.typeLabel, fontSize: 10.5),
            const SizedBox(height: FSpace.lg),
            Text(job.title, style: FType.displayLg),
            const SizedBox(height: FSpace.sm),
            Text(
              '${job.budget} · Posted ${Fmt.relative(job.createdAt)}',
              style: FType.caption,
            ),
            const SizedBox(height: FSpace.x3),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FPill.teal('${job.trustScore}% Client Trust'),
                if (job.escrowFunded) FPill.blue('Escrow Verified'),
                FPill.neutral('${job.proposalsCount} Applicants'),
              ],
            ),
            const SizedBox(height: FSpace.x3),
            const FSectionLabel('Project Scope'),
            const SizedBox(height: FSpace.lg),
            Text(job.scope, style: FType.body),
            const SizedBox(height: FSpace.x4),
            const FSectionLabel('Milestones'),
            const SizedBox(height: FSpace.lg),
            for (final Milestone m in job.milestones)
              Container(
                margin: const EdgeInsets.only(bottom: FSpace.md),
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  color: FColors.surfaceSunken,
                  borderRadius: FRadius.rowR,
                  border: Border.all(color: FColors.borderFaint),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(m.label, style: FType.bodyXs.copyWith(fontSize: 12.5)),
                    Text(m.amount, style: FType.money.copyWith(fontSize: 12)),
                  ],
                ),
              ),
            const SizedBox(height: FSpace.lg),
            if (job.hasChallenge) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: FColors.violetTint,
                  borderRadius: FRadius.cardR,
                  border:
                      Border.all(color: FColors.violet.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          job.challenge.modeLabel.toUpperCase(),
                          style: FType.sectionLabel.copyWith(
                            color: FColors.violet,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          job.challenge.mode == ChallengeMode.liveInterview
                              ? 'call session'
                              : '${job.challenge.durationLabel} preview',
                          style: FType.captionSm.copyWith(fontSize: 9.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: FSpace.lg),
                    if (job.challenge.mode == ChallengeMode.writtenPrompt)
                      Text(job.challenge.prompt,
                          style: FType.bodySm.copyWith(fontSize: 12.5))
                    else if (job.challenge.mode == ChallengeMode.quiz)
                      Text(
                        '${job.challenge.questions.length} multiple-choice questions.',
                        style: FType.bodySm.copyWith(fontSize: 12.5),
                      )
                    else
                      Text(
                        'A short live call with the client instead of a written test.',
                        style: FType.bodySm.copyWith(fontSize: 12.5),
                      ),
                    const SizedBox(height: FSpace.xl),
                    if (job.challenge.mode == ChallengeMode.liveInterview &&
                        mine?.challenge.interviewScheduledAt != null &&
                        !challengeDone) ...<Widget>[
                      FButton.compact(
                        label: 'Start Interview Call',
                        variant: FButtonVariant.teal,
                        onPressed: () => _startInterview(context, mine!),
                      ),
                      const SizedBox(height: FSpace.md),
                    ],
                    if (challengeDone &&
                        mine != null &&
                        mine.challenge.hasFullSubmission) ...<Widget>[
                      FTextAction(
                        label: 'View my submission',
                        color: FColors.violet,
                        fontSize: 11.5,
                        onPressed: () => _showMySubmission(context, mine),
                      ),
                      const SizedBox(height: FSpace.md),
                    ],
                    FButton.compact(
                      label: challengeDone
                          ? 'Challenge Completed ✓'
                          : job.challenge.mode == ChallengeMode.liveInterview
                              ? 'Request Interview Slot'
                              : 'Start ${job.challenge.durationLabel} Challenge',
                      variant: challengeDone
                          ? FButtonVariant.success
                          : FButtonVariant.violet,
                      onPressed:
                          challengeDone ? null : () => _takeChallenge(mine),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FSpace.x3),
            ],
            const FSectionLabel('Your Bid'),
            const SizedBox(height: FSpace.lg),
            FField(
              controller: _bid,
              hint: 'Enter your bid amount',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              errorText: _bidError,
              enabled: !submitted,
            ),
            const SizedBox(height: FSpace.lg),
            FField(
              controller: _note,
              hint: 'Add a short note about your approach (recommended)',
              multiline: true,
              height: 80,
              enabled: !submitted,
            ),
            if (mine != null &&
                mine.status == ProposalStatus.completed) ...<Widget>[
              const SizedBox(height: FSpace.x2),
              FButton(
                label: 'Review ${job.ownerName}',
                variant: FButtonVariant.secondary,
                onPressed: () => ReviewSheet.show(
                  context,
                  job: job,
                  proposal: mine,
                  subjectId: job.ownerId,
                  subjectName: job.ownerName,
                ),
              ),
            ],
            const SizedBox(height: FSpace.x2),
            FButton(
              label: submitted ? 'Proposal Submitted ✓' : 'Submit Proposal',
              variant:
                  submitted ? FButtonVariant.success : FButtonVariant.primary,
              busy: _busy,
              onPressed: submitted ? null : () => _submitProposal(mine),
            ),
          ],
        );
      },
    );
  }
}

// ── Owner view ───────────────────────────────────────────────────────────

class _OwnerView extends StatelessWidget {
  const _OwnerView({required this.job, required this.owner});

  final Job job;
  final AppUser owner;

  @override
  Widget build(BuildContext context) {
    final int maxWeekly = job.weeklyApplicants.isEmpty
        ? 1
        : job.weeklyApplicants.reduce((a, b) => a > b ? a : b);
    const List<String> dayLabels = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        FPill.violet(job.typeLabel, fontSize: 10.5),
        const SizedBox(height: FSpace.lg),
        Text(job.title, style: FType.displayLg),
        const SizedBox(height: FSpace.sm),
        Text('${job.budget} · Posted ${Fmt.relative(job.createdAt)}',
            style: FType.caption),
        const SizedBox(height: FSpace.x3),
        if (job.isHired) ...<Widget>[
          _EscrowPanel(job: job),
          const SizedBox(height: FSpace.x3),
        ],
        const FSectionLabel('Listing Analytics'),
        const SizedBox(height: FSpace.lg),
        Row(
          children: <Widget>[
            FStatTile(value: '${job.views}', label: 'Views'),
            const SizedBox(width: FSpace.lg),
            FStatTile(
              value: '${job.shortlisted}',
              label: 'Shortlisted',
              valueColor: FColors.blue,
            ),
            const SizedBox(width: FSpace.lg),
            FStatTile(
              value: job.avgBidPlaceholder,
              label: 'Avg. Bid',
              valueColor: FColors.tealDeep,
              fontSize: 14,
            ),
          ],
        ),
        const SizedBox(height: FSpace.x3),
        FCard(
          radius: FRadius.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Applicants — last 7 days',
                  style: FType.caption.copyWith(fontSize: 10.5)),
              const SizedBox(height: FSpace.lg),
              SizedBox(
                height: 80,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    for (int i = 0; i < job.weeklyApplicants.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor:
                                        (job.weeklyApplicants[i] / maxWeekly)
                                            .clamp(0.02, 1.0),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: FColors.teal,
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(4),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: FSpace.sm),
                              Text(dayLabels[i % 7],
                                  style: FType.captionSm.copyWith(fontSize: 9)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FSpace.x3),
        const FSectionLabel('Applicants & Skill Challenge Results'),
        const SizedBox(height: FSpace.lg),
        StreamBuilder<List<Proposal>>(
          stream: context.proposalRepo.watchForJob(job.id),
          builder: (BuildContext context, AsyncSnapshot<List<Proposal>> snap) {
            final List<Proposal> applicants = snap.data ?? const <Proposal>[];
            if (snap.hasError) {
              return FErrorState(
                  message: describeFirestoreError(snap.error!));
            }
            if (!snap.hasData) return const FLoading();
            if (applicants.isEmpty) {
              return const FEmptyState(
                icon: Icons.people_outline_rounded,
                title: 'No applicants yet',
                message: 'Proposals will appear here as freelancers apply.',
              );
            }
            return Column(
              children: <Widget>[
                for (final Proposal p in applicants) ...<Widget>[
                  _ApplicantCard(job: job, proposal: p),
                  const SizedBox(height: FSpace.lg),
                ],
              ],
            );
          },
        ),
        if (job.hasEquity) ...<Widget>[
          const SizedBox(height: FSpace.x2),
          const FSectionLabel('Equity Offered (optional)'),
          const SizedBox(height: FSpace.lg),
          FField(hint: job.equity ?? ''),
        ],
        const SizedBox(height: FSpace.x3),
        Row(
          children: <Widget>[
            Expanded(
              child: FButton(
                label: 'Edit Listing',
                fontSize: 13,
                padding: const EdgeInsets.all(14),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PostJobScreen(existing: job),
                  ),
                ),
              ),
            ),
            const SizedBox(width: FSpace.lg),
            Expanded(
              child: FButton(
                label: 'Close Listing',
                variant: FButtonVariant.danger,
                fontSize: 13,
                padding: const EdgeInsets.all(14),
                onPressed: () async {
                  final JobRepository jobs = context.jobRepo;
                  final bool ok = await AppFeedback.confirm(
                    context,
                    title: 'Close this listing?',
                    message: 'It will no longer accept proposals.',
                    confirmLabel: 'Close',
                    destructive: true,
                  );
                  if (!ok || !context.mounted) return;
                  await AppFeedback.guard(
                    context,
                    () => jobs.setStatus(job.id, JobStatus.closed),
                    onSuccess: 'Listing closed.',
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ApplicantCard extends StatelessWidget {
  const _ApplicantCard({required this.job, required this.proposal});

  final Job job;
  final Proposal proposal;

  /// Hiring funds escrow out of the client's posting balance and opens the
  /// thread the engagement's event lines are posted into.
  Future<void> _hire(BuildContext context) async {
    final bool ok = await AppFeedback.confirm(
      context,
      title: 'Hire ${proposal.freelancerName}?',
      message:
          '${proposal.bidLabel} moves from your posting balance into escrow, '
          'and the listing closes to new proposals.',
      confirmLabel: 'Hire',
    );
    if (!ok || !context.mounted) return;

    final SessionController session = context.read<SessionController>();
    final PublicProfile? me = session.publicProfile;
    final EngagementRepository engagements = context.engagementRepo;
    final UserRepository users = context.userRepo;
    final ChatRepository chats = context.chatRepo;
    if (me == null) return;

    try {
      final PublicProfile? other =
          await users.fetchProfile(proposal.freelancerId);
      if (other == null) {
        if (context.mounted) {
          AppFeedback.error(context, 'That freelancer is no longer available.');
        }
        return;
      }
      final String chatId = await chats.openThread(
        me: me,
        other: other,
        jobId: job.id,
        jobTitle: job.title,
      );
      await engagements.hire(job: job, proposal: proposal, chatId: chatId);
      if (context.mounted) {
        AppFeedback.success(context, 'Hired — escrow funded.');
      }
    } on InsufficientPostingBalance catch (e) {
      if (context.mounted) AppFeedback.error(context, e.message);
    } on Object {
      if (context.mounted) {
        AppFeedback.error(context, 'Could not complete the hire. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isQuiz = proposal.challenge.mode == ChallengeMode.quiz;

    return FCard(
      radius: FRadius.card,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Expanded(
                child: Text(
                  proposal.freelancerName,
                  style: FType.titleSm,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(proposal.bidLabel, style: FType.money),
            ],
          ),
          const SizedBox(height: FSpace.md),
          Row(
            children: <Widget>[
              FPill.teal('${proposal.freelancerTrustScore}% Trust'),
              const SizedBox(width: FSpace.md),
              if (isQuiz && proposal.challenge.score != null)
                FPill.violet('Score ${proposal.challenge.score}%')
              else
                FPill(
                  proposal.challengeLabel,
                  color: proposal.challenge.completed
                      ? FColors.teal
                      : (proposal.reviewNote != null
                          ? FColors.blue
                          : FColors.danger),
                  background: proposal.challenge.completed
                      ? FColors.tealTint
                      : (proposal.reviewNote != null
                          ? FColors.blueTint
                          : FColors.dangerTint),
                ),
              if (isQuiz &&
                  proposal.challenge.score == null &&
                  proposal.challenge.completed) ...<Widget>[
                const SizedBox(width: FSpace.md),
                InkWell(
                  onTap: () => AppFeedback.guard(
                    context,
                    () => context.proposalRepo
                        .gradeQuiz(jobId: job.id, proposal: proposal),
                  ),
                  child: Text(
                    'Grade now',
                    style: FType.pill
                        .copyWith(fontSize: 10.5, color: FColors.violet),
                  ),
                ),
              ],
            ],
          ),
          if (proposal.challenge.answerPreview.isNotEmpty) ...<Widget>[
            const SizedBox(height: FSpace.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: FColors.surfaceSunken,
                borderRadius: FRadius.rowR,
                border: Border.all(color: FColors.borderFaint),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    proposal.challenge.answerPreview,
                    style: FType.supportSm
                        .copyWith(fontSize: 11.5, color: FColors.inkBody),
                  ),
                  if (proposal.challenge.hasFullSubmission)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Full submission is private to the applicant until hired.',
                        style: FType.captionSm.copyWith(fontSize: 9.5),
                      ),
                    ),
                ],
              ),
            ),
          ] else if (proposal.reviewNote != null) ...<Widget>[
            const SizedBox(height: FSpace.md),
            Text(proposal.reviewNote!,
                style: FType.supportSm.copyWith(fontSize: 11.5)),
          ],
          if (proposal.canMessage) ...<Widget>[
            const SizedBox(height: FSpace.md),
            Wrap(
              spacing: FSpace.md,
              children: <Widget>[
                FTextAction(
                  label: 'Message',
                  background: FColors.tealTint,
                  fontSize: 11,
                  onPressed: () => openChatWith(
                    context,
                    otherUid: proposal.freelancerId,
                    jobId: job.id,
                    jobTitle: job.title,
                    headerName: proposal.freelancerName,
                  ),
                ),
                if (!job.isHired &&
                    (proposal.status == ProposalStatus.submitted ||
                        proposal.status == ProposalStatus.shortlisted))
                  FTextAction(
                    label: proposal.status == ProposalStatus.shortlisted
                        ? 'Shortlisted ✓'
                        : 'Shortlist',
                    background: FColors.blueTint,
                    color: FColors.blue,
                    fontSize: 11,
                    onPressed: () => AppFeedback.guard(
                      context,
                      () => context.engagementRepo.shortlist(
                        proposal: proposal,
                        on: proposal.status != ProposalStatus.shortlisted,
                      ),
                    ),
                  ),
                if (!job.isHired &&
                    (proposal.status == ProposalStatus.submitted ||
                        proposal.status == ProposalStatus.shortlisted))
                  FTextAction(
                    label: 'Hire',
                    background: FColors.inkStrong,
                    color: Colors.white,
                    fontSize: 11,
                    onPressed: () => _hire(context),
                  ),
                if (job.hiredProposalId == proposal.id)
                  FPill.teal('Hired', fontSize: 10.5),
                if (job.hiredProposalId == proposal.id && job.isFullyReleased)
                  FTextAction(
                    label: 'Leave a review',
                    background: FColors.amberTint,
                    color: FColors.amber,
                    fontSize: 11,
                    onPressed: () => ReviewSheet.show(
                      context,
                      job: job,
                      proposal: proposal,
                      subjectId: proposal.freelancerId,
                      subjectName: proposal.freelancerName,
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

// ── Escrow / milestone release ─────────────────────────────────────────────

/// The owner's release panel: what is still held in escrow, and a Release
/// button per milestone.
///
/// This is the half of the marketplace that actually moves money. Releasing
/// the final milestone completes the engagement — the job closes, the
/// freelancer's job count moves, and their refundable trust bond unlocks. All
/// of that happens in one transaction inside [EngagementRepository].
class _EscrowPanel extends StatefulWidget {
  const _EscrowPanel({required this.job});

  final Job job;

  @override
  State<_EscrowPanel> createState() => _EscrowPanelState();
}

class _EscrowPanelState extends State<_EscrowPanel> {
  int? _releasing;

  Future<void> _release(Proposal hired, int index) async {
    final Milestone m = widget.job.milestones[index];
    final bool isFinal = widget.job.milestones.asMap().entries.every(
        (MapEntry<int, Milestone> e) => e.key == index || e.value.released);

    final bool ok = await AppFeedback.confirm(
      context,
      title: 'Release "${m.label}"?',
      message: isFinal
          ? 'This is the last milestone. Releasing it pays ${hired.freelancerName}, '
              'closes the engagement, and unlocks their trust deposit. This cannot '
              'be undone.'
          : 'This pays ${hired.freelancerName} for this milestone. It cannot be undone.',
      confirmLabel: 'Release',
    );
    if (!ok || !mounted) return;

    final EngagementRepository engagements = context.engagementRepo;
    setState(() => _releasing = index);
    try {
      await engagements.releaseMilestone(
        job: widget.job,
        proposal: hired,
        milestoneIndex: index,
      );
      if (mounted) {
        AppFeedback.success(
          context,
          isFinal ? 'Engagement complete.' : 'Milestone released.',
        );
      }
    } on Object {
      if (mounted) {
        AppFeedback.error(
            context, 'Could not release that milestone. Try again.');
      }
    } finally {
      if (mounted) setState(() => _releasing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Job job = widget.job;

    return StreamBuilder<List<Proposal>>(
      stream: context.proposalRepo.watchForJob(job.id),
      builder: (BuildContext context, AsyncSnapshot<List<Proposal>> snap) {
        // Without this the whole escrow panel disappeared on a failed read,
        // so the client could not release a milestone and nothing on screen
        // suggested there was anything to release.
        if (snap.hasError) {
          return FErrorState(message: describeFirestoreError(snap.error!));
        }
        Proposal? hired;
        for (final Proposal p in snap.data ?? const <Proposal>[]) {
          if (p.id == job.hiredProposalId) hired = p;
        }
        if (hired == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FColors.tealTint,
            borderRadius: FRadius.cardR,
            border: Border.all(color: FColors.teal.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  const FSectionLabel('Escrow', color: FColors.tealDarker),
                  FPill.teal('Hired · ${hired.freelancerName}', fontSize: 10),
                ],
              ),
              const SizedBox(height: FSpace.lg),
              Text(
                job.isFullyReleased
                    ? 'All milestones released'
                    : '${Fmt.moneyExact(job.escrowHeld)} still held',
                style: FType.titleLg.copyWith(fontSize: 22),
              ),
              const SizedBox(height: FSpace.x2),
              for (int i = 0; i < job.milestones.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: FSpace.md),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 10),
                    decoration: BoxDecoration(
                      color: FColors.surface,
                      borderRadius: FRadius.rowR,
                      border: Border.all(color: FColors.borderFaint),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          job.milestones[i].released
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 16,
                          color: job.milestones[i].released
                              ? FColors.teal
                              : FColors.inkFaint,
                        ),
                        const SizedBox(width: FSpace.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                job.milestones[i].label,
                                style: FType.bodyXs.copyWith(fontSize: 12.5),
                              ),
                              Text(
                                job.milestones[i].amount,
                                style: FType.money.copyWith(fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                        if (job.milestones[i].released)
                          FPill.teal('Released', fontSize: 10)
                        else if (_releasing == i)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: FColors.teal,
                            ),
                          )
                        else
                          FTextAction(
                            label: 'Release',
                            background: FColors.inkStrong,
                            color: Colors.white,
                            fontSize: 11,
                            onPressed: () => _release(hired!, i),
                          ),
                      ],
                    ),
                  ),
                ),
              Text(
                'Released funds reach the freelancer immediately, net of the flat '
                '${Fees.label(PayoutMethod.bkash)} maintenance fee.',
                style: FType.captionSm.copyWith(fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }
}
