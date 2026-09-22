package `in`.nann.smashhockey.core.math

import `in`.nann.smashhockey.core.generated.MathConstants

/**
 * The simulation's only source of randomness (spec §4.3): a seeded SplitMix64 stream.
 *
 * Every step is 64-bit integer arithmetic (a [Long] holds the bits; `ushr` is the logical shift,
 * and Kotlin's multiply wraps mod 2^64), and [uniform] converts a 53-bit integer (exact) and scales
 * it by 2^−53 (exact), so the stream is bit-identical on every platform. The iOS twin is
 * `SmashCore.SplitMix64`; both replay shared/vectors/math/.
 */
class SplitMix64 private constructor(state: Long) {
    /** The stream position; [resume] restores it exactly (a season stores its stream, §15). */
    var state: Long = state
        private set

    /** The next 64-bit output, as the bits of a [Long]. */
    fun next(): Long {
        state += K.gamma
        var z = state
        z = (z xor (z ushr K.shift1)) * K.mix1
        z = (z xor (z ushr K.shift2)) * K.mix2
        return z xor (z ushr K.shift3)
    }

    /** A double in [0, 1): the top 53 bits of the next output × 2^−53. */
    fun uniform(): Double = (next() ushr K.mantissaShift).toDouble() * K.unit

    /** `(u₁ + u₂ + u₃ − 1.5) × s` from three consecutive draws, summed left to right. */
    fun noise(s: Double): Double {
        val u1 = uniform()
        val u2 = uniform()
        val u3 = uniform()
        val sum = (u1 + u2) + u3
        return (sum - K.noiseCenter) * s
    }

    companion object {
        private val K = MathConstants.Splitmix

        /** A stream seeded with [seed] (the bits of a 64-bit unsigned seed). */
        fun seeded(seed: Long): SplitMix64 = SplitMix64(seed)

        /** A stream resumed at a stored [state]. */
        fun resume(state: Long): SplitMix64 = SplitMix64(state)
    }
}
