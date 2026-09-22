// feel/ — the pure half of how a match looks, sounds and feels (spec §5.2, §8.8, §16.4): numbers and
// decisions the app draws and plays, taken out of the scene so a test can pin them. Nothing here is on
// the simulation path; it reads snapshots and events and never feeds a tick. Its tunables are the
// app's presentation (presentation.toml), handed in by the caller. The iOS twin is SmashCore/Feel/.
package `in`.nann.smashhockey.core.feel

import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.match.MatchSnapshot
import `in`.nann.smashhockey.core.match.MatchState
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

    /** What the lock-on marker shows (spec §5.2). */
    sealed interface Lock {
        data object None : Lock
        /** The receiver's ring and the dotted line to their lead point. */
        data class Pass(val to: Int) : Lock
        /** The glow across the goal mouth. */
        data object Shot : Lock
    }

    /** What the arrow shows this frame. */
    data class Look(
        /** The ribbon, its glow, the arrowhead and the ring the ball circles on are drawn. */
        val arrow: Boolean,
        /** 0 free (yellow), 1 a pass (green), 2 a shot (pink) — `[aim]`'s three colours in order. */
        val colour: Int,
        val lock: Lock,
        /** 0…1 — how far the lock-on has faded in since this snap began. */
        val fade: Double,
    ) {
        /** Whether a release now would snap: the arrow pulses and its glow lifts. */
        val snapped: Boolean get() = colour != 0

        companion object { val HIDDEN = Look(false, 0, Lock.None, 0.0) }
    }

    /**
     * The arrow's state between frames (spec §5.2) — which snap is being shown and since when — so the
     * arrow is right at **every** transition: the match leaving and re-entering play, a snap beginning,
     * changing or ending, the ball changing hands, a restart. Both apps drive their arrow from this;
     * nothing about it is a platform's own. The iOS twin is `AimArrow.Showing`.
     */
    class Showing {
        /** The snap on screen: whose it is and what it aims at. Null while the arrow is hidden, so the
         *  next one fades in from nothing rather than appearing fully lit. */
        private var carrier: Int? = null
        private var aim: MatchSnapshot.Aim? = null
        /** The real second the snap on screen began. */
        private var since = 0.0

        /**
         * One frame. [clock] is real seconds, monotonic for the life of the match scene; [fadeIn] is
         * the lock-on's fade (`[aim.lock] fade_in`).
         */
        fun frame(
            state: MatchState,
            playerCarrier: Boolean,
            carrier: Int?,
            aim: MatchSnapshot.Aim?,
            clock: Double,
            fadeIn: Double,
        ): Look {
            if (!playerCarrier || carrier == null || aim == null ||
                (state != MatchState.PLAY && state != MatchState.READY)
            ) {
                this.carrier = null
                this.aim = null
                return Look.HIDDEN
            }
            // A snap begins when what it aims at changes — and when the ball changes hands, which is a
            // new snap even when it aims at the same place.
            if (this.carrier != carrier || this.aim != aim) {
                this.carrier = carrier; this.aim = aim; since = clock
            }
            // Never run backwards: a clock that jumps back (a new scene) restarts the fade.
            if (clock < since) since = clock
            val fade = if (fadeIn > 0) min(1.0, (clock - since) / fadeIn) else 1.0
            return when (aim) {
                MatchSnapshot.Aim.Unassisted -> Look(true, 0, Lock.None, 0.0)
                is MatchSnapshot.Aim.Pass -> Look(true, 1, Lock.Pass(aim.to), fade)
                MatchSnapshot.Aim.Shot -> Look(true, 2, Lock.Shot, fade)
            }
        }
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
