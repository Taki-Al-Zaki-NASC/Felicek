import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/chat.dart';
import '../../data/models/message.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/user_repository.dart';

/// All the state one open conversation needs.
///
/// The controller owns the two live subscriptions (thread + messages), the
/// composer, the typing throttle, pagination and the read watermark. Widgets
/// stay dumb: they render `messages` and call `send()`.
class ChatController extends ChangeNotifier {
  ChatController({
    required ChatRepository repository,
    required UserRepository userRepository,
    required this.chatId,
    required this.myUid,
    required this.myName,
  })  : _repo = repository,
        _users = userRepository {
    _subscribe();
  }

  final ChatRepository _repo;
  final UserRepository _users;
  final String chatId;
  final String myUid;
  final String myName;

  StreamSubscription<ChatThread?>? _threadSub;
  StreamSubscription<List<Message>>? _messagesSub;
  Timer? _typingStopTimer;
  Timer? _typingTickTimer;

  ChatThread? _thread;
  List<Message> _messages = const <Message>[];
  int _limit = ChatRepository.pageSize;
  bool _loadingOlder = false;
  bool _reachedStart = false;
  bool _loading = true;
  String? _error;

  /// Locally-known send failures, so a rejected write still shows a bubble
  /// with a Retry affordance instead of silently vanishing.
  final Map<String, Message> _failed = <String, Message>{};

  /// The message being edited, if any.
  Message? _editing;

  /// The message being replied to, if any.
  Message? _replyingTo;

  DateTime? _lastTypingWrite;
  DateTime? _lastReadWatermark;

  // ── Exposed state ───────────────────────────────────────────────────────

  ChatThread? get thread => _thread;
  bool get loading => _loading;
  String? get error => _error;
  bool get loadingOlder => _loadingOlder;
  bool get reachedStart => _reachedStart;
  Message? get editing => _editing;
  Message? get replyingTo => _replyingTo;

  ChatParticipant? get other => _thread?.otherFor(myUid);
  String get otherUid => _thread?.otherIdFor(myUid) ?? '';

  bool get otherIsTyping => _thread?.otherIsTyping(myUid) ?? false;

  bool get isBlocked => _thread?.isBlocked ?? false;
  bool get blockedByMe => _thread?.blockedByMe(myUid) ?? false;
  bool get isMuted => _thread?.isMutedBy(myUid) ?? false;

  /// Newest first — the list view renders reversed.
  List<Message> get messages => _messages;

  DateTime? get otherDeliveredUpTo => _thread?.deliveredUpTo[otherUid];
  DateTime? get otherReadUpTo => _thread?.readUpTo[otherUid];

  MessageStatus statusOf(Message m) => m.statusFor(
        myUid: myUid,
        otherDeliveredUpTo: otherDeliveredUpTo,
        otherReadUpTo: otherReadUpTo,
      );

  // ── Wiring ──────────────────────────────────────────────────────────────

  void _subscribe() {
    _threadSub = _repo.watchThread(chatId).listen(
      (ChatThread? t) {
        _thread = t;
        notifyListeners();
        _maybeMarkRead();
      },
      onError: _onStreamError,
    );
    _listenMessages();
  }

  void _listenMessages() {
    _messagesSub?.cancel();
    _messagesSub = _repo.watchMessages(chatId, limit: _limit).listen(
      (List<Message> items) {
        _loading = false;
        _loadingOlder = false;
        _error = null;
        // A page that comes back short means there is nothing older left.
        _reachedStart = items.length < _limit;
        _messages = _merge(items);
        notifyListeners();
        _maybeMarkRead();
      },
      onError: _onStreamError,
    );
  }

  /// Splices locally-failed sends back into the server list, ordered with
  /// everything else.
  List<Message> _merge(List<Message> serverMessages) {
    if (_failed.isEmpty) return serverMessages;
    final Set<String> serverIds =
        serverMessages.map((Message m) => m.id).toSet();
    // A failure that later succeeded (retry, or the offline queue drained)
    // stops being a failure.
    _failed.removeWhere(
      (String id, Message m) => serverIds.contains(id) && !_repo.isFailed(id),
    );
    final List<Message> combined = <Message>[
      ...serverMessages.where((Message m) => !_failed.containsKey(m.id)),
      ..._failed.values,
    ]..sort((Message a, Message b) => b.orderedAt.compareTo(a.orderedAt));
    return combined;
  }

  void _onStreamError(Object e) {
    _loading = false;
    _loadingOlder = false;
    _error = 'Messages could not load. Check your connection.';
    notifyListeners();
  }

  // ── Pagination ──────────────────────────────────────────────────────────

  /// Grows the live window rather than freezing older pages, so an edit to a
  /// message from last week still updates in place.
  void loadOlder() {
    if (_loadingOlder || _reachedStart || _loading) return;
    _loadingOlder = true;
    _limit += ChatRepository.pageSize;
    notifyListeners();
    _listenMessages();
  }

  // ── Receipts ────────────────────────────────────────────────────────────

  /// Marks the thread read up to the newest message the other side sent.
  /// Costs one write, no matter how far behind you were.
  void _maybeMarkRead() {
    if (_thread == null || _messages.isEmpty) return;
    if (_thread!.unreadFor(myUid) == 0 && _lastReadWatermark != null) return;

    DateTime? newest;
    for (final Message m in _messages) {
      if (m.senderId == myUid) continue;
      final DateTime? at = m.sentAt;
      if (at == null) continue;
      if (newest == null || at.isAfter(newest)) newest = at;
    }
    if (newest == null) return;
    if (_lastReadWatermark != null && !newest.isAfter(_lastReadWatermark!)) {
      return;
    }

    _lastReadWatermark = newest;
    _repo.markRead(chatId: chatId, uid: myUid, upTo: newest);
  }

  // ── Composer ────────────────────────────────────────────────────────────

  /// Called on every keystroke. Writes a typing flag at most once every few
  /// seconds and always schedules the clear, so the indicator cannot stick.
  void onComposerChanged(String value) {
    if (value.trim().isEmpty) {
      _stopTyping();
      return;
    }
    final DateTime now = DateTime.now();
    if (_lastTypingWrite == null ||
        now.difference(_lastTypingWrite!) > ChatRepository.typingThrottle) {
      _lastTypingWrite = now;
      _repo.setTyping(chatId: chatId, uid: myUid, typing: true);
    }
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 4), _stopTyping);

    // Re-evaluate the other side's expiring typing flag once a second so the
    // indicator disappears on time even without a new snapshot.
    _typingTickTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (_thread != null) notifyListeners();
      },
    );
  }

  void _stopTyping() {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;
    if (_lastTypingWrite == null) return;
    _lastTypingWrite = null;
    _repo.setTyping(chatId: chatId, uid: myUid, typing: false);
  }

  void startReply(Message message) {
    _replyingTo = message;
    _editing = null;
    notifyListeners();
  }

  void startEdit(Message message) {
    _editing = message;
    _replyingTo = null;
    notifyListeners();
  }

  void cancelComposerContext() {
    _editing = null;
    _replyingTo = null;
    notifyListeners();
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  /// Sends (or applies an edit). Returns the text that should stay in the
  /// field — empty on success — so the UI never loses a draft on failure.
  Future<String> send(String rawText) async {
    final String text = rawText.trim();
    if (text.isEmpty || isBlocked) return rawText;
    _stopTyping();

    final Message? edit = _editing;
    if (edit != null) {
      _editing = null;
      notifyListeners();
      try {
        await _repo.editMessage(
          chatId: chatId,
          messageId: edit.id,
          text: text,
          isLastMessage: _messages.isNotEmpty && _messages.first.id == edit.id,
        );
      } on Object {
        _error = 'That edit did not save. Try again.';
        notifyListeners();
        return rawText;
      }
      return '';
    }

    final MessageQuote? quote = _replyingTo == null
        ? null
        : MessageQuote(
            messageId: _replyingTo!.id,
            senderId: _replyingTo!.senderId,
            senderName: _replyingTo!.senderName,
            preview: _replyingTo!.preview.length > 90
                ? '${_replyingTo!.preview.substring(0, 89)}…'
                : _replyingTo!.preview,
          );
    _replyingTo = null;

    final ({String messageId, Future<void> committed}) result = _repo.sendText(
      chatId: chatId,
      senderId: myUid,
      senderName: myName,
      recipientId: otherUid,
      text: text,
      quote: quote,
    );

    // Drop a notification into the recipient's feed. Fire-and-forget: a
    // missed notification must never fail the message it describes.
    unawaited(
      _repo.notifyNewMessage(
        recipientId: otherUid,
        actorId: myUid,
        actorName: myName,
        chatId: chatId,
        preview: text.length > 120 ? '${text.substring(0, 119)}…' : text,
      ),
    );

    // The bubble is already on screen via the offline cache; only surface the
    // failure path.
    unawaited(
      result.committed.catchError((Object _) {
        _failed[result.messageId] = Message(
          id: result.messageId,
          senderId: myUid,
          senderName: myName,
          text: text,
          clientSentAt: DateTime.now(),
          localFailure: true,
        );
        _messages = _merge(_messages);
        notifyListeners();
      }),
    );

    notifyListeners();
    return '';
  }

  Future<void> sendOffer(
      {required int amountCents, required String milestone}) async {
    if (isBlocked) return;
    final ({String messageId, Future<void> committed}) result = _repo.sendOffer(
      chatId: chatId,
      senderId: myUid,
      senderName: myName,
      recipientId: otherUid,
      amountCents: amountCents,
      milestone: milestone,
    );
    unawaited(
      result.committed.catchError((Object _) {
        _error = 'That offer did not send. Try again.';
        notifyListeners();
      }),
    );
  }

  Future<void> retry(Message message) async {
    _failed.remove(message.id);
    notifyListeners();
    try {
      await _repo.retry(
        chatId: chatId,
        recipientId: otherUid,
        message: message.copyWith(localFailure: false),
      );
    } on Object {
      _failed[message.id] = message.copyWith(localFailure: true);
      _messages = _merge(_messages);
      notifyListeners();
    }
  }

  void discardFailed(Message message) {
    _failed.remove(message.id);
    _repo.clearFailure(message.id);
    _messages = _merge(_messages);
    notifyListeners();
  }

  Future<void> deleteMessage(Message message) => _repo.deleteMessage(
        chatId: chatId,
        messageId: message.id,
        isLastMessage: _messages.isNotEmpty && _messages.first.id == message.id,
      );

  Future<void> respondToOffer(Message message, {required bool accept}) => _repo
      .respondToOffer(chatId: chatId, messageId: message.id, accept: accept);

  Future<void> toggleMute() =>
      _repo.setMuted(chatId: chatId, uid: myUid, muted: !isMuted);

  /// Blocking is recorded on the thread (so both composers lock instantly)
  /// *and* on my account, so it survives the conversation and shows up under
  /// Account & security.
  Future<void> toggleBlock() async {
    final bool blocking = !blockedByMe;
    final String other = otherUid;
    await _repo.setBlocked(chatId: chatId, uid: myUid, blocked: blocking);
    if (other.isEmpty) return;
    if (blocking) {
      await _users.blockUser(myUid, other);
    } else {
      await _users.unblockUser(myUid, other);
    }
  }

  Future<void> archive() =>
      _repo.setArchived(chatId: chatId, uid: myUid, archived: true);

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTyping();
    _typingTickTimer?.cancel();
    _typingStopTimer?.cancel();
    _threadSub?.cancel();
    _messagesSub?.cancel();
    super.dispose();
  }
}
