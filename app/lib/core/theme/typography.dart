import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Named text styles, sized exactly as the design specifies.
///
/// The design mixes a serif (`Newsreader`) for editorial moments — the
/// wordmark, job titles, screen titles — with `IBM Plex Sans` for everything
/// else. Both faces are bundled in `assets/fonts`, so the app renders
/// identically offline and on devices with no Google Fonts cache.
class FType {
  const FType._();

  static const String sans = 'IBMPlexSans';
  static const String serif = 'Newsreader';

  // ── Editorial serif ─────────────────────────────────────────────────────

  /// 34/600 — onboarding wordmark.
  static const TextStyle displayXl = TextStyle(
    fontFamily: serif,
    fontSize: 34,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    height: 1.15,
    color: FColors.ink,
  );

  /// 22/600 — job detail title.
  static const TextStyle displayLg = TextStyle(
    fontFamily: serif,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: FColors.ink,
  );

  /// 20/600 — screen titles ("Wallet & Vault", "Proposal Queue"), home wordmark.
  static const TextStyle displayMd = TextStyle(
    fontFamily: serif,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: FColors.ink,
  );

  /// 18/600 — dark profile header.
  static const TextStyle displaySm = TextStyle(
    fontFamily: serif,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: FColors.ink,
  );

  /// 16/600 — job card title.
  static const TextStyle displayXs = TextStyle(
    fontFamily: serif,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: FColors.ink,
  );

  // ── Sans UI ─────────────────────────────────────────────────────────────

  /// 17/600 — profile name.
  static const TextStyle titleLg = TextStyle(
    fontFamily: sans,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: FColors.ink,
  );

  /// 14/600 — settings row title.
  static const TextStyle titleMd = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: FColors.ink,
  );

  /// 13/600 — app bar title, list headline.
  static const TextStyle titleSm = TextStyle(
    fontFamily: sans,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: FColors.ink,
  );

  /// 12.5/600 — compact list headline.
  static const TextStyle titleXs = TextStyle(
    fontFamily: sans,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: FColors.ink,
  );

  /// 13.5/400 — the default body size for forms and scope copy.
  static const TextStyle body = TextStyle(
    fontFamily: sans,
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.7,
    color: FColors.inkBody,
  );

  /// 13/400 — cards and paragraph copy.
  static const TextStyle bodySm = TextStyle(
    fontFamily: sans,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.6,
    color: FColors.inkBody,
  );

  /// 12.5/400 — chat bubbles, dense rows.
  static const TextStyle bodyXs = TextStyle(
    fontFamily: sans,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: FColors.ink,
  );

  /// 12/400 — supporting copy under a title.
  static const TextStyle support = TextStyle(
    fontFamily: sans,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.6,
    color: FColors.inkMuted,
  );

  /// 11.5/400 — card summaries.
  static const TextStyle supportSm = TextStyle(
    fontFamily: sans,
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: FColors.inkMuted,
  );

  /// 11.5/500 — field labels.
  static const TextStyle fieldLabel = TextStyle(
    fontFamily: sans,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    color: FColors.inkMuted,
  );

  /// 11/600 uppercase 0.6px tracking — section headers.
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: sans,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.6,
    color: FColors.inkMuted,
  );

  /// 10.5/600 — status pills.
  static const TextStyle pill = TextStyle(
    fontFamily: sans,
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
  );

  /// 10/600 — small pills, tab labels.
  static const TextStyle pillSm = TextStyle(
    fontFamily: sans,
    fontSize: 10,
    fontWeight: FontWeight.w600,
  );

  /// 10.5/400 — timestamps and captions.
  static const TextStyle caption = TextStyle(
    fontFamily: sans,
    fontSize: 10.5,
    fontWeight: FontWeight.w400,
    height: 1.6,
    color: FColors.inkFaint,
  );

  /// 10/400 — the very smallest metadata.
  static const TextStyle captionSm = TextStyle(
    fontFamily: sans,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: FColors.inkFaint,
  );

  /// 16/700 — stat tile number.
  static const TextStyle statValue = TextStyle(
    fontFamily: sans,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: FColors.ink,
  );

  /// 14/700 — filled button label.
  static const TextStyle button = TextStyle(
    fontFamily: sans,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );

  /// 13.5/700 — the more common filled button label.
  static const TextStyle buttonSm = TextStyle(
    fontFamily: sans,
    fontSize: 13.5,
    fontWeight: FontWeight.w700,
  );

  /// 13/700 — money amounts on cards.
  static const TextStyle money = TextStyle(
    fontFamily: sans,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: FColors.tealDeep,
  );
}
