package `in`.nann.smashhockey.screens

import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.season.CreatedTeamRules
import `in`.nann.smashhockey.core.season.createTeam
import `in`.nann.smashhockey.core.season.draft
import `in`.nann.smashhockey.core.season.editTeam
import `in`.nann.smashhockey.core.season.startSeason
import `in`.nann.smashhockey.game.Game
import `in`.nann.smashhockey.game.L
import `in`.nann.smashhockey.game.MatchPlan
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.WaveText

/**
 * First launch (spec §16.1, §2.2) — the twin of iOS's TeamScreen.swift: the game opens here, once,
 * until a career exists. There is one way through it — the player creates their team ([TeamForm]):
 * a name, a short code derived from it, a kit and a home world. Confirming starts the career and
 * its first season, saved before the hub appears. Training and quick match are a tap away before
 * the team exists.
 */
class TeamScreen(game: Game, editing: Boolean = false) :
    Screen(Game.pose(Presentation.Screens.Team.eye, Presentation.Screens.Team.target), game) {
    private val confirm: BlockButton
    private val form: TeamForm
    /** Changing the team the career already has, rather than creating one (§16.1, §2.2). */
    private val editing = editing && game.save.career != null

    init {
        part(WaveText(kit, L(CopyKey.TEAM_TITLE), 0.17f, C.PAPER, bob = 0.6f, id = "team_title_header"), at(0f, top - 0.2f))
        part(Label3D(kit, L(if (this.editing) CopyKey.TEAM_EDIT else CopyKey.TEAM_CREATE), 0.06f, C.SUN, maxWidth = 1.72f),
            at(0f, top - 0.42f))

        form = TeamForm(this, top - 0.62f, if (this.editing) game.save.career?.draft else null) { refresh() }

        confirm = part(BlockButton(kit, L(CopyKey.TEAM_CHOOSE), "team_confirm_button", BlockButton.Style.PRIMARY, 1.5f, 0.36f, 0.13f) {
            confirmed()
        }, at(0f, bottom + 0.72f))
        if (this.editing) {
            // Changing the team is a detour from the hub: one way on, one way back (§16.1).
            part(BlockButton(kit, L(CopyKey.COMMON_BACK), "team_cancel_button", BlockButton.Style.QUIET, 0.84f, 0.28f, 0.09f) {
                done()
            }, at(0f, bottom + 0.3f))
        } else {
            part(BlockButton(kit, L(CopyKey.TITLE_TRAINING), "team_training_button", BlockButton.Style.QUIET, 0.84f, 0.28f, 0.09f) {
                game.go(Game.Place.Training(null))
            }, at(-0.45f, bottom + 0.3f))
            part(BlockButton(kit, L(CopyKey.TITLE_QUICK), "team_quick_button", BlockButton.Style.QUIET, 0.84f, 0.28f, 0.09f) {
                playQuick(game)
            }, at(0.45f, bottom + 0.3f))
        }
        refresh()
    }

    override fun show(after: Double) {
        super.show(after)
        val stagger = motion.staggerSeconds * 1.6
        for ((i, p) in form.parts.withIndex()) p.show(after + 0.2 + i * stagger * 0.5)
    }

    override fun leave() {
        for (p in form.parts) p.hide(0.0)
        super.leave()
    }

    /** The confirm button says what it would do, and can only do it when the draft breaks no rule. */
    private fun refresh() {
        val name = CreatedTeamRules.trimmedName(form.draft.name).uppercase()
        confirm.retitle(if (editing) L(CopyKey.TEAM_SAVE) else if (name.isEmpty()) L(CopyKey.TEAM_CHOOSE) else L(CopyKey.TEAM_CONFIRM, name))
        confirm.isEnabled = CreatedTeamRules.issues(form.draft).isEmpty()
        confirm.bobs = confirm.isEnabled
    }

    /**
     * Starts the career and its first season (§2.2), or writes the changed team (§16.1) — saved
     * before the next screen appears (§15).
     */
    private fun confirmed() {
        val seed = MatchPlan.seed()
        val draft = form.draft
        if (editing) {
            if (game.commit { it.editTeam(draft) }) {
                game.teamChanged()
                done()
            }
        } else if (game.commit { it.createTeam(draft).startSeason(seed) }) {
            game.go(Game.Place.Hub)
        }
    }

    /** Where changing the team leads back to: the season it was changed from, or the title. */
    private fun done() = game.go(if (game.save.season == null) Game.Place.Title else Game.Place.Hub)
}
