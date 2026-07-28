import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/feedback.dart';
import '../../core/widgets/f_button.dart';
import '../../core/widgets/f_field.dart';
import '../../data/models/job.dart';
import '../../data/models/proposal.dart';
import '../../data/models/review.dart';

/// Leaving a review once an engagement is complete.
///
/// Both directions use this: the client rates the freelancer, and the
/// freelancer rates the client. The review id is `${jobId}__${authorId}`, so
/// re-opening this edits your existing review instead of stacking a second
/// one.
class ReviewSheet extends StatefulWidget {
  const ReviewSheet({
    super.key,
    required this.job,
    required this.proposal,
    required this.subjectId,
    required this.subjectName,
    this.existing,
  });

  final Job job;
  final Proposal proposal;
  final String subjectId;
  final String subjectName;
  final Review? existing;

  static Future<bool> show(
    BuildContext context, {
    required Job job,
    required Proposal proposal,
    required String subjectId,
    required String subjectName,
  }) async {
    final String? uid = context.read<SessionController>().uid;
    if (uid == null) return false;
    // A failed lookup previously meant the sheet never opened at all, with
    // no explanation. Treat it as "no existing review" so the person can
    // still leave one — the write itself is guarded below.
    Review? existing;
    try {
      existing = await context.engagementRepo.myReviewFor(
        jobId: job.id,
        authorId: uid,
      );
    } on Object {
      existing = null;
    }
    if (!context.mounted) return false;

    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ReviewSheet(
          job: job,
          proposal: proposal,
          subjectId: subjectId,
          subjectName: subjectName,
          existing: existing,
        ),
      ),
    );
    return saved ?? false;
  }

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  late int _rating = widget.existing?.rating ?? 5;
  late final TextEditingController _comment =
      TextEditingController(text: widget.existing?.comment ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final SessionController session = context.read<SessionController>();
    final String? uid = session.uid;
    if (uid == null) return;

    setState(() => _busy = true);
    try {
      await context.engagementRepo.leaveReview(
        Review(
          id: Review.idFor(jobId: widget.job.id, authorId: uid),
          jobId: widget.job.id,
          jobTitle: widget.job.title,
          authorId: uid,
          authorName: session.user?.displayName ?? 'Felicek user',
          subjectId: widget.subjectId,
          rating: _rating,
          comment: _comment.text,
          amountCents: widget.proposal.bidAmountCents,
        ),
      );
      if (mounted) {
        AppFeedback.success(context, 'Review posted.');
        Navigator.of(context).pop(true);
      }
    } on Object {
      if (mounted) {
        AppFeedback.error(context, 'Could not post that review. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.existing == null
                  ? 'Rate ${widget.subjectName}'
                  : 'Edit your review',
              style: FType.displaySm,
            ),
            const SizedBox(height: FSpace.sm),
            Text(widget.job.title, style: FType.caption),
            const SizedBox(height: FSpace.x3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: () => setState(() => _rating = i),
                    iconSize: 30,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      i <= _rating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: i <= _rating ? FColors.amber : FColors.inkDisabled,
                    ),
                    tooltip: '$i star${i == 1 ? '' : 's'}',
                  ),
              ],
            ),
            const SizedBox(height: FSpace.lg),
            FField(
              controller: _comment,
              label: 'Comment (optional)',
              hint: 'What was it like working together?',
              multiline: true,
              height: 100,
            ),
            const SizedBox(height: FSpace.x3),
            FButton(
              label: widget.existing == null ? 'Post Review' : 'Save Changes',
              busy: _busy,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
