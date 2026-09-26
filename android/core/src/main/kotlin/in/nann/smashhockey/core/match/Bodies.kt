package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Patrol
import `in`.nann.smashhockey.core.generated.Role
import `in`.nann.smashhockey.core.generated.Tuning
import kotlin.math.PI

/**
 * One player on the pitch (spec §3): who they are, where they are, and what their automatic play
 * currently remembers (§7). Referred to by roster index everywhere.
 */
internal class Athlete(
    val team: Int,
    /** Position in the team's roster (face-off slots, §8.2). */
    val slot: Int,
    val role: Role,
    /** The formation spot (§3) for this team's own attacking direction; in a drill, the start spot. */
    val home: Vec,
    speedFactor: Double,
    rating: Int,
    val patrol: Patrol?,
) {
    /** Where a drill reset puts them (§10). */
    val start: Vec = home
    val radius: Double
    val topSpeed: Double

    init {
        when (role) {
            Role.GOALIE -> {
                radius = Tuning.Player.goalieRadius
                topSpeed = Tuning.Player.goalieTopSpeed * speedFactor
            }
            Role.DUMMY -> {
                radius = Tuning.Player.dummyRadius
                topSpeed = 0.0
            }
            Role.DEFENDER, Role.FORWARD -> {
                radius = Tuning.Player.outfieldRadius
                val base = Tuning.Player.outfieldSpeedBase +
                    (rating.toDouble() - Tuning.Player.ratingOrigin) * Tuning.Player.outfieldSpeedPerRating
                topSpeed = base * speedFactor
            }
        }
    }

    var pos: Vec = home
    var vel: Vec = Vec.ZERO
    var facing: Double = if (team == 0) 0.0 else PI

    // Automatic play (§7) and possession (§6).
    var target: Vec? = null
    var pickupCooldown = 0.0
    var holdTime = 0.0
    var decision: CarrierDecision? = null
    var mark: Int? = null
    var expectPass = 0.0
    var stealContact = 0.0
    /** Committed as a challenger while match time is below this (§7.2). */
    var challengeUntil = 0.0
    /**
     * True while this player is the challenger going for the **ball** rather than covering (§7.2).
     * It is kept for as long as the commitment lasts so the two defenders do not swap jobs several
     * times a second and end up in the same place.
     */
    var onTheBall = false
    var thinkTimer = 0.0
    /** A patrolling dummy's next step reports zero velocity (§10: zero across a reset). */
    var patrolFresh = true

    val isDummy get() = role == Role.DUMMY
    val isGoalie get() = role == Role.GOALIE
    /** Defenders and forwards: the players the rules call "outfield". */
    val isOutfield get() = role == Role.DEFENDER || role == Role.FORWARD
}

/** What an AI carrier has decided to do with the ball (§7.6, §7.8). */
internal sealed interface CarrierDecision {
    data object Shoot : CarrierDecision
    data class Pass(val to: Int) : CarrierDecision
    data object Clear : CarrierDecision
}

/** The ball (spec §5, §6). */
internal class Ball {
    var pos: Vec = Vec.ZERO
    var vel: Vec = Vec.ZERO
    var carrier: Int? = null
    /** The orbit angle, in (−π, π] (§5.1). */
    var orbit: Double = PI
    /** +1 or −1: the direction the ball circles in. */
    var orbitDirection: Double = 1.0
    var lastTouch: Int? = null
    /** The last player to release it (§8.5). */
    var lastReleaser: Int? = null
    var assist: Int? = null
    /** Match time the carrier won it (the settle window, §6.4). */
    var wonAt = 0.0
    /** Match time of the last release of any kind (§7.8); null before the first. */
    var lastReleaseTime: Double? = null
    /** Distance to goal of the last shot-type release (§8.6); null before the first. */
    var lastShotDistance: Double? = null
    var pending: PendingRelease? = null
}

/** A player's release held until the ball snaps (§5.3). */
internal data class PendingRelease(val player: Int, val deadline: Double)

/** What a release would snap to (§5.2). */
internal sealed interface Snap {
    data class Pass(val to: Int) : Snap
    data object Shot : Snap
}
