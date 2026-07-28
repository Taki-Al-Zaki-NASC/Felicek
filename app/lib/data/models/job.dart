import 'package:cloud_firestore/cloud_firestore.dart';

/// A payment stage on a listing.
class Milestone {
  const Milestone(
      {required this.label, required this.amount, this.released = false});

  factory Milestone.fromMap(Map<String, dynamic> map) => Milestone(
        label: map['label'] as String? ?? '',
        amount: map['amount'] as String? ?? 'TBD',
        released: map['released'] as bool? ?? false,
      );

  final String label;
  final String amount;
  final bool released;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'label': label,
        'amount': amount,
        'released': released,
      };
}

/// How a listing's live skill challenge is administered.
enum ChallengeMode {
  /// A free-text prompt ("build this component", "write this paragraph") —
  /// the original design behaviour.
  writtenPrompt,

  /// Multiple-choice questions, auto-graded.
  quiz,

  /// A scheduled live call session (see `CallService`) instead of a written
  /// answer — the "call session exam" case.
  liveInterview;

  static ChallengeMode fromName(String? name) =>
      ChallengeMode.values.firstWhere(
        (ChallengeMode m) => m.name == name,
        orElse: () => ChallengeMode.writtenPrompt,
      );
}

/// One multiple-choice question. The *question and options* are public (any
/// applicant needs to see them to answer) — only the correct-answer index is
/// private, stored separately in `jobs/{id}/challengeKey`, never on this
/// object as it appears to a freelancer.
class QuizQuestion {
  const QuizQuestion({required this.prompt, required this.options});

  factory QuizQuestion.fromMap(Map<String, dynamic> map) => QuizQuestion(
        prompt: map['prompt'] as String? ?? '',
        options: (map['options'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => e.toString())
            .toList(growable: false),
      );

  final String prompt;
  final List<String> options;

  Map<String, dynamic> toMap() =>
      <String, dynamic>{'prompt': prompt, 'options': options};
}

/// The optional live skill challenge attached to a listing.
///
/// **Privacy design, per product requirement:** the job owner (client,
/// agency or startup) must never see an applicant's full solution — their
/// code, design, or the quiz answer key. What the owner can see is exactly
/// what [Proposal.challenge] carries: a score and a short, truncated
/// summary. The full text lives at `proposals/{id}/submission/full`, a
/// subcollection Firestore rules restrict to the freelancer who wrote it —
/// see `firestore.rules`. For a [ChallengeMode.quiz], the correct answers
/// live at `jobs/{id}/challengeKey`, restricted to the job's owner, so an
/// applicant can never read the key either; grading a quiz therefore happens
/// on the *owner's* device when they open the applicant list (they already
/// hold both the key and the submitted answers), not on the freelancer's.
class SkillChallenge {
  const SkillChallenge({
    this.enabled = false,
    this.mode = ChallengeMode.writtenPrompt,
    this.prompt = '',
    this.durationSeconds = 240,
    this.questions = const <QuizQuestion>[],
  });

  factory SkillChallenge.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const SkillChallenge();
    return SkillChallenge(
      enabled: map['enabled'] as bool? ?? false,
      mode: ChallengeMode.fromName(map['mode'] as String?),
      prompt: map['prompt'] as String? ?? '',
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 240,
      questions: (map['questions'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) =>
              QuizQuestion.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
    );
  }

  final bool enabled;
  final ChallengeMode mode;
  final String prompt;
  final int durationSeconds;

  /// Public for [ChallengeMode.quiz] — prompts and options only, no answers.
  final List<QuizQuestion> questions;

  /// "4 min preview" in the design.
  String get durationLabel => '${(durationSeconds / 60).round()} min';

  String get modeLabel => switch (mode) {
        ChallengeMode.writtenPrompt => 'Written Challenge',
        ChallengeMode.quiz => 'Skill Quiz',
        ChallengeMode.liveInterview => 'Live Call Interview',
      };

  Map<String, dynamic> toMap() => <String, dynamic>{
        'enabled': enabled,
        'mode': mode.name,
        'prompt': prompt,
        'durationSeconds': durationSeconds,
        'questions': questions.map((QuizQuestion q) => q.toMap()).toList(),
      };
}

enum JobStatus { open, closed, filled }

/// A listing. Stored at `jobs/{jobId}`.
class Job {
  const Job({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.type,
    required this.typeLabel,
    required this.title,
    this.summary = '',
    this.scope = '',
    this.budget = 'Budget TBD',
    this.budgetValue,
    this.skills = const <String>[],
    this.milestones = const <Milestone>[],
    this.challenge = const SkillChallenge(),
    this.escrowFunded = false,
    this.trustScore = 90,
    this.status = JobStatus.open,
    this.views = 0,
    this.shortlisted = 0,
    this.proposalsCount = 0,
    this.equity,
    this.ownerStatusLabel = 'Active now',
    this.weeklyApplicants = const <int>[0, 0, 0, 0, 0, 0, 0],
    this.searchTerms = const <String>[],
    this.hiredProposalId,
    this.hiredFreelancerId,
    this.escrowHeldCents = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory Job.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return Job(
      id: doc.id,
      ownerId: d['ownerId'] as String? ?? '',
      ownerName: d['ownerName'] as String? ?? '',
      type: d['type'] as String? ?? 'freelance',
      typeLabel: d['typeLabel'] as String? ?? 'Freelance',
      title: d['title'] as String? ?? '',
      summary: d['summary'] as String? ?? '',
      scope: d['scope'] as String? ?? '',
      budget: d['budget'] as String? ?? 'Budget TBD',
      budgetValue: (d['budgetValue'] as num?)?.toDouble(),
      skills: (d['skills'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(growable: false),
      milestones: (d['milestones'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) =>
              Milestone.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false),
      challenge:
          SkillChallenge.fromMap(d['challenge'] as Map<String, dynamic>?),
      escrowFunded: d['escrowFunded'] as bool? ?? false,
      trustScore: (d['trustScore'] as num?)?.toInt() ?? 90,
      status: JobStatus.values.firstWhere(
        (JobStatus s) => s.name == d['status'],
        orElse: () => JobStatus.open,
      ),
      views: (d['views'] as num?)?.toInt() ?? 0,
      shortlisted: (d['shortlisted'] as num?)?.toInt() ?? 0,
      proposalsCount: (d['proposalsCount'] as num?)?.toInt() ?? 0,
      equity: d['equity'] as String?,
      ownerStatusLabel: d['ownerStatusLabel'] as String? ?? 'Active now',
      weeklyApplicants: (d['weeklyApplicants'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => (e as num).toInt())
          .toList(growable: false),
      searchTerms: (d['searchTerms'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(growable: false),
      hiredProposalId: d['hiredProposalId'] as String?,
      hiredFreelancerId: d['hiredFreelancerId'] as String?,
      escrowHeldCents: (d['escrowHeldCents'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String ownerId;
  final String ownerName;

  /// `freelance` | `agency` | `startup` — drives the home filter chips.
  final String type;
  final String typeLabel;
  final String title;
  final String summary;
  final String scope;
  final String budget;

  /// Numeric budget parsed at write time so the browse list can sort.
  final double? budgetValue;
  final List<String> skills;
  final List<Milestone> milestones;
  final SkillChallenge challenge;
  final bool escrowFunded;
  final int trustScore;
  final JobStatus status;
  final int views;
  final int shortlisted;
  final int proposalsCount;
  final String? equity;
  final String ownerStatusLabel;
  final List<int> weeklyApplicants;
  final List<String> searchTerms;

  /// Set once someone is hired — the engagement half of a listing.
  final String? hiredProposalId;
  final String? hiredFreelancerId;

  /// Client money currently held against this listing's milestones.
  final int escrowHeldCents;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasChallenge => challenge.enabled && challenge.prompt.isNotEmpty;
  bool get hasEquity => equity != null && equity!.isNotEmpty;
  bool get isOpen => status == JobStatus.open;

  bool get isHired => hiredProposalId != null;

  double get escrowHeld => escrowHeldCents / 100;

  /// True once every milestone has been paid out.
  bool get isFullyReleased =>
      milestones.isNotEmpty && milestones.every((Milestone m) => m.released);

  /// Average of the submitted bids, filled in by the proposal repository.
  String get avgBidPlaceholder => proposalsCount == 0 ? '—' : budget;

  static List<String> buildSearchTerms(
    String title,
    List<String> skills,
    String summary,
  ) {
    final Set<String> terms = <String>{};
    for (final String source in <String>[title, summary, ...skills]) {
      for (final String word
          in source.toLowerCase().split(RegExp(r'[^a-z0-9+#.]+'))) {
        if (word.length < 2) continue;
        terms.add(word);
        for (int i = 2; i <= word.length && i <= 8; i++) {
          terms.add(word.substring(0, i));
        }
      }
    }
    return terms.take(200).toList(growable: false);
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'ownerId': ownerId,
        'ownerName': ownerName,
        'type': type,
        'typeLabel': typeLabel,
        'title': title,
        'summary': summary,
        'scope': scope,
        'budget': budget,
        'budgetValue': budgetValue,
        'skills': skills,
        'milestones': milestones.map((Milestone m) => m.toMap()).toList(),
        'challenge': challenge.toMap(),
        'escrowFunded': escrowFunded,
        'trustScore': trustScore,
        'status': status.name,
        'views': views,
        'shortlisted': shortlisted,
        'proposalsCount': proposalsCount,
        'equity': equity,
        'ownerStatusLabel': ownerStatusLabel,
        'weeklyApplicants': weeklyApplicants,
        'searchTerms': buildSearchTerms(title, skills, summary),
      };

  Job copyWith({
    String? title,
    String? summary,
    String? scope,
    String? budget,
    double? budgetValue,
    List<String>? skills,
    List<Milestone>? milestones,
    SkillChallenge? challenge,
    JobStatus? status,
    int? proposalsCount,
    int? views,
    int? shortlisted,
    String? equity,
  }) =>
      Job(
        id: id,
        ownerId: ownerId,
        ownerName: ownerName,
        type: type,
        typeLabel: typeLabel,
        title: title ?? this.title,
        summary: summary ?? this.summary,
        scope: scope ?? this.scope,
        budget: budget ?? this.budget,
        budgetValue: budgetValue ?? this.budgetValue,
        skills: skills ?? this.skills,
        milestones: milestones ?? this.milestones,
        challenge: challenge ?? this.challenge,
        escrowFunded: escrowFunded,
        trustScore: trustScore,
        status: status ?? this.status,
        views: views ?? this.views,
        shortlisted: shortlisted ?? this.shortlisted,
        proposalsCount: proposalsCount ?? this.proposalsCount,
        equity: equity ?? this.equity,
        ownerStatusLabel: ownerStatusLabel,
        weeklyApplicants: weeklyApplicants,
        searchTerms: searchTerms,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
