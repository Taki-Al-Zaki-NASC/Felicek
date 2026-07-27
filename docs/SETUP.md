# Felicek — setup

This repo has three parts:

- **`app/`** — the Flutter client (Android, iOS, macOS, Windows).
- **`firebase/`** — Firestore security rules and indexes (Auth + Firestore
  only, both on the free **Spark** plan — nothing here requires a paid plan).
- **`website/`** — the public download page and the `update.json` manifest
  the app polls for in-app updates.

## 1. Create the Firebase project

1. [console.firebase.google.com](https://console.firebase.google.com) → Add
   project. The Spark (free) plan is enough for everything in this repo.
2. **Authentication** → Sign-in method → enable **Email/Password**.
3. **Firestore Database** → Create database → start in production mode (the
   rules in `firebase/firestore.rules` replace the defaults).
4. Add an Android app in Project settings, package name `app.felicek.felicek`
   (or whatever you set with `flutter create --org` if you changed it), and
   download `google-services.json` into `app/android/app/`.
5. If you also build iOS/macOS, add those apps too and download
   `GoogleService-Info.plist` into `app/ios/Runner/` and
   `app/macos/Runner/`.

## 2. Deploy Firestore rules and indexes

```bash
cd firebase
cp .firebaserc.example .firebaserc   # then edit in your project id
firebase deploy --only firestore:rules,firestore:indexes
```

The rules file is heavily commented — it's the actual enforcement of every
"mandatory" claim the product makes (no account without ID + deposit, no job
owner ever reading a freelancer's full challenge answer, no client-side write
that marks a payment as received). Read it before changing anything.

## 3. Point the app at your project

Either:

- Drop `google-services.json` into `app/android/app/` (recommended — no code
  changes needed), **or**
- Build with `--dart-define` values (`FIREBASE_API_KEY`, `FIREBASE_APP_ID`,
  `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID`, `FIREBASE_STORAGE_BUCKET`) —
  see `app/lib/firebase_options.dart`.

## 4. Payment gateway

Deposits, job-posting balances and wallet top-ups are handled by a **separate,
dedicated payment gateway** — never simulated inside the app. See
`docs/PAYMENTS.md` for exactly what that integration needs to do; it is
infrastructure you deploy alongside a real payment provider (Stripe,
SSLCommerz, a local MFS aggregator, etc.), not Dart source in this repo.

Until that's wired up, set `FELICEK_PAYMENT_CHECKOUT_URL` to a placeholder —
the app will open it, but no account can actually clear verification without
a webhook confirming a real payment. That is intentional, not a bug: it is
the whole point of the "no account without a real payment" requirement.

## 5. Run it

```bash
cd app
flutter pub get
flutter run   # or: flutter run -d macos / -d windows / -d chrome (not supported, no web target)
```

For the emulator suite instead of a live project:

```bash
firebase emulators:start --project demo-felicek   # from firebase/
flutter run --dart-define=FELICEK_EMULATORS=true  # from app/
```

## 6. Building a release APK

See `docs/RELEASE.md` and `.github/workflows/release.yml` — CI builds a
signed APK, computes its SHA-256, publishes a GitHub Release, and updates
`website/update.json` so every installed copy of the app offers the update
automatically (see `docs/UPDATER.md`).
