import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/f_avatar.dart';
import '../../core/widgets/f_pill.dart';
import '../../core/widgets/f_surface.dart';
import '../../data/models/chat.dart';
import '../../data/models/message.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/services/firestore_refs.dart';
import 'chat_screen.dart';

/// The conversation list.
///
/// The design only ever opened a thread straight from an applicant card, so
/// this screen is new — built from the same tokens as everything else. It also
/// owns delivery receipts: while the inbox is listening, an arriving message
/// gets acknowledged, which is what turns the sender's single tick into two.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final Set<String> _acknowledged = <String>{};
  String _query = '';
  bool _showArchived = false;

  void _acknowledgeDeliveries(List<ChatThread> chats, String uid) {
    for (final ChatThread chat in chats) {
      final DateTime? at = chat.lastMessageAt;
      if (at == null) continue;
      if (chat.lastMessageSenderId == null || chat.lastMessageSenderId == uid) {
        continue;
      }
      final DateTime? acked = chat.deliveredUpTo[uid];
      if (acked != null && !acked.isBefore(at)) continue;
      // Guard against re-writing the same watermark while the snapshot
      // round-trips.
      final String key = '${chat.id}@${at.millisecondsSinceEpoch}';
      if (!_acknowledged.add(key)) continue;
      unawaited(
        context.chatRepo.markDelivered(chatId: chat.id, uid: uid, upTo: at),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String uid = context.select<SessionController, String?>(
          (SessionController s) => s.uid,
        ) ??
        '';
    final ChatRepository repo = context.chatRepo;

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: Column(
        children: <Widget>[
          _InboxHeader(
            onQueryChanged: (String q) => setState(() => _query = q),
            showArchived: _showArchived,
            onToggleArchived: () =>
                setState(() => _showArchived = !_showArchived),
          ),
          Expanded(
            child: StreamBuilder<List<ChatThread>>(
              stream: repo.watchInbox(uid),
              builder: (
                BuildContext context,
                AsyncSnapshot<List<ChatThread>> snapshot,
              ) {
                if (snapshot.hasError) {
                  return FErrorState(
                    message: describeFirestoreError(snapshot.error!),
                  );
                }
                if (!snapshot.hasData) return const FLoading();

                final List<ChatThread> all = snapshot.data!;
                _acknowledgeDeliveries(all, uid);

                final String q = _query.trim().toLowerCase();
                final List<ChatThread> chats = all.where((ChatThread c) {
                  if (c.isArchivedBy(uid) != _showArchived) return false;
                  if (q.isEmpty) return true;
                  final ChatParticipant other = c.otherFor(uid);
                  return other.displayName.toLowerCase().contains(q) ||
                      c.lastMessagePreview.toLowerCase().contains(q) ||
                      (c.jobTitle ?? '').toLowerCase().contains(q);
                }).toList(growable: false);

                if (chats.isEmpty) {
                  return FEmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: _showArchived
                        ? 'Nothing archived'
                        : q.isEmpty
                            ? 'No conversations yet'
                            : 'No matches',
                    message: _showArchived
                        ? 'Archived conversations will show up here.'
                        : q.isEmpty
                            ? 'Message an applicant from a job, or reply to a client, '
                                'and the thread will appear here.'
                            : 'Try a different name or keyword.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  itemCount: chats.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: FSpace.lg),
                  itemBuilder: (BuildContext context, int index) =>
                      _ChatRow(chat: chats[index], uid: uid),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxHeader extends StatelessWidget {
  const _InboxHeader({
    required this.onQueryChanged,
    required this.showArchived,
    required this.onToggleArchived,
  });

  final ValueChanged<String> onQueryChanged;
  final bool showArchived;
  final VoidCallback onToggleArchived;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FColors.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    showArchived ? 'Archived' : 'Messages',
                    style: FType.displayMd,
                  ),
                  InkWell(
                    onTap: onToggleArchived,
                    borderRadius: FRadius.chipR,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            showArchived
                                ? Icons.inbox_rounded
                                : Icons.archive_outlined,
                            size: 14,
                            color: FColors.inkMuted,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            showArchived ? 'Inbox' : 'Archived',
                            style: FType.pill.copyWith(
                              fontSize: 11,
                              color: FColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FSpace.xl),
              Container(
                decoration: const BoxDecoration(
                  color: FColors.neutralTint,
                  borderRadius: FRadius.buttonR,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.search_rounded,
                      size: 15,
                      color: FColors.inkFaint,
                    ),
                    const SizedBox(width: FSpace.md),
                    Expanded(
                      child: TextField(
                        onChanged: onQueryChanged,
                        cursorColor: FColors.teal,
                        style: FType.bodyXs,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 11),
                          hintText: 'Search conversations',
                          hintStyle:
                              FType.bodyXs.copyWith(color: FColors.inkFaint),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat, required this.uid});

  final ChatThread chat;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final ChatParticipant other = chat.otherFor(uid);
    final int unread = chat.unreadFor(uid);
    final bool mine = chat.lastMessageSenderId == uid;
    final bool typing = chat.otherIsTyping(uid);

    return FCard(
      radius: FRadius.card,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            chatId: chat.id,
            headerName: other.displayName,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FAvatar(
            size: 38,
            seed: other.uid,
            initials: FAvatar.initialsFor(other.displayName),
            verified: other.verified,
          ),
          const SizedBox(width: FSpace.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        other.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FType.titleXs.copyWith(
                          fontWeight:
                              unread > 0 ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: FSpace.md),
                    Text(
                      Fmt.relativeShort(chat.lastMessageAt),
                      style: FType.captionSm.copyWith(
                        fontSize: 9.5,
                        color: unread > 0 ? FColors.teal : FColors.inkFaint,
                      ),
                    ),
                  ],
                ),
                if (chat.jobTitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    chat.jobTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FType.captionSm.copyWith(
                      fontSize: 10,
                      color: FColors.tealDeep,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    if (mine && !typing) ...<Widget>[
                      const Icon(
                        Icons.done_all_rounded,
                        size: 12,
                        color: FColors.inkFaint,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        typing
                            ? 'typing…'
                            : chat.lastMessagePreview.isEmpty
                                ? 'No messages yet'
                                : chat.lastMessagePreview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FType.supportSm.copyWith(
                          fontSize: 11.5,
                          fontStyle:
                              typing ? FontStyle.italic : FontStyle.normal,
                          color: typing
                              ? FColors.teal
                              : unread > 0
                                  ? FColors.ink
                                  : FColors.inkMuted,
                        ),
                      ),
                    ),
                    if (chat.isMutedBy(uid)) ...<Widget>[
                      const SizedBox(width: FSpace.sm),
                      const Icon(
                        Icons.notifications_off_outlined,
                        size: 12,
                        color: FColors.inkFaint,
                      ),
                    ],
                    if (unread > 0) ...<Widget>[
                      const SizedBox(width: FSpace.md),
                      Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: const BoxDecoration(
                          color: FColors.teal,
                          borderRadius: BorderRadius.all(Radius.circular(9)),
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          textAlign: TextAlign.center,
                          style: FType.pillSm.copyWith(
                            color: Colors.white,
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (chat.lastMessageType == MessageType.offer) ...<Widget>[
                  const SizedBox(height: FSpace.sm),
                  FPill.violet('Milestone offer', fontSize: 9.5),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
