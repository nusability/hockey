package `in`.nann.smashhockey.engine

import android.util.Log

/**
 * Measures input → tick latency (spec §5.3, conventions: input latency is sacred) — the twin of
 * iOS's InputLatency.swift: from the MotionEvent's own time to the moment the tick that applies it
 * has run, both on the monotonic clock (`SystemClock.uptimeMillis` and `System.nanoTime` share it).
 * `adb logcat -s SmashInput` shows every edge with a running summary.
 */
class InputLatency {
    private class Edge(val touchMs: Double, val handledMs: Double, val down: Boolean)
    private val waiting = ArrayList<Edge>()
    private val samples = ArrayList<Double>()

    fun edge(down: Boolean, eventTimeMs: Long) {
        waiting += Edge(eventTimeMs.toDouble(), System.nanoTime() / 1e6, down)
    }

    /** Ticks have just run: every edge waiting has been applied (§4.1). */
    fun ticked() {
        if (waiting.isEmpty()) return
        val now = System.nanoTime() / 1e6
        for (w in waiting) {
            val ms = now - w.touchMs
            samples += ms
            val s = samples.sorted()
            fun p(q: Double) = s[((s.size - 1) * q).toInt()]
            Log.i(TAG, "%s touch→handler %.2f ms, touch→tick %.2f ms | n=%d p50=%.2f p95=%.2f max=%.2f".format(
                if (w.down) "hold" else "lift", w.handledMs - w.touchMs, ms, s.size, p(0.5), p(0.95), s.last()))
        }
        waiting.clear()
    }

    companion object { const val TAG = "SmashInput" }
}
