import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationKind {
  message,
  proposal,
  proposalAccepted,
  proposalDeclined,
  jobMatch,
  payout,
  verification,
  system;

  static NotificationKind fromName(String? name) =>
      NotificationKind.values.firstWhere(
        (NotificationKind k) => k.name == name,
        orElse: () => NotificationKind.system,
      );
}

/// An in-app notification. Stored at `users/{uid}/notifications/{id}`.
///
/// Written by whichever client causes the event (Firestore rules restrict who
/// may write into another user's notification feed and to what shape), which
/// is how the app delivers alerts with no Cloud Functions and therefore no
/// billing plan upgrade.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.read = false,
    this.chatId,
    this.jobId,
    this.proposalId,
    this.actorId,
    this.actorName,
    this.createdAt,
  });

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return AppNotification(
      id: doc.id,
      kind: NotificationKind.fromName(d['kind'] as String?),
      title: d['title'] as String? ?? '',
      body: d['body'] as String? ?? '',
      read: d['read'] as bool? ?? false,
      chatId: d['chatId'] as String?,
      jobId: d['jobId'] as String?,
      proposalId: d['proposalId'] as String?,
      actorId: d['actorId'] as String?,
      actorName: d['actorName'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final bool read;
  final String? chatId;
  final String? jobId;
  final String? proposalId;
  final String? actorId;
  final String? actorName;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'kind': kind.name,
        'title': title,
        'body': body,
        'read': read,
        'chatId': chatId,
        'jobId': jobId,
        'proposalId': proposalId,
        'actorId': actorId,
        'actorName': actorName,
      };
}
