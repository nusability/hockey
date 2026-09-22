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

    private fun clubSeason(club: Club = Club.FALCONS, seed: Long = 7): SaveRecord = SaveRecord.fresh().chooseClub(club).startSeason(seed)

    private fun refused(expected: GameError, block: () -> Unit) =
        assertEquals(expected, assertThrows(GameException::class.java) { block() }.error)

    private fun SaveRecord.isCupDay() = season!!.step is MatchdayStep.Cup

    // --- §11.1 fixtures ---

    @Test fun everyTeamPlaysEveryOtherTwiceWithSwappedVenues() {
        val created = CareerRecord(TeamKey.CREATED, CreatedTeam("Moss Giants", "MOG", jet.primary, jet.secondary, World.OCEAN), 0, 0)
        for (seed in listOf(0L, 1L, 42L, 0xDEADBEEFL)) for (career in listOf(CareerRecord.picked(Club.NEBULA), created)) {
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

    @Test fun aCreatedTeamReplacesGlacierWolvesInTheirPlace() {
        val save = SaveRecord.fresh().createTeam(draft())
        val league = save.career!!.league
        assertEquals(8, league.size)
        assertFalse(TeamKey.WOLVES in league)
        assertEquals(TeamKey.CREATED, league[6])
        assertEquals(77, save.career!!.rating(TeamKey.CREATED))
    }

    @Test fun theCircleMethodAsSpecified() {
        val o = listOf(TeamKey.MOSSFOXES, TeamKey.GLOWOWLS, TeamKey.NEBULA, TeamKey.ROCKETLYNX, TeamKey.SCORPIONS, TeamKey.FALCONS, TeamKey.WOLVES, TeamKey.KRAKEN)
        val rounds = SeasonEngine.leagueRounds(o)
        assertEquals(14, rounds.size)
        assertEquals(listOf(o[0] to o[7], o[1] to o[6], o[2] to o[5], o[3] to o[4]), rounds[0])
        assertEquals(listOf(o[6] to o[0], o[5] to o[7], o[4] to o[1], o[3] to o[2]), rounds[1])
    }

    // --- §11.2–11.4 playing ---

    @Test fun theCupAdvancesWinnersInBracketOrder() {
        var save = clubSeason()
        while (!save.season!!.isFinished) save = save.recordPlayed(2, if (save.isCupDay()) 1 else 2).first
        val s = save.season!!
        val qf = s.cupTies(CupRound.QUARTER_FINAL)
        val sf = s.cupTies(CupRound.SEMI_FINAL)
        val f = s.cupTies(CupRound.FINAL)
        val qfWinners = qf.map { SeasonEngine.winner(it)!! }
        assertEquals(listOf(qfWinners[0] to qfWinners[1], qfWinners[2] to qfWinners[3]), sf.map { it.home to it.away })
        assertEquals(sf.map { SeasonEngine.winner(it)!! }, listOf(f.single().home, f.single().away))
        assertEquals(TeamKey.FALCONS, s.cupWinner)
        assertEquals(1, save.career!!.cups)
        (qf + sf + f).forEach { assertTrue(it.score!!.home != it.score!!.away) }
    }

    @Test fun afterACupExitTheRestIsSimulatedStraightThrough() {
        var save = clubSeason()
        var played = 0
        while (!save.season!!.isFinished) {
            save = (if (save.isCupDay()) save.forfeit() else save.recordPlayed(1, 1)).first
            played++
        }
        assertEquals(15, played)
        val qf = save.season!!.cupTies(CupRound.QUARTER_FINAL).first { it.home == TeamKey.FALCONS || it.away == TeamKey.FALCONS }
        assertEquals(if (qf.home == TeamKey.FALCONS) Score(0, 3, false) else Score(3, 0, false), qf.score)
    }

    @Test fun theTableBreaksTiesByGoalDifferenceGoalsForThenShortCode() {
        val career = CareerRecord.picked(Club.MOSSFOXES)
        val s = SeasonRecord(0, 0, career.league, 1, listOf(
            Fixture(TeamKey.ROCKETLYNX, TeamKey.GLOWOWLS, 0, Score(3, 1, false)),
            Fixture(TeamKey.NEBULA, TeamKey.KRAKEN, 0, Score(2, 0, false)),
            Fixture(TeamKey.MOSSFOXES, TeamKey.FALCONS, 0, Score(2, 0, false)),
            Fixture(TeamKey.SCORPIONS, TeamKey.WOLVES, 0, Score(1, 1, false)),
        ))
        val expected = listOf(TeamKey.ROCKETLYNX, TeamKey.MOSSFOXES, TeamKey.NEBULA, TeamKey.SCORPIONS, TeamKey.WOLVES, TeamKey.GLOWOWLS, TeamKey.KRAKEN, TeamKey.FALCONS)
        assertEquals(expected, s.table(career).map { it.team })
        assertEquals(1, s.table(career)[3].drawn)
        val withCup = s.copy(fixtures = s.fixtures + Fixture(TeamKey.FALCONS, TeamKey.KRAKEN, 4, Score(5, 0, false)))
        assertEquals(expected, withCup.table(career).map { it.team })   // a cup result never counts
    }

    @Test fun thePlayersScoreIsCheckedAndForfeitIsNilThree() {
        var save = clubSeason()
        refused(GameError.NegativeGoals) { save.recordPlayed(-1, 0) }
        refused(GameError.OvertimeOutsideCup) { save.recordPlayed(2, 1, true) }
        val f = save.playerFixture!!
        save = save.forfeit().first
        val recorded = save.season!!.fixtures.first { it.home == f.home && it.away == f.away && it.matchday == f.matchday }
        assertEquals(if (f.home == TeamKey.FALCONS) Score(0, 3, false) else Score(3, 0, false), recorded.score)
        while (!save.isCupDay()) save = save.recordPlayed(0, 0).first
        refused(GameError.CupScoreLevel) { save.recordPlayed(1, 1) }
        refused(GameError.OvertimeNotByOneGoal) { save.recordPlayed(3, 1, true) }
        save.recordPlayed(3, 2, true)
    }

    @Test fun aNewSeasonKeepsTheCareerAndItsTrophies() {
        var save = clubSeason(Club.ROCKETLYNX, 3)
        refused(GameError.SeasonInProgress) { save.startSeason(4) }
        while (!save.season!!.isFinished) save = save.recordPlayed(9, 0).first
        assertEquals(1, save.career!!.leagueTitles)
        assertEquals(1, save.career!!.cups)
        val finished = save
        refused(GameError.SeasonFinished) { finished.recordPlayed(1, 0) }
        save = save.startSeason(4)
        assertEquals(0, save.season!!.matchday)
        assertEquals(4L, save.season!!.seed)
        assertEquals(TeamKey.ROCKETLYNX, save.career!!.team)
        assertEquals(1, save.career!!.leagueTitles)
    }

    // --- §2.2 the career ---

    @Test fun aCareerIsChosenOnceAndStartingOverKeepsTraining() {
        var save = SaveRecord.fresh()
        refused(GameError.NoCareer) { save.startSeason(1) }
        save = save.chooseClub(Club.GLOWOWLS)
        assertEquals(0.65, save.board.pressing, 0.0)
        val chosen = save
        refused(GameError.CareerExists) { chosen.chooseClub(Club.NEBULA) }
        refused(GameError.CareerExists) { chosen.createTeam(draft()) }
        save = save.startSeason(1).recordPlayed(1, 0).first.won(Drill.SHOT).won(Drill.PASS).won(Drill.SHOT)
        save = save.startOver()
        assertNull(save.career)
        assertNull(save.season)
        assertEquals(listOf(Drill.SHOT, Drill.PASS), save.training.won)
        save = save.createTeam(draft("  Moss Giants "))
        assertEquals("Moss Giants", save.career!!.created!!.name)
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

    @Test fun resetRestoresTheDefaultsOrThePickedClubsTactics() {
        assertEquals(Board.defaults, Board.reset(null))
        val rocket = Board.reset(CareerRecord.picked(Club.ROCKETLYNX))
        assertEquals(0.7, rocket.pressing, 0.0)
        assertEquals(0.75, rocket.pushUp, 0.0)
        assertEquals(Formation.BALANCED, rocket.formation)
        assertEquals(120.0, rocket.periodSeconds, 0.0)
    }

    @Test fun aQuickMatchNeverDrawsThePlayersClubNorTouchesTheSeason() {
        val save = clubSeason(Club.KRAKEN)
        for (seed in 0L until 200L) assertTrue(QuickMatch.draw(seed, TeamKey.KRAKEN).opponent != Club.KRAKEN)
        assertTrue((0L until 200L).map { QuickMatch.draw(it, TeamKey.CREATED).opponent }.contains(Club.WOLVES))
        assertEquals(clubSeason(Club.KRAKEN), save)
    }
}
