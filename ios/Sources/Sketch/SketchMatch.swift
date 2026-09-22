import Foundation
import RealityKit

// THROWAWAY (SMASH-5): the match HUD over a fake match, the result, and the coach's board.

private func at(_ x: Float, _ y: Float, z: Float = 0, tilt: Float = 0) -> Transform {
    Transform(scale: .one, rotation: simd_quatf(angle: tilt, axis: [0, 0, 1]), translation: [x, y, z])
}

/// Match HUD, on the camera-parented rig: the scoreboard with flip-card scores, a flip clock
/// ticking down, a pause button. A fake ball runs at a goal every few seconds; the score flips,
/// the board jellies, GOAL! bounces across. At 0:00, FULL TIME, then the result.
@MainActor
final class SketchMatchScreen: SketchScreen {
    private(set) var pause: BlockButton!
    private(set) var resume: BlockButton!
    private var quit: BlockButton!
    private var board: Panel!
    private var homeScore: FlipDigits!
    private var awayScore: FlipDigits!
    private var clock: FlipDigits!
    private var goalText: WaveText!
    private var fullTime: WaveText!
    private var pausePanel: Panel!
    private var pauseParts: [Presentable] = []
    private let ball: ModelEntity
    private let go: Go
    private var elapsed = 0.0
    private var nextGoal = 0
    private var score = (0, 0)
    private var running = false
    private(set) var paused = false
    var onFinished: ((Int, Int) -> Void)?

    init(stage: UIStage, world: Entity, go: @escaping Go) {
        self.go = go
        ball = Blocks.model(.generateSphere(radius: 0.36), 0xFFFFFF)
        ball.components.set(DynamicLightShadowComponent(castsShadow: true))
        ball.position = [0, 0.36, 0]
        ball.isEnabled = false
        world.addChild(ball)
        super.init(pose: CameraPose(eye: [0, 24, -46], target: [0, 0, 2]), stage: stage)
        let f = stage.hud
        let m = stage.motion
        let C = DesignTokens.Colour.self
        let home = SketchData.clubs[SketchData.player]!, away = SketchData.clubs[SketchData.opponent]!

        board = part(Panel(size: [1.3, 0.38, 0.12], colour: C.board, entrance: .drop, motion: m), on: f.entity)
        board.rest = at(-0.12, f.top - 0.26)
        for (club, x) in [(home, Float(-0.45)), (away, Float(0.45))] {
            let chip = stage.add(Panel(size: [0.34, 0.26, 0.06], colour: club.primary, entrance: .pop, motion: m), to: board.content)
            chip.rest = at(x, 0)
            chip.show(after: 0)
            stage.add(Label3D(club.code, height: 0.085, colour: club.secondary, motion: m), to: chip.content).show(after: 0)
        }
        let cardSize = SIMD2<Float>(0.19, 0.27)
        homeScore = stage.add(FlipDigits("0", cardSize: cardSize, id: "match_home_score", label: L("match.score.home"), motion: m), to: board.content)
        homeScore.rest = at(-0.13, 0, z: 0.05)
        homeScore.show(after: 0)
        awayScore = stage.add(FlipDigits("0", cardSize: cardSize, id: "match_away_score", label: L("match.score.away"), motion: m), to: board.content)
        awayScore.rest = at(0.13, 0, z: 0.05)
        awayScore.show(after: 0)
        stage.add(Label3D(":", height: 0.14, colour: C.cardInk, motion: m), to: board.content).show(after: 0)
        homeScore.onLanded = { [weak self] in self?.board.thud() }
        awayScore.onLanded = { [weak self] in self?.board.thud() }

        clock = part(FlipDigits(clockText(SketchData.matchSeconds), cardSize: [0.11, 0.15], id: "match_clock",
                                label: L("match.clock"), entrance: .drop, motion: m), on: f.entity)
        clock.rest = at(-0.12, f.top - 0.6)

        pause = part(BlockButton("II", id: "match_pause_button", style: .quiet, size: [0.26, 0.26],
                                 textHeight: 0.11, entrance: .pop, motion: m) { [weak self] in self?.setPaused(true) }, on: f.entity)
        pause.rest = at(0.72, f.top - 0.26)

        goalText = WaveText(L("match.goal"), height: 0.36, colour: C.sun, bob: 2, id: "match_goal_header", motion: m)
        stage.add(goalText, to: f.entity)
        goalText.rest = at(0, 0.35, z: 0.3, tilt: 0.08)
        fullTime = WaveText(L("match.fulltime"), height: 0.26, colour: C.cream, id: "match_fulltime_header", motion: m)
        stage.add(fullTime, to: f.entity)
        fullTime.rest = at(0, 0.3, z: 0.3)

        pausePanel = Panel(size: [1.4, 1.1, 0.12], colour: C.cream, entrance: .tumble, motion: m)
        stage.add(pausePanel, to: f.entity)
        pausePanel.rest = at(0, 0, z: 0.4)
        let title = stage.add(Label3D(L("pause.title"), height: 0.15, colour: C.ink, maxWidth: 1.2, motion: m), to: pausePanel.content)
        title.rest = at(0, 0.34)
        title.show(after: 0)
        resume = stage.add(BlockButton(L("pause.resume"), id: "pause_resume_button", style: .primary, size: [1.0, 0.3],
                                       motion: m) { [weak self] in self?.setPaused(false) }, to: pausePanel.content)
        resume.rest = at(0, 0.02)
        quit = stage.add(BlockButton(L("pause.quit"), id: "pause_quit_button", style: .danger, size: [1.0, 0.3],
                                     motion: m) { [weak self] in self?.quitMatch() }, to: pausePanel.content)
        quit.rest = at(0, -0.34)
        pauseParts = [pausePanel, resume, quit]
    }

    private func clockText(_ remaining: Double) -> String {
        let s = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    override func show(after delay: Double) {
        super.show(after: delay)
        elapsed = 0
        nextGoal = 0
        score = (0, 0)
        homeScore.set("0")
        awayScore.set("0")
        clock.set(clockText(SketchData.matchSeconds))
        paused = false
        ball.position = [0, 0.36, 0]
        ball.isEnabled = true
        stage.after(delay + 0.8) { [weak self] in self?.running = true }
    }

    override func hide() {
        super.hide()
        for p in pauseParts { p.hide(after: 0) }
        goalText.hide(after: 0)
        fullTime.hide(after: 0)
        running = false
        stage.after(0.4) { [weak self] in self?.ball.isEnabled = false }
    }

    func setPaused(_ p: Bool) {
        guard running || paused else { return }
        paused = p
        if p {
            for (i, part) in pauseParts.enumerated() { part.show(after: Double(i) * stage.motion.staggerSeconds * 2) }
        } else {
            for part in pauseParts.reversed() { part.hide(after: 0) }
        }
        pause.isEnabled = !p
    }

    private func quitMatch() {
        paused = false
        running = false
        pause.isEnabled = true
        go(.hub)
    }

    override func update(_ dt: Double) {
        guard running, !paused else { return }
        elapsed += dt
        clock.set(clockText(max(0, SketchData.matchSeconds - elapsed)))
        moveBall()
        if nextGoal < SketchData.goals.count, elapsed >= SketchData.goals[nextGoal].at {
            scored(home: SketchData.goals[nextGoal].home)
            nextGoal += 1
        }
        if elapsed >= SketchData.matchSeconds {
            running = false
            fullTime.show(after: 0)
            pause.isEnabled = false
            stage.after(1.8) { [weak self] in
                guard let self else { return }
                self.pause.isEnabled = true
                self.onFinished?(self.score.0, self.score.1)
            }
        }
    }

    /// The fake ball: a wiggly run from the centre spot into the scoring goal over the four
    /// seconds before each goal; otherwise it idles on the spot.
    private func moveBall() {
        guard nextGoal < SketchData.goals.count else { ball.position = [0, 0.36, 0]; return }
        let g = SketchData.goals[nextGoal]
        let u = Float(max(0, min(1, (elapsed - (g.at - 4)) / 4)))
        let side: Float = g.home ? 1 : -1
        let x = sin(u * .pi * 2.5) * 7 * (1 - u)
        let z = side * 27 * pow(u, 1.3)
        ball.position = [x, 0.36 + abs(sin(u * .pi * 6)) * 0.4 * (1 - u), z]
    }

    private func scored(home: Bool) {
        if home { score.0 += 1 } else { score.1 += 1 }
        homeScore.set("\(score.0)")
        awayScore.set("\(score.1)")
        (home ? homeScore : awayScore)?.celebrate()
        board.celebrate()
        goalText.show(after: 0)
        stage.after(1.5) { [weak self] in self?.goalText.hide(after: 0) }
        stage.after(0.9) { [weak self] in self?.ball.position = [0, 0.36, 0] }
    }
}

/// Result: FULL TIME, a big score slab whose cards flip up from 0:0 to the final score, a WIN
/// badge that pops and jellies, Continue.
@MainActor
final class ResultScreen: SketchScreen {
    private(set) var next: BlockButton!
    private var digits: FlipDigits!
    private var badge: Panel!
    private var badgeLabel: Label3D!
    private var slab: Panel!
    private var finalScore = (0, 0)

    init(stage: UIStage, go: @escaping Go) {
        super.init(pose: CameraPose(eye: [5, 3.2, 12], target: [0, 2.2, 30]), stage: stage)
        let f = stage.frame(at: pose)
        let m = stage.motion
        let C = DesignTokens.Colour.self
        let home = SketchData.clubs[SketchData.player]!, away = SketchData.clubs[SketchData.opponent]!

        let header = part(WaveText(L("match.fulltime"), height: 0.2, colour: C.cream, id: "result_title_header", motion: m), on: f.entity)
        header.rest = at(0, f.top - 0.3)
        slab = part(Panel(size: [1.66, 1.0, 0.18], colour: C.sun, entrance: .tumble, motion: m), on: f.entity)
        slab.rest = at(0, f.top - 1.05, tilt: 0.03)
        for (club, x) in [(home, Float(-0.52)), (away, Float(0.52))] {
            let chip = stage.add(Panel(size: [0.44, 0.2, 0.06], colour: club.primary, entrance: .pop, motion: m), to: slab.content)
            chip.rest = at(x, 0.34)
            chip.show(after: 0)
            stage.add(Label3D(club.code, height: 0.09, colour: club.secondary, motion: m), to: chip.content).show(after: 0)
        }
        digits = stage.add(FlipDigits("0:0", cardSize: [0.32, 0.44], id: "result_score", label: L("result.score"), motion: m), to: slab.content)
        digits.rest = at(0, -0.1, z: 0.06)
        digits.show(after: 0)
        digits.onLanded = { [weak self] in self?.slab.thud() }

        badge = part(Panel(size: [0.62, 0.26, 0.12], colour: C.coral, entrance: .pop, motion: m), on: f.entity)
        badge.rest = at(0.5, f.top - 1.58, z: 0.2, tilt: -0.2)
        badgeLabel = stage.add(Label3D(L("result.win"), height: 0.13, colour: C.cream, maxWidth: 0.52, motion: m), to: badge.content)
        badgeLabel.show(after: 0)

        next = part(BlockButton(L("result.continue"), id: "result_continue_button", style: .primary, size: [1.3, 0.38],
                                textHeight: 0.14, motion: m) { go(.hub) }, on: f.entity)
        next.rest = at(0, f.bottom + 0.4)
        next.bobs = true
    }

    func setScore(_ home: Int, _ away: Int) {
        finalScore = (home, away)
        badgeLabel.set(home > away ? L("result.win") : home < away ? L("result.loss") : L("result.draw"))
    }

    override func show(after delay: Double) {
        digits.set("0:0")
        super.show(after: delay)
        // Count up, one goal at a time, once the slab has landed.
        var steps: [String] = []
        for h in 0...finalScore.0 { steps.append("\(h):0") }
        for a in 0...finalScore.1 where a > 0 { steps.append("\(finalScore.0):\(a)") }
        for (i, s) in steps.dropFirst().enumerated() {
            stage.after(delay + 0.9 + Double(i) * 0.4) { [weak self] in self?.digits.set(s) }
        }
        let landed = delay + 0.9 + Double(steps.count) * 0.4
        stage.after(landed) { [weak self] in
            guard let self else { return }
            self.digits.celebrate()
            self.badge.celebrate(1.2)
            self.slab.celebrate(0.6)
        }
    }
}

/// The coach's board (§12): three of its 0–1 settings on sliders, Reset, Back.
@MainActor
final class CoachScreen: SketchScreen {
    private(set) var sliders: [Slider3D] = []
    private(set) var back: BlockButton!

    init(stage: UIStage, go: @escaping Go) {
        super.init(pose: CameraPose(eye: [19, 8, -8], target: [-3, 2, 12]), stage: stage)
        let f = stage.frame(at: pose)
        let m = stage.motion
        let C = DesignTokens.Colour.self
        let header = part(WaveText(L("coach.title"), height: 0.16, colour: C.cream, bob: 0.6, id: "coach_title_header", motion: m), on: f.entity)
        header.rest = at(0, f.top - 0.25)
        let board = part(Panel(size: [1.76, 1.5, 0.12], colour: C.chalk, entrance: .tumble, motion: m), on: f.entity)
        board.rest = at(0, f.top - 1.3)
        let settings: [(String, String)] = [(L("coach.pressing"), "coach_pressing_field"),
                                            (L("coach.covering"), "coach_covering_field"),
                                            (L("coach.pushup"), "coach_pushup_field")]
        for (i, (title, id)) in settings.enumerated() {
            let s = part(Slider3D(title, id: id, value: 0.55, length: 1.4, entrance: .slide(fromLeft: i % 2 == 0), motion: m),
                         on: board.content)
            s.rest = at(0, 0.42 - Float(i) * 0.42, z: 0.02)
            sliders.append(s)
        }
        let reset = part(BlockButton(L("coach.reset"), id: "coach_reset_button", style: .quiet, size: [0.78, 0.32],
                                     textHeight: 0.1, motion: m) { [weak self] in
            self?.sliders.forEach { $0.set(0.55) }
            board.celebrate(0.4)
        }, on: f.entity)
        reset.rest = at(-0.46, f.bottom + 0.36)
        back = part(BlockButton(L("hub.back"), id: "coach_back_button", style: .primary, size: [0.78, 0.32],
                                textHeight: 0.1, motion: m) { go(.title) }, on: f.entity)
        back.rest = at(0.46, f.bottom + 0.36)
    }
}
