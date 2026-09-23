package `in`.nann.smashhockey.game

import `in`.nann.smashhockey.core.match.MatchResult
import `in`.nann.smashhockey.scene.TeamColours

/** How a match or drill ended, for the result screen (§16.5). */
data class Outcome(
    val plan: MatchPlan,
    val score: List<Int>,
    val overtime: Boolean,
    val result: MatchResult,
    val codes: List<String>?,
    /** The two sides' full names, the player's first — shown under the codes (§16.5); null in a drill. */
    val names: List<String>?,
    val colours: List<TeamColours>,
    val drillGoals: Int?,
)
