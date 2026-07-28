# Felicek

Verified talent. Zero spam. Fair fees, always.

A freelance marketplace where every account is identity-verified and
deposit-backed before it can post or bid — with escrow milestones, live skill
challenges, real-time messaging and built-in audio/video calling.

Built from the Claude Design source in `Felicek.dc.html` (kept in the repo as
the design's source of truth, alongside `android-frame.jsx` and `support.js`).

## Repository layout

```
app/          Flutter client — Android, iOS, macOS, Windows
firebase/     Firestore security rules + indexes (Spark/free tier only)
website/      Download page and update.json release manifest
docs/         Setup, payments, and updater documentation
.github/      CI and release workflows
```

## What's implemented

**Every screen in the design**, token-for-token — onboarding, profile setup,
verification, home (browse + dashboard), job detail (freelancer and owner
views), post a job, proposals, wallet & vault, profile, chat. Colours, type
scale, radii and spacing all come from `app/lib/core/theme/tokens.dart`,
lifted directly from the design file. Both typefaces (Newsreader, IBM Plex
Sans) are bundled, so the app renders identically offline.

**Plus the screens the design didn't cover**, built from the same tokens:
sign in / sign up / password reset, splash, inbox, search, settings, the
challenge-taking sheet, the call screens, and the update surfaces.

### Messaging

Deterministic thread ids (so a double-tap can't fork a conversation),
optimistic send through Firestore's offline cache, delivery/read receipts as
chat-level watermarks (one write to mark 200 messages read, not 200), typing
indicators with a TTL so they can't stick, pagination over a live window,
reply/edit/delete, retry for rejected sends, day separators, message
grouping, mute, archive, and block.

### Verification and payments

No account reaches a usable state without **identity on file and a cleared
payment** — enforced in `firebase/firestore.rules`, not just in the UI.

| Role | Deposit | What it is |
|---|---|---|
| Freelancer | $20 | Refundable trust bond, released after the first completed job |
| Individual Client | $50 | Job-posting balance — their money, spent into escrow when they hire |
| Agency | $50 | Same as client |
| Startup | $50 | Same as client |

Identity accepts National ID, passport, driver's licence or another
government ID (plus an optional birth certificate). Only the document
*number* is stored — never a photo. Individual freelancers must also add a
real profile photo.

Money moves through a **dedicated external payment gateway**, never in-app.
See [docs/PAYMENTS.md](docs/PAYMENTS.md) — including an explicit account of
which piece is infrastructure you deploy rather than Dart in this repo, and
why that boundary is a security requirement.

### Skill challenges

Three modes: a written prompt, an auto-graded multiple-choice quiz, or a live
call-session interview.

The privacy rule is enforced server-side: a job owner **never** sees an
applicant's full code or design. The full submission lives in
`proposals/{id}/submission/full`, readable only by its author; the owner sees
a score and a ≤160-character preview. Quiz answer keys live in
`jobs/{id}/challengeKey`, readable only by the owner — so an applicant can't
read the key either.

### Calling

One-to-one audio and video over WebRTC, signaled through Firestore documents
with public STUN for NAT traversal — no media server, so no per-minute bill.
Works on Android phones and tablets, iOS iPhone and iPad, macOS and Windows.

### Auto-update

The app polls `update.json`, compares `versionCode`, honours a staged
rollout, downloads in the background, **verifies SHA-256 before installing**,
and hands the APK to Android's package installer. See
[docs/UPDATER.md](docs/UPDATER.md) — which is also explicit that Android
still shows one system confirmation dialog; no sideloaded app can silently
replace itself, and this repo doesn't pretend otherwise.

### The engagement loop

Hire → escrow funded from the client's posting balance → milestones released
one at a time → final release closes the job, moves the freelancer's job
count, and unlocks their trust bond → both sides review each other. All of
that moves in single Firestore transactions, so a double-tapped Hire or
Release cannot pay twice.

## Getting started

**No Firebase project needed** — the emulator suite gives you real Auth and
Firestore locally, seeded with four verified demo accounts:

```bash
./scripts/dev_emulator.sh
# then, in a second terminal:
cd app && flutter run --dart-define=FELICEK_EMULATORS=true
```

**With a real project** — one command, then one console click to enable
Email/Password sign-in:

```bash
./scripts/setup_firebase.sh
```

**Build an APK** — installs the Android SDK if it's missing:

```bash
./scripts/build_apk.sh          # debug
./scripts/build_apk.sh release  # signed release
```

Details in [docs/SETUP.md](docs/SETUP.md) and [docs/RELEASE.md](docs/RELEASE.md).

## Free-tier posture

Everything runs on Firebase's free **Spark** plan: Auth + Firestore only. No
Cloud Functions (Blaze-only), no Cloud Storage (Blaze-only for new projects).
The design decisions that keep it there are called out in comments where they
matter:

- Profile photos are downsized to ~480px JPEG and stored as base64 on the
  profile document instead of in Cloud Storage.
- Read receipts are chat-level watermarks, not per-message arrays.
- Search runs off denormalised `searchTerms` prefix arrays, not a paid search
  service.
- The spam filter is an on-device heuristic, not a hosted model.
- Notifications are Firestore documents written by the acting client, with
  rules restricting the exact shape — no Functions needed.
- APKs are served from GitHub Releases (no bandwidth cap) rather than
  Firebase Hosting (360 MB/day free).

At ~12 users this sits far inside the free quotas. The scaling path when that
changes: Blaze plan, Cloud Functions for notification fan-out and payment
reconciliation, Cloud Storage for media, and a TURN server for calls behind
strict NATs.

## Play Store readiness

Built to Play-grade standards — release signing, R8 minification, scoped
`FileProvider`, runtime permissions, no cleartext traffic, `targetSdk` current
— but distributed from a website first, per the brief. For a Play submission:

```bash
flutter build appbundle --release --dart-define=FELICEK_SELF_UPDATE=false
```

and remove `REQUEST_INSTALL_PACKAGES` from the manifest — self-updating
violates Play policy. The updater is fully gated behind that flag.

## Verification

```bash
cd app && flutter analyze && flutter test        # 0 issues, 63 tests
cd firebase/tests && npm install && npm test     # 61 rules tests
```

The rules suite runs against a throwaway Firestore emulator — no project, no
login, no network. It is what actually verifies the security guarantees above:
that a client cannot mark its own payment paid, that a job owner cannot read a
freelancer's full submission, that an applicant cannot read the answer key.
See [firebase/tests/README.md](firebase/tests/README.md).
