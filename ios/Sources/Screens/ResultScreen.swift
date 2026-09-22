import RealityKit
import SmashCore

/// The result (spec §16.5): the final score flipping up goal by goal, win, draw or loss, overtime if
/// it happened — and one button on: back to the hub after a season match, Again after a drill (one
/// tap, A2) or Next drill once it is won, the menu after a quick match. The result was saved before
/// this screen appeared (§15). The twin of Android's ResultScreen.kt.
@MainActor
final class ResultScreen: Screen {
    private let outcome: Outcome
    private var digits: FlipDigits!
    private var slab: Panel!
    private var badge: Panel?

    init(game: Game, outcome: Outcome) {
        self.outcome = outcome
        super.init(pose: CameraPose(Presentation.Screens.Result.eye, Presentation.Screens.Result.target), game: game)
        let m = motion
        let drill = outcome.plan.drill
        let won = outcome.result == .won
        let header: CopyKey = drill == nil ? .resultFulltime : won ? .resultDrillWon : .resultTimeUp
        part(WaveText(L(header), height: 0.2, colour: C.cream, id: "result_title_header", motion: m), at: at(0, top - 0.3))
        slab = part(Panel(size: [1.66, 1.0, 0.18], colour: C.sun, entrance: .tumble, motion: m), at: at(0, top - 1.05, tilt: 0.03))
        let s = outcome.score
        if let goals = outcome.drillGoals {
            digits = child(FlipDigits("0/\(goals)", cardSize: [0.32, 0.44], id: "result_score", label: L(.resultScore), motion: m),
                           at: at(0, -0.02, z: 0.06), on: slab.content)
        } else {
            for (i, x) in [Float(-0.52), 0.52].enumerated() {
                let colours = outcome.colours[i]
                let chip = child(Panel(size: [0.44, 0.2, 0.06], colour: Int(colours.primary), entrance: .pop, motion: m),
                                 at: at(x, 0.34), on: slab.content)
                chip.show(after: 0)
                child(Label3D(outcome.codes?[i] ?? "", height: 0.09, colour: Int(colours.secondary), maxWidth: 0.4, motion: m),
                      on: chip.content).show(after: 0)
            }
            digits = child(FlipDigits(zeroed("\(s[0]):\(s[1])"), cardSize: [0.32, 0.44], id: "result_score",
                                      label: L(.resultScore), motion: m), at: at(0, -0.1, z: 0.06), on: slab.content)
            let key: CopyKey = won ? .resultWin : outcome.result == .lost ? .resultLoss : .resultDraw
            let b = part(Panel(size: [0.62, 0.26, 0.12], colour: won ? C.coral : C.teal, entrance: .pop, motion: m),
                         at: at(0.5, top - 1.58, z: 0.2, tilt: -0.2))
            child(Label3D(L(key), height: 0.1, colour: C.cream, maxWidth: 0.54, motion: m), on: b.content).show(after: 0)
            badge = b
        }
        digits.show(after: 0)
        digits.onLanded = { [weak self] in self?.slab.thud() }
        if outcome.overtime {
            part(Label3D(L(.resultOt), height: 0.07, colour: C.cream, maxWidth: 1.5, motion: m), at: at(0, top - 1.8))
        }

        let next: BlockButton
        switch outcome.plan {
        case .season:
            next = BlockButton(L(.resultHub), id: "result_hub_button", style: .primary, size: [1.3, 0.38], textHeight: 0.13,
                               motion: m) { [weak game] in game?.go(.hub) }
        case .drill(let d) where won:
            let later = Drill.allCases.firstIndex(of: d).map { $0 + 1 }.flatMap { $0 < Drill.allCases.count ? Drill.allCases[$0] : nil }
            if let later {
                next = BlockButton(L(.resultNextDrill), id: "result_next_button", style: .primary, size: [1.3, 0.38],
                                   textHeight: 0.13, motion: m) { [weak game] in game?.go(.training(intro: later)) }
            } else {
                next = BlockButton(L(.resultDrills), id: "result_drills_button", style: .primary, size: [1.3, 0.38],
                                   textHeight: 0.13, motion: m) { [weak game] in game?.go(.training(intro: nil)) }
            }
        case .drill(let d):
            next = BlockButton(L(.resultAgain), id: "result_again_button", style: .primary, size: [1.3, 0.38],
                               textHeight: 0.14, motion: m) { [weak game] in game?.play(.drill(d)) }
        default:
            next = BlockButton(L(.resultTitle), id: "result_title_button", style: .primary, size: [1.3, 0.38],
                               textHeight: 0.14, motion: m) { [weak game] in game.map { $0.go($0.home) } }
        }
        next.bobs = true
        part(next, at: at(0, bottom + 0.4))
    }

    /// The final score's shape with every digit a zero — where the count starts.
    private func zeroed(_ text: String) -> String { String(text.map { $0.isNumber ? "0" : $0 }) }

    override func show(after delay: Double) {
        super.show(after: delay)
        // Count up, one goal at a time, once the slab has landed.
        let s = outcome.score
        var steps: [String] = []
        if let goals = outcome.drillGoals {
            for g in 0...min(s[0], 9) { steps.append("\(g)/\(goals)") }
        } else {
            let final = "\(s[0]):\(s[1])"
            let width = final.count
            func pad(_ h: Int, _ a: Int) -> String {
                let text = "\(h):\(a)"
                return text.count == width ? text : final       // two-digit scores: straight to the final
            }
            for h in 0...s[0] { steps.append(pad(h, 0)) }
            for a in 0...s[1] where a > 0 { steps.append(pad(s[0], a)) }
            steps.insert(zeroed(final), at: 0)
        }
        for (i, text) in steps.dropFirst().enumerated() {
            stage.after(delay + 0.9 + Double(i) * 0.4) { [weak self] in self?.digits.set(text) }
        }
        stage.after(delay + 0.9 + Double(steps.count) * 0.4) { [weak self] in
            guard let self, self.outcome.result == .won else { return }
            self.digits.celebrate()
            self.badge?.celebrate(1.2)
            self.slab.celebrate(0.6)
        }
    }
}
