package `in`.nann.smashhockey.core.feel

import `in`.nann.smashhockey.core.generated.SoundCue
import `in`.nann.smashhockey.core.generated.Tuning
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin

/**
 * How a play of an event is mixed (spec §8.8, shared/data/sounds.toml) — the same arithmetic as iOS's
 * playback layer. A sound made *somewhere on the pitch* (it carries an x) follows §8.6's time scale
 * and pans with where it happened; every other sound plays at real speed, centred.
 */
object SoundMix {
    /** dB → linear amplitude. */
    fun amplitude(db: Double): Double = 10.0.pow(db / 20)

    /** A play's pitch factor for a uniform draw [u] in [0, 1): ± [semitones], uniformly in semitones. */
    fun pitch(semitones: Double, u: Double): Double = 2.0.pow((2 * u - 1) * semitones / 12)

    /** A play's rate: its pitch, × the time scale when it happened on the pitch, clamped to the layer's range. */
    fun rate(pitch: Double, timeScale: Double, onPitch: Boolean, min: Double, max: Double): Double =
        (if (onPitch) pitch * timeScale else pitch).coerceIn(min, max)

    /** Where a sound at [x] across the pitch (half-width 15) sits: −1 left … 1 right, [width] at the boards; centred without a place. */
    fun pan(x: Double?, width: Double): Double {
        if (x == null) return 0.0
        return (x / Tuning.Pitch.halfWidth * width).coerceIn(-1.0, 1.0)
    }

    /** Left and right gains for [pan] under a constant-power law (pan 0: both 1/√2). */
    fun stereo(pan: Double): Pair<Double, Double> {
        val a = (pan + 1) * PI / 4
        return cos(a) to sin(a)
    }

    /**
     * Which of [count] variants a play takes for a uniform draw [u] in [0, 1): at random, never the one
     * played last ([last]) when there are two or more.
     */
    fun variant(count: Int, last: Int?, u: Double): Int {
        if (count <= 1) return 0
        if (last == null || last < 0 || last >= count) return minOf((u * count).toInt(), count - 1)
        val pick = minOf((u * (count - 1)).toInt(), count - 2)
        return if (pick >= last) pick + 1 else pick
    }
}

/**
 * The voices a playback layer has (spec §8.8): which one a new play takes. An event already at its
 * `maxVoices` steals its own oldest; otherwise a free voice; otherwise the oldest voice of the lowest
 * priority below the event's; otherwise the play is dropped.
 */
class VoicePool(count: Int) {
    data class Voice(val cue: SoundCue, val priority: Int, val started: Double, val ends: Double)

    private val slots = arrayOfNulls<Voice>(count)
    val voices: List<Voice?> get() = slots.toList()

    /** The voice a play of [cue] starting at [now] and lasting [seconds] takes, or null to drop it. */
    fun claim(cue: SoundCue, now: Double, seconds: Double): Int? {
        val spec = cue.spec
        fun live(i: Int) = slots[i]?.takeIf { it.ends > now }
        val mine = slots.indices.filter { live(it)?.cue == cue }
        val chosen: Int? = if (mine.size >= spec.maxVoices) {
            mine.minByOrNull { slots[it]!!.started }
        } else {
            slots.indices.firstOrNull { live(it) == null }
                ?: slots.indices.filter { slots[it]!!.priority < spec.priority }
                    .minWithOrNull(compareBy<Int>({ slots[it]!!.priority }, { slots[it]!!.started }))
        }
        val i = chosen ?: return null
        slots[i] = Voice(cue, spec.priority, now, now + seconds)
        return i
    }
}
