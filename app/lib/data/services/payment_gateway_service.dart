import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_config.dart';
import '../models/payment_intent.dart';
import 'firestore_refs.dart';

/// Hands real money off to a dedicated external payment gateway instead of
/// simulating it in-app.
///
/// The requirement this implements: **no account exists in a usable state,
/// and no client can post a job, without money actually moving** — and that
/// "actually" has to be enforceable, which a pure client app cannot do for
/// itself. So the flow is:
///
/// 1. The app creates a `paymentIntents/{ref}` document in `pending` status —
///    this is the only part a client is allowed to do.
/// 2. It opens the gateway's hosted checkout (Stripe Checkout, SSLCommerz,
///    bKash's own payment page, etc.) in the system browser via
///    [launchUrl], passing `ref` as the client reference number.
/// 3. The gateway's own webhook — running on a small server endpoint that is
///    *not* part of this Flutter app — verifies the charge and flips that
///    same document to `paid` using the Admin SDK, which is not bound by
///    Firestore security rules.
/// 4. The app watches the document and only then calls
///    `UserRepository.recordDeposit` / credits the wallet.
///
/// Steps 1, 2 and 4 live here. Step 3 is infrastructure this repository
/// cannot ship as Dart source — it is a webhook endpoint you deploy next to
/// whichever gateway you contract with — and `docs/PAYMENTS.md` documents
/// exactly what that endpoint needs to do. Treating that as "already wired"
/// would be dishonest: nothing running purely on a user's phone can prove to
/// itself that a real payment cleared.
class PaymentGatewayService {
  PaymentGatewayService(this._db);

  final Db _db;

  static const Duration _pollInterval = Duration(seconds: 3);
  static const Duration _timeout = Duration(minutes: 15);

  /// Creates the pending intent and opens the gateway checkout. Returns the
  /// reference to watch with [watchStatus] or [waitForCompletion].
  Future<String> startCheckout({
    required String uid,
    required PaymentPurpose purpose,
    required int amountCents,
    Map<String, String> metadata = const <String, String>{},
  }) async {
    final String ref = _db.newId(_db.paymentIntents);
    final PaymentIntent intent = PaymentIntent(
      ref: ref,
      uid: uid,
      purpose: purpose,
      amountCents: amountCents,
      metadata: metadata,
    );
    await _db.paymentIntent(ref).set(<String, dynamic>{
      ...intent.toCreateMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final Uri checkoutUrl = Uri.parse(AppConfig.paymentCheckoutUrl).replace(
      queryParameters: <String, String>{
        'ref': ref,
        'uid': uid,
        'amount': (amountCents / 100).toStringAsFixed(2),
        'currency': 'USD',
        'purpose': purpose.name,
        'return_url': '${AppConfig.deepLinkScheme}://payment-return?ref=$ref',
        ...metadata,
      },
    );

    final bool opened = await launchUrl(
      checkoutUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw const PaymentGatewayException(
        'Could not open the payment page. Check your connection and try again.',
      );
    }
    return ref;
  }

  Stream<PaymentIntent?> watchStatus(String ref) =>
      _db.paymentIntent(ref).snapshots().map(
            (DocumentSnapshot<Json> doc) =>
                doc.exists ? PaymentIntent.fromDoc(doc) : null,
          );

  Future<PaymentIntent?> fetchStatus(String ref) async {
    final DocumentSnapshot<Json> doc = await _db.paymentIntent(ref).get();
    return doc.exists ? PaymentIntent.fromDoc(doc) : null;
  }

  /// Polls until the webhook marks the intent `paid`/`failed`/`cancelled`, or
  /// [_timeout] elapses (surfaced as `null` so the UI can offer "check
  /// again" rather than hanging forever on a webhook that never arrives).
  Future<PaymentIntent?> waitForCompletion(String ref) async {
    final DateTime deadline = DateTime.now().add(_timeout);
    while (DateTime.now().isBefore(deadline)) {
      final PaymentIntent? intent = await fetchStatus(ref);
      if (intent != null && intent.status != PaymentStatus.pending) {
        return intent;
      }
      await Future<void>.delayed(_pollInterval);
    }
    return null;
  }
}

class PaymentGatewayException implements Exception {
  const PaymentGatewayException(this.message);

  final String message;

  @override
  String toString() => message;
}
