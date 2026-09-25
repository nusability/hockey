package `in`.nann.smashhockey.engine

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log
import `in`.nann.smashhockey.core.math.Samples

/**
 * The spike's soak meter (SMASH-2): frame intervals and the thermal status, summarised to logcat
 * every [windowSeconds] under the tag `SmashFrames`, plus a running summary since launch.
 *
 * `adb logcat -s SmashFrames` during a 6-minute run is the whole measurement.
 *
 * Both summaries are [Samples] — a fixed histogram — so the meter costs the same on the first frame
 * of a session as on the hundred-thousandth. It used to keep every frame time since launch in an
 * array and sort a copy of it every 10 s on the render thread, which made the game choppier the
 * longer it was played (SMASH-58).
 */
class FrameStats(context: Context, private val windowSeconds: Double = 10.0) {
    private val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val window = Samples()
    private val all = Samples()
    private var elapsed = 0.0
    private var worstThermal = 0

    fun record(dtSeconds: Double) {
        if (dtSeconds <= 0.0) return
        val ms = dtSeconds * 1000.0
        window.add(ms)
        all.add(ms)
        elapsed += dtSeconds
        if (elapsed >= windowSeconds) {
            val thermal = thermalStatus()
            worstThermal = maxOf(worstThermal, thermal)
            Log.i(TAG, "window ${window.summary()} thermal=$thermal | total ${all.summary()} worstThermal=$worstThermal")
            window.reset()
            elapsed = 0.0
        }
    }

    private fun thermalStatus(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) power.currentThermalStatus else -1

    companion object {
        const val TAG = "SmashFrames"
    }
}
