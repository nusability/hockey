import RealityKit
import SmashCore

/// First launch (spec §16.1, §2.2): the game opens here, once, until a career exists. There is
/// one way through it — the player creates their team (`TeamForm`): a name, a short code derived
/// from it, a kit and a home world. Confirming starts the career and its first season, saved
/// before the hub appears. Training and quick match are a tap away before the team exists.
/// The twin of Android's TeamScreen.kt.
@MainActor
final class TeamScreen: Screen {
    private var confirm: BlockButton!
    private var form: TeamForm!

    init(game: Game) {
        super.init(pose: CameraPose(Presentation.Screens.Team.eye, Presentation.Screens.Team.target), game: game)
        let m = motion
        part(WaveText(L(.teamTitle), height: 0.17, colour: C.paper, bob: 0.6, id: "team_title_header", motion: m),
             at: at(0, top - 0.2))
        part(Label3D(L(.teamCreate), height: 0.06, colour: C.sun, maxWidth: 1.72, motion: m), at: at(0, top - 0.42))

        form = TeamForm(screen: self, top: top - 0.62) { [weak self] in self?.refresh() }

        confirm = part(BlockButton(L(.teamChoose), id: "team_confirm_button", style: .primary, size: [1.5, 0.36],
                                   textHeight: 0.13, motion: m) { [weak self] in self?.confirmed() },
                       at: at(0, bottom + 0.72))
        part(BlockButton(L(.titleTraining), id: "team_training_button", style: .quiet, size: [0.84, 0.28], textHeight: 0.09,
                         motion: m) { [weak game] in game?.go(.training(intro: nil)) }, at: at(-0.45, bottom + 0.3))
        part(BlockButton(L(.titleQuick), id: "team_quick_button", style: .quiet, size: [0.84, 0.28], textHeight: 0.09,
                         motion: m) { [weak game] in game?.playQuick() }, at: at(0.45, bottom + 0.3))
        refresh()
    }

    override func show(after delay: Double) {
        super.show(after: delay)
        let stagger = motion.staggerSeconds * 1.6
        for (i, p) in form.parts.enumerated() { p.show(after: delay + 0.2 + Double(i) * stagger * 0.5) }
    }

    override func leave() {
        for p in form.parts { p.hide(after: 0) }
        super.leave()
    }

    /// The confirm button says what it would do, and can only do it when the draft breaks no rule.
    private func refresh() {
        let name = CreatedTeamRules.trimmedName(form.draft.name).uppercased()
        confirm.retitle(name.isEmpty ? L(.teamChoose) : L(.teamConfirm, name))
        confirm.isEnabled = CreatedTeamRules.issues(form.draft).isEmpty
        confirm.bobs = confirm.isEnabled
    }

    /// Starts the career and its first season (§2.2), saved before the hub appears (§15).
    private func confirmed() {
        let seed = MatchPlan.seed()
        let draft = form.draft
        if game.commit({ try $0.createTeam(draft); try $0.startSeason(seed: seed) }) { game.go(.hub) }
    }
}
