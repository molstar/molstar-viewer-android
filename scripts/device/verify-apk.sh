#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APK_PATH="${APK_PATH:-${1:-}}"
FIXTURE="${FIXTURE:-$ROOT/scripts/device/fixtures/minimal-ala.pdb}"
APP_ID="${APP_ID:-io.github.daylight00.molstarandroid.candidate}"
# The launcher class stays in the Gradle namespace, which the candidate and debug
# applicationId suffixes do not share, so the "$APP_ID/.Class" shorthand cannot be used.
ACTIVITY="${ACTIVITY:-$APP_ID/io.github.daylight00.molstarandroid.MainActivity}"
WAIT_SECONDS="${WAIT_SECONDS:-45}"
KEEP_DEVICE_FIXTURE="${KEEP_DEVICE_FIXTURE:-0}"
UTC="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${EVIDENCE_DIR:-$HOME/Downloads/molstar-android-viewer-device-results/device-smoke-$UTC}"
REMOTE_NAME="molstar-android-smoke-$UTC.pdb"
REMOTE_PATH="/sdcard/Download/$REMOTE_NAME"
MEDIA_URI=""

[[ -n "$APK_PATH" ]] || {
  APK_PATH="$(find "$ROOT/app/build/outputs/apk/candidate/release" -maxdepth 1 -type f -name '*.apk' -print -quit 2>/dev/null || true)"
}

# shellcheck source=scripts/lib/android-env.sh
source "$ROOT/scripts/lib/android-env.sh"
resolve_android_sdk "$ROOT"
ADB="${ADB:-$ANDROID_SDK_ROOT/platform-tools/adb}"

for cmd in awk grep sed sha256sum unzip; do
  command -v "$cmd" >/dev/null || { echo "missing command: $cmd" >&2; exit 1; }
done
[[ -x "$ADB" ]] || { echo "adb not found: $ADB" >&2; exit 1; }
[[ -n "$APK_PATH" && -s "$APK_PATH" ]] || { echo "APK not found; pass its path or set APK_PATH" >&2; exit 1; }
[[ -s "$FIXTURE" ]] || { echo "device fixture not found: $FIXTURE" >&2; exit 1; }

mkdir -p "$EVIDENCE_DIR"
EVIDENCE_DIR="$(cd "$EVIDENCE_DIR" && pwd -P)"
RUN_LOG="$EVIDENCE_DIR/run.log"
exec > >(tee -a "$RUN_LOG") 2>&1

adb_cmd=("$ADB")
if [[ -n "${ANDROID_SERIAL:-}" ]]; then
  adb_cmd+=( -s "$ANDROID_SERIAL" )
else
  mapfile -t devices < <("$ADB" devices | awk 'NR > 1 && $2 == "device" { print $1 }')
  if [[ "${#devices[@]}" -ne 1 ]]; then
    printf 'expected exactly one authorized adb device, found %s\n' "${#devices[@]}" >&2
    "$ADB" devices -l >&2 || true
    exit 1
  fi
  adb_cmd+=( -s "${devices[0]}" )
fi

serial="$("${adb_cmd[@]}" get-serialno | tr -d '\r')"
cleanup() {
  if [[ "$KEEP_DEVICE_FIXTURE" != "1" ]]; then
    if [[ -n "$MEDIA_URI" ]]; then
      "${adb_cmd[@]}" shell content delete --uri "$MEDIA_URI" >/dev/null 2>&1 || true
    fi
    "${adb_cmd[@]}" shell rm -f "$REMOTE_PATH" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

wait_for_log() {
  local description="$1" first_pattern="$2" second_pattern="${3:-}"
  local deadline=$((SECONDS + WAIT_SECONDS))
  while (( SECONDS < deadline )); do
    "${adb_cmd[@]}" logcat -d -v threadtime MolstarAndroid:D '*:S' > "$EVIDENCE_DIR/logcat-current.txt" 2>&1 || true
    if grep -F "$first_pattern" "$EVIDENCE_DIR/logcat-current.txt" >/dev/null 2>&1; then
      if [[ -z "$second_pattern" ]] || grep -F "$first_pattern" "$EVIDENCE_DIR/logcat-current.txt" | grep -F "$second_pattern" >/dev/null 2>&1; then
        printf 'observed: %s\n' "$description"
        return 0
      fi
    fi
    sleep 1
  done
  printf 'timed out waiting for: %s\n' "$description" >&2
  return 1
}

# adb shell cannot delegate a Storage Access Framework document grant it does not
# already hold, so the fixture is published through MediaStore and opened by its
# media URI. This still exercises the content:// path the app sees from a file manager.
resolve_media_uri() {
  local deadline=$((SECONDS + WAIT_SECONDS)) id
  while (( SECONDS < deadline )); do
    "${adb_cmd[@]}" shell content call --uri content://media/external \
      --method scan_file --arg "$REMOTE_PATH" >/dev/null 2>&1 || true
    id="$("${adb_cmd[@]}" shell content query --uri content://media/external/downloads \
      --projection _id:_display_name 2>/dev/null | tr -d '\r' |
      awk -F', ' -v name="$REMOTE_NAME" '
        {
          row_id = ""; display = ""
          for (i = 1; i <= NF; i++) {
            field = $i
            if (field ~ /_id=/) { sub(/.*_id=/, "", field); row_id = field }
            else if (field ~ /_display_name=/) { sub(/.*_display_name=/, "", field); display = field }
          }
          if (display == name && row_id != "") { print row_id; exit }
        }')"
    if [[ -n "$id" ]]; then
      printf 'content://media/external/downloads/%s\n' "$id"
      return 0
    fi
    sleep 1
  done
  printf 'timed out waiting for MediaStore to index: %s\n' "$REMOTE_PATH" >&2
  return 1
}

printf 'DEVICE_SERIAL=%s\n' "$serial"
"${adb_cmd[@]}" shell getprop > "$EVIDENCE_DIR/device-getprop.txt"
"${adb_cmd[@]}" shell cmd webviewupdate getCurrentWebViewPackage > "$EVIDENCE_DIR/webview-provider.txt" 2>&1 || true
"${adb_cmd[@]}" install -r "$APK_PATH" | tee "$EVIDENCE_DIR/adb-install.txt"
"${adb_cmd[@]}" logcat -c
"${adb_cmd[@]}" shell am force-stop "$APP_ID"
"${adb_cmd[@]}" shell am start -W -n "$ACTIVITY" | tee "$EVIDENCE_DIR/launch-main.txt"
wait_for_log 'Mol* viewer ready event' '"type":"ready"'

"${adb_cmd[@]}" push "$FIXTURE" "$REMOTE_PATH" | tee "$EVIDENCE_DIR/adb-push.txt"
MEDIA_URI="$(resolve_media_uri)"
printf 'MEDIA_URI=%s\n' "$MEDIA_URI" | tee "$EVIDENCE_DIR/media-uri.txt"
"${adb_cmd[@]}" shell am start -W \
  -a android.intent.action.VIEW -d "$MEDIA_URI" -t chemical/x-pdb \
  -f 0x00000001 -n "$ACTIVITY" | tee "$EVIDENCE_DIR/launch-structure.txt"
wait_for_log 'native PDB file completion' '"type":"command-completed"' '"type":"open-files"'

"${adb_cmd[@]}" logcat -d -v threadtime > "$EVIDENCE_DIR/logcat-full.txt"
"${adb_cmd[@]}" logcat -d -v threadtime MolstarAndroid:D '*:S' > "$EVIDENCE_DIR/logcat-app.txt"
if grep -F '"type":"error"' "$EVIDENCE_DIR/logcat-app.txt" >/dev/null 2>&1; then
  echo 'viewer emitted an error event' >&2
  exit 1
fi
"${adb_cmd[@]}" exec-out screencap -p > "$EVIDENCE_DIR/screenshot.png"
"${adb_cmd[@]}" shell dumpsys activity top > "$EVIDENCE_DIR/dumpsys-activity-top.txt" 2>&1 || true
"${adb_cmd[@]}" shell dumpsys package "$APP_ID" > "$EVIDENCE_DIR/dumpsys-package.txt" 2>&1 || true
cp "$FIXTURE" "$EVIDENCE_DIR/fixture.pdb"
printf '%s  %s\n' "$(sha256sum "$APK_PATH" | awk '{print $1}')" "$(basename "$APK_PATH")" > "$EVIDENCE_DIR/apk.sha256"
printf '%s  fixture.pdb\n' "$(sha256sum "$FIXTURE" | awk '{print $1}')" > "$EVIDENCE_DIR/fixture.sha256"
unzip -t "$APK_PATH" > "$EVIDENCE_DIR/apk-unzip-test.txt"

cat > "$EVIDENCE_DIR/status.env" <<STATUS
DEVICE_RC=0
DEVICE_SERIAL=$serial
APP_ID=$APP_ID
ACTIVITY=$ACTIVITY
MEDIA_URI=$MEDIA_URI
APK_PATH=$APK_PATH
APK_SHA256=$(sha256sum "$APK_PATH" | awk '{print $1}')
FIXTURE_SHA256=$(sha256sum "$FIXTURE" | awk '{print $1}')
READY_EVENT=1
OPEN_FILES_EVENT=1
VIEWER_ERROR_EVENT=0
EVIDENCE_DIR=$EVIDENCE_DIR
STATUS
cat "$EVIDENCE_DIR/status.env"
