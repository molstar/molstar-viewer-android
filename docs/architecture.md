# Architecture

Mol* Viewer for Android is a platform host for upstream Mol*, not a separate molecular viewer implementation.

## Layers

```text
Layer 3  minimal mobile policy
   ↓
Layer 2  Android platform integration and stable bridge
   ↓
Layer 1  upstream prebuilt Mol* Viewer runtime
```

### Layer 1: upstream Mol*

`app/src/main/assets/viewer/vendor/molstar/` contains the prebuilt Viewer runtime from the `molstar` npm package. It is replaced as a unit and is not edited by hand.

Mol* owns:

- molecular and volume parsing;
- archive and compression handling;
- topology and coordinate pairing;
- representations, selections, camera, and state;
- sessions, snapshots, and the normal user interface.

The Android project does not fork Mol*, patch generated JavaScript or CSS, depend on Mol* DOM class names, or duplicate its format registry.

### Layer 2: Android integration

```text
Android lifecycle, system UI, and file intents
                 ↓
          ViewerContract.kt
                 ↓
            app-bridge.js
                 ↓
        public Mol* Viewer API
```

Layer 2 supplies:

- WebView lifecycle and renderer recovery;
- system-bar and display-cutout insets;
- the Android document picker;
- `VIEW`, `SEND`, and `SEND_MULTIPLE` intents;
- transport of file bytes, original names, and MIME types;
- system light/dark signals;
- external URL routing and terminal startup diagnostics.

Native files are copied into a private temporary directory and exposed through `WebViewAssetLoader`. `app-bridge.js` creates browser `File` objects and calls `viewer.loadFiles(files)`.

### Layer 3: minimal mobile policy

`customization.js` contains explicit product policy outside both upstream Mol* and the Android bridge. Its only active Viewer option is:

```js
layoutShowLog: false
```

Nothing else is reserved here. A future module gets its mount point when it exists, not before.

## Upgrade boundary

A normal upstream update should replace Layer 1, verify the small public Viewer surface used by Layer 2, and leave Android integration and Layer 3 unchanged.

```bash
bash scripts/sync-molstar-assets.sh <version>
bash scripts/verify.sh
```

Any Layer 2 or Layer 3 change requires an explicit human-authored commit. Automated upstream preparation may change only `vendor/molstar/**`.
