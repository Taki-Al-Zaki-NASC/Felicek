import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentPurpose {
  trustDeposit,
  postingBalance,
  walletTopUp;

  static PaymentPurpose fromName(String? name) =>
      PaymentPurpose.values.firstWhere(
        (PaymentPurpose p) => p.name == name,
        orElse: () => PaymentPurpose.walletTopUp,
      );
}

enum PaymentStatus {
  pending,
  paid,
  failed,
  cancelled;

  static PaymentStatus fromName(String? name) =>
      PaymentStatus.values.firstWhere(
        (PaymentStatus s) => s.name == name,
        orElse: () => PaymentStatus.pending,
      );
}

/// A record of one external-gateway checkout. Stored at
/// `paymentIntents/{ref}`.
///
/// The client is only ever allowed to *create* this document, in `pending`
/// status, for its own uid — see `firestore.rules`. Only the payment
/// gateway's server-side webhook (using the Admin SDK, which bypasses
/// Firestore rules entirely) is trusted to flip it to `paid`. This is what
/// makes "no account without a real payment" an actual guarantee rather than
/// a client-side checkbox: nothing running on the phone can mark its own
/// money as received.
class PaymentIntent {
  const PaymentIntent({
    required this.ref,
    required this.uid,
    required this.purpose,
    required this.amountCents,
    this.status = PaymentStatus.pending,
    this.method,
    this.gatewayTransactionId,
    this.metadata = const <String, String>{},
    this.createdAt,
    this.updatedAt,
  });

  factory PaymentIntent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return PaymentIntent(
      ref: doc.id,
      uid: d['uid'] as String? ?? '',
      purpose: PaymentPurpose.fromName(d['purpose'] as String?),
      amountCents: (d['amountCents'] as num?)?.toInt() ?? 0,
      status: PaymentStatus.fromName(d['status'] as String?),
      method: d['method'] as String?,
      gatewayTransactionId: d['gatewayTransactionId'] as String?,
      metadata: (d['metadata'] as Map<String, dynamic>? ?? <String, dynamic>{})
          .map((String k, dynamic v) =>
              MapEntry<String, String>(k, v.toString())),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  final String ref;
  final String uid;
  final PaymentPurpose purpose;
  final int amountCents;
  final PaymentStatus status;
  final String? method;

  /// The gateway's own charge/session id, set by the webhook — useful for
  /// support disputes.
  final String? gatewayTransactionId;
  final Map<String, String> metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  double get amount => amountCents / 100;

  Map<String, dynamic> toCreateMap() => <String, dynamic>{
        'uid': uid,
        'purpose': purpose.name,
        'amountCents': amountCents,
        'status': PaymentStatus.pending.name,
        'metadata': metadata,
      };
}
