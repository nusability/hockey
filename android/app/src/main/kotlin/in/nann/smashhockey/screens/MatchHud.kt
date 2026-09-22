package `in`.nann.smashhockey.screens

import `in`.nann.smashhockey.core.feel.Scoreboard
import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.feel.Banner
import `in`.nann.smashhockey.core.match.MatchEvent
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.core.match.snapshot
import `in`.nann.smashhockey.game.Game
import `in`.nann.smashhockey.game.Kickoff
import `in`.nann.smashhockey.game.L
import `in`.nann.smashhockey.game.MatchPlan
import `in`.nann.smashhockey.game.Names
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.Entrance
import `in`.nann.smashhockey.ui.FlipDigits
import `in`.nann.smashhockey.ui.KitSound
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Panel
import `in`.nann.smashhockey.ui.Presentable
import `in`.nann.smashhockey.ui.UiNode
import `in`.nann.smashhockey.ui.WaveText

/**
 * The match's HUD (spec §16.4) on the camera-parented rig (ADR 0005) — the twin of iOS's
 * MatchHud.swift: at the top edge, clear of the pitch, both teams' short codes on their kit
 * colours, the score and the clock as flip digits, the period as three pips (or OT), and a pause
 * button in the corner. Goals flip the score and wobble the board; banners pop in the middle. A
 * drill shows its goals of the target and the clock (§10). It runs on real time, so §8.6's slow
 * motion leaves it at full speed.
 */
class MatchHud(game: Game, private val plan: MatchPlan, kickoff: Kickoff) : Screen(game) {
    private val drillGoals = kickoff.drillGoals
    private val board: Panel = part(Panel(kit, BOARD.boardWidth.toFloat(), 0.38f, 0.12f, C.BOARD, Entrance.Drop),
        at(-0.12f, top - 0.26f))
    private val scores = arrayOfNulls<FlipDigits>(2)
    private val shownScore = intArrayOf(0, 0)
    private val clock: FlipDigits
    private val pips = ArrayList<UiNode>()
    private var overtime: Label3D? = null
    private val pause: BlockButton
    private val pauseParts = ArrayList<Presentable>()
    private var banner: WaveText? = null
    private var shownOvertime = false
    private var shownPeriod = 1
    private var shownClock = ""

    init {
        val goals = drillGoals
        if (goals != null) {
            val digits = child(FlipDigits(kit, Scoreboard.drill(0, goals), CARD_W, CARD_H, "match_goals", L(CopyKey.HUD_GOALS)),
                at(0f, 0f, z = 0.05f), board.content)
            digits.onLanded = { board.thud() }
            digits.show(0.0)
            scores[0] = digits
        } else {
            for (i in 0..1) {
                val colours = kickoff.colours[i]
                val x = if (i == 0) -BOARD.chipX.toFloat() else BOARD.chipX.toFloat()
                val chip = child(Panel(kit, CHIP, 0.26f, 0.06f, colours.primary, Entrance.Pop), at(x, 0f), board.content)
                chip.show(0.0)
                child(Label3D(kit, kickoff.codes?.get(i) ?: "", 0.085f, colours.secondary, maxWidth = CHIP - 0.04f),
                    parent = chip.content).show(0.0)
            }
            for (side in 0..1) scores[side] = makeScore(side, Scoreboard.score(0))
            child(Label3D(kit, ":", 0.12f, C.CARD_INK), parent = board.content).show(0.0)
        }
        shownClock = Names.clock(kickoff.match.snapshot.clock)
        clock = part(FlipDigits(kit, shownClock, 0.11f, 0.15f, "match_clock", L(CopyKey.MATCH_CLOCK), entrance = Entrance.Drop),
            at(-0.12f, top - 0.6f))
        if (drillGoals == null) {
            val holder = part(Panel(kit, 0.36f, 0.13f, 0.05f, C.BOARD, Entrance.Drop), at(0.34f, top - 0.6f))
            for (i in 0 until Tuning.Match.periods) {
                pips += kit.slab(0.07f, 0.07f, 0.03f, if (i == 0) C.SUN else C.DISABLED_SHADE, holder.content, corner = 0.02f)
                    .also { it.setPosition((i - 1) * 0.1f, 0f, 0.01f) }
            }
            // In overtime "OT" takes the clock's place (§16.4).
            overtime = child(Label3D(kit, L(CopyKey.HUD_OT), 0.11f, C.PINK, entrance = Entrance.Pop), at(-0.12f, top - 0.6f, z = 0.06f), layer)
        }
        pause = part(BlockButton(kit, "II", "match_pause_button", BlockButton.Style.QUIET, 0.26f, 0.26f, 0.11f, Entrance.Pop,
            label = L(CopyKey.HUD_PAUSE)) { game.pause(true) }, at(0.72f, top - 0.26f))
        buildPausePanel(plan == MatchPlan.Season)
    }

    private fun makeScore(side: Int, text: String): FlipDigits {
        val x = BOARD.scoreX.toFloat()
        val d = child(FlipDigits(kit, text, CARD_W, CARD_H, if (side == 0) "match_home_score" else "match_away_score",
            L(if (side == 0) CopyKey.MATCH_SCORE_HOME else CopyKey.MATCH_SCORE_AWAY)),
            at(if (side == 0) -x else x, 0f, z = 0.05f), board.content)
        d.onLanded = { board.thud() }
        d.show(0.0)
        return d
    }

    private fun buildPausePanel(season: Boolean) {
        val height = if (season) 1.3f else 1.1f
        val panel = child(Panel(kit, 1.4f, height, 0.12f, C.PAPER, Entrance.Tumble), at(0f, 0f, z = 0.4f), layer)
        val y0 = height / 2
        child(Label3D(kit, L(CopyKey.PAUSE_TITLE), 0.15f, C.INK, maxWidth = 1.2f), at(0f, y0 - 0.2f), panel.content).show(0.0)
        if (season) {
            child(Label3D(kit, L(CopyKey.PAUSE_FORFEIT), 0.06f, C.PINK_INK, maxWidth = 1.25f), at(0f, y0 - 0.4f), panel.content).show(0.0)
        }
        val resume = child(BlockButton(kit, L(CopyKey.PAUSE_RESUME), "pause_resume_button", BlockButton.Style.PRIMARY, 1.0f, 0.3f) {
            game.pause(false)
        }, at(0f, -height / 2 + 0.58f), panel.content)
        val quit = child(BlockButton(kit, L(CopyKey.PAUSE_QUIT), "pause_quit_button", BlockButton.Style.DANGER, 1.0f, 0.3f) {
            game.quit()
        }, at(0f, -height / 2 + 0.22f), panel.content)
        pauseParts += listOf(panel, resume, quit)
    }

    fun setPaused(on: Boolean) {
        if (on) {
            KitSound.sweep()
            for ((i, p) in pauseParts.withIndex()) p.show(i * motion.staggerSeconds * 2)
        }
        else for (p in pauseParts.asReversed()) p.hide(0.0)
        pause.isEnabled = !on
    }

    override fun leave() {
        for (p in pauseParts) p.hide(0.0)
        banner?.hide(0.0)
        overtime?.hide(0.0)
        super.leave()
    }

    // ---------------------------------------------------------------- what the match says

    /** The board reacts to a goal; the pause goes once the match is over. The banners come from [banner]. */
    fun event(e: MatchEvent) {
        when (e) {
            is MatchEvent.Goal -> board.celebrate(if (e.team == 0) 1.0 else 0.5)
            is MatchEvent.End -> pause.isEnabled = false
            else -> Unit
        }
    }

    /**
     * A banner (§16.4, decided by the core's MatchCues): a word in the middle of the screen whose
     * letters drop in — pop, for a good one — bob, and hop away after its seconds.
     */
    fun banner(b: Banner) {
        val bs = Presentation.Banner
        val (colour, height) = when (b.style) {
            Banner.Style.GOOD -> bs.good to bs.heightGood
            Banner.Style.BAD -> bs.bad to bs.heightBad
            Banner.Style.WARN -> bs.warn to bs.heightWarn
            Banner.Style.INFO -> bs.info to bs.heightInfo
        }
        banner?.let { old ->
            old.hide(0.0)
            stage.after(0.8) { stage.remove(old.node) }
        }
        val good = b.style == Banner.Style.GOOD
        val w = child(WaveText(kit, L(b.key, *b.args.toTypedArray()), height.toFloat(), colour, bob = if (good) 2.5f else 1.5f,
            id = "match_banner_header", entrance = if (good) Entrance.Pop else Entrance.Drop), at(0f, 0.35f, z = 0.3f, tilt = 0.06f), layer)
        w.show(0.0)
        banner = w
        stage.after(b.seconds) {
            if (banner !== w) return@after
            w.hide(0.0)
            stage.after(0.8) { stage.remove(w.node) }
            banner = null
        }
    }

    // ---------------------------------------------------------------- the frame

    override fun update(dt: Double) {
        if (game.pitch.plan != plan) return
        val s = game.pitch.snapshot ?: return
        val goals = drillGoals
        if (goals != null) {
            scores[0]?.set(Scoreboard.drill(s.score[0], goals))
        } else {
            // The board always holds two cards a side, so a tenth goal flips the tens card rather
            // than rebuilding anything (§16.4).
            for (side in 0..1) {
                if (s.score[side] == shownScore[side]) continue
                scores[side]?.set(Scoreboard.score(s.score[side]))
                scores[side]?.celebrate()
                shownScore[side] = s.score[side]
            }
        }
        val c = Names.clock(s.clock)
        if (c != shownClock) { shownClock = c; clock.set(c) }
        if (s.period != shownPeriod) {
            shownPeriod = s.period
            for ((i, pip) in pips.withIndex()) pip.recolour(if (i < s.period) C.SUN else C.DISABLED_SHADE)
        }
        if (s.overtime != shownOvertime) {
            shownOvertime = s.overtime
            if (s.overtime) {
                clock.hide(0.0)
                overtime?.show(0.0)
            }
        }
    }

    private companion object {
        /** The board's measures (§16.4), derived once from one card so both apps lay it out the
         *  same: two cards a side, a colon between them, a team chip outside each. */
        const val CARD_W = 0.14f
        const val CARD_H = 0.20f
        const val CHIP = 0.30f
        val BOARD = Scoreboard.metrics(CARD_W.toDouble(), CARD_W.toDouble() * 0.08, 0.084, CHIP.toDouble(), 0.03)
    }
}
