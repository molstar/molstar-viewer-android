(() => {
    'use strict';

    let viewer = null;

    function emit(type, payload = {}) {
        const detail = { type, payload, contractVersion: 1 };
        const event = JSON.stringify(detail);
        console.info(`[MolApp] ${type}`, payload);
        if (window.MolAndroid && typeof window.MolAndroid.postEvent === 'function') {
            window.MolAndroid.postEvent(event);
        }
        window.dispatchEvent(new CustomEvent('molapp-event', { detail }));
    }

    async function materializeNativeFiles(payload) {
        const descriptors = Array.isArray(payload && payload.files) ? payload.files : [];
        if (descriptors.length === 0) throw new Error('No native files were provided');
        if (typeof File !== 'function') throw new Error('This WebView does not support File objects');

        return Promise.all(descriptors.map(async (descriptor, index) => {
            const url = String(descriptor && descriptor.url || '');
            const name = String(descriptor && descriptor.name || `file-${index + 1}`);
            const type = String(descriptor && descriptor.type || '');
            if (!url) throw new Error(`Native file ${index + 1} has no transport URL`);

            const response = await fetch(url, { cache: 'no-store', credentials: 'same-origin' });
            if (!response.ok) {
                throw new Error(`Could not read native file '${name}' (${response.status})`);
            }
            const blob = await response.blob();
            return new File([blob], name, {
                type: type || blob.type || '',
                lastModified: Date.now(),
            });
        }));
    }

    async function loadNativeFiles(payload) {
        if (!viewer || typeof viewer.loadFiles !== 'function') {
            throw new Error('The bundled Mol* Viewer does not expose loadFiles()');
        }
        const files = await materializeNativeFiles(payload);
        await viewer.loadFiles(files);
    }

    async function dispatch(command) {
        if (!viewer) throw new Error('Viewer is not ready');
        const type = command && command.type;
        const payload = (command && command.payload) || {};
        const batchId = payload.batchId ? String(payload.batchId) : undefined;

        emit('command-started', { type, batchId });
        try {
            if (type !== 'open-files') throw new Error(`Unsupported command: ${String(type)}`);
            await loadNativeFiles(payload);
            emit('command-completed', { type, batchId });
        } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            emit('error', { type, batchId, message });
            throw error;
        }
    }

    window.MolApp = Object.freeze({
        contractVersion: 1,
        capabilities: Object.freeze({
            nativeFiles: true,
            multipleNativeFiles: true,
            systemTheme: true,
        }),
        dispatch,
        subscribe(listener) {
            const handler = event => listener(event.detail);
            window.addEventListener('molapp-event', handler);
            return () => window.removeEventListener('molapp-event', handler);
        },
    });

    async function initialize() {
        if (!window.molstar || !window.molstar.Viewer ||
            typeof window.molstar.Viewer.create !== 'function') {
            throw new Error('The bundled Mol* Viewer API did not load');
        }

        const customization = window.MolCustomization;
        const viewerOptions = customization && customization.viewerOptions
            ? customization.viewerOptions
            : {};

        // Layer 1 is instantiated with upstream defaults plus only the explicit Layer 3 options.
        viewer = await window.molstar.Viewer.create('app', viewerOptions);
        if (typeof viewer.loadFiles !== 'function') {
            throw new Error('The bundled Mol* Viewer is incompatible: loadFiles() is missing');
        }

        window.__molstarViewer = viewer;
        if (window.MolBoot) window.MolBoot.markReady();
        emit('ready', {
            molstarVersion: window.molstar.version || 'unknown',
            theme: window.MolTheme ? window.MolTheme.getTheme() : 'unknown',
            customizationVersion: customization && customization.contractVersion || 0,
        });
    }

    initialize().catch(error => {
        const message = error instanceof Error ? error.message : String(error);
        if (window.MolBoot) {
            window.MolBoot.fail('boot-error', message, {
                detail: error instanceof Error ? (error.stack || error.message) : String(error),
            });
        } else {
            emit('boot-error', { message });
        }
    });
})();
