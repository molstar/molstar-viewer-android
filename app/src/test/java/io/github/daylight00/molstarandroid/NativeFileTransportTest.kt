package io.github.daylight00.molstarandroid

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeFileTransportTest {
    @Test
    fun `keeps an ordinary file name unchanged`() {
        assertEquals("model.pdb", NativeFileTransport.normalizeDisplayName("model.pdb", 0))
    }

    @Test
    fun `keeps an inner extension so Mol-star can still pick a parser`() {
        assertEquals("model.pdb.gz", NativeFileTransport.normalizeDisplayName("model.pdb.gz", 0))
        assertEquals("traj.xtc", NativeFileTransport.normalizeDisplayName("traj.xtc", 0))
    }

    @Test
    fun `reduces a posix path to its last segment`() {
        assertEquals("passwd", NativeFileTransport.normalizeDisplayName("../../etc/passwd", 0))
        assertEquals("model.cif", NativeFileTransport.normalizeDisplayName("/storage/emulated/0/model.cif", 0))
    }

    @Test
    fun `reduces a windows path to its last segment`() {
        assertEquals("secret.pdb", NativeFileTransport.normalizeDisplayName("..\\..\\secret.pdb", 0))
    }

    @Test
    fun `replaces control characters`() {
        assertEquals("a_b.pdb", NativeFileTransport.normalizeDisplayName("a\nb.pdb", 0))
        assertEquals("a_b.pdb", NativeFileTransport.normalizeDisplayName("a\u0001b.pdb", 0))
        assertEquals("a_b.pdb", NativeFileTransport.normalizeDisplayName("a\u007Fb.pdb", 0))
    }

    @Test
    fun `keeps an ordinary space, which is legal in a file name`() {
        assertEquals("my model.pdb", NativeFileTransport.normalizeDisplayName("my model.pdb", 0))
    }

    @Test
    fun `trims surrounding whitespace`() {
        assertEquals("model.pdb", NativeFileTransport.normalizeDisplayName("  model.pdb  ", 0))
    }

    @Test
    fun `falls back to a positional name when nothing usable remains`() {
        assertEquals("file-1", NativeFileTransport.normalizeDisplayName("", 0))
        assertEquals("file-3", NativeFileTransport.normalizeDisplayName("   ", 2))
        assertEquals("file-1", NativeFileTransport.normalizeDisplayName("/", 0))
        assertEquals("file-2", NativeFileTransport.normalizeDisplayName("some/directory/", 1))
    }

    @Test
    fun `always returns one non-blank segment`() {
        val awkward = listOf("", "   ", "/", "\\", "a/b/c", "..\\x", "a\u0001b", "  /tmp/  ")
        for ((index, name) in awkward.withIndex()) {
            val result = NativeFileTransport.normalizeDisplayName(name, index)
            assertTrue("blank result for '$name'", result.isNotBlank())
            assertFalse("separator survived in '$result'", result.contains('/'))
            assertFalse("separator survived in '$result'", result.contains('\\'))
        }
    }

    @Test
    fun `accepts a generated batch identifier`() {
        assertTrue(NativeFileTransport.isBatchId("34c1b902-8d4d-47fb-8613-7473aa3d0845"))
        assertTrue(NativeFileTransport.isBatchId("34C1B902-8D4D-47FB-8613-7473AA3D0845"))
    }

    @Test
    fun `rejects anything that could escape the transport directory`() {
        val rejected = listOf(
            "",
            "..",
            "../..",
            "not-a-uuid",
            "34c1b902-8d4d-47fb-8613-7473aa3d0845/..",
            "../34c1b902-8d4d-47fb-8613-7473aa3d0845",
            "34c1b902-8d4d-47fb-8613-7473aa3d084",
            "34c1b902-8d4d-47fb-8613-7473aa3d0845x",
            "34c1b902_8d4d_47fb_8613_7473aa3d0845",
        )
        for (value in rejected) {
            assertFalse("accepted '$value'", NativeFileTransport.isBatchId(value))
        }
    }
}
