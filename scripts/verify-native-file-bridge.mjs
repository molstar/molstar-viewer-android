#!/usr/bin/env node
import fs from 'node:fs';
import vm from 'node:vm';

const events = [];
const loadedBatches = [];

const roots = {
    app: {},
};

const context = {
    console,
    Blob,
    File,
    Date,
    Promise,
    JSON,
    String,
    Boolean,
    Array,
    Object,
    Error,
    CustomEvent: class {
        constructor(type, options) {
            this.type = type;
            this.detail = options.detail;
        }
    },
    document: {
        getElementById(id) {
            return roots[id] || null;
        },
    },
    fetch: async url => ({
        ok: true,
        status: 200,
        blob: async () => new Blob(
            [`transport:${url}`],
            { type: 'application/octet-stream' },
        ),
    }),
};

context.window = context;
context.dispatchEvent = event => events.push(event.detail);
context.MolAndroid = {
    postEvent(json) {
        events.push(JSON.parse(json));
    },
};
context.MolBoot = {
    markReady() {},
    fail(type, message) {
        throw new Error(`${type}: ${message}`);
    },
};
context.molstar = {
    version: 'bridge-contract-test',
    Viewer: {
        create: async () => ({
            loadFiles: async files => loadedBatches.push(files),
        }),
    },
};

vm.createContext(context);
vm.runInContext(
    fs.readFileSync('app/src/main/assets/viewer/customization.js', 'utf8'),
    context,
);
vm.runInContext(
    fs.readFileSync('app/src/main/assets/viewer/app-bridge.js', 'utf8'),
    context,
);
await new Promise(resolve => setTimeout(resolve, 0));

await context.MolApp.dispatch({
    type: 'open-files',
    payload: {
        batchId: 'contract-batch',
        files: [
            {
                url: 'https://appassets.androidplatform.net/native-files/contract-batch/0',
                name: 'density.map.gz',
                type: 'application/gzip',
            },
            {
                url: 'https://appassets.androidplatform.net/native-files/contract-batch/1',
                name: 'trajectory.xtc',
                type: 'application/octet-stream',
            },
        ],
    },
});

if (loadedBatches.length !== 1 || loadedBatches[0].length !== 2) {
    throw new Error('native file batch was not delegated intact to viewer.loadFiles()');
}
if (loadedBatches[0][0].name !== 'density.map.gz' || loadedBatches[0][1].name !== 'trajectory.xtc') {
    throw new Error('native file names were not preserved for Mol* format recognition');
}
if (!events.some(event => event.type === 'command-completed' && event.payload.batchId === 'contract-batch')) {
    throw new Error('native file completion event did not preserve the transport batch id');
}

console.log('Native file bridge contract passed.');
