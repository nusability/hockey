package `in`.nann.smashhockey.core.season

import `in`.nann.smashhockey.core.generated.Career
import `in`.nann.smashhockey.core.generated.CareerRecord
import `in`.nann.smashhockey.core.generated.Club
import `in`.nann.smashhockey.core.generated.CreatedTeam
import `in`.nann.smashhockey.core.generated.CupRound
import `in`.nann.smashhockey.core.generated.Drill
import `in`.nann.smashhockey.core.generated.Fixture
import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.MatchdayStep
import `in`.nann.smashhockey.core.generated.SaveRecord
import `in`.nann.smashhockey.core.generated.Score
import `in`.nann.smashhockey.core.generated.Season
import `in`.nann.smashhockey.core.generated.SeasonRecord
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.generated.World
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** The contracts of the career, the season and the save (spec §2.2, §8.7, §11, §12, §15). */
class SeasonTest {
    private val jet = Career.kitPalette[0]

    private fun draft(name: String = "Moss Giants", short: String = "MOG") = TeamDraft(name, short, jet.primary, jet.secondary, World.OCEAN)

    private fun career(name: String = "Moss Giants", short: String = "MOG") =
        CareerRecord(CreatedTeam(name, short, jet.primary, jet.secondary, World.OCEAN), 0, 0)

    /** A season played by the player's own team — the only career there is (§2.2). */
    private fun season(seed: Long = 7): SaveRecord = SaveRecord.fresh().createTeam(draft()).startSeason(seed)

    private fun refused(expected: GameError, block: () -> Unit) =
        assertEquals(expected, assertThrows(GameException::class.java) { block() }.error)

    private fun SaveRecord.isCupDay() = season!!.step is MatchdayStep.Cup

    // --- §11.1 fixtures ---

    @Test fun everyTeamPlaysEveryOtherTwiceWithSwappedVenues() {
        for (seed in listOf(0L, 1L, 42L, 0xDEADBEEFL)) for (career in listOf(career(), career("Rocket Rangers", "ROK"))) {
            val s = SeasonEngine.start(seed, career)
            val league = s.fixtures.filter { Season.plan[it.matchday] is MatchdayStep.League }
            assertEquals(56, league.size)
            assertEquals(career.league.toSet(), s.teams.toSet())
            val venues = league.groupingBy { it.home to it.away }.eachCount()
            for (a in s.teams) for (b in s.teams) if (a != b) assertEquals(1, venues[a to b])
            Season.plan.forEachIndexed { md, step ->
                if (step !is MatchdayStep.League) return@forEachIndexed
                val teams = s.fixturesOn(md).flatMap { listOf(it.home, it.away) }
                assertEquals(8, teams.toSet().size)
                assertEquals(8, teams.size)
                if (step.round > 7) {
                    val mirror = s.fixturesOn(Season.plan.indexOf(MatchdayStep.League(step.round - 7)))
                    assertEquals(mirror.map { it.home to it.away }, s.fixturesOn(md).map { it.away to it.home })
                }
            }
            assertEquals(4, s.cupTies(CupRound.QUARTER_FINAL).size)
            assertTrue(s.cupTies(CupRound.SEMI_FINAL).isEmpty())
            assertEquals(s.teams.toSet(), s.cupTies(CupRound.QUARTER_FINAL).flatMap { listOf(it.home, it.away) }.toSet())
        }
    }

    /**
     * §2.2: creating the team is the only way into a career, and it always takes Glacier Wolves'
     * place at the league average.
     */
    @Test fun thePlayersOwnTeamReplacesGlacierWolvesInTheirPlace() {
        val fresh = SaveRecord.fresh()
        assertNull(fresh.career)
        assertNull(fresh.playerTeam)
        val save = fresh.createTeam(draft())
        val career = save.career!!
        assertEquals(TeamKey.CREATED, career.team)
        assertEquals(TeamKey.CREATED, save.playerTeam)
        val league = career.league
        assertEquals(8, league.size)
        assertFalse(TeamKey.WOLVES in league)
        assertEquals(TeamKey.CREATED, league[6])
        assertEquals(77, career.rating(TeamKey.CREATED))
        assertEquals(77, Career.createdRating)
        assertEquals("MOG", career.short(TeamKey.CREATED))
        assertEquals("Moss Giants", career.created.name)
        // Glacier Wolves stay in the game outside the season (§11.5).
        assertEquals(70, career.rating(TeamKey.WOLVES))
    }

    @Test fun theCircleMethodAsSpecified() {
        val o = listOf(TeamKey.MOSSFOXES, TeamKey.GLOWOWLS, TeamKey.NEBULA, TeamKey.ROCKETLYNX, TeamKey.SCORPIONS, TeamKey.FALCONS, TeamKey.CREATED, TeamKey.KRAKEN)
        val rounds = SeasonEngine.leagueRounds(o)
        assertEquals(14, rounds.size)
        assertEquals(listOf(o[0] to o[7], o[1] to o[6], o[2] to o[5], o[3] to o[4]), rounds[0])
        assertEquals(listOf(o[6] to o[0], o[5] to o[7], o[4] to o[1], o[3] to o[2]), rounds[1])
    }

    // --- §11.2–11.4 playing ---

    @Test fun theCupAdvancesWinnersInBracketOrder() {
        var save = season()
        while (!save.season!!.isFinished) save = save.recordPlayed(2, if (save.isCupDay()) 1 else 2).first
        val s = save.season!!
        val qf = s.cupTies(CupRound.QUARTER_FINAL)
        val sf = s.cupTies(CupRound.SEMI_FINAL)
        val f = s.cupTies(CupRound.FINAL)
        val qfWinners = qf.map { SeasonEngine.winner(it)!! }
        assertEquals(listOf(qfWinners[0] to qfWinners[1], qfWinners[2] to qfWinners[3]), sf.map { it.home to it.away })
        assertEquals(sf.map { SeasonEngine.winner(it)!! }, listOf(f.single().home, f.single().away))
        assertEquals(TeamKey.CREATED, s.cupWinner)
        assertEquals(1, save.career!!.cups)
        (qf + sf + f).forEach { assertTrue(it.score!!.home != it.score!!.away) }
    }

    @Test fun afterACupExitTheRestIsSimulatedStraightThrough() {
        var save = season()
        var played = 0
        while (!save.season!!.isFinished) {
            save = (if (save.isCupDay()) save.forfeit() else save.recordPlayed(1, 1)).first
            played++
        }
        assertEquals(15, played)
        val qf = save.season!!.cupTies(CupRound.QUARTER_FINAL).first { it.home == TeamKey.CREATED || it.away == TeamKey.CREATED }
        assertEquals(if (qf.home == TeamKey.CREATED) Score(0, 3, false) else Score(3, 0, false), qf.score)
    }

    @Test fun theTableBreaksTiesByGoalDifferenceGoalsForThenShortCode() {
        val career = career()
        val s = SeasonRecord(1, 0, 0, career.league, 1, listOf(
            Fixture(TeamKey.ROCKETLYNX, TeamKey.GLOWOWLS, 0, Score(3, 1, false)),
            Fixture(TeamKey.NEBULA, TeamKey.KRAKEN, 0, Score(2, 0, false)),
            Fixture(TeamKey.MOSSFOXES, TeamKey.FALCONS, 0, Score(2, 0, false)),
            Fixture(TeamKey.SCORPIONS, TeamKey.CREATED, 0, Score(1, 1, false)),
        ))
        // DUN before MOG, and COR before MIR, on short code alone.
        val expected = listOf(TeamKey.ROCKETLYNX, TeamKey.MOSSFOXES, TeamKey.NEBULA, TeamKey.SCORPIONS, TeamKey.CREATED, TeamKey.GLOWOWLS, TeamKey.KRAKEN, TeamKey.FALCONS)
        assertEquals(expected, s.table(career).map { it.team })
        assertEquals(1, s.table(career)[3].drawn)
        val withCup = s.copy(fixtures = s.fixtures + Fixture(TeamKey.FALCONS, TeamKey.KRAKEN, 4, Score(5, 0, false)))
        assertEquals(expected, withCup.table(career).map { it.team })   // a cup result never counts
    }

    @Test fun thePlayersScoreIsCheckedAndForfeitIsNilThree() {
        var save = season()
        refused(GameError.NegativeGoals) { save.recordPlayed(-1, 0) }
        refused(GameError.OvertimeOutsideCup) { save.recordPlayed(2, 1, true) }
        val f = save.playerFixture!!
        save = save.forfeit().first
        val recorded = save.season!!.fixtures.first { it.home == f.home && it.away == f.away && it.matchday == f.matchday }
        assertEquals(if (f.home == TeamKey.CREATED) Score(0, 3, false) else Score(3, 0, false), recorded.score)
        while (!save.isCupDay()) save = save.recordPlayed(0, 0).first
        refused(GameError.CupScoreLevel) { save.recordPlayed(1, 1) }
        refused(GameError.OvertimeNotByOneGoal) { save.recordPlayed(3, 1, true) }
        save.recordPlayed(3, 2, true)
    }

    @Test fun aNewSeasonKeepsTheCareerAndItsTrophies() {
        var save = season(3)
        refused(GameError.SeasonInProgress) { save.startSeason(4) }
        while (!save.season!!.isFinished) save = save.recordPlayed(9, 0).first
        assertEquals(1, save.career!!.leagueTitles)
        assertEquals(1, save.career!!.cups)
        val finished = save
        refused(GameError.SeasonFinished) { finished.recordPlayed(1, 0) }
        save = save.startSeason(4)
        assertEquals(0, save.season!!.matchday)
        assertEquals(4L, save.season!!.seed)
        assertEquals(TeamKey.CREATED, save.career!!.team)
        assertEquals(1, save.career!!.leagueTitles)
    }

    // --- §2.2 the career ---

    @Test fun aCareerIsCreatedOnceAndStartingOverKeepsTraining() {
        var save = SaveRecord.fresh()
        refused(GameError.NoCareer) { save.startSeason(1) }
        save = save.createTeam(draft())
        assertEquals(Tactics.defaults.pressing, save.board.pressing, 0.0)   // the defaults (§2.2, §12)
        val created = save
        refused(GameError.CareerExists) { created.createTeam(draft("Rocket Rangers", "ROK")) }
        save = save.startSeason(1).recordPlayed(1, 0).first.won(Drill.SHOT).won(Drill.PASS).won(Drill.SHOT)
        save = save.startOver()
        assertNull(save.career)
        assertNull(save.season)
        assertEquals(listOf(Drill.SHOT, Drill.PASS), save.training.won)
        save = save.createTeam(draft("  Moss Giants "))
        assertEquals("Moss Giants", save.career!!.created.name)
        assertEquals(Tactics.defaults.pressing, save.board.pressing, 0.0)
    }

    @Test fun aDraftsIssuesAreTyped() {
        refused(GameError.InvalidTeam(listOf(TeamIssue.NAME_TOO_SHORT, TeamIssue.SHORT_CODE_IS_A_CLUBS))) {
            SaveRecord.fresh().createTeam(draft("M", "MOS"))
        }
        assertTrue(CreatedTeamRules.issues(draft()).isEmpty())
    }

    @Test fun thePaletteNeverClashesWithAClub() {
        assertEquals(12, Career.kitPalette.size)
        val clubPrimaries = Club.entries.map { it.primary }.toSet()
        assertTrue(Career.kitPalette.none { it.primary in clubPrimaries })
    }

    // --- §12 the board, §11.5 quick match ---

    @Test fun resetRestoresTheDefaults() {
        val save = season().copy(board = Board.defaults.copy(pressing = 0.9, formation = Formation.DIAMOND, periodSeconds = 150.0))
        val reset = save.resetBoard().board
        assertEquals(Board.defaults, reset)
        assertEquals(Tactics.defaults.pressing, reset.pressing, 0.0)
        assertEquals(Formation.BALANCED, reset.formation)
        assertEquals(120.0, reset.periodSeconds, 0.0)
    }

    /**
     * §11.5: before a career the player's side is the demo's club, which is never drawn against
     * itself; the player's own team draws all eight clubs, Glacier Wolves included.
     */
    @Test fun aQuickMatchDrawsEveryClubForThePlayersOwnTeam() {
        val save = season()
        val demo = TeamKey.of(Career.demoClub)
        for (seed in 0L until 200L) assertTrue(QuickMatch.draw(seed, demo).opponent != Career.demoClub)
        val drawn = (0L until 200L).map { QuickMatch.draw(it, TeamKey.CREATED).opponent }.toSet()
        assertEquals(Club.entries.toSet(), drawn)
        assertTrue(Club.WOLVES in drawn)
        assertEquals(season(), save)
    }
}
