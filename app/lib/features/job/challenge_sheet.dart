import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/f_button.dart';
import '../../core/widgets/f_field.dart';
import '../../data/models/job.dart';

/// The timed challenge-taking flow, opened from the job detail screen.
///
/// Only ever writes through `ProposalRepository.submitWrittenAnswer` /
/// `submitQuizAnswers` — see those methods for exactly what the job owner
/// can and cannot see afterward.
class ChallengeSheet extends StatefulWidget {
  const ChallengeSheet({super.key, required this.challenge});

  final SkillChallenge challenge;

  /// Returns the written answer text, or null if cancelled.
  static Future<String?> showWritten(
      BuildContext context, SkillChallenge challenge) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => ChallengeSheet(challenge: challenge),
    );
  }

  /// Returns the selected option index per question, or null if cancelled.
  static Future<List<int>?> showQuiz(
      BuildContext context, SkillChallenge challenge) {
    return showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => ChallengeSheet(challenge: challenge),
    );
  }

  @override
  State<ChallengeSheet> createState() => _ChallengeSheetState();
}

class _ChallengeSheetState extends State<ChallengeSheet> {
  late int _remaining = widget.challenge.durationSeconds;
  Timer? _timer;
  final TextEditingController _answer = TextEditingController();
  late final List<int?> _picks =
      List<int?>.filled(widget.challenge.questions.length, null);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        _timer?.cancel();
        setState(() => _remaining = 0);
        _submit(timedOut: true);
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _answer.dispose();
    super.dispose();
  }

  void _submit({bool timedOut = false}) {
    if (!mounted) return;
    if (widget.challenge.mode == ChallengeMode.quiz) {
      if (!timedOut && _picks.any((int? p) => p == null)) {
        AppFeedback.error(context, 'Answer every question first.');
        return;
      }
      Navigator.of(context).pop(_picks.map((int? p) => p ?? 0).toList());
    } else {
      if (!timedOut && _answer.text.trim().isEmpty) {
        AppFeedback.error(context, 'Write an answer first.');
        return;
      }
      Navigator.of(context).pop(_answer.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isQuiz = widget.challenge.mode == ChallengeMode.quiz;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scroll) => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(widget.challenge.modeLabel, style: FType.titleMd),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _remaining < 30
                        ? FColors.dangerTint
                        : FColors.violetTint,
                    borderRadius: FRadius.chipR,
                  ),
                  child: Text(
                    Fmt.countdown(_remaining),
                    style: FType.pill.copyWith(
                      fontSize: 12,
                      color: _remaining < 30 ? FColors.danger : FColors.violet,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              children: isQuiz
                  ? <Widget>[
                      for (int qi = 0;
                          qi < widget.challenge.questions.length;
                          qi++)
                        _QuestionBlock(
                          index: qi,
                          question: widget.challenge.questions[qi],
                          selected: _picks[qi],
                          onSelect: (int oi) => setState(() => _picks[qi] = oi),
                        ),
                    ]
                  : <Widget>[
                      Text(widget.challenge.prompt, style: FType.body),
                      const SizedBox(height: FSpace.x3),
                      FField(
                        controller: _answer,
                        label: 'Your answer',
                        hint: 'Type your solution or explanation here',
                        multiline: true,
                        height: 220,
                        autofocus: true,
                      ),
                    ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
              child: FButton(
                label: 'Submit Challenge',
                variant: FButtonVariant.violet,
                onPressed: () => _submit(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionBlock extends StatelessWidget {
  const _QuestionBlock({
    required this.index,
    required this.question,
    required this.selected,
    required this.onSelect,
  });

  final int index;
  final QuizQuestion question;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('${index + 1}. ${question.prompt}', style: FType.titleXs),
          const SizedBox(height: FSpace.lg),
          for (int oi = 0; oi < question.options.length; oi++)
            _OptionTile(
              label: question.options[oi],
              selected: selected == oi,
              onTap: () => onSelect(oi),
            ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FSpace.sm),
      child: Material(
        color: selected ? FColors.violetTint : FColors.surface,
        borderRadius: FRadius.fieldR,
        child: InkWell(
          onTap: onTap,
          borderRadius: FRadius.fieldR,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: FRadius.fieldR,
              border: Border.all(
                color: selected
                    ? FColors.violet.withValues(alpha: 0.4)
                    : FColors.border,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 17,
                  color: selected ? FColors.violet : FColors.inkFaint,
                ),
                const SizedBox(width: FSpace.xl),
                Expanded(child: Text(label, style: FType.bodyXs)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
