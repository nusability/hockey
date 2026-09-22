package `in`.nann.smashhockey.core.season

import `in`.nann.smashhockey.core.generated.CareerRecord
import `in`.nann.smashhockey.core.generated.CupRound
import `in`.nann.smashhockey.core.generated.Fixture
import `in`.nann.smashhockey.core.generated.MatchdayStep
import `in`.nann.smashhockey.core.generated.Score
import `in`.nann.smashhockey.core.generated.Season
import `in`.nann.smashhockey.core.generated.SeasonRecord
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.math.DetMath
import `in`.nann.smashhockey.core.math.SplitMix64
import kotlin.math.abs
import kotlin.math.floor

/*
 * The season (spec §11): fixtures, simulated results, the table, the cup and the end — all drawn
 * from the season's own SplitMix64 stream, whose position the record keeps (§4.3, §15), so a season
 * reloaded from the save continues with exactly the draws it would have made. The iOS twin is
 * SmashCore's `Season/SeasonEngine.swift`; both replay shared/vectors/season/.
 */

/** How a season ended (§11.4). */
data class SeasonEnd(val champion: TeamKey, val cupWinner: TeamKey)

/** A row of the league table (§11.4). */
data class TableRow(
    val team: TeamKey,
    val played: Int = 0,
    val won: Int = 0,
    val drawn: Int = 0,
    val lost: Int = 0,
    val goalsFor: Int = 0,
    val goalsAgainst: Int = 0,
) {
    val points: Int get() = won * Tuning.Season.pointsWin + drawn * Tuning.Season.pointsDraw
    val goalDifference: Int get() = goalsFor - goalsAgainst

    internal fun add(gf: Int, ga: Int) = copy(
        played = played + 1, goalsFor = goalsFor + gf, goalsAgainst = goalsAgainst + ga,
        won = won + (if (gf > ga) 1 else 0), drawn = drawn + (if (gf == ga) 1 else 0), lost = lost + (if (gf < ga) 1 else 0),
    )
}

internal fun MatchdayStep.isCup() = this is MatchdayStep.Cup

internal fun cupMatchday(round: CupRound): Int = Season.plan.indexOf(MatchdayStep.Cup(round))

/** The season's rules, over its record. */
object SeasonEngine {
    /**
     * A new season for [career] (§11.1), its stream seeded with [seed]: the league order and the
     * cup order shuffled, every league fixture and the quarter-finals drawn.
     */
    fun start(seed: Long, career: CareerRecord): SeasonRecord {
        val teams = career.league
        val rng = SplitMix64.seeded(seed)
        val order = shuffled(teams, rng)
        val cupOrder = shuffled(teams, rng)
        val rounds = leagueRounds(order)
        val fixtures = ArrayList<Fixture>()
        Season.plan.forEachIndexed { md, step ->
            when {
                step is MatchdayStep.League ->
                    rounds[step.round - 1].forEach { (h, a) -> fixtures.add(Fixture(h, a, md, null)) }
                step is MatchdayStep.Cup && step.round == CupRound.entries[0] ->
                    pairs(cupOrder).forEach { (h, a) -> fixtures.add(Fixture(h, a, md, null)) }
            }
        }
        return SeasonRecord(seed, rng.state, teams, 0, fixtures)
    }

    /** Fisher–Yates from the last position down, `j = floor(u × (i + 1))`, i = n−1 … 1. */
    internal fun shuffled(teams: List<TeamKey>, rng: SplitMix64): List<TeamKey> {
        val a = teams.toMutableList()
        for (i in a.size - 1 downTo 1) {
            val j = floor(rng.uniform() * (i + 1).toDouble()).toInt()
            a[i] = a[j].also { a[j] = a[i] }
        }
        return a
    }

    /**
     * The circle method (§11.1): rounds 1–7 pair order[i] with order[7 − i], the first at home in
     * even rounds; the order rotates with position 0 fixed. Rounds 8–14 swap home and away.
     */
    internal fun leagueRounds(order: List<TeamKey>): List<List<Pair<TeamKey, TeamKey>>> {
        val o = order.toMutableList()
        val n = o.size
        val first = ArrayList<List<Pair<TeamKey, TeamKey>>>()
        for (r in 0 until n - 1) {
            first.add((0 until n / 2).map { i -> if (r % 2 == 0) o[i] to o[n - 1 - i] else o[n - 1 - i] to o[i] })
            o.add(1, o.removeAt(n - 1))
        }
        return first + first.map { round -> round.map { (h, a) -> a to h } }
    }

    /** Consecutive pairs (0, 1), (2, 3), …, the first at home. */
    internal fun pairs(teams: List<TeamKey>) = (teams.indices step 2).map { teams[it] to teams[it + 1] }

    internal fun winner(f: Fixture): TeamKey? {
        val s = f.score ?: return null
        if (s.home == s.away) return null
        return if (s.home > s.away) f.home else f.away
    }

    /**
     * A simulated result (§11.3): each side's goals Poisson-distributed by Knuth's method, the home
     * side's drawn first; a level cup match goes to the home side when a draw is below
     * `home mean / (home mean + away mean)`, else to the away side, by one goal in overtime.
     */
    internal fun simulate(home: Int, away: Int, cup: Boolean, rng: SplitMix64): Score {
        val homeMean = Tuning.Season.goalMean * DetMath.exp((home - away).toDouble() / Tuning.Season.goalMeanScale) +
            Tuning.Season.homeBonus
        val awayMean = Tuning.Season.goalMean * DetMath.exp((away - home).toDouble() / Tuning.Season.goalMeanScale)
        val h = poisson(homeMean, rng)
        val a = poisson(awayMean, rng)
        if (!cup || h != a) return Score(h, a, false)
        return if (rng.uniform() < homeMean / (homeMean + awayMean)) Score(h + 1, a, true) else Score(h, a + 1, true)
    }

    /** Knuth: multiply uniforms until the product is no longer above e^−mean; the count − 1. */
    internal fun poisson(mean: Double, rng: SplitMix64): Int {
        val limit = DetMath.exp(-mean)
        var k = 0
        var p = 1.0
        do {
            k += 1
            p = p * rng.uniform()
        } while (p > limit)
        return k - 1
    }
}

val SeasonRecord.isFinished: Boolean get() = matchday >= Season.plan.size

/** The matchday to play next, or null once the final is played. */
val SeasonRecord.step: MatchdayStep? get() = if (isFinished) null else Season.plan[matchday]

/** The fixtures of matchday [md] (an index in `Season.plan`), in their drawn order. */
fun SeasonRecord.fixturesOn(md: Int): List<Fixture> = fixtures.filter { it.matchday == md }

/** The player's unplayed fixture on the current matchday. */
fun SeasonRecord.playerFixture(player: TeamKey): Fixture? = playerFixtureIndex(player)?.let { fixtures[it] }

internal fun SeasonRecord.playerFixtureIndex(player: TeamKey): Int? {
    if (isFinished) return null
    val i = fixtures.indexOfFirst { it.matchday == matchday && it.score == null && (it.home == player || it.away == player) }
    return if (i < 0) null else i
}

/**
 * The league table after every league result so far — or only those up to and including matchday
 * [through] — ranked by points, goal difference, goals for, then short code (§11.4).
 */
fun SeasonRecord.table(career: CareerRecord, through: Int = Int.MAX_VALUE): List<TableRow> {
    val rows = LinkedHashMap<TeamKey, TableRow>()
    teams.forEach { rows[it] = TableRow(it) }
    for (f in fixtures) {
        val s = f.score ?: continue
        if (Season.plan[f.matchday].isCup() || f.matchday > through) continue
        rows[f.home] = rows.getValue(f.home).add(s.home, s.away)
        rows[f.away] = rows.getValue(f.away).add(s.away, s.home)
    }
    return rows.values.sortedWith(
        compareByDescending<TableRow> { it.points }.thenByDescending { it.goalDifference }
            .thenByDescending { it.goalsFor }.thenBy { career.short(it.team) },
    )
}

/** The ties of a cup round, in bracket order (empty until drawn). */
fun SeasonRecord.cupTies(round: CupRound): List<Fixture> = fixturesOn(cupMatchday(round))

/** The cup winner, once the final is played. */
val SeasonRecord.cupWinner: TeamKey? get() = cupTies(CupRound.entries.last()).firstOrNull()?.let(SeasonEngine::winner)

/**
 * Records the player's result on the current matchday (goals from the player's side), closes the
 * matchday and simulates every matchday after it on which the player has no fixture. Returns the
 * new record and how the season ended if it did.
 */
internal fun SeasonRecord.recordPlayed(
    player: TeamKey, goalsFor: Int, goalsAgainst: Int, overtime: Boolean, career: CareerRecord,
): Pair<SeasonRecord, SeasonEnd?> {
    if (isFinished) refuse(GameError.SeasonFinished)
    val index = playerFixtureIndex(player) ?: refuse(GameError.NoPlayerFixture)
    if (goalsFor < 0 || goalsAgainst < 0) refuse(GameError.NegativeGoals)
    val cup = Season.plan[matchday].isCup()
    if (cup && goalsFor == goalsAgainst) refuse(GameError.CupScoreLevel)
    if (overtime && !cup) refuse(GameError.OvertimeOutsideCup)
    if (overtime && abs(goalsFor - goalsAgainst) != 1) refuse(GameError.OvertimeNotByOneGoal)
    val f = fixtures[index]
    val home = f.home == player
    val score = Score(if (home) goalsFor else goalsAgainst, if (home) goalsAgainst else goalsFor, overtime)
    val played = copy(fixtures = fixtures.toMutableList().also { it[index] = f.copy(score = score) })
    return played.advance(player, career)
}

/** Closes matchdays until the player has a fixture to play or the season is over (§11.2). */
internal fun SeasonRecord.advance(player: TeamKey, career: CareerRecord): Pair<SeasonRecord, SeasonEnd?> {
    var s = this
    while (!s.isFinished) {
        if (s.playerFixtureIndex(player) != null) return s to null
        s = s.closeMatchday(career)
    }
    return s to SeasonEnd(s.table(career)[0].team, s.cupWinner!!)
}

/**
 * Simulates every unplayed fixture of the current matchday in drawn order (§11.3), draws the next
 * cup round after a cup matchday, and moves on.
 */
internal fun SeasonRecord.closeMatchday(career: CareerRecord): SeasonRecord {
    val rng = SplitMix64.resume(stream)
    val step = Season.plan[matchday]
    val out = fixtures.map {
        if (it.matchday != matchday || it.score != null) it
        else it.copy(score = SeasonEngine.simulate(career.rating(it.home), career.rating(it.away), step.isCup(), rng))
    }.toMutableList()
    var next = copy(stream = rng.state, fixtures = out)
    if (step is MatchdayStep.Cup) {
        val nextRound = CupRound.entries.indexOf(step.round) + 1
        if (nextRound < CupRound.entries.size) {
            val winners = next.cupTies(step.round).map { SeasonEngine.winner(it)!! }
            val md = cupMatchday(CupRound.entries[nextRound])
            next = next.copy(fixtures = out + SeasonEngine.pairs(winners).map { (h, a) -> Fixture(h, a, md, null) })
        }
    }
    return next.copy(matchday = matchday + 1)
}
