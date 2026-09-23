package `in`.nann.smashhockey.game

import `in`.nann.smashhockey.core.generated.BoardRecord
import `in`.nann.smashhockey.core.generated.CareerRecord
import `in`.nann.smashhockey.core.generated.Competition
import `in`.nann.smashhockey.core.generated.MatchOutcome
import `in`.nann.smashhockey.core.generated.MatchRow
import `in`.nann.smashhockey.core.generated.MatchdayStep
import `in`.nann.smashhockey.core.generated.Season
import `in`.nann.smashhockey.core.generated.SeasonRecord
import `in`.nann.smashhockey.core.generated.SeasonRow
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.generated.World
import `in`.nann.smashhockey.core.match.MatchResult
import `in`.nann.smashhockey.core.match.MatchSnapshot
import `in`.nann.smashhockey.core.season.SeasonEnd
import `in`.nann.smashhockey.core.season.team
import `in`.nann.smashhockey.core.season.table
import `in`.nann.smashhockey.core.telemetry.LoveMatch

/**
 * What a finished match and a finished season report (spec §18.2, §18.3), built from what the game is
 * already holding at the moment it records the result. The iOS twin is `Game/MatchReport.swift`.
 *
 * Nothing is recomputed here that the core already decides: `trailed` and `hard_fought` come off
 * [LoveMatch], the same value the love dialog's arming reads (§17.2), so the column and the question
 * can never disagree about what a hard-fought win was.
 */
object MatchReport {
    /**
     * One played match. [love] carries the goal tape the game collected as the match ran; [season] is
     * the season **as it stood before this result was recorded**, which is where the matchday and the
     * competition come from.
     */
    fun match(
        plan: MatchPlan,
        world: World,
        periodSeconds: Double,
        result: MatchResult,
        snapshot: MatchSnapshot,
        love: LoveMatch,
        board: BoardRecord,
        season: SeasonRecord?,
        matchesPlayed: Int,
        forfeit: Boolean,
    ): MatchRow.Body {
        val drill = plan is MatchPlan.Practice
        val competition = when {
            plan == MatchPlan.Season -> if (season != null && isCup(season)) Competition.CUP else Competition.LEAGUE
            drill -> Competition.DRILL
            else -> Competition.QUICK
        }
        val inSeason = competition == Competition.LEAGUE || competition == Competition.CUP
        val periods = if (drill) 1 else Tuning.Match.periods
        val elapsed = LoveMatch.elapsedMillis(
            snapshot.period, snapshot.clock, periodSeconds, snapshot.overtime, periods,
        )
        return MatchRow.Body(
            sport = world.sport,
            world = world,
            competition = competition,
            seasonNumber = if (inSeason) season?.number else null,
            // 1-based, as the player is shown it (§16.3); null outside a season.
            matchday = if (inSeason) season?.let { it.matchday + 1 } else null,
            goalsFor = snapshot.score[0],
            goalsAgainst = snapshot.score[1],
            result = outcome(result),
            overtime = snapshot.overtime,
            forfeit = forfeit,
            durationMs = elapsed,
            periodMs = Math.round(periodSeconds * 1000).toInt(),
            formation = board.formation,
            matchesPlayed = matchesPlayed,
            trailed = love.trailed,
            hardFought = love.wasHardFought,
        )
    }

    /** One finished season (§18.3), read off the table the season ended with. */
    fun season(end: SeasonEnd, season: SeasonRecord, career: CareerRecord, matchesPlayed: Int): SeasonRow.Body? {
        val table = season.table(career)
        val place = table.indexOfFirst { it.team == career.team }
        if (place < 0) return null
        val row = table[place]
        return SeasonRow.Body(
            seasonNumber = season.number,
            position = place + 1,
            points = row.points,
            played = row.played,
            won = row.won,
            drawn = row.drawn,
            lost = row.lost,
            goalsFor = row.goalsFor,
            goalsAgainst = row.goalsAgainst,
            champion = end.champion == career.team,
            cupWon = end.cupWinner == career.team,
            matchesPlayed = matchesPlayed,
        )
    }

    private fun isCup(season: SeasonRecord): Boolean =
        season.matchday < Season.plan.size && Season.plan[season.matchday] is MatchdayStep.Cup

    private fun outcome(result: MatchResult): MatchOutcome = when (result) {
        MatchResult.WON -> MatchOutcome.WON
        MatchResult.DRAWN -> MatchOutcome.DREW
        MatchResult.LOST -> MatchOutcome.LOST
    }
}
