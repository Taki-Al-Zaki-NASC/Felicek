#!/usr/bin/env bash
#
# Build a Felicek APK, installing the Android SDK first if it isn't there.
#
#   ./scripts/build_apk.sh              # debug APK (no signing key needed)
#   ./scripts/build_apk.sh release      # release APK (needs android/key.properties)
#
# Exists because "install the Android SDK" is otherwise a page of clicking.
# Everything it fetches comes from dl.google.com; on a network that blocks
# that host the script says so plainly instead of failing halfway through.

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly MODE="${1:-debug}"
readonly BOLD=$'\033[1m'; readonly RESET=$'\033[0m'
readonly GREEN=$'\033[32m'; readonly YELLOW=$'\033[33m'; readonly RED=$'\033[31m'

step() { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$RESET"; }
ok()   { printf '%s  ✓ %s%s\n' "$GREEN" "$1" "$RESET"; }
warn() { printf '%s  ! %s%s\n' "$YELLOW" "$1" "$RESET"; }
die()  { printf '%s  ✗ %s%s\n' "$RED" "$1" "$RESET" >&2; exit 1; }

[[ "$MODE" == "debug" || "$MODE" == "release" ]] \
  || die "Usage: $0 [debug|release]"

# ── Java ────────────────────────────────────────────────────────────────────
step "Checking Java"
command -v java >/dev/null || die "Java 17+ is required. Install Temurin 17 or 21."
JAVA_MAJOR="$(java -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')"
[[ "$JAVA_MAJOR" -ge 17 ]] || die "Java $JAVA_MAJOR found; Android Gradle Plugin needs 17+."
ok "Java $JAVA_MAJOR"

# ── Android SDK ─────────────────────────────────────────────────────────────
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

step "Checking the Android SDK at $ANDROID_HOME"
if [[ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]]; then
  warn "Not found — installing the command-line tools"

  if ! curl -sSI --max-time 20 -o /dev/null https://dl.google.com/android/repository/ 2>/dev/null; then
    die "Cannot reach dl.google.com, which hosts the Android SDK.
     If you are behind a corporate proxy or a restricted network, either
     allow that host or install Android Studio once on an unrestricted
     machine. Nothing in this repository needs changing — the build itself
     is fine, only the SDK download is blocked."
  fi

  ZIP_URL="https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip"
  case "$(uname -s)" in
    Darwin) ZIP_URL="https://dl.google.com/android/repository/commandlinetools-mac-13114758_latest.zip" ;;
  esac

  mkdir -p "$ANDROID_HOME/cmdline-tools"
  TMP="$(mktemp -d)"
  curl -# -L -o "$TMP/cmdline.zip" "$ZIP_URL"
  unzip -q "$TMP/cmdline.zip" -d "$TMP"
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mv "$TMP/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rm -rf "$TMP"
  ok "Command-line tools installed"
fi

export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

step "Accepting licenses and installing SDK packages"
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager --install \
  "platform-tools" \
  "platforms;android-36" \
  "build-tools;36.0.0" >/dev/null
ok "SDK packages ready"

# ── Flutter ─────────────────────────────────────────────────────────────────
step "Checking Flutter"
command -v flutter >/dev/null || die "flutter is not installed. https://docs.flutter.dev/get-started/install"
flutter config --android-sdk "$ANDROID_HOME" >/dev/null
ok "$(flutter --version 2>/dev/null | head -1)"

# ── Firebase config ─────────────────────────────────────────────────────────
step "Checking Firebase config"
if [[ -f "$ROOT/app/android/app/google-services.json" ]]; then
  if grep -q '"demo-felicek"' "$ROOT/app/android/app/google-services.json"; then
    warn "Using the EMULATOR-ONLY config — this build will not talk to a real backend."
    warn "Run ./scripts/setup_firebase.sh for a real project."
  else
    ok "google-services.json present"
  fi
else
  warn "No google-services.json — the build will still succeed, but the app will"
  warn "show its 'Firebase is not configured' screen at launch."
  warn "Fix with: ./scripts/setup_firebase.sh"
fi

# ── Signing ─────────────────────────────────────────────────────────────────
if [[ "$MODE" == "release" ]]; then
  step "Checking release signing"
  if [[ -f "$ROOT/app/android/key.properties" ]]; then
    ok "key.properties found"
  else
    warn "No android/key.properties — Gradle will fall back to the DEBUG key."
    warn "A debug-signed APK cannot update an existing install (Android rejects"
    warn "a different signing key). Fine for testing, never for the website."
    warn "See app/android/key.properties.example."
  fi
fi

# ── Build ───────────────────────────────────────────────────────────────────
step "Building the $MODE APK"
cd "$ROOT/app"
flutter pub get
if [[ "$MODE" == "release" ]]; then
  flutter build apk --release \
    --dart-define=FELICEK_SITE="${FELICEK_SITE:-https://felicek.app}" \
    --dart-define=FELICEK_UPDATE_MANIFEST="${FELICEK_UPDATE_MANIFEST:-https://felicek.app/update.json}" \
    --dart-define=FELICEK_PAYMENT_CHECKOUT_URL="${FELICEK_PAYMENT_CHECKOUT_URL:-https://pay.felicek.app/checkout}"
  APK="build/app/outputs/flutter-apk/app-release.apk"
else
  flutter build apk --debug
  APK="build/app/outputs/flutter-apk/app-debug.apk"
fi

step "Done"
ls -lh "$APK"
if command -v sha256sum >/dev/null; then
  printf '  sha256 %s\n' "$(sha256sum "$APK" | awk '{print $1}')"
elif command -v shasum >/dev/null; then
  printf '  sha256 %s\n' "$(shasum -a 256 "$APK" | awk '{print $1}')"
fi
printf '\n  Install on a connected device:\n    adb install -r %s/app/%s\n\n' "$ROOT" "$APK"
