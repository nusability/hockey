package `in`.nann.smashhockey.core.season

import `in`.nann.smashhockey.core.generated.SaveRecord
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.generated.World
import `in`.nann.smashhockey.core.math.SplitMix64
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Spec §4.7 for the season, the career and the save (§2.2, §11, §15): shared/vectors/season/,
 * recorded by iOS's RecordSeasonVectors and replayed here line for line and byte for byte.
 */
class SeasonVectorTest {
    private val dir: File by lazy {
        File(
            System.getProperty("smash.vectors")
                ?: error("system property smash.vectors is not set — android/core/build.gradle.kts sets it for tests"),
            "season",
        )
    }

    private fun file(name: String): File = File(dir, name).also {
        check(it.isFile) { "vector file ${it.path} is missing — record it with `swift run RecordSeasonVectors` in ios/SmashCore" }
    }

    private fun text(name: String) = file(name).readText(Charsets.UTF_8)

    private fun lines(name: String) = text(name).lines().filter { it.isNotEmpty() && !it.startsWith("#") }

    private fun assertSameLines(what: String, expected: List<String>, got: List<String>) {
        for (i in 0 until maxOf(expected.size, got.size)) {
            val e = expected.getOrNull(i)
            val g = got.getOrNull(i)
            if (e != g) fail("$what: line ${i + 1}: expected ${e ?: "<end>"}, got ${g ?: "<end>"}")
        }
    }

    @Test fun aWholeSeasonReplays() {
        for (name in listOf("season-club.txt", "season-created.txt")) {
            assertSameLines(name, lines(name), SeasonScript.parse(text(name)).run().first)
        }
    }

    /** A season written to the save and read back after any player match goes on with exactly the draws it would have made. */
    @Test fun aReloadedSeasonContinuesTheSameDraws() {
        for (name in listOf("season-club.txt", "season-created.txt")) {
            val script = SeasonScript.parse(text(name))
            for (k in 1..script.entries.size) {
                assertSameLines("$name reloaded after $k", lines(name), script.run(reloadAfter = k).first)
            }
        }
    }

    @Test fun simulatedResultsReplay() {
        val rows = lines("simulated.txt")
        val rng = SplitMix64.seeded(java.lang.Long.parseUnsignedLong(rows[0].removePrefix("seed 0x"), 16))
        val sims = rows.drop(1).dropLast(1)
        assertEquals(486, sims.size)
        for (line in sims) {
            val w = line.split(" ")
            val s = SeasonEngine.simulate(w[1].toInt(), w[2].toInt(), w[3] == "cup", rng)
            assertEquals(line, w.subList(4, 7).joinToString(" "), "${s.home} ${s.away} ${if (s.overtime) "ot" else "-"}")
        }
        assertEquals("stream 0x" + SaveJson.hex(rng.state, 16), rows.last())
    }

    @Test fun theCreatedTeamsRulesReplay() {
        val rows = lines("career.txt")
        assertEquals(34, rows.size)
        for (line in rows) {
            val name = line.substring(line.indexOf('"') + 1, line.lastIndexOf('"'))
            val w = line.split(" ")
            when (w[0]) {
                "short" -> assertEquals(line, w[1], CreatedTeamRules.suggestedShortCode(name))
                "issues" -> {
                    val draft = TeamDraft(name, if (w[2] == "-") "" else w[2], w[3].substring(1).toInt(16), w[4].substring(1).toInt(16), World.MAGICWOOD)
                    val got = CreatedTeamRules.issues(draft).joinToString(",") { it.key }
                    assertEquals(line, w[1], got.ifEmpty { "-" })
                }
                else -> fail("unknown line $line")
            }
        }
    }

    @Test fun quickMatchesReplay() {
        val rows = lines("quickmatch.txt")
        assertEquals(48, rows.size)
        for (line in rows) {
            val w = line.split(" ")
            val q = QuickMatch.draw(java.lang.Long.parseUnsignedLong(w[1].substring(2), 16), TeamKey.of(w[2]))
            assertEquals(line, "${w[3]} ${w[4]}", "${q.opponent.key} ${q.world.key}")
        }
    }

    /** Android builds each state and must write the file iOS wrote, byte for byte; reading it back yields the same state. */
    @Test fun saveFilesAreWrittenAndReadExactly() {
        val manifest = lines("save/manifest.txt")
        assertEquals(3, manifest.size)
        for (line in manifest) {
            val (name, save) = SeasonScript.saveCase(line) { text(it) }
            val bytes = file("save/$name").readBytes()
            assertTrue("$name: the encoding differs", save.encoded().toByteArray(Charsets.UTF_8).contentEquals(bytes))
            val read = SaveRecord.decode(bytes)
            assertEquals(name, save, read)
            assertEquals(name, text("save/$name"), read.encoded())
        }
    }

    /** Every refused save is refused with exactly the recorded, typed error — never read. */
    @Test fun brokenSavesAreRefusedTyped() {
        val cases = lines("save/invalid.txt")
        assertEquals(22, cases.size)
        for (line in cases) {
            val name = line.substringBefore(' ')
            val expected = line.substringAfter(' ')
            try {
                SaveRecord.decode(file("save/invalid/$name").readBytes())
                fail("$name was read; expected $expected")
            } catch (e: SaveDecodeException) {
                assertEquals(name, expected, e.error.toString())
            }
        }
    }
}
