import 'package:cloud_firestore/cloud_firestore.dart';

/// What a message *is*. `system` messages are written by the app when a job
/// event happens (proposal sent, hired, milestone released) so the thread reads
/// as a complete record of the engagement.
enum MessageType { text, system, offer }

/// Delivery state of one of *my* messages, derived from the chat-level
/// watermarks rather than per-message arrays — one write per read instead of
/// one per message, which is what keeps this inside the free tier.
enum MessageStatus {
  /// Queued locally, not yet acknowledged by Firestore.
  sending,

  /// The server has it.
  sent,

  /// The other device has received it (its inbox listener acked).
  delivered,

  /// The other person opened the thread past this message.
  read,

  /// Rejected — validation or permissions. Retryable from the UI.
  failed,
}

/// A quoted message shown above a reply.
class MessageQuote {
  const MessageQuote({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.preview,
  });

  factory MessageQuote.fromMap(Map<String, dynamic> map) => MessageQuote(
        messageId: map['messageId'] as String? ?? '',
        senderId: map['senderId'] as String? ?? '',
        senderName: map['senderName'] as String? ?? '',
        preview: map['preview'] as String? ?? '',
      );

  final String messageId;
  final String senderId;
  final String senderName;
  final String preview;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'messageId': messageId,
        'senderId': senderId,
        'senderName': senderName,
        'preview': preview,
      };
}

/// A structured price offer sent inside a thread.
class MessageOffer {
  const MessageOffer({
    required this.amountCents,
    required this.milestone,
    this.accepted = false,
    this.declined = false,
  });

  factory MessageOffer.fromMap(Map<String, dynamic> map) => MessageOffer(
        amountCents: (map['amountCents'] as num?)?.toInt() ?? 0,
        milestone: map['milestone'] as String? ?? '',
        accepted: map['accepted'] as bool? ?? false,
        declined: map['declined'] as bool? ?? false,
      );

  final int amountCents;
  final String milestone;
  final bool accepted;
  final bool declined;

  double get amount => amountCents / 100;
  bool get pending => !accepted && !declined;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'amountCents': amountCents,
        'milestone': milestone,
        'accepted': accepted,
        'declined': declined,
      };
}

/// One message. Stored at `chats/{chatId}/messages/{messageId}`.
///
/// The document id is generated on the client *before* the write, so a retry
/// after a dropped connection overwrites the same document instead of
/// duplicating it.
class Message {
  const Message({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    this.imageBase64,
    this.attachmentName,
    this.watermarked = false,
    this.type = MessageType.text,
    this.sentAt,
    this.clientSentAt,
    this.editedAt,
    this.deletedAt,
    this.quote,
    this.offer,
    this.pendingWrite = false,
    this.localFailure = false,
  });

  factory Message.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return Message(
      id: doc.id,
      senderId: d['senderId'] as String? ?? '',
      senderName: d['senderName'] as String? ?? '',
      text: d['text'] as String? ?? '',
      imageBase64: d['imageBase64'] as String?,
      attachmentName: d['attachmentName'] as String?,
      watermarked: d['watermarked'] as bool? ?? false,
      type: MessageType.values.firstWhere(
        (MessageType t) => t.name == d['type'],
        orElse: () => MessageType.text,
      ),
      sentAt: (d['sentAt'] as Timestamp?)?.toDate(),
      clientSentAt: (d['clientSentAt'] as Timestamp?)?.toDate(),
      editedAt: (d['editedAt'] as Timestamp?)?.toDate(),
      deletedAt: (d['deletedAt'] as Timestamp?)?.toDate(),
      quote: d['quote'] == null
          ? null
          : MessageQuote.fromMap(Map<String, dynamic>.from(d['quote'] as Map)),
      offer: d['offer'] == null
          ? null
          : MessageOffer.fromMap(Map<String, dynamic>.from(d['offer'] as Map)),
      pendingWrite: doc.metadata.hasPendingWrites,
    );
  }

  final String id;
  final String senderId;
  final String senderName;
  final String text;

  /// A shared image, stored inline. Watermarked when [watermarked] is true —
  /// the clean original then lives in the chat's `deliverables` subcollection,
  /// which the recipient cannot read until it is released.
  final String? imageBase64;
  final String? attachmentName;
  final bool watermarked;

  bool get hasImage => imageBase64 != null && imageBase64!.isNotEmpty;
  final MessageType type;

  /// Server timestamp — null while the write is still queued offline.
  final DateTime? sentAt;

  /// Device clock at compose time; used to order optimistic messages.
  final DateTime? clientSentAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final MessageQuote? quote;
  final MessageOffer? offer;

  /// True while Firestore still has this write in its local queue.
  final bool pendingWrite;

  /// Set by the repository when a write was rejected outright.
  final bool localFailure;

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null && !isDeleted;
  bool get isSystem => type == MessageType.system;

  /// Ordering key that keeps optimistic messages in place until the server
  /// timestamp lands.
  DateTime get orderedAt => sentAt ?? clientSentAt ?? DateTime.now();

  /// Body actually rendered — deleted messages become a tombstone.
  String get displayText => isDeleted ? 'This message was deleted' : text;

  /// A message can be edited by its author for 15 minutes.
  bool canEdit(String uid, {DateTime? now}) =>
      senderId == uid &&
      !isDeleted &&
      type == MessageType.text &&
      (now ?? DateTime.now()).difference(orderedAt) <
          const Duration(minutes: 15);

  bool canDelete(String uid) => senderId == uid && !isDeleted;

  /// Resolves the tick state against the chat's read/delivery watermarks.
  MessageStatus statusFor({
    required String myUid,
    required DateTime? otherDeliveredUpTo,
    required DateTime? otherReadUpTo,
  }) {
    if (senderId != myUid) return MessageStatus.read;
    if (localFailure) return MessageStatus.failed;
    if (pendingWrite || sentAt == null) return MessageStatus.sending;
    if (otherReadUpTo != null && !otherReadUpTo.isBefore(sentAt!)) {
      return MessageStatus.read;
    }
    if (otherDeliveredUpTo != null && !otherDeliveredUpTo.isBefore(sentAt!)) {
      return MessageStatus.delivered;
    }
    return MessageStatus.sent;
  }

  /// One-line preview stored on the parent chat document.
  String get preview {
    if (isDeleted) return 'Message deleted';
    return switch (type) {
      MessageType.offer =>
        'Offer · ${offer == null ? '' : '\$${offer!.amount.toStringAsFixed(0)}'}',
      MessageType.system => text,
      MessageType.text => text.replaceAll('\n', ' '),
    };
  }

  Map<String, dynamic> toMap({required bool serverTimestamp}) =>
      <String, dynamic>{
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        if (imageBase64 != null) 'imageBase64': imageBase64,
        if (attachmentName != null) 'attachmentName': attachmentName,
        if (watermarked) 'watermarked': true,
        'type': type.name,
        'sentAt': serverTimestamp
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(sentAt!),
        'clientSentAt': Timestamp.fromDate(clientSentAt ?? DateTime.now()),
        if (quote != null) 'quote': quote!.toMap(),
        if (offer != null) 'offer': offer!.toMap(),
      };

  Message copyWith({
    String? text,
    DateTime? editedAt,
    DateTime? deletedAt,
    bool? localFailure,
    bool? pendingWrite,
    MessageOffer? offer,
  }) =>
      Message(
        id: id,
        senderId: senderId,
        senderName: senderName,
        text: text ?? this.text,
        imageBase64: imageBase64,
        attachmentName: attachmentName,
        watermarked: watermarked,
        type: type,
        sentAt: sentAt,
        clientSentAt: clientSentAt,
        editedAt: editedAt ?? this.editedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        quote: quote,
        offer: offer ?? this.offer,
        pendingWrite: pendingWrite ?? this.pendingWrite,
        localFailure: localFailure ?? this.localFailure,
      );
}
