package `in`.nann.smashhockey.core.telemetry

import `in`.nann.smashhockey.core.generated.DeviceRecord
import `in`.nann.smashhockey.core.season.SaveDecodeException
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Spec §4.7 for the love dialog and the device record (§17): shared/vectors/telemetry/, recorded by
 * iOS's RecordTelemetryVectors and replayed here line for line and byte for byte. No tolerance — the
 * policy's clock arithmetic is integer milliseconds precisely so that there is none to grant.
 */
class TelemetryVectorTest {
    private val dir: File by lazy {
        File(
            System.getProperty("smash.vectors")
                ?: error("system property smash.vectors is not set — android/core/build.gradle.kts sets it for tests"),
            "telemetry",
        )
    }

    private fun file(name: String): File = File(dir, name).also {
        check(it.isFile) { "vector file ${it.path} is missing — record it with `swift run RecordTelemetryVectors` in ios/SmashCore" }
    }

    private fun text(name: String) = file(name).readText(Charsets.UTF_8)

    private fun lines(name: String) = text(name).lines().filter { it.isNotEmpty() && !it.startsWith("#") }

    /**
     * Every step of the script, recomputed from its input lines: the trigger a match armed, the verdict
     * on a settled screen, and the record after each one.
     */
    @Test fun theWholeLoveScriptReplays() {
        val expected = lines("love.txt")
        var pinned = 0
        val got = LoveScript.parse(text("love.txt")).run { name, record ->
            pinned++
            val bytes = text(name)
            assertEquals("$name: the record's canonical JSON differs", bytes, record.encoded())
            // The pinned bytes must read back as the very record that wrote them.
            assertEquals("$name: reading it back gave another record", record, DeviceRecord.decode(bytes))
        }
        assertEquals(4, pinned)
        for (i in 0 until maxOf(expected.size, got.size)) {
            val e = expected.getOrNull(i)
            val g = got.getOrNull(i)
            if (e != g) fail("love.txt: line ${i + 1}: expected ${e ?: "<end>"}, got ${g ?: "<end>"}")
        }
        assertEquals(expected.size, got.size)
    }

    /** Every refused record is refused with exactly the recorded, typed error — never read. */
    @Test fun brokenDeviceRecordsAreRefusedTyped() {
        val cases = lines("invalid.txt")
        assertEquals(15, cases.size)
        for (line in cases) {
            val name = line.substringBefore(' ')
            val expected = line.substringAfter(' ')
            try {
                DeviceRecord.decode(file("invalid/$name").readBytes())
                fail("$name was read; expected $expected")
            } catch (e: SaveDecodeException) {
                assertEquals(name, expected, e.error.toString())
            }
        }
    }

    /** The thresholds are the declared ones, not a second copy of them. */
    @Test fun theCooldownIsNinetyDaysOfAbsoluteTime() {
        assertTrue(LovePolicy.COOLDOWN_MILLIS == 90L * 86_400_000L)
        assertEquals(20, LovePolicy.HARD_FOUGHT_MATCHES)
    }
}
