package `in`.nann.smashhockey.core

import `in`.nann.smashhockey.core.generated.Career
import `in`.nann.smashhockey.core.generated.Club
import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.generated.CupRound
import `in`.nann.smashhockey.core.generated.Drill
import `in`.nann.smashhockey.core.generated.DrillRule
import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.GeneratedConstantBits
import `in`.nann.smashhockey.core.generated.MatchdayStep
import `in`.nann.smashhockey.core.generated.Patrol
import `in`.nann.smashhockey.core.generated.Season
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Spot
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.generated.World
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The generated config (shared/data/ → generated/): every declared double arrives with the exact
 * bits the declaration names, and the tables hold what the spec says they hold.
 */
class GeneratedDataTest {
    @Test fun everyDeclaredDoubleHasItsExactBits() {
        assertTrue(GeneratedConstantBits.all.size > 300)
        val bad = GeneratedConstantBits.all.filter { (_, value, bits) -> value.toRawBits() != bits }
        assertTrue("constants whose bits differ from the declaration: $bad", bad.isEmpty())
    }

    @Test fun theTablesMatchTheSpec() {
        assertEquals(8, Club.entries.size) // §2.1
        assertEquals(8, Club.entries.map { it.short }.toSet().size)
        assertEquals(0.65, Club.GLOWOWLS.tactics.pressing, 0.0)
        assertEquals(Tactics.defaults.passing, Club.GLOWOWLS.tactics.passing, 0.0)
        assertTrue(Club.WOLVES.world == World.HIMALAYA && World.HIMALAYA.sport == Sport.ICE)
        assertTrue(Career.createdRating == 77 && Career.createdReplaces == Club.WOLVES) // §2.2
        assertTrue(Formation.entries.size == 5 && Formation.entries.all { it.players.size == 5 })
        assertEquals(Spot(0.0, -25.0), Formation.goalie) // §3
        assertTrue(Drill.entries.size == 8 && Drill.SCRIMMAGE.ballTo == 1) // §10
        assertEquals(Patrol(Spot(-8.0, 15.0), 0.9, 1.5), Drill.MOVING.away[2].patrol)
        assertTrue(Drill.SCRIMMAGE.rule == DrillRule.FREE_PLAY && Drill.PASS.rule == DrillRule.ASSIST)
        assertEquals(17, Season.plan.size) // §11.1
        assertEquals(MatchdayStep.Cup(CupRound.QUARTER_FINAL), Season.plan[4])
        assertEquals(MatchdayStep.Cup(CupRound.FINAL), Season.plan.last())
        assertEquals(1.0 / 240.0, Tuning.Time.stepSeconds, 0.0) // §4.1
        assertEquals(listOf(1.4, 3.2), listOf(Tuning.Board.ballSpinSeconds.first(), Tuning.Board.ballSpinSeconds.last()))
        assertEquals(8.5, Sport.ICE.cornerRadius, 0.0) // §1
    }

    @Test fun everyCopyKeyIsDeclaredOnce() {
        assertEquals(CopyKey.entries.size, CopyKey.entries.map { it.key }.toSet().size)
        assertEquals(listOf("league", "cup"), CopyKey.MENU_TROPHIES.arguments)
        assertEquals(CopyKey.PLAY_BUTTON, CopyKey.of("play.button"))
        assertEquals("play_button", CopyKey.PLAY_BUTTON.resourceName)
        assertEquals(CopyKey.CLUB_NEBULA_NAME, Club.NEBULA.nameKey)
    }

    @Test(expected = IllegalArgumentException::class)
    fun anUndeclaredKeyFailsLoud() {
        Club.of("nonesuch")
    }
}
