package `in`.nann.smashhockey.core.feel

import `in`.nann.smashhockey.core.generated.Tuning
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The goal nets (spec §8.8): their shape, their cloth sway, a goal's ripple — and the box that holds
 * every vertex an app can ever write for them.
 *
 * The net is the **apps'** (ADR 0008): a world's asset carries the goal frame — the two posts and the
 * crossbar — and nothing else, so that the whole net moves rather than a faint film swaying behind
 * cords baked into the scenery. Both apps build the same four sheets per goal from here and move
 * every one of their points by the same two formulas, so the nets are the same cloth on both
 * platforms. The iOS twin is `SmashCore/Feel/GoalNet.swift`.
 */
object GoalNet {
    /** `presentation.toml [net]` and `[net.sway]`, handed in by the app that draws it. */
    data class Params(
        /** The net's height — the goal frame's (§1). */
        val height: Double,
        /** Cells across the mouth, up the back and the sides, and along the goal's depth. */
        val columns: Int,
        val rows: Int,
        val depth: Int,
        /** A cord's width, and how far it stands off its film so the two never fight. */
        val cord: Double,
        val cordLift: Double,
        /** The cloth: the middle's sway, its period, its phase per metre, and Reduce Motion's share. */
        val sway: Double,
        val swaySeconds: Double,
        val wave: Double,
        val calm: Double,
        /** A goal's ripple: amplitude, decay, frequency, wave number, reach and how long it runs. */
        val ripple: Double,
        val decay: Double,
        val frequency: Double,
        val k: Double,
        val reach: Double,
        val seconds: Double,
    )

    /** A point in the game's frame (metres): x across, y up, z along. */
    data class Point(val x: Double, val y: Double, val z: Double) {
        operator fun plus(b: Point) = Point(x + b.x, y + b.y, z + b.z)
        operator fun times(s: Double) = Point(x * s, y * s, z * s)
    }

    /**
     * One sheet of a net: a grid of [columns] × [rows] cells spanning `origin + u·across + v·up`,
     * swaying along its outward [normal].
     */
    data class Sheet(
        val origin: Point,
        val across: Point,
        val up: Point,
        val normal: Point,
        val columns: Int,
        val rows: Int,
    ) {
        /** The resting point at grid node (i, j), 0 ≤ i ≤ columns, 0 ≤ j ≤ rows. */
        fun point(i: Int, j: Int): Point =
            origin + across * (i.toDouble() / columns) + up * (j.toDouble() / rows)

        /**
         * How freely that node may sway: 0 where the net is laced to its frame or to the next sheet,
         * 1 in the middle — `sin(π·u)·sin(π·v)`. An edge is exactly 0, not `sin(π)`'s rounding: the
         * sheets share those nodes and have to hold them at exactly the same place.
         */
        fun bell(i: Int, j: Int): Double =
            if (i <= 0 || i >= columns || j <= 0 || j >= rows) 0.0
            else sin(PI * i / columns) * sin(PI * j / rows)

        /** The unit vectors along the sheet's two edges: what a cord the other way is made wide by. */
        val acrossUnit: Point get() = unit(across)
        val upUnit: Point get() = unit(up)

        private fun unit(p: Point): Point {
            val len = sqrt(p.x * p.x + p.y * p.y + p.z * p.z)
            return if (len > 0) p * (1 / len) else p
        }
    }

    /**
     * The four sheets of the goal behind the goal line on the [sign] side (−1 is the player's own
     * end): the back, the roof and the two sides. Every sheet's edge sits where the net is laced — to
     * the frame, to the ground or to the next sheet — so the four move as one skin.
     */
    fun sheets(sign: Double, p: Params): List<Sheet> {
        val hw = Tuning.Pitch.goalMouthWidth / 2
        val h = p.height
        val line = sign * Tuning.Pitch.goalLineZ
        val back = sign * (Tuning.Pitch.goalLineZ + Tuning.Pitch.goalDepth)
        val deep = back - line
        val out = mutableListOf(
            // The back: across the mouth, up from the ground, facing away from the pitch.
            Sheet(Point(-hw, 0.0, back), Point(2 * hw, 0.0, 0.0), Point(0.0, h, 0.0),
                Point(0.0, 0.0, sign), p.columns, p.rows),
            // The roof: across the mouth, from the crossbar back, facing up.
            Sheet(Point(-hw, h, line), Point(2 * hw, 0.0, 0.0), Point(0.0, 0.0, deep),
                Point(0.0, 1.0, 0.0), p.columns, p.depth),
        )
        for (sx in listOf(-1.0, 1.0)) {
            // A side: from the post back, up from the ground, facing out across the pitch.
            out += Sheet(Point(sx * hw, 0.0, line), Point(0.0, 0.0, deep), Point(0.0, h, 0.0),
                Point(sx, 0.0, 0.0), p.depth, p.rows)
        }
        return out
    }

    /**
     * How far the node at ([x], [y], [z]) stands off its sheet at real time [t]: the cloth's sway, and
     * a goal's ripple on top of it. [age] is the real seconds since the ball struck at ([strikeX],
     * [strikeY], [strikeZ]) — negative, or past `seconds`, for a net that is only breathing. Reduce
     * Motion keeps `calm` of the sway — calmer, never frozen. Scalars, not points: this runs for every
     * vertex of both nets on every frame, on both platforms.
     */
    @Suppress("LongParameterList")
    fun offset(
        x: Double,
        y: Double,
        z: Double,
        bell: Double,
        t: Double,
        reduceMotion: Boolean,
        strikeX: Double,
        strikeY: Double,
        strikeZ: Double,
        age: Double,
        p: Params,
    ): Double {
        val amplitude = p.sway * if (reduceMotion) p.calm else 1.0
        var d = amplitude * bell * sin(2 * PI * t / p.swaySeconds + p.wave * (x + z))
        if (age >= 0 && age < p.seconds) {
            val dx = x - strikeX; val dy = y - strikeY; val dz = z - strikeZ
            val distance = sqrt(dx * dx + dy * dy + dz * dz)
            d += p.ripple * exp(-p.decay * age) * sin(p.frequency * age - p.k * distance) *
                exp(-distance / p.reach)
        }
        return d
    }

    /**
     * Where a goal's ripple starts: the middle of the back sheet's height, at the ball's x across the
     * mouth, on the goal line [goalZ] names.
     */
    fun strike(goalZ: Double, ballX: Double): Point {
        val hw = Tuning.Pitch.goalMouthWidth / 2
        val sign = if (goalZ > 0) 1.0 else -1.0
        return Point(min(max(ballX, -hw), hw), 0.36, sign * (Tuning.Pitch.goalLineZ + Tuning.Pitch.goalDepth))
    }

    /**
     * How far off its sheet any point can ever be pushed: the sway at full stretch, a fresh goal's
     * ripple, and the cord that stands off the film and is half its own width wide.
     */
    fun reach(p: Params): Double = p.sway + p.ripple + p.cordLift + p.cord / 2

    /** The box in the game's frame holding **every** vertex an app writes for both nets. */
    data class Extent(val x: Double, val yLow: Double, val yHigh: Double, val z: Double)

    /**
     * The four sheets of each goal, their films and their cords, at every moment of the sway and of a
     * goal's ripple, all lie inside this box. It exists because a mesh written in place carries its
     * own bounds and the renderer culls against them (SMASH-33): the nets are written in the pitch's
     * frame on nodes that never move, so this box can never go stale.
     */
    fun extent(p: Params): Extent {
        val r = reach(p)
        return Extent(
            Tuning.Pitch.goalMouthWidth / 2 + r, -r, p.height + r,
            Tuning.Pitch.goalLineZ + Tuning.Pitch.goalDepth + r,
        )
    }
}
