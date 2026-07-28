#!/usr/bin/env node
import fs from 'node:fs';

const indexPath = 'app/src/main/assets/viewer/index.html';
const bridgePath = 'app/src/main/assets/viewer/app-bridge.js';
const customizationPath = 'app/src/main/assets/viewer/customization.js';
const diagnosticsPath = 'app/src/main/assets/viewer/boot-diagnostics.js';
const themePath = 'app/src/main/assets/viewer/theme-controller.js';
const vendorPath = 'app/src/main/assets/viewer/vendor/molstar/molstar.js';

const index = fs.readFileSync(indexPath, 'utf8');
const bridge = fs.readFileSync(bridgePath, 'utf8');
const customization = fs.readFileSync(customizationPath, 'utf8');
const diagnostics = fs.readFileSync(diagnosticsPath, 'utf8');
const theme = fs.readFileSync(themePath, 'utf8');
const vendor = fs.readFileSync(vendorPath, 'utf8');

function requireMatch(condition, message) {
    if (!condition) throw new Error(message);
}

const cspMatch = index.match(/Content-Security-Policy"\s+content="([^"]+)"/s);
const csp = cspMatch ? cspMatch[1] : '';
requireMatch(csp.includes("script-src 'self'"), 'CSP must restrict scripts to the app origin');

if (vendor.includes('new Function') || vendor.includes('eval(')) {
    requireMatch(csp.includes("'unsafe-eval'"), 'Mol* bundle uses generated JavaScript; CSP must allow unsafe-eval');
}
if (vendor.includes('WebAssembly')) {
    requireMatch(
        csp.includes("'wasm-unsafe-eval'") || csp.includes("'unsafe-eval'"),
        'Mol* bundle uses WebAssembly; CSP must allow wasm evaluation',
    );
}

const themeIndex = index.indexOf('src="theme-controller.js"');
const diagnosticsIndex = index.indexOf('src="boot-diagnostics.js"');
const vendorIndex = index.indexOf('src="vendor/molstar/molstar.js"');
const customizationIndex = index.indexOf('src="customization.js"');
const bridgeIndex = index.indexOf('src="app-bridge.js"');
requireMatch(themeIndex >= 0, 'theme controller script is missing');
requireMatch(diagnosticsIndex > themeIndex, 'theme controller must run before viewer boot diagnostics');
requireMatch(vendorIndex > diagnosticsIndex, 'boot diagnostics must load before Mol*');
requireMatch(customizationIndex > vendorIndex, 'customization must load after the upstream Mol* bundle');
requireMatch(bridgeIndex > customizationIndex, 'platform bridge must load after customization');
requireMatch(/#app\s*\{[^}]*position:\s*absolute;[^}]*inset:\s*0;/s.test(index), '#app must establish a full-viewport positioned container');
requireMatch(diagnostics.includes("window.addEventListener('error'"), 'global JavaScript error capture is missing');
requireMatch(diagnostics.includes("window.addEventListener('unhandledrejection'"), 'promise rejection capture is missing');
requireMatch(bridge.includes('window.molstar.Viewer.create'), 'bridge must guard and invoke the viewer API through window.molstar');
requireMatch(vendor.includes('loadFiles('), 'upstream Mol* bundle must expose the Viewer loadFiles capability');
requireMatch(bridge.includes('viewer.loadFiles(files)'), 'native files must be delegated to Mol* loadFiles()');
requireMatch(bridge.includes("'open-files'"), 'native multi-file bridge command is missing');
requireMatch(bridge.includes("emit('ready'"), 'bridge must expose the ready event');
requireMatch(!bridge.includes('layoutShowLog'), 'mobile customization must not be embedded in the platform bridge');
const optionsMatch = customization.match(/const viewerOptions = Object\.freeze\(\{([\s\S]*?)\}\);/);
requireMatch(optionsMatch, 'customization viewerOptions object is missing');
const optionKeys = [...optionsMatch[1].matchAll(/^\s*([A-Za-z_$][\w$]*)\s*:/gm)].map(match => match[1]);
requireMatch(
    optionKeys.length === 1 && optionKeys[0] === 'layoutShowLog',
    `layoutShowLog must be the only active custom Viewer option; found: ${optionKeys.join(', ') || 'none'}`,
);
requireMatch(customization.includes('layoutShowLog: false'), 'minimal mobile customization must hide the non-live log panel');
requireMatch(!customization.includes('viewportShowExpand'), 'Mol* browser expansion control must use the upstream default');
requireMatch(/<div id="boot-status"[^>]*\shidden(?:\s|>)/.test(index), 'boot diagnostic surface must be hidden during normal startup');
requireMatch(index.includes('role="alert"'), 'boot diagnostic surface must be error-only alert semantics');
requireMatch(!index.includes('Starting Mol*'), 'custom loading screen must remain disabled');
requireMatch(diagnostics.includes('Normal startup is intentionally silent'), 'boot diagnostics must document silent normal startup');
requireMatch(index.includes('vendor/molstar/theme/dark.css'), 'official Mol* dark stylesheet is missing');
requireMatch(theme.includes('getSystemTheme'), 'theme controller must read the Android system theme');
requireMatch(theme.includes('MolTheme'), 'theme controller must expose the stable theme adapter');

console.log('Viewer layer contract passed.');
