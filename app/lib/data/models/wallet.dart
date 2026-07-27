import 'package:cloud_firestore/cloud_firestore.dart';

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
class Fees {
  const Fees._();

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
}
