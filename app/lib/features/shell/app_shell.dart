import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../data/models/call_session.dart';
import '../../data/services/call_service.dart';
import '../call/incoming_call_screen.dart';
import '../chat/inbox_screen.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../proposals/proposals_screen.dart';
import '../wallet/wallet_screen.dart';
import 'update_banner.dart';

enum ShellTab { home, proposals, payment, profile }

/// The four-tab shell: Home / Proposals / Payment / Profile, with an inbox
/// entry point and the mandatory in-app-update banner living above it.
///
/// This also owns the single incoming-call listener for the whole app —
/// wherever you are when someone calls, the incoming-call screen appears.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  ShellTab _tab = ShellTab.home;
  bool _callListenerBound = false;

  @override
  Widget build(BuildContext context) {
    final SessionController session = context.watch<SessionController>();
    final String? uid = session.uid;

    if (uid != null && !_callListenerBound) {
      _callListenerBound = true;
      final CallService callService = context.callService;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        callService.listenForIncomingCalls(uid, (CallSession call) {
          if (!mounted) return;
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  IncomingCallScreen(call: call, service: callService),
              fullscreenDialog: true,
            ),
          );
        });
      });
    }

    final List<Widget> pages = <Widget>[
      const HomeScreen(),
      const ProposalsScreen(),
      const WalletScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            const UpdateBanner(),
            Expanded(
              child: IndexedStack(
                index: _tab.index,
                children: pages,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomNav(
        current: _tab,
        onChanged: (ShellTab t) => setState(() => _tab = t),
      ),
      // Messages are reachable from every tab, with a live unread badge. The
      // design only opened chat from an applicant card, which left no way
      // back to a conversation once you navigated away.
      floatingActionButton: uid == null
          ? null
          : StreamBuilder<int>(
              stream: context.chatRepo.watchTotalUnread(uid),
              builder: (BuildContext context, AsyncSnapshot<int> snap) {
                // Same deliberate degradation as the notifications badge: a
                // count on a FAB has no room to explain itself, and the inbox
                // it opens surfaces the error.
                final int unread = snap.data ?? 0;
                return Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    FloatingActionButton(
                      backgroundColor: FColors.inkStrong,
                      elevation: 2,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const InboxScreen(),
                        ),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    if (unread > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: FColors.teal,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: FColors.canvas, width: 2),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            textAlign: TextAlign.center,
                            style: FType.pillSm.copyWith(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.current, required this.onChanged});

  final ShellTab current;
  final ValueChanged<ShellTab> onChanged;

  static const List<(ShellTab, IconData, IconData, String)> _items =
      <(ShellTab, IconData, IconData, String)>[
    (ShellTab.home, Icons.home_outlined, Icons.home_rounded, 'Home'),
    (
      ShellTab.proposals,
      Icons.description_outlined,
      Icons.description_rounded,
      'Proposals'
    ),
    (
      ShellTab.payment,
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet_rounded,
      'Payment'
    ),
    (
      ShellTab.profile,
      Icons.person_outline_rounded,
      Icons.person_rounded,
      'Profile'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: FColors.surface,
        border: Border(top: BorderSide(color: FColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: <Widget>[
              for (final (
                    ShellTab tab,
                    IconData outline,
                    IconData filled,
                    String label
                  ) in _items)
                Expanded(
                  child: _NavButton(
                    active: current == tab,
                    icon: current == tab ? filled : outline,
                    label: label,
                    onTap: () => onChanged(tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? FColors.inkStrong : FColors.inkDisabled;
    return InkResponse(
      onTap: onTap,
      radius: 40,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: FType.pillSm.copyWith(
              fontSize: 10,
              color: color,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
