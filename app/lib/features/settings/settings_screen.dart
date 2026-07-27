import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_config.dart';
import '../../app/services.dart';
import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/feedback.dart';
import '../../core/widgets/f_surface.dart';
import '../../data/models/app_user.dart';

/// Notification preferences, privacy links, app version, and manual
/// "Check for updates" — the settings destinations the design's Profile
/// screen links out to.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppUser? user =
        context.select<SessionController, AppUser?>((s) => s.user);

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: Column(
        children: <Widget>[
          const FTopBar(title: 'Settings'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              children: <Widget>[
                const FSectionLabel('Notifications'),
                const SizedBox(height: FSpace.lg),
                if (user != null) _NotificationToggles(user: user),
                const SizedBox(height: FSpace.x3),
                const FSectionLabel('Privacy & data'),
                const SizedBox(height: FSpace.lg),
                FCard(
                  radius: FRadius.card,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      _LinkRow(
                        label: 'Privacy policy',
                        onTap: () => launchUrl(Uri.parse(AppConfig.privacyUrl)),
                      ),
                      _LinkRow(
                        label: 'Terms of service',
                        onTap: () => launchUrl(Uri.parse(AppConfig.termsUrl)),
                      ),
                      _LinkRow(
                        label: 'Contact support',
                        showDivider: false,
                        onTap: () => launchUrl(
                            Uri.parse('mailto:${AppConfig.supportEmail}')),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FSpace.x3),
                const FSectionLabel('About'),
                const SizedBox(height: FSpace.lg),
                const _UpdateRow(),
                const SizedBox(height: FSpace.lg),
                const _VersionLabel(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationToggles extends StatefulWidget {
  const _NotificationToggles({required this.user});

  final AppUser user;

  @override
  State<_NotificationToggles> createState() => _NotificationTogglesState();
}

class _NotificationTogglesState extends State<_NotificationToggles> {
  late NotificationPrefs _prefs = widget.user.notificationPrefs;
  bool _saving = false;

  Future<void> _set(NotificationPrefs next) async {
    setState(() => _prefs = next);
    if (_saving) return;
    _saving = true;
    try {
      await context.userRepo.saveNotificationPrefs(widget.user.uid, next);
    } on Object {
      if (mounted) AppFeedback.error(context, 'Could not save that.');
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FCard(
      radius: FRadius.card,
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          _ToggleRow(
            label: 'New messages',
            value: _prefs.newMessages,
            onChanged: (bool v) => _set(_prefs.copyWith(newMessages: v)),
          ),
          _ToggleRow(
            label: 'Proposal updates',
            value: _prefs.proposalUpdates,
            onChanged: (bool v) => _set(_prefs.copyWith(proposalUpdates: v)),
          ),
          _ToggleRow(
            label: 'Job matches',
            value: _prefs.jobMatches,
            onChanged: (bool v) => _set(_prefs.copyWith(jobMatches: v)),
          ),
          _ToggleRow(
            label: 'Payouts',
            value: _prefs.payouts,
            onChanged: (bool v) => _set(_prefs.copyWith(payouts: v)),
          ),
          _ToggleRow(
            label: 'Calls',
            value: _prefs.calls,
            onChanged: (bool v) => _set(_prefs.copyWith(calls: v)),
          ),
          _ToggleRow(
            label: 'Product news',
            value: _prefs.productNews,
            showDivider: false,
            onChanged: (bool v) => _set(_prefs.copyWith(productNews: v)),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.showDivider = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: FColors.borderFaint))
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: FType.bodyXs.copyWith(fontSize: 13)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow(
      {required this.label, required this.onTap, this.showDivider = true});

  final String label;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          border: showDivider
              ? const Border(bottom: BorderSide(color: FColors.borderFaint))
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label,
                style: FType.titleSm.copyWith(fontWeight: FontWeight.w400)),
            const Icon(Icons.open_in_new_rounded,
                size: 14, color: FColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow();

  @override
  Widget build(BuildContext context) {
    return FCard(
      radius: FRadius.card,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: () async {
        final bool found = await context.updateService.check(force: true);
        if (context.mounted) {
          AppFeedback.toast(
            context,
            found ? 'An update is available.' : "You're on the latest version.",
          );
        }
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text('Check for updates',
              style: FType.titleSm.copyWith(fontWeight: FontWeight.w400)),
          const Icon(Icons.refresh_rounded, size: 16, color: FColors.inkFaint),
        ],
      ),
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (BuildContext context, AsyncSnapshot<PackageInfo> snap) {
        final PackageInfo? info = snap.data;
        return Center(
          child: Text(
            info == null
                ? 'Felicek'
                : 'Felicek ${info.version} (${info.buildNumber})',
            style: FType.caption,
          ),
        );
      },
    );
  }
}
