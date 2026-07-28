#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERIFY_BUILD="${VERIFY_BUILD:-auto}"
VERIFY_VARIANT="${VERIFY_VARIANT:-CandidateDebug}"

required=(
  .nvmrc
  version.properties
  app/src/main/assets/viewer/index.html
  app/src/main/assets/viewer/app-bridge.js
  app/src/main/assets/viewer/customization.js
  app/src/main/assets/viewer/boot-diagnostics.js
  app/src/main/assets/viewer/theme-controller.js
  app/src/main/assets/viewer/vendor/molstar/molstar.js
  app/src/main/assets/viewer/vendor/molstar/molstar.css
  app/src/main/assets/viewer/vendor/molstar/theme/dark.css
  app/src/main/assets/viewer/vendor/molstar/LICENSE
  app/src/main/assets/viewer/vendor/molstar/VERSION
  app/src/main/assets/viewer/vendor/molstar/UPSTREAM.json
  app/src/main/assets/viewer/vendor/molstar/SHA256SUMS
  app/src/test/java/io/github/daylight00/molstarandroid/NativeFileTransportTest.kt
  scripts/device/fixtures/minimal-ala.pdb
  scripts/device/verify-apk.sh
  scripts/device/verify-debug-apk.sh
  scripts/device/verify-candidate-apk.sh
  scripts/lib/node-env.sh
  scripts/lib/android-env.sh
  scripts/lib/signing-env.sh
  scripts/lib/version-env.sh
  scripts/verify-viewer-shell.mjs
  scripts/verify-native-file-bridge.mjs
  scripts/verify-automation-contract.mjs
  scripts/ci/build-channel.sh
  scripts/ci/ensure-android-sdk.sh
  scripts/ci/github-version-env.sh
  scripts/ci/verify-artifact.mjs
  scripts/ci/simulate-actions.sh
  scripts/ci/emulator-smoke.sh
  scripts/automation/check-molstar-update.mjs
  scripts/automation/verify-update-scope.sh
  scripts/automation/prepare-molstar-update.sh
  scripts/release/prepare-release.sh
  scripts/release/publish-github-release.sh
  scripts/release/configure-github-signing.sh
  .github/workflows/ci.yml
  .github/workflows/molstar-update.yml
  .github/workflows/promote.yml
  README.md
  CONTRIBUTING.md
  SECURITY.md
  .github/PULL_REQUEST_TEMPLATE.md
  .github/ISSUE_TEMPLATE/bug-report.yml
  .github/ISSUE_TEMPLATE/config.yml
  docs/android.md
  docs/architecture.md
  docs/maintenance.md
  scripts/verify-public-boundary.mjs
)
for path in "${required[@]}"; do
  [[ -s "$path" ]] || { echo "missing or empty: $path" >&2; exit 1; }
done

# shellcheck source=scripts/lib/node-env.sh
source "$ROOT/scripts/lib/node-env.sh"
require_node_lts "$ROOT"

for cmd in sha256sum grep diff find sort unzip; do
  command -v "$cmd" >/dev/null || { echo "missing command: $cmd" >&2; exit 1; }
done

node --check app/src/main/assets/viewer/app-bridge.js
node --check app/src/main/assets/viewer/customization.js
node --check app/src/main/assets/viewer/boot-diagnostics.js
node --check app/src/main/assets/viewer/theme-controller.js
node scripts/verify-viewer-shell.mjs
node scripts/verify-native-file-bridge.mjs
node scripts/verify-automation-contract.mjs
node scripts/verify-public-boundary.mjs
node --check scripts/ci/verify-artifact.mjs
node --check scripts/automation/check-molstar-update.mjs
for script in \
  scripts/lib/node-env.sh \
  scripts/lib/android-env.sh \
  scripts/lib/signing-env.sh \
  scripts/lib/version-env.sh \
  scripts/sync-molstar-assets.sh \
  scripts/device/install-debug-apk.sh \
  scripts/device/verify-apk.sh \
  scripts/device/verify-debug-apk.sh \
  scripts/device/verify-candidate-apk.sh \
  scripts/ci/build-channel.sh \
  scripts/ci/ensure-android-sdk.sh \
  scripts/ci/github-version-env.sh \
  scripts/ci/simulate-actions.sh \
  scripts/ci/emulator-smoke.sh \
  scripts/automation/verify-update-scope.sh \
  scripts/automation/prepare-molstar-update.sh \
  scripts/release/prepare-release.sh \
  scripts/release/publish-github-release.sh \
  scripts/release/configure-github-signing.sh; do
  bash -n "$script"
done
(
  cd app/src/main/assets/viewer/vendor/molstar
  sha256sum -c SHA256SUMS
  declared="$(mktemp)"
  actual="$(mktemp)"
  trap 'rm -f "$declared" "$actual"' EXIT
  awk '{ sub(/^\*/, "", $2); print $2 }' SHA256SUMS | sort > "$declared"
  find . -type f ! -name SHA256SUMS -print | sort > "$actual"
  diff -u "$declared" "$actual"
)

MAIN=app/src/main/java/io/github/daylight00/molstarandroid/MainActivity.kt
CONTRACT=app/src/main/java/io/github/daylight00/molstarandroid/ViewerContract.kt
MANIFEST=app/src/main/AndroidManifest.xml
BUILD=app/build.gradle.kts
BRIDGE=app/src/main/assets/viewer/app-bridge.js
CUSTOM=app/src/main/assets/viewer/customization.js
INDEX=app/src/main/assets/viewer/index.html

grep -q 'window.MolApp' "$BRIDGE"
grep -q 'viewer.loadFiles(files)' "$BRIDGE"
grep -q 'case '\''open-files'\''' "$BRIDGE"
grep -q 'WebViewAssetLoader' "$MAIN"
grep -q 'onShowFileChooser' "$MAIN"
grep -q 'WindowInsets.Type.systemBars()' "$MAIN"
grep -q 'WindowInsets.Type.displayCutout()' "$MAIN"
grep -q 'private lateinit var rootView: FrameLayout' "$MAIN"
grep -q 'rootView.addView(webView)' "$MAIN"
grep -q 'getSystemTheme' "$MAIN"
grep -q 'onConfigurationChanged' "$MAIN"
grep -q 'Intent.ACTION_SEND_MULTIPLE' "$MAIN"
grep -q 'ViewerContract.openFiles' "$MAIN"
grep -q 'resetNativeFileTransportDirectory' "$MAIN"
grep -q 'fun openFiles' "$CONTRACT"
grep -q 'fun openAlphaFold' "$CONTRACT"
grep -q 'layoutShowLog: false' "$CUSTOM"
if grep -q 'viewportShowExpand' "$CUSTOM"; then
  echo 'layoutShowLog must be the only active custom Viewer option' >&2
  exit 1
fi
grep -Eq '<div id="boot-status"[^>]* hidden' "$INDEX"
if grep -q 'Starting Mol\*' "$INDEX"; then
  echo 'custom loading screen must remain disabled' >&2
  exit 1
fi
grep -q 'android.intent.action.SEND_MULTIPLE' "$MANIFEST"
grep -q 'android:label="${appLabel}"' "$MANIFEST"
grep -q 'create("stable")' "$BUILD"
grep -q 'create("candidate")' "$BUILD"
grep -q 'applicationIdSuffix = ".candidate"' "$BUILD"

for workflow in .github/workflows/ci.yml .github/workflows/molstar-update.yml .github/workflows/promote.yml; do
  grep -q '^name:' "$workflow"
  grep -q '^on:' "$workflow"
  grep -q '^permissions:' "$workflow"
  if grep -q $'\t' "$workflow"; then
    echo "workflow YAML must not contain tabs: $workflow" >&2
    exit 1
  fi
done

if grep -Eq 'GZIPInputStream|detectStructureFile|inferFormat|lammps_traj_data|chemical/x-' "$MAIN" "$MANIFEST"; then
  echo 'Android integration must not duplicate Mol* format recognition or decompression' >&2
  exit 1
fi
if grep -q 'layoutShowLog' "$BRIDGE"; then
  echo 'custom Viewer options must stay in customization.js, not app-bridge.js' >&2
  exit 1
fi
if grep -q 'applySystemBarInsets(this)' "$MAIN"; then
  echo 'system insets must be applied to the outer host container, not the WebView' >&2
  exit 1
fi
grep -q 'android:windowNoTitle">true' app/src/main/res/values/styles.xml
if grep -q 'onCreateOptionsMenu' "$MAIN"; then
  echo 'persistent Android options menu must remain absent' >&2
  exit 1
fi
if find . -path './.git' -prune -o -type f \( -name '*.jks' -o -name '*.keystore' \) -print | grep -q .; then
  echo 'keystore files must not be tracked or stored in the repository' >&2
  exit 1
fi

do_build=0
case "$VERIFY_BUILD" in
  never) do_build=0 ;;
  auto)
    if [[ -x ./gradlew ]]; then
      # shellcheck source=scripts/lib/android-env.sh
      source "$ROOT/scripts/lib/android-env.sh"
      if resolve_android_sdk "$ROOT"; then do_build=1; fi
    fi
    ;;
  always)
    [[ -x ./gradlew ]] || { echo "Gradle wrapper is unavailable" >&2; exit 1; }
    # shellcheck source=scripts/lib/android-env.sh
    source "$ROOT/scripts/lib/android-env.sh"
    resolve_android_sdk "$ROOT"
    do_build=1
    ;;
  *) echo "VERIFY_BUILD must be auto, always, or never" >&2; exit 1 ;;
esac

case "$VERIFY_VARIANT" in
  StableDebug) variant_path=stable/debug ;;
  StableRelease) variant_path=stable/release ;;
  CandidateDebug) variant_path=candidate/debug ;;
  CandidateRelease) variant_path=candidate/release ;;
  *) echo "VERIFY_VARIANT must be StableDebug, StableRelease, CandidateDebug, or CandidateRelease" >&2; exit 1 ;;
esac

if [[ "$do_build" == "1" ]]; then
  # Unit tests need the SDK, so they run with the build rather than in the
  # static pass. They cover the transport rules that decide file names and which
  # directory may be deleted.
  ./gradlew --no-daemon ":app:test${VERIFY_VARIANT}UnitTest"
  TEST_RESULTS="app/build/test-results/test${VERIFY_VARIANT}UnitTest"
  [[ -d "$TEST_RESULTS" ]] && ls "$TEST_RESULTS"/*.xml >/dev/null 2>&1 || {
    echo "no unit test results were produced in $TEST_RESULTS" >&2
    exit 1
  }
  ./gradlew --no-daemon ":app:assemble$VERIFY_VARIANT"
  APK="$(find "app/build/outputs/apk/$variant_path" -maxdepth 1 -type f -name '*.apk' -print -quit 2>/dev/null || true)"
  [[ -n "$APK" && -s "$APK" ]] || { echo "$VERIFY_VARIANT APK was not produced" >&2; exit 1; }
  unzip -t "$APK" >/dev/null
  echo "Android build passed: $APK"
  sha256sum "$APK"
else
  echo "Static verification passed; Android build deferred."
fi
