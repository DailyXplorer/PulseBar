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
  /usr/bin/open -n "$APP_BUNDLE" --args "$@"
}

find_app_pid() {
  local pid
  local executable

  while read -r pid; do
    [[ -n "$pid" ]] || continue
    executable="$(ps -p "$pid" -o comm= 2>/dev/null || true)"

    if [[ "$executable" == "$APP_BINARY" ]]; then
      printf '%s\n' "$pid"
      return 0
    fi
  done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)

  return 1
}

show_verification_logs() {
  /usr/bin/log show \
    --last 2m \
    --info \
    --style compact \
    --predicate "subsystem == \"$BUNDLE_ID\"" 2>/dev/null \
    | tail -n 80 >&2 || true
}

verify_running_interface() {
  local report_file
  local pid=""
  local attempt
  local ready=""
  local report_pid=""
  local report_bundle=""

  report_file="$(mktemp "${TMPDIR:-/tmp}/pulsebar-health.XXXXXX")"

  open_app --pulsebar-smoke-report "$report_file"

  for attempt in {1..100}; do
    pid="$(find_app_pid || true)"
    if [[ -n "$pid" && -s "$report_file" ]]; then
      ready="$(plutil -extract ready raw -o - "$report_file" 2>/dev/null || true)"
      report_pid="$(plutil -extract processIdentifier raw -o - "$report_file" 2>/dev/null || true)"
      report_bundle="$(plutil -extract bundlePath raw -o - "$report_file" 2>/dev/null || true)"
      if [[ "$ready" == "true" && "$report_pid" == "$pid" && "$report_bundle" == "$APP_BUNDLE" ]]; then
        printf 'PulseBar ready (pid %s, verified interface presentation).\n' "$pid"
        rm -f "$report_file"
        return 0
      fi
    fi

    sleep 0.1
  done

  echo "PulseBar did not report a ready status item and visible interface." >&2
  if [[ -s "$report_file" ]]; then
    plutil -p "$report_file" >&2 || true
  fi
  show_verification_logs
  rm -f "$report_file"
  return 1
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
    verify_running_interface
    ;;
  *)
    usage
    exit 2
    ;;
esac
