package `in`.nann.smashhockey.core.math

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Spec §4.7 and ADR 0010: the policy kernel golden vector in shared/vectors/policy/ (recorded by
 * iOS's SmashCore), replayed to the bit. No tolerance: a single differing bit is a red build.
 *
 * This is the experiment ADR 0010 says to run before any trained weights are relied on. It is also
 * only half of it — a green run here proves the JVM agrees, and the JVM proves nothing ART does
 * not. The other half is this same test on a real device.
 */
class PolicyVectorTest {

    private fun vectorFile(): File {
        val dir = System.getProperty("smash.vectors")
            ?: error("system property smash.vectors is not set — android/core/build.gradle.kts sets it for tests")
        val file = File(dir, "policy/kernel.txt")
        check(file.isFile) {
            "vector file ${file.path} is missing — record it with `swift run -c release RecordPolicyVectors` in ios/SmashCore"
        }
        return file
    }

    private fun bits(token: String): Long = java.lang.Long.parseUnsignedLong(token, 16)
    private fun double(token: String): Double = Double.fromBits(bits(token))
    private fun hex(v: Long): String = java.lang.Long.toHexString(v).uppercase().padStart(16, '0')

    @Test
    fun theKernelAgreesWithIOSToTheBit() {
        val lines = vectorFile().readLines().filter { it.isNotEmpty() && !it.startsWith("#") }

        val shape = lines.first { it.startsWith("shape ") }.split(" ")
        val nIn = shape[1].toInt()
        val nHidden = shape[2].toInt()
        val nOut = shape[3].toInt()

        val parameters = lines.filter { it.startsWith("p ") }.map { double(it.split(" ")[1]) }.toDoubleArray()
        assertEquals(
            "parameter count",
            PolicyNet.parameterCount(nIn, nHidden, nOut),
            parameters.size,
        )
        val net = PolicyNet(nIn, nHidden, nOut, parameters)

        val rows = lines.filter { it.startsWith("r ") }
        assertTrue("the corpus has rows", rows.isNotEmpty())

        val bad = mutableListOf<String>()
        rows.forEachIndexed { index, line ->
            val f = line.split(" ")
            check(f.size == 1 + nIn + 1 + nOut) {
                "row $index has ${f.size} fields, expected ${1 + nIn + 1 + nOut}"
            }
            val observation = DoubleArray(nIn) { double(f[1 + it]) }
            val (h0, h1, out) = net.trace(observation)

            var fold = 0L
            for (v in h0) fold = fold xor v.toRawBits()
            for (v in h1) fold = fold xor v.toRawBits()
            val expectedFold = bits(f[1 + nIn])
            if (fold != expectedFold) {
                bad += "row $index: hidden fold expected ${f[1 + nIn]}, got ${hex(fold)}"
                return@forEachIndexed
            }
            for (o in 0 until nOut) {
                val expected = f[1 + nIn + 1 + o]
                if (out[o].toRawBits() != bits(expected)) {
                    bad += "row $index output $o: expected $expected, got ${hex(out[o].toRawBits())}"
                }
            }
        }
        assertTrue(
            "${bad.size} of ${rows.size} rows differ from iOS, first: ${bad.take(3)}",
            bad.isEmpty(),
        )
    }

    /**
     * The accumulation order is the contract, so three ways of writing the same dot product must
     * agree. If a toolchain ever does reassociate or fuse, this is the cheapest place to find out:
     * the hostile forms are the ones an optimiser is most tempted by.
     */
    @Test
    fun threeWaysOfWritingTheLoopAgree() {
        val n = 2000
        var state = 0x1234_5678_9ABC_DEF0uL.toLong()
        fun next(): Double {
            state += -0x61c8864680b583ebL // 0x9E3779B97F4A7C15 as a signed long
            var z = state
            z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
            z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
            z = z xor (z ushr 31)
            return (z ushr 11).toDouble() * 1.1102230246251565E-16 * 2.0 - 1.0
        }
        val w = DoubleArray(n) { next() }
        val x = DoubleArray(n) { next() }

        var plain = 0.0
        for (i in 0 until n) plain = plain + w[i] * x[i]

        var compound = 0.0
        for (i in 0 until n) compound += w[i] * x[i]

        var unrolled = 0.0
        var i = 0
        while (i + 4 <= n) {
            unrolled = unrolled + w[i] * x[i]
            unrolled = unrolled + w[i + 1] * x[i + 1]
            unrolled = unrolled + w[i + 2] * x[i + 2]
            unrolled = unrolled + w[i + 3] * x[i + 3]
            i += 4
        }
        while (i < n) { unrolled = unrolled + w[i] * x[i]; i++ }

        assertEquals("`+=` must not differ from `s = s + …`", plain.toRawBits(), compound.toRawBits())
        assertEquals("unrolling must not reassociate", plain.toRawBits(), unrolled.toRawBits())
    }
}
