import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/wallet.dart';
import '../services/firestore_refs.dart';

/// The wallet ledger and the trust-fund vault.
///
/// Balances move through a Firestore transaction so a double-tapped withdraw
/// can never spend the same money twice, and every movement writes a ledger
/// line in the same atomic step.
class WalletRepository {
  WalletRepository(this._db);

  final Db _db;

  Stream<List<WalletTransaction>> watchTransactions(String uid,
          {int limit = 40}) =>
      _db
          .transactions(uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map(
            (JsonQuerySnap s) =>
                s.docs.map(WalletTransaction.fromDoc).toList(growable: false),
          );

  /// Withdraws to a payout rail, taking the flat maintenance fee.
  ///
  /// Throws [InsufficientFunds] when the balance cannot cover it.
  Future<void> withdraw({
    required String uid,
    required int amountCents,
    required PayoutMethod method,
  }) async {
    if (amountCents <= 0) {
      throw const InsufficientFunds('Enter an amount greater than zero.');
    }
    final int feeCents = Fees.feeCentsFor(amountCents, method);
    final DocumentReference<Json> userRef = _db.user(uid);
    final DocumentReference<Json> txRef = _db.transactions(uid).doc();
    final DocumentReference<Json> feeRef = _db.transactions(uid).doc();

    await _db.firestore.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Json> snap = await tx.get(userRef);
      final int balance =
          (snap.data()?['walletBalanceCents'] as num?)?.toInt() ?? 0;
      if (balance < amountCents + feeCents) {
        throw InsufficientFunds(
          'Your available balance is ${(balance / 100).toStringAsFixed(2)} — '
          'not enough for this withdrawal plus the ${Fees.label(method)} fee.',
        );
      }
      tx.update(userRef, <String, dynamic>{
        'walletBalanceCents': balance - amountCents - feeCents,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(txRef, <String, dynamic>{
        ...WalletTransaction(
          id: txRef.id,
          label: 'Withdrawal to ${method.label}',
          amountCents: -amountCents,
          kind: TxKind.withdrawal,
          method: method.label,
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (feeCents > 0) {
        tx.set(feeRef, <String, dynamic>{
          ...WalletTransaction(
            id: feeRef.id,
            label: 'Platform maintenance fee (${Fees.label(method)})',
            amountCents: -feeCents,
            kind: TxKind.platformFee,
            method: method.label,
          ).toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  /// Adds funds (a client pre-funding escrow, or a sandbox top-up).
  Future<void> addFunds({
    required String uid,
    required int amountCents,
    required PayoutMethod method,
  }) async {
    if (amountCents <= 0) return;
    final DocumentReference<Json> userRef = _db.user(uid);
    final DocumentReference<Json> txRef = _db.transactions(uid).doc();

    await _db.firestore.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Json> snap = await tx.get(userRef);
      final int balance =
          (snap.data()?['walletBalanceCents'] as num?)?.toInt() ?? 0;
      tx.update(userRef, <String, dynamic>{
        'walletBalanceCents': balance + amountCents,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(txRef, <String, dynamic>{
        ...WalletTransaction(
          id: txRef.id,
          label: 'Added funds via ${method.label}',
          amountCents: amountCents,
          kind: TxKind.topUp,
          method: method.label,
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Records the refundable $20 trust deposit as a ledger line.
  Future<void> recordTrustDeposit({
    required String uid,
    required PayoutMethod method,
  }) async {
    final DocumentReference<Json> txRef = _db.transactions(uid).doc();
    await txRef.set(<String, dynamic>{
      ...WalletTransaction(
        id: txRef.id,
        label: 'Trust fund deposit (refundable)',
        amountCents: -Fees.trustDepositCents,
        kind: TxKind.deposit,
        method: method.label,
      ).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Releases an escrow milestone into the freelancer's balance, net of the
  /// platform fee, and mirrors both lines into the ledger.
  Future<void> releaseEscrow({
    required String freelancerId,
    required int amountCents,
    required String jobTitle,
    required String jobId,
    PayoutMethod method = PayoutMethod.bkash,
  }) async {
    final int feeCents = Fees.feeCentsFor(amountCents, method);
    final DocumentReference<Json> userRef = _db.user(freelancerId);
    final DocumentReference<Json> creditRef =
        _db.transactions(freelancerId).doc();
    final DocumentReference<Json> feeRef = _db.transactions(freelancerId).doc();

    await _db.firestore.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Json> snap = await tx.get(userRef);
      final Json data = snap.data() ?? <String, dynamic>{};
      final int balance = (data['walletBalanceCents'] as num?)?.toInt() ?? 0;
      final int earned = (data['totalEarnedCents'] as num?)?.toInt() ?? 0;
      tx.update(userRef, <String, dynamic>{
        'walletBalanceCents': balance + amountCents - feeCents,
        'totalEarnedCents': earned + amountCents,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(creditRef, <String, dynamic>{
        ...WalletTransaction(
          id: creditRef.id,
          label: 'Escrow release — $jobTitle',
          amountCents: amountCents,
          kind: TxKind.escrowRelease,
          jobId: jobId,
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(feeRef, <String, dynamic>{
        ...WalletTransaction(
          id: feeRef.id,
          label: 'Platform maintenance fee (${Fees.label(method)})',
          amountCents: -feeCents,
          kind: TxKind.platformFee,
          jobId: jobId,
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}

/// Raised when a withdrawal exceeds the available balance.
class InsufficientFunds implements Exception {
  const InsufficientFunds(this.message);

  final String message;

  @override
  String toString() => message;
}
