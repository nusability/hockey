package `in`.nann.smashhockey.game

import android.content.Intent
import `in`.nann.smashhockey.core.generated.Career
import `in`.nann.smashhockey.core.generated.Club
import `in`.nann.smashhockey.core.generated.Drill
import `in`.nann.smashhockey.core.generated.SaveRecord
import `in`.nann.smashhockey.core.generated.World
import `in`.nann.smashhockey.core.match.Control
import `in`.nann.smashhockey.core.match.Match
import `in`.nann.smashhockey.core.match.MatchSetup
import `in`.nann.smashhockey.core.match.SideSetup
import `in`.nann.smashhockey.core.season.QuickMatch
import `in`.nann.smashhockey.core.season.demo
import `in`.nann.smashhockey.core.season.drill
import `in`.nann.smashhockey.core.season.homeWorld
import `in`.nann.smashhockey.core.season.kit
import `in`.nann.smashhockey.core.season.playerFixture
import `in`.nann.smashhockey.core.season.quickMatch
import `in`.nann.smashhockey.core.season.seasonMatch
import `in`.nann.smashhockey.core.season.short
import `in`.nann.smashhockey.core.season.sideTeam
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.scene.TeamColours
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * A match to put on the pitch (spec §8–§11) — the twin of iOS's MatchPlan.swift: which one it is,
 * and — with the save — everything it is made of. The core decides the teams, rules and settings
 * (`SaveRecord.seasonMatch` & co.); this adds what only the screen needs: the world, the kits, the
 * short codes.
 */
sealed interface MatchPlan {
    /** The player's fixture of the current matchday (§11.2). */
    data object Season : MatchPlan
    /** A friendly against a drawn club in a drawn world (§11.5). */
    data class Quick(val draw: QuickMatch) : MatchPlan
    /** A drill (§10). */
    data class Practice(val drill: Drill) : MatchPlan
    /** The demo behind the menus (§9): the n-th, in the worlds in turn, against [opponent]. */
    data class Demo(val round: Int, val opponent: Club) : MatchPlan
    /** A developer shortcut (`--es quick home,away,world`): two named clubs, the player on the first. */
    data class Friendly(val home: Club, val away: Club, val world: World) : MatchPlan

    val isDemo get() = this is Demo

    /** The match itself and how it looks; null when there is nothing to play (no fixture). */
    fun kickoff(save: SaveRecord, seed: Long): Kickoff? {
        val career = save.career
        val mine = career?.kit(career.team) ?: (Career.demoClub.primary to Career.demoClub.secondary)
        val myCode = career?.short(career.team) ?: Career.demoClub.short
        val me = TeamColours(mine.first, mine.second)
        fun kit(c: Club) = TeamColours(c.primary, c.secondary)
        fun name(c: Club) = L(c.nameKey).uppercase()
        val myName = career?.let { Names.team(it.team, it) } ?: name(Career.demoClub)
        return when (this) {
            Season -> {
                val c = career ?: return null
                val setup = save.seasonMatch(seed) ?: return null
                val f = save.playerFixture ?: return null
                val them = if (f.home == c.team) f.away else f.home
                val k = c.kit(them)
                Kickoff(Match(setup), setup.orbitPeriod, c.homeWorld(f.home), dress(me, TeamColours(k.first, k.second)),
                    listOf(myCode, c.short(them)), null, listOf(Names.team(f.home, c), Names.team(f.away, c)))
            }
            is Quick -> {
                val setup = save.quickMatch(draw, seed)
                Kickoff(Match(setup), setup.orbitPeriod, draw.world, dress(me, kit(draw.opponent)),
                    listOf(myCode, draw.opponent.short), null, listOf(myName, name(draw.opponent)))
            }
            is Practice -> {
                val setup = save.drill(drill, seed)
                val sparring = TeamColours(Presentation.Player.sparringPrimary, Presentation.Player.sparringSecondary)
                Kickoff(Match(setup), setup.orbitPeriod, drill.world, dress(me, sparring), null, drill.goals)
            }
            is Demo -> {
                val world = World.entries[round % World.entries.size]
                val setup = save.demo(world, opponent, seed)
                Kickoff(Match(setup), setup.orbitPeriod, world, dress(me, kit(opponent)), listOf(myCode, opponent.short), null)
            }
            is Friendly -> {
                val setup = MatchSetup(seed, world.sport, SideSetup.club(home), SideSetup.club(away), save.board.periodSeconds,
                    save.board.ballSpinSeconds, false, Control.PLAYER)
                Kickoff(Match(setup), setup.orbitPeriod, world, dress(kit(home), kit(away)), listOf(home.short, away.short), null,
                    listOf(name(home), name(away)))
            }
        }
    }

    companion object {
        /** A demo against a random club other than the player's own (§9) — presentation's own draw. */
        fun demo(round: Int, save: SaveRecord): MatchPlan {
            val others = Club.entries.filter { it != save.sideTeam.club }
            return Demo(round, others.random())
        }

        fun seed(): Long = Random.nextLong()

        /** The away side changes into its secondary when the primaries clash. */
        fun dress(home: TeamColours, away: TeamColours): List<TeamColours> =
            listOf(home, if (clash(home.primary, away.primary)) TeamColours(away.secondary, away.primary) else away)

        fun clash(a: Int, b: Int): Boolean {
            fun c(v: Int, s: Int) = ((v shr s) and 0xFF).toDouble()
            val d = listOf(16, 8, 0).map { c(a, it) - c(b, it) }
            return sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]) < Presentation.Player.kitClash
        }
    }
}

/** A match ready to play, and what the screen needs to draw it. */
class Kickoff(
    val match: Match,
    val orbitPeriod: Double,
    val world: World,
    /** The two sides' kits, the player's first. */
    val colours: List<TeamColours>,
    /** The short codes above the score; null in a drill. */
    val codes: List<String>?,
    /** A drill's goal target; null in a match. */
    val drillGoals: Int?,
    /** The home and the away side's names, for the intro banner (§16.4); null in a drill and the demo. */
    val names: List<String>? = null,
)

/**
 * Where the app opens (the developer shortcuts; a player's launch has none of these) — the twin of
 * iOS's `Launch`, from intent extras with the launch arguments' names:
 *
 *     adb shell am start -n in.nann.smashhockey/.MainActivity --es scene match --es quick mossfoxes,glowowls,space
 *     … --es scene match --ei drill 1          straight into a drill, by number (§10)
 *     … --es scene match --ez demo true        the menus, as on any launch (the demo plays behind them)
 *
 * A malformed extra fails loud.
 */
object Launch {
    fun plan(intent: Intent): MatchPlan? {
        if (intent.getStringExtra("scene") != "match") return null
        intent.getStringExtra("quick")?.let { q ->
            val parts = q.split(",")
            require(parts.size == 3 && parts[0] != parts[1]) { "quick wants home,away,world — two different clubs and a world, got '$q'" }
            return MatchPlan.Friendly(Club.of(parts[0]), Club.of(parts[1]), World.of(parts[2]))
        }
        if (intent.hasExtra("drill")) {
            val n = intent.getIntExtra("drill", -1)
            val drill = Drill.entries.firstOrNull { it.number == n }
                ?: throw IllegalArgumentException("drill wants a drill number 1…${Drill.entries.size}, got $n")
            return MatchPlan.Practice(drill)
        }
        return null
    }
}
