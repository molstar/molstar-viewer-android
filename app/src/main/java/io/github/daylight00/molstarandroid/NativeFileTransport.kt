package io.github.daylight00.molstarandroid

/**
 * Naming and identity rules for the native file transport.
 *
 * These decide what a provider-supplied file is called once it reaches Mol* and
 * which import batch may be deleted from the transport directory. They hold no
 * Android types so they can be covered by unit tests rather than by asserting on
 * source text.
 */
object NativeFileTransport {
    private val CONTROL_CHARACTERS = Regex("[\\u0000-\\u001f\\u007f]")
    private val BATCH_ID = Regex(
        "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
    )

    /**
     * Reduce a display name to one path segment that is safe to hand to Mol* as a
     * browser file name. Meaningful extensions, including inner ones such as
     * `.pdb.gz`, are preserved because Mol* selects its parser from them.
     */
    fun normalizeDisplayName(name: String, index: Int): String {
        val leaf = name.substringAfterLast('/').substringAfterLast('\\')
        val normalized = leaf.replace(CONTROL_CHARACTERS, "_").trim()
        return normalized.ifBlank { "file-${index + 1}" }
    }

    /**
     * Only an identifier this application generated may name a directory that is
     * deleted recursively, so a value arriving from the WebView is accepted only
     * when it is exactly a UUID.
     */
    fun isBatchId(value: String): Boolean = BATCH_ID.matches(value)
}
