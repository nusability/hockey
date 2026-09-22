package `in`.nann.smashhockey.screens

import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.generated.Drill
import `in`.nann.smashhockey.core.generated.Role
import `in`.nann.smashhockey.core.generated.SaveRecord
import `in`.nann.smashhockey.core.season.isOpen
import `in`.nann.smashhockey.core.season.isWon
import `in`.nann.smashhockey.game.Game
import `in`.nann.smashhockey.game.L
import `in`.nann.smashhockey.game.MatchPlan
import `in`.nann.smashhockey.game.Names
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.Entrance
import `in`.nann.smashhockey.ui.KitSound
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Panel
import `in`.nann.smashhockey.ui.Paragraph
import `in`.nann.smashhockey.ui.Presentable
import `in`.nann.smashhockey.ui.Quat
import `in`.nann.smashhockey.ui.Tile
import `in`.nann.smashhockey.ui.WaveText

/**
 * Training (spec §16.6, §10) — the twin of iOS's TrainingScreen.swift: the eight drills as cards
 * in order — name, world, goals and time, what opposes, won or locked. A locked card shakes its
 * head. Choosing an open one tips its intro card up — the hint — with Start, which goes straight to
 * the drill's "get ready".
 */
class TrainingScreen(game: Game, intro: Drill?) :
    Screen(Game.pose(Presentation.Screens.Training.eye, Presentation.Screens.Training.target), game) {
    private var introParts: List<Presentable> = emptyList()
    private val cards = ArrayList<Tile>()

    init {
        val save = game.save
        part(WaveText(kit, L(CopyKey.TRAINING_TITLE), 0.17f, C.PAPER, bob = 0.6f, id = "training_title_header"), at(0f, top - 0.2f))
        val done = Drill.entries.count { save.isWon(it) }
        part(Label3D(kit, L(CopyKey.TRAINING_PROGRESS, done, Drill.entries.size), S.TEXT_SMALL, C.SUN, maxWidth = 1.6f,
            entrance = Entrance.Drop), at(0f, top - 0.43f))
        val contentTop = top - 0.58f
        val contentBottom = bottom + 0.62f
        val pitch = minOf(0.5f, (contentTop - contentBottom) / 4)
        for ((i, drill) in Drill.entries.withIndex()) {
            val x = if (i % 2 == 0) -0.45f else 0.45f
            val y = contentTop - pitch * (i / 2 + 0.5f)
            cards += part(card(drill, pitch - 0.05f, save), at(x, y))
        }
        part(BlockButton(kit, L(CopyKey.COMMON_BACK), "training_back_button", BlockButton.Style.QUIET, 0.8f, 0.3f, 0.09f) {
            game.go(game.home)
        }, at(0f, bottom + 0.3f))
        if (intro != null && save.isOpen(intro)) stage.after(0.9) { open(intro) }
    }

    private fun card(d: Drill, h: Float, save: SaveRecord): Tile {
        val open = save.isOpen(d)
        val won = save.isWon(d)
        val state = if (won) L(CopyKey.TRAINING_WON) else if (open) "" else L(CopyKey.TRAINING_LOCKED)
        val label = listOf(L(CopyKey.TRAINING_DRILL, d.number), L(d.nameKey), L(d.world.nameKey), state).filter { it.isNotEmpty() }.joinToString(", ")
        val t = Tile(kit, 0.86f, h, if (won) C.ROW_DARK else C.PAPER, id = "training_drill_${d.number}_button", label = label) { open(d) }
        t.isEnabled = open
        val ink = if (open) C.INK else C.DISABLED_INK
        letters(L(CopyKey.TRAINING_DRILL, d.number), 0.032f, if (open) C.GREEN_INK else C.DISABLED_INK, align = Label3D.Align.LEADING,
            x = -0.39f, y = h * 0.3f, parent = t.content)
        letters(L(d.nameKey).uppercase(), 0.05f, ink, maxWidth = 0.76f, align = Label3D.Align.LEADING, x = -0.39f, y = h * 0.08f, parent = t.content)
        val facts = "${Names.world(d.world)} · ${L(CopyKey.TRAINING_GOALS_IN, d.goals, d.seconds.toInt())}"
        letters(facts, 0.03f, ink, maxWidth = 0.76f, align = Label3D.Align.LEADING, x = -0.39f, y = -h * 0.13f, parent = t.content)
        letters(L(opposition(d)), 0.03f, if (open) C.PINK_INK else C.DISABLED_INK, maxWidth = 0.5f, align = Label3D.Align.LEADING,
            x = -0.39f, y = -h * 0.3f, parent = t.content)
        if (won || !open) {
            val badge = kit.slab(0.26f, 0.08f, 0.03f, if (won) C.GREEN else C.DISABLED_SHADE, t.content, corner = 0.03f)
            badge.setPosition(0.27f, -h * 0.3f, 0.02f)
            badge.setRotation(Quat().axisAngle(-0.12f, 0f, 0f, 1f))
            letters(state, 0.035f, C.INK, maxWidth = 0.22f, x = 0.27f, y = -h * 0.3f, z = 0.04f, parent = t.content)
        }
        return t
    }

    /** The intro card (§16.4, §16.6): the drill's name, its hint, and Start. */
    private fun open(d: Drill) {
        if (!game.save.isOpen(d)) return
        closeIntro()
        for ((i, c) in cards.withIndex()) c.isSelected = Drill.entries[i] == d
        cards.forEach { it.isEnabled = false }      // the cards behind the intro take no taps (§16.6)
        val panel = child(Panel(kit, 1.62f, 1.5f, 0.14f, C.PAPER, Entrance.Tumble), at(0f, 0.05f, z = 0.5f), layer)
        child(Label3D(kit, L(CopyKey.TRAINING_DRILL, d.number), 0.05f, C.GREEN_INK), at(0f, 0.6f), panel.content).show(0.0)
        child(Label3D(kit, L(d.nameKey).uppercase(), 0.11f, C.INK, maxWidth = 1.45f), at(0f, 0.45f), panel.content).show(0.0)
        child(Label3D(kit, L(CopyKey.TRAINING_GOALS_IN, d.goals, d.seconds.toInt()), 0.05f, C.PINK_INK, maxWidth = 1.4f),
            at(0f, 0.31f), panel.content).show(0.0)
        child(Paragraph(kit, L(d.hintKey), 0.058f, C.INK, 1.4f, id = "training_hint"), at(0f, -0.02f), panel.content).show(0.0)
        val start = child(BlockButton(kit, L(CopyKey.TRAINING_START), "training_start_button", BlockButton.Style.PRIMARY, 0.8f, 0.32f, 0.13f) {
            game.play(MatchPlan.Practice(d))
        }, at(0.33f, -0.52f), panel.content)
        start.bobs = true
        val close = child(BlockButton(kit, L(CopyKey.COMMON_BACK), "training_close_button", BlockButton.Style.QUIET, 0.56f, 0.28f, 0.08f) {
            closeIntro()
        }, at(-0.46f, -0.52f), panel.content)
        val parts = listOf(panel, start, close)
        KitSound.sweep()
        for ((i, p) in parts.withIndex()) p.show(i * motion.staggerSeconds * 3)
        introParts = parts
    }

    private fun closeIntro() {
        val panel = introParts.firstOrNull() as? Panel ?: return
        for (p in introParts.asReversed()) p.hide(0.0)
        introParts = emptyList()
        for (c in cards) c.isSelected = false
        for ((i, c) in cards.withIndex()) c.isEnabled = game.save.isOpen(Drill.entries[i])
        stage.after(0.9) { stage.remove(panel.node) }
    }

    override fun leave() {
        for (p in introParts) p.hide(0.0)
        super.leave()
    }

    companion object {
        /** What a drill's opponents are (§10): none, a goalie, dummies, or defenders. */
        fun opposition(d: Drill): CopyKey {
            val roles = d.away.map { it.role }
            return when {
                roles.isEmpty() -> CopyKey.TRAINING_NONE
                roles.any { it == Role.DEFENDER || it == Role.FORWARD } -> CopyKey.TRAINING_DEFENDERS
                Role.DUMMY in roles -> CopyKey.TRAINING_DUMMIES
                else -> CopyKey.TRAINING_GOALIE
            }
        }
    }
}
