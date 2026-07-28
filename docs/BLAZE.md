# What needs the Blaze plan

Everything in Felicek runs on Firebase's free **Spark** plan today. Four
features cannot, and this is the honest account of why, what each one costs,
and exactly what to do when you upgrade.

Read this before paying for anything: Blaze is pay-as-you-go with no ceiling by
default. **Set a budget alert first** (Google Cloud Console → Billing → Budgets
& alerts). At ~12 users the free allowances still cover almost all of this, so
the bill is likely to be pennies — but "likely" is not a spend limit, and a
runaway loop in a Cloud Function is a real way to get a surprising invoice.

---

## 1. Push notifications (FCM)

**Blocked because:** sending a push requires the FCM server key, and a key
shipped inside an APK is a key anyone can extract and use to send push
notifications to your whole user base. There is no client-only version of this.
The send has to happen somewhere the user does not control.

Today the app writes notification documents to Firestore and the recipient's
device picks them up while the app is running. That covers in-app notifications
completely. What it cannot do is wake a closed app.

**When you upgrade:**

1. `flutter pub add firebase_messaging`
2. Request the notification permission on Android 13+ (`POST_NOTIFICATIONS`).
3. Store each device's FCM token on the user document, and delete it on sign
   out — otherwise the next person to use that phone gets the previous
   account's messages.
4. Deploy a Cloud Function on `onDocumentCreated` for
   `users/{uid}/notifications/{id}` that reads the token and sends. The
   notification documents already exist and already have the right shape, so
   this is a fan-out step, not a redesign.
5. Handle the token refresh callback — tokens rotate, and a stale token fails
   silently.

**Cost:** FCM itself is free at any volume. You are paying for the Cloud
Function invocations: 2M/month free, then ~$0.40 per million.

---

## 2. Video watermarking

**Blocked because:** two separate things, and the second is the harder one.

- **Processing.** Stamping a video means decoding, compositing and re-encoding
  it. That is ffmpeg. `ffmpeg_kit_flutter` was retired in 2025 and its binaries
  are no longer distributed, so there is no maintained Flutter package for it.
  The realistic path is server-side transcoding, not on-device.
- **Storage.** Photo watermarking works today because a downsized JPEG fits in
  a Firestore document. Firestore's hard limit is 1 MiB per document; a video
  is orders of magnitude larger. Cloud Storage is Blaze-only for new projects.

**When you upgrade:**

1. Enable Cloud Storage; add `firebase_storage`.
2. Upload the original to a path the client cannot read
   (`deliverables/{chatId}/{messageId}/original.mp4`).
3. A Cloud Function on finalize transcodes a watermarked preview to a path the
   client *can* read.
4. Releasing the milestone grants access to the original — the same rule shape
   as `chats/{chatId}/deliverables/{messageId}` uses now, so the model carries
   over unchanged.

**Cost:** Storage ~$0.026/GB/month plus egress. Transcoding is the expensive
part — a Cloud Function doing ffmpeg work is billed on CPU-seconds, and video
is not quick. Budget-alert this one specifically.

---

## 3. Payment webhook

**Blocked because:** the rule that stops an account marking its own deposit
paid is the reason payments mean anything:

```
allow update: if ... request.resource.data.kyc.depositPaid == true
  && get(/databases/$(database)/documents/paymentIntents/$(ref)).data.status == 'paid'
```

A client can only flip `depositPaid` when a matching intent already reads
`paid` — and **nothing in this app can write that value.** Only the Admin SDK
can, from a server the user does not control. That is deliberate. Until the
webhook exists, "I've paid — Verify" can never succeed against a real gateway.

**When you upgrade:** deploy the webhook from `docs/PAYMENTS.md`. It verifies
the gateway's signature, then sets `paymentIntents/{ref}.status = 'paid'` with
the Admin SDK.

**Cost:** Cloud Function invocations only — negligible at this volume.

---

## 4. Server-side identity verification

**Not blocked by Blaze**, but worth listing beside the others because it is the
same class of gap.

`IdentityCheck` screens photos on the device: sharpness, exposure, resolution,
and the number's format. It rejects input a reviewer could not use. It cannot
tell you a document is genuine, and nothing running on the claimant's own phone
ever could — the device that captures the image can fabricate it.

`IdentityCheck.providerHook()` throws `UnimplementedError` rather than
returning a fake pass, and a test asserts it keeps throwing. Wiring in Onfido,
Persona or Stripe Identity means their verdict arrives on a server and sets
`kyc.stage`, so the account being verified is not the thing deciding it.

---

## Quick reference

| Feature | Needs | Roughly |
|---|---|---|
| FCM push | Cloud Functions | Free tier covers it |
| Video watermarking | Cloud Storage + Functions | Storage cheap, transcoding is not |
| Payment webhook | Cloud Functions | Negligible |
| Identity provider | A KYC vendor, not Firebase | ~$1–2 per check |

Nothing here changes the client's data model. Each one replaces a piece
currently marked as unimplemented, and the Firestore shapes they write to
already exist.
