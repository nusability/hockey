package `in`.nann.smashhockey.core.math

import kotlin.math.abs
import kotlin.math.max
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Spec §4.4: our sin, cos, atan2 and exp stay within 1e-9 (absolute) of the true value on the
 * simulation's input ranges. [StrictMath] (fdlibm, ≤ 1 ulp) stands in for the true value. This is
 * the tolerance test; bit-exactness across platforms is [MathVectorTest]'s job.
 */
class DetMathAccuracyTest {
    private val bound = 1e-9

    private fun maxError(lo: Double, hi: Double, n: Int, ours: (Double) -> Double, ref: (Double) -> Double): Pair<Double, Double> {
        var worst = 0.0
        var at = lo
        val g = SplitMix64.seeded(99)
        for (i in 0..n) {
            for (x in doubleArrayOf(lo + (hi - lo) * i / n, lo + (hi - lo) * g.uniform())) {
                val e = abs(ours(x) - ref(x))
                if (e > worst) { worst = e; at = x }
            }
        }
        return worst to at
    }

    @Test fun sineAndCosineOnTheSimulationsAngles() {
        for ((lo, hi) in listOf(-4 * Math.PI to 4 * Math.PI, -300.0 to 300.0, -1e6 to 1e6)) {
            val (s, sAt) = maxError(lo, hi, 200_000, DetMath::sin, StrictMath::sin)
            val (c, cAt) = maxError(lo, hi, 200_000, DetMath::cos, StrictMath::cos)
            println("DetMath.sin max error on [$lo, $hi]: $s at $sAt; cos: $c at $cAt")
            assertTrue("sin error $s at $sAt", s <= bound)
            assertTrue("cos error $c at $cAt", c <= bound)
        }
    }

    @Test fun arctangentOverAllFiniteInputs() {
        var worst = 0.0
        var at = 0.0 to 0.0
        val g = SplitMix64.seeded(5)
        for (i in 0 until 400_000) {
            var y = (g.uniform() * 2 - 1) * Math.scalb(1.0, (g.uniform() * 160).toInt() - 80)
            var x = (g.uniform() * 2 - 1) * Math.scalb(1.0, (g.uniform() * 160).toInt() - 80)
            if (i % 2 == 0) {
                val a = i / 400_000.0 * 2 * Math.PI - Math.PI
                y = StrictMath.sin(a); x = StrictMath.cos(a)
            }
            val e = abs(DetMath.atan2(y, x) - StrictMath.atan2(y, x))
            if (e > worst) { worst = e; at = y to x }
        }
        println("DetMath.atan2 max error: $worst at $at")
        assertTrue("atan2 error $worst at $at", worst <= bound)
    }

    @Test fun exponentialOnTheSimulationsRange() {
        val (e, at) = maxError(-50.0, 5.0, 400_000, DetMath::exp, StrictMath::exp)
        println("DetMath.exp max error on [-50, 5]: $e at $at")
        assertTrue("exp error $e at $at", e <= bound)
        var worstRel = 0.0
        val g = SplitMix64.seeded(11)
        repeat(100_000) {
            val x = -745 + 1454 * g.uniform()
            val ref = StrictMath.exp(x)
            if (ref > 1e-300) worstRel = max(worstRel, abs(DetMath.exp(x) - ref) / ref)
        }
        println("DetMath.exp max relative error on [-745, 709]: $worstRel")
        assertTrue(worstRel <= 1e-15)
    }

    @Test fun edgeCases() {
        assertEquals(0.0, DetMath.sin(0.0), 0.0)
        assertEquals(1.0, DetMath.cos(0.0), 0.0)
        assertEquals(1.0, DetMath.exp(0.0), 0.0)
        assertEquals(Double.POSITIVE_INFINITY, DetMath.exp(710.0), 0.0)
        assertEquals(0.0, DetMath.exp(-746.0), 0.0)
        assertEquals(0.0, DetMath.atan2(0.0, 0.0), 0.0)
        assertEquals(Math.PI, DetMath.atan2(0.0, -1.0), 0.0)
        assertEquals(Math.PI / 2, DetMath.atan2(1.0, 0.0), 0.0)
        assertEquals(-Math.PI / 2, DetMath.atan2(-1.0, 0.0), 0.0)
        assertEquals(5.0, DetMath.length(3.0, 4.0), 0.0)
    }

    @Test(expected = IllegalArgumentException::class)
    fun aTrigArgumentBeyondTheRangeFailsLoud() {
        DetMath.sin(2e6)
    }
}
