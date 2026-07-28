(() => {
    'use strict';

    // Layer 3: explicit, minimal Android/mobile adaptation only.
    // Keep this separate from both the upstream Mol* bundle and the platform bridge.
    // The sole active product policy is hiding Mol*'s non-live log panel.
    const viewerOptions = Object.freeze({
        layoutShowLog: false,
    });

    window.MolCustomization = Object.freeze({
        contractVersion: 3,
        viewerOptions,
    });
})();
