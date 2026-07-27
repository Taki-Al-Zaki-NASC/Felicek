import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';
import 'user_role.dart';

/// The public mirror of an account, stored at `profiles/{uid}`.
///
/// `users/{uid}` is readable only by its owner because it holds the email
/// address, verification reference numbers, wallet balance and block list.
/// Everything other people are allowed to see lives here instead, written by
/// the owner in the same batch as the private record.
class PublicProfile {
  const PublicProfile({
    required this.uid,
    required this.displayName,
    required this.role,
    this.title = '',
    this.bio = '',
    this.location = '',
    this.skills = const <String>[],
    this.hourlyRate,
    this.trustScore = 60,
    this.jobSuccess = 0,
    this.jobsDone = 0,
    this.totalEarnedCents = 0,
    this.verified = false,
    this.profilePhotoBase64,
    this.lastSeenAt,
    this.searchTerms = const <String>[],
  });

  factory PublicProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return PublicProfile(
      uid: doc.id,
      displayName: d['displayName'] as String? ?? 'Felicek user',
      role: UserRole.fromKey(d['role'] as String?),
      title: d['title'] as String? ?? '',
      bio: d['bio'] as String? ?? '',
      location: d['location'] as String? ?? '',
      skills: (d['skills'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(growable: false),
      hourlyRate: (d['hourlyRate'] as num?)?.toDouble(),
      trustScore: (d['trustScore'] as num?)?.toInt() ?? 60,
      jobSuccess: (d['jobSuccess'] as num?)?.toInt() ?? 0,
      jobsDone: (d['jobsDone'] as num?)?.toInt() ?? 0,
      totalEarnedCents: (d['totalEarnedCents'] as num?)?.toInt() ?? 0,
      verified: d['verified'] as bool? ?? false,
      profilePhotoBase64: d['profilePhotoBase64'] as String?,
      lastSeenAt: (d['lastSeenAt'] as Timestamp?)?.toDate(),
      searchTerms: (d['searchTerms'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(growable: false),
    );
  }

  factory PublicProfile.fromUser(AppUser user) => PublicProfile(
        uid: user.uid,
        displayName: user.displayName,
        role: user.role,
        title: user.title,
        bio: user.bio,
        location: user.location,
        skills: user.skills,
        hourlyRate: user.hourlyRate,
        trustScore: user.trustScore,
        jobSuccess: user.jobSuccess,
        jobsDone: user.jobsDone,
        totalEarnedCents: user.totalEarnedCents,
        verified: user.kyc.isVerified,
        profilePhotoBase64: user.profilePhotoBase64,
        lastSeenAt: user.lastSeenAt,
      );

  final String uid;
  final String displayName;
  final UserRole role;
  final String title;
  final String bio;
  final String location;
  final List<String> skills;
  final double? hourlyRate;
  final int trustScore;
  final int jobSuccess;
  final int jobsDone;
  final int totalEarnedCents;
  final bool verified;
  final String? profilePhotoBase64;
  final DateTime? lastSeenAt;
  final List<String> searchTerms;

  double get totalEarned => totalEarnedCents / 100;

  /// "Active now" / "Active 3h ago" / "Inactive 2d" — the client-status pill.
  String get presenceLabel {
    final DateTime? seen = lastSeenAt;
    if (seen == null) return 'New here';
    final Duration d = DateTime.now().difference(seen);
    if (d.inMinutes < 5) return 'Active now';
    if (d.inMinutes < 60) return 'Active ${d.inMinutes}m ago';
    if (d.inHours < 24) return 'Active ${d.inHours}h ago';
    return 'Inactive ${d.inDays}d';
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'displayName': displayName,
        'role': role.key,
        'title': title,
        'bio': bio,
        'location': location,
        'skills': skills,
        'hourlyRate': hourlyRate,
        'trustScore': trustScore,
        'jobSuccess': jobSuccess,
        'jobsDone': jobsDone,
        'totalEarnedCents': totalEarnedCents,
        'verified': verified,
        'profilePhotoBase64': profilePhotoBase64,
        'searchTerms': AppUser.buildSearchTerms(displayName, skills, title),
      };
}
