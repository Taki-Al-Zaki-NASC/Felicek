import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/f_surface.dart';
import '../../data/models/app_notification.dart';
import '../chat/chat_screen.dart';
import '../job/job_detail_screen.dart';

/// The in-app notification feed.
///
/// Every alert in the product is a Firestore document written by whichever
/// client caused the event — a message, a proposal, a hire, a payout — with
/// security rules pinning the exact shape one account may write into
/// another's feed. That is how the app delivers notifications with no Cloud
/// Functions, and therefore no paid plan.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Housekeeping: this is the only collection that grows purely from
    // activity, and the free tier has a 1 GiB ceiling. Trimming here costs
    // nothing extra — the person is already looking at the feed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final String? uid = context.read<SessionController>().uid;
      if (uid != null) context.notificationRepo.pruneOlderThan(uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final String uid =
        context.select<SessionController, String?>((s) => s.uid) ?? '';

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: Column(
        children: <Widget>[
          FTopBar(
            title: 'Notifications',
            actions: <Widget>[
              TextButton(
                onPressed: () => context.notificationRepo.markAllRead(uid),
                child: Text(
                  'Mark all read',
                  style: FType.pill
                      .copyWith(fontSize: 11, color: FColors.tealDeep),
                ),
              ),
            ],
          ),
          Expanded(
            child: StreamBuilder<List<AppNotification>>(
              stream: context.notificationRepo.watch(uid),
              builder: (
                BuildContext context,
                AsyncSnapshot<List<AppNotification>> snap,
              ) {
                if (snap.hasError) {
                  return const FErrorState(
                    message: 'Notifications could not load.',
                  );
                }
                if (!snap.hasData) return const FLoading();
                final List<AppNotification> items = snap.data!;
                if (items.isEmpty) {
                  return const FEmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'Nothing yet',
                    message:
                        'Messages, proposals, hires and payouts will show up here.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: FSpace.lg),
                  itemBuilder: (BuildContext context, int i) =>
                      _NotificationRow(uid: uid, item: items[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.uid, required this.item});

  final String uid;
  final AppNotification item;

  ({IconData icon, Color color, Color background}) get _visual =>
      switch (item.kind) {
        NotificationKind.message => (
            icon: Icons.chat_bubble_outline_rounded,
            color: FColors.teal,
            background: FColors.tealTint,
          ),
        NotificationKind.proposal => (
            icon: Icons.description_outlined,
            color: FColors.blue,
            background: FColors.blueTint,
          ),
        NotificationKind.proposalAccepted => (
            icon: Icons.check_circle_outline_rounded,
            color: FColors.teal,
            background: FColors.tealTint,
          ),
        NotificationKind.proposalDeclined => (
            icon: Icons.cancel_outlined,
            color: FColors.danger,
            background: FColors.dangerTint,
          ),
        NotificationKind.jobMatch => (
            icon: Icons.work_outline_rounded,
            color: FColors.violet,
            background: FColors.violetTint,
          ),
        NotificationKind.payout => (
            icon: Icons.account_balance_wallet_outlined,
            color: FColors.teal,
            background: FColors.tealTint,
          ),
        NotificationKind.verification => (
            icon: Icons.verified_outlined,
            color: FColors.amber,
            background: FColors.amberTint,
          ),
        NotificationKind.system => (
            icon: Icons.info_outline_rounded,
            color: FColors.inkMuted,
            background: FColors.neutralTint,
          ),
      };

  Future<void> _open(BuildContext context) async {
    if (!item.read) {
      await context.notificationRepo.markRead(uid, item.id);
    }
    if (!context.mounted) return;

    if (item.chatId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ChatScreen(chatId: item.chatId!, headerName: item.actorName),
        ),
      );
    } else if (item.jobId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
            builder: (_) => JobDetailScreen(jobId: item.jobId!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ({IconData icon, Color color, Color background}) v = _visual;

    return Dismissible(
      key: ValueKey<String>(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        decoration: const BoxDecoration(
          color: FColors.dangerTint,
          borderRadius: FRadius.cardR,
        ),
        child: const Icon(Icons.delete_outline_rounded,
            size: 18, color: FColors.danger),
      ),
      onDismissed: (_) => context.notificationRepo.delete(uid, item.id),
      child: FCard(
        radius: FRadius.card,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        background: item.read ? FColors.surface : FColors.tealTint,
        onTap: () => _open(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration:
                  BoxDecoration(color: v.background, shape: BoxShape.circle),
              child: Icon(v.icon, size: 16, color: v.color),
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
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FType.titleXs.copyWith(
                            fontWeight:
                                item.read ? FontWeight.w600 : FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: FSpace.md),
                      Text(
                        Fmt.relativeShort(item.createdAt),
                        style: FType.captionSm.copyWith(fontSize: 9.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FType.supportSm.copyWith(fontSize: 11.5),
                  ),
                ],
              ),
            ),
            if (!item.read) ...<Widget>[
              const SizedBox(width: FSpace.md),
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 5),
                decoration: const BoxDecoration(
                  color: FColors.teal,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A bell with an unread count, for the home header.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final String uid =
        context.select<SessionController, String?>((s) => s.uid) ?? '';

    return StreamBuilder<int>(
      stream: context.notificationRepo.watchUnreadCount(uid),
      builder: (BuildContext context, AsyncSnapshot<int> snap) {
        final int count = snap.data ?? 0;
        return InkResponse(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (_) => const NotificationsScreen()),
          ),
          radius: 22,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              const SizedBox(
                width: 30,
                height: 30,
                child: Icon(Icons.notifications_none_rounded,
                    size: 20, color: FColors.inkMuted),
              ),
              if (count > 0)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 15),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: FColors.teal,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: FColors.surface, width: 1.5),
                    ),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      textAlign: TextAlign.center,
                      style: FType.pillSm
                          .copyWith(fontSize: 8.5, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
