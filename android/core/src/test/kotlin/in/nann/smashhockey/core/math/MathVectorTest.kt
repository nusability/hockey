package `in`.nann.smashhockey.core.math

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Spec §4.7: the math golden vectors in shared/vectors/math/ (recorded by iOS's SmashCore),
 * replayed to the bit. No tolerance: a single differing bit is a red build.
 */
class MathVectorTest {
    private fun rows(name: String, arity: Int): List<List<String>> {
        val dir = System.getProperty("smash.vectors")
            ?: error("system property smash.vectors is not set — android/core/build.gradle.kts sets it for tests")
        val file = File(dir, "math/$name")
        check(file.isFile) { "vector file ${file.path} is missing — record it with `swift run RecordVectors` in ios/SmashCore" }
        val rows = file.readLines().filter { it.isNotEmpty() && !it.startsWith("#") }.map { it.split(" ") }
        rows.forEach { check(it.size == arity) { "$name: row $it has ${it.size} fields, expected $arity" } }
        check(rows.isNotEmpty()) { "$name has no rows" }
        return rows
    }

    private fun bits(token: String): Long = java.lang.Long.parseUnsignedLong(token, 16)
    private fun double(token: String): Double = Double.fromBits(bits(token))
    private fun hex(v: Long): String = java.lang.Long.toHexString(v).uppercase().padStart(16, '0')

    /** Replays [rows]; fails listing the rows whose recomputed last field differs. */
    private fun replay(name: String, rows: List<List<String>>, compute: (List<String>) -> Long) {
        val bad = rows.mapNotNull { row ->
            val got = compute(row)
            if (got == bits(row.last())) null
            else "${row.dropLast(1).joinToString(" ")}: expected ${row.last()}, got ${hex(got)}"
        }
        assertTrue("$name: ${bad.size} of ${rows.size} rows differ, first: ${bad.take(3)}", bad.isEmpty())
    }

    @Test fun splitMix64() {
        val rows = rows("splitmix64.txt", 3)
        assertEquals(3000, rows.size)
        val streams = HashMap<Long, SplitMix64>()
        replay("splitmix64.txt", rows) { streams.getOrPut(bits(it[0])) { SplitMix64.seeded(bits(it[0])) }.next() }
    }

    @Test fun uniform() {
        val rows = rows("uniform.txt", 3)
        val g = SplitMix64.seeded(bits(rows[0][0]))
        replay("uniform.txt", rows) { g.uniform().toRawBits() }
    }

    @Test fun noise() {
        val streams = HashMap<Long, SplitMix64>()
        replay("noise.txt", rows("noise.txt", 4)) {
            streams.getOrPut(bits(it[1])) { SplitMix64.seeded(bits(it[0])) }.noise(double(it[1])).toRawBits()
        }
    }

    @Test fun sine() = replay("sin.txt", rows("sin.txt", 2)) { DetMath.sin(double(it[0])).toRawBits() }

    @Test fun cosine() = replay("cos.txt", rows("cos.txt", 2)) { DetMath.cos(double(it[0])).toRawBits() }

    @Test fun arctangent() =
        replay("atan2.txt", rows("atan2.txt", 3)) { DetMath.atan2(double(it[0]), double(it[1])).toRawBits() }

    @Test fun exponential() = replay("exp.txt", rows("exp.txt", 2)) { DetMath.exp(double(it[0])).toRawBits() }

    @Test fun length() =
        replay("length.txt", rows("length.txt", 3)) { DetMath.length(double(it[0]), double(it[1])).toRawBits() }
}
