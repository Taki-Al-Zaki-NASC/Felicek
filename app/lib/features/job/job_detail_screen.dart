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
import '../../data/models/job.dart';
import '../../data/models/proposal.dart';
import '../../data/models/public_profile.dart';
import '../../data/repositories/job_repository.dart';
import '../chat/chat_screen.dart';
import '../kyc/kyc_screen.dart';
import 'challenge_sheet.dart';

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
      await context.proposalRepo
          .scheduleInterview(proposalId: proposalId, scheduledAt: scheduled);
      if (mounted) {
        AppFeedback.success(
          context,
          'Interview requested for ${Fmt.dayHeader(scheduled)} · ${Fmt.clock(scheduled)}.',
        );
      }
      return;
    }

    final String proposalId = '${widget.job.id}__${user.uid}';
    if (challenge.mode == ChallengeMode.quiz) {
      final List<int>? answers =
          await ChallengeSheet.showQuiz(context, challenge);
      if (answers == null || !mounted) return;
      await context.proposalRepo.submitQuizAnswers(
        proposalId: proposalId,
        answers: answers,
        elapsedSeconds: challenge.durationSeconds,
      );
    } else {
      final String? answer =
          await ChallengeSheet.showWritten(context, challenge);
      if (answer == null || !mounted) return;
      await context.proposalRepo.submitWrittenAnswer(
        proposalId: proposalId,
        fullAnswer: answer,
        elapsedSeconds: challenge.durationSeconds,
      );
    }
    if (mounted) {
      AppFeedback.success(context, 'Challenge submitted.');
    }
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
                onPressed: () {},
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
                  if (ok) await jobs.setStatus(job.id, JobStatus.closed);
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
                  onTap: () => context.proposalRepo
                      .gradeQuiz(jobId: job.id, proposal: proposal),
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
                if (proposal.status == ProposalStatus.submitted ||
                    proposal.status == ProposalStatus.shortlisted)
                  FTextAction(
                    label: 'Hire',
                    background: FColors.inkStrong,
                    color: Colors.white,
                    fontSize: 11,
                    onPressed: () => context.proposalRepo.setStatus(
                      proposal: proposal,
                      status: ProposalStatus.accepted,
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
