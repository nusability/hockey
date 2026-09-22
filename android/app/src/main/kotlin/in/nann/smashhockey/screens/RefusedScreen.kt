package `in`.nann.smashhockey.screens

import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.game.Game
import `in`.nann.smashhockey.game.L
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.Entrance
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Panel
import `in`.nann.smashhockey.ui.Paragraph
import `in`.nann.smashhockey.ui.WaveText

/**
 * A save that cannot be read (spec §15) — the twin of iOS's RefusedScreen.swift: the game says so
 * on a screen of its own and never opens as if the player were new. The file stays on the phone,
 * untouched, beside the new one; the one way on is to start over.
 */
class RefusedScreen(game: Game, why: String) :
    Screen(Game.pose(Presentation.Screens.Refused.eye, Presentation.Screens.Refused.target), game) {
    init {
        part(WaveText(kit, L(CopyKey.REFUSED_TITLE), 0.15f, C.CORAL, bob = 0.4f, id = "refused_title_header"), at(0f, top - 0.5f))
        val card = part(Panel(kit, 1.66f, 1.2f, 0.14f, C.CREAM, Entrance.Tumble), at(0f, top - 1.45f))
        child(Paragraph(kit, L(CopyKey.REFUSED_BODY), 0.07f, C.INK, 1.44f, id = "refused_body"), at(0f, 0.08f), card.content).show(0.0)
        // The reason, small, for whoever is asked to look at the phone.
        child(Label3D(kit, why, 0.035f, C.DISABLED_INK, maxWidth = 1.44f), at(0f, -0.45f), card.content).show(0.0)
        val go = part(BlockButton(kit, L(CopyKey.REFUSED_START_OVER), "refused_startover_button", BlockButton.Style.DANGER, 1.3f, 0.38f, 0.13f) {
            game.startOver()
        }, at(0f, bottom + 0.4f))
        go.bobs = true
    }
}
