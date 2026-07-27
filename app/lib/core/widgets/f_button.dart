import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

enum FButtonVariant {
  /// `background:#1c2534; color:#f7f5f0` — the primary action everywhere.
  primary,

  /// `background:#0d9488; color:#fff` — money-positive action (Withdraw).
  teal,

  /// `background:#8659c9; color:#fff` — skill-challenge action.
  violet,

  /// White with a hairline border.
  secondary,

  /// `background:#fbe9e7; color:#b8382f` — destructive.
  danger,

  /// Teal-tinted confirmation state ("Proposal Submitted ✓").
  success,

  /// Disabled / awaiting-precondition state.
  muted,
}

/// The filled action button used across the design. It is a `div` there, so
/// this widget reproduces the exact padding/radius/weight rather than using
/// Material's default button metrics.
class FButton extends StatelessWidget {
  const FButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = FButtonVariant.primary,
    this.expand = true,
    this.padding = const EdgeInsets.all(15),
    this.fontSize = 13.5,
    this.busy = false,
    this.icon,
  });

  /// Compact variant used inside cards (11–13px padding).
  const FButton.compact({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = FButtonVariant.primary,
    this.expand = true,
    this.busy = false,
    this.icon,
  })  : padding = const EdgeInsets.all(11),
        fontSize = 12.5;

  final String label;
  final VoidCallback? onPressed;
  final FButtonVariant variant;
  final bool expand;
  final EdgeInsets padding;
  final double fontSize;
  final bool busy;
  final IconData? icon;

  bool get _enabled => onPressed != null && !busy;

  ({Color bg, Color fg, Color? border}) get _palette {
    switch (variant) {
      case FButtonVariant.primary:
        return (bg: FColors.inkStrong, fg: FColors.canvas, border: null);
      case FButtonVariant.teal:
        return (bg: FColors.teal, fg: Colors.white, border: null);
      case FButtonVariant.violet:
        return (bg: FColors.violet, fg: Colors.white, border: null);
      case FButtonVariant.secondary:
        return (
          bg: FColors.surface,
          fg: FColors.inkMuted,
          border: FColors.borderStrong
        );
      case FButtonVariant.danger:
        return (bg: FColors.dangerTint, fg: FColors.danger, border: null);
      case FButtonVariant.success:
        return (
          bg: FColors.tealTint,
          fg: FColors.teal,
          border: FColors.teal.withValues(alpha: 0.3),
        );
      case FButtonVariant.muted:
        return (bg: FColors.neutralTint, fg: FColors.inkFaint, border: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ({Color bg, Color fg, Color? border}) p = _palette;
    final Widget content = busy
        ? SizedBox(
            height: fontSize + 2,
            width: fontSize + 2,
            child: CircularProgressIndicator(strokeWidth: 2, color: p.fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: fontSize + 2, color: p.fg),
                const SizedBox(width: FSpace.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style:
                      FType.buttonSm.copyWith(fontSize: fontSize, color: p.fg),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: label,
      child: Opacity(
        opacity: _enabled ? 1 : 0.75,
        child: Material(
          color: p.bg,
          borderRadius: FRadius.buttonR,
          child: InkWell(
            onTap: _enabled ? onPressed : null,
            borderRadius: FRadius.buttonR,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: FRadius.buttonR,
                border: p.border == null ? null : Border.all(color: p.border!),
              ),
              child: Container(
                width: expand ? double.infinity : null,
                padding: padding,
                alignment: Alignment.center,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tappable text link ("Manage ›", "Message").
class FTextAction extends StatelessWidget {
  const FTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = FColors.tealDeep,
    this.background,
    this.fontSize = 11,
  });

  final String label;
  final VoidCallback onPressed;
  final Color color;
  final Color? background;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background ?? Colors.transparent,
      borderRadius: FRadius.chipR,
      child: InkWell(
        onTap: onPressed,
        borderRadius: FRadius.chipR,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: background == null ? 0 : 11,
            vertical: background == null ? 2 : 6,
          ),
          child: Text(
            label,
            style: FType.pill.copyWith(fontSize: fontSize, color: color),
          ),
        ),
      ),
    );
  }
}
