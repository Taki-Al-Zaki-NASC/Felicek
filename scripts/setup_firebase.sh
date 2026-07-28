#!/usr/bin/env bash
#
# One-command Firebase setup for Felicek.
#
#   ./scripts/setup_firebase.sh [project-id]
#
# Creates (or selects) a Firebase project, turns on Email/Password sign-in,
# writes app/android/app/google-services.json (plus the iOS/macOS plists),
# and deploys the Firestore rules and indexes.
#
# What this script CANNOT do for you: log in. Firebase projects belong to a
# Google account, so the first step is interactive by design — `firebase login`
# opens a browser. Everything after that is automated.
#
# Everything it enables is on the free Spark plan. No billing required.

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BOLD=$'\033[1m'; readonly DIM=$'\033[2m'; readonly RESET=$'\033[0m'
readonly GREEN=$'\033[32m'; readonly RED=$'\033[31m'; readonly YELLOW=$'\033[33m'

step() { printf '\n%s==> %s%s\n' "$BOLD" "$1" "$RESET"; }
ok()   { printf '%s  ✓ %s%s\n' "$GREEN" "$1" "$RESET"; }
warn() { printf '%s  ! %s%s\n' "$YELLOW" "$1" "$RESET"; }
die()  { printf '%s  ✗ %s%s\n' "$RED" "$1" "$RESET" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not installed. $2"
}

# ── 0. Prerequisites ────────────────────────────────────────────────────────
step "Checking prerequisites"
need flutter "Install from https://docs.flutter.dev/get-started/install"
need node    "Install Node.js 18+ from https://nodejs.org"

if ! command -v firebase >/dev/null 2>&1; then
  warn "firebase-tools not found — installing globally"
  npm install -g firebase-tools
fi
ok "firebase-tools $(firebase --version)"

if ! command -v flutterfire >/dev/null 2>&1; then
  warn "flutterfire_cli not found — installing"
  dart pub global activate flutterfire_cli
  export PATH="$PATH:$HOME/.pub-cache/bin"
fi
command -v flutterfire >/dev/null 2>&1 \
  || die "flutterfire is still not on PATH. Add \$HOME/.pub-cache/bin to your PATH and re-run."
ok "flutterfire ready"

# ── 1. Login ────────────────────────────────────────────────────────────────
step "Signing in to Firebase"
if firebase projects:list >/dev/null 2>&1; then
  ok "Already signed in"
else
  firebase login
fi

# ── 2. Project ──────────────────────────────────────────────────────────────
PROJECT_ID="${1:-}"
if [[ -z "$PROJECT_ID" ]]; then
  step "Choose a project"
  firebase projects:list || true
  printf '\nEnter a project id to use, or a NEW id to create one: '
  read -r PROJECT_ID
fi
[[ -n "$PROJECT_ID" ]] || die "A project id is required."

step "Preparing project '$PROJECT_ID'"
if firebase projects:list 2>/dev/null | grep -qE "[[:space:]]${PROJECT_ID}[[:space:]]"; then
  ok "Using existing project"
else
  warn "Creating new project"
  firebase projects:create "$PROJECT_ID" --display-name "Felicek" \
    || die "Could not create '$PROJECT_ID'. The id may be taken — try another."
  ok "Created"
fi

printf '{\n  "projects": {\n    "default": "%s"\n  }\n}\n' "$PROJECT_ID" \
  > "$ROOT/firebase/.firebaserc"
ok "Wrote firebase/.firebaserc"

# ── 3. Firestore ────────────────────────────────────────────────────────────
step "Provisioning Firestore"
if firebase firestore:databases:list --project "$PROJECT_ID" 2>/dev/null | grep -q '(default)'; then
  ok "Firestore database already exists"
else
  warn "Creating the default Firestore database (nam5 / multi-region US)"
  firebase firestore:databases:create '(default)' \
    --project "$PROJECT_ID" --location nam5 \
    || warn "Automatic creation failed — create it once in the console, then re-run this script."
fi

# ── 4. Platform config ──────────────────────────────────────────────────────
step "Generating platform config (google-services.json etc.)"
(
  cd "$ROOT/app"
  flutterfire configure \
    --project "$PROJECT_ID" \
    --platforms=android,ios,macos \
    --android-package-name app.felicek.felicek \
    --ios-bundle-id app.felicek.felicek \
    --macos-bundle-id app.felicek.felicek \
    --yes
)
[[ -f "$ROOT/app/android/app/google-services.json" ]] \
  && ok "app/android/app/google-services.json written" \
  || warn "google-services.json missing — check the flutterfire output above"

# ── 5. Rules + indexes ──────────────────────────────────────────────────────
step "Deploying Firestore rules and indexes"
(
  cd "$ROOT/firebase"
  firebase deploy --only firestore:rules,firestore:indexes --project "$PROJECT_ID"
)
ok "Rules and indexes deployed"

# ── 6. Auth (the one manual step) ───────────────────────────────────────────
step "Enable Email/Password sign-in"
cat <<EOF
  The Firebase CLI has no command to toggle a sign-in provider, so this last
  step is a console click:

    ${BOLD}https://console.firebase.google.com/project/$PROJECT_ID/authentication/providers${RESET}

    Authentication -> Sign-in method -> Email/Password -> Enable -> Save

  (If you see "Get started" first, click it once.)
EOF

step "Done"
cat <<EOF
  Next:
    cd app && flutter run

  To develop with no cloud project at all, use the emulator instead:
    ./scripts/dev_emulator.sh
EOF
