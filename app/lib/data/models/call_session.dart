import 'package:cloud_firestore/cloud_firestore.dart';

enum CallKind { audio, video }

enum CallStatus {
  /// Offer written, waiting for the callee.
  ringing,

  /// Callee accepted; SDP answer exchanged.
  accepted,

  /// Callee declined explicitly.
  declined,

  /// Caller hung up before it was answered.
  cancelled,

  /// Nobody answered within the ring window.
  missed,

  /// Either side ended a connected call.
  ended,

  /// One side's connection dropped without a clean hang-up.
  failed;

  bool get isActive =>
      this == CallStatus.ringing || this == CallStatus.accepted;

  static CallStatus fromName(String? name) => CallStatus.values.firstWhere(
        (CallStatus s) => s.name == name,
        orElse: () => CallStatus.ended,
      );
}

/// One audio/video call. Stored at `calls/{callId}`, signaling exchanged
/// through `calls/{callId}/callerCandidates` and `.../calleeCandidates`.
///
/// Works the same way on every platform `flutter_webrtc` supports — Android
/// and iOS phones and tablets, macOS and Windows desktop — because the
/// signaling is just Firestore documents; only the media capture/render layer
/// is platform-specific, and that's entirely inside the plugin.
class CallSession {
  const CallSession({
    required this.id,
    required this.callerId,
    required this.callerName,
    required this.calleeId,
    required this.calleeName,
    required this.kind,
    this.status = CallStatus.ringing,
    this.chatId,
    this.offerSdp,
    this.offerType,
    this.answerSdp,
    this.answerType,
    this.createdAt,
    this.acceptedAt,
    this.endedAt,
    this.endedBy,
    this.durationSeconds = 0,
  });

  factory CallSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return CallSession(
      id: doc.id,
      callerId: d['callerId'] as String? ?? '',
      callerName: d['callerName'] as String? ?? 'Felicek user',
      calleeId: d['calleeId'] as String? ?? '',
      calleeName: d['calleeName'] as String? ?? 'Felicek user',
      kind: (d['kind'] as String?) == 'audio' ? CallKind.audio : CallKind.video,
      status: CallStatus.fromName(d['status'] as String?),
      chatId: d['chatId'] as String?,
      offerSdp: d['offerSdp'] as String?,
      offerType: d['offerType'] as String?,
      answerSdp: d['answerSdp'] as String?,
      answerType: d['answerType'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      acceptedAt: (d['acceptedAt'] as Timestamp?)?.toDate(),
      endedAt: (d['endedAt'] as Timestamp?)?.toDate(),
      endedBy: d['endedBy'] as String?,
      durationSeconds: (d['durationSeconds'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String callerId;
  final String callerName;
  final String calleeId;
  final String calleeName;
  final CallKind kind;
  final CallStatus status;
  final String? chatId;
  final String? offerSdp;
  final String? offerType;
  final String? answerSdp;
  final String? answerType;
  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final DateTime? endedAt;
  final String? endedBy;
  final int durationSeconds;

  String otherIdFor(String myUid) => myUid == callerId ? calleeId : callerId;

  String otherNameFor(String myUid) =>
      myUid == callerId ? calleeName : callerName;

  bool isCallerFor(String myUid) => myUid == callerId;
}
