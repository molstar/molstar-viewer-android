#!/usr/bin/env node
import fs from 'node:fs';

const read = path => fs.readFileSync(path, 'utf8');
const build = read('app/build.gradle.kts');
const manifest = read('app/src/main/AndroidManifest.xml');
const verify = read('scripts/verify.sh');
const release = read('scripts/release/prepare-release.sh');
const publish = read('scripts/release/publish-github-release.sh');
const update = read('scripts/automation/prepare-molstar-update.sh');
const scope = read('scripts/automation/verify-update-scope.sh');
const version = read('scripts/ci/github-version-env.sh');
const ciWorkflow = read('.github/workflows/ci.yml');
const updateWorkflow = read('.github/workflows/molstar-update.yml');
const promoteWorkflow = read('.github/workflows/promote.yml');

function requireMatch(condition, message) {
    if (!condition) throw new Error(message);
}
function requireOfficialActions(workflow, name) {
    for (const action of ['actions/checkout@v7', 'actions/setup-node@v7', 'actions/setup-java@v5', 'actions/upload-artifact@v7']) {
        if (action.includes('setup-java') && name === 'Molstar update' && !workflow.includes(action)) continue;
        requireMatch(workflow.includes(action), `${name} must use ${action}`);
    }
    requireMatch(!workflow.includes('pull_request_target'), `${name} must not use pull_request_target`);
}

requireMatch(build.includes('create("stable")'), 'stable product flavor is missing');
requireMatch(build.includes('create("candidate")'), 'candidate product flavor is missing');
requireMatch(build.includes('applicationIdSuffix = ".candidate"'), 'candidate application ID isolation is missing');
requireMatch(build.includes('MOLSTAR_ANDROID_KEYSTORE_FILE'), 'environment-driven signing contract is missing');
requireMatch(build.includes('MOLSTAR_ANDROID_VERSION_CODE'), 'environment-driven version code is missing');
requireMatch(manifest.includes('android:label="${appLabel}"'), 'variant application label placeholder is missing');
requireMatch(verify.includes('VERIFY_VARIANT'), 'verification must target an explicit Android variant');
requireMatch(release.includes('RELEASE_READY=1'), 'release preparation status contract is missing');
requireMatch(publish.includes('PUBLISH_DRY_RUN'), 'release publication dry-run contract is missing');
requireMatch(publish.includes('gh release create'), 'GitHub Release publication command is missing');
requireMatch(update.includes('verify-update-scope.sh'), 'automated Molstar update scope gate is missing');
requireMatch(scope.includes('app/src/main/assets/viewer/vendor/molstar/*'), 'update scope is not restricted to Layer 1');
requireMatch(version.includes('1000000000'), 'stable GitHub version-code band is missing');
requireMatch(version.includes('1100000000'), 'candidate GitHub version-code band is missing');
requireMatch(fs.existsSync('scripts/ci/simulate-actions.sh'), 'local Actions simulation is missing');
requireMatch(fs.existsSync('scripts/release/configure-github-signing.sh'), 'GitHub signing setup helper is missing');
requireMatch(fs.existsSync('docs/maintenance.md'), 'maintenance documentation is missing');

requireOfficialActions(ciWorkflow, 'CI workflow');
requireOfficialActions(updateWorkflow, 'Molstar update');
requireOfficialActions(promoteWorkflow, 'promotion workflow');
requireMatch(ciWorkflow.includes('contents: read'), 'CI workflow must remain read-only');
requireMatch(ciWorkflow.includes('scripts/ci/build-channel.sh candidate debug'), 'CI must build the bounded candidate debug artifact');
requireMatch(updateWorkflow.includes("cron: '17 3 * * 1'"), 'scheduled Molstar update cadence is missing');
requireMatch(updateWorkflow.includes('contents: write'), 'update workflow cannot push the verified update');
requireMatch(!updateWorkflow.includes('pull-requests:'), 'update workflow must not hold pull request permission it no longer uses');
requireMatch(updateWorkflow.includes('scripts/ci/emulator-smoke.sh'), 'update workflow must gate the candidate on the runtime smoke test before pushing to main');
requireMatch(updateWorkflow.includes('scripts/automation/prepare-molstar-update.sh'), 'update workflow must delegate to the repository update script');
requireMatch(updateWorkflow.includes('app/src/main/assets/viewer/vendor/molstar'), 'update workflow must stage only the upstream vendor layer');
requireMatch(promoteWorkflow.includes('workflow_dispatch'), 'stable promotion must be manual');
requireMatch(promoteWorkflow.includes('approved_commit'), 'stable promotion must require the device-approved commit SHA');
requireMatch(promoteWorkflow.includes('contents: write'), 'stable promotion requires release publication permission');
requireMatch(promoteWorkflow.includes('scripts/release/publish-github-release.sh'), 'promotion workflow must delegate release publication');

console.log('Automation and GitHub Actions contract passed.');
