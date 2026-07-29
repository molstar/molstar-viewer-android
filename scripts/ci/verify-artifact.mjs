#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const manifestPath = process.argv[2];
if (!manifestPath) throw new Error('Usage: verify-artifact.mjs <artifact-manifest.json>');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const required = [
    'schemaVersion', 'channel', 'buildType', 'variant', 'applicationId',
    'versionCode', 'versionName', 'molstarVersion', 'sourceHead', 'sourceTree',
    'apkFile', 'apkSha256', 'signed',
];
for (const key of required) {
    if (manifest[key] === undefined || manifest[key] === null || manifest[key] === '') {
        throw new Error(`Artifact manifest is missing ${key}`);
    }
}
if (manifest.schemaVersion !== 1) throw new Error(`Unsupported artifact schema ${manifest.schemaVersion}`);
if (!['stable', 'candidate'].includes(manifest.channel)) throw new Error('Invalid channel');
if (!['debug', 'release'].includes(manifest.buildType)) throw new Error('Invalid build type');
const expectedBase = 'io.github.daylight00.molstarandroid';
if (manifest.channel === 'stable' && manifest.buildType === 'release' && manifest.applicationId !== expectedBase) {
    throw new Error('Stable release applicationId is incorrect');
}
if (manifest.channel === 'candidate' && manifest.buildType === 'release' && manifest.applicationId !== `${expectedBase}.candidate`) {
    throw new Error('Candidate release applicationId is incorrect');
}
if (manifest.channel === 'candidate' && manifest.buildType === 'debug' && manifest.applicationId !== `${expectedBase}.candidate.debug`) {
    throw new Error('Candidate debug applicationId is incorrect');
}
if (!Number.isInteger(manifest.versionCode) || manifest.versionCode <= 0) throw new Error('Invalid versionCode');
if (typeof manifest.signed !== 'boolean') throw new Error('signed must be boolean');
// The certificate digest is the app's permanent identity, so a signed artifact that
// cannot state it has lost the one fact its provenance record exists to carry.
if (manifest.signed && !/^[0-9a-f]{64}$/.test(manifest.certificateSha256 ?? '')) {
    throw new Error('signed artifact must record a 64 character signing certificate SHA-256');
}

const apkPath = path.resolve(path.dirname(manifestPath), manifest.apkFile);
const stat = fs.statSync(apkPath);
if (!stat.isFile() || stat.size === 0) throw new Error('APK is missing or empty');
const digest = crypto.createHash('sha256').update(fs.readFileSync(apkPath)).digest('hex');
if (digest !== manifest.apkSha256) throw new Error('APK SHA-256 does not match artifact manifest');

console.log(`Artifact manifest passed: ${manifest.variant} ${manifest.versionName}`);
