import 'package:cloud_firestore/cloud_firestore.dart';

import 'message.dart';

/// The denormalised copy of a participant kept on the chat document so the
/// inbox renders from a single read per conversation.
class ChatParticipant {
  const ChatParticipant({
    required this.uid,
    required this.displayName,
    this.role = 'freelancer',
    this.title = '',
    this.trustScore = 60,
    this.verified = false,
  });

  factory ChatParticipant.fromMap(String uid, Map<String, dynamic> map) =>
      ChatParticipant(
        uid: uid,
        displayName: map['displayName'] as String? ?? 'Felicek user',
        role: map['role'] as String? ?? 'freelancer',
        title: map['title'] as String? ?? '',
        trustScore: (map['trustScore'] as num?)?.toInt() ?? 60,
        verified: map['verified'] as bool? ?? false,
      );

  final String uid;
  final String displayName;
  final String role;
  final String title;
  final int trustScore;
  final bool verified;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'displayName': displayName,
        'role': role,
        'title': title,
        'trustScore': trustScore,
        'verified': verified,
      };
}

/// A one-to-one conversation. Stored at `chats/{chatId}`.
///
/// `chatId` is deterministic — the two uids sorted and joined, optionally
/// scoped to a job — so both sides derive the same id without a lookup and a
/// double-tap can never create two threads.
class ChatThread {
  const ChatThread({
    required this.id,
    required this.participantIds,
    required this.participants,
    this.jobId,
    this.jobTitle,
    this.lastMessagePreview = '',
    this.lastMessageSenderId,
    this.lastMessageAt,
    this.lastMessageType = MessageType.text,
    this.unread = const <String, int>{},
    this.deliveredUpTo = const <String, DateTime>{},
    this.readUpTo = const <String, DateTime>{},
    this.typingUntil = const <String, DateTime>{},
    this.mutedBy = const <String>[],
    this.archivedBy = const <String>[],
    this.blockedBy = const <String>[],
    this.createdAt,
    this.updatedAt,
  });

  factory ChatThread.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    final Map<String, dynamic> rawParticipants = Map<String, dynamic>.from(
        d['participants'] as Map? ?? <String, dynamic>{});
    return ChatThread(
      id: doc.id,
      participantIds: (d['participantIds'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(growable: false),
      participants: rawParticipants.map(
        (String uid, dynamic value) => MapEntry<String, ChatParticipant>(
          uid,
          ChatParticipant.fromMap(uid, Map<String, dynamic>.from(value as Map)),
        ),
      ),
      jobId: d['jobId'] as String?,
      jobTitle: d['jobTitle'] as String?,
      lastMessagePreview: d['lastMessagePreview'] as String? ?? '',
      lastMessageSenderId: d['lastMessageSenderId'] as String?,
      lastMessageAt: (d['lastMessageAt'] as Timestamp?)?.toDate(),
      lastMessageType: MessageType.values.firstWhere(
        (MessageType t) => t.name == d['lastMessageType'],
        orElse: () => MessageType.text,
      ),
      unread: _intMap(d['unread']),
      deliveredUpTo: _dateMap(d['deliveredUpTo']),
      readUpTo: _dateMap(d['readUpTo']),
      typingUntil: _dateMap(d['typingUntil']),
      mutedBy: _stringList(d['mutedBy']),
      archivedBy: _stringList(d['archivedBy']),
      blockedBy: _stringList(d['blockedBy']),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final List<String> participantIds;
  final Map<String, ChatParticipant> participants;
  final String? jobId;
  final String? jobTitle;
  final String lastMessagePreview;
  final String? lastMessageSenderId;
  final DateTime? lastMessageAt;
  final MessageType lastMessageType;
  final Map<String, int> unread;
  final Map<String, DateTime> deliveredUpTo;
  final Map<String, DateTime> readUpTo;
  final Map<String, DateTime> typingUntil;
  final List<String> mutedBy;
  final List<String> archivedBy;
  final List<String> blockedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Deterministic thread id. A conversation is scoped to a job when one
  /// exists so a client hiring the same person twice keeps the threads apart.
  static String idFor(String uidA, String uidB, {String? jobId}) {
    final List<String> pair = <String>[uidA, uidB]..sort();
    final String base = pair.join('__');
    return jobId == null || jobId.isEmpty ? base : '${base}__$jobId';
  }

  String otherIdFor(String myUid) => participantIds.firstWhere(
        (String id) => id != myUid,
        orElse: () => myUid,
      );

  ChatParticipant otherFor(String myUid) {
    final String otherId = otherIdFor(myUid);
    return participants[otherId] ??
        ChatParticipant(uid: otherId, displayName: 'Felicek user');
  }

  int unreadFor(String uid) => unread[uid] ?? 0;

  bool isMutedBy(String uid) => mutedBy.contains(uid);

  bool isArchivedBy(String uid) => archivedBy.contains(uid);

  /// Either side can block; once blocked the composer is disabled for both.
  bool get isBlocked => blockedBy.isNotEmpty;

  bool blockedByMe(String uid) => blockedBy.contains(uid);

  /// A typing flag written with a 6-second expiry, so a crashed app never
  /// leaves the other person staring at "typing…" forever.
  bool isTyping(String uid, {DateTime? now}) {
    final DateTime? until = typingUntil[uid];
    if (until == null) return false;
    return until.isAfter(now ?? DateTime.now());
  }

  bool otherIsTyping(String myUid, {DateTime? now}) =>
      isTyping(otherIdFor(myUid), now: now);

  static Map<String, int> _intMap(Object? raw) {
    if (raw is! Map) return const <String, int>{};
    return raw.map(
      (Object? k, Object? v) =>
          MapEntry<String, int>(k.toString(), (v as num?)?.toInt() ?? 0),
    );
  }

  static Map<String, DateTime> _dateMap(Object? raw) {
    if (raw is! Map) return const <String, DateTime>{};
    final Map<String, DateTime> out = <String, DateTime>{};
    raw.forEach((Object? k, Object? v) {
      if (v is Timestamp) out[k.toString()] = v.toDate();
    });
    return out;
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw.map((dynamic e) => e.toString()).toList(growable: false);
  }
}
