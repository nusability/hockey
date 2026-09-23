package `in`.nann.smashhockey.core.feel

import `in`.nann.smashhockey.core.generated.Tuning
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The goal nets (spec §8.8): their shape, their cloth sway, the ripple the ball knocks into them —
 * and the box that holds every vertex an app can ever write for them.
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
        /**
         * A contact's ripple: the dent a ball at full speed makes, its decay, its frequency, its
         * wave number, how far it reaches from the contact and how long it runs.
         */
        val ripple: Double,
        val decay: Double,
        val frequency: Double,
        val k: Double,
        val reach: Double,
        val seconds: Double,
        /**
         * The speed **into** a sheet that dents it the full [ripple], and the least speed the cloth
         * answers at all — below it the ball is leaning on the net, not striking it.
         */
        val hitSpeed: Double,
        val hitLeast: Double,
    )

    /** A point in the game's frame (metres): x across, y up, z along. */
    data class Point(val x: Double, val y: Double, val z: Double) {
        operator fun plus(b: Point) = Point(x + b.x, y + b.y, z + b.z)
        operator fun minus(b: Point) = Point(x - b.x, y - b.y, z - b.z)
        operator fun times(s: Double) = Point(x * s, y * s, z * s)
        fun dot(b: Point): Double = x * b.x + y * b.y + z * b.z
        val length: Double get() = sqrt(dot(this))
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

    // ---- what the ball does to the cloth

    /**
     * The ball meeting a net: which [goal] (0 is the −z end, 1 the +z end), which of that goal's
     * [sheets] it struck, where on it, how fast it was going **into** the sheet, and what share of a
     * full-speed dent that is.
     */
    data class Touch(
        val goal: Int,
        val sheet: Int,
        val point: Point,
        val speed: Double,
        val strength: Double,
    )

    /**
     * Where the ball meets the cloth over one frame of the match: its place and velocity at the
     * frame's start, and how many **match** [seconds] the frame ran for.
     *
     * §6.2 resolves the collision itself — the net is solid, the ball is pushed out and bounced —
     * and does it per tick, twice a frame, so by the time an app reads the snapshot the ball has
     * already left the cloth. So this sweeps the ball along the path it *would* have taken had
     * nothing stopped it and asks where that path first reaches a sheet: the same answer the physics
     * gave, a frame later and in the app's own hands. It answers on the **rising edge** — the frame
     * the path first reaches a sheet the ball was not already standing on — so a shot into the side
     * netting, a rebound off the back from inside and a goal are each one contact, and a ball leaning
     * on the net is none. [ballY] is the height the app draws the ball's centre at; a ball on the ice
     * can only ever reach the back and the sides, and the roof is written the same way for the day it
     * can. Null when the ball misses, or when it is only brushing the net slower than `hitLeast`.
     */
    @Suppress("LongParameterList", "ReturnCount", "NestedBlockDepth")
    fun touch(
        x: Double,
        z: Double,
        vx: Double,
        vz: Double,
        seconds: Double,
        ballY: Double,
        radius: Double,
        p: Params,
    ): Touch? {
        if (seconds <= 0) return null
        // The net's cloth is drawn on the goal frame's own lines, while §6.2 holds the ball off a box
        // `netFrameMargin` outside it — so a ball resting against the net sits that much proud of its
        // sheet. The band a ball counts as touching a sheet in is that gap on the outside and its own
        // radius on the inside.
        val slack = radius + Tuning.Pitch.netFrameMargin
        val from = Point(x, ballY, z)
        val free = Point(x + vx * seconds, ballY, z + vz * seconds)
        var bestWhen = Double.POSITIVE_INFINITY
        var best: Touch? = null
        for ((goal, sign) in listOf(-1.0, 1.0).withIndex()) {
            if (max(sign * z, sign * free.z) <= Tuning.Pitch.goalLineZ - slack) continue
            for ((index, sheet) in sheets(sign, p).withIndex()) {
                val s0 = (from - sheet.origin).dot(sheet.normal)
                val s1 = (free - sheet.origin).dot(sheet.normal)
                if (s0 >= -radius && s0 <= slack) continue        // already on this sheet
                if (min(s0, s1) > slack || max(s0, s1) < -radius) continue
                // Where along the path the ball's surface first meets the sheet: from outside that is
                // the band's outer edge, from inside it is its inner one.
                val edge = if (s1 < s0) slack else -radius
                val when0 = if (s1 == s0) 0.0 else min(max((edge - s0) / (s1 - s0), 0.0), 1.0)
                val at = from + (free - from) * when0
                val d = at - sheet.origin
                val a = d.dot(sheet.acrossUnit)
                val u = d.dot(sheet.upUnit)
                val la = sheet.across.length
                val lu = sheet.up.length
                if (a < -slack || a > la + slack || u < -slack || u > lu + slack) continue
                // The ball's speed into the sheet — its size, not its sign: a sheet is struck from
                // either side, and the rising edge is what says the ball was on its way into it.
                val speed = abs(vx * sheet.normal.x + vz * sheet.normal.z)
                if (speed < p.hitLeast || when0 >= bestWhen) continue
                bestWhen = when0
                best = Touch(
                    goal, index,
                    sheet.origin + sheet.acrossUnit * min(max(a, 0.0), la) + sheet.upUnit * min(max(u, 0.0), lu),
                    speed, min(1.0, speed / p.hitSpeed),
                )
            }
        }
        return best
    }

    /**
     * How far the node at ([x], [y], [z]) stands off its sheet at real time [t]: the cloth's sway, and
     * the ripple of the ball's last contact on top of it. [age] is the real seconds since the ball
     * struck at ([strikeX], [strikeY], [strikeZ]) at [strength] of a full-speed dent — negative, or
     * past `seconds`, for a net that is only breathing. Both terms are bound by the node's [bell], so
     * the edges the net is laced along never move and the four sheets stay one skin. Reduce Motion
     * keeps `calm` of the sway and the same share of a dent — calmer, never frozen. Scalars, not
     * points: this runs for every vertex of both nets on every frame, on both platforms.
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
        strength: Double,
        p: Params,
    ): Double {
        val calm = if (reduceMotion) p.calm else 1.0
        var d = p.sway * calm * bell * sin(2 * PI * t / p.swaySeconds + p.wave * (x + z))
        if (age >= 0 && age < p.seconds && strength > 0) {
            val dx = x - strikeX; val dy = y - strikeY; val dz = z - strikeZ
            val distance = sqrt(dx * dx + dy * dy + dz * dz)
            d += p.ripple * strength * calm * bell * exp(-p.decay * age) *
                sin(p.frequency * age - p.k * distance) * exp(-distance / p.reach)
        }
        return d
    }

    /**
     * How far off its sheet any point can ever be pushed: the sway at full stretch, the deepest dent
     * a ball can knock into it, and the cord that stands off the film and is half its own width wide.
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
