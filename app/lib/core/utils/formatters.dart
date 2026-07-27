import 'package:intl/intl.dart';

/// Money, date and count formatting shared by every screen so numbers read the
/// same way everywhere (the design uses `$1,240.50`, `$18.4K`, `2h ago`).
class Fmt {
  const Fmt._();

  static final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: r'$',
    decimalDigits: 2,
  );
  static final NumberFormat _moneyWhole = NumberFormat.currency(
    locale: 'en_US',
    symbol: r'$',
    decimalDigits: 0,
  );
  static final NumberFormat _compact = NumberFormat.compact(locale: 'en_US');
  static final DateFormat _dayLabel = DateFormat('EEEE');
  static final DateFormat _dateLabel = DateFormat('d MMM yyyy');
  static final DateFormat _clock = DateFormat('h:mm a');

  /// `1240.5 → $1,240.50`; whole amounts drop the cents (`450 → $450`).
  static String money(num value) =>
      value % 1 == 0 ? _moneyWhole.format(value) : _money.format(value);

  /// Always shows cents — used for wallet balances and the $20 deposit.
  static String moneyExact(num value) => _money.format(value);

  /// `18400 → 18.4K` for the profile "Total earned" tile.
  static String compact(num value) => _compact.format(value);

  /// Signed amount for the transaction ledger (`+$540.00` / `-$10.80`).
  static String signedMoney(num value) =>
      '${value >= 0 ? '+' : '-'}${_money.format(value.abs())}';

  /// Relative time in the design's voice: `just now`, `10m ago`, `2h ago`,
  /// `1d ago`, then an absolute date past a week.
  static String relative(DateTime? when, {DateTime? now}) {
    if (when == null) return 'just now';
    final DateTime ref = now ?? DateTime.now();
    final Duration d = ref.difference(when);
    if (d.isNegative || d.inSeconds < 45) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return _dateLabel.format(when);
  }

  /// Very short relative label for chat list rows (`10m`, `2h`, `Mon`).
  static String relativeShort(DateTime? when, {DateTime? now}) {
    if (when == null) return '';
    final DateTime ref = now ?? DateTime.now();
    final Duration d = ref.difference(when);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return DateFormat('E').format(when);
    return DateFormat('d/M').format(when);
  }

  /// `9:30 PM` — the timestamp under a chat bubble.
  static String clock(DateTime when) => _clock.format(when);

  /// Day separator inside a chat thread.
  static String dayHeader(DateTime when, {DateTime? now}) {
    final DateTime ref = now ?? DateTime.now();
    final DateTime a = DateTime(when.year, when.month, when.day);
    final DateTime b = DateTime(ref.year, ref.month, ref.day);
    final int diff = b.difference(a).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return _dayLabel.format(when);
    return _dateLabel.format(when);
  }

  /// `1536000 → 1.5 MB` for the update downloader.
  static String bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(0)} KB';
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// `245 → 4:05` for the skill-challenge countdown.
  static String countdown(int seconds) {
    final int m = seconds ~/ 60;
    final String s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Parses the free-text budget strings the product allows
  /// (`$450`, `0.5% Equity + $2,000`, `Budget TBD`) into a sortable number.
  static double? budgetValue(String raw) {
    final RegExpMatch? m = RegExp(r'\$\s*([\d,]+(?:\.\d+)?)').firstMatch(raw);
    if (m == null) return null;
    return double.tryParse(m.group(1)!.replaceAll(',', ''));
  }
}
