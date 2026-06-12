#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PulseBar"
SCHEME="PulseBar"
CONFIGURATION="${CONFIGURATION:-Release}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
RELEASE_IDENTITY="${RELEASE_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/PulseBar.xcodeproj"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData/PulseBar-Release}"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
LOCAL_SIGNING_ENV="$ROOT_DIR/.pulsebar-signing.env"
SUBMISSION_OUTPUT_FILE=""

if [[ -f "$LOCAL_SIGNING_ENV" ]]; then
  # Local-only convenience file, ignored by git.
  # Expected shape: DEVELOPMENT_TEAM=ABCDE12345
  # Optional: CODE_SIGN_IDENTITY="Developer ID Application: Name (ABCDE12345)"
  set -a
  # shellcheck disable=SC1090
  source "$LOCAL_SIGNING_ENV"
  set +a
fi

cleanup() {
  if [[ -n "$SUBMISSION_OUTPUT_FILE" && -f "$SUBMISSION_OUTPUT_FILE" ]]; then
    rm -f "$SUBMISSION_OUTPUT_FILE"
  fi
}

trap cleanup EXIT

fail() {
  printf '%s\n' "$1" >&2
  exit 2
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

developer_id_signing_identities() {
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  while IFS= read -r line; do
    case "$line" in
      *"\"Developer ID Application:"*) ;;
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

detect_team_id() {
  developer_id_signing_identities \
    | cut -f2- \
    | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p' \
    | sort -u
}

detect_release_identity() {
  developer_id_signing_identities \
    | awk -F '\t' 'NR == 1 { print $2; exit }'
}

identity_exists() {
  local identity="$1"

  developer_id_signing_identities \
    | awk -F '\t' -v identity="$identity" '$2 == identity { found = 1 } END { exit found ? 0 : 1 }'
}

preflight() {
  if ! xcrun notarytool --version >/dev/null 2>&1; then
    fail "xcrun notarytool is unavailable. Install Xcode 16 or select its command line tools with xcode-select."
  fi

  if [[ "$RELEASE_IDENTITY" == "Developer ID Application" ]]; then
    RELEASE_IDENTITY=""
  fi

  if [[ -z "$RELEASE_IDENTITY" && "$CODE_SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
    RELEASE_IDENTITY="$CODE_SIGN_IDENTITY"
  fi

  if [[ -n "$RELEASE_IDENTITY" && "$RELEASE_IDENTITY" != Developer\ ID\ Application:* ]]; then
    fail "Release notarization requires a Developer ID Application identity. Apple Development certificates cannot be notarized."
  fi

  if [[ -z "$RELEASE_IDENTITY" ]]; then
    RELEASE_IDENTITY="$(detect_release_identity)"
  fi

  if [[ -z "$RELEASE_IDENTITY" ]]; then
    cat >&2 <<'EOF'
No Developer ID Application signing identity was found in the keychain.

Apple Development certificates cannot be notarized. Install a "Developer ID
Application" certificate from an Apple Developer account, then re-run this
script.
EOF
    exit 2
  fi

  if ! identity_exists "$RELEASE_IDENTITY"; then
    cat >&2 <<EOF
The selected release signing identity was not found as an Apple-issued Developer ID Application certificate:
  $RELEASE_IDENTITY

Install the matching Developer ID Application certificate or unset RELEASE_IDENTITY to auto-detect one.
EOF
    exit 2
  fi

  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"

  if [[ -z "$DEVELOPMENT_TEAM" ]]; then
    local detected_team_ids
    local detected_team_count
    detected_team_ids="$(detect_team_id)"
    detected_team_count="$(echo "$detected_team_ids" | sed '/^$/d' | wc -l | tr -d ' ')"

    if [[ "$detected_team_count" == "1" ]]; then
      DEVELOPMENT_TEAM="$detected_team_ids"
      echo "Using detected Development Team: $DEVELOPMENT_TEAM"
    fi
  fi

  if [[ -z "$DEVELOPMENT_TEAM" ]]; then
    cat >&2 <<'EOF'
Missing DEVELOPMENT_TEAM.

Set your Apple Developer Team ID for the release build:
  DEVELOPMENT_TEAM=ABCDE12345 NOTARY_PROFILE=<name> ./script/notarize_release.sh

See the README "Publishing a Release" section for setup details.
EOF
    exit 2
  fi

  if [[ -z "$NOTARY_PROFILE" ]]; then
    cat >&2 <<'EOF'
Missing NOTARY_PROFILE.

Run:
  xcrun notarytool store-credentials <name> --apple-id <id> --team-id <team>

Then re-run with:
  NOTARY_PROFILE=<name> ./script/notarize_release.sh
EOF
    exit 2
  fi
}

build_release_app() {
  echo "Building $APP_NAME with Developer ID signing..."

  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$RELEASE_IDENTITY" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime"

  if [[ ! -d "$BUILT_APP" ]]; then
    printf 'Expected built app was not found: %s\n' "$BUILT_APP" >&2
    exit 1
  fi
}

verify_signature() {
  echo "Verifying Developer ID signature..."

  codesign --verify --strict --verbose=2 "$BUILT_APP"

  if ! codesign -dvv "$BUILT_APP" 2>&1 | grep -q "Developer ID Application"; then
    codesign -dvv "$BUILT_APP" 2>&1 | sed -n '1,20p' >&2
    printf 'The built app is not signed with a Developer ID Application identity.\n' >&2
    exit 1
  fi
}

package_app() {
  local zip_path="$1"

  mkdir -p "$DIST_DIR"
  rm -f "$zip_path"
  ditto -c -k --keepParent "$BUILT_APP" "$zip_path"
  echo "Created $zip_path"
}

notarize_zip() {
  local zip_path="$1"
  local submission_id

  echo "Submitting $zip_path for notarization..."
  SUBMISSION_OUTPUT_FILE="$(mktemp)"

  if ! xcrun notarytool submit "$zip_path" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | tee "$SUBMISSION_OUTPUT_FILE"; then
    submission_id="$(sed -nE 's/^[[:space:]]*id:[[:space:]]*([A-Za-z0-9-]+).*$/\1/p' "$SUBMISSION_OUTPUT_FILE" | tail -n 1)"
    printf 'Notarization failed.\n' >&2

    if [[ -n "$submission_id" ]]; then
      printf 'Review the Apple notary log with:\n  xcrun notarytool log %s --keychain-profile "%s"\n' "$submission_id" "$NOTARY_PROFILE" >&2
    else
      printf 'If a submission ID was printed above, review it with:\n  xcrun notarytool log <submission-id> --keychain-profile "%s"\n' "$NOTARY_PROFILE" >&2
    fi

    exit 1
  fi
}

staple_and_assess() {
  local assessment_output

  echo "Stapling notarization ticket..."
  xcrun stapler staple "$BUILT_APP"

  echo "Assessing stapled app with Gatekeeper..."
  if ! assessment_output="$(spctl --assess --type execute -vv "$BUILT_APP" 2>&1)"; then
    printf '%s\n' "$assessment_output" >&2
    printf 'Gatekeeper assessment failed.\n' >&2
    exit 1
  fi

  printf '%s\n' "$assessment_output"

  if ! grep -q "accepted" <<< "$assessment_output" || ! grep -q "source=Notarized Developer ID" <<< "$assessment_output"; then
    printf 'Gatekeeper assessment did not report "accepted" and "source=Notarized Developer ID".\n' >&2
    exit 1
  fi
}

preflight
build_release_app
verify_signature

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$BUILT_APP/Contents/Info.plist")"
ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"

package_app "$ZIP"
notarize_zip "$ZIP"
staple_and_assess
package_app "$ZIP"

echo "Notarized release zip: $ZIP"
