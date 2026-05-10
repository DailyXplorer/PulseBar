#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PulseBar"
LEGACY_APP_NAME="MissionBar"
SCHEME="PulseBar"
CONFIGURATION="Debug"
BUNDLE_ID="com.dailyxplorer.pulsebar"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/PulseBar.xcodeproj"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData/PulseBar-Codex}"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

usage() {
  echo "usage: $0 [run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify]" >&2
}

stop_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -x "$LEGACY_APP_NAME" >/dev/null 2>&1 || true
}

build_app() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build
}

verify_signature() {
  codesign --verify --strict --verbose=2 "$APP_BUNDLE"
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

stop_app
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    verify_signature
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    usage
    exit 2
    ;;
esac
