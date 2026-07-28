# Maintenance and releases

## Upstream Mol* updates

The vendored version is recorded in `app/src/main/assets/viewer/vendor/molstar/VERSION`. Replace it with:

```bash
bash scripts/sync-molstar-assets.sh <version>
bash scripts/verify.sh
```

The synchronization script downloads the npm release, replaces the complete prebuilt Viewer runtime, records provenance, and regenerates checksums. Do not edit vendored files by hand.

The compatibility checks cover only the public surface required by the host: `Viewer.create`, `viewer.loadFiles`, and the default and dark stylesheets. Nothing else in the Viewer API is used, so nothing else has to keep working for an update to be safe.

## Automation

| Workflow | Trigger | Result |
|---|---|---|
| `ci.yml` | push, pull request, manual | candidate debug artifact and emulator smoke evidence |
| `molstar-update.yml` | weekly, manual | emulator-verified upstream runtime pushed to `main` |
| `promote.yml` | manual | signed stable GitHub Release |

Workflow YAML remains thin; build, update, signing, and publication logic lives in repository scripts so it can also run locally.

Useful entry points:

```bash
bash scripts/ci/build-channel.sh candidate debug
bash scripts/ci/emulator-smoke.sh candidate debug
bash scripts/automation/prepare-molstar-update.sh latest
bash scripts/ci/simulate-actions.sh
bash scripts/release/prepare-release.sh
```

`emulator-smoke.sh` runs the same adb gate as the device scripts against any attached
emulator or device. CI runs it on a headless API 36 emulator, where SwiftShader supplies
the OpenGL ES 3.0 that Mol*'s WebGL2 renderer needs. It confirms that the Viewer reaches
`ready` and that a real structure file completes loading through an Android intent, but it
does not replace approval on a physical device before a stable release.

Automated upstream preparation is restricted to `app/src/main/assets/viewer/vendor/molstar/**`.

The update workflow builds a signed candidate, runs the emulator gate against it, and only
then pushes the new runtime to `main`. There is no update branch and no pull request, so the
workflow holds no pull request permission. The gate has to run inside that workflow rather
than in `ci.yml`, because a push made with `GITHUB_TOKEN` does not start another workflow.

This makes the gate load-bearing: it is the only check between an upstream release and
`main`. Removing it, or letting it pass without asserting the Viewer events, would leave
unattended updates unverified. `scripts/verify-automation-contract.mjs` therefore requires
the update workflow to invoke `scripts/ci/emulator-smoke.sh`.

## Signing and stable releases

Stable Android updates require the same application ID and long-lived signing identity. Candidate builds use a separate application ID so they can be installed beside stable.

Configure repository signing secrets from a trusted workstation with:

```bash
bash scripts/release/configure-github-signing.sh
```

The helper manages the permanent keystore outside the repository and configures the encrypted GitHub secrets expected by the workflows.

Stable promotion is manual. The workflow accepts only the full commit SHA currently at `main`, and that exact commit must first be installed and approved on a real Android device.

```bash
gh workflow run promote.yml \
  --repo "$(gh repo view --json nameWithOwner --jq .nameWithOwner)" \
  -f approved_commit="$(git rev-parse HEAD)"
```

Release outputs include the signed APK, artifact and release manifests, release notes, checksums, and signing-certificate identity.
