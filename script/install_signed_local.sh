#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PulseBar"
SCHEME="PulseBar"
CONFIGURATION="${CONFIGURATION:-Release}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/PulseBar.xcodeproj"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData/PulseBar-Signed}"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"
LOCAL_SIGNING_ENV="$ROOT_DIR/.pulsebar-signing.env"

if [[ -f "$LOCAL_SIGNING_ENV" ]]; then
  # Local-only convenience file, ignored by git.
  # Expected shape: DEVELOPMENT_TEAM=ABCDE12345
  set -a
  # shellcheck disable=SC1090
  source "$LOCAL_SIGNING_ENV"
  set +a
fi

detect_team_id() {
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  echo "$identities" \
    | sed -nE 's/.*"(Apple Development|Developer ID Application):.*\(([A-Z0-9]{10})\)".*/\2/p' \
    | sort -u
}

detect_code_sign_identity() {
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  echo "$identities" \
    | sed -nE 's/.*"(Apple Development|Developer ID Application):.*/\1/p' \
    | awk '!seen[$0]++' \
    | head -n 1
}

TEAM_ID="${DEVELOPMENT_TEAM:-${1:-}}"

if [[ -z "$TEAM_ID" ]]; then
  detected_team_ids="$(detect_team_id)"
  detected_team_count="$(echo "$detected_team_ids" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [[ "$detected_team_count" == "1" ]]; then
    TEAM_ID="$detected_team_ids"
    echo "Using detected Development Team: $TEAM_ID"
  fi
fi

if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
  CODE_SIGN_IDENTITY="$(detect_code_sign_identity)"
fi

if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
  CODE_SIGN_IDENTITY="Apple Development"
fi

if [[ -z "$TEAM_ID" ]]; then
  cat >&2 <<'EOF'
Missing DEVELOPMENT_TEAM.

Set your Apple Development Team ID, for example:
  DEVELOPMENT_TEAM=ABCDE12345 ./script/install_signed_local.sh

Or create a local ignored file named .pulsebar-signing.env:
  DEVELOPMENT_TEAM=ABCDE12345

In Xcode, you can find it under the PulseBar target's Signing & Capabilities tab
after adding your Apple account in Xcode Settings > Accounts.
EOF
  exit 2
fi

if ! security find-identity -v -p codesigning | grep -E "Apple Development|Developer ID Application" >/dev/null; then
  cat >&2 <<'EOF'
No Apple code signing identity was found in the keychain.

The build will still ask Xcode to manage signing, but if it fails, open Xcode
Settings > Accounts, add your Apple ID, and create/download an Apple Development
certificate for this Mac.
EOF
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  build

rm -rf "$INSTALLED_APP"
ditto "$BUILT_APP" "$INSTALLED_APP"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f -R -trusted "$INSTALLED_APP"

codesign --verify --strict --verbose=2 "$INSTALLED_APP"
codesign -dvv "$INSTALLED_APP" 2>&1 | sed -n '1,12p'

open -n "$INSTALLED_APP"
echo "Installed and launched $INSTALLED_APP"
