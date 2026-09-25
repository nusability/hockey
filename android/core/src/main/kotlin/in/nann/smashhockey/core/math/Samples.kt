package `in`.nann.smashhockey.core.math

/**
 * A running summary of a stream of millisecond measurements — count, mean, peak and quantiles — in
 * **constant memory and constant time per sample**. The twin of iOS's `Samples.swift`.
 *
 * It exists because the two soak meters it serves (`FrameStats`, `InputLatency`) kept every sample
 * since launch in an array and re-sorted it on every measurement: one of them on the render thread
 * every 10 s, the other **on the input path on every touch edge**. The cost grew with the length of
 * the session, which is the one thing A0 forbids — an instrument that measures input latency may not
 * add it, and one that grows cannot be left in a shipping build. A fixed histogram cannot grow.
 *
 * Quantiles are exact to within [STEP]; [count], [mean] and [peak] are exact. This is a diagnostic
 * aid and takes no part in the simulation — nothing in §4's fixed steps reads it, and no vector pins
 * it.
 */
class Samples {
    private val counts = IntArray(BUCKETS + 1)

    var count = 0
        private set

    /** The sum of every sample, so the mean stays exact however many there have been. */
    var sum = 0.0
        private set

    /** The largest sample seen, exactly, whichever bucket it landed in. */
    var peak = 0.0
        private set

    /** The mean in ms, or 0 with nothing measured. */
    val mean: Double get() = if (count == 0) 0.0 else sum / count

    /** Measurements a second, from the mean — 0 with nothing measured, or with a mean of 0. */
    val rate: Double get() = if (mean <= 0.0) 0.0 else 1000.0 / mean

    /**
     * Records one measurement in ms. A value that is not finite is ignored rather than allowed to
     * poison the sum; a negative one lands in the first bucket, which is where a clock that ran
     * backwards belongs.
     */
    fun add(ms: Double) {
        if (!ms.isFinite()) return
        val i = if (ms <= 0.0) 0 else minOf((ms / STEP).toInt(), BUCKETS)
        counts[i]++
        count++
        sum += ms
        if (ms > peak) peak = ms
    }

    /**
     * The [q]-quantile in ms ([q] in 0..1), to within [STEP]. The same rank [q] picks out of a
     * sorted array of [count] samples: `floor((count - 1) * q)`. 0 with nothing measured. A rank
     * that falls in the overflow bucket reports [peak], which is the only exact thing known about a
     * sample that far out.
     *
     * The bucket is reported by its middle, which can sit above the largest sample that landed in
     * it, so the result is capped at [peak]: a p99 above the max is nonsense in a log, and it makes
     * `quantile(1.0) == peak` hold.
     */
    fun quantile(q: Double): Double {
        if (count == 0) return 0.0
        val rank = ((count - 1) * q.coerceIn(0.0, 1.0)).toInt()
        var seen = 0
        for (i in counts.indices) {
            seen += counts[i]
            if (seen <= rank) continue
            if (i == BUCKETS) return peak
            return minOf((i + 0.5) * STEP, peak)
        }
        return peak
    }

    /** Forgets everything, keeping the buckets allocated — a window starting over. */
    fun reset() {
        counts.fill(0)
        count = 0
        sum = 0.0
        peak = 0.0
    }

    /** `n=… fps=… p50=… p95=… p99=… max=…`, the line both meters log. */
    fun summary(): String =
        if (count == 0) "n=0"
        else "n=%d fps=%.1f p50=%.2f p95=%.2f p99=%.2f max=%.2f".format(
            count, rate, quantile(0.5), quantile(0.95), quantile(0.99), peak)

    companion object {
        /**
         * Milliseconds per bucket. Quantiles are reported to the middle of the bucket they fall in,
         * so this is the whole of their error.
         */
        const val STEP = 0.25

        /** Buckets covering `0 until BUCKETS * STEP` ms — 0–256 ms — plus one overflow bucket. */
        const val BUCKETS = 1024
    }
}
