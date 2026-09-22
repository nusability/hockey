package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Club
import `in`.nann.smashhockey.core.generated.Drill
import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.Spot
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.generated.World

/**
 * What a match is asked to be (spec §8, §9, §12): who plays, where, how long, and who decides the
 * player's releases. Everything a [Match] does follows from this and its [seed] (§4.3).
 */
data class MatchSetup(
    /** The match stream's seed (§4.3), as the bits of an unsigned 64-bit value. */
    val seed: Long,
    val sport: Sport,
    /** Team 0 (the player's side, attacking +Z). */
    val home: SideSetup,
    val away: SideSetup,
    /** The chosen period length (§8.3, §12). */
    val periodSeconds: Double,
    /** Seconds per revolution of every carrier's orbit (§5.1). */
    val orbitPeriod: Double,
    /** A cup match: level after three periods goes to sudden-death overtime (§8.4). */
    val cup: Boolean,
    val control: Control,
) {
    companion object {
        /** The demo behind the menus (§9): both sides automatic, the demo's orbit period. */
        fun demo(seed: Long, world: World, home: SideSetup, away: SideSetup, periodSeconds: Double) = MatchSetup(
            seed, world.sport, home, away, periodSeconds, Tuning.Orbit.demoPeriod, cup = false, control = Control.AUTOMATIC,
        )
    }
}

/** One side of a match: rating (§2.1), tactics (§12) and formation (§3). */
data class SideSetup(val rating: Int, val tactics: Tactics, val formation: Formation) {
    companion object {
        /** A club as an AI side: its rating and tactics, the balanced formation (§3). */
        fun club(club: Club) = SideSetup(club.rating, club.tactics, Formation.BALANCED)
    }
}

/** A training drill (§10): the drill, the seed, and the coach's settings that still apply. */
data class DrillSetup(val drill: Drill, val seed: Long, val tactics: Tactics, val orbitPeriod: Double)

/** Who decides team 0's outfield releases (§5.3, §9). */
enum class Control(val key: String) {
    /** The player's finger: team 0's outfield carriers wait for a lift. */
    PLAYER("player"),
    /** Both sides fully automatic — the demo (§9). */
    AUTOMATIC("automatic");

    companion object {
        fun of(key: String): Control = entries.firstOrNull { it.key == key }
            ?: throw IllegalArgumentException("unknown control '$key'")
    }
}

/** The match states (§8.1); [READY] and [LOST] occur only in drills (§10). */
enum class MatchState(val key: String) {
    FACE_OFF("faceoff"), PLAY("play"), GOAL("goal"), WHISTLE("whistle"), PERIOD_END("periodEnd"),
    READY("ready"), LOST("lost"), ENDED("ended"),
}

/** Why a drill was interrupted (§10). */
enum class DrillInterruption(val key: String) {
    SAVED("saved"), STOLEN("stolen"), WRONG_NET("wrongNet"), NO_ASSIST("noAssist"), DEAD_BALL("deadBall"),
}

/** How a match or drill finished. */
enum class MatchResult(val key: String) { WON("won"), LOST("lost"), DRAWN("drawn") }

/** The kind of a shot-type release (§5.4, §8.6). Passes are not shot-type. */
enum class ReleaseKind(val key: String) { SHOT("shot"), UNASSISTED("unassisted"), CLEAR("clear") }

/** What happened during a tick, for presentation and audio. Players are roster indices (§3). */
sealed interface MatchEvent {
    data class FaceOff(val spot: Spot) : MatchEvent
    /** Play starts: a face-off drops or a drill's "get ready" ends. */
    data object Play : MatchEvent
    /** A drill (re)starts its "get ready" (§10). */
    data object Ready : MatchEvent
    data class Pickup(val player: Int) : MatchEvent
    data class Pass(val from: Int, val to: Int) : MatchEvent
    data class Shot(val by: Int, val kind: ReleaseKind) : MatchEvent
    data class Steal(val by: Int, val from: Int) : MatchEvent
    data class Save(val by: Int) : MatchEvent
    data class Block(val by: Int) : MatchEvent
    data object Post : MatchEvent
    data class Board(val speed: Double) : MatchEvent
    data class Goal(val team: Int, val scorer: Int?, val assist: Int?, val ownGoal: Boolean) : MatchEvent
    data object Whistle : MatchEvent
    data class PeriodEnd(val period: Int) : MatchEvent
    data class DrillInterrupted(val reason: DrillInterruption) : MatchEvent
    data class End(val result: MatchResult) : MatchEvent
}
