import RealityKit
import SmashCore

/// The result (spec §16.5): the final score flipping up goal by goal, win, draw or loss, overtime if
/// it happened — and the way on: back to the hub after a season match, Again (one tap, A2) or Training
/// after a failed drill, Next drill once it is won, the menu after a quick match. The result was saved
/// before this screen appeared (§15). The twin of Android's ResultScreen.kt.
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
        part(WaveText(L(header), height: 0.2, colour: C.paper, id: "result_title_header", motion: m), at: at(0, top - 0.3))
        slab = part(Panel(size: [1.66, 1.0, 0.18], colour: C.sun, entrance: .tumble, motion: m), at: at(0, top - 1.05, tilt: 0.03))
        if let goals = outcome.drillGoals {
            digits = child(FlipDigits(Scoreboard.drill(scored: 0, target: goals), cardSize: Self.card,
                                      id: "result_score", label: L(.resultScore), motion: m),
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
            digits = child(FlipDigits(Scoreboard.score(0, 0), cardSize: Self.card, id: "result_score",
                                      label: L(.resultScore), motion: m), at: at(0, -0.1, z: 0.06), on: slab.content)
            let key: CopyKey = won ? .resultWin : outcome.result == .lost ? .resultLoss : .resultDraw
            let b = part(Panel(size: [0.62, 0.26, 0.12], colour: won ? C.pink : C.green, entrance: .pop, motion: m),
                         at: at(0.5, top - 1.58, z: 0.2, tilt: -0.2))
            child(Label3D(L(key), height: 0.1, colour: C.ink, maxWidth: 0.54, motion: m), on: b.content).show(after: 0)
            badge = b
        }
        digits.show(after: 0)
        digits.onLanded = { [weak self] in self?.slab.thud() }
        if outcome.overtime {
            part(Label3D(L(.resultOt), height: 0.07, colour: C.paper, maxWidth: 1.5, motion: m), at: at(0, top - 1.8))
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
            // A failed drill: again in one tap (A2), or back to the drills.
            next = BlockButton(L(.resultAgain), id: "result_again_button", style: .primary, size: [1.3, 0.38],
                               textHeight: 0.14, motion: m) { [weak game] in game?.play(.drill(d)) }
            part(BlockButton(L(.trainingTitle), id: "result_training_button", style: .quiet, size: [1.0, 0.3],
                             textHeight: 0.1, motion: m) { [weak game] in game?.go(.training(intro: nil)) },
                 at: at(0, bottom + 0.9))
        default:
            next = BlockButton(L(.resultTitle), id: "result_title_button", style: .primary, size: [1.3, 0.38],
                               textHeight: 0.14, motion: m) { [weak game] in game.map { $0.go($0.home) } }
        }
        next.bobs = true
        part(next, at: at(0, bottom + 0.4))
    }

    /// The final score's shape with every digit a zero — where the count starts.
    /// Two cards a side, so 0:0 and 12:11 stand in the same place (§16.4).
    static let card = SIMD2<Float>(0.26, 0.36)

    override func show(after delay: Double) {
        super.show(after: delay)
        // Count up, one goal at a time, once the slab has landed.
        let s = outcome.score
        var steps: [String] = []
        if let goals = outcome.drillGoals {
            for g in 0...min(s[0], goals) { steps.append(Scoreboard.drill(scored: g, target: goals)) }
        } else {
            for h in 0...s[0] { steps.append(Scoreboard.score(h, 0)) }
            for a in 0...s[1] where a > 0 { steps.append(Scoreboard.score(s[0], a)) }
            steps.insert(Scoreboard.score(0, 0), at: 0)
        }
        // The ladder runs the same length whether the score is 1:0 or 12:11.
        let tick = min(0.4, 3.6 / Double(max(1, steps.count - 1)))
        for (i, text) in steps.dropFirst().enumerated() {
            stage.after(delay + 0.9 + Double(i) * tick) { [weak self] in self?.digits.set(text) }
        }
        stage.after(delay + 0.9 + Double(steps.count) * tick) { [weak self] in
            guard let self, self.outcome.result == .won else { return }
            self.digits.celebrate()
            self.badge?.celebrate(1.2)
            self.slab.celebrate(0.6)
        }
    }
}
