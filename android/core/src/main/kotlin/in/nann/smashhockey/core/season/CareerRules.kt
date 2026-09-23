package `in`.nann.smashhockey.core.season

import `in`.nann.smashhockey.core.generated.BoardRecord
import `in`.nann.smashhockey.core.generated.Career
import `in`.nann.smashhockey.core.generated.CareerRecord
import `in`.nann.smashhockey.core.generated.Club
import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.generated.World
import java.text.Normalizer

/** A team the player is creating (spec §2.2): what the create screen edits before confirming. */
data class TeamDraft(val name: String, val short: String, val primary: Int, val secondary: Int, val world: World)

/** Why a draft cannot be confirmed (spec §2.2). Listed in this order by [CreatedTeamRules.issues]; keys match iOS. */
enum class TeamIssue(val key: String) {
    NAME_TOO_SHORT("nameTooShort"),
    NAME_TOO_LONG("nameTooLong"),
    SHORT_CODE_NOT_THREE_LETTERS("shortCodeNotThreeLetters"),
    SHORT_CODE_IS_A_CLUBS("shortCodeIsAClubs"),
    PRIMARY_NOT_IN_PALETTE("primaryNotInPalette"),
    SECONDARY_NOT_IN_PALETTE("secondaryNotInPalette"),
}

/** What the game refuses to do (spec §2.2, §11, §8.7). Every refusal is typed; none is a string. */
sealed interface GameError {
    /** A career exists: there is no switching (§2.2) — only starting over. */
    data object CareerExists : GameError
    data object NoCareer : GameError
    data class InvalidTeam(val issues: List<TeamIssue>) : GameError
    /** A new season starts only when there is none or the last one is over (§11.4). */
    data object SeasonInProgress : GameError
    data object NoSeason : GameError
    data object SeasonFinished : GameError
    /** The current matchday has no fixture for the player (they are never left on one: §11.2). */
    data object NoPlayerFixture : GameError
    data object NegativeGoals : GameError
    /** A cup match always has a winner (§8.4). */
    data object CupScoreLevel : GameError
    data object OvertimeOutsideCup : GameError
    /** Sudden death ends on the next goal (§8.4). */
    data object OvertimeNotByOneGoal : GameError
    /** A coach's board value outside §12's ranges and steps. */
    data object NotABoardValue : GameError
}

class GameException(val error: GameError) : Exception(error.toString())

internal fun refuse(error: GameError): Nothing = throw GameException(error)

/** The created team's rules (spec §2.2). */
object CreatedTeamRules {
    /** The name as it is kept: leading and trailing spaces (U+0020) dropped. */
    fun trimmedName(name: String): String = name.trim(' ')

    /**
     * The short code derived from a name: its letters A–Z (accents dropped, uppercased) — the
     * first, the second and the first later one that makes a code no club has; failing that, the
     * first two letters (as many as there are) padded with [Career.shortCodePad].
     */
    fun suggestedShortCode(name: String): String {
        val letters = Normalizer.normalize(name, Normalizer.Form.NFD).mapNotNull {
            when (it) {
                in 'A'..'Z' -> it
                in 'a'..'z' -> it.uppercaseChar()
                else -> null
            }
        }
        val clubCodes = Club.entries.map { it.short }.toSet()
        if (letters.size >= Career.shortCodeLength) {
            for (k in 2 until letters.size) {
                val code = "${letters[0]}${letters[1]}${letters[k]}"
                if (code !in clubCodes) return code
            }
        }
        return letters.take(2).joinToString("").padEnd(Career.shortCodeLength, Career.shortCodePad[0])
    }

    /** Every rule the draft breaks, in [TeamIssue] order; empty when it can be confirmed. */
    fun issues(draft: TeamDraft): List<TeamIssue> {
        val out = ArrayList<TeamIssue>()
        val name = trimmedName(draft.name)
        val length = name.codePointCount(0, name.length)
        if (length < Career.nameMinLength) out.add(TeamIssue.NAME_TOO_SHORT)
        if (length > Career.nameMaxLength) out.add(TeamIssue.NAME_TOO_LONG)
        if (draft.short.length != Career.shortCodeLength || !draft.short.all { it in 'A'..'Z' }) {
            out.add(TeamIssue.SHORT_CODE_NOT_THREE_LETTERS)
        } else if (Club.entries.any { it.short == draft.short }) {
            out.add(TeamIssue.SHORT_CODE_IS_A_CLUBS)
        }
        if (Career.kitPalette.none { it.primary == draft.primary }) out.add(TeamIssue.PRIMARY_NOT_IN_PALETTE)
        if (Career.kitPalette.none { it.secondary == draft.secondary }) out.add(TeamIssue.SECONDARY_NOT_IN_PALETTE)
        return out
    }
}

/** The player's team: always the one they created (§2.2) — there is no picking a club. */
val CareerRecord.team: TeamKey get() = TeamKey.CREATED

/**
 * The league's eight teams in their canonical order (§11.1): the clubs as declared, the player's
 * team in the place of the club it replaces.
 */
val CareerRecord.league: List<TeamKey>
    get() = Club.entries.map { club -> if (club == Career.createdReplaces) TeamKey.CREATED else TeamKey.of(club) }

/** The created team as a draft, for the screen that edits it (§16.1). */
val CareerRecord.draft: TeamDraft
    get() = TeamDraft(created.name, created.short, created.primary, created.secondary, created.world)

/** A team's short code — the player's team's own, or a club's. */
fun CareerRecord.short(of: TeamKey): String = of.club?.short ?: created.short

/** A team's rating (§2.1); the player's team's is fixed (§2.2). */
fun CareerRecord.rating(of: TeamKey): Int = of.club?.rating ?: Career.createdRating

/** The coach's board (§12): its defaults and the tactics a created team starts it from. */
object Board {
    val defaults: BoardRecord = BoardRecord(
        pressing = Tactics.defaults.pressing, covering = Tactics.defaults.covering, pushUp = Tactics.defaults.pushUp,
        discipline = Tactics.defaults.discipline, formation = Formation.entries[0],
        periodSeconds = Tuning.Board.periodSecondsDefault, ballSpinSeconds = Tuning.Board.ballSpinSecondsDefault,
    )

}

/**
 * The board with [t]'s tactics — creating a team starts the board from its tactics (§2.2) and
 * keeps the formation, period length and ball spin the player set.
 */
fun BoardRecord.withTactics(t: Tactics): BoardRecord =
    copy(pressing = t.pressing, covering = t.covering, pushUp = t.pushUp, discipline = t.discipline)
