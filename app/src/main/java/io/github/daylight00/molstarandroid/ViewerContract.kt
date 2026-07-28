package io.github.daylight00.molstarandroid

import org.json.JSONArray
import org.json.JSONObject

/** Stable platform-facing contract. Mol* implementation details stay behind app-bridge.js. */
object ViewerContract {
    const val ORIGIN = "https://appassets.androidplatform.net"
    const val ENTRYPOINT = "$ORIGIN/assets/viewer/index.html"

    /**
     * Transport native files without interpreting their molecular format on Android.
     * File names and MIME types are preserved so Mol* can use its own registry.
     */
    fun openFiles(batchId: String, files: JSONArray): JSONObject =
        JSONObject()
            .put("type", "open-files")
            .put(
                "payload",
                JSONObject()
                    .put("batchId", batchId)
                    .put("files", files),
            )
}
