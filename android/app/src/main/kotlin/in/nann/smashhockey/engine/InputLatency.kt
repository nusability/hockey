package `in`.nann.smashhockey.engine

import android.util.Log
import `in`.nann.smashhockey.core.math.Samples

/**
 * Measures input → tick latency (spec §5.3, conventions: input latency is sacred) — the twin of
 * iOS's InputLatency.swift: from the MotionEvent's own time to the moment the tick that applies it
 * has run, both on the monotonic clock (`SystemClock.uptimeMillis` and `System.nanoTime` share it).
 * `adb logcat -s SmashInput` shows every edge with a running summary.
 *
 * The summary is a [Samples] histogram, so it costs the same on the first tap of a session as on the
 * thousandth. It used to keep every sample since launch in an array and sort a copy of it on every
 * edge — **on the input path**, the one place A0 says nothing may be added, and growing with the
 * session (SMASH-58). An instrument that measures latency may not add it.
 */
class InputLatency {
    private class Edge(val touchMs: Double, val handledMs: Double, val down: Boolean)
    private val waiting = ArrayList<Edge>()
    private val samples = Samples()

    fun edge(down: Boolean, eventTimeMs: Long) {
        waiting += Edge(eventTimeMs.toDouble(), System.nanoTime() / 1e6, down)
    }

    /** Ticks have just run: every edge waiting has been applied (§4.1). */
    fun ticked() {
        if (waiting.isEmpty()) return
        val now = System.nanoTime() / 1e6
        for (w in waiting) {
            val ms = now - w.touchMs
            samples.add(ms)
            Log.i(TAG, "%s touch→handler %.2f ms, touch→tick %.2f ms | n=%d p50=%.2f p95=%.2f max=%.2f".format(
                if (w.down) "hold" else "lift", w.handledMs - w.touchMs, ms, samples.count,
                samples.quantile(0.5), samples.quantile(0.95), samples.peak))
        }
        waiting.clear()
    }

    companion object { const val TAG = "SmashInput" }
}
