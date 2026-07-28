# Felicek — setup

Three parts:

- **`app/`** — the Flutter client (Android, iOS, macOS, Windows).
- **`firebase/`** — Firestore security rules, indexes and their test suite.
  Auth + Firestore only, both on the free **Spark** plan.
- **`website/`** — the download page and the `update.json` manifest the app
  polls for in-app updates.

There are two ways to get running. Pick one.

---

## Option A — no Firebase project at all (fastest)

The Firebase emulator suite gives you real Auth and Firestore locally. A
project id starting with `demo-` makes the SDK refuse to contact production,
so nothing leaves your machine and nothing is billable.

```bash
./scripts/dev_emulator.sh
```

That installs `firebase-tools` if needed, drops the emulator-only
`google-services.json` into place, starts the emulators, and seeds four
verified demo accounts plus three listings. Then, in a second terminal:

```bash
cd app && flutter run --dart-define=FELICEK_EMULATORS=true
```

Sign in as any of:

| Email | Role |
|---|---|
| `sadia@felicek.test` | Verified freelancer (has a profile photo) |
| `finnova@felicek.test` | Verified individual client, one open listing |
| `devcraft@felicek.test` | Verified agency |
| `nimbus@felicek.test` | Verified startup, quiz-challenge listing |

Password for all four: `felicek123`.

On a **physical** Android device the emulator host has to be your computer's
LAN IP rather than the Android-emulator loopback alias:

```bash
flutter run --dart-define=FELICEK_EMULATORS=true \
            --dart-define=FELICEK_EMULATOR_HOST=192.168.1.42
```

---

## Option B — a real Firebase project

```bash
./scripts/setup_firebase.sh            # prompts for a project id
./scripts/setup_firebase.sh my-felicek # or name one up front
```

The script signs you in, creates or selects the project, provisions Firestore,
generates `google-services.json` (plus the iOS/macOS plists) via `flutterfire`,
and deploys the rules and indexes.

**One step it can't do for you:** enabling Email/Password sign-in. The Firebase
CLI has no command for toggling a sign-in provider, so the script prints the
console link and you click once:

> Authentication → Sign-in method → Email/Password → Enable → Save

Then:

```bash
cd app && flutter run
```

### Doing it by hand

<details>
<summary>If you'd rather not run the script</summary>

1. [console.firebase.google.com](https://console.firebase.google.com) → Add
   project. Spark (free) is enough.
2. Authentication → Sign-in method → enable **Email/Password**.
3. Firestore Database → Create database → production mode.
4. Add an Android app with package name `app.felicek.felicek`, download
   `google-services.json` into `app/android/app/`.
5. Deploy the rules:
   ```bash
   cd firebase
   cp .firebaserc.example .firebaserc   # edit in your project id
   firebase deploy --only firestore:rules,firestore:indexes
   ```

Instead of `google-services.json` you can inject config at build time — see
`app/lib/firebase_options.dart` for the `--dart-define` names.
</details>

---

## Building an APK

```bash
./scripts/build_apk.sh            # debug — no signing key needed
./scripts/build_apk.sh release    # release
```

The script installs the Android SDK command-line tools and the needed
platform/build-tools if they aren't present, accepts the licenses, points
Flutter at the SDK, and builds. It fetches from `dl.google.com`; on a network
that blocks that host it says so rather than failing halfway through.

For release signing, see [RELEASE.md](RELEASE.md). Without
`app/android/key.properties` the build falls back to the debug key — fine for
your own device, never for the website, because Android refuses an update
signed with a different key.

---

## Payments

Deposits, posting balances and top-ups are handled by a **dedicated external
payment gateway**, never inside the app. [PAYMENTS.md](PAYMENTS.md) covers the
split between what ships here and the webhook you deploy — and why that
boundary is a security requirement rather than a shortcut.

Until the webhook exists, no account can clear verification. That is the
intended behaviour: "no account without a real payment" would be meaningless
if the app could grant it to itself.

For local development, flip a `paymentIntents/{ref}` document to
`status: "paid"` in the emulator UI (<http://127.0.0.1:4000>) — the same
privileged write the webhook makes.

---

## Tests

```bash
cd app && flutter analyze && flutter test    # 0 issues, 52 tests
cd firebase/tests && npm install && npm test # 48 rules tests
```

The rules suite runs against a throwaway Firestore emulator and needs no
Firebase project. It is what verifies the security guarantees — read
[firebase/tests/README.md](../firebase/tests/README.md) for what each one
pins down.
