package `in`.nann.smashhockey.core.math

import `in`.nann.smashhockey.core.generated.MathConstants
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.sqrt

/**
 * The simulation's math (spec §4.4): the same result, to the bit, as iOS's `SmashCore.DetMath`.
 *
 * Only operations IEEE-754 defines exactly are used — `+ − × ÷`, [sqrt], and the exact integral
 * rounding [floor] — each in the order written here and in the Swift twin. The JVM never fuses:
 * since Java 17 every floating-point operation is strict (JEP 306), and neither HotSpot nor ART
 * turns `a * b + c` into a fused multiply-add — only an explicit `Math.fma` is one.
 *
 * The constants come from shared/data/math.toml ([MathConstants], generated). Accuracy — absolute
 * error ≤ 1e-9 on the simulation's ranges — is asserted by DetMathAccuracyTest; bit-exactness
 * across platforms by the golden vectors in shared/vectors/math/.
 */
object DetMath {
    private val T = MathConstants.Trig
    private val A = MathConstants.Atan
    private val E = MathConstants.Exp

    /** `sqrt(x² + z²)`, never `hypot` (spec §4.4). */
    fun length(x: Double, z: Double): Double {
        val xx = x * x
        val zz = z * z
        return sqrt(xx + zz)
    }

    /** sin x for |x| ≤ 1e6. Beyond that, or for a non-finite x, it fails loud. */
    fun sin(x: Double): Double {
        val k = reduceK(x)
        val r = reduceR(x, k)
        return when (k.toLong().toInt() and 3) {
            0 -> sinKernel(r)
            1 -> cosKernel(r)
            2 -> -sinKernel(r)
            else -> -cosKernel(r)
        }
    }

    /** cos x for |x| ≤ 1e6. Beyond that, or for a non-finite x, it fails loud. */
    fun cos(x: Double): Double {
        val k = reduceK(x)
        val r = reduceR(x, k)
        return when (k.toLong().toInt() and 3) {
            0 -> cosKernel(r)
            1 -> -sinKernel(r)
            2 -> -cosKernel(r)
            else -> sinKernel(r)
        }
    }

    /** k = floor(x·2/π + ½): the multiple of π/2 nearest x. */
    private fun reduceK(x: Double): Double {
        require(x.isFinite() && abs(x) <= T.maxInput) {
            "DetMath: sin/cos argument $x is outside ±1e6 (spec §4.4); wrap angles first"
        }
        val scaled = x * T.invPio2
        return floor(scaled + 0.5)
    }

    /** r = x − k·π/2 by Cody–Waite with a three-part π/2 (k·p1, k·p2 exact for |k| < 2^20). */
    private fun reduceR(x: Double, k: Double): Double {
        val r1 = x - k * T.pio21
        val r2 = r1 - k * T.pio22
        return r2 - k * T.pio23
    }

    /** sin r ≈ r + (r·z)·(s1 + z·(s2 + z·(s3 + z·(s4 + z·(s5 + z·s6))))), z = r². */
    private fun sinKernel(r: Double): Double {
        val z = r * r
        var p = T.sin6
        p = T.sin5 + z * p
        p = T.sin4 + z * p
        p = T.sin3 + z * p
        p = T.sin2 + z * p
        p = T.sin1 + z * p
        val rz = r * z
        return r + rz * p
    }

    /** cos r ≈ (1 − 0.5·z) + (z·z)·(c1 + z·(c2 + z·(c3 + z·(c4 + z·(c5 + z·c6))))), z = r². */
    private fun cosKernel(r: Double): Double {
        val z = r * r
        var p = T.cos6
        p = T.cos5 + z * p
        p = T.cos4 + z * p
        p = T.cos3 + z * p
        p = T.cos2 + z * p
        p = T.cos1 + z * p
        val head = 1.0 - 0.5 * z
        val zz = z * z
        return head + zz * p
    }

    /**
     * The angle of (x, y) in [−π, π], for finite x and y (a non-finite one fails loud).
     * atan2(0, 0) is 0; the sign of a zero is not consulted, so atan2(−0, −1) is +π.
     */
    fun atan2(y: Double, x: Double): Double {
        require(x.isFinite() && y.isFinite()) { "DetMath: atan2($y, $x) needs finite arguments (spec §4.4)" }
        val ax = abs(x)
        val ay = abs(y)
        if (ax == 0.0 && ay == 0.0) return 0.0
        var a: Double
        if (ay <= ax) {
            a = atanUnit(ay / ax)
        } else {
            val inner = atanUnit(ax / ay)
            a = (A.pio2Hi - inner) + A.pio2Lo
        }
        if (x < 0.0) {
            a = (A.piHi - a) + A.piLo
        }
        return if (y < 0.0) -a else a
    }

    /** atan t for t in [0, 1], reduced to |u| < 7/16 around 0, ½ or 1 (fdlibm's split). */
    private fun atanUnit(t: Double): Double {
        if (t < A.splitLow) {
            return t - t * atanSeries(t)
        }
        if (t < A.splitHigh) {
            val num = 2.0 * t - 1.0
            val u = num / (2.0 + t)
            return A.halfHi - ((u * atanSeries(u) - A.halfLo) - u)
        }
        val u = (t - 1.0) / (t + 1.0)
        return A.oneHi - ((u * atanSeries(u) - A.oneLo) - u)
    }

    /** s1 + s2 with z = u², w = z²: s1 = z·(a0 + w·(a2 + … + w·a10)), s2 = w·(a1 + w·(a3 + … + w·a9)). */
    private fun atanSeries(u: Double): Double {
        val z = u * u
        val w = z * z
        var odd = A.a10
        odd = A.a8 + w * odd
        odd = A.a6 + w * odd
        odd = A.a4 + w * odd
        odd = A.a2 + w * odd
        odd = A.a0 + w * odd
        var even = A.a9
        even = A.a7 + w * even
        even = A.a5 + w * even
        even = A.a3 + w * even
        even = A.a1 + w * even
        val s1 = z * odd
        val s2 = w * even
        return s1 + s2
    }

    /** e^x for any non-NaN x: +∞ above 709.78, 0 below −745.13 (a NaN fails loud). */
    fun exp(x: Double): Double {
        require(!x.isNaN()) { "DetMath: exp(NaN) (spec §4.4)" }
        if (x > E.overflow) return Double.POSITIVE_INFINITY
        if (x < E.underflow) return 0.0
        val scaled = x * E.invLn2
        val k = floor(scaled + 0.5)
        val hi = x - k * E.ln2Hi
        val lo = k * E.ln2Lo
        val r = hi - lo
        val z = r * r
        var p = E.p5
        p = E.p4 + z * p
        p = E.p3 + z * p
        p = E.p2 + z * p
        p = E.p1 + z * p
        val c = r - z * p
        val rc = r * c
        val q = rc / (2.0 - c)
        val y = 1.0 - ((lo - q) - hi)
        return scale(y, k.toInt())
    }

    /** y · 2^k, exact except where the result is subnormal. */
    private fun scale(y: Double, k: Int): Double {
        if (k > 1023) return (y * 2.0) * twoTo(k - 1)
        if (k < -1022) return (y * twoTo(k + 1000)) * twoTo(-1000)
        return y * twoTo(k)
    }

    /** 2^n for −1022 ≤ n ≤ 1023, built from its bits. */
    private fun twoTo(n: Int): Double = Double.fromBits((1023L + n) shl 52)
}
