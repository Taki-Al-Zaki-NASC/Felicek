#!/usr/bin/env bash
#
# Run Felicek end to end with NO Firebase project at all.
#
#   ./scripts/dev_emulator.sh            # emulators + seed data, then instructions
#   ./scripts/dev_emulator.sh --run      # …and launch the app on a connected device
#
# The Firebase emulator suite gives you real Auth and Firestore locally. A
# project id starting with "demo-" makes the SDK refuse to contact production,
# so nothing leaves your machine and nothing is billable.
#
# This is the fastest path to a working app: no Google account, no project
# creation, no waiting on rules deployment.

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PROJECT="demo-felicek"
readonly BOLD=$'\033[1m'; readonly RESET=$'\033[0m'
readonly GREEN=$'\033[32m'; readonly YELLOW=$'\033[33m'; readonly RED=$'\033[31m'

step() { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$RESET"; }
ok()   { printf '%s  ✓ %s%s\n' "$GREEN" "$1" "$RESET"; }
warn() { printf '%s  ! %s%s\n' "$YELLOW" "$1" "$RESET"; }
die()  { printf '%s  ✗ %s%s\n' "$RED" "$1" "$RESET" >&2; exit 1; }

RUN_APP=false
[[ "${1:-}" == "--run" ]] && RUN_APP=true

step "Checking prerequisites"
command -v flutter >/dev/null || die "flutter is not installed."
command -v java >/dev/null    || die "Java 11+ is required by the Firestore emulator."
if ! command -v firebase >/dev/null 2>&1; then
  warn "firebase-tools not found — installing globally"
  npm install -g firebase-tools
fi
ok "prerequisites present"

# The Android build needs *a* google-services.json; the emulator-only one is
# safe to use because "demo-" project ids never reach production.
step "Installing emulator Firebase config"
DEST="$ROOT/app/android/app/google-services.json"
if [[ -f "$DEST" ]] && ! grep -q '"demo-felicek"' "$DEST"; then
  warn "A real google-services.json is already in place — leaving it alone."
  warn "The app will still use the emulators because of --dart-define below."
else
  cp "$ROOT/firebase/emulator/google-services.json" "$DEST"
  ok "Copied the emulator config into app/android/app/"
fi

step "Starting emulators and seeding demo data"
cat <<EOF
  Emulator UI:  ${BOLD}http://127.0.0.1:4000${RESET}
  Auth:         127.0.0.1:9099
  Firestore:    127.0.0.1:8080

  Demo accounts (password for all: ${BOLD}felicek123${RESET}):
    sadia@felicek.test    verified freelancer
    finnova@felicek.test  verified client (has an open listing)
    devcraft@felicek.test verified agency
    nimbus@felicek.test   verified startup

  Leave this running. In a second terminal:
    cd app && flutter run --dart-define=FELICEK_EMULATORS=true

  On a physical Android device, the emulator host must be your computer's LAN
  IP rather than the Android-emulator loopback alias:
    flutter run --dart-define=FELICEK_EMULATORS=true \\
                --dart-define=FELICEK_EMULATOR_HOST=192.168.x.x
EOF

if $RUN_APP; then
  step "Launching emulators, then the app"
  (
    cd "$ROOT/firebase"
    firebase emulators:exec --project "$PROJECT" --only auth,firestore \
      "node '$ROOT/scripts/seed_emulator.mjs' && cd '$ROOT/app' && flutter run --dart-define=FELICEK_EMULATORS=true"
  )
else
  (
    cd "$ROOT/firebase"
    firebase emulators:exec --project "$PROJECT" --only auth,firestore \
      "node '$ROOT/scripts/seed_emulator.mjs' && echo '' && echo 'Seeded. Press Ctrl-C when you are done.' && tail -f /dev/null"
  )
fi
