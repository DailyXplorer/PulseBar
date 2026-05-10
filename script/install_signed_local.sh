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
  # Optional: CODE_SIGN_IDENTITY="Apple Development: Name (ABCDE12345)"
  set -a
  # shellcheck disable=SC1090
  source "$LOCAL_SIGNING_ENV"
  set +a
fi

detect_team_id() {
  apple_issued_signing_identities \
    | cut -f2- \
    | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p' \
    | sort -u
}

detect_code_sign_identity() {
  apple_issued_signing_identities \
    | awk -F '\t' 'NR == 1 { print $2; exit }'
}

certificate_issuer() {
  local certificate_name="$1"

  security find-certificate -c "$certificate_name" -p 2>/dev/null \
    | openssl x509 -noout -issuer 2>/dev/null \
    || true
}

is_apple_issued_identity() {
  local certificate_name="$1"
  local issuer
  issuer="$(certificate_issuer "$certificate_name")"

  case "$issuer" in
    *"Apple Worldwide Developer Relations"*|*"Developer ID Certification Authority"*|*"Apple Development Certification Authority"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

apple_issued_signing_identities() {
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  while IFS= read -r line; do
    case "$line" in
      *"\"Apple Development:"*|*"\"Developer ID Application:"*) ;;
      *) continue ;;
    esac

    local sha
    local name
    sha="$(echo "$line" | sed -nE 's/^[[:space:]]*[0-9]+\)[[:space:]]+([A-F0-9]+)[[:space:]]+".*$/\1/p')"
    name="$(echo "$line" | sed -nE 's/^[[:space:]]*[0-9]+\)[[:space:]]+[A-F0-9]+[[:space:]]+"(.*)".*$/\1/p')"

    if [[ -n "$sha" && -n "$name" ]] && is_apple_issued_identity "$name"; then
      printf '%s\t%s\n' "$sha" "$name"
    fi
  done <<< "$identities"
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

if [[ "$CODE_SIGN_IDENTITY" != "Apple Development" && "$CODE_SIGN_IDENTITY" != "Developer ID Application" ]]; then
  if ! is_apple_issued_identity "$CODE_SIGN_IDENTITY"; then
    cat >&2 <<EOF
The selected signing identity is not issued by Apple:
  $CODE_SIGN_IDENTITY

PulseBar can be signed with a self-signed local certificate, but macOS
will still treat it differently from an Apple-issued development or distribution
identity. Use the default local build if you do not need Apple signing.
EOF
    exit 2
  fi
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

if [[ -z "$(apple_issued_signing_identities)" ]]; then
  cat >&2 <<'EOF'
No Apple-issued code signing identity was found in the keychain.

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
