import 'package:cloud_firestore/cloud_firestore.dart';

import 'job.dart';

enum ProposalStatus {
  /// Written but not sent.
  draft,

  /// Sent and waiting on the client.
  submitted,

  /// Client marked it interesting.
  shortlisted,

  /// Client hired this freelancer.
  accepted,

  /// Client passed.
  declined,

  /// Caught by the on-device spam heuristic.
  flaggedSpam,

  /// Work delivered, escrow released.
  completed;

  String get label => switch (this) {
        ProposalStatus.draft => 'Draft',
        ProposalStatus.submitted => 'Submitted',
        ProposalStatus.shortlisted => 'Shortlisted',
        ProposalStatus.accepted => 'Accepted',
        ProposalStatus.declined => 'Declined',
        ProposalStatus.flaggedSpam => 'Flagged Spam',
        ProposalStatus.completed => 'Completed',
      };

  static ProposalStatus fromName(String? name) =>
      ProposalStatus.values.firstWhere(
        (ProposalStatus s) => s.name == name,
        orElse: () => ProposalStatus.submitted,
      );
}

/// The freelancer's outcome on a listing's live skill challenge, as visible
/// to the **job owner**.
///
/// This is deliberately a summary, not the work itself: [answerPreview] is a
/// short, truncated excerpt (never the full code/design), and for a quiz
/// [score] is the only thing that ever crosses to the owner's device — the
/// correct-answer key and the freelancer's full submission both live outside
/// this document. See the privacy note on [SkillChallenge].
class ChallengeResult {
  const ChallengeResult({
    this.attempted = false,
    this.completed = false,
    this.mode = ChallengeMode.writtenPrompt,
    this.answerPreview = '',
    this.hasFullSubmission = false,
    this.quizAnswers,
    this.score,
    this.elapsedSeconds = 0,
    this.interviewScheduledAt,
    this.interviewCallId,
    this.startedAt,
    this.submittedAt,
  });

  factory ChallengeResult.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ChallengeResult();
    return ChallengeResult(
      attempted: map['attempted'] as bool? ?? false,
      completed: map['completed'] as bool? ?? false,
      mode: ChallengeMode.fromName(map['mode'] as String?),
      answerPreview:
          map['answerPreview'] as String? ?? map['answer'] as String? ?? '',
      hasFullSubmission: map['hasFullSubmission'] as bool? ?? false,
      quizAnswers: (map['quizAnswers'] as List<dynamic>?)
          ?.map((dynamic e) => (e as num).toInt())
          .toList(growable: false),
      score: (map['score'] as num?)?.toInt(),
      elapsedSeconds: (map['elapsedSeconds'] as num?)?.toInt() ?? 0,
      interviewScheduledAt:
          (map['interviewScheduledAt'] as Timestamp?)?.toDate(),
      interviewCallId: map['interviewCallId'] as String?,
      startedAt: (map['startedAt'] as Timestamp?)?.toDate(),
      submittedAt: (map['submittedAt'] as Timestamp?)?.toDate(),
    );
  }

  final bool attempted;
  final bool completed;
  final ChallengeMode mode;

  /// Truncated excerpt only — see the class doc. Capped to ~160 characters by
  /// [ProposalRepository.submit].
  final String answerPreview;

  /// True when the freelancer's full answer exists in the private
  /// `proposals/{id}/submission/full` subcollection — the owner can see that
  /// it exists (and, once hired, that IP now belongs to the engagement) but
  /// cannot read it from this document.
  final bool hasFullSubmission;

  /// Selected option index per question, for [ChallengeMode.quiz] only.
  /// Multiple-choice picks are not the "code or design" the owner is walled
  /// off from — the owner needs these (together with the private answer key
  /// only they hold) to grade the quiz, since there is no server to do it.
  final List<int>? quizAnswers;

  /// 0–100 for a graded quiz; null for a written prompt or an interview,
  /// which are reviewed qualitatively rather than scored.
  final int? score;
  final int elapsedSeconds;
  final DateTime? interviewScheduledAt;
  final String? interviewCallId;
  final DateTime? startedAt;
  final DateTime? submittedAt;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'attempted': attempted,
        'completed': completed,
        'mode': mode.name,
        'answerPreview': answerPreview,
        'hasFullSubmission': hasFullSubmission,
        'quizAnswers': quizAnswers,
        'score': score,
        'elapsedSeconds': elapsedSeconds,
        if (interviewScheduledAt != null)
          'interviewScheduledAt': Timestamp.fromDate(interviewScheduledAt!),
        'interviewCallId': interviewCallId,
        if (startedAt != null) 'startedAt': Timestamp.fromDate(startedAt!),
        if (submittedAt != null)
          'submittedAt': Timestamp.fromDate(submittedAt!),
      };
}

/// A bid on a listing. Stored at `proposals/{proposalId}`.
class Proposal {
  const Proposal({
    required this.id,
    required this.jobId,
    required this.jobTitle,
    required this.jobOwnerId,
    required this.freelancerId,
    required this.freelancerName,
    this.freelancerTrustScore = 60,
    this.bidAmountCents = 0,
    this.bidLabel = '',
    this.coverNote = '',
    this.challenge = const ChallengeResult(),
    this.status = ProposalStatus.submitted,
    this.spamScore = 0,
    this.reviewNote,
    this.chatId,
    this.createdAt,
    this.updatedAt,
  });

  factory Proposal.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return Proposal(
      id: doc.id,
      jobId: d['jobId'] as String? ?? '',
      jobTitle: d['jobTitle'] as String? ?? '',
      jobOwnerId: d['jobOwnerId'] as String? ?? '',
      freelancerId: d['freelancerId'] as String? ?? '',
      freelancerName: d['freelancerName'] as String? ?? '',
      freelancerTrustScore: (d['freelancerTrustScore'] as num?)?.toInt() ?? 60,
      bidAmountCents: (d['bidAmountCents'] as num?)?.toInt() ?? 0,
      bidLabel: d['bidLabel'] as String? ?? '',
      coverNote: d['coverNote'] as String? ?? '',
      challenge:
          ChallengeResult.fromMap(d['challenge'] as Map<String, dynamic>?),
      status: ProposalStatus.fromName(d['status'] as String?),
      spamScore: (d['spamScore'] as num?)?.toInt() ?? 0,
      reviewNote: d['reviewNote'] as String?,
      chatId: d['chatId'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String jobId;
  final String jobTitle;
  final String jobOwnerId;
  final String freelancerId;
  final String freelancerName;
  final int freelancerTrustScore;
  final int bidAmountCents;
  final String bidLabel;
  final String coverNote;
  final ChallengeResult challenge;
  final ProposalStatus status;

  /// 0–100 from the on-device heuristic; ≥60 flags the proposal.
  final int spamScore;
  final String? reviewNote;

  /// Set once the client opens a conversation about this proposal.
  final String? chatId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get bidAmount => bidAmountCents / 100;
  bool get passedFilter => status != ProposalStatus.flaggedSpam;
  bool get canMessage =>
      challenge.completed ||
      reviewNote != null ||
      status == ProposalStatus.shortlisted;

  String get challengeLabel {
    if (challenge.completed) return 'Challenge Passed';
    if (reviewNote != null) return 'Portfolio Review';
    return 'Challenge Not Taken';
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'jobId': jobId,
        'jobTitle': jobTitle,
        'jobOwnerId': jobOwnerId,
        'freelancerId': freelancerId,
        'freelancerName': freelancerName,
        'freelancerTrustScore': freelancerTrustScore,
        'bidAmountCents': bidAmountCents,
        'bidLabel': bidLabel,
        'coverNote': coverNote,
        'challenge': challenge.toMap(),
        'status': status.name,
        'spamScore': spamScore,
        'reviewNote': reviewNote,
        'chatId': chatId,
      };

  Proposal copyWith({
    ProposalStatus? status,
    String? chatId,
    ChallengeResult? challenge,
  }) =>
      Proposal(
        id: id,
        jobId: jobId,
        jobTitle: jobTitle,
        jobOwnerId: jobOwnerId,
        freelancerId: freelancerId,
        freelancerName: freelancerName,
        freelancerTrustScore: freelancerTrustScore,
        bidAmountCents: bidAmountCents,
        bidLabel: bidLabel,
        coverNote: coverNote,
        challenge: challenge ?? this.challenge,
        status: status ?? this.status,
        spamScore: spamScore,
        reviewNote: reviewNote,
        chatId: chatId ?? this.chatId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
