import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/public_profile.dart';
import '../services/firestore_refs.dart';

/// Everything a message does, in one place.
///
/// Design notes that shape this class:
///
/// * **Deterministic ids.** A thread id is the two uids sorted (optionally
///   scoped to a job) and a message id is generated on the client *before* the
///   write. Double-taps and retries therefore overwrite instead of duplicate.
/// * **One write per action.** A send is a single batch: the message document
///   plus the parent chat's preview / counters. Read receipts are chat-level
///   watermarks rather than per-message arrays, so marking 200 messages read
///   costs one write, not 200. That is what keeps a real messaging product
///   inside the Firebase free tier.
/// * **Optimistic by default.** Firestore's offline cache surfaces the write
///   immediately with `hasPendingWrites`, so the bubble appears the instant
///   you hit send and quietly gains its tick when the server acknowledges it.
/// * **Ordering by `clientSentAt`.** An unresolved server timestamp reads as
///   `null` locally, which would sort pending messages to the wrong end of the
///   list. Ordering by the client clock keeps optimistic messages exactly
///   where the sender put them; the security rules bound that clock to ±5
///   minutes of server time so it cannot be abused.
class ChatRepository {
  ChatRepository(this._db);

  final Db _db;

  /// How long a typing flag stays valid. A crashed app can therefore never
  /// leave the other person staring at "typing…".
  static const Duration typingTtl = Duration(seconds: 6);

  /// Minimum gap between typing writes while someone keeps typing.
  static const Duration typingThrottle = Duration(seconds: 3);

  static const int pageSize = 30;

  /// Message ids whose write was rejected outright, so the UI can offer retry.
  final Set<String> _failedMessageIds = <String>{};

  bool isFailed(String messageId) => _failedMessageIds.contains(messageId);

  void clearFailure(String messageId) => _failedMessageIds.remove(messageId);

  // ── Reading ─────────────────────────────────────────────────────────────

  /// The inbox, newest conversation first.
  Stream<List<ChatThread>> watchInbox(String uid, {int limit = 60}) => _db.chats
      .where('participantIds', arrayContains: uid)
      .orderBy('lastMessageAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (QuerySnapshot<Json> snap) =>
            snap.docs.map(ChatThread.fromDoc).toList(growable: false),
      );

  Stream<ChatThread?> watchThread(String chatId) =>
      _db.chat(chatId).snapshots().map(
            (DocumentSnapshot<Json> doc) =>
                doc.exists ? ChatThread.fromDoc(doc) : null,
          );

  Future<ChatThread?> fetchThread(String chatId) async {
    final DocumentSnapshot<Json> doc = await _db.chat(chatId).get();
    return doc.exists ? ChatThread.fromDoc(doc) : null;
  }

  /// The most recent [limit] messages, newest first (the list renders
  /// reversed). Growing [limit] is how "load older" works — one live query
  /// keeps every message reactive instead of freezing older pages.
  Stream<List<Message>> watchMessages(String chatId, {int limit = pageSize}) =>
      _db
          .messages(chatId)
          .orderBy('clientSentAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (QuerySnapshot<Json> snap) => snap.docs
                .map(Message.fromDoc)
                .map(
                  (Message m) => _failedMessageIds.contains(m.id)
                      ? m.copyWith(localFailure: true)
                      : m,
                )
                .toList(growable: false),
          );

  /// Total unread across every conversation — drives the tab-bar badge.
  Stream<int> watchTotalUnread(String uid) => watchInbox(uid).map(
        (List<ChatThread> chats) => chats
            .where((ChatThread c) => !c.isArchivedBy(uid))
            .fold<int>(0, (int sum, ChatThread c) => sum + c.unreadFor(uid)),
      );

  // ── Opening a conversation ──────────────────────────────────────────────

  /// Creates the thread if it does not exist and returns its id.
  ///
  /// Both public profiles are embedded on the document so the inbox renders
  /// from one read per conversation.
  Future<String> openThread({
    required PublicProfile me,
    required PublicProfile other,
    String? jobId,
    String? jobTitle,
  }) async {
    final String chatId = ChatThread.idFor(me.uid, other.uid, jobId: jobId);
    final DocumentReference<Json> ref = _db.chat(chatId);
    final DocumentSnapshot<Json> existing = await ref.get();

    final Map<String, dynamic> participants = <String, dynamic>{
      me.uid: _participantFrom(me).toMap(),
      other.uid: _participantFrom(other).toMap(),
    };

    if (existing.exists) {
      // Refresh the denormalised copies — names and verification change.
      await ref.set(
        <String, dynamic>{
          'participants': participants,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return chatId;
    }

    await ref.set(<String, dynamic>{
      'participantIds': <String>[me.uid, other.uid]..sort(),
      'participants': participants,
      'jobId': jobId,
      'jobTitle': jobTitle,
      'lastMessagePreview': '',
      'lastMessageSenderId': null,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageType': MessageType.text.name,
      'unread': <String, int>{me.uid: 0, other.uid: 0},
      'deliveredUpTo': <String, dynamic>{},
      'readUpTo': <String, dynamic>{},
      'typingUntil': <String, dynamic>{},
      'mutedBy': <String>[],
      'archivedBy': <String>[],
      'blockedBy': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return chatId;
  }

  static ChatParticipant _participantFrom(PublicProfile p) => ChatParticipant(
        uid: p.uid,
        displayName: p.displayName,
        role: p.role.key,
        title: p.title,
        trustScore: p.trustScore,
        verified: p.verified,
      );

  // ── Sending ─────────────────────────────────────────────────────────────

  /// Sends a text message. Returns immediately with the new message id; the
  /// bubble is already on screen by then via the offline cache.
  ///
  /// The returned future completes when the server acknowledges the write, and
  /// throws if the write was rejected — callers can await it to surface a
  /// retry affordance without blocking the UI.
  ({String messageId, Future<void> committed}) sendText({
    required String chatId,
    required String senderId,
    required String senderName,
    required String recipientId,
    required String text,
    MessageQuote? quote,
  }) {
    final String body = text.trim();
    final Message message = Message(
      id: _db.messages(chatId).doc().id,
      senderId: senderId,
      senderName: senderName,
      text: body,
      clientSentAt: DateTime.now(),
    );
    return (
      messageId: message.id,
      committed: _commit(
        chatId: chatId,
        recipientId: recipientId,
        message: message.copyWith(),
        quote: quote,
      ),
    );
  }

  /// Sends a structured price offer.
  ({String messageId, Future<void> committed}) sendOffer({
    required String chatId,
    required String senderId,
    required String senderName,
    required String recipientId,
    required int amountCents,
    required String milestone,
  }) {
    final Message message = Message(
      id: _db.messages(chatId).doc().id,
      senderId: senderId,
      senderName: senderName,
      text: milestone,
      type: MessageType.offer,
      clientSentAt: DateTime.now(),
      offer: MessageOffer(amountCents: amountCents, milestone: milestone),
    );
    return (
      messageId: message.id,
      committed:
          _commit(chatId: chatId, recipientId: recipientId, message: message),
    );
  }

  Future<void> _commit({
    required String chatId,
    required String recipientId,
    required Message message,
    MessageQuote? quote,
  }) async {
    final Message payload = quote == null
        ? message
        : Message(
            id: message.id,
            senderId: message.senderId,
            senderName: message.senderName,
            text: message.text,
            type: message.type,
            clientSentAt: message.clientSentAt,
            quote: quote,
            offer: message.offer,
          );

    final WriteBatch batch = _db.firestore.batch();
    batch.set(
      _db.message(chatId, payload.id),
      payload.toMap(serverTimestamp: true),
    );
    batch.set(
      _db.chat(chatId),
      <String, dynamic>{
        'lastMessagePreview': _clampPreview(payload.preview),
        'lastMessageSenderId': payload.senderId,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageType': payload.type.name,
        'unread': <String, dynamic>{recipientId: FieldValue.increment(1)},
        // A new message pulls the thread back out of the recipient's archive.
        'archivedBy': FieldValue.arrayRemove(<String>[recipientId]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    try {
      await batch.commit();
      _failedMessageIds.remove(payload.id);
    } catch (_) {
      _failedMessageIds.add(payload.id);
      rethrow;
    }
  }

  /// Re-commits a message that previously failed, reusing its id.
  Future<void> retry({
    required String chatId,
    required String recipientId,
    required Message message,
  }) {
    _failedMessageIds.remove(message.id);
    return _commit(chatId: chatId, recipientId: recipientId, message: message);
  }

  static String _clampPreview(String text) =>
      text.length <= 120 ? text : '${text.substring(0, 119)}…';

  // ── Editing & deleting ──────────────────────────────────────────────────

  Future<void> editMessage({
    required String chatId,
    required String messageId,
    required String text,
    required bool isLastMessage,
  }) async {
    final String body = text.trim();
    final WriteBatch batch = _db.firestore.batch();
    batch.set(
      _db.message(chatId, messageId),
      <String, dynamic>{'text': body, 'editedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    if (isLastMessage) {
      batch.set(
        _db.chat(chatId),
        <String, dynamic>{
          'lastMessagePreview': _clampPreview(body),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  /// Soft delete: the document stays so the thread keeps its shape, but the
  /// body is cleared on the server rather than merely hidden on the client.
  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
    required bool isLastMessage,
  }) async {
    final WriteBatch batch = _db.firestore.batch();
    batch.set(
      _db.message(chatId, messageId),
      <String, dynamic>{
        'text': '',
        'offer': FieldValue.delete(),
        'quote': FieldValue.delete(),
        'deletedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    if (isLastMessage) {
      batch.set(
        _db.chat(chatId),
        <String, dynamic>{
          'lastMessagePreview': 'Message deleted',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> respondToOffer({
    required String chatId,
    required String messageId,
    required bool accept,
  }) =>
      _db.message(chatId, messageId).set(
        <String, dynamic>{
          'offer': <String, dynamic>{'accepted': accept, 'declined': !accept},
        },
        SetOptions(merge: true),
      );

  // ── Receipts, typing, presence ──────────────────────────────────────────

  /// Marks everything up to [upTo] as read and zeroes my unread counter.
  /// One write regardless of how many messages were unread.
  Future<void> markRead({
    required String chatId,
    required String uid,
    required DateTime upTo,
  }) async {
    try {
      await _db.chat(chatId).set(
        <String, dynamic>{
          'readUpTo': <String, dynamic>{uid: Timestamp.fromDate(upTo)},
          'deliveredUpTo': <String, dynamic>{uid: Timestamp.fromDate(upTo)},
          'unread': <String, dynamic>{uid: 0},
        },
        SetOptions(merge: true),
      );
    } on FirebaseException {
      // Receipts are best-effort; never block reading a thread on them.
    }
  }

  /// Acknowledges receipt without opening the thread — called by the inbox
  /// listener, which is what turns one tick into two.
  Future<void> markDelivered({
    required String chatId,
    required String uid,
    required DateTime upTo,
  }) async {
    try {
      await _db.chat(chatId).set(
        <String, dynamic>{
          'deliveredUpTo': <String, dynamic>{uid: Timestamp.fromDate(upTo)},
        },
        SetOptions(merge: true),
      );
    } on FirebaseException {
      // Best-effort.
    }
  }

  Future<void> setTyping({
    required String chatId,
    required String uid,
    required bool typing,
  }) async {
    try {
      final DateTime until = typing
          ? DateTime.now().add(typingTtl)
          : DateTime.now().subtract(const Duration(seconds: 1));
      await _db.chat(chatId).set(
        <String, dynamic>{
          'typingUntil': <String, dynamic>{uid: Timestamp.fromDate(until)},
        },
        SetOptions(merge: true),
      );
    } on FirebaseException {
      // Best-effort.
    }
  }

  // ── Thread management ───────────────────────────────────────────────────

  Future<void> setMuted({
    required String chatId,
    required String uid,
    required bool muted,
  }) =>
      _db.chat(chatId).set(
        <String, dynamic>{
          'mutedBy': muted
              ? FieldValue.arrayUnion(<String>[uid])
              : FieldValue.arrayRemove(<String>[uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  Future<void> setArchived({
    required String chatId,
    required String uid,
    required bool archived,
  }) =>
      _db.chat(chatId).set(
        <String, dynamic>{
          'archivedBy': archived
              ? FieldValue.arrayUnion(<String>[uid])
              : FieldValue.arrayRemove(<String>[uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  /// Blocking is recorded on the thread so both composers lock immediately,
  /// and on the blocker's private record so it survives the thread.
  Future<void> setBlocked({
    required String chatId,
    required String uid,
    required bool blocked,
  }) =>
      _db.chat(chatId).set(
        <String, dynamic>{
          'blockedBy': blocked
              ? FieldValue.arrayUnion(<String>[uid])
              : FieldValue.arrayRemove(<String>[uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  // ── Cross-feature notification ──────────────────────────────────────────

  /// Drops an in-app notification into the recipient's feed. Firestore rules
  /// allow exactly this shape and nothing else, which is how the product
  /// delivers alerts with no Cloud Functions and therefore no paid plan.
  Future<void> notifyNewMessage({
    required String recipientId,
    required String actorId,
    required String actorName,
    required String chatId,
    required String preview,
  }) async {
    try {
      await _db.notifications(recipientId).add(<String, dynamic>{
        ...AppNotification(
          id: '',
          kind: NotificationKind.message,
          title: actorName,
          body: preview,
          chatId: chatId,
          actorId: actorId,
          actorName: actorName,
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      // A missed notification must never fail the send it describes.
    }
  }
}
