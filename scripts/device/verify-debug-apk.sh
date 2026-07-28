#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export APP_ID="${APP_ID:-io.github.daylight00.molstarandroid.candidate.debug}"
export APK_PATH="${APK_PATH:-$(find "$ROOT/app/build/outputs/apk/candidate/debug" -maxdepth 1 -type f -name '*.apk' -print -quit 2>/dev/null || true)}"
exec "$ROOT/scripts/device/verify-apk.sh" "$APK_PATH"
