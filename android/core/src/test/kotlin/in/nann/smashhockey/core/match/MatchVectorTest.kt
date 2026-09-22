package `in`.nann.smashhockey.core.match

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Spec §4.7: the match golden vectors in shared/vectors/match/ (recorded by iOS's SmashCore),
 * replayed to the bit — every sampled state and every event, line by line. No tolerance: a single
 * differing bit is a red build.
 */
class MatchVectorTest {
    private val dir: File
        get() {
            val root = System.getProperty("smash.vectors")
                ?: error("system property smash.vectors is not set — android/core/build.gradle.kts sets it for tests")
            return File(root, "match")
        }

    private fun replay(name: String) {
        val file = File(dir, name)
        check(file.isFile) { "vector file ${file.path} is missing — record it with `swift run -c release RecordMatchVectors` in ios/SmashCore" }
        val (vector, recorded) = MatchVector.parse(file.readText())
        assertTrue("$name records nothing", recorded.isNotEmpty())
        val replayed = vector.run()
        val n = minOf(recorded.size, replayed.size)
        for (i in 0 until n) {
            if (recorded[i] != replayed[i]) {
                fail("$name: line ${i + 1} of the body differs\n  recorded: ${recorded[i].take(400)}\n  replayed: ${replayed[i].take(400)}")
            }
        }
        assertEquals("$name: body length", recorded.size, replayed.size)
    }

    @Test fun drill1FirstShot() = replay("drill1-first-shot.txt")
    @Test fun drill2GiveAndGo() = replay("drill2-give-and-go.txt")
    @Test fun drill5MovingCones() = replay("drill5-moving-cones.txt")
    @Test fun drill8Scrimmage() = replay("drill8-scrimmage.txt")
    @Test fun demoField() = replay("demo-field.txt")
    @Test fun demoIce() = replay("demo-ice.txt")
    @Test fun matchPlayerTape() = replay("match-player-tape.txt")
    @Test fun cupOvertime() = replay("cup-overtime.txt")

    @Test fun everyVectorFileIsReplayed() {
        val names = dir.listFiles()!!.map { it.name }.filter { it.endsWith(".txt") }.sorted()
        assertEquals(
            listOf(
                "cup-overtime.txt", "demo-field.txt", "demo-ice.txt", "drill1-first-shot.txt", "drill2-give-and-go.txt",
                "drill5-moving-cones.txt", "drill8-scrimmage.txt", "match-player-tape.txt",
            ),
            names,
        )
    }
}
