#!/usr/bin/env bash
set -euo pipefail

# Runs the adb runtime smoke gate against whichever emulator or device is attached.
# Kept out of workflow YAML so the same gate can be reproduced locally.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

CHANNEL="${1:-candidate}"
BUILD_TYPE="${2:-debug}"

case "$CHANNEL" in stable|candidate) ;; *) echo "channel must be stable or candidate" >&2; exit 1 ;; esac
case "$BUILD_TYPE" in debug|release) ;; *) echo "build type must be debug or release" >&2; exit 1 ;; esac

APP_ID="io.github.daylight00.molstarandroid"
if [[ "$CHANNEL" == "candidate" ]]; then
  APP_ID="$APP_ID.candidate"
fi
if [[ "$BUILD_TYPE" == "debug" ]]; then
  APP_ID="$APP_ID.debug"
fi

APK="${APK_PATH:-}"
if [[ -z "$APK" ]]; then
  APK="$(find "$ROOT/app/build/outputs/apk/$CHANNEL/$BUILD_TYPE" -maxdepth 1 -type f -name '*.apk' -print -quit 2>/dev/null || true)"
fi
[[ -n "$APK" && -s "$APK" ]] || {
  echo "$CHANNEL $BUILD_TYPE APK not found; build it first or set APK_PATH" >&2
  exit 1
}

export APP_ID
export EVIDENCE_DIR="${EVIDENCE_DIR:-$ROOT/artifacts/emulator-smoke}"
# Software rendering needs more headroom than a physical device.
export WAIT_SECONDS="${WAIT_SECONDS:-120}"

exec "$ROOT/scripts/device/verify-apk.sh" "$APK"
