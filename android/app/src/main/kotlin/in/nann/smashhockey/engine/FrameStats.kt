package `in`.nann.smashhockey.engine

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log

/**
 * The spike's soak meter (SMASH-2): frame intervals and the thermal status, summarised to logcat
 * every [windowSeconds] under the tag `SmashFrames`, plus a running summary since launch.
 *
 * `adb logcat -s SmashFrames` during a 6-minute run is the whole measurement.
 */
class FrameStats(context: Context, private val windowSeconds: Double = 10.0) {
    private val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val window = ArrayList<Double>(1024)
    private val all = ArrayList<Double>(64 * 1024)
    private var elapsed = 0.0
    private var worstThermal = 0

    fun record(dtSeconds: Double) {
        if (dtSeconds <= 0.0) return
        val ms = dtSeconds * 1000.0
        window += ms
        all += ms
        elapsed += dtSeconds
        if (elapsed >= windowSeconds) {
            val thermal = thermalStatus()
            worstThermal = maxOf(worstThermal, thermal)
            Log.i(TAG, "window ${summary(window)} thermal=$thermal | total ${summary(all)} worstThermal=$worstThermal")
            window.clear()
            elapsed = 0.0
        }
    }

    private fun thermalStatus(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) power.currentThermalStatus else -1

    private fun summary(samples: List<Double>): String {
        if (samples.isEmpty()) return "n=0"
        val s = samples.sorted()
        fun p(q: Double) = s[((s.size - 1) * q).toInt()]
        return "n=${s.size} fps=%.1f p50=%.2f p95=%.2f p99=%.2f max=%.2f".format(
            1000.0 / (samples.sum() / samples.size), p(0.5), p(0.95), p(0.99), s.last())
    }

    companion object {
        const val TAG = "SmashFrames"
    }
}
