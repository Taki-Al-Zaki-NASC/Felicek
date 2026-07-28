import 'package:cloud_firestore/cloud_firestore.dart';

/// A review left after a completed engagement. Stored at `reviews/{id}` with
/// the deterministic id `${jobId}__${authorId}` so one person can leave one
/// review per job — no brigading, and a re-submit edits rather than stacks.
class Review {
  const Review({
    required this.id,
    required this.jobId,
    required this.jobTitle,
    required this.authorId,
    required this.authorName,
    required this.subjectId,
    required this.rating,
    this.comment = '',
    this.amountCents = 0,
    this.createdAt,
  });

  factory Review.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return Review(
      id: doc.id,
      jobId: d['jobId'] as String? ?? '',
      jobTitle: d['jobTitle'] as String? ?? '',
      authorId: d['authorId'] as String? ?? '',
      authorName: d['authorName'] as String? ?? '',
      subjectId: d['subjectId'] as String? ?? '',
      rating: (d['rating'] as num?)?.toInt() ?? 5,
      comment: d['comment'] as String? ?? '',
      amountCents: (d['amountCents'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  static String idFor({required String jobId, required String authorId}) =>
      '${jobId}__$authorId';

  final String id;
  final String jobId;
  final String jobTitle;

  /// Who wrote it.
  final String authorId;
  final String authorName;

  /// Who it is about.
  final String subjectId;

  /// 1–5.
  final int rating;
  final String comment;
  final int amountCents;
  final DateTime? createdAt;

  double get amount => amountCents / 100;

  /// "★★★★★" / "★★★★☆", the way the design renders it.
  String get stars => '★' * rating + '☆' * (5 - rating);

  Map<String, dynamic> toMap() => <String, dynamic>{
        'jobId': jobId,
        'jobTitle': jobTitle,
        'authorId': authorId,
        'authorName': authorName,
        'subjectId': subjectId,
        'rating': rating.clamp(1, 5),
        'comment': comment.trim(),
        'amountCents': amountCents,
      };
}
