package `in`.nann.smashhockey.screens

import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.season.QuickMatch
import `in`.nann.smashhockey.core.season.isFinished
import `in`.nann.smashhockey.core.season.sideTeam
import `in`.nann.smashhockey.core.season.startSeason
import `in`.nann.smashhockey.game.Game
import `in`.nann.smashhockey.game.L
import `in`.nann.smashhockey.game.MatchPlan
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.Entrance
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Panel
import `in`.nann.smashhockey.ui.WaveText

/**
 * The title (spec §16.2) — the twin of iOS's TitleScreen.swift: the logo drops in letter by letter
 * and keeps bobbing; the season button bobs for the thumb — continue the season, or on to the next
 * once it is over; training, quick match, the coach's board and how to play. The trophy counts
 * when there are any.
 */
class TitleScreen(game: Game) :
    Screen(Game.pose(Presentation.Screens.Title.eye, Presentation.Screens.Title.target), game) {
    private val badge: Panel

    init {
        part(WaveText(kit, L(CopyKey.TITLE_LOGO_TOP), 0.36f, C.SUN, id = "title_logo_header"), at(0f, top - 0.45f, tilt = 0.05f))
        part(WaveText(kit, L(CopyKey.TITLE_LOGO_BOTTOM), 0.30f, C.CREAM, bob = 0.7f, id = "title_logo2_header"),
            at(-0.05f, top - 0.90f, tilt = 0.05f))
        badge = part(Panel(kit, 0.42f, 0.30f, 0.12f, C.CORAL, Entrance.Pop), at(0.62f, top - 1.22f, z = 0.05f, tilt = -0.22f))
        child(Label3D(kit, "3D", 0.16f, C.CREAM), parent = badge.content).show(0.0)
        // The buttons stand on the bottom edge; the tagline and the trophies ride just above them.
        val y0 = bottom + 0.3f
        part(Label3D(kit, L(CopyKey.TITLE_TAGLINE), S.TEXT_SMALL, C.INK, maxWidth = 1.7f, entrance = Entrance.Tumble),
            at(0f, y0 + 1.78f))
        val c = game.save.career
        if (c != null && c.leagueTitles + c.cups > 0) {
            part(Label3D(kit, L(CopyKey.TITLE_TROPHIES, c.leagueTitles, c.cups), S.TEXT_SMALL, C.SUN, maxWidth = 1.6f,
                entrance = Entrance.Pop), at(0f, y0 + 1.6f))
        }
        val over = game.save.season?.isFinished ?: true
        val season = part(BlockButton(kit, L(if (over) CopyKey.TITLE_NEXT_SEASON else CopyKey.TITLE_CONTINUE), "title_season_button",
            BlockButton.Style.PRIMARY, 1.5f, 0.4f, 0.14f) {
            val seed = MatchPlan.seed()
            if (game.save.season == null) game.commit { it.startSeason(seed) }
            game.go(Game.Place.Hub)
        }, at(0f, y0 + 1.2f))
        season.bobs = true
        part(BlockButton(kit, L(CopyKey.TITLE_TRAINING), "title_training_button", BlockButton.Style.SECONDARY, 1.5f, 0.32f) {
            game.go(Game.Place.Training(null))
        }, at(0f, y0 + 0.78f))
        part(BlockButton(kit, L(CopyKey.TITLE_QUICK), "title_quick_button", BlockButton.Style.SECONDARY, 1.5f, 0.32f) {
            playQuick(game)
        }, at(0f, y0 + 0.4f))
        part(BlockButton(kit, L(CopyKey.TITLE_COACH), "title_coach_button", BlockButton.Style.QUIET, 0.72f, 0.3f, 0.1f) {
            game.go(Game.Place.Coach)
        }, at(-0.39f, y0))
        part(BlockButton(kit, L(CopyKey.TITLE_HELP), "title_help_button", BlockButton.Style.QUIET, 0.72f, 0.3f, 0.1f) {
            game.go(Game.Place.Help)
        }, at(0.39f, y0))
    }

    override fun show(after: Double) {
        super.show(after)
        stage.after(after + 1.0) { badge.celebrate(0.8) }
    }
}

/** A quick match (§11.5): opponent and world drawn from a stream of its own, seeded now. */
fun playQuick(game: Game) = game.play(MatchPlan.Quick(QuickMatch.draw(MatchPlan.seed(), game.save.sideTeam)))
