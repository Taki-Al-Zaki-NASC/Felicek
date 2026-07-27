# Auto-update for a website-distributed APK

Felicek ships from a website, not the Play Store, so it carries its own
updater. This is what "auto update happens when an update comes" means in
practice, and — just as importantly — what it cannot mean.

## The flow

1. **Check.** On launch (and at most every 6 hours, plus on demand from
   Settings → Check for updates) the app fetches
   `https://<site>/update.json` with a cache-busting query param.
2. **Compare.** Only `versionCode` is compared, against the running build's
   own `buildNumber` read via `package_info_plus` — not a constant someone
   might forget to bump.
3. **Stage.** `rolloutPercent` is honoured using a per-install bucket stored
   in `SharedPreferences`, so a bad build reaches 10% of people rather than
   everyone, and the same devices stay in the same bucket across checks.
4. **Download.** Streamed to app-private storage with live progress; the
   previous staged APK is deleted first.
5. **Verify.** SHA-256 of the downloaded file is compared to the manifest's
   `sha256`. A mismatch deletes the file and reports an error — a truncated
   or tampered download is never handed to the installer.
6. **Install.** The verified file is passed to Android's package installer
   through a `FileProvider` URI (`InstallerPlugin.kt`).

## The honest limitation

**Android will still show its own install confirmation.** Outside a
device-owner/enterprise deployment, no app can silently replace itself — that
is an OS-level guarantee, not something a library can work around, and any
"fully silent self-update" claim for a normal sideloaded app is wrong.

So: detection, download, checksum verification and queuing are automatic. The
user taps once on a system dialog. For a mandatory build the app blocks behind
a non-dismissible prompt until that tap happens.

The first time, Android also asks the user to allow "install unknown apps"
for Felicek. `UpdateService.canInstallPackages()` detects that state and
`openInstallPermissionSettings()` deep-links into the right Settings page
instead of failing silently.

## Manifest fields

| Field | Meaning |
|---|---|
| `versionCode` | Integer. The only thing compared. Must increase every release. |
| `versionName` | Human-facing, e.g. `1.2.0`. |
| `apkUrl` | HTTPS only — enforced by `UpdateManifest.isValid`. |
| `sha256` | Lowercase hex. Verified before install. |
| `sizeBytes` | Shown in the update sheet. |
| `releaseNotes` | Shown in the update sheet. |
| `mandatory` | Blocks the app until installed. |
| `minSupportedVersionCode` | Anything at or below this is force-updated. |
| `rolloutPercent` | Staged rollout, 1–100. |

## Signing

Android refuses an update signed with a different key than the installed
build. That makes the release keystore load-bearing:

- **Lose it** → every existing install is stranded; users must uninstall and
  reinstall, losing local state.
- **Leak it** → anyone can ship a "Felicek update" that users' phones will
  accept.

Keep it in a password manager and in `KEYSTORE_BASE64` as a repository
secret. It is git-ignored (`*.jks`, `app/android/key.properties`), and the
release workflow fails loudly rather than falling back to the debug key.

## Releasing

```bash
# 1. Bump BOTH parts in app/pubspec.yaml — the build number is the versionCode
#    and must increase:  version: 1.2.0+7
# 2. Tag and push. CI does the rest.
git tag v1.2.0 && git push origin v1.2.0
```

CI builds and signs the APK, computes its SHA-256, publishes a GitHub Release
(unlimited bandwidth — the free Firebase Hosting tier would run out after a
handful of downloads), rewrites `website/update.json`, and deploys the site to
GitHub Pages. The manifest step refuses to publish a `versionCode` that
doesn't increase.

## Turning it off for a Play Store build

Play policy prohibits self-updating. For a Play build:

```bash
flutter build appbundle --release --dart-define=FELICEK_SELF_UPDATE=false
```

and remove `REQUEST_INSTALL_PACKAGES` from `AndroidManifest.xml`. The updater
is fully gated behind `AppConfig.selfUpdateEnabled`.
