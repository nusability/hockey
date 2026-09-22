// feel/ — the pure half of how a match looks, sounds and feels (spec §5.2, §8.8, §16.4): numbers and
// decisions the app draws and plays, taken out of the scene so a test can pin them. Nothing here is on
// the simulation path; it reads snapshots and events and never feeds a tick. Its tunables are the
// app's presentation (presentation.toml), handed in by the caller. The iOS twin is SmashCore/Feel/.
package `in`.nann.smashhockey.core.feel

import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.match.Pitch
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * The aim arrow's length (spec §5.2): how far the ribbon runs out from its start, which is the orbit
 * radius plus the presentation's `start` from the carrier's centre, along the orbit angle.
 */
object AimArrow {
    data class Params(
        val maxLength: Double,
        val minLength: Double,
        val passShort: Double,
        val shotShort: Double,
        val boardMargin: Double,
        val boardProbe: Double,
        val probeStep: Double,
    )

    /** What the arrow is showing. */
    sealed interface Kind {
        data object Free : Kind
        /** A pass to a team-mate standing at (x, z). */
        data class Pass(val x: Double, val z: Double) : Kind
        /** A shot at the goal whose centre is at (0, goalZ). */
        data class Shot(val goalZ: Double) : Kind
    }

    /** The ribbon's length for a carrier at (x, z) with the ball at orbit [angle], corners of radius [corner] (§1). */
    fun length(kind: Kind, x: Double, z: Double, angle: Double, corner: Double, p: Params): Double {
        val r = Tuning.Orbit.radius
        val len = when (kind) {
            Kind.Free -> p.maxLength
            is Kind.Pass -> Pitch.length(kind.x - x, kind.z - z) - r - p.passShort
            is Kind.Shot -> Pitch.length(-x, kind.goalZ - z) - r - p.shotShort
        }
        val toBoards = boards(x, z, angle, corner, p)
        return max(p.minLength, min(len, toBoards - r - p.boardMargin))
    }

    /**
     * How far out along [angle] the pitch stays clear of the boards: marching from 1 m in steps of
     * `probeStep` while under `maxLength + 2`, the last distance whose point is more than `boardProbe`
     * inside the boundary; 0 if the first is not.
     */
    fun boards(x: Double, z: Double, angle: Double, corner: Double, p: Params): Double {
        val dx = sin(angle); val dz = cos(angle)
        var clear = 0.0
        var d = 1.0
        while (d < p.maxLength + 2) {
            if (Pitch.boundary(x + dx * d, z + dz * d, corner).distance > -p.boardProbe) break
            clear = d
            d += p.probeStep
        }
        return clear
    }
}
