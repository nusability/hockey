import RealityKit
import SmashCore

/// First launch (spec §16.1, §2.2): the game opens here, once, until a career exists. Two ways —
/// pick one of the eight clubs from its card (name, kit, home world, strength), or create a team
/// (`TeamForm`). Confirming starts the career and its first season, saved before the hub appears.
/// Training and quick match are a tap away without choosing. The twin of Android's TeamScreen.kt.
@MainActor
final class TeamScreen: Screen {
    private var pickTab: Tile!
    private var createTab: Tile!
    private var confirm: BlockButton!
    private var cards: [Club: Tile] = [:]
    private var pickParts: [Presentable] = []
    private var form: TeamForm!
    private var creating = false
    private var picked: Club?

    init(game: Game) {
        super.init(pose: CameraPose(Presentation.Screens.Team.eye, Presentation.Screens.Team.target), game: game)
        let m = motion
        part(WaveText(L(.teamTitle), height: 0.17, colour: C.paper, bob: 0.6, id: "team_title_header", motion: m),
             at: at(0, top - 0.2))
        pickTab = part(tab(L(.teamPick), id: "team_pick_button") { [weak self] in self?.switchTo(creating: false) },
                       at: at(-0.45, top - 0.52))
        createTab = part(tab(L(.teamCreate), id: "team_create_button") { [weak self] in self?.switchTo(creating: true) },
                         at: at(0.45, top - 0.52))
        pickTab.isSelected = true

        // The content fills what the tabs and the buttons leave.
        let contentTop = top - 0.72, contentBottom = bottom + 0.98
        let pitch = min(0.46, (contentTop - contentBottom) / 4)
        for (i, club) in Club.allCases.enumerated() {
            let x: Float = i % 2 == 0 ? -0.45 : 0.45
            let y = contentTop - pitch * (Float(i / 2) + 0.5)
            let card = child(clubCard(club, height: pitch - 0.05), at: at(x, y), on: layer)
            cards[club] = card
            pickParts.append(card)
        }
        form = TeamForm(screen: self, top: contentTop) { [weak self] in self?.refresh() }

        confirm = part(BlockButton(L(.teamChoose), id: "team_confirm_button", style: .primary, size: [1.5, 0.36],
                                   textHeight: 0.13, motion: m) { [weak self] in self?.confirmed() },
                       at: at(0, bottom + 0.72))
        part(BlockButton(L(.titleTraining), id: "team_training_button", style: .quiet, size: [0.84, 0.28], textHeight: 0.09,
                         motion: m) { [weak game] in game?.go(.training(intro: nil)) }, at: at(-0.45, bottom + 0.3))
        part(BlockButton(L(.titleQuick), id: "team_quick_button", style: .quiet, size: [0.84, 0.28], textHeight: 0.09,
                         motion: m) { [weak game] in game?.playQuick() }, at: at(0.45, bottom + 0.3))
        refresh()
    }

    private func tab(_ title: String, id: String, action: @escaping () -> Void) -> Tile {
        let t = Tile(size: [0.86, 0.26], colour: C.paper, selectedColour: C.green, id: id, label: title, motion: motion,
                     action: action)
        letters(title, height: 0.075, colour: C.ink, maxWidth: 0.76, at: [0, 0, 0], on: t.content)
        return t
    }

    /// A club's card: its kit with the short code, its name, its home world and its strength.
    private func clubCard(_ club: Club, height h: Float) -> Tile {
        let label = "\(L(club.nameKey)), \(L(club.world.nameKey)), \(L(.teamStrength, club.rating))"
        let card = Tile(size: [0.86, h], colour: C.paper, id: "team_club_\(club.rawValue)_button", label: label,
                        motion: motion) { [weak self] in self?.pick(club) }
        let chip = Blocks.slab([0.24, min(0.3, h * 0.72), 0.05], Int(club.primary), corner: 0.03)
        chip.position = [-0.28, 0, 0.02]
        let stripe = Blocks.slab([0.05, min(0.3, h * 0.72) + 0.005, 0.055], Int(club.secondary), corner: 0.005)
        stripe.position = [-0.36, 0, 0.022]
        card.content.addChild(chip)
        card.content.addChild(stripe)
        letters(club.short, height: 0.07, colour: Int(club.secondary), maxWidth: 0.16, at: [-0.26, 0, 0.05], on: card.content)
        letters(Names.team(TeamKey(club), nil), height: 0.05, colour: C.ink, maxWidth: 0.5, align: .leading,
                at: [-0.13, h * 0.2, 0], on: card.content)
        letters(Names.world(club.world), height: 0.034, colour: C.greenInk, maxWidth: 0.5, align: .leading,
                at: [-0.13, 0, 0], on: card.content)
        // Strength: the rating across the clubs' range (§2.1's skill, 60…90).
        let track = Blocks.slab([0.5, 0.035, 0.02], C.paperShade, corner: 0.012)
        track.position = [0.12, -h * 0.24, 0.01]
        let share = Float(min(max(Double(club.rating - 60) / 30, 0.05), 1))
        let fill = Blocks.slab([0.5 * share, 0.045, 0.03], C.pink, corner: 0.015)
        fill.position = [-0.13 + 0.25 * share, -h * 0.24, 0.015]
        card.content.addChild(track)
        card.content.addChild(fill)
        return card
    }

    override func show(after delay: Double) {
        super.show(after: delay)
        let stagger = motion.staggerSeconds * 1.6
        for (i, p) in (creating ? form.parts : pickParts).enumerated() {
            p.show(after: delay + 0.2 + Double(i) * stagger * 0.5)
        }
    }

    override func leave() {
        for p in pickParts + form.parts { p.hide(after: 0) }
        super.leave()
    }

    private func switchTo(creating c: Bool) {
        guard c != creating else { return }
        creating = c
        pickTab.isSelected = !c
        createTab.isSelected = c
        game.keyboard.end()
        let stagger = motion.staggerSeconds
        for (i, p) in (c ? pickParts : form.parts).enumerated() { p.hide(after: Double(i) * stagger * 0.3) }
        for (i, p) in (c ? form.parts : pickParts).enumerated() { p.show(after: 0.25 + Double(i) * stagger * 0.6) }
        refresh()
    }

    private func pick(_ club: Club) {
        picked = club
        for (c, card) in cards { card.isSelected = c == club }
        refresh()
    }

    /// The confirm button says what it would do, and can only do it when the choice is valid.
    private func refresh() {
        if creating {
            let issues = CreatedTeamRules.issues(form.draft)
            let name = CreatedTeamRules.trimmedName(form.draft.name).uppercased()
            confirm.retitle(L(.teamConfirm, name.isEmpty ? form.draft.short : name))
            confirm.isEnabled = issues.isEmpty
        } else if let picked {
            confirm.retitle(L(.teamConfirm, Names.team(TeamKey(picked), nil)))
            confirm.isEnabled = true
        } else {
            confirm.retitle(L(.teamChoose))
            confirm.isEnabled = false
        }
        confirm.bobs = confirm.isEnabled
    }

    /// Starts the career and its first season (§2.2), saved before the hub appears (§15).
    private func confirmed() {
        let seed = MatchPlan.seed()
        let ok: Bool
        if creating {
            let draft = form.draft
            ok = game.commit { try $0.createTeam(draft); try $0.startSeason(seed: seed) }
        } else if let club = picked {
            ok = game.commit { try $0.chooseClub(club); try $0.startSeason(seed: seed) }
        } else {
            ok = false
        }
        if ok { game.go(.hub) }
    }
}
