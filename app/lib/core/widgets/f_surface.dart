import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// White card: `background:#fff; border:1px solid rgba(27,36,48,0.08)`.
class FCard extends StatelessWidget {
  const FCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(15),
    this.radius = FRadius.cardLg,
    this.onTap,
    this.background = FColors.surface,
    this.border = FColors.border,
    this.margin,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;
  final Color background;
  final Color? border;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final BorderRadius br = BorderRadius.circular(radius);
    final Widget body = Container(padding: padding, child: child);

    return Container(
      margin: margin,
      child: Material(
        color: background,
        borderRadius: br,
        child: onTap == null
            ? Container(
                decoration: BoxDecoration(
                  borderRadius: br,
                  border: border == null ? null : Border.all(color: border!),
                ),
                child: body,
              )
            : InkWell(
                onTap: onTap,
                borderRadius: br,
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: br,
                    border: border == null ? null : Border.all(color: border!),
                  ),
                  child: body,
                ),
              ),
      ),
    );
  }
}

/// Uppercase section header: `11px / 0.6px tracking / #5b6472`.
class FSectionLabel extends StatelessWidget {
  const FSectionLabel(this.label, {super.key, this.trailing, this.color});

  final String label;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Widget text = Text(
      label.toUpperCase(),
      style: FType.sectionLabel.copyWith(color: color ?? FColors.inkMuted),
    );
    if (trailing == null) return text;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[text, trailing!],
    );
  }
}

/// The three-up stat tile from the dashboard and profile.
class FStatTile extends StatelessWidget {
  const FStatTile({
    super.key,
    required this.value,
    required this.label,
    this.valueColor = FColors.ink,
    this.fontSize = 16,
  });

  final String value;
  final String label;
  final Color valueColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FCard(
        radius: FRadius.button,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FType.statValue
                  .copyWith(color: valueColor, fontSize: fontSize),
            ),
            const SizedBox(height: FSpace.xxs),
            Text(label, style: FType.captionSm, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// The back-chevron + title header used on every pushed screen.
class FTopBar extends StatelessWidget implements PreferredSizeWidget {
  const FTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.leading,
    this.actions = const <Widget>[],
    this.subtitle,
    this.background = FColors.canvas,
    this.showDivider = true,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? subtitle;
  final Color background;
  final bool showDivider;

  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? 49 : 68);

  @override
  Widget build(BuildContext context) {
    final bool canBack = onBack != null || Navigator.of(context).canPop();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: background,
        border: showDivider
            ? const Border(bottom: BorderSide(color: FColors.border))
            : null,
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            if (leading != null)
              leading!
            else if (canBack)
              FBackChevron(
                  onTap: onBack ?? () => Navigator.of(context).maybePop()),
            if (leading != null || canBack) const SizedBox(width: FSpace.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(title,
                      style: FType.titleSm, overflow: TextOverflow.ellipsis),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 1),
                    subtitle!,
                  ],
                ],
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// The 10x10 rotated-square chevron the design draws with CSS borders.
class FBackChevron extends StatelessWidget {
  const FBackChevron({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: Icon(Icons.arrow_back_ios_new_rounded,
              size: 15, color: FColors.ink),
        ),
      ),
    );
  }
}

/// Full-bleed empty state used by every list.
class FEmptyState extends StatelessWidget {
  const FEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: FColors.neutralTint,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: FColors.inkFaint),
            ),
            const SizedBox(height: FSpace.x2),
            Text(title, style: FType.titleSm, textAlign: TextAlign.center),
            const SizedBox(height: FSpace.sm),
            Text(message, style: FType.supportSm, textAlign: TextAlign.center),
            if (action != null) ...<Widget>[
              const SizedBox(height: FSpace.x3),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Centred spinner in the brand teal.
class FLoading extends StatelessWidget {
  const FLoading({super.key, this.size = 22, this.padding = 32});

  final double size;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(padding),
      child: Center(
        child: SizedBox(
          width: size,
          height: size,
          child: const CircularProgressIndicator(
              strokeWidth: 2, color: FColors.teal),
        ),
      ),
    );
  }
}

/// Inline error with a retry affordance — used wherever a stream can fail.
class FErrorState extends StatelessWidget {
  const FErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded,
                size: 26, color: FColors.inkFaint),
            const SizedBox(height: FSpace.xl),
            Text(message, style: FType.supportSm, textAlign: TextAlign.center),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: FSpace.x2),
              InkWell(
                onTap: onRetry,
                borderRadius: FRadius.chipR,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Text(
                    'Try again',
                    style: FType.pill
                        .copyWith(color: FColors.tealDeep, fontSize: 11.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
