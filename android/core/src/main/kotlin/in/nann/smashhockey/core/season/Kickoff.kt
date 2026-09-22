package `in`.nann.smashhockey.core.season

import `in`.nann.smashhockey.core.generated.BoardRecord
import `in`.nann.smashhockey.core.generated.Career
import `in`.nann.smashhockey.core.generated.CareerRecord
import `in`.nann.smashhockey.core.generated.Club
import `in`.nann.smashhockey.core.generated.Drill
import `in`.nann.smashhockey.core.generated.MatchdayStep
import `in`.nann.smashhockey.core.generated.SaveRecord
import `in`.nann.smashhockey.core.generated.Season
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.generated.World
import `in`.nann.smashhockey.core.match.Control
import `in`.nann.smashhockey.core.match.DrillSetup
import `in`.nann.smashhockey.core.match.MatchSetup
import `in`.nann.smashhockey.core.match.SideSetup

/*
 * What the save says every match the player starts looks like (spec §2.2, §9, §10, §11, §12): the
 * player's side from the career and the coach's board, the opponent, the world, the rules. The
 * screens ask here instead of assembling a match themselves, so a season match, a quick match, a
 * drill and the demo can never disagree about whose tactics apply. The iOS twin is SmashCore's
 * `Season/Kickoff.swift`.
 */

/** The team the player plays as: the career's, or the demo's club before there is one (§9, §11.5). */
val SaveRecord.sideTeam: TeamKey get() = career?.team ?: TeamKey.of(Career.demoClub)

/**
 * The player's side in every match they play (§12): the team's rating (§2.1, §2.2), the board's
 * pressing, covering, push up, discipline and formation. Passing and shooting are not the board's
 * (§12) — they stay the team's own.
 */
val SaveRecord.playerSide: SideSetup
    get() {
        val own = career?.startingTactics ?: Career.demoClub.tactics
        val tactics = Tactics(board.pressing, board.covering, board.pushUp, own.passing, own.shooting, board.discipline)
        val rating = career?.let { it.rating(it.team) } ?: Career.demoClub.rating
        return SideSetup(rating, tactics, board.formation)
    }

/**
 * The player's fixture of the current matchday as a match (§11.1, §11.2): in the home team's world,
 * sudden death when it is a cup tie, the board's period length and ball spin. Null when there is no
 * fixture to play.
 */
fun SaveRecord.seasonMatch(seed: Long): MatchSetup? {
    val career = career ?: return null
    val season = season ?: return null
    val fixture = playerFixture ?: return null
    val opponent = if (fixture.home == career.team) fixture.away else fixture.home
    val cup = Season.plan[season.matchday] is MatchdayStep.Cup
    val world = career.homeWorld(fixture.home)
    return MatchSetup(seed, world.sport, playerSide, career.side(opponent), board.periodSeconds, board.ballSpinSeconds, cup,
        Control.PLAYER)
}

/** A quick match (§11.5): the friendly [quick] drew, league rules, the board's settings. */
fun SaveRecord.quickMatch(quick: QuickMatch, seed: Long): MatchSetup =
    MatchSetup(seed, quick.world.sport, playerSide, SideSetup.club(quick.opponent), board.periodSeconds, board.ballSpinSeconds,
        false, Control.PLAYER)

/** A drill (§10): the drill's own lineups and ratings, the coach's tactics and ball spin. */
fun SaveRecord.drill(drill: Drill, seed: Long): DrillSetup = DrillSetup(drill, seed, playerSide.tactics, board.ballSpinSeconds)

/** The demo behind the menus (§9): the player's team against [opponent], both automatic. */
fun SaveRecord.demo(world: World, opponent: Club, seed: Long): MatchSetup =
    MatchSetup.demo(seed, world, playerSide, SideSetup.club(opponent), board.periodSeconds)

/** A drill is open once the one before it has been won (§10); the first always is. */
fun SaveRecord.isOpen(drill: Drill): Boolean {
    val i = Drill.entries.indexOf(drill)
    return i <= 0 || Drill.entries[i - 1] in training.won
}

/** Whether [drill] has been won. */
fun SaveRecord.isWon(drill: Drill): Boolean = drill in training.won

/**
 * Replaces the board. The values are the caller's to choose from §12's ranges and steps; one
 * outside them is a programming error, refused.
 */
fun SaveRecord.withBoard(next: BoardRecord): SaveRecord {
    for (v in listOf(next.pressing, next.covering, next.pushUp, next.discipline)) {
        if (!(v >= Tuning.Board.tacticMin && v <= Tuning.Board.tacticMax)) refuse(GameError.NotABoardValue)
    }
    if (next.periodSeconds !in Tuning.Board.periodSeconds || next.ballSpinSeconds !in Tuning.Board.ballSpinSeconds) {
        refuse(GameError.NotABoardValue)
    }
    return copy(board = next)
}

/** "Reset" on the coach's board (§12): the defaults, or the picked club's tactics. */
fun SaveRecord.resetBoard(): SaveRecord = copy(board = Board.reset(career))

/** A team's kit, sRGB 0xRRGGBB, primary then secondary: a club's, or the created team's. */
fun CareerRecord.kit(of: TeamKey): Pair<Int, Int> =
    (of.club?.let { it.primary to it.secondary }) ?: created!!.let { it.primary to it.secondary }

/** A team's home world (§2.1, §2.2): where its home fixtures are played (§11.1). */
fun CareerRecord.homeWorld(of: TeamKey): World = of.club?.world ?: created!!.world

/** An opponent as an AI side. The created team is never the opponent — it is always the player's. */
internal fun CareerRecord.side(of: TeamKey): SideSetup =
    SideSetup.club(of.club ?: error("the created team is the player's, never the opponent"))
