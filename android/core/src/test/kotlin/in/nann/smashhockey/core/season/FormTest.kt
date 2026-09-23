package `in`.nann.smashhockey.core.season

import `in`.nann.smashhockey.core.generated.Career
import `in`.nann.smashhockey.core.generated.CreatedTeam
import `in`.nann.smashhockey.core.generated.CupRound
import `in`.nann.smashhockey.core.generated.MatchdayStep
import `in`.nann.smashhockey.core.generated.SaveRecord
import `in`.nann.smashhockey.core.generated.Season
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.generated.World
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** The team detail behind a table row (spec §16.3a) and editing the created team (§2.2, §16.1). */
class FormTest {
    private val jet = Career.kitPalette[0]

    private fun draft(name: String = "Moss Giants", short: String = "MOG") = TeamDraft(name, short, jet.primary, jet.secondary, World.OCEAN)

    private fun season(seed: Long = 7): SaveRecord = SaveRecord.fresh().createTeam(draft()).startSeason(seed)

    private fun SaveRecord.play(vararg scores: Pair<Int, Int>): SaveRecord {
        var s = this
        for ((f, a) in scores) s = s.recordPlayed(f, a).first
        return s
    }

    private fun SaveRecord.detail(team: TeamKey = TeamKey.CREATED) = season!!.detail(team, career!!)

    private fun refused(expected: GameError, block: () -> Unit) =
        assertEquals(expected, assertThrows(GameException::class.java) { block() }.error)

    // --- §16.3a the detail ---

    @Test fun beforeAnythingIsPlayedTheFormIsEmptyAndTheNextFixtureIsTheFirst() {
        val save = season()
        val d = save.detail()
        assertTrue(d.form.isEmpty())
        assertEquals(0, d.row.played)
        assertEquals(0, d.row.points)
        assertEquals(save.playerFixture, d.next)
        assertTrue(d.position in 1..8)
        for (team in save.season!!.teams) {
            val c = save.detail(team)
            assertTrue(c.form.isEmpty())
            assertEquals(0, c.next!!.matchday)
        }
    }

    @Test fun theFormIsTheLastThreeMostRecentFirstWithFewerEarlyOn() {
        var save = season().play(1 to 0)
        var d = save.detail()
        assertEquals(1, d.form.size)
        assertEquals(FormKind.WON, d.form[0].kind)
        assertEquals(1, d.form[0].goalsFor)
        assertEquals(0, d.form[0].goalsAgainst)
        assertEquals(3, d.row.points)

        save = save.play(0 to 0, 0 to 2)
        d = save.detail()
        assertEquals(listOf(FormKind.LOST, FormKind.DRAWN, FormKind.WON), d.form.map { it.kind })
        assertEquals(3, d.row.played)
        assertEquals(1, d.row.goalsFor)
        assertEquals(2, d.row.goalsAgainst)
        assertEquals(4, d.row.points)

        save = save.play(4 to 1)
        d = save.detail()
        assertEquals(Tuning.Season.formMatches, d.form.size)            // never more than three
        assertEquals(listOf(FormKind.WON, FormKind.LOST, FormKind.DRAWN), d.form.map { it.kind })
        assertFalse(d.form[0].cup)
        // The detail's row is the team's row of the table, and its position the table's place.
        val standings = save.season!!.table(save.career!!)
        assertEquals(TeamKey.CREATED, standings[d.position - 1].team)
        assertEquals(standings[d.position - 1], d.row)
        // Its next fixture is the cup quarter-final it has not played (§11.1).
        assertEquals(4, d.next!!.matchday)
        assertNull(d.next!!.score)
        for (m in d.form) assertTrue(m.opponent != TeamKey.CREATED)
    }

    @Test fun aForfeitedCupTieIsTheMostRecentFormEntryAndNeverInTheTable() {
        var save = season().play(1 to 0, 2 to 0, 3 to 0, 4 to 0)
        val before = save.detail().row
        assertEquals(MatchdayStep.Cup(CupRound.QUARTER_FINAL), save.season!!.step)
        save = save.forfeit().first
        val d = save.detail()
        assertTrue(d.form[0].cup)
        assertEquals(FormKind.LOST, d.form[0].kind)
        assertEquals(Tuning.Match.forfeitFor, d.form[0].goalsFor)
        assertEquals(Tuning.Match.forfeitAgainst, d.form[0].goalsAgainst)
        assertFalse(d.form[0].overtime)
        // A cup result never moves the table (§11.4), so played, points and goals stand still.
        assertEquals(before, d.row)
        // Knocked out: the next fixture is a league round again.
        assertTrue(Season.plan[d.next!!.matchday] is MatchdayStep.League)
    }

    @Test fun aClubsFormIsItsSimulatedResults() {
        val save = season().play(1 to 0, 1 to 0)
        for (team in save.season!!.teams) {
            if (team == TeamKey.CREATED) continue
            val d = save.detail(team)
            assertEquals(2, d.form.size)
            assertEquals(2, d.row.played)
            assertEquals(2, d.row.won + d.row.drawn + d.row.lost)
            assertTrue(d.form.none { it.cup || it.opponent == team })
        }
    }

    @Test fun atTheSeasonsEndThereIsNoNextFixture() {
        var save = season()
        while (!save.season!!.isFinished) save = save.recordPlayed(2, 1).first
        val d = save.detail()
        assertNull(d.next)
        assertEquals(3, d.form.size)
        assertEquals(14, d.row.played)
        assertEquals(14, d.row.won)
    }

    // --- §2.2, §16.1 editing the team ---

    @Test fun editingKeepsTheSeasonAndItsResults() {
        var save = season().play(3 to 1, 0 to 2)
        val fixtures = save.season!!.fixtures
        val titles = save.career!!.leagueTitles
        val edited = save.career!!.draft.copy(
            name = "  Iron Puffins ", short = "IRP",
            primary = Career.kitPalette[3].primary, secondary = Career.kitPalette[5].secondary, world = World.HIMALAYA,
        )
        save = save.editTeam(edited)
        val c = save.career!!
        assertEquals("Iron Puffins", c.created.name)                    // kept without its spaces
        assertEquals("IRP", c.short(TeamKey.CREATED))
        assertEquals(World.HIMALAYA, c.homeWorld(TeamKey.CREATED))
        assertEquals(Career.kitPalette[3].primary to Career.kitPalette[5].secondary, c.kit(TeamKey.CREATED))
        // The season's fixtures name the team, not its name: nothing moved.
        assertEquals(fixtures, save.season!!.fixtures)
        assertEquals(titles, c.leagueTitles)
        assertEquals(2, save.detail().row.played)
        assertTrue(save.season!!.teams.contains(TeamKey.CREATED))
        // And it round-trips through the save file.
        assertEquals(save, SaveRecord.decode(save.encoded()))
    }

    @Test fun editingIsHeldToTheRulesOfCreating() {
        val save = season()
        val before: CreatedTeam = save.career!!.created
        refused(GameError.InvalidTeam(listOf(TeamIssue.NAME_TOO_SHORT, TeamIssue.SHORT_CODE_IS_A_CLUBS))) {
            save.editTeam(save.career!!.draft.copy(name = "M", short = "GLW"))
        }
        refused(GameError.InvalidTeam(listOf(TeamIssue.PRIMARY_NOT_IN_PALETTE))) {
            save.editTeam(save.career!!.draft.copy(primary = 0x00FF00))
        }
        assertEquals(before, save.career!!.created)
        refused(GameError.NoCareer) { SaveRecord.fresh().editTeam(draft()) }
        assertNotNull(before)
    }
}
