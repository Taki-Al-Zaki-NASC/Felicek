import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/f_avatar.dart';
import '../../core/widgets/f_surface.dart';
import '../../data/models/call_session.dart';
import '../../data/models/chat.dart';
import '../../data/models/message.dart';
import '../../data/models/public_profile.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/call_service.dart';
import '../call/call_screen.dart';
import 'chat_controller.dart';
import 'widgets/message_bubble.dart';

/// One conversation.
///
/// Everything the design's chat screen showed is here — the gradient avatar,
/// the "Verified applicant" line, the ink/white bubble pair, the pill
/// composer — plus what a shipped messenger needs: receipts, day separators,
/// typing, reply, edit, delete, retry, mute and block.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatId,
    this.headerName,
    this.headerSubtitle,
  });

  final String chatId;
  final String? headerName;
  final String? headerSubtitle;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  ChatController? _controller;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final SessionController session = context.read<SessionController>();
    _controller = ChatController(
      repository: context.chatRepo,
      chatId: widget.chatId,
      myUid: session.uid ?? '',
      myName: session.user?.displayName ?? 'You',
    )..addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final ChatController c = _controller!;
    // Pull an edit into the field so the person can amend the text in place.
    if (c.editing != null && _composer.text != c.editing!.text) {
      _composer.text = c.editing!.text;
      _composer.selection =
          TextSelection.collapsed(offset: _composer.text.length);
      _composerFocus.requestFocus();
    }
  }

  void _onScroll() {
    // The list is reversed, so "further from zero" means further into history.
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      _controller?.loadOlder();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final ChatController c = _controller!;
    final String text = _composer.text;
    if (text.trim().isEmpty) return;
    setState(() => _sending = true);
    final String remaining = await c.send(text);
    if (!mounted) return;
    setState(() => _sending = false);
    _composer.text = remaining;
    if (remaining.isEmpty && _scroll.hasClients) {
      _scroll.animateTo(0, duration: FMotion.base, curve: FMotion.curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ChatController controller = _controller!;
    return ChangeNotifierProvider<ChatController>.value(
      value: controller,
      child: Consumer<ChatController>(
        builder: (BuildContext context, ChatController c, _) {
          final ChatParticipant? other = c.other;
          final String name =
              other?.displayName ?? widget.headerName ?? 'Conversation';

          return Scaffold(
            backgroundColor: FColors.canvas,
            resizeToAvoidBottomInset: true,
            body: Column(
              children: <Widget>[
                _ChatHeader(
                  name: name,
                  subtitle: _subtitleFor(c, other),
                  subtitleColor: c.otherIsTyping ? FColors.teal : FColors.teal,
                  verified: other?.verified ?? false,
                  seed: other?.uid,
                  muted: c.isMuted,
                  jobTitle: c.thread?.jobTitle,
                  onMute: c.toggleMute,
                  onBlock: () => _confirmBlock(context, c, name),
                  onArchive: () async {
                    await c.archive();
                    if (context.mounted) Navigator.of(context).maybePop();
                  },
                  onAudioCall: c.isBlocked
                      ? null
                      : () => _placeCall(context, c, name, CallKind.audio),
                  onVideoCall: c.isBlocked
                      ? null
                      : () => _placeCall(context, c, name, CallKind.video),
                ),
                Expanded(child: _MessageList(controller: c, scroll: _scroll)),
                if (c.error != null)
                  _InlineBanner(message: c.error!, onDismiss: c.clearError),
                _Composer(
                  controller: c,
                  textController: _composer,
                  focusNode: _composerFocus,
                  sending: _sending,
                  onSend: _send,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _subtitleFor(ChatController c, ChatParticipant? other) {
    if (c.isBlocked) return 'Blocked';
    if (c.otherIsTyping) return 'typing…';
    if (other == null) return widget.headerSubtitle ?? '';
    if (other.verified) {
      return other.role == 'freelancer'
          ? 'Verified applicant'
          : 'Verified client';
    }
    return other.title.isEmpty ? 'Felicek member' : other.title;
  }

  Future<void> _confirmBlock(
    BuildContext context,
    ChatController c,
    String name,
  ) async {
    if (c.blockedByMe) {
      await c.toggleBlock();
      return;
    }
    final bool ok = await AppFeedback.confirm(
      context,
      title: 'Block $name?',
      message:
          'Neither of you will be able to send messages in this conversation. '
          'You can unblock at any time.',
      confirmLabel: 'Block',
      destructive: true,
    );
    if (ok) await c.toggleBlock();
  }

  Future<void> _placeCall(
    BuildContext context,
    ChatController c,
    String name,
    CallKind kind,
  ) async {
    final SessionController session = context.read<SessionController>();
    final CallService callService = context.callService;
    if (callService.inCall) {
      AppFeedback.error(context, 'You are already on a call.');
      return;
    }

    // Push the call screen immediately so permission prompts and "Calling…"
    // render on it rather than freezing the chat behind a blank wait.
    final Future<void> pushed = Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CallScreen(otherName: name, otherUid: c.otherUid),
      ),
    );

    final String? callId = await callService.startCall(
      myUid: session.uid ?? '',
      myName: session.user?.displayName ?? 'You',
      otherUid: c.otherUid,
      otherName: name,
      kind: kind,
      chatId: c.chatId,
    );
    if (callId == null && context.mounted) {
      Navigator.of(context).maybePop();
      AppFeedback.error(
          context, callService.error ?? 'Could not start the call.');
    }
    await pushed;
  }
}

// ── Header ────────────────────────────────────────────────────────────────

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.name,
    required this.subtitle,
    required this.subtitleColor,
    required this.verified,
    required this.seed,
    required this.muted,
    required this.jobTitle,
    required this.onMute,
    required this.onBlock,
    required this.onArchive,
    required this.onAudioCall,
    required this.onVideoCall,
  });

  final String name;
  final String subtitle;
  final Color subtitleColor;
  final bool verified;
  final String? seed;
  final bool muted;
  final String? jobTitle;
  final VoidCallback onMute;
  final VoidCallback onBlock;
  final VoidCallback onArchive;
  final VoidCallback? onAudioCall;
  final VoidCallback? onVideoCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: FColors.canvas,
        border: Border(bottom: BorderSide(color: FColors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: <Widget>[
              FBackChevron(onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: FSpace.xl),
              FAvatar(size: 30, seed: seed, verified: verified),
              const SizedBox(width: FSpace.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: FType.titleSm,
                          ),
                        ),
                        if (muted) ...<Widget>[
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.notifications_off_outlined,
                            size: 12,
                            color: FColors.inkFaint,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: FType.captionSm.copyWith(
                        fontSize: 10.5,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onAudioCall,
                icon: const Icon(Icons.call_outlined, size: 19),
                color: FColors.inkMuted,
                disabledColor: FColors.inkFaint.withValues(alpha: 0.4),
                visualDensity: VisualDensity.compact,
                tooltip: 'Voice call',
              ),
              IconButton(
                onPressed: onVideoCall,
                icon: const Icon(Icons.videocam_outlined, size: 20),
                color: FColors.inkMuted,
                disabledColor: FColors.inkFaint.withValues(alpha: 0.4),
                visualDensity: VisualDensity.compact,
                tooltip: 'Video call',
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: FColors.inkMuted,
                ),
                color: FColors.surface,
                shape:
                    const RoundedRectangleBorder(borderRadius: FRadius.fieldR),
                onSelected: (String value) {
                  switch (value) {
                    case 'mute':
                      onMute();
                    case 'archive':
                      onArchive();
                    case 'block':
                      onBlock();
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  if (jobTitle != null)
                    PopupMenuItem<String>(
                      enabled: false,
                      height: 34,
                      child: Text(
                        jobTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FType.captionSm,
                      ),
                    ),
                  PopupMenuItem<String>(
                    value: 'mute',
                    height: 42,
                    child: Text(
                      muted ? 'Unmute conversation' : 'Mute conversation',
                      style: FType.bodyXs,
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'archive',
                    height: 42,
                    child: Text('Archive', style: FType.bodyXs),
                  ),
                  PopupMenuItem<String>(
                    value: 'block',
                    height: 42,
                    child: Text(
                      'Block & report',
                      style: FType.bodyXs.copyWith(color: FColors.danger),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Message list ──────────────────────────────────────────────────────────

class _MessageList extends StatelessWidget {
  const _MessageList({required this.controller, required this.scroll});

  final ChatController controller;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) return const FLoading();

    final List<Message> messages = controller.messages;
    if (messages.isEmpty) {
      return FEmptyState(
        icon: Icons.forum_outlined,
        title: 'Say hello',
        message: controller.thread?.jobTitle == null
            ? 'Start the conversation — messages are end-to-end private to the two of you.'
            : 'Ask about ${controller.thread!.jobTitle} to get things moving.',
      );
    }

    final bool typing = controller.otherIsTyping;
    // One extra row for the typing pill, one for the "load older" spinner.
    final int extraTop = typing ? 1 : 0;
    final int extraBottom = controller.reachedStart ? 1 : 1;

    return ListView.builder(
      controller: scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      itemCount: messages.length + extraTop + extraBottom,
      itemBuilder: (BuildContext context, int index) {
        if (typing && index == 0) {
          return TypingIndicator(
            name: controller.other?.displayName ?? 'They',
          );
        }
        final int i = index - extraTop;
        if (i >= messages.length) {
          return controller.reachedStart
              ? const _ThreadStart()
              : const FLoading(size: 16, padding: 16);
        }

        final Message message = messages[i];
        final Message? older = i + 1 < messages.length ? messages[i + 1] : null;
        final bool isMine = message.senderId == controller.myUid;
        final bool newBlock = older == null ||
            older.senderId != message.senderId ||
            message.orderedAt.difference(older.orderedAt) >
                const Duration(minutes: 5);
        final bool newDay =
            older == null || !_sameDay(older.orderedAt, message.orderedAt);

        final Widget bubble = MessageBubble(
          message: message,
          isMine: isMine,
          status: controller.statusOf(message),
          showTail: newBlock,
          onRetry: () => controller.retry(message),
          onDiscard: () => controller.discardFailed(message),
          onLongPress: () => _showMessageActions(context, controller, message),
          onOfferResponse: (bool accept) =>
              controller.respondToOffer(message, accept: accept),
        );

        if (!newDay) return bubble;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            bubble,
            MessageDayDivider(date: message.orderedAt)
          ],
        );
      },
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _showMessageActions(
    BuildContext context,
    ChatController controller,
    Message message,
  ) async {
    if (message.isDeleted) return;
    HapticFeedback.selectionClick();
    final bool canEdit = message.canEdit(controller.myUid);
    final bool canDelete = message.canDelete(controller.myUid);

    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _SheetAction(
              icon: Icons.reply_rounded,
              label: 'Reply',
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.startReply(message);
              },
            ),
            _SheetAction(
              icon: Icons.copy_rounded,
              label: 'Copy text',
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Clipboard.setData(ClipboardData(text: message.text));
                if (context.mounted) AppFeedback.toast(context, 'Copied');
              },
            ),
            if (canEdit)
              _SheetAction(
                icon: Icons.edit_outlined,
                label: 'Edit',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  controller.startEdit(message);
                },
              ),
            if (canDelete)
              _SheetAction(
                icon: Icons.delete_outline_rounded,
                label: 'Delete for everyone',
                danger: true,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final bool ok = await AppFeedback.confirm(
                    context,
                    title: 'Delete this message?',
                    message:
                        'It will be replaced with "This message was deleted" for both of you.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                  if (ok) await controller.deleteMessage(message);
                },
              ),
            const SizedBox(height: FSpace.md),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color color = danger ? FColors.danger : FColors.ink;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 19, color: color),
      title: Text(label, style: FType.bodyXs.copyWith(color: color)),
      dense: true,
    );
  }
}

class _ThreadStart extends StatelessWidget {
  const _ThreadStart();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FSpace.x5),
      child: Center(
        child: Text(
          'Start of the conversation',
          style:
              FType.captionSm.copyWith(fontSize: 10, color: FColors.inkFaint),
        ),
      ),
    );
  }
}

// ── Composer ──────────────────────────────────────────────────────────────

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.textController,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final ChatController controller;
  final TextEditingController textController;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    if (controller.isBlocked) {
      return _BlockedBar(
        blockedByMe: controller.blockedByMe,
        onUnblock: controller.toggleBlock,
      );
    }

    final Message? context0 = controller.editing ?? controller.replyingTo;

    return Container(
      decoration: const BoxDecoration(
        color: FColors.canvas,
        border: Border(top: BorderSide(color: FColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (context0 != null)
              _ComposerContext(
                isEdit: controller.editing != null,
                message: context0,
                onCancel: () {
                  controller.cancelComposerContext();
                  textController.clear();
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: TextField(
                        controller: textController,
                        focusNode: focusNode,
                        onChanged: controller.onComposerChanged,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 4000,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.newline,
                        cursorColor: FColors.teal,
                        style: FType.bodyXs,
                        decoration: InputDecoration(
                          isDense: true,
                          counterText: '',
                          hintText: 'Write a message...',
                          hintStyle:
                              FType.bodyXs.copyWith(color: FColors.inkFaint),
                          filled: true,
                          fillColor: FColors.surfaceField,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: _pill(FColors.border),
                          enabledBorder: _pill(FColors.border),
                          focusedBorder: _pill(FColors.teal),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: FSpace.md),
                  _SendButton(
                    busy: sending,
                    isEdit: controller.editing != null,
                    onTap: onSend,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static OutlineInputBorder _pill(Color color) => OutlineInputBorder(
        borderRadius: FRadius.roundR,
        borderSide: BorderSide(color: color),
      );
}

class _SendButton extends StatelessWidget {
  const _SendButton(
      {required this.busy, required this.isEdit, required this.onTap});

  final bool busy;
  final bool isEdit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FColors.inkStrong,
      borderRadius: FRadius.roundR,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: FRadius.roundR,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          alignment: Alignment.center,
          constraints: const BoxConstraints(minWidth: 60),
          child: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  isEdit ? 'Save' : 'Send',
                  style: FType.pill.copyWith(fontSize: 12, color: Colors.white),
                ),
        ),
      ),
    );
  }
}

class _ComposerContext extends StatelessWidget {
  const _ComposerContext({
    required this.isEdit,
    required this.message,
    required this.onCancel,
  });

  final bool isEdit;
  final Message message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 0),
      child: Row(
        children: <Widget>[
          Container(width: 2.5, height: 30, color: FColors.teal),
          const SizedBox(width: FSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  isEdit
                      ? 'Editing message'
                      : 'Replying to ${message.senderName}',
                  style: FType.pill
                      .copyWith(fontSize: 10, color: FColors.tealDeep),
                ),
                Text(
                  message.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FType.captionSm.copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded,
                size: 16, color: FColors.inkFaint),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _BlockedBar extends StatelessWidget {
  const _BlockedBar({required this.blockedByMe, required this.onUnblock});

  final bool blockedByMe;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: FColors.dangerTint,
        border: Border(top: BorderSide(color: FColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                blockedByMe
                    ? 'You blocked this conversation.'
                    : 'This conversation has been blocked.',
                textAlign: TextAlign.center,
                style: FType.supportSm.copyWith(color: FColors.danger),
              ),
              if (blockedByMe) ...<Widget>[
                const SizedBox(height: FSpace.md),
                InkWell(
                  onTap: onUnblock,
                  child: Text(
                    'Unblock',
                    style: FType.pill
                        .copyWith(fontSize: 12, color: FColors.danger),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineBanner extends StatelessWidget {
  const _InlineBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: FColors.amberTint,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline_rounded,
              size: 14, color: FColors.amber),
          const SizedBox(width: FSpace.md),
          Expanded(
            child: Text(
              message,
              style:
                  FType.captionSm.copyWith(fontSize: 10.5, color: FColors.ink),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 14),
            color: FColors.inkMuted,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// Opens (or creates) a conversation and pushes the thread.
Future<void> openChatWith(
  BuildContext context, {
  required String otherUid,
  String? jobId,
  String? jobTitle,
  String? headerName,
}) async {
  final SessionController session = context.read<SessionController>();
  final PublicProfile? me = session.publicProfile;
  if (me == null) return;

  // Resolve the repositories before the first await — `context` may be gone
  // by the time the profile lookup returns.
  final UserRepository users = context.userRepo;
  final ChatRepository chats = context.chatRepo;

  final PublicProfile? other = await users.fetchProfile(otherUid);
  if (other == null) {
    if (context.mounted) {
      AppFeedback.error(context, 'That account is no longer available.');
    }
    return;
  }
  final String chatId = await chats.openThread(
    me: me,
    other: other,
    jobId: jobId,
    jobTitle: jobTitle,
  );
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChatScreen(
        chatId: chatId,
        headerName: headerName ?? other.displayName,
        headerSubtitle: Fmt.relative(other.lastSeenAt),
      ),
    ),
  );
}
