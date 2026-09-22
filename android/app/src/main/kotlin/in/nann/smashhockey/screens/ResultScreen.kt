package `in`.nann.smashhockey.screens

import `in`.nann.smashhockey.core.feel.Scoreboard
import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.generated.Drill
import `in`.nann.smashhockey.core.match.MatchResult
import `in`.nann.smashhockey.game.Game
import `in`.nann.smashhockey.game.L
import `in`.nann.smashhockey.game.MatchPlan
import `in`.nann.smashhockey.game.Outcome
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.Entrance
import `in`.nann.smashhockey.ui.FlipDigits
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Panel
import `in`.nann.smashhockey.ui.WaveText

/**
 * The result (spec §16.5) — the twin of iOS's ResultScreen.swift: the final score flipping up goal
 * by goal, win, draw or loss, overtime if it happened — and one button on: back to the hub after a
 * season match, Again after a drill (one tap, A2) or Next drill once it is won, the menu after a
 * quick match. The result was saved before this screen appeared (§15).
 */
class ResultScreen(game: Game, private val outcome: Outcome) :
    Screen(Game.pose(Presentation.Screens.Result.eye, Presentation.Screens.Result.target), game) {
    private val digits: FlipDigits
    private val slab: Panel
    private var badge: Panel? = null

    init {
        val plan = outcome.plan
        val won = outcome.result == MatchResult.WON
        val header = if (plan !is MatchPlan.Practice) CopyKey.RESULT_FULLTIME else if (won) CopyKey.RESULT_DRILL_WON else CopyKey.RESULT_TIME_UP
        part(WaveText(kit, L(header), 0.2f, C.PAPER, id = "result_title_header"), at(0f, top - 0.3f))
        slab = part(Panel(kit, 1.66f, 1.0f, 0.18f, C.SUN, Entrance.Tumble), at(0f, top - 1.05f, tilt = 0.03f))
        val s = outcome.score
        val goals = outcome.drillGoals
        if (goals != null) {
            digits = child(FlipDigits(kit, Scoreboard.drill(0, goals), CARD_W, CARD_H, "result_score", L(CopyKey.RESULT_SCORE)),
                at(0f, -0.02f, z = 0.06f), slab.content)
        } else {
            for ((i, x) in listOf(-0.52f, 0.52f).withIndex()) {
                val colours = outcome.colours[i]
                val chip = child(Panel(kit, 0.44f, 0.2f, 0.06f, colours.primary, Entrance.Pop), at(x, 0.34f), slab.content)
                chip.show(0.0)
                child(Label3D(kit, outcome.codes?.get(i) ?: "", 0.09f, colours.secondary, maxWidth = 0.4f), parent = chip.content).show(0.0)
            }
            digits = child(FlipDigits(kit, Scoreboard.score(0, 0), CARD_W, CARD_H, "result_score", L(CopyKey.RESULT_SCORE)),
                at(0f, -0.1f, z = 0.06f), slab.content)
            val key = if (won) CopyKey.RESULT_WIN else if (outcome.result == MatchResult.LOST) CopyKey.RESULT_LOSS else CopyKey.RESULT_DRAW
            val b = part(Panel(kit, 0.62f, 0.26f, 0.12f, if (won) C.PINK else C.GREEN, Entrance.Pop), at(0.5f, top - 1.58f, z = 0.2f, tilt = -0.2f))
            child(Label3D(kit, L(key), 0.1f, C.INK, maxWidth = 0.54f), parent = b.content).show(0.0)
            badge = b
        }
        digits.show(0.0)
        digits.onLanded = { slab.thud() }
        if (outcome.overtime) part(Label3D(kit, L(CopyKey.RESULT_OT), 0.07f, C.PAPER, maxWidth = 1.5f), at(0f, top - 1.8f))

        fun button(key: CopyKey, id: String, text: Float = 0.13f, action: () -> Unit) =
            BlockButton(kit, L(key), id, BlockButton.Style.PRIMARY, 1.3f, 0.38f, text, action = action)
        val next = when {
            plan == MatchPlan.Season -> button(CopyKey.RESULT_HUB, "result_hub_button") { game.go(Game.Place.Hub) }
            plan is MatchPlan.Practice && won -> {
                val later = Drill.entries.getOrNull(Drill.entries.indexOf(plan.drill) + 1)
                if (later != null) button(CopyKey.RESULT_NEXT_DRILL, "result_next_button") { game.go(Game.Place.Training(later)) }
                else button(CopyKey.RESULT_DRILLS, "result_drills_button") { game.go(Game.Place.Training(null)) }
            }
            plan is MatchPlan.Practice -> {
                // A failed drill: again in one tap (A2), or back to the drills (§16.5).
                part(BlockButton(kit, L(CopyKey.TRAINING_TITLE), "result_training_button", BlockButton.Style.QUIET, 1.0f, 0.3f, 0.1f) {
                    game.go(Game.Place.Training(null))
                }, at(0f, bottom + 0.9f))
                button(CopyKey.RESULT_AGAIN, "result_again_button", 0.14f) { game.play(MatchPlan.Practice(plan.drill)) }
            }
            else -> button(CopyKey.RESULT_TITLE, "result_title_button", 0.14f) { game.go(game.home) }
        }
        next.bobs = true
        part(next, at(0f, bottom + 0.4f))
    }

    /** The final score's shape with every digit a zero — where the count starts. */

    override fun show(after: Double) {
        super.show(after)
        // Count up, one goal at a time, once the slab has landed.
        val s = outcome.score
        val steps = ArrayList<String>()
        val goals = outcome.drillGoals
        if (goals != null) {
            for (g in 0..minOf(s[0], goals)) steps += Scoreboard.drill(g, goals)
        } else {
            steps += Scoreboard.score(0, 0)
            for (h in 0..s[0]) steps += Scoreboard.score(h, 0)
            for (a in 1..s[1]) steps += Scoreboard.score(s[0], a)
        }
        // The ladder runs the same length whether the score is 1:0 or 12:11.
        val tick = minOf(0.4, 3.6 / maxOf(1, steps.size - 1))
        for ((i, text) in steps.drop(1).withIndex()) stage.after(after + 0.9 + i * tick) { digits.set(text) }
        stage.after(after + 0.9 + steps.size * tick) {
            if (outcome.result != MatchResult.WON) return@after
            digits.celebrate()
            badge?.celebrate(1.2)
            slab.celebrate(0.6)
        }
    }

    private companion object {
        /** Two cards a side, so 0:0 and 12:11 stand in the same place (§16.4). */
        const val CARD_W = 0.26f
        const val CARD_H = 0.36f
    }
}
