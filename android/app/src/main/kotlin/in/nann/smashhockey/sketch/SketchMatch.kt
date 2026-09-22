package `in`.nann.smashhockey.sketch

import `in`.nann.smashhockey.R
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.CameraPose
import `in`.nann.smashhockey.ui.DesignTokens.Colour
import `in`.nann.smashhockey.ui.Entrance
import `in`.nann.smashhockey.ui.FlipDigits
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Panel
import `in`.nann.smashhockey.ui.Presentable
import `in`.nann.smashhockey.ui.Slider3D
import `in`.nann.smashhockey.ui.UIStage
import `in`.nann.smashhockey.ui.UiNode
import `in`.nann.smashhockey.ui.WaveText
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.pow
import kotlin.math.sin

// THROWAWAY (SMASH-5): the match HUD over a fake match, the result, and the coach's board — the
// twin of iOS's SketchMatch.swift.

/**
 * Match HUD, on the camera-parented rig: the scoreboard with flip-card scores, a flip clock
 * ticking down, a pause button. A fake ball runs at a goal every few seconds; the score flips,
 * the board jellies, GOAL! bounces across. At 0:00, FULL TIME, then the result.
 */
class SketchMatchScreen(stage: UIStage, L: Copy, worldRoot: UiNode, private val go: Go) :
    SketchScreen(CameraPose(0f, 24f, -46f, 0f, 0f, 2f), stage) {
    val pause: BlockButton
    val resume: BlockButton
    private val quit: BlockButton
    private val board: Panel
    private val homeScore: FlipDigits
    private val awayScore: FlipDigits
    private val clock: FlipDigits
    private val goalText: WaveText
    private val fullTime: WaveText
    private val pausePanel: Panel
    private val pauseParts: List<Presentable>
    private val ball: UiNode = kit.sphere(0.36f, 0xFFFFFF, worldRoot)
    private var elapsed = 0.0
    private var nextGoal = 0
    private var homeGoals = 0
    private var awayGoals = 0
    private var running = false
    var paused = false; private set
    var onFinished: ((Int, Int) -> Unit)? = null
    private var shownSeconds = -1

    init {
        ball.setPosition(0f, 0.36f, 0f)
        ball.enabled = false
        val f = stage.hud
        val home = SketchData.clubs.getValue(SketchData.PLAYER)
        val away = SketchData.clubs.getValue(SketchData.OPPONENT)

        board = part(Panel(kit, 1.3f, 0.38f, 0.12f, Colour.BOARD, Entrance.Drop), f.node)
        board.rest.set(at(-0.12f, f.top - 0.26f))
        for ((club, x) in listOf(home to -0.45f, away to 0.45f)) {
            val chip = stage.add(Panel(kit, 0.34f, 0.26f, 0.06f, club.primary, Entrance.Pop), board.content)
            chip.rest.set(at(x, 0f))
            chip.show(0.0)
            stage.add(Label3D(kit, club.code, 0.085f, club.secondary), chip.content).show(0.0)
        }
        homeScore = stage.add(FlipDigits(kit, "0", 0.19f, 0.27f, "match_home_score", L(R.string.match_score_home)), board.content)
        homeScore.rest.set(at(-0.13f, 0f, z = 0.05f))
        homeScore.show(0.0)
        awayScore = stage.add(FlipDigits(kit, "0", 0.19f, 0.27f, "match_away_score", L(R.string.match_score_away)), board.content)
        awayScore.rest.set(at(0.13f, 0f, z = 0.05f))
        awayScore.show(0.0)
        stage.add(Label3D(kit, ":", 0.14f, Colour.CARD_INK), board.content).show(0.0)
        homeScore.onLanded = { board.thud() }
        awayScore.onLanded = { board.thud() }

        clock = part(FlipDigits(kit, clockText(SketchData.MATCH_SECONDS), 0.11f, 0.15f, "match_clock", L(R.string.match_clock),
            entrance = Entrance.Drop), f.node)
        clock.rest.set(at(-0.12f, f.top - 0.6f))

        pause = part(BlockButton(kit, "II", "match_pause_button", BlockButton.Style.QUIET, 0.26f, 0.26f, 0.11f, Entrance.Pop) {
            setPaused(true)
        }, f.node)
        pause.rest.set(at(0.72f, f.top - 0.26f))

        goalText = stage.add(WaveText(kit, L(R.string.match_goal), 0.36f, Colour.SUN, bob = 2f, id = "match_goal_header"), f.node)
        goalText.rest.set(at(0f, 0.35f, z = 0.3f, tilt = 0.08f))
        fullTime = stage.add(WaveText(kit, L(R.string.match_fulltime), 0.26f, Colour.CREAM, id = "match_fulltime_header"), f.node)
        fullTime.rest.set(at(0f, 0.3f, z = 0.3f))

        pausePanel = stage.add(Panel(kit, 1.4f, 1.1f, 0.12f, Colour.CREAM, Entrance.Tumble), f.node)
        pausePanel.rest.set(at(0f, 0f, z = 0.4f))
        val title = stage.add(Label3D(kit, L(R.string.pause_title), 0.15f, Colour.INK, maxWidth = 1.2f), pausePanel.content)
        title.rest.set(at(0f, 0.34f))
        title.show(0.0)
        resume = stage.add(BlockButton(kit, L(R.string.pause_resume), "pause_resume_button", BlockButton.Style.PRIMARY, 1.0f, 0.3f) {
            setPaused(false)
        }, pausePanel.content)
        resume.rest.set(at(0f, 0.02f))
        quit = stage.add(BlockButton(kit, L(R.string.pause_quit), "pause_quit_button", BlockButton.Style.DANGER, 1.0f, 0.3f) {
            quitMatch()
        }, pausePanel.content)
        quit.rest.set(at(0f, -0.34f))
        pauseParts = listOf(pausePanel, resume, quit)
    }

    /** m:ss of the seconds left, rounded up; formatted only when the second changes. */
    private fun clockText(remaining: Double): String {
        val s = ceil(remaining).toInt()
        return "${s / 60}:${(s % 60).toString().padStart(2, '0')}"
    }

    override fun show(after: Double) {
        super.show(after)
        elapsed = 0.0
        nextGoal = 0
        homeGoals = 0; awayGoals = 0
        homeScore.set("0")
        awayScore.set("0")
        shownSeconds = ceil(SketchData.MATCH_SECONDS).toInt()
        clock.set(clockText(SketchData.MATCH_SECONDS))
        paused = false
        ball.setPosition(0f, 0.36f, 0f)
        ball.enabled = true
        stage.after(after + 0.8) { running = true }
    }

    override fun hide() {
        super.hide()
        for (p in pauseParts) p.hide(0.0)
        goalText.hide(0.0)
        fullTime.hide(0.0)
        running = false
        stage.after(0.4) { ball.enabled = false }
    }

    fun setPaused(p: Boolean) {
        if (!running && !paused) return
        paused = p
        if (p) for ((i, part) in pauseParts.withIndex()) part.show(i * stage.motion.staggerSeconds * 2)
        else for (part in pauseParts.asReversed()) part.hide(0.0)
        pause.isEnabled = !p
    }

    private fun quitMatch() {
        paused = false
        running = false
        pause.isEnabled = true
        go(SketchScreenId.HUB)
    }

    override fun update(dt: Double) {
        if (!running || paused) return
        elapsed += dt
        val left = maxOf(0.0, SketchData.MATCH_SECONDS - elapsed)
        val secs = ceil(left).toInt()
        if (secs != shownSeconds) { shownSeconds = secs; clock.set(clockText(left)) }
        moveBall()
        if (nextGoal < SketchData.goals.size && elapsed >= SketchData.goals[nextGoal].at) {
            scored(SketchData.goals[nextGoal].home)
            nextGoal += 1
        }
        if (elapsed >= SketchData.MATCH_SECONDS) {
            running = false
            fullTime.show(0.0)
            pause.isEnabled = false
            stage.after(1.8) {
                pause.isEnabled = true
                onFinished?.invoke(homeGoals, awayGoals)
            }
        }
    }

    /**
     * The fake ball: a wiggly run from the centre spot into the scoring goal over the four seconds
     * before each goal; otherwise it idles on the spot.
     */
    private fun moveBall() {
        if (nextGoal >= SketchData.goals.size) { ball.setPosition(0f, 0.36f, 0f); return }
        val g = SketchData.goals[nextGoal]
        val u = ((elapsed - (g.at - 4)) / 4).coerceIn(0.0, 1.0).toFloat()
        val side = if (g.home) 1f else -1f
        val x = sin(u * PI.toFloat() * 2.5f) * 7 * (1 - u)
        val z = side * 27 * u.pow(1.3f)
        ball.setPosition(x, 0.36f + abs(sin(u * PI.toFloat() * 6)) * 0.4f * (1 - u), z)
    }

    private fun scored(home: Boolean) {
        if (home) homeGoals += 1 else awayGoals += 1
        homeScore.set("$homeGoals")
        awayScore.set("$awayGoals")
        (if (home) homeScore else awayScore).celebrate()
        board.celebrate()
        goalText.show(0.0)
        stage.after(1.5) { goalText.hide(0.0) }
        stage.after(0.9) { ball.setPosition(0f, 0.36f, 0f) }
    }
}

/**
 * Result: FULL TIME, a big score slab whose cards flip up from 0:0 to the final score, a WIN badge
 * that pops and jellies, Continue.
 */
class ResultScreen(stage: UIStage, private val L: Copy, go: Go) :
    SketchScreen(CameraPose(5f, 3.2f, 12f, 0f, 2.2f, 30f), stage) {
    val next: BlockButton
    private val digits: FlipDigits
    private val badge: Panel
    private val badgeLabel: Label3D
    private val slab: Panel
    private var finalHome = 0
    private var finalAway = 0

    init {
        val f = stage.frame(pose)
        val home = SketchData.clubs.getValue(SketchData.PLAYER)
        val away = SketchData.clubs.getValue(SketchData.OPPONENT)

        val header = part(WaveText(kit, L(R.string.match_fulltime), 0.2f, Colour.CREAM, id = "result_title_header"), f.node)
        header.rest.set(at(0f, f.top - 0.3f))
        slab = part(Panel(kit, 1.66f, 1.0f, 0.18f, Colour.SUN, Entrance.Tumble), f.node)
        slab.rest.set(at(0f, f.top - 1.05f, tilt = 0.03f))
        for ((club, x) in listOf(home to -0.52f, away to 0.52f)) {
            val chip = stage.add(Panel(kit, 0.44f, 0.2f, 0.06f, club.primary, Entrance.Pop), slab.content)
            chip.rest.set(at(x, 0.34f))
            chip.show(0.0)
            stage.add(Label3D(kit, club.code, 0.09f, club.secondary), chip.content).show(0.0)
        }
        digits = stage.add(FlipDigits(kit, "0:0", 0.32f, 0.44f, "result_score", L(R.string.result_score)), slab.content)
        digits.rest.set(at(0f, -0.1f, z = 0.06f))
        digits.show(0.0)
        digits.onLanded = { slab.thud() }

        badge = part(Panel(kit, 0.62f, 0.26f, 0.12f, Colour.CORAL, Entrance.Pop), f.node)
        badge.rest.set(at(0.5f, f.top - 1.58f, z = 0.2f, tilt = -0.2f))
        badgeLabel = stage.add(Label3D(kit, L(R.string.result_win), 0.13f, Colour.CREAM, maxWidth = 0.52f), badge.content)
        badgeLabel.show(0.0)

        next = part(BlockButton(kit, L(R.string.result_continue), "result_continue_button", BlockButton.Style.PRIMARY,
            1.3f, 0.38f, 0.14f) { go(SketchScreenId.HUB) }, f.node)
        next.rest.set(at(0f, f.bottom + 0.4f))
        next.bobs = true
    }

    fun setScore(home: Int, away: Int) {
        finalHome = home; finalAway = away
        badgeLabel.set(L(if (home > away) R.string.result_win else if (home < away) R.string.result_loss else R.string.result_draw))
    }

    override fun show(after: Double) {
        digits.set("0:0")
        super.show(after)
        // Count up, one goal at a time, once the slab has landed.
        val steps = ArrayList<String>()
        for (h in 0..finalHome) steps += "$h:0"
        for (a in 1..finalAway) steps += "$finalHome:$a"
        for ((i, s) in steps.drop(1).withIndex()) stage.after(after + 0.9 + i * 0.4) { digits.set(s) }
        val landed = after + 0.9 + steps.size * 0.4
        stage.after(landed) {
            digits.celebrate()
            badge.celebrate(1.2)
            slab.celebrate(0.6)
        }
    }
}

/** The coach's board (§12): three of its 0–1 settings on sliders, Reset, Back. */
class CoachScreen(stage: UIStage, L: Copy, go: Go) :
    SketchScreen(CameraPose(19f, 8f, -8f, -3f, 2f, 12f), stage) {
    val sliders = ArrayList<Slider3D>()
    val back: BlockButton

    init {
        val f = stage.frame(pose)
        val header = part(WaveText(kit, L(R.string.coach_title), 0.16f, Colour.CREAM, bob = 0.6f, id = "coach_title_header"), f.node)
        header.rest.set(at(0f, f.top - 0.25f))
        val board = part(Panel(kit, 1.76f, 1.5f, 0.12f, Colour.CHALK, Entrance.Tumble), f.node)
        board.rest.set(at(0f, f.top - 1.3f))
        val settings = listOf(L(R.string.coach_pressing) to "coach_pressing_field",
            L(R.string.coach_covering) to "coach_covering_field",
            L(R.string.coach_pushup) to "coach_pushup_field")
        for ((i, s) in settings.withIndex()) {
            val slider = part(Slider3D(kit, s.first, s.second, 0.55, 1.4f, entrance = Entrance.Slide(fromLeft = i % 2 == 0)), board.content)
            slider.rest.set(at(0f, 0.42f - i * 0.42f, z = 0.02f))
            sliders += slider
        }
        val reset = part(BlockButton(kit, L(R.string.coach_reset), "coach_reset_button", BlockButton.Style.QUIET, 0.78f, 0.32f, 0.1f) {
            for (s in sliders) s.set(0.55)
            board.celebrate(0.4)
        }, f.node)
        reset.rest.set(at(-0.46f, f.bottom + 0.36f))
        back = part(BlockButton(kit, L(R.string.hub_back), "coach_back_button", BlockButton.Style.PRIMARY, 0.78f, 0.32f, 0.1f) {
            go(SketchScreenId.TITLE)
        }, f.node)
        back.rest.set(at(0.46f, f.bottom + 0.36f))
    }
}
