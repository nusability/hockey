package `in`.nann.smashhockey.screens

import `in`.nann.smashhockey.core.generated.Career
import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.game.Game
import `in`.nann.smashhockey.game.L
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.Entrance
import `in`.nann.smashhockey.ui.KitDisk
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Panel
import `in`.nann.smashhockey.ui.Paragraph
import `in`.nann.smashhockey.ui.WaveText

/**
 * How to play (spec §16.8) — the twin of iOS's HelpScreen.swift: the prototype's six lessons, one
 * card at a time, and above them the one-touch control itself — a disk with the ball circling it
 * and an aim line that turns pink at the goal and green at a team-mate. Next tips the card away
 * and the next one up.
 */
class HelpScreen(game: Game) : Screen(Game.pose(Presentation.Screens.Help.eye, Presentation.Screens.Help.target), game) {
    private var index = 0
    private var card: Panel? = null
    private val next: BlockButton

    init {
        part(WaveText(kit, L(CopyKey.HELP_TITLE), 0.16f, C.CREAM, bob = 0.6f, id = "help_title_header"), at(0f, top - 0.22f))
        part(KitDisk(kit, 0.2f, Career.demoClub.primary, Career.demoClub.secondary, ball = true), at(0f, top - 0.95f))
        part(BlockButton(kit, L(CopyKey.COMMON_BACK), "help_back_button", BlockButton.Style.QUIET, 0.78f, 0.32f, 0.1f) {
            game.go(game.home)
        }, at(-0.46f, bottom + 0.3f))
        next = part(BlockButton(kit, L(CopyKey.HELP_NEXT), "help_next_button", BlockButton.Style.PRIMARY, 0.78f, 0.32f, 0.1f) {
            advance()
        }, at(0.46f, bottom + 0.3f))
        next.bobs = true
    }

    override fun show(after: Double) {
        super.show(after)
        showCard(after + 0.4)
    }

    private fun showCard(after: Double) {
        val y = (top - 1.45f + bottom + 0.55f) / 2
        val panel = child(Panel(kit, 1.66f, 1.35f, 0.14f, C.CREAM, Entrance.Tumble), at(0f, y, tilt = if (index % 2 == 0) 0.02f else -0.02f), layer)
        child(Label3D(kit, "${index + 1} / ${LESSONS.size}", 0.05f, C.TEAL_SHADE), at(0f, 0.54f), panel.content).show(0.0)
        child(Paragraph(kit, L(LESSONS[index]), 0.066f, C.INK, 1.44f, id = "help_card"), at(0f, -0.04f), panel.content).show(0.0)
        panel.show(after)
        card = panel
    }

    private fun advance() {
        if (index + 1 >= LESSONS.size) { game.go(game.home); return }
        card?.let { old ->
            old.hide(0.0)
            stage.after(0.9) { stage.remove(old.node) }
        }
        index++
        if (index + 1 == LESSONS.size) next.retitle(L(CopyKey.HELP_DONE))
        showCard(0.25)
    }

    override fun leave() {
        card?.hide(0.0)
        super.leave()
    }

    private companion object {
        val LESSONS = listOf(CopyKey.HELP_1, CopyKey.HELP_2, CopyKey.HELP_3, CopyKey.HELP_4, CopyKey.HELP_5, CopyKey.HELP_6)
    }
}
