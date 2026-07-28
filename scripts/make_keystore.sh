#!/usr/bin/env bash
# Generate the Android release signing key and wire it up for local builds
# and for CI.
#
# Why this matters more than it looks: Android identifies an app by
# (package name + signing key). An update signed with a different key is
# rejected outright — the user has to uninstall first, losing local state.
# So this key is created once and then kept for the life of the app.
#
#   ./scripts/make_keystore.sh
#
# Produces app/android/felicek-release.jks and app/android/key.properties
# (both git-ignored), then prints exactly what to paste into GitHub secrets.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$ROOT/app/android"
KEYSTORE="$ANDROID_DIR/felicek-release.jks"
PROPS="$ANDROID_DIR/key.properties"
ALIAS="felicek"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

command -v keytool >/dev/null 2>&1 || die \
  "keytool not found. Install a JDK (17 or newer): apt install openjdk-17-jdk"

# Refusing to overwrite is the entire safety story here. Regenerating a
# keystore silently would strand every install already in the wild, and there
# is no recovery from that — the old key is simply gone.
if [ -e "$KEYSTORE" ]; then
  die "$KEYSTORE already exists.
     This is your signing key. Do NOT regenerate it — a new key cannot update
     any build signed with the old one. If you genuinely mean to start over,
     move the old file aside yourself first."
fi

bold "Felicek release signing key"
echo
echo "Choose a password. Use the same one for the store and the key — the"
echo "Android toolchain supports separate passwords, but nothing gains from it"
echo "and mismatched passwords are a common cause of confusing build failures."
echo

if [ -n "${FELICEK_KEYSTORE_PASSWORD:-}" ]; then
  # Non-interactive path, for provisioning from another script.
  PASSWORD="$FELICEK_KEYSTORE_PASSWORD"
else
  read -rsp "Password (min 6 characters): " PASSWORD; echo
  read -rsp "Confirm: " CONFIRM; echo
  [ "$PASSWORD" = "$CONFIRM" ] || die "passwords did not match"
fi
[ ${#PASSWORD} -ge 6 ] || die "keytool requires at least 6 characters"

DNAME="${FELICEK_KEYSTORE_DNAME:-CN=Felicek, OU=Felicek, O=Felicek, C=US}"

mkdir -p "$ANDROID_DIR"
keytool -genkeypair -v \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -storepass "$PASSWORD" \
  -keypass "$PASSWORD" \
  -dname "$DNAME" >/dev/null

chmod 600 "$KEYSTORE"

cat > "$PROPS" <<EOF
storePassword=$PASSWORD
keyPassword=$PASSWORD
keyAlias=$ALIAS
storeFile=$KEYSTORE
EOF
chmod 600 "$PROPS"

FINGERPRINT=$(keytool -list -v -keystore "$KEYSTORE" -alias "$ALIAS" \
  -storepass "$PASSWORD" 2>/dev/null | grep 'SHA256:' | head -1 | sed 's/^[[:space:]]*//')

echo
bold "Created"
echo "  $KEYSTORE"
echo "  $PROPS"
echo "  $FINGERPRINT"
echo
echo "Both are git-ignored. \`./scripts/build_apk.sh release\` will now produce"
echo "a properly signed, updatable APK."
echo

# base64 -w0 is GNU; macOS needs -i and wraps by default.
if base64 --help 2>&1 | grep -q -- '-w'; then
  B64=$(base64 -w0 "$KEYSTORE")
else
  B64=$(base64 -i "$KEYSTORE" | tr -d '\n')
fi

OUT="$ROOT/keystore-secrets.txt"
{
  echo "GitHub → Settings → Secrets and variables → Actions → New repository secret"
  echo
  echo "KEYSTORE_PASSWORD = $PASSWORD"
  echo "KEY_PASSWORD      = $PASSWORD"
  echo "KEY_ALIAS         = $ALIAS"
  echo
  echo "KEYSTORE_BASE64 ="
  echo "$B64"
} > "$OUT"
chmod 600 "$OUT"

bold "Next: add four repository secrets"
echo
echo "  The values are in: $OUT"
echo "  (git-ignored — delete it once the secrets are saved)"
echo
warn "Back up $KEYSTORE somewhere you would still have after losing this"
warn "machine — a password manager, not just this repo. There is no way to"
warn "regenerate it, and without it you can never ship an update again."
