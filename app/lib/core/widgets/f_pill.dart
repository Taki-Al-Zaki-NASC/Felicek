import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';

/// The tinted status pill used everywhere: `98% Verified`, `Escrow Funded`,
/// `Flagged Spam`, `Challenge Passed`, …
class FPill extends StatelessWidget {
  const FPill(
    this.label, {
    super.key,
    required this.color,
    required this.background,
    this.fontSize = 10.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.radius = FRadius.chip,
    this.border,
    this.icon,
  });

  /// `color:#0d9488; background:#eaf6f4` — trust, verification, success.
  factory FPill.teal(String label, {double fontSize = 10.5, IconData? icon}) =>
      FPill(
        label,
        color: FColors.teal,
        background: FColors.tealTint,
        fontSize: fontSize,
        icon: icon,
      );

  /// `color:#2f5fa8; background:#eaf0fa` — escrow, counts, analytics.
  factory FPill.blue(String label, {double fontSize = 10.5, IconData? icon}) =>
      FPill(
        label,
        color: FColors.blue,
        background: FColors.blueTint,
        fontSize: fontSize,
        icon: icon,
      );

  /// `color:#8659c9; background:#f1eafb` — skill challenges and listing types.
  factory FPill.violet(String label,
          {double fontSize = 10.5, IconData? icon}) =>
      FPill(
        label,
        color: FColors.violet,
        background: FColors.violetTint,
        fontSize: fontSize,
        icon: icon,
      );

  /// `color:#d4a017; background:#fbf1de` — locked / pending.
  factory FPill.amber(String label, {double fontSize = 10.5, IconData? icon}) =>
      FPill(
        label,
        color: FColors.amber,
        background: FColors.amberTint,
        fontSize: fontSize,
        icon: icon,
      );

  /// `color:#b8382f; background:#fbe9e7` — rejected / spam.
  factory FPill.danger(String label,
          {double fontSize = 10.5, IconData? icon}) =>
      FPill(
        label,
        color: FColors.danger,
        background: FColors.dangerTint,
        fontSize: fontSize,
        icon: icon,
      );

  /// `color:#5b6472; background:#f2f0ea` — neutral metadata.
  factory FPill.neutral(String label,
          {double fontSize = 10.5, IconData? icon}) =>
      FPill(
        label,
        color: FColors.inkMuted,
        background: FColors.neutralTint,
        fontSize: fontSize,
        icon: icon,
      );

  final String label;
  final Color color;
  final Color background;
  final double fontSize;
  final EdgeInsets padding;
  final double radius;
  final Color? border;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: fontSize + 1.5, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: FType.pill.copyWith(fontSize: fontSize, color: color),
          ),
        ],
      ),
    );
  }
}

/// The role badge in the home header / profile card. Same shape as [FPill] but
/// with the teal hairline border the design draws around it.
class FRoleBadge extends StatelessWidget {
  const FRoleBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return FPill(
      label,
      color: FColors.tealDeep,
      background: FColors.tealTint,
      fontSize: 10,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      radius: FRadius.pill,
      border: FColors.teal.withValues(alpha: 0.25),
    );
  }
}

/// Skill / tag chip: `background:#f2f0ea` with a faint border.
class FTag extends StatelessWidget {
  const FTag(this.label, {super.key, this.fontSize = 10});

  final String label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: fontSize > 10 ? 9 : 8, vertical: fontSize > 10 ? 4 : 3),
      decoration: BoxDecoration(
        color: FColors.neutralTint,
        borderRadius: FRadius.chipR,
        border: Border.all(color: FColors.borderFaint),
      ),
      child: Text(
        label,
        style: FType.captionSm
            .copyWith(fontSize: fontSize, color: FColors.inkMuted),
      ),
    );
  }
}

/// Selectable filter / payment-method chip.
class FChoiceChip extends StatelessWidget {
  const FChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.expand = false,
    this.selectedColor = FColors.inkStrong,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool expand;
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final Widget chip = Material(
      color: selected
          ? selectedColor
          : (expand ? FColors.surface : FColors.neutralTint),
      borderRadius: expand ? FRadius.pillR : FRadius.roundR,
      child: InkWell(
        onTap: onTap,
        borderRadius: expand ? FRadius.pillR : FRadius.roundR,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: expand ? FRadius.pillR : FRadius.roundR,
            border: selected ? null : Border.all(color: FColors.borderStrong),
          ),
          child: Container(
            alignment: Alignment.center,
            padding: expand
                ? const EdgeInsets.symmetric(horizontal: 4, vertical: 9)
                : const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Text(
              label,
              style: FType.pill.copyWith(
                fontSize: expand ? 11 : 11.5,
                fontWeight: expand ? FontWeight.w600 : FontWeight.w500,
                color: selected ? Colors.white : FColors.inkMuted,
              ),
            ),
          ),
        ),
      ),
    );
    return expand ? Expanded(child: chip) : chip;
  }
}
