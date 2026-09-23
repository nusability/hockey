package `in`.nann.smashhockey.core.season

import `in`.nann.smashhockey.core.generated.CareerRecord
import `in`.nann.smashhockey.core.generated.Fixture
import `in`.nann.smashhockey.core.generated.Season
import `in`.nann.smashhockey.core.generated.SeasonRecord
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.generated.Tuning

/*
 * A team's detail behind its row in the league table (spec §16.3a): what it has played, won, drawn
 * and lost, where it stands, how its last matches went and what it plays next — all read off the
 * season record's fixtures (§15), one computation for both platforms like `Scoreboard` and
 * `TextLayout`. The iOS twin is SmashCore's `Season/Form.swift`.
 */

/** How a match went for the team the detail is about (§16.3a). */
enum class FormKind { WON, DRAWN, LOST }

/** One of a team's recent matches (§16.3a), from that team's side. */
data class FormMatch(
    val opponent: TeamKey,
    /** The team played this one at home. */
    val home: Boolean,
    val goalsFor: Int,
    val goalsAgainst: Int,
    /** A cup tie rather than a league round (§11.1). */
    val cup: Boolean,
    /** The cup tie was decided in sudden death (§8.4). */
    val overtime: Boolean,
) {
    val kind: FormKind
        get() = if (goalsFor > goalsAgainst) FormKind.WON else if (goalsFor == goalsAgainst) FormKind.DRAWN else FormKind.LOST
}

/** Everything a team's detail shows (spec §16.3a). */
data class TeamDetail(
    val team: TeamKey,
    /** Its place in the table, 1-based (§11.4). */
    val position: Int,
    /**
     * Played, won, drawn, lost, goals for and against, goal difference and points — the league
     * only, exactly as the table counts them (§11.4).
     */
    val row: TableRow,
    /**
     * Its last matches, most recent first — at most `Tuning.Season.formMatches`, league and cup
     * alike, fewer early in a season.
     */
    val form: List<FormMatch>,
    /** The team's next fixture, league or cup; null once it has none left this season. */
    val next: Fixture?,
)

/**
 * The detail of [team] (§16.3a). The fixtures are read in the order they were drawn (§11.1): a
 * matchday's later, so the most recent result is the last played fixture of the highest matchday,
 * and the next fixture the first unplayed one of the lowest.
 */
fun SeasonRecord.detail(team: TeamKey, career: CareerRecord): TeamDetail {
    val standings = table(career)
    val place = standings.indexOfFirst { it.team == team }
    // Fixtures are appended matchday by matchday, so index order is drawn order within one.
    val mine = fixtures.withIndex().filter { it.value.home == team || it.value.away == team }
        .sortedWith(compareBy({ it.value.matchday }, { it.index })).map { it.value }
    val form = ArrayList<FormMatch>()
    for (f in mine.asReversed()) {
        val s = f.score ?: continue
        if (form.size >= Tuning.Season.formMatches) break
        val home = f.home == team
        form += FormMatch(
            opponent = if (home) f.away else f.home, home = home,
            goalsFor = if (home) s.home else s.away, goalsAgainst = if (home) s.away else s.home,
            cup = Season.plan[f.matchday].isCup(), overtime = s.overtime,
        )
    }
    return TeamDetail(
        team = team, position = if (place >= 0) place + 1 else 1,
        row = if (place >= 0) standings[place] else TableRow(team),
        form = form, next = mine.firstOrNull { it.score == null },
    )
}
