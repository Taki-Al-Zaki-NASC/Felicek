import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/formatters.dart';
import '../models/job.dart';
import '../models/public_profile.dart';
import '../services/firestore_refs.dart';

/// Listings: browse, publish, edit, close.
class JobRepository {
  JobRepository(this._db);

  final Db _db;

  /// The browse feed. `type` maps to the design's filter chips
  /// (`all` / `freelance` / `agency` / `startup`).
  Stream<List<Job>> watchOpenJobs({String type = 'all', int limit = 40}) {
    JsonQuery query = _db.jobs.where('status', isEqualTo: JobStatus.open.name);
    if (type != 'all') {
      query = query.where('type', isEqualTo: type);
    }
    return query
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((JsonQuerySnap s) =>
            s.docs.map(Job.fromDoc).toList(growable: false));
  }

  /// Listings owned by the signed-in client / agency / startup.
  Stream<List<Job>> watchMyJobs(String ownerId, {int limit = 40}) => _db.jobs
      .where('ownerId', isEqualTo: ownerId)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
          (JsonQuerySnap s) => s.docs.map(Job.fromDoc).toList(growable: false));

  Stream<Job?> watch(String jobId) => _db.job(jobId).snapshots().map(
        (JsonDoc doc) => doc.exists ? Job.fromDoc(doc) : null,
      );

  Future<Job?> fetch(String jobId) async {
    final JsonDoc doc = await _db.job(jobId).get();
    return doc.exists ? Job.fromDoc(doc) : null;
  }

  /// Publishes a new listing and returns its id.
  Future<String> publish({
    required PublicProfile owner,
    required String title,
    required String summary,
    required String scope,
    required String budget,
    required List<String> skills,
    required List<Milestone> milestones,
    required SkillChallenge challenge,
    String? equity,

    /// One correct-option index per quiz question, in the same order as
    /// [SkillChallenge.questions]. Written to the owner-only `challengeKey`
    /// subcollection — never embedded in the job document itself, so an
    /// applicant reading the (public) listing can never see it.
    List<int>? quizAnswerKey,
  }) async {
    final String id = _db.jobs.doc().id;
    final Job job = Job(
      id: id,
      ownerId: owner.uid,
      ownerName: owner.displayName,
      type: owner.role.publishesListingType,
      typeLabel: owner.role.publishesTypeLabel,
      title: title.trim(),
      summary: summary.trim(),
      scope: scope.trim(),
      budget: budget.trim(),
      budgetValue: Fmt.budgetValue(budget),
      skills: skills,
      milestones: milestones,
      challenge: challenge,
      escrowFunded: true,
      trustScore: owner.trustScore,
      equity: equity,
      ownerStatusLabel: 'Active now',
    );
    final WriteBatch batch = _db.firestore.batch();
    batch.set(_db.job(id), <String, dynamic>{
      ...job.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (challenge.mode == ChallengeMode.quiz && quizAnswerKey != null) {
      batch.set(_db.challengeKey(id), <String, dynamic>{
        'correctIndexes': quizAnswerKey,
      });
    }
    await batch.commit();
    return id;
  }

  Future<void> update({
    required String jobId,
    required String title,
    required String summary,
    required String scope,
    required String budget,
    required List<String> skills,
    required List<Milestone> milestones,
    required SkillChallenge challenge,
    String? equity,
    List<int>? quizAnswerKey,
  }) async {
    final WriteBatch batch = _db.firestore.batch();
    batch.set(
      _db.job(jobId),
      <String, dynamic>{
        'title': title.trim(),
        'summary': summary.trim(),
        'scope': scope.trim(),
        'budget': budget.trim(),
        'budgetValue': Fmt.budgetValue(budget),
        'skills': skills,
        'milestones': milestones.map((Milestone m) => m.toMap()).toList(),
        'challenge': challenge.toMap(),
        'equity': equity,
        'searchTerms': Job.buildSearchTerms(title, skills, summary),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    if (challenge.mode == ChallengeMode.quiz && quizAnswerKey != null) {
      batch.set(_db.challengeKey(jobId), <String, dynamic>{
        'correctIndexes': quizAnswerKey,
      });
    }
    await batch.commit();
  }

  Future<void> setStatus(String jobId, JobStatus status) => _db.job(jobId).set(
        <String, dynamic>{
          'status': status.name,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  /// Counts a listing view. Rate-limited by the caller to once per session per
  /// job so the free-tier write budget is not spent on analytics.
  Future<void> recordView(String jobId) async {
    try {
      await _db
          .job(jobId)
          .update(<String, dynamic>{'views': FieldValue.increment(1)});
    } on FirebaseException {
      // A missed view count is not worth surfacing.
    }
  }

  /// Prefix search across titles, summaries and skills.
  Future<List<Job>> search(String query, {int limit = 30}) async {
    final String q = query.trim().toLowerCase();
    if (q.length < 2) return const <Job>[];
    final JsonQuerySnap snap = await _db.jobs
        .where('status', isEqualTo: JobStatus.open.name)
        .where('searchTerms', arrayContains: q)
        .limit(limit)
        .get();
    final List<Job> jobs = snap.docs.map(Job.fromDoc).toList();
    jobs.sort(
      (Job a, Job b) => (b.createdAt ?? DateTime(2000))
          .compareTo(a.createdAt ?? DateTime(2000)),
    );
    return jobs;
  }
}
