import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/f_button.dart';
import '../../core/widgets/f_field.dart';
import '../../core/widgets/f_pill.dart';
import '../../core/widgets/f_surface.dart';
import '../../data/models/job.dart';
import '../../data/models/user_role.dart';

/// "Post a New Job" — title, budget, scope, and the optional live skill
/// challenge, with a mode picker (written prompt / quiz / live interview) on
/// top of the design's single free-text challenge field.
///
/// Pass [existing] to reuse the same form as "Edit Listing": the fields are
/// pre-filled and Publish becomes Save. The quiz answer key is deliberately
/// *not* pre-filled — it lives in an owner-only subcollection and re-entering
/// it is the honest behaviour, rather than silently keeping a key the form
/// can no longer show.
class PostJobScreen extends StatefulWidget {
  const PostJobScreen({super.key, this.existing});

  final Job? existing;

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _QuizDraft {
  _QuizDraft() : promptCtrl = TextEditingController();
  final TextEditingController promptCtrl;
  final List<TextEditingController> optionCtrls =
      List<TextEditingController>.generate(4, (_) => TextEditingController());
  int correctIndex = 0;

  void dispose() {
    promptCtrl.dispose();
    for (final TextEditingController c in optionCtrls) {
      c.dispose();
    }
  }
}

class _PostJobScreenState extends State<PostJobScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _budget = TextEditingController();
  final TextEditingController _scope = TextEditingController();
  final TextEditingController _skills = TextEditingController();
  final TextEditingController _prompt = TextEditingController();
  final TextEditingController _equity = TextEditingController();

  bool _challengeEnabled = false;
  ChallengeMode _mode = ChallengeMode.writtenPrompt;
  final List<_QuizDraft> _quiz = <_QuizDraft>[_QuizDraft()];
  bool _busy = false;
  String? _titleError, _budgetError, _scopeError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Job? job = widget.existing;
    if (job == null) return;
    _title.text = job.title;
    _budget.text = job.budget;
    _scope.text = job.scope;
    _skills.text = job.skills.join(', ');
    _equity.text = job.equity ?? '';
    _challengeEnabled = job.challenge.enabled;
    _mode = job.challenge.mode;
    _prompt.text = job.challenge.prompt;
    if (job.challenge.questions.isNotEmpty) {
      for (final _QuizDraft q in _quiz) {
        q.dispose();
      }
      _quiz
        ..clear()
        ..addAll(job.challenge.questions.map((QuizQuestion q) {
          final _QuizDraft draft = _QuizDraft();
          draft.promptCtrl.text = q.prompt;
          for (int i = 0;
              i < draft.optionCtrls.length && i < q.options.length;
              i++) {
            draft.optionCtrls[i].text = q.options[i];
          }
          return draft;
        }));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _budget.dispose();
    _scope.dispose();
    _skills.dispose();
    _prompt.dispose();
    _equity.dispose();
    for (final _QuizDraft q in _quiz) {
      q.dispose();
    }
    super.dispose();
  }

  bool _validate() {
    setState(() {
      _titleError = Validate.jobTitle(_title.text);
      _budgetError = Validate.budget(_budget.text);
      _scopeError = Validate.jobScope(_scope.text);
    });
    return _titleError == null && _budgetError == null && _scopeError == null;
  }

  Future<void> _submit() async {
    if (_busy || !_validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    final SessionController session = context.read<SessionController>();
    final profile = session.publicProfile;
    if (profile == null) {
      setState(() => _busy = false);
      return;
    }

    final List<String> skills = _skills.text
        .split(',')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .take(8)
        .toList(growable: false);

    final SkillChallenge challenge = SkillChallenge(
      enabled: _challengeEnabled,
      mode: _mode,
      prompt: _mode == ChallengeMode.writtenPrompt ? _prompt.text.trim() : '',
      questions: _mode == ChallengeMode.quiz
          ? _quiz
              .where((_QuizDraft q) => q.promptCtrl.text.trim().isNotEmpty)
              .map(
                (_QuizDraft q) => QuizQuestion(
                  prompt: q.promptCtrl.text.trim(),
                  options: q.optionCtrls
                      .map((TextEditingController c) => c.text.trim())
                      .toList(),
                ),
              )
              .toList()
          : const <QuizQuestion>[],
    );
    final List<int>? key = _mode == ChallengeMode.quiz
        ? _quiz
            .where((_QuizDraft q) => q.promptCtrl.text.trim().isNotEmpty)
            .map((_QuizDraft q) => q.correctIndex)
            .toList()
        : null;

    try {
      final Job? existing = widget.existing;
      if (existing != null) {
        await context.jobRepo.update(
          jobId: existing.id,
          title: _title.text,
          summary: _scope.text.length > 130
              ? '${_scope.text.substring(0, 129)}…'
              : _scope.text,
          scope: _scope.text,
          budget: _budget.text,
          skills: skills,
          milestones: existing.milestones,
          challenge: _challengeEnabled ? challenge : const SkillChallenge(),
          equity:
              session.role == UserRole.startup && _equity.text.trim().isNotEmpty
                  ? _equity.text.trim()
                  : null,
          quizAnswerKey: key,
        );
        if (mounted) {
          AppFeedback.success(context, 'Listing updated.');
          Navigator.of(context).maybePop();
        }
        return;
      }

      await context.jobRepo.publish(
        owner: profile,
        title: _title.text,
        summary: _scope.text.length > 130
            ? '${_scope.text.substring(0, 129)}…'
            : _scope.text,
        scope: _scope.text,
        budget: _budget.text,
        skills: skills,
        milestones: const <Milestone>[
          Milestone(label: 'Milestone 1', amount: 'TBD')
        ],
        challenge: _challengeEnabled ? challenge : const SkillChallenge(),
        equity:
            session.role == UserRole.startup && _equity.text.trim().isNotEmpty
                ? _equity.text.trim()
                : null,
        quizAnswerKey: key,
      );
      if (mounted) {
        AppFeedback.success(context, 'Job published.');
        Navigator.of(context).maybePop();
      }
    } on Object {
      if (mounted) {
        AppFeedback.error(context, 'Could not publish that job. Try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final UserRole role =
        context.select<SessionController, UserRole>((s) => s.role);

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: Column(
        children: <Widget>[
          const FTopBar(title: 'Post a New Job'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              children: <Widget>[
                FField(
                  controller: _title,
                  label: 'Job title',
                  hint: 'e.g. Redesign onboarding flow',
                  errorText: _titleError,
                ),
                const SizedBox(height: FSpace.x2),
                FField(
                  controller: _budget,
                  label: 'Budget',
                  hint: 'e.g. \$500 or 0.5% Equity + \$1,000',
                  errorText: _budgetError,
                ),
                const SizedBox(height: FSpace.x2),
                FField(
                  controller: _scope,
                  label: 'Scope',
                  hint: 'Describe the work in detail',
                  multiline: true,
                  height: 100,
                  errorText: _scopeError,
                ),
                const SizedBox(height: FSpace.x2),
                FField(
                  controller: _skills,
                  label: 'Skills (comma separated)',
                  hint: 'e.g. Flutter, Firebase, UI/UX',
                ),
                if (role == UserRole.startup) ...<Widget>[
                  const SizedBox(height: FSpace.x2),
                  FField(
                    controller: _equity,
                    label: 'Equity offered (optional)',
                    hint: 'e.g. 0.5%',
                  ),
                ],
                const SizedBox(height: FSpace.x2),
                _ChallengeCard(
                  enabled: _challengeEnabled,
                  mode: _mode,
                  promptCtrl: _prompt,
                  quiz: _quiz,
                  onToggle: () =>
                      setState(() => _challengeEnabled = !_challengeEnabled),
                  onMode: (ChallengeMode m) => setState(() => _mode = m),
                  onAddQuestion: () => setState(() => _quiz.add(_QuizDraft())),
                  onRemoveQuestion: (int i) => setState(() {
                    _quiz[i].dispose();
                    _quiz.removeAt(i);
                  }),
                  onCorrectChanged: (int qi, int oi) =>
                      setState(() => _quiz[qi].correctIndex = oi),
                ),
                const SizedBox(height: FSpace.x2),
                FButton(
                  label: _isEditing ? 'Save Changes' : 'Publish Job',
                  busy: _busy,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.enabled,
    required this.mode,
    required this.promptCtrl,
    required this.quiz,
    required this.onToggle,
    required this.onMode,
    required this.onAddQuestion,
    required this.onRemoveQuestion,
    required this.onCorrectChanged,
  });

  final bool enabled;
  final ChallengeMode mode;
  final TextEditingController promptCtrl;
  final List<_QuizDraft> quiz;
  final VoidCallback onToggle;
  final ValueChanged<ChallengeMode> onMode;
  final VoidCallback onAddQuestion;
  final ValueChanged<int> onRemoveQuestion;
  final void Function(int questionIndex, int optionIndex) onCorrectChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: FColors.violetTint,
        borderRadius: FRadius.cardR,
        border: Border.all(color: FColors.violet.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                'LIVE SKILL CHALLENGE',
                style: FType.sectionLabel.copyWith(
                  color: FColors.violet,
                  fontWeight: FontWeight.w600,
                ),
              ),
              InkWell(
                onTap: onToggle,
                borderRadius: FRadius.chipR,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: enabled ? FColors.violet : FColors.surface,
                    borderRadius: FRadius.chipR,
                    border: enabled ? null : Border.all(color: FColors.border),
                  ),
                  child: Text(
                    enabled ? 'Enabled' : 'Add Challenge',
                    style: FType.pill.copyWith(
                      fontSize: 12.5,
                      color: enabled ? Colors.white : FColors.inkMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (enabled) ...<Widget>[
            const SizedBox(height: FSpace.xl),
            Text(
              'Applicants only ever see the score/pass-fail we compute — never '
              "each other's submissions, and neither do you until you open an "
              'applicant.',
              style: FType.captionSm.copyWith(fontSize: 10.5),
            ),
            const SizedBox(height: FSpace.lg),
            Row(
              children: <Widget>[
                for (final ChallengeMode m in ChallengeMode.values) ...<Widget>[
                  Expanded(
                    child: FChoiceChip(
                      label: switch (m) {
                        ChallengeMode.writtenPrompt => 'Written',
                        ChallengeMode.quiz => 'Quiz',
                        ChallengeMode.liveInterview => 'Live Call',
                      },
                      selected: mode == m,
                      expand: true,
                      selectedColor: FColors.violet,
                      onTap: () => onMode(m),
                    ),
                  ),
                  if (m != ChallengeMode.values.last)
                    const SizedBox(width: FSpace.md),
                ],
              ],
            ),
            const SizedBox(height: FSpace.lg),
            if (mode == ChallengeMode.writtenPrompt)
              FField(
                controller: promptCtrl,
                hint:
                    'e.g. Build a working counter widget with persisted state in 4 minutes',
                multiline: true,
                height: 70,
              )
            else if (mode == ChallengeMode.quiz)
              Column(
                children: <Widget>[
                  for (int qi = 0; qi < quiz.length; qi++)
                    _QuizEditor(
                      index: qi,
                      draft: quiz[qi],
                      onRemove:
                          quiz.length > 1 ? () => onRemoveQuestion(qi) : null,
                      onCorrectChanged: (int oi) => onCorrectChanged(qi, oi),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onAddQuestion,
                      icon: const Icon(Icons.add_rounded,
                          size: 16, color: FColors.violet),
                      label: Text(
                        'Add question',
                        style: FType.pill
                            .copyWith(fontSize: 12, color: FColors.violet),
                      ),
                    ),
                  ),
                ],
              )
            else
              const Text(
                'Applicants will be asked to book a short live call with you from '
                'the job detail screen instead of writing an answer.',
                style: FType.supportSm,
              ),
          ],
        ],
      ),
    );
  }
}

class _QuizEditor extends StatelessWidget {
  const _QuizEditor({
    required this.index,
    required this.draft,
    required this.onRemove,
    required this.onCorrectChanged,
  });

  final int index;
  final _QuizDraft draft;
  final VoidCallback? onRemove;
  final ValueChanged<int> onCorrectChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: FSpace.lg),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FColors.surface,
        borderRadius: FRadius.fieldR,
        border: Border.all(color: FColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('Question ${index + 1}', style: FType.fieldLabel),
              ),
              if (onRemove != null)
                InkWell(
                  onTap: onRemove,
                  child: const Icon(Icons.close_rounded,
                      size: 15, color: FColors.inkFaint),
                ),
            ],
          ),
          const SizedBox(height: FSpace.sm),
          FField(controller: draft.promptCtrl, hint: 'Question text'),
          const SizedBox(height: FSpace.lg),
          // The selected radio marks the correct option. It is stored in the
          // owner-only `challengeKey` subcollection, never on the listing —
          // an applicant reading the public job document cannot see it.
          RadioGroup<int>(
            groupValue: draft.correctIndex,
            onChanged: (int? v) => onCorrectChanged(v ?? 0),
            child: Column(
              children: <Widget>[
                for (int oi = 0; oi < draft.optionCtrls.length; oi++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FSpace.sm),
                    child: Row(
                      children: <Widget>[
                        Radio<int>(
                          value: oi,
                          activeColor: FColors.violet,
                          visualDensity: VisualDensity.compact,
                        ),
                        Expanded(
                          child: FField(
                            controller: draft.optionCtrls[oi],
                            hint:
                                'Option ${oi + 1}${oi == draft.correctIndex ? ' (correct)' : ''}',
                          ),
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
