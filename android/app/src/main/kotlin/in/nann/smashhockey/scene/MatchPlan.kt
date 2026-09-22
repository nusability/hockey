package `in`.nann.smashhockey.scene

import android.content.Intent
import `in`.nann.smashhockey.core.generated.Career
import `in`.nann.smashhockey.core.generated.Club
import `in`.nann.smashhockey.core.generated.Drill
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.generated.World
import `in`.nann.smashhockey.core.match.Control
import `in`.nann.smashhockey.core.match.DrillSetup
import `in`.nann.smashhockey.core.match.Match
import `in`.nann.smashhockey.core.match.MatchSetup
import `in`.nann.smashhockey.core.match.SideSetup
import `in`.nann.smashhockey.generated.Presentation
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * What to put on screen — a debug entry until the menus exist (SMASH-11), the twin of iOS's
 * MatchPlan.swift, read from intent extras with the launch arguments' names:
 *
 *     adb shell am start -n in.nann.smashhockey/.MainActivity --es scene match --es quick mossfoxes,glowowls,space
 *     … --es scene match --ei drill 1          a drill, by number (§10)
 *     … --es scene match --ez demo true        the demo (§9), both sides automatic
 *     … --el seed 42                           optional: the match stream's seed (§4.3)
 */
sealed interface MatchPlan {
    data class Quick(val home: Club, val away: Club, val place: World) : MatchPlan
    data class Practice(val drill: Drill) : MatchPlan
    /** The demo's n-th match: the worlds in turn (§9). */
    data class Demo(val round: Int) : MatchPlan

    val world: World
        get() = when (this) {
            is Quick -> place
            is Practice -> drill.world
            is Demo -> World.entries[round % World.entries.size]
        }

    /** The match, set up with the coach's defaults (no board is saved yet, §12), and its orbit period. */
    fun start(seed: Long): Pair<Match, Double> {
        val spin = Tuning.Board.ballSpinSecondsDefault
        return when (this) {
            is Quick -> Match(MatchSetup(seed, place.sport, SideSetup.club(home), SideSetup.club(away),
                Tuning.Board.periodSecondsDefault, spin, false, Control.PLAYER)) to spin
            is Practice -> Match(DrillSetup(drill, seed, Tactics.defaults, spin)) to spin
            is Demo -> Match(MatchSetup.demo(seed, world, SideSetup.club(Career.demoClub), SideSetup.club(demoOpponent(seed)),
                Tuning.Board.periodSecondsDefault)) to Tuning.Orbit.demoPeriod
        }
    }

    /** The two sides' kits; the away side changes into its secondary when the primaries clash. */
    fun colours(seed: Long): List<TeamColours> {
        fun kit(c: Club) = TeamColours(c.primary, c.secondary)
        val sides = when (this) {
            is Quick -> listOf(kit(home), kit(away))
            is Practice -> listOf(kit(Career.demoClub), TeamColours(Presentation.Player.sparringPrimary, Presentation.Player.sparringSecondary))
            is Demo -> listOf(kit(Career.demoClub), kit(demoOpponent(seed)))
        }
        val away = if (clash(sides[0].primary, sides[1].primary)) TeamColours(sides[1].secondary, sides[1].primary) else sides[1]
        return listOf(sides[0], away)
    }

    fun codes(seed: Long): List<String>? = when (this) {
        is Quick -> listOf(home.short, away.short)
        is Practice -> null
        is Demo -> listOf(Career.demoClub.short, demoOpponent(seed).short)
    }

    companion object {
        /** The plan the intent asks for; null unless `scene` is `match`. A malformed extra fails loud. */
        fun fromIntent(intent: Intent): MatchPlan? {
            if (intent.getStringExtra("scene") != "match") return null
            intent.getStringExtra("quick")?.let { q ->
                val parts = q.split(",")
                require(parts.size == 3 && parts[0] != parts[1]) { "quick wants home,away,world — two different clubs and a world, got '$q'" }
                return Quick(Club.of(parts[0]), Club.of(parts[1]), World.of(parts[2]))
            }
            if (intent.hasExtra("drill")) {
                val n = intent.getIntExtra("drill", -1)
                val drill = Drill.entries.firstOrNull { it.number == n }
                    ?: throw IllegalArgumentException("drill wants a drill number 1…${Drill.entries.size}, got $n")
                return Practice(drill)
            }
            return Demo(0)
        }

        fun seed(intent: Intent?): Long =
            if (intent != null && intent.hasExtra("seed")) intent.getLongExtra("seed", 0) else Random.nextLong()

        private fun demoOpponent(seed: Long): Club {
            val others = Club.entries.filter { it != Career.demoClub }
            return others[java.lang.Long.remainderUnsigned(seed, others.size.toLong()).toInt()]
        }

        fun clash(a: Int, b: Int): Boolean {
            fun c(v: Int, s: Int) = ((v shr s) and 0xFF).toDouble()
            val d = listOf(16, 8, 0).map { c(a, it) - c(b, it) }
            return sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]) < Presentation.Player.kitClash
        }
    }
}
