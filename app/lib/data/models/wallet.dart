import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/formatters.dart';

enum TxKind {
  escrowRelease,
  platformFee,
  withdrawal,
  deposit,
  depositRefund,
  topUp;

  static TxKind fromName(String? name) => TxKind.values.firstWhere(
        (TxKind k) => k.name == name,
        orElse: () => TxKind.escrowRelease,
      );
}

/// A line in the wallet ledger. Stored at `users/{uid}/transactions/{txId}`.
class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.label,
    required this.amountCents,
    required this.kind,
    this.method,
    this.jobId,
    this.createdAt,
  });

  factory WalletTransaction.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return WalletTransaction(
      id: doc.id,
      label: d['label'] as String? ?? '',
      amountCents: (d['amountCents'] as num?)?.toInt() ?? 0,
      kind: TxKind.fromName(d['kind'] as String?),
      method: d['method'] as String?,
      jobId: d['jobId'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String label;

  /// Signed: credits are positive, debits negative.
  final int amountCents;
  final TxKind kind;
  final String? method;
  final String? jobId;
  final DateTime? createdAt;

  double get amount => amountCents / 100;
  bool get isCredit => amountCents >= 0;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'label': label,
        'amountCents': amountCents,
        'kind': kind.name,
        'method': method,
        'jobId': jobId,
      };
}

/// The payout rails the product supports. Local rails carry no markup; the
/// platform only ever takes the flat maintenance fee.
enum PayoutMethod {
  bkash('bKash'),
  nagad('Nagad'),
  paypal('PayPal'),
  bank('Bank');

  const PayoutMethod(this.label);

  final String label;

  static PayoutMethod fromLabel(String? label) =>
      PayoutMethod.values.firstWhere(
        (PayoutMethod m) => m.label == label,
        orElse: () => PayoutMethod.bkash,
      );
}

/// Flat platform maintenance fee — 1% for local rails, 2% for international.
/// What a payment processor charges to move the money.
///
/// Separate from Felicek's own fee on purpose: one is a cost passed through
/// from a third party, the other is what this platform charges. Showing them
/// as a single blended number is how "we take 1%" quietly becomes 4%.
class GatewaySchedule {
  const GatewaySchedule({
    required this.key,
    required this.label,
    required this.rate,
    required this.fixedCents,
  });

  final String key;
  final String label;

  /// Percentage of the amount, as a fraction (0.029 == 2.9%).
  final double rate;

  /// Flat per-transaction charge, in cents.
  final int fixedCents;

  /// Card processing. Stripe's published rate; the fixed 30c is why small
  /// transfers are disproportionately expensive and worth showing.
  static const GatewaySchedule card = GatewaySchedule(
    key: 'card',
    label: 'Card',
    rate: 0.029,
    fixedCents: 30,
  );

  /// Local rails (bKash, Nagad, bank transfer) — percentage only.
  static const GatewaySchedule local = GatewaySchedule(
    key: 'local',
    label: 'Local transfer',
    rate: 0.02,
    fixedCents: 0,
  );

  static const List<GatewaySchedule> all = <GatewaySchedule>[card, local];

  static GatewaySchedule forMethod(PayoutMethod method) =>
      method == PayoutMethod.paypal ? card : local;

  int chargeCentsFor(int amountCents) =>
      amountCents <= 0 ? 0 : (amountCents * rate).round() + fixedCents;

  String get rateLabel {
    final String pct = (rate * 100).toStringAsFixed(1);
    final String trimmed = pct.endsWith('.0') ? pct.substring(0, pct.length - 2) : pct;
    return fixedCents == 0
        ? '$trimmed%'
        : '$trimmed% + ${Fmt.moneyExact(fixedCents / 100)}';
  }
}

/// A fully itemised fee calculation.
///
/// Every field is derived, never stored, so a screen cannot drift from what is
/// actually charged.
class FeeBreakdown {
  const FeeBreakdown({
    required this.grossCents,
    required this.gatewayCents,
    required this.platformCents,
    required this.schedule,
  });

  factory FeeBreakdown.of(int amountCents, GatewaySchedule schedule) {
    final int gross = amountCents < 0 ? 0 : amountCents;
    return FeeBreakdown(
      grossCents: gross,
      gatewayCents: schedule.chargeCentsFor(gross),
      platformCents: (gross * Fees.platformRate).round(),
      schedule: schedule,
    );
  }

  final int grossCents;
  final int gatewayCents;
  final int platformCents;
  final GatewaySchedule schedule;

  int get totalFeeCents => gatewayCents + platformCents;

  /// What the freelancer actually receives. Clamped at zero: on a tiny
  /// transfer the gateway's flat charge can exceed the amount, and a negative
  /// payout is not a thing that can happen.
  int get netCents =>
      (grossCents - totalFeeCents) < 0 ? 0 : grossCents - totalFeeCents;

  /// What a client pays in total when fees are added on top rather than
  /// deducted — used on the deposit screen.
  int get grossPlusFeesCents => grossCents + totalFeeCents;

  double get gross => grossCents / 100;
  double get gatewayFee => gatewayCents / 100;
  double get platformFee => platformCents / 100;
  double get totalFee => totalFeeCents / 100;
  double get net => netCents / 100;

  /// True when fees have eaten the whole amount — worth saying out loud
  /// rather than showing a confident "$0.00 you receive".
  bool get feesExceedAmount => totalFeeCents >= grossCents && grossCents > 0;
}

class Fees {
  const Fees._();

  /// Felicek's own cut. One percent, on everything, both roles.
  static const double platformRate = 0.01;

  static const double localRate = 0.01;
  static const double internationalRate = 0.02;

  /// The refundable freelancer trust deposit, in cents.
  static const int trustDepositCents = 2000;

  static double rateFor(PayoutMethod method) =>
      method == PayoutMethod.paypal ? internationalRate : localRate;

  static int feeCentsFor(int amountCents, PayoutMethod method) =>
      (amountCents * rateFor(method)).round();

  static String label(PayoutMethod method) =>
      method == PayoutMethod.paypal ? '2%' : '1%';

  /// The itemised version — prefer this anywhere a number is shown to someone.
  static FeeBreakdown breakdown(int amountCents, PayoutMethod method) =>
      FeeBreakdown.of(amountCents, GatewaySchedule.forMethod(method));
}
