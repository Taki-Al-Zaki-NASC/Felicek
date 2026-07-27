import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import '../models/job.dart';
import '../models/proposal.dart';
import '../models/public_profile.dart';
import '../services/firestore_refs.dart';
import '../services/spam_filter.dart';

/// Bids: submit, list, triage, accept.
class ProposalRepository {
  ProposalRepository(this._db);

  final Db _db;

  /// Everything I have bid on ("My Proposals").
  Stream<List<Proposal>> watchMine(String freelancerId, {int limit = 50}) =>
      _db.proposals
          .where('freelancerId', isEqualTo: freelancerId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((JsonQuerySnap s) =>
              s.docs.map(Proposal.fromDoc).toList(growable: false));

  /// Everything sent to my listings ("Proposal Queue").
  Stream<List<Proposal>> watchIncoming(String ownerId, {int limit = 80}) =>
      _db.proposals
          .where('jobOwnerId', isEqualTo: ownerId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((JsonQuerySnap s) =>
              s.docs.map(Proposal.fromDoc).toList(growable: false));

  /// Applicants on one listing, for the owner's job-detail view.
  Stream<List<Proposal>> watchForJob(String jobId) => _db.proposals
      .where('jobId', isEqualTo: jobId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((JsonQuerySnap s) =>
          s.docs.map(Proposal.fromDoc).toList(growable: false));

  /// My existing bid on a listing, if any — used to switch the CTA to
  /// "Proposal Submitted ✓".
  Stream<Proposal?> watchMineForJob({
    required String jobId,
    required String freelancerId,
  }) =>
      _db.proposals
          .where('jobId', isEqualTo: jobId)
          .where('freelancerId', isEqualTo: freelancerId)
          .limit(1)
          .snapshots()
          .map(
            (JsonQuerySnap s) =>
                s.docs.isEmpty ? null : Proposal.fromDoc(s.docs.first),
          );

  /// Submits a bid. The id is derived from the job and the bidder so a
  /// double-tap updates the same document instead of creating a second bid.
  Future<Proposal> submit({
    required Job job,
    required PublicProfile freelancer,
    required int bidAmountCents,
    required String bidLabel,
    required String coverNote,
    required ChallengeResult challenge,
  }) async {
    final String id = '${job.id}__${freelancer.uid}';
    final int spam = SpamFilter.score(
      coverNote: coverNote,
      job: job,
      bidAmount: bidAmountCents / 100,
      challengeCompleted: challenge.completed,
      trustScore: freelancer.trustScore,
    );

    final Proposal proposal = Proposal(
      id: id,
      jobId: job.id,
      jobTitle: job.title,
      jobOwnerId: job.ownerId,
      freelancerId: freelancer.uid,
      freelancerName: freelancer.displayName,
      freelancerTrustScore: freelancer.trustScore,
      bidAmountCents: bidAmountCents,
      bidLabel: bidLabel,
      coverNote: coverNote.trim(),
      challenge: challenge,
      status: spam >= SpamFilter.flagThreshold
          ? ProposalStatus.flaggedSpam
          : ProposalStatus.submitted,
      spamScore: spam,
      reviewNote:
          job.hasChallenge ? null : 'Portfolio & escrow history reviewed.',
    );

    final DocumentSnapshot<Json> existing = await _db.proposal(id).get();
    final WriteBatch batch = _db.firestore.batch();
    batch.set(
      _db.proposal(id),
      <String, dynamic>{
        ...proposal.toMap(),
        if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    if (!existing.exists) {
      batch.set(
        _db.job(job.id),
        <String, dynamic>{'proposalsCount': FieldValue.increment(1)},
        SetOptions(merge: true),
      );
    }
    await batch.commit();

    if (proposal.passedFilter) {
      await _notify(
        recipientId: job.ownerId,
        kind: NotificationKind.proposal,
        title: 'New proposal · ${job.title}',
        body: '${freelancer.displayName} bid $bidLabel',
        jobId: job.id,
        proposalId: id,
        actorId: freelancer.uid,
        actorName: freelancer.displayName,
      );
    }
    return proposal;
  }

  Future<void> setStatus({
    required Proposal proposal,
    required ProposalStatus status,
  }) async {
    await _db.proposal(proposal.id).set(
      <String, dynamic>{
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    final ({NotificationKind kind, String title, String body})? note =
        switch (status) {
      ProposalStatus.accepted => (
          kind: NotificationKind.proposalAccepted,
          title: 'You were hired',
          body: '${proposal.jobTitle} — the client accepted your proposal.',
        ),
      ProposalStatus.declined => (
          kind: NotificationKind.proposalDeclined,
          title: 'Proposal declined',
          body: 'The client passed on ${proposal.jobTitle}.',
        ),
      ProposalStatus.shortlisted => (
          kind: NotificationKind.proposal,
          title: 'You were shortlisted',
          body: '${proposal.jobTitle} — the client shortlisted your proposal.',
        ),
      _ => null,
    };

    if (note != null) {
      await _notify(
        recipientId: proposal.freelancerId,
        kind: note.kind,
        title: note.title,
        body: note.body,
        jobId: proposal.jobId,
        proposalId: proposal.id,
        actorId: proposal.jobOwnerId,
        actorName: null,
      );
    }
  }

  Future<void> attachChat(
          {required String proposalId, required String chatId}) =>
      _db.proposal(proposalId).set(
        <String, dynamic>{
          'chatId': chatId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  // ── Challenge submission (owner-blind for written/code answers) ─────────

  /// Records a free-text / code answer for [ChallengeMode.writtenPrompt].
  ///
  /// The full text goes to `proposals/{id}/submission/full`, readable only by
  /// the freelancer who wrote it. The proposal document — which the job
  /// owner can read — only ever gets a short, truncated [answerPreview]. This
  /// is what keeps a client from harvesting an applicant's full solution
  /// without hiring them.
  Future<void> submitWrittenAnswer({
    required String proposalId,
    required String fullAnswer,
    required int elapsedSeconds,
  }) async {
    final String trimmed = fullAnswer.trim();
    final String preview =
        trimmed.length <= 160 ? trimmed : '${trimmed.substring(0, 159)}…';

    await _db.proposalSubmission(proposalId).set(
      <String, dynamic>{
        'fullAnswer': trimmed,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await _db.proposal(proposalId).set(
      <String, dynamic>{
        'challenge': <String, dynamic>{
          'attempted': true,
          'completed': trimmed.isNotEmpty,
          'mode': ChallengeMode.writtenPrompt.name,
          'answerPreview': preview,
          'hasFullSubmission': trimmed.isNotEmpty,
          'elapsedSeconds': elapsedSeconds,
          'submittedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Records quiz picks. Multiple-choice selections are not the "code or
  /// design" the owner is walled off from — they're needed, together with
  /// the private key only the owner holds, to grade the quiz at all, since
  /// there is no server to do it.
  Future<void> submitQuizAnswers({
    required String proposalId,
    required List<int> answers,
    required int elapsedSeconds,
  }) =>
      _db.proposal(proposalId).set(
        <String, dynamic>{
          'challenge': <String, dynamic>{
            'attempted': true,
            'completed': true,
            'mode': ChallengeMode.quiz.name,
            'quizAnswers': answers,
            'elapsedSeconds': elapsedSeconds,
            'submittedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  /// Grades a quiz proposal. Only callable meaningfully by the job owner —
  /// they are the only account Firestore rules let read `challengeKey`, so a
  /// freelancer's client would fail the key read and simply cannot compute a
  /// score for itself.
  Future<int?> gradeQuiz({
    required String jobId,
    required Proposal proposal,
  }) async {
    if (proposal.challenge.quizAnswers == null) return null;
    final DocumentSnapshot<Json> keyDoc = await _db.challengeKey(jobId).get();
    if (!keyDoc.exists) return null;
    final List<dynamic> correct =
        (keyDoc.data()?['correctIndexes'] as List<dynamic>?) ?? <dynamic>[];
    final List<int> given = proposal.challenge.quizAnswers!;
    if (correct.isEmpty) return null;

    int right = 0;
    for (int i = 0; i < correct.length; i++) {
      if (i < given.length && given[i] == correct[i]) right++;
    }
    final int score = ((right / correct.length) * 100).round();

    await _db.proposal(proposal.id).set(
      <String, dynamic>{
        'challenge': <String, dynamic>{'score': score},
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return score;
  }

  /// Schedules a live call-session interview in place of a written answer.
  Future<void> scheduleInterview({
    required String proposalId,
    required DateTime scheduledAt,
  }) =>
      _db.proposal(proposalId).set(
        <String, dynamic>{
          'challenge': <String, dynamic>{
            'attempted': true,
            'mode': ChallengeMode.liveInterview.name,
            'interviewScheduledAt': Timestamp.fromDate(scheduledAt),
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  /// Links the call actually held for the interview and marks it complete.
  Future<void> recordInterviewCall({
    required String proposalId,
    required String callId,
  }) =>
      _db.proposal(proposalId).set(
        <String, dynamic>{
          'challenge': <String, dynamic>{
            'completed': true,
            'interviewCallId': callId,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  /// The freelancer's own full answer — only ever called from that
  /// freelancer's device (rules block anyone else's read).
  Future<String?> fetchMyFullAnswer(String proposalId) async {
    final DocumentSnapshot<Json> doc =
        await _db.proposalSubmission(proposalId).get();
    return doc.data()?['fullAnswer'] as String?;
  }

  /// Count of proposals this week that the filter caught — the banner on the
  /// proposal queue.
  Future<int> spamBlockedThisWeek(String ownerId) async {
    final DateTime weekAgo = DateTime.now().subtract(const Duration(days: 7));
    try {
      // An aggregation query bills as a single read regardless of the count.
      final AggregateQuerySnapshot snap = await _db.proposals
          .where('jobOwnerId', isEqualTo: ownerId)
          .where('status', isEqualTo: ProposalStatus.flaggedSpam.name)
          .where('createdAt', isGreaterThan: Timestamp.fromDate(weekAgo))
          .count()
          .get();
      return snap.count ?? 0;
    } on FirebaseException {
      return 0;
    }
  }

  Future<void> _notify({
    required String recipientId,
    required NotificationKind kind,
    required String title,
    required String body,
    String? jobId,
    String? proposalId,
    String? actorId,
    String? actorName,
  }) async {
    try {
      await _db.notifications(recipientId).add(<String, dynamic>{
        ...AppNotification(
          id: '',
          kind: kind,
          title: title,
          body: body,
          jobId: jobId,
          proposalId: proposalId,
          actorId: actorId,
          actorName: actorName,
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      // Notifications are additive — never fail the action they describe.
    }
  }
}
