#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PulseBar"
SCHEME="PulseBar"
CONFIGURATION="${CONFIGURATION:-Release}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development}"
TEAM_ID="${DEVELOPMENT_TEAM:-${1:-}}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/PulseBar.xcodeproj"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData/PulseBar-Signed}"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"

if [[ -z "$TEAM_ID" ]]; then
  cat >&2 <<'EOF'
Missing DEVELOPMENT_TEAM.

Set your Apple Development Team ID, for example:
  DEVELOPMENT_TEAM=ABCDE12345 ./script/install_signed_local.sh

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
