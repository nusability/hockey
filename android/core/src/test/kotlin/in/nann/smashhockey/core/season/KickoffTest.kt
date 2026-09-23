package `in`.nann.smashhockey.core.season

import `in`.nann.smashhockey.core.generated.Career
import `in`.nann.smashhockey.core.generated.Club
import `in`.nann.smashhockey.core.generated.Drill
import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.MatchdayStep
import `in`.nann.smashhockey.core.generated.SaveRecord
import `in`.nann.smashhockey.core.generated.Season
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.generated.World
import `in`.nann.smashhockey.core.match.Control
import `in`.nann.smashhockey.core.match.SideSetup
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * What a started match is made of (spec §2.2, §9, §10, §11, §12), and the save on the device
 * (§15). The twin of KickoffTests.swift.
 */
class KickoffTest {
    private val jet = Career.kitPalette[0]

    private fun draft() = TeamDraft("Moss Giants", "MOG", jet.primary, jet.secondary, World.OCEAN)

    private fun season() = SaveRecord.fresh().createTeam(draft()).startSeason(11)

    @Test fun theSeasonMatchIsTheFixtureInTheHomeTeamsWorldWithTheBoard() {
        val base = season()
        val save = base.copy(board = base.board.copy(formation = Formation.DIAMOND, periodSeconds = 90.0,
            ballSpinSeconds = Tuning.Board.ballSpinSeconds[0]))
        val fixture = save.playerFixture!!
        val setup = save.seasonMatch(5)!!
        val opponent = if (fixture.home == TeamKey.CREATED) fixture.away else fixture.home
        assertEquals(save.career!!.homeWorld(fixture.home).sport, setup.sport)
        assertEquals(Formation.DIAMOND, setup.home.formation)
        assertEquals(Career.createdRating, setup.home.rating)
        assertEquals(SideSetup.club(opponent.club!!), setup.away)
        assertEquals(90.0, setup.periodSeconds, 0.0)
        assertEquals(Tuning.Board.ballSpinSeconds[0], setup.orbitPeriod, 0.0)
        assertFalse(setup.cup)
        assertEquals(Control.PLAYER, setup.control)
        // Passing and shooting stay the team's own — the defaults (§2.2); the rest is the board's (§12).
        assertEquals(Tactics.defaults.passing, setup.home.tactics.passing, 0.0)
        assertEquals(save.board.pressing, setup.home.tactics.pressing, 0.0)
    }

    @Test fun aCupTieIsPlayedWithSuddenDeath() {
        var save = season()
        while (Season.plan[save.season!!.matchday] is MatchdayStep.League) save = save.recordPlayed(1, 0).first
        assertTrue(save.seasonMatch(1)!!.cup)
    }

    @Test fun beforeACareerThePlayerIsTheMossFoxes() {
        val save = SaveRecord.fresh()
        assertEquals(TeamKey.of(Career.demoClub), save.sideTeam)
        assertNull(save.seasonMatch(1))
        val quick = QuickMatch.draw(3, save.sideTeam)
        val setup = save.quickMatch(quick, 9)
        assertEquals(Career.demoClub.rating, setup.home.rating)
        assertEquals(SideSetup.club(quick.opponent), setup.away)
        assertEquals(quick.world.sport, setup.sport)
        assertFalse(setup.cup)
    }

    @Test fun thePlayersTeamPlaysAtItsFixedRating() {
        val save = SaveRecord.fresh().createTeam(draft())
        assertEquals(Career.createdRating, save.playerSide.rating)
        assertEquals(World.OCEAN, save.career!!.homeWorld(TeamKey.CREATED))
        assertEquals(jet.primary, save.career!!.kit(TeamKey.CREATED).first)
    }

    @Test fun drillsOpenInOrder() {
        var save = SaveRecord.fresh()
        assertTrue(save.isOpen(Drill.entries[0]))
        assertFalse(save.isOpen(Drill.entries[1]))
        save = save.won(Drill.entries[0])
        assertTrue(save.isOpen(Drill.entries[1]))
        assertFalse(save.isOpen(Drill.entries[2]))
        assertEquals(save.board.ballSpinSeconds, save.drill(Drill.entries[1], 1).orbitPeriod, 0.0)
    }

    @Test fun theBoardTakesOnlyItsOwnValues() {
        var save = SaveRecord.fresh()
        val bad = save.board.copy(periodSeconds = 100.0)
        assertEquals(GameError.NotABoardValue, assertThrows(GameException::class.java) { save.withBoard(bad) }.error)
        save = save.withBoard(save.board.copy(periodSeconds = 150.0, pressing = 0.9))
        assertEquals(0.9, save.board.pressing, 0.0)
        save = save.createTeam(draft()).resetBoard()
        assertEquals(Tactics.defaults.pressing, save.board.pressing, 0.0)
        assertEquals(Tuning.Board.periodSecondsDefault, save.board.periodSeconds, 0.0)
    }

    // --- §15 the file ---

    private fun directory(): File = Files.createTempDirectory("smash-save").toFile()

    @Test fun aMissingSaveIsANewPlayerAndAWrittenOneReadsBack() {
        val store = SaveStore(directory())
        assertEquals(SaveStore.Loaded.New(SaveRecord.fresh()), store.load())
        val save = season()
        store.write(save)
        assertEquals(SaveStore.Loaded.Found(save), store.load())
        assertEquals("nothing but the save is left behind", listOf(SaveStore.FILE_NAME), store.directory.list()!!.toList())
        assertEquals(save.encoded(), store.file.readText())
    }

    @Test fun aRefusedSaveIsKeptBesideTheNewOne() {
        val store = SaveStore(directory())
        val bad = "{\"version\": 99}".toByteArray()
        store.file.writeBytes(bad)
        assertEquals(SaveStore.Loaded.Refused("unknownVersion 99"), store.load())
        assertTrue("loading never touches the file", store.file.readBytes().contentEquals(bad))
        val (fresh, kept) = store.replaceRefused()
        assertEquals(SaveRecord.fresh(), fresh)
        assertEquals("save.refused-1.json", kept!!.name)
        assertTrue(kept.readBytes().contentEquals(bad))
        assertEquals(SaveStore.Loaded.Found(SaveRecord.fresh()), store.load())
        store.file.writeBytes(bad)
        assertEquals("save.refused-2.json", store.replaceRefused().second!!.name)
    }
}
