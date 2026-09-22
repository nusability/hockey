import RealityKit
import SmashCore

/// How to play (spec §16.8): the prototype's six lessons, one card at a time, and above them the
/// one-touch control itself — a disk with the ball circling it and an aim line that turns pink at
/// the goal and green at a team-mate. Next tips the card away and the next one up. The twin of
/// Android's HelpScreen.kt.
@MainActor
final class HelpScreen: Screen {
    private static let lessons: [CopyKey] = [.help1, .help2, .help3, .help4, .help5, .help6]
    private var index = 0
    private var card: Panel?
    private var next: BlockButton!

    init(game: Game) {
        super.init(pose: CameraPose(Presentation.Screens.Help.eye, Presentation.Screens.Help.target), game: game)
        let m = motion
        part(WaveText(L(.helpTitle), height: 0.16, colour: C.paper, bob: 0.6, id: "help_title_header", motion: m),
             at: at(0, top - 0.22))
        part(KitDisk(radius: 0.2, primary: Int(Career.demoClub.primary), secondary: Int(Career.demoClub.secondary), ball: true,
                     motion: m), at: at(0, top - 0.95))
        part(BlockButton(L(.commonBack), id: "help_back_button", style: .quiet, size: [0.78, 0.32], textHeight: 0.1, motion: m) {
            [weak game] in game.map { $0.go($0.home) }
        }, at: at(-0.46, bottom + 0.3))
        next = part(BlockButton(L(.helpNext), id: "help_next_button", style: .primary, size: [0.78, 0.32], textHeight: 0.1,
                                motion: m) { [weak self] in self?.advance() }, at: at(0.46, bottom + 0.3))
        next.bobs = true
    }

    override func show(after delay: Double) {
        super.show(after: delay)
        showCard(after: delay + 0.4)
    }

    private func showCard(after delay: Double) {
        let m = motion
        let y = (top - 1.45 + bottom + 0.55) / 2
        let panel = child(Panel(size: [1.66, 1.35, 0.14], colour: C.paper, entrance: .tumble, motion: m),
                          at: at(0, y, tilt: index % 2 == 0 ? 0.02 : -0.02), on: layer)
        child(Label3D("\(index + 1) / \(Self.lessons.count)", height: 0.05, colour: C.greenInk, motion: m),
              at: at(0, 0.54), on: panel.content).show(after: 0)
        child(Paragraph(L(Self.lessons[index]), height: 0.066, colour: C.ink, width: 1.44, id: "help_card", motion: m),
              at: at(0, -0.04), on: panel.content).show(after: 0)
        panel.show(after: delay)
        card = panel
    }

    private func advance() {
        guard index + 1 < Self.lessons.count else {
            game.go(game.home)
            return
        }
        if let old = card {
            old.hide(after: 0)
            stage.after(0.9) { [weak stage] in stage?.remove(under: old.entity) }
        }
        index += 1
        if index + 1 == Self.lessons.count { next.retitle(L(.helpDone)) }
        showCard(after: 0.25)
    }

    override func leave() {
        card?.hide(after: 0)
        super.leave()
    }
}
