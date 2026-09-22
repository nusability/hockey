package `in`.nann.smashhockey.core.math

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Spec §4.3, checked against the published SplitMix64 reference (Steele, Lea & Flood 2014;
 * Vigna's splitmix64.c) rather than against the recording.
 */
class SplitMix64Test {
    @Test fun matchesTheReferenceSequenceForSeedZero() {
        val g = SplitMix64.seeded(0)
        assertEquals(java.lang.Long.parseUnsignedLong("E220A8397B1DCDAF", 16), g.next())
        assertEquals(0x6E789E6AA1B965F4L, g.next())
        assertEquals(0x06C45D188009454FL, g.next())
    }

    @Test fun uniformIsTheTop53BitsScaled() {
        val a = SplitMix64.seeded(123)
        val b = SplitMix64.seeded(123)
        repeat(1000) {
            val u = a.uniform()
            assertEquals((b.next() ushr 11).toDouble() / 9_007_199_254_740_992.0, u, 0.0)
            assertTrue(u >= 0.0 && u < 1.0)
        }
    }

    @Test fun noiseSumsThreeDrawsLeftToRight() {
        val a = SplitMix64.seeded(9)
        val b = SplitMix64.seeded(9)
        val n = a.noise(1.6)
        val u1 = b.uniform(); val u2 = b.uniform(); val u3 = b.uniform()
        assertEquals((u1 + u2 + u3 - 1.5) * 1.6, n, 0.0)
    }

    @Test fun aStoredStateResumesTheStream() {
        val a = SplitMix64.seeded(77)
        a.next(); a.next()
        val b = SplitMix64.resume(a.state)
        assertEquals(a.next(), b.next())
    }
}
