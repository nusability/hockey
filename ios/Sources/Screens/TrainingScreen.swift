import RealityKit
import SmashCore

/// Training (spec §16.6, §10): the eight drills as cards in order — name, world, goals and time,
/// what opposes, won or locked. A locked card shakes its head. Choosing an open one tips its intro
/// card up — the hint — with Start, which goes straight to the drill's "get ready". The twin of
/// Android's TrainingScreen.kt.
@MainActor
final class TrainingScreen: Screen {
    private var introParts: [Presentable] = []
    private var cards: [Tile] = []
    private var intro: Drill?

    init(game: Game, intro: Drill?) {
        super.init(pose: CameraPose(Presentation.Screens.Training.eye, Presentation.Screens.Training.target), game: game)
        let m = motion
        let save = game.save
        part(WaveText(L(.trainingTitle), height: 0.17, colour: C.cream, bob: 0.6, id: "training_title_header", motion: m),
             at: at(0, top - 0.2))
        let done = Drill.allCases.filter(save.isWon).count
        part(Label3D(L(.trainingProgress, done, Drill.allCases.count), height: S.textSmall, colour: C.sun, maxWidth: 1.6,
                     entrance: .drop, motion: m), at: at(0, top - 0.43))
        let contentTop = top - 0.58, contentBottom = bottom + 0.62
        let pitch = min(0.5, (contentTop - contentBottom) / 4)
        for (i, drill) in Drill.allCases.enumerated() {
            let x: Float = i % 2 == 0 ? -0.45 : 0.45
            let y = contentTop - pitch * (Float(i / 2) + 0.5)
            cards.append(part(card(drill, height: pitch - 0.05, save: save), at: at(x, y)))
        }
        part(BlockButton(L(.commonBack), id: "training_back_button", style: .quiet, size: [0.8, 0.3], textHeight: 0.09,
                         motion: m) { [weak game] in game.map { $0.go($0.home) } }, at: at(0, bottom + 0.3))
        if let intro, save.isOpen(intro) {
            stage.after(0.9) { [weak self] in self?.open(intro) }
        }
    }

    /// What a drill's opponents are (§10): none, a goalie, dummies, or defenders.
    static func opposition(_ d: Drill) -> CopyKey {
        let roles = d.away.map(\.role)
        if roles.isEmpty { return .trainingNone }
        if roles.contains(where: { $0 == .defender || $0 == .forward }) { return .trainingDefenders }
        if roles.contains(.dummy) { return .trainingDummies }
        return .trainingGoalie
    }

    private func card(_ d: Drill, height h: Float, save: SaveRecord) -> Tile {
        let open = save.isOpen(d), won = save.isWon(d)
        let state = won ? L(.trainingWon) : open ? "" : L(.trainingLocked)
        let label = [L(.trainingDrill, d.number), L(d.nameKey), L(d.world.nameKey), state].filter { !$0.isEmpty }.joined(separator: ", ")
        let t = Tile(size: [0.86, h], colour: won ? C.rowDark : C.cream, id: "training_drill_\(d.number)_button", label: label,
                     motion: motion) { [weak self] in self?.open(d) }
        t.isEnabled = open
        let ink = open ? C.ink : C.disabledInk
        letters(L(.trainingDrill, d.number), height: 0.032, colour: open ? C.tealShade : C.disabledInk, align: .leading,
                at: [-0.39, h * 0.3, 0], on: t.content)
        letters(L(d.nameKey).uppercased(), height: 0.05, colour: ink, maxWidth: 0.76, align: .leading, at: [-0.39, h * 0.08, 0],
                on: t.content)
        let facts = "\(Names.world(d.world)) · \(L(.trainingGoalsIn, d.goals, Int(d.seconds)))"
        letters(facts, height: 0.03, colour: ink, maxWidth: 0.76, align: .leading, at: [-0.39, -h * 0.13, 0], on: t.content)
        letters(L(Self.opposition(d)), height: 0.03, colour: open ? C.coralShade : C.disabledInk, maxWidth: 0.5, align: .leading,
                at: [-0.39, -h * 0.3, 0], on: t.content)
        if won || !open {
            let badge = Blocks.slab([0.26, 0.08, 0.03], won ? C.teal : C.disabledShade, corner: 0.03)
            badge.position = [0.27, -h * 0.3, 0.02]
            badge.orientation = simd_quatf(angle: -0.12, axis: [0, 0, 1])
            t.content.addChild(badge)
            letters(state, height: 0.035, colour: C.cream, maxWidth: 0.22, at: [0.27, -h * 0.3, 0.04], on: t.content)
        }
        return t
    }

    /// The intro card (§16.4, §16.6): the drill's name, its hint, and Start.
    private func open(_ d: Drill) {
        guard game.save.isOpen(d) else { return }
        closeIntro()
        intro = d
        for (i, c) in cards.enumerated() {
            c.isSelected = Drill.allCases[i] == d
            c.isEnabled = false                     // the intro stands in front: the cards behind take no taps
        }
        KitSound.sweep()
        let m = motion
        let panel = child(Panel(size: [1.62, 1.5, 0.14], colour: C.cream, entrance: .tumble, motion: m), at: at(0, 0.05, z: 0.5),
                          on: layer)
        var parts: [Presentable] = [panel]
        child(Label3D(L(.trainingDrill, d.number), height: 0.05, colour: C.tealShade, motion: m), at: at(0, 0.6), on: panel.content)
            .show(after: 0)
        child(Label3D(L(d.nameKey).uppercased(), height: 0.11, colour: C.ink, maxWidth: 1.45, motion: m), at: at(0, 0.45),
              on: panel.content).show(after: 0)
        child(Label3D(L(.trainingGoalsIn, d.goals, Int(d.seconds)), height: 0.05, colour: C.coralShade, maxWidth: 1.4, motion: m),
              at: at(0, 0.31), on: panel.content).show(after: 0)
        let hint = child(Paragraph(L(d.hintKey), height: 0.058, colour: C.ink, width: 1.4, id: "training_hint", motion: m),
                         at: at(0, -0.02), on: panel.content)
        hint.show(after: 0)
        let start = child(BlockButton(L(.trainingStart), id: "training_start_button", style: .primary, size: [0.8, 0.32],
                                      textHeight: 0.13, motion: m) { [weak game] in game?.play(.drill(d)) },
                          at: at(0.33, -0.52), on: panel.content)
        start.bobs = true
        let close = child(BlockButton(L(.commonBack), id: "training_close_button", style: .quiet, size: [0.56, 0.28],
                                      textHeight: 0.08, motion: m) { [weak self] in self?.closeIntro() },
                          at: at(-0.46, -0.52), on: panel.content)
        parts += [start, close]
        for (i, p) in parts.enumerated() { p.show(after: Double(i) * motion.staggerSeconds * 3) }
        introParts = parts
    }

    private func closeIntro() {
        guard !introParts.isEmpty, let panel = introParts.first as? Panel else { return }
        for p in introParts.reversed() { p.hide(after: 0) }
        introParts = []
        intro = nil
        for (i, c) in cards.enumerated() {
            c.isSelected = false
            c.isEnabled = game.save.isOpen(Drill.allCases[i])
        }
        stage.after(0.9) { [weak stage] in stage?.remove(under: panel.entity) }
    }

    override func leave() {
        for p in introParts { p.hide(after: 0) }
        super.leave()
    }
}
