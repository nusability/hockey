package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Tuning
import kotlin.math.roundToLong

/**
 * Turns real time into whole ticks (spec §4.2).
 *
 * Real time is counted in integer units — a tick is `realUnitsPerTick` of them — so a display at
 * 60 Hz (two ticks a frame) and one at 120 Hz (one a frame) accumulate exactly the same count and
 * run exactly the same ticks. The time scale changes how many ticks a real second holds, never
 * what a tick does.
 */
internal class TickClock {
    private var units = 0L

    fun ticks(realSeconds: Double, timeScale: Double): Int {
        require(timeScale >= 0 && realSeconds.isFinite()) { "TickClock: a time scale is ≥ 0 and real time finite" }
        val gap = Pitch.clamp(realSeconds, 0.0, Tuning.Time.maxRealGap)
        val perSecond = (Tuning.Time.stepsPerSecond / Tuning.Time.stepsPerTick).toDouble() * Tuning.Time.realUnitsPerTick.toDouble()
        units += (gap * timeScale * perSecond).roundToLong()
        val perTick = Tuning.Time.realUnitsPerTick.toLong()
        val n = units / perTick
        units -= n * perTick
        return n.toInt()
    }
}
