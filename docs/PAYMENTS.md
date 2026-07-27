# Payments — what's shipped vs. what you deploy

Felicek requires real money to move before an account is usable: every role
pays a mandatory, non-skippable deposit (a refundable $20 trust bond for
freelancers, a $50 job-posting balance for clients/agencies/startups) through
a **dedicated external payment gateway** — never a button that just flips a
flag inside the app.

This document is the split between "shipped in this repo" and "infrastructure
you deploy," because that split is a security requirement, not a shortcut. No
code running purely on a user's phone can prove to itself that a real charge
cleared — if the app could mark its own payment as `paid`, so could anyone
with a rooted phone and five minutes, and the entire "no account without
payment" guarantee would be theater.

## Shipped in this repo

- **`app/lib/data/services/payment_gateway_service.dart`** — creates a
  `paymentIntents/{ref}` document in Firestore (`status: 'pending'`), opens
  the gateway's hosted checkout URL with `ref`, `uid`, `amount`, `purpose`
  and a `return_url` as query params, and polls/watches that same document
  for a status change.
- **`firebase/firestore.rules`** — a client may **create** a pending intent
  for itself and **read** it back. That is all. `allow update, delete: if
  false` for everyone — the rule that makes the guarantee real.
- **`app/lib/features/kyc/kyc_screen.dart`** and
  **`app/lib/features/wallet/wallet_screen.dart`** — the UI that starts a
  checkout and offers "I've paid — Verify" to re-check status.

## What you deploy

A small server-side webhook, hosted anywhere that isn't this Flutter app
(Cloud Run, a Cloud Function, a VM — anything with the Firebase Admin SDK):

1. Your payment gateway (Stripe, SSLCommerz, a local mobile-money aggregator)
   calls this webhook when a checkout succeeds, using **its own** signature
   verification — never trust an unsigned callback.
2. The webhook reads `ref` from the gateway's payload (you passed it through
   as the client reference / metadata when creating the checkout session).
3. Using the **Admin SDK** — which bypasses `firestore.rules` entirely — it
   updates `paymentIntents/{ref}`:
   ```js
   await db.doc(`paymentIntents/${ref}`).update({
     status: 'paid',
     method: gatewayPaymentMethodLabel,
     gatewayTransactionId: charge.id,
     updatedAt: FieldValue.serverTimestamp(),
   });
   ```
4. Nothing else. The app itself calls `UserRepository.recordDeposit` /
   credits the wallet once it observes `status == 'paid'` — and
   `firestore.rules` independently re-checks that same document before
   letting `kyc.depositPaid` flip to `true`, so even a compromised client
   gains nothing by lying about it.

## Why the app can't just "handle payments directly"

Handling card data or bank/mobile-money credentials inside the app puts you
in PCI/regulatory scope you almost certainly don't want, and — the more
basic problem — an app cannot authoritatively tell itself "yes, that charge
is real." A dedicated gateway's hosted checkout keeps card/PIN entry off this
app's surface entirely, and the ref-based webhook is the only place "paid"
can honestly originate from.

## Local/manual testing without a real gateway

Point `FELICEK_PAYMENT_CHECKOUT_URL` at any page you control, and use the
Firebase console (Admin access, not the client) to manually flip a test
`paymentIntents/{ref}` document to `status: 'paid'` while developing. That is
exactly what the webhook automates in production — the rules do not
distinguish "console" from "webhook," both use privileged Admin access the
app itself never has.
