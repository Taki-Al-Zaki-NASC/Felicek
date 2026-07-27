import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/call_session.dart';
import 'firestore_refs.dart';

/// What the local side of an active call is doing.
enum CallPhase {
  idle,
  requestingPermissions,
  dialing,
  ringingIncoming,
  connecting,
  connected,
  ended,
  failed,
}

/// One-to-one audio/video calling over WebRTC, signaled through Firestore.
///
/// There is no media server: two devices exchange an SDP offer/answer and ICE
/// candidates as plain Firestore documents (`calls/{id}` plus its
/// `callerCandidates` / `calleeCandidates` subcollections), then talk to each
/// other directly (or via a public STUN server when a direct path needs NAT
/// traversal help). That is what keeps calling inside the free tier — there
/// is no per-minute media-relay bill, at the cost of calls occasionally
/// failing to connect on very restrictive NATs, where a paid TURN relay would
/// be the fix later.
///
/// `flutter_webrtc` backs this identically on Android, iOS, macOS and
/// Windows — the platform differences live entirely inside the plugin.
class CallService extends ChangeNotifier {
  CallService(this._db);

  final Db _db;

  static const List<Map<String, String>> _iceServers = <Map<String, String>>[
    <String, String>{'urls': 'stun:stun.l.google.com:19302'},
    <String, String>{'urls': 'stun:stun1.l.google.com:19302'},
  ];

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<DocumentSnapshot<Json>>? _callDocSub;
  StreamSubscription<QuerySnapshot<Json>>? _remoteCandidatesSub;
  StreamSubscription<QuerySnapshot<Json>>? _incomingCallsSub;
  Timer? _durationTicker;
  Timer? _ringTimeout;

  CallPhase _phase = CallPhase.idle;
  CallSession? _activeCall;
  bool _muted = false;
  bool _cameraOff = false;
  bool _frontCamera = true;
  String? _error;
  int _elapsedSeconds = 0;
  bool _renderersReady = false;

  CallPhase get phase => _phase;
  CallSession? get activeCall => _activeCall;
  bool get muted => _muted;
  bool get cameraOff => _cameraOff;
  String? get error => _error;
  int get elapsedSeconds => _elapsedSeconds;
  bool get inCall =>
      _phase == CallPhase.connecting || _phase == CallPhase.connected;

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  void _emit([CallPhase? phase]) {
    if (phase != null) _phase = phase;
    notifyListeners();
  }

  // ── Incoming-call listener ──────────────────────────────────────────────

  /// Watches for a ringing call addressed to [uid]. The UI should call this
  /// once, near app start, and show an incoming-call screen when it fires.
  void listenForIncomingCalls(
      String uid, void Function(CallSession) onIncoming) {
    _incomingCallsSub?.cancel();
    _incomingCallsSub = _db.calls
        .where('calleeId', isEqualTo: uid)
        .where('status', isEqualTo: CallStatus.ringing.name)
        .snapshots()
        .listen((QuerySnapshot<Json> snap) {
      for (final DocumentChange<Json> change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          onIncoming(CallSession.fromDoc(change.doc));
        }
      }
    });
  }

  void stopListeningForIncomingCalls() {
    _incomingCallsSub?.cancel();
    _incomingCallsSub = null;
  }

  // ── Placing a call ──────────────────────────────────────────────────────

  Future<bool> _grantMediaPermissions(CallKind kind) async {
    final List<Permission> needed = <Permission>[
      Permission.microphone,
      if (kind == CallKind.video) Permission.camera,
    ];
    final Map<Permission, PermissionStatus> results = await needed.request();
    return results.values.every((PermissionStatus s) => s.isGranted);
  }

  Future<String?> startCall({
    required String myUid,
    required String myName,
    required String otherUid,
    required String otherName,
    required CallKind kind,
    String? chatId,
  }) async {
    _error = null;
    _emit(CallPhase.requestingPermissions);
    if (!await _grantMediaPermissions(kind)) {
      _error = 'Allow microphone${kind == CallKind.video ? ' and camera' : ''} '
          'access to place a call.';
      _emit(CallPhase.failed);
      return null;
    }

    await _ensureRenderers();
    final String callId = _db.newId(_db.calls);
    final CallSession call = CallSession(
      id: callId,
      callerId: myUid,
      callerName: myName,
      calleeId: otherUid,
      calleeName: otherName,
      kind: kind,
      chatId: chatId,
    );
    _activeCall = call;
    _emit(CallPhase.dialing);

    try {
      await _openMedia(kind);
      _pc = await _createPeerConnection();

      _pc!.onIceCandidate = (RTCIceCandidate c) => _writeCandidate(
            callId: callId,
            path: 'callerCandidates',
            candidate: c,
          );

      final RTCSessionDescription offer = await _pc!.createOffer(
        kind == CallKind.video
            ? const <String, dynamic>{
                'offerToReceiveAudio': true,
                'offerToReceiveVideo': true
              }
            : const <String, dynamic>{
                'offerToReceiveAudio': true,
                'offerToReceiveVideo': false
              },
      );
      await _pc!.setLocalDescription(offer);

      await _db.call(callId).set(<String, dynamic>{
        'callerId': myUid,
        'callerName': myName,
        'calleeId': otherUid,
        'calleeName': otherName,
        'kind': kind.name,
        'status': CallStatus.ringing.name,
        'chatId': chatId,
        'offerSdp': offer.sdp,
        'offerType': offer.type,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _watchCallDoc(callId, isCaller: true);
      _ringTimeout = Timer(const Duration(seconds: 45), () {
        if (_phase == CallPhase.dialing) _markMissedAndClose(callId);
      });
      return callId;
    } on Object catch (e) {
      _error = _describeError(e);
      _emit(CallPhase.failed);
      await _cleanup();
      return null;
    }
  }

  // ── Answering ────────────────────────────────────────────────────────────

  Future<void> acceptCall(CallSession call) async {
    _error = null;
    _activeCall = call;
    _emit(CallPhase.requestingPermissions);
    if (!await _grantMediaPermissions(call.kind)) {
      _error =
          'Allow microphone${call.kind == CallKind.video ? ' and camera' : ''} '
          'access to answer.';
      _emit(CallPhase.failed);
      await declineCall(call, status: CallStatus.declined);
      return;
    }

    await _ensureRenderers();
    _emit(CallPhase.connecting);

    try {
      await _openMedia(call.kind);
      _pc = await _createPeerConnection();
      _pc!.onIceCandidate = (RTCIceCandidate c) => _writeCandidate(
            callId: call.id,
            path: 'calleeCandidates',
            candidate: c,
          );

      await _pc!.setRemoteDescription(
        RTCSessionDescription(call.offerSdp, call.offerType),
      );
      final RTCSessionDescription answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);

      await _db.call(call.id).set(
        <String, dynamic>{
          'status': CallStatus.accepted.name,
          'answerSdp': answer.sdp,
          'answerType': answer.type,
          'acceptedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      _listenForRemoteCandidates(call.id, path: 'callerCandidates');
      _watchCallDoc(call.id, isCaller: false);
      _startDurationTimer();
    } on Object catch (e) {
      _error = _describeError(e);
      _emit(CallPhase.failed);
      await _cleanup();
    }
  }

  Future<void> declineCall(CallSession call,
      {CallStatus status = CallStatus.declined}) async {
    try {
      await _db.call(call.id).set(
        <String, dynamic>{
          'status': status.name,
          'endedAt': FieldValue.serverTimestamp(),
          'endedBy': status.name,
        },
        SetOptions(merge: true),
      );
    } on FirebaseException {
      // The other side will time out on its own ring window regardless.
    }
    if (_activeCall?.id == call.id) await _cleanup();
  }

  // ── In-call state ────────────────────────────────────────────────────────

  void _watchCallDoc(String callId, {required bool isCaller}) {
    _callDocSub?.cancel();
    _callDocSub =
        _db.call(callId).snapshots().listen((DocumentSnapshot<Json> doc) async {
      if (!doc.exists) return;
      final CallSession call = CallSession.fromDoc(doc);
      _activeCall = call;

      if (isCaller && call.status == CallStatus.accepted && _pc != null) {
        final RTCSessionDescription? remoteDesc =
            await _pc!.getRemoteDescription();
        if (remoteDesc == null && call.answerSdp != null) {
          await _pc!.setRemoteDescription(
            RTCSessionDescription(call.answerSdp, call.answerType),
          );
          _listenForRemoteCandidates(callId, path: 'calleeCandidates');
          _ringTimeout?.cancel();
          _startDurationTimer();
        }
        _emit(CallPhase.connecting);
      }

      if (call.status == CallStatus.declined && _phase != CallPhase.ended) {
        _error = '${call.otherNameFor(call.callerId)} declined the call.';
        _emit(CallPhase.ended);
        await _cleanup();
      } else if (call.status == CallStatus.ended && _phase != CallPhase.ended) {
        _emit(CallPhase.ended);
        await _cleanup();
      }
    });
  }

  void _listenForRemoteCandidates(String callId, {required String path}) {
    _remoteCandidatesSub?.cancel();
    _remoteCandidatesSub = _db
        .call(callId)
        .collection(path)
        .snapshots()
        .listen((QuerySnapshot<Json> snap) {
      for (final DocumentChange<Json> change in snap.docChanges) {
        if (change.type != DocumentChangeType.added || _pc == null) continue;
        final Json d = change.doc.data() ?? <String, dynamic>{};
        _pc!.addCandidate(
          RTCIceCandidate(
            d['candidate'] as String?,
            d['sdpMid'] as String?,
            (d['sdpMLineIndex'] as num?)?.toInt(),
          ),
        );
      }
    });
  }

  Future<void> _writeCandidate({
    required String callId,
    required String path,
    required RTCIceCandidate candidate,
  }) async {
    try {
      await _db.call(callId).collection(path).add(<String, dynamic>{
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      // A dropped candidate is not fatal — WebRTC gathers several.
    }
  }

  Future<RTCPeerConnection> _createPeerConnection() async {
    final RTCPeerConnection pc = await createPeerConnection(<String, dynamic>{
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    });

    pc.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        if (_phase != CallPhase.connected) _emit(CallPhase.connected);
        notifyListeners();
      }
    };
    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _error = 'The call connection was lost.';
        _emit(CallPhase.failed);
        _cleanup();
      }
    };

    if (_localStream != null) {
      for (final MediaStreamTrack track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }
    return pc;
  }

  Future<void> _openMedia(CallKind kind) async {
    _localStream = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
      'audio': true,
      'video': kind == CallKind.video
          ? <String, dynamic>{
              'facingMode': _frontCamera ? 'user' : 'environment',
              'width': 640,
              'height': 480,
            }
          : false,
    });
    localRenderer.srcObject = _localStream;
    notifyListeners();
  }

  void _startDurationTimer() {
    _elapsedSeconds = 0;
    _durationTicker?.cancel();
    _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds++;
      notifyListeners();
    });
    _emit(CallPhase.connected);
  }

  // ── Controls ────────────────────────────────────────────────────────────

  void toggleMute() {
    _muted = !_muted;
    _localStream
        ?.getAudioTracks()
        .forEach((MediaStreamTrack t) => t.enabled = !_muted);
    notifyListeners();
  }

  void toggleCamera() {
    _cameraOff = !_cameraOff;
    _localStream
        ?.getVideoTracks()
        .forEach((MediaStreamTrack t) => t.enabled = !_cameraOff);
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final List<MediaStreamTrack> videoTracks =
        _localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (videoTracks.isEmpty) return;
    _frontCamera = !_frontCamera;
    await Helper.switchCamera(videoTracks.first);
    notifyListeners();
  }

  Future<void> hangUp() async {
    final CallSession? call = _activeCall;
    if (call == null) {
      await _cleanup();
      return;
    }
    try {
      await _db.call(call.id).set(
        <String, dynamic>{
          'status': CallStatus.ended.name,
          'endedAt': FieldValue.serverTimestamp(),
          'endedBy': call.callerId,
          'durationSeconds': _elapsedSeconds,
        },
        SetOptions(merge: true),
      );
    } on FirebaseException {
      // Best-effort — local cleanup still proceeds below.
    }
    await _cleanup();
  }

  Future<void> _markMissedAndClose(String callId) async {
    try {
      await _db.call(callId).set(
        <String, dynamic>{
          'status': CallStatus.missed.name,
          'endedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on FirebaseException {
      // Best-effort.
    }
    _error = 'No answer.';
    _emit(CallPhase.ended);
    await _cleanup();
  }

  Future<void> _cleanup() async {
    _ringTimeout?.cancel();
    _durationTicker?.cancel();
    await _callDocSub?.cancel();
    await _remoteCandidatesSub?.cancel();
    _callDocSub = null;
    _remoteCandidatesSub = null;

    await _pc?.close();
    _pc = null;

    _localStream?.getTracks().forEach((MediaStreamTrack t) => t.stop());
    await _localStream?.dispose();
    _localStream = null;

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    _muted = false;
    _cameraOff = false;
    _activeCall = null;
    _emit(CallPhase.idle);
  }

  /// Called by the UI when it navigates away from a finished call screen.
  void reset() {
    if (_phase == CallPhase.ended || _phase == CallPhase.failed) {
      _phase = CallPhase.idle;
      _error = null;
      notifyListeners();
    }
  }

  static String _describeError(Object e) {
    if (e.toString().contains('Permission')) {
      return 'Camera or microphone permission was denied.';
    }
    return 'The call could not be started. Check your connection and try again.';
  }

  @override
  void dispose() {
    stopListeningForIncomingCalls();
    _cleanup();
    if (_renderersReady) {
      localRenderer.dispose();
      remoteRenderer.dispose();
    }
    super.dispose();
  }
}
