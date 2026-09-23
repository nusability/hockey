package `in`.nann.smashhockey.core.season

import `in`.nann.smashhockey.core.generated.BoardRecord
import `in`.nann.smashhockey.core.generated.CareerRecord
import `in`.nann.smashhockey.core.generated.Club
import `in`.nann.smashhockey.core.generated.CreatedTeam
import `in`.nann.smashhockey.core.generated.Drill
import `in`.nann.smashhockey.core.generated.Fixture
import `in`.nann.smashhockey.core.generated.SaveFormat
import `in`.nann.smashhockey.core.generated.SaveRecord
import `in`.nann.smashhockey.core.generated.Season
import `in`.nann.smashhockey.core.generated.SeasonRecord
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.generated.TrainingRecord
import `in`.nann.smashhockey.core.generated.Tuning

/*
 * The save as the game's one state for the career, the season, training and the board (spec §2.2,
 * §10, §11, §12, §15): every change a player can make is a function from one save to the next, so
 * the trophy counts, the board and the season can never disagree. The iOS twin is SmashCore's
 * `Season/Save.swift`.
 */

/** A device's first save: no career, no season, no drill won, the board at its defaults. */
fun SaveRecord.Companion.fresh(): SaveRecord = SaveRecord(SaveFormat.version, null, null, TrainingRecord(emptyList()), Board.defaults)

/** The canonical JSON (shared/data/save.toml) — byte for byte what iOS writes. */
fun SaveRecord.encoded(): String = toJson().canonicalText()

/** Reads a save file. Throws [SaveDecodeException], typed, on anything but a well-formed record of this version. */
fun SaveRecord.Companion.decode(bytes: ByteArray): SaveRecord {
    val json = JsonValue.parse(bytes)
    if (json !is JsonValue.Obj) refuse(SaveDecodeError.WrongType("$"))
    val version = json.members.firstOrNull { it.first == "version" }?.second
        ?: refuse(SaveDecodeError.MissingField("$.version"))
    if (version !is JsonValue.Num) refuse(SaveDecodeError.WrongType("$.version"))
    if (version.value != SaveFormat.version.toLong()) refuse(SaveDecodeError.UnknownVersion(version.value))
    return fromJson(json, "$")
}

fun SaveRecord.Companion.decode(text: String): SaveRecord = decode(text.toByteArray(Charsets.UTF_8))

// --- The career (§2.2) ---------------------------------------------------------------------------

/** The player's team in league, cup and every match they play. */
val SaveRecord.playerTeam: TeamKey? get() = career?.team

/**
 * Confirms the team the player created — there is no other way into a career (§2.2); the name is
 * kept without its leading and trailing spaces.
 */
fun SaveRecord.createTeam(draft: TeamDraft): SaveRecord {
    if (career != null) refuse(GameError.CareerExists)
    val issues = CreatedTeamRules.issues(draft)
    if (issues.isNotEmpty()) refuse(GameError.InvalidTeam(issues))
    val team = CreatedTeam(CreatedTeamRules.trimmedName(draft.name), draft.short, draft.primary, draft.secondary, draft.world)
    return copy(career = CareerRecord(team, 0, 0), board = board.withTactics(Tactics.defaults))
}

/** Ends the career, its season and its trophies. Training progress survives (§2.2). */
fun SaveRecord.startOver(): SaveRecord = copy(career = null, season = null)

// --- The season (§11) ----------------------------------------------------------------------------

/**
 * Starts the first season, or the next once the last one is over, keeping the career and its
 * trophies; each season's number is one more than the last's (§15). [seed] seeds the season's stream
 * (§4.3); the app draws it, the vectors fix it.
 */
fun SaveRecord.startSeason(seed: Long): SaveRecord {
    val career = career ?: refuse(GameError.NoCareer)
    if (season != null && !season.isFinished) refuse(GameError.SeasonInProgress)
    return copy(season = SeasonEngine.start(seed, career, (season?.number ?: 0) + 1).advance(career.team, career).first)
}

/** The player's fixture on the current matchday. */
val SaveRecord.playerFixture: Fixture? get() = career?.let { c -> season?.playerFixture(c.team) }

/**
 * Records the player's match (goals from their side; [overtime] when a cup match was decided in
 * sudden death), closes the matchday and simulates on to the player's next fixture. At the
 * season's end the trophies grow when they are the player's; the end is returned with the save.
 */
fun SaveRecord.recordPlayed(goalsFor: Int, goalsAgainst: Int, overtime: Boolean = false): Pair<SaveRecord, SeasonEnd?> {
    val career = career ?: refuse(GameError.NoCareer)
    val season = season ?: refuse(GameError.NoSeason)
    val (next, end) = season.recordPlayed(career.team, goalsFor, goalsAgainst, overtime, career)
    val titles = career.leagueTitles + if (end?.champion == career.team) 1 else 0
    val cups = career.cups + if (end?.cupWinner == career.team) 1 else 0
    return copy(season = next, career = career.copy(leagueTitles = titles, cups = cups)) to end
}

/** Quitting a season match forfeits it as a 0–3 loss (§8.7). */
fun SaveRecord.forfeit(): Pair<SaveRecord, SeasonEnd?> =
    recordPlayed(Tuning.Match.forfeitFor, Tuning.Match.forfeitAgainst)

// --- Training (§10) ------------------------------------------------------------------------------

/** Records a won drill (once). */
fun SaveRecord.won(drill: Drill): SaveRecord =
    if (drill in training.won) this else copy(training = TrainingRecord(training.won + drill))

// --- The rules a decoded save is checked against --------------------------------------------------

internal fun SaveRecord.validate(path: String) {
    if (season == null) return
    if (career == null) refuse(SaveDecodeError.BrokenRule("$path.season", SaveRule.SEASON_WITHOUT_CAREER))
    if (season.teams != career.league) refuse(SaveDecodeError.BrokenRule("$path.season.teams", SaveRule.LEAGUE_IS_NOT_THE_CAREERS))
}

internal fun CareerRecord.validate(path: String) {
    if (leagueTitles < 0 || cups < 0) refuse(SaveDecodeError.BrokenRule(path, SaveRule.NEGATIVE_COUNT))
    val c = created
    val draft = TeamDraft(c.name, c.short, c.primary, c.secondary, c.world)
    if (CreatedTeamRules.issues(draft).isNotEmpty() || CreatedTeamRules.trimmedName(c.name) != c.name) {
        refuse(SaveDecodeError.BrokenRule("$path.created", SaveRule.CREATED_TEAM_INVALID))
    }
}

internal fun SeasonRecord.validate(path: String) {
    if (number < 1) refuse(SaveDecodeError.BrokenRule("$path.number", SaveRule.SEASON_NUMBER))
    if (teams.toSet().size != teams.size || teams.size != Tuning.Season.leagueTeams) {
        refuse(SaveDecodeError.BrokenRule("$path.teams", SaveRule.LEAGUE_IS_NOT_THE_CAREERS))
    }
    if (matchday !in 0..Season.plan.size) refuse(SaveDecodeError.BrokenRule("$path.matchday", SaveRule.MATCHDAY_OUT_OF_RANGE))
    fixtures.forEachIndexed { i, f ->
        val at = "$path.fixtures[$i]"
        if (f.matchday !in Season.plan.indices) refuse(SaveDecodeError.BrokenRule("$at.matchday", SaveRule.MATCHDAY_OUT_OF_RANGE))
        if (f.home !in teams || f.away !in teams || f.home == f.away) refuse(SaveDecodeError.BrokenRule(at, SaveRule.FIXTURE_NOT_IN_LEAGUE))
        val s = f.score ?: return@forEachIndexed
        if (s.home < 0 || s.away < 0) refuse(SaveDecodeError.BrokenRule("$at.score", SaveRule.NEGATIVE_COUNT))
        if (Season.plan[f.matchday].isCup()) {
            if (s.home == s.away) refuse(SaveDecodeError.BrokenRule("$at.score", SaveRule.CUP_SCORE_LEVEL))
        } else if (s.overtime) {
            refuse(SaveDecodeError.BrokenRule("$at.score", SaveRule.OVERTIME_OUTSIDE_CUP))
        }
    }
}

internal fun TrainingRecord.validate(path: String) {
    if (won.toSet().size != won.size) refuse(SaveDecodeError.BrokenRule("$path.won", SaveRule.DRILL_WON_TWICE))
}

internal fun BoardRecord.validate(path: String) {
    for ((key, v) in listOf("pressing" to pressing, "covering" to covering, "push_up" to pushUp, "discipline" to discipline)) {
        if (!(v >= Tuning.Board.tacticMin && v <= Tuning.Board.tacticMax)) {
            refuse(SaveDecodeError.BrokenRule("$path.$key", SaveRule.TACTIC_OUT_OF_RANGE))
        }
    }
    if (periodSeconds !in Tuning.Board.periodSeconds) refuse(SaveDecodeError.BrokenRule("$path.period_seconds", SaveRule.NOT_A_BOARD_CHOICE))
    if (ballSpinSeconds !in Tuning.Board.ballSpinSeconds) {
        refuse(SaveDecodeError.BrokenRule("$path.ball_spin_seconds", SaveRule.NOT_A_BOARD_CHOICE))
    }
}
