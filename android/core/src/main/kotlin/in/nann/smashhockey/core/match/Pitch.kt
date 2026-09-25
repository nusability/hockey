package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Spot
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.math.DetMath
import kotlin.math.PI
import kotlin.math.abs

/** A point or direction on the pitch: x across, z along (spec §1). */
data class Vec(val x: Double, val z: Double) {
    companion object {
        val ZERO = Vec(0.0, 0.0)
    }
}

/**
 * The pitch's geometry and the helpers every rule is written in (spec §1, §4.4).
 *
 * Each helper evaluates in one fixed order — the order iOS's `Pitch.swift` uses too; that order,
 * not merely the formula, keeps the two simulations bit-identical. `lesser`, `greater` and
 * `clamp` are spelled out rather than taken from `kotlin.math` (whose `min(0.0, -0.0)` is `-0.0`)
 * so a signed zero comes out the same on both platforms.
 */
internal object Pitch {
    const val TWO_PI = 2.0 * PI

    fun length(x: Double, z: Double): Double = DetMath.length(x, z)

    fun distance(a: Vec, b: Vec): Double = DetMath.length(a.x - b.x, a.z - b.z)

    fun lesser(a: Double, b: Double): Double = if (b < a) b else a
    fun greater(a: Double, b: Double): Double = if (b > a) b else a
    fun clamp(v: Double, lo: Double, hi: Double): Double = if (v < lo) lo else if (v > hi) hi else v

    /** The unit vector along (x, z), or zero when it is shorter than the direction epsilon. */
    fun unit(x: Double, z: Double): Vec {
        val l = length(x, z)
        return if (l > Tuning.Sim.directionEpsilon) Vec(x / l, z / l) else Vec.ZERO
    }

    /** a − b wrapped into [−π, π]. */
    fun angleDiff(a: Double, b: Double): Double {
        var d = a - b
        while (d > PI) d -= TWO_PI
        while (d < -PI) d += TWO_PI
        return d
    }

    /** An angle wrapped into (−π, π]. */
    fun wrap(a: Double): Double {
        var w = a
        while (w > PI) w -= TWO_PI
        while (w <= -PI) w += TWO_PI
        return w
    }

    /** The direction angle of (x, z); `0` points down +Z. */
    fun heading(x: Double, z: Double): Double = DetMath.atan2(x, z)

    /** Distance from [p] to the segment [a]–[b]. */
    fun segmentDistance(p: Vec, a: Vec, b: Vec): Double {
        val abx = b.x - a.x
        val abz = b.z - a.z
        val l2 = abx * abx + abz * abz
        var t = 0.0
        if (l2 > 0) {
            val dot = (p.x - a.x) * abx + (p.z - a.z) * abz
            t = clamp(dot / l2, 0.0, 1.0)
        }
        val cx = a.x + abx * t
        val cz = a.z + abz * t
        return length(p.x - cx, p.z - cz)
    }

    /** +1 for team 0 (attacking +Z), −1 for team 1. */
    fun direction(team: Int): Double = if (team == 0) 1.0 else -1.0

    fun ownGoalZ(team: Int): Double = -direction(team) * Tuning.Pitch.goalLineZ
    fun attackGoalZ(team: Int): Double = direction(team) * Tuning.Pitch.goalLineZ

    /**
     * Pushes a point out of the net [team] defends, by the nearest way out of the three the net has
     * — its **mouth**, its **back** or one of its **sides** — with the point kept [r] clear of the
     * cloth. Returns the point untouched when it is already outside.
     *
     * This is where a **carried** ball is kept out of the net (§5.1). The loose-ball solver (§6.2)
     * uses the same frame but not this function, because for a loose ball the mouth is not a way out:
     * crossing it is the goal test. A carried ball is the other case — the orbit can carry it over
     * the goal line through the open mouth, which is allowed and is not a goal, so the mouth is the
     * nearest way out from in there and it has to be one of the three.
     */
    fun pushOutOfNet(p: Vec, team: Int, r: Double): Vec {
        val gz = ownGoalZ(team)
        val dir = direction(team)
        val hw = Tuning.Pitch.goalMouthWidth / 2 + Tuning.Pitch.netFrameMargin + r
        val deep = Tuning.Pitch.goalDepth + Tuning.Pitch.netFrameMargin + r
        // How far past the goal line, into the net, the point is.
        val into = -dir * (p.z - gz)
        if (!(abs(p.x) < hw && into > -r && into < deep)) return p
        val outMouth = into + r
        val outBack = deep - into
        val outSide = hw - abs(p.x)
        val least = lesser(lesser(outMouth, outBack), outSide)
        if (least == outSide) return Vec(if (p.x >= 0) hw else -hw, p.z)
        if (least == outMouth) return Vec(p.x, gz + dir * r)
        return Vec(p.x, gz - dir * deep)
    }

    /** Signed distance to the boundary's rounded rectangle (negative inside) and its outward normal. */
    class Boundary(val distance: Double, val normal: Vec)

    fun boundary(x: Double, z: Double, corner: Double): Boundary {
        val qx = abs(x) - (Tuning.Pitch.halfWidth - corner)
        val qz = abs(z) - (Tuning.Pitch.halfLength - corner)
        val sx = if (x >= 0) 1.0 else -1.0
        val sz = if (z >= 0) 1.0 else -1.0
        if (qx > 0 && qz > 0) {
            val l = length(qx, qz)
            return Boundary(l - corner, Vec(sx * (qx / l), sz * (qz / l)))
        }
        if (qx >= qz) return Boundary(qx - corner, Vec(sx, 0.0))
        return Boundary(qz - corner, Vec(0.0, sz))
    }

    /** The nine face-off spots (§1): the centre, then the neutral and the end spots. */
    val faceOffSpots: List<Spot> = listOf(Tuning.Pitch.faceoffCenter) + Tuning.Pitch.faceoffNeutral + Tuning.Pitch.faceoffEnd
}
