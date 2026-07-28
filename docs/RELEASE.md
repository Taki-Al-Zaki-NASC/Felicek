# Releasing

The short version:

```bash
# 1. Bump BOTH halves of the version in app/pubspec.yaml.
#    The number after "+" is the Android versionCode and MUST increase.
#      version: 1.2.0+7
#
# 2. Tag and push. CI does everything else.
git tag v1.2.0 && git push origin v1.2.0
```

CI then builds and signs the APK, runs analyze + tests + the Firestore rules
suite, computes the SHA-256, publishes a GitHub Release, rewrites
`website/update.json`, and deploys the site to GitHub Pages. Every installed
copy of the app picks the update up on its next check.

## One-time setup

### Signing key

Android refuses an update signed with a different key than the installed
build, so this key is load-bearing. **Lose it and every existing install is
stranded** (users must uninstall and reinstall, losing local state). **Leak it
and anyone can ship a "Felicek update" that phones will accept.**

```bash
keytool -genkey -v -keystore ~/felicek-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias felicek

# For CI:
base64 -w0 ~/felicek-release.jks   # macOS: base64 -i ~/felicek-release.jks
```

Store the keystore in a password manager, and keep an offline copy somewhere
you would still have after losing your laptop.

### Repository secrets

`Settings → Secrets and variables → Actions → Secrets`:

| Secret | Value |
|---|---|
| `KEYSTORE_BASE64` | The base64 blob printed above |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_PASSWORD` | Key password |
| `KEY_ALIAS` | `felicek` |
| `GOOGLE_SERVICES_JSON` | Contents of `app/android/app/google-services.json` |

And under **Variables** (not secrets — these are public in the built APK):

| Variable | Example |
|---|---|
| `FELICEK_SITE` | `https://felicek.app` |
| `FELICEK_PAYMENT_CHECKOUT_URL` | `https://pay.felicek.app/checkout` |

### GitHub Pages

`Settings → Pages → Source: Deploy from a branch → gh-pages / root`. The
release workflow pushes the `website/` directory there.

APKs go to **GitHub Releases**, not Pages — Releases has no bandwidth cap,
while the free Firebase Hosting tier would run out after roughly ten
downloads a day.

## Building locally

```bash
./scripts/build_apk.sh release
```

This installs the Android SDK if it is missing, then builds. Without
`app/android/key.properties` it falls back to the debug key and says so — fine
for testing on your own device, never for the website, because a debug-signed
build cannot update anyone's existing install.

## Release checklist

- [ ] `versionCode` (after the `+`) is higher than the last release. CI refuses
      a manifest that doesn't increase, but catch it earlier.
- [ ] `flutter analyze` clean, `flutter test` green, `npm test` in
      `firebase/tests` green.
- [ ] Firestore rules deployed if they changed —
      `cd firebase && firebase deploy --only firestore:rules`. **Deploy rules
      before the app build that depends on them**, or the new client will hit
      permission errors against the old rules.
- [ ] Release notes written in `website/update.json` (`releaseNotes` survives
      the CI rewrite).
- [ ] Installed the APK over the *previous* version on a real device, not just
      onto a clean one — that is the only way to catch a signing mismatch.

## Staged rollouts and forced updates

Run the release workflow manually (`Actions → Release APK → Run workflow`) to
set:

- **`rolloutPercent`** — offer the build to a slice of installs first. Each
  device keeps a stable bucket, so the same 10% keep getting it rather than
  the set churning on every check.
- **`mandatory`** — block the app behind a non-dismissible prompt until the
  update installs. Use for security fixes and breaking schema changes only.

To force-retire old builds without marking a release mandatory, edit
`minSupportedVersionCode` in `website/update.json` and commit; anything at or
below it is forced to update.

## Rolling back

There is no way to un-ship an APK someone already installed, and Android
refuses to downgrade to a lower `versionCode`. So a rollback is a
**roll-forward**:

1. Revert the bad commit.
2. Bump to a *higher* version (`1.2.1+8`).
3. Tag and push.
4. If the bad build is actively harmful, set `mandatory: true` so it is
   replaced immediately rather than on the next idle check.
