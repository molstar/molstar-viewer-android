#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

CHANNEL="${1:-candidate}"
BUILD_TYPE="${2:-debug}"
ARTIFACT_OUTPUT_DIR="${ARTIFACT_OUTPUT_DIR:-$ROOT/artifacts/$CHANNEL-$BUILD_TYPE}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"
ALLOW_UNSIGNED_RELEASE="${ALLOW_UNSIGNED_RELEASE:-0}"

case "$CHANNEL" in stable|candidate) ;; *) echo "channel must be stable or candidate" >&2; exit 1 ;; esac
case "$BUILD_TYPE" in debug|release) ;; *) echo "build type must be debug or release" >&2; exit 1 ;; esac

# shellcheck source=scripts/lib/node-env.sh
source "$ROOT/scripts/lib/node-env.sh"
require_node_lts "$ROOT"
# shellcheck source=scripts/lib/android-env.sh
source "$ROOT/scripts/lib/android-env.sh"
resolve_android_sdk "$ROOT"
# shellcheck source=scripts/lib/signing-env.sh
source "$ROOT/scripts/lib/signing-env.sh"

if [[ "$BUILD_TYPE" == "release" ]] && ! signing_env_complete && [[ "$ALLOW_UNSIGNED_RELEASE" != "1" ]]; then
  echo "release builds require the complete MOLSTAR_ANDROID signing environment" >&2
  exit 1
fi

if [[ "$SKIP_VERIFY" != "1" ]]; then
  VERIFY_BUILD=never "$ROOT/scripts/verify.sh"
fi

capitalize() {
  local value="$1"
  printf '%s%s' "${value:0:1}" "${value:1}" | awk '{ print toupper(substr($0,1,1)) substr($0,2) }'
}
CHANNEL_CAP="$(capitalize "$CHANNEL")"
TYPE_CAP="$(capitalize "$BUILD_TYPE")"
VARIANT="$CHANNEL_CAP$TYPE_CAP"
TASK=":app:assemble$VARIANT"
# This is the entry point CI uses, and it calls verify.sh without a build, so the
# unit tests have to be requested here too or they never run on a pull request.
# AGP generates unit test tasks for debug variants only, and these tests are plain
# JVM logic that does not vary by build type, so a release build runs the same
# channel's debug unit tests.
TEST_TASK=":app:test${CHANNEL_CAP}DebugUnitTest"

./gradlew --no-daemon "$TEST_TASK" "$TASK"

METADATA="$ROOT/app/build/outputs/apk/$CHANNEL/$BUILD_TYPE/output-metadata.json"
[[ -s "$METADATA" ]] || {
  METADATA="$(find "$ROOT/app/build/outputs/apk" -type f -path "*/$CHANNEL/$BUILD_TYPE/output-metadata.json" -print -quit 2>/dev/null || true)"
}
[[ -n "$METADATA" && -s "$METADATA" ]] || { echo "output-metadata.json not found for $VARIANT" >&2; exit 1; }

mapfile -t META < <(node --input-type=module - "$METADATA" <<'NODE'
import fs from 'node:fs';
const metadata = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const element = metadata.elements?.[0];
if (!element?.outputFile) throw new Error('APK output metadata has no outputFile');
const values = [
  metadata.applicationId || element.applicationId || '',
  String(element.versionCode ?? ''),
  String(element.versionName ?? ''),
  element.outputFile,
];
for (const value of values) process.stdout.write(`${value}\n`);
NODE
)
APPLICATION_ID="${META[0]:-}"
VERSION_CODE="${META[1]:-}"
VERSION_NAME="${META[2]:-}"
OUTPUT_FILE="${META[3]:-}"
[[ -n "$APPLICATION_ID" && "$VERSION_CODE" =~ ^[0-9]+$ && -n "$VERSION_NAME" && -n "$OUTPUT_FILE" ]] || {
  echo "invalid APK output metadata" >&2
  exit 1
}
APK="$(dirname "$METADATA")/$OUTPUT_FILE"
[[ -s "$APK" ]] || { echo "APK not found: $APK" >&2; exit 1; }

rm -rf "$ARTIFACT_OUTPUT_DIR"
mkdir -p "$ARTIFACT_OUTPUT_DIR"
SAFE_VERSION="$(printf '%s' "$VERSION_NAME" | tr -cs 'A-Za-z0-9._-' '-')"
ARTIFACT_APK="molstar-android-viewer-$CHANNEL-$BUILD_TYPE-$SAFE_VERSION.apk"
cp "$APK" "$ARTIFACT_OUTPUT_DIR/$ARTIFACT_APK"
cp "$METADATA" "$ARTIFACT_OUTPUT_DIR/output-metadata.json"
unzip -t "$ARTIFACT_OUTPUT_DIR/$ARTIFACT_APK" > "$ARTIFACT_OUTPUT_DIR/apk-unzip-test.txt"

SIGNED=false
CERT_SHA256=""
APKSIGNER="$(resolve_android_build_tool apksigner)"
if "$APKSIGNER" verify --verbose --print-certs "$ARTIFACT_OUTPUT_DIR/$ARTIFACT_APK" > "$ARTIFACT_OUTPUT_DIR/apksigner.txt" 2>&1; then
  SIGNED=true
  CERT_SHA256="$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' "$ARTIFACT_OUTPUT_DIR/apksigner.txt" | head -n 1 | tr -d ':[:space:]')"
else
  if [[ "$BUILD_TYPE" == "debug" || "$ALLOW_UNSIGNED_RELEASE" != "1" ]]; then
    cat "$ARTIFACT_OUTPUT_DIR/apksigner.txt" >&2
    exit 1
  fi
fi

APK_SHA256="$(sha256sum "$ARTIFACT_OUTPUT_DIR/$ARTIFACT_APK" | awk '{print $1}')"
SOURCE_HEAD="$(git rev-parse HEAD)"
SOURCE_TREE="$(git rev-parse HEAD^{tree})"
SOURCE_DIRTY=false
if [[ -n "$(git status --porcelain)" ]]; then
  SOURCE_DIRTY=true
  TMP_INDEX="$(mktemp)"
  rm -f "$TMP_INDEX"
  GIT_INDEX_FILE="$TMP_INDEX" git read-tree HEAD
  GIT_INDEX_FILE="$TMP_INDEX" git add -A
  SOURCE_TREE="$(GIT_INDEX_FILE="$TMP_INDEX" git write-tree)"
  rm -f "$TMP_INDEX"
fi
MOLSTAR_VERSION="$(tr -d '[:space:]' < app/src/main/assets/viewer/vendor/molstar/VERSION)"
HOST_VERSION_NAME="$(sed -n 's/^HOST_VERSION_NAME=//p' version.properties)"
HOST_VERSION_CODE="$(sed -n 's/^HOST_VERSION_CODE=//p' version.properties)"
VENDOR_SHA256="$(sha256sum app/src/main/assets/viewer/vendor/molstar/SHA256SUMS | awk '{print $1}')"

node --input-type=module - \
  "$ARTIFACT_OUTPUT_DIR/artifact-manifest.json" \
  "$CHANNEL" "$BUILD_TYPE" "$VARIANT" "$APPLICATION_ID" "$VERSION_CODE" "$VERSION_NAME" \
  "$MOLSTAR_VERSION" "$HOST_VERSION_NAME" "$HOST_VERSION_CODE" "$SOURCE_HEAD" "$SOURCE_TREE" \
  "$SOURCE_DIRTY" "$ARTIFACT_APK" "$APK_SHA256" "$SIGNED" "$CERT_SHA256" "$VENDOR_SHA256" <<'NODE'
import fs from 'node:fs';
const [
  output, channel, buildType, variant, applicationId, versionCode, versionName,
  molstarVersion, hostVersionName, hostVersionCode, sourceHead, sourceTree,
  sourceDirty, apkFile, apkSha256, signed, certificateSha256, vendorManifestSha256,
] = process.argv.slice(2);
const manifest = {
  schemaVersion: 1,
  createdAt: new Date().toISOString(),
  channel,
  buildType,
  variant,
  applicationId,
  versionCode: Number(versionCode),
  versionName,
  molstarVersion,
  hostVersionName,
  hostVersionCode: Number(hostVersionCode),
  sourceHead,
  sourceTree,
  sourceDirty: sourceDirty === 'true',
  apkFile,
  apkSha256,
  signed: signed === 'true',
  certificateSha256: certificateSha256 || null,
  vendorManifestSha256,
};
fs.writeFileSync(output, `${JSON.stringify(manifest, null, 2)}\n`);
NODE

node scripts/ci/verify-artifact.mjs "$ARTIFACT_OUTPUT_DIR/artifact-manifest.json"
(
  cd "$ARTIFACT_OUTPUT_DIR"
  sha256sum "$ARTIFACT_APK" artifact-manifest.json output-metadata.json > SHA256SUMS
)

cat <<STATUS
===== final status =====
BUILD_RC=0
CHANNEL=$CHANNEL
BUILD_TYPE=$BUILD_TYPE
VARIANT=$VARIANT
APPLICATION_ID=$APPLICATION_ID
VERSION_CODE=$VERSION_CODE
VERSION_NAME=$VERSION_NAME
MOLSTAR_VERSION=$MOLSTAR_VERSION
SIGNED=$SIGNED
CERTIFICATE_SHA256=${CERT_SHA256:-none}
APK=$ARTIFACT_OUTPUT_DIR/$ARTIFACT_APK
APK_SHA256=$APK_SHA256
ARTIFACT_MANIFEST=$ARTIFACT_OUTPUT_DIR/artifact-manifest.json
STATUS
