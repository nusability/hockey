package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Role
import `in`.nann.smashhockey.core.generated.Tuning
import kotlin.math.abs

/** What a renderer draws (spec §5.2, §8): a read-only picture of the match after the last tick. */
data class MatchSnapshot(
    val state: MatchState,
    val players: List<Player>,
    val ball: Ball,
    /** The carrier's aim line, when someone carries the ball. */
    val aim: Aim?,
    /** True when the carrier waits for the player's finger (§5.3). */
    val playerCarrier: Boolean,
    /** Seconds left in the period (or the drill); 0 in overtime. */
    val clock: Double,
    val score: List<Int>,
    val period: Int,
    val overtime: Boolean,
    val time: Double,
    val result: MatchResult?,
) {
    data class Player(
        val team: Int,
        val role: Role,
        val radius: Double,
        val x: Double,
        val z: Double,
        val vx: Double,
        val vz: Double,
        /** The direction they face; `0` points down +Z. */
        val facing: Double,
    )

    data class Ball(
        val x: Double,
        val z: Double,
        val vx: Double,
        val vz: Double,
        val radius: Double,
        /** The carrier's roster index, or null when loose. */
        val carrier: Int?,
        /** The orbit angle in (−π, π] and its direction (+1 or −1). */
        val orbit: Double,
        val orbitDirection: Double,
    )

    /** The aim line (§5.2): where a release now would go, and what it would snap to. */
    sealed interface Aim {
        data class Pass(val to: Int) : Aim
        data object Shot : Aim
        data object Unassisted : Aim
    }
}

val Match.snapshot: MatchSnapshot
    get() {
        val people = players.map { MatchSnapshot.Player(it.team, it.role, it.radius, it.pos.x, it.pos.z, it.vel.x, it.vel.z, it.facing) }
        val c = ball.carrier
        val b = MatchSnapshot.Ball(ball.pos.x, ball.pos.z, ball.vel.x, ball.vel.z, sport.ballRadius, c, ball.orbit, ball.orbitDirection)
        val aim = if (c == null) {
            null
        } else {
            when (val s = snap(c, ball.orbit)) {
                is Snap.Pass -> MatchSnapshot.Aim.Pass(s.to)
                Snap.Shot -> MatchSnapshot.Aim.Shot
                null -> MatchSnapshot.Aim.Unassisted
            }
        }
        return MatchSnapshot(
            state, people, b, aim, c != null && isPlayerControlled(c), clock, scores, period, overtime, time, result,
        )
    }

/** Distance to goal of the last shot-type release — never a pass (§8.6). Null before the first. */
val Match.lastShotDistance: Double? get() = ball.lastShotDistance

/**
 * §8.6: the loose ball in play moving faster than 8 toward a goal mouth (within 0.8 of the posts)
 * and crossing its line within 0.6 s. Presentation decides what to do about it.
 */
val Match.shotAboutToScore: Boolean
    get() {
        val s = Tuning.SlowMotion
        if (state != MatchState.PLAY || ball.carrier != null ||
            Pitch.length(ball.vel.x, ball.vel.z) <= s.shotSpeed || ball.vel.z == 0.0
        ) return false
        for (team in 0 until 2) {
            val gz = Pitch.ownGoalZ(team)
            val t = (gz - ball.pos.z) / ball.vel.z
            if (t < 0 || t > s.shotHorizon) continue
            val crossing = ball.pos.x + ball.vel.x * t
            if (abs(crossing) <= Tuning.Pitch.postX + s.shotPostMargin) return true
        }
        return false
    }
