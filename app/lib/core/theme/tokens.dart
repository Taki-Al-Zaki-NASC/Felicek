import 'package:flutter/widgets.dart';

/// Design tokens lifted verbatim from `Felicek.dc.html`.
///
/// Every colour, radius and type size in the app comes from here — nothing in
/// the feature layer is allowed to hard-code a hex value, which is what keeps
/// the added screens visually identical to the ones that came from the design.
class FColors {
  const FColors._();

  // ── Surfaces ────────────────────────────────────────────────────────────
  /// Page canvas behind the device frame in the design.
  static const Color pageBackdrop = Color(0xFFE9E6DF);

  /// The app's own canvas.
  static const Color canvas = Color(0xFFF7F5F0);

  /// Cards, sheets, app bars.
  static const Color surface = Color(0xFFFFFFFF);

  /// Quiet inset rows (milestones, challenge answers).
  static const Color surfaceSunken = Color(0xFFF9F8F5);

  /// Text-field fill inside the composer.
  static const Color surfaceField = Color(0xFFFAF9F6);

  /// Neutral chips, search bar, inactive filter pills.
  static const Color neutralTint = Color(0xFFF2F0EA);

  // ── Ink ─────────────────────────────────────────────────────────────────
  /// Primary body text.
  static const Color ink = Color(0xFF1B2430);

  /// Slightly warmer ink used for long-form paragraphs.
  static const Color inkBody = Color(0xFF2B3340);

  /// Filled buttons, bottom nav, wallet card, dark headers.
  static const Color inkStrong = Color(0xFF1C2534);

  /// Secondary labels.
  static const Color inkMuted = Color(0xFF5B6472);

  /// Tertiary / metadata text.
  static const Color inkFaint = Color(0xFF8A92A0);

  /// Inactive tab-bar items and radio outlines.
  static const Color inkDisabled = Color(0xFFAAB2C0);

  /// Unselected radio ring on the role cards.
  static const Color radioRing = Color(0xFFC9CDD6);

  /// Muted copy on the dark wallet card.
  static const Color onDarkMuted = Color(0xFFAAB2C0);

  // ── Accent: teal (trust, verification, money in) ────────────────────────
  static const Color teal = Color(0xFF0D9488);
  static const Color tealDeep = Color(0xFF0D7D74);
  static const Color tealDarker = Color(0xFF0A5F58);
  static const Color tealTint = Color(0xFFEAF6F4);

  // ── Accent: blue (escrow, analytics) ────────────────────────────────────
  static const Color blue = Color(0xFF2F5FA8);
  static const Color blueTint = Color(0xFFEAF0FA);

  // ── Accent: violet (skill challenges, listing type tag) ─────────────────
  static const Color violet = Color(0xFF8659C9);
  static const Color violetTint = Color(0xFFF1EAFB);

  // ── Accent: amber (locked vault, warnings, ratings) ─────────────────────
  static const Color amber = Color(0xFFD4A017);
  static const Color amberTint = Color(0xFFFBF1DE);

  // ── Accent: red (danger, spam, destructive) ─────────────────────────────
  static const Color danger = Color(0xFFB8382F);
  static const Color dangerTint = Color(0xFFFBE9E7);

  // ── Lines ───────────────────────────────────────────────────────────────
  /// `rgba(27,36,48,0.08)` — card borders and section dividers.
  static const Color border = Color(0x141B2430);

  /// `rgba(27,36,48,0.12)` — input borders.
  static const Color borderStrong = Color(0x1F1B2430);

  /// `rgba(27,36,48,0.06)` — hairlines inside sunken rows.
  static const Color borderFaint = Color(0x0F1B2430);

  /// Border on translucent controls sitting on the dark wallet card.
  static const Color borderOnDark = Color(0x26FFFFFF);

  /// Fill for translucent controls on the dark wallet card.
  static const Color fillOnDark = Color(0x14FFFFFF);

  /// Readable accent for links/actions rendered on `inkStrong` backgrounds.
  static const Color accentOnDark = Color(0xFF83D5C6);

  // ── Portfolio placeholder hatch ─────────────────────────────────────────
  static const Color hatchA = Color(0xFFE3E0D8);
  static const Color hatchB = Color(0xFFDCD8CE);
  static const Color hatchInk = Color(0xFF9A9488);

  /// The verified-avatar gradient (`conic-gradient(from 210deg,…)`).
  static const List<Color> avatarSweep = <Color>[teal, blue, teal];

  /// 12% tint of [c] — the design writes this as `<hex>1a`.
  static Color tint(Color c) => c.withValues(alpha: 0.10);
}

/// 4px-derived spacing scale, matching the paddings used in the design.
class FSpace {
  const FSpace._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 12;
  static const double x2 = 14;
  static const double x3 = 16;
  static const double x4 = 18;
  static const double x5 = 20;
  static const double x6 = 22;
  static const double x7 = 26;
  static const double x8 = 32;
}

/// Corner radii used in the design.
class FRadius {
  const FRadius._();

  static const double chip = 8;
  static const double pill = 9;
  static const double field = 10;
  static const double row = 11;
  static const double button = 12;
  static const double card = 14;
  static const double cardLg = 16;
  static const double sheet = 18;
  static const double round = 20;
  static const double full = 999;

  static const BorderRadius chipR = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius pillR = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius fieldR = BorderRadius.all(Radius.circular(field));
  static const BorderRadius rowR = BorderRadius.all(Radius.circular(row));
  static const BorderRadius buttonR = BorderRadius.all(Radius.circular(button));
  static const BorderRadius cardR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius cardLgR = BorderRadius.all(Radius.circular(cardLg));
  static const BorderRadius sheetR = BorderRadius.all(Radius.circular(sheet));
  static const BorderRadius roundR = BorderRadius.all(Radius.circular(round));
}

/// Motion durations. Kept short — the product reads as "fast and factual".
class FMotion {
  const FMotion._();

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
  static const Curve curve = Curves.easeOutCubic;
}
