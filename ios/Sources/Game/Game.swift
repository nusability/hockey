import Foundation
import Observation
import RealityKit
import SmashCore
import UIKit
import os

/// The whole game on one stage (spec §15, §16): one RealityKit scene with one camera and one clock
/// (ADR 0005), the pitch with the demo or the player's match on it, the 3D UI's screens standing
/// around it, and the save. Every screen change is a camera move; every recorded result, career
/// change and board change is written to the device before the next screen appears. The twin of
/// Android's Game.kt.
@MainActor
final class Game {
    /// Where the player can be. Each is a screen of §16.
    enum Place: Equatable {
        case refused(String)
        /// Creating the team, or changing it later (§16.1, §2.2).
        case team(editing: Bool)
        case title
        case hub
        /// A team's detail off the league table — its own screen (§16.3a).
        case detail(TeamKey)
        case training(intro: Drill?)
        case coach
        case help
        case result(Outcome)
    }

    let root = Entity()
    let stage: UIStage
    let pitch: Pitch
    let keyboard = Keyboard()
    private let store: SaveStore
    /// The sounds and haptics (§8.8).
    private let feedback: Feedback
    private(set) var save: SaveRecord
    private var screen: Screen?
    private var hud: MatchHud?
    /// The player's match in progress — nil while the demo plays.
    private(set) var playing: MatchPlan?
    /// The league table before the player's latest result, for the hub's reshuffle (§16.3).
    var tableBefore: [SmashCore.TableRow]?
    private var demoRound = 0
    /// The demo is on the pitch, or on its way there.
    private var demoOn = false
    private var place: Place?
    private var opened = false
    /// A board change not yet on the device — written at the end of the frame it happened in.
    private var boardDirty = false
    private let log = Logger(subsystem: "in.nann.smashhockey", category: "game")

    var reduceMotion = false {
        didSet {
            stage.reduceMotion = reduceMotion
            pitch.reduceMotion = reduceMotion
        }
    }

    private init(stage: UIStage, pitch: Pitch, store: SaveStore, save: SaveRecord, feedback: Feedback) {
        self.stage = stage
        self.pitch = pitch
        self.store = store
        self.save = save
        self.feedback = feedback
        root.addChild(pitch.root)
        root.addChild(stage.root)
        pitch.onEvent = { [weak self] e in self?.matchEvent(e) }
        pitch.onCue = { [weak self] c in self?.cue(c) }
        KitSound.play = { [weak feedback] cue in feedback?.ui(cue) }
    }

    /// Loads what the game draws with, reads the save and opens the first screen: the refusal
    /// (§15), the team choice on a first launch (§16.1), or the title.
    static func make(viewSize: CGSize, insets: UIEdgeInsets, launch: MatchPlan?) async throws -> Game {
        let motion = try MotionTokens.load()
        try TextMesh.registerFont()
        let materials = try await Materials.load()
        // The UI blocks are toon-shaded under the UI's own light (design.json), not the light of the
        // world standing behind them: a menu looks the same everywhere and a white slab stays white.
        Blocks.light(with: materials, look: DesignTokens.look)
        let stage = UIStage(pose: CameraPose(Presentation.Screens.Refused.eye, Presentation.Screens.Refused.target),
                            viewSize: viewSize, insets: insets, motion: motion)
        let pitch = try Pitch(materials: materials, feel: try await FeelMaterials.load())
        pitch.aspect = viewSize.width / max(viewSize.height, 1)
        let feedback = Feedback(audio: try Audio())
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let store = SaveStore(directory: directory)
        let loaded = store.load()
        let save: SaveRecord
        switch loaded {
        case .new(let s), .loaded(let s): save = s
        case .refused: save = .fresh
        }
        let game = Game(stage: stage, pitch: pitch, store: store, save: save, feedback: feedback)
        if case .refused(let why) = loaded {
            game.log.error("save refused: \(why, privacy: .public)")
            game.go(.refused(why))
        } else if let launch {
            game.go(game.home)
            game.play(launch)
        } else {
            game.go(game.home)
        }
        return game
    }

    /// The menu the game comes back to: the title, or the team choice until there is a career.
    var home: Place { save.career == nil ? .team(editing: false) : .title }

    // MARK: - Screens

    /// The one way between screens: the old one's parts hop away, the camera swoops, the new
    /// one's parts tumble in as it arrives. The demo plays behind every menu (§9).
    func go(_ next: Place) {
        flush()
        keyboard.end()
        let first = !opened
        opened = true
        place = next
        screen?.leave()
        let s = build(next)
        screen = s
        stage.rig.swoop(to: s.pose, roll: first ? 0 : 0.12)
        s.show(after: first ? 0.9 : 0.45)
        if playing != nil { endMatch() }
        // Leaving a match (even one whose world is still loading) puts the demo back on.
        if !demoOn { startDemo() }
        log.info("screen \(String(describing: next), privacy: .public)")
    }

    private func build(_ place: Place) -> Screen {
        switch place {
        case .refused(let why): RefusedScreen(game: self, why: why)
        case .team(let editing): TeamScreen(game: self, editing: editing)
        case .title: TitleScreen(game: self)
        case .hub: HubScreen(game: self)
        case .detail(let team): DetailScreen(game: self, team: team)
        case .training(let intro): TrainingScreen(game: self, intro: intro)
        case .coach: CoachScreen(game: self)
        case .help: HelpScreen(game: self)
        case .result(let outcome): ResultScreen(game: self, outcome: outcome)
        }
    }

    // MARK: - The save (§15)

    /// Changes the save and writes it before anything else happens. A change the core refuses is
    /// logged and dropped — the screens only offer what the rules allow.
    @discardableResult
    func commit(_ change: (inout SaveRecord) throws -> Void) -> Bool {
        var next = save
        do {
            try change(&next)
        } catch {
            log.error("refused change: \(String(describing: error), privacy: .public)")
            return false
        }
        save = next
        write()
        return true
    }

    /// A change on the coach's board (§12): taken at once, written by the end of the frame — a
    /// dragged slider changes many times a second, the file once per frame at most (§15).
    func setBoard(_ board: BoardRecord) {
        var next = save
        do { try next.setBoard(board) } catch {
            log.error("refused board: \(String(describing: error), privacy: .public)")
            return
        }
        save = next
        boardDirty = true
    }

    private func flush() {
        guard boardDirty else { return }
        boardDirty = false
        write()
    }

    private func write() {
        boardDirty = false
        do { try store.write(save) } catch {
            log.fault("the save could not be written: \(error, privacy: .public)")
        }
    }

    /// The player's team was changed (§2.2, §16.1): the demo behind the menus is started again on
    /// the next screen, so the new kit is worn at once wherever the team is drawn.
    func teamChanged() { demoOn = false }

    /// The refusal's one way on (§15): the refused file moved aside, untouched; a new one begun.
    func startOver() {
        do {
            save = try store.replaceRefused().record
        } catch {
            log.fault("starting over failed: \(error, privacy: .public)")
            return
        }
        go(.team(editing: false))
    }

    // MARK: - The match

    /// Starts `plan` — one tap from the menu to the face-off (A2). The camera swoops onto the
    /// match camera; the HUD drops in.
    func play(_ plan: MatchPlan) {
        flush()
        guard let kickoff = plan.kickoff(save, seed: MatchPlan.seed()) else { return }
        keyboard.end()
        screen?.leave()
        screen = nil
        place = nil
        hud?.leave()
        playing = plan
        demoOn = false
        let hud = MatchHud(game: self, plan: plan, kickoff: kickoff)
        self.hud = hud
        hud.show(after: 0.5)
        feedback.audio.sport = kickoff.world.sport
        feedback.stadium(true)
        pitch.start(plan, kickoff)
        stage.rig.track { [weak self] in self?.pitch.pose ?? (CameraPose(eye: .zero, target: [0, 0, 1]), 50) }
    }

    /// The pause button, and the app leaving the foreground (§8.7).
    func pause(_ on: Bool) {
        guard playing != nil, pitch.plan == playing else { return }
        pitch.paused = on
        hud?.setPaused(on)
    }

    /// Quit from the pause panel (§8.7): a season match is forfeited 0–3 (the panel said so);
    /// anything else just leaves.
    func quit() {
        guard let plan = playing else { return }
        switch plan {
        case .season:
            if let c = save.career { tableBefore = save.season?.table(c) }
            commit { _ = try $0.forfeit() }
            go(.hub)
        case .drill(let d):
            go(.training(intro: d))
        default:
            go(home)
        }
    }

    private func endMatch() {
        hud?.leave()
        hud = nil
        playing = nil
        pitch.paused = false
        feedback.cancelMatchCues()
        feedback.stadium(false)
    }

    /// What the player's match set off beyond the pitch (§8.8, §16.4): banners to the HUD, the
    /// sounds and haptics to the feedback.
    private func cue(_ c: Cue) {
        guard playing != nil, pitch.plan == playing else { return }
        if case .banner(let b) = c { hud?.show(b) } else { feedback.perform(c) }
    }

    private func matchEvent(_ e: MatchEvent) {
        guard let plan = playing, pitch.plan == plan else {
            return
        }
        hud?.event(e)
        if let s = pitch.snapshot { feedback.hear(e, s) }
        guard case .end(let result) = e, let s = pitch.snapshot else { return }
        let outcome = Outcome(plan: plan, score: s.score, overtime: s.overtime, result: result,
                              codes: pitch.kickoff?.codes, names: pitch.kickoff?.sideNames,
                              colours: pitch.kickoff?.colours ?? [], drillGoals: pitch.kickoff?.drillGoals)
        // Recorded now, before anything else can happen (§15); shown once the banner has had its moment.
        switch plan {
        case .season:
            if let c = save.career { tableBefore = save.season?.table(c) }
            commit { try $0.recordPlayed(goalsFor: s.score[0], goalsAgainst: s.score[1], overtime: s.overtime) }
        case .drill(let d) where result == .won: commit { $0.won(d) }
        default: break
        }
        stage.after(Presentation.Screens.resultDelay) { [weak self] in
            guard let self, self.playing == plan else { return }
            self.go(.result(outcome))
        }
    }

    /// The demo behind the menus (§9): the player's team against a random club, in the worlds in
    /// turn — starting from whichever world stands, so a menu never waits for a load.
    private func startDemo() {
        if let shown = pitch.worldShown, let i = World.allCases.firstIndex(of: shown) {
            demoRound = demoRound - demoRound % World.allCases.count + i
        }
        let plan = MatchPlan.demo(round: demoRound, save: save)
        guard let kickoff = plan.kickoff(save, seed: MatchPlan.seed()) else { return }
        demoOn = true
        pitch.start(plan, kickoff)
    }

    // MARK: - The frame, the one clock (ADR 0005)

    func update(_ dt: Double) {
        let step = min(max(dt, 0), 0.1)
        pitch.update(dt)
        feedback.menuMusic(playing == nil)
        feedback.update(step, timeScale: pitch.timeScale, match: pitch.atmosphere)
        if demoOn, !pitch.isLoading, case .demo(let round, _)? = pitch.plan, pitch.endedFor > Presentation.Screens.demoRest {
            demoRound = round + 1
            let plan = MatchPlan.demo(round: demoRound, save: save)
            if let k = plan.kickoff(save, seed: MatchPlan.seed()) { pitch.start(plan, k) }
        }
        screen?.update(step)
        hud?.update(step)
        stage.update(step)
        flush()
    }

    // MARK: - Touches

    /// Whether the UI takes a finger landing at `point`. A finger the UI does not take is the
    /// match's (§5.3) — while the player's match runs and is not paused.
    func touchDown(at point: CGPoint) -> Bool { stage.touchDown(at: point) }

    var pitchTakesFingers: Bool { playing != nil && pitch.plan == playing && !pitch.paused }

    func finger(down: Bool, touchTime: Double) {
        pitch.hold(down, touchTime: touchTime)
    }
}

/// How a match or drill ended, for the result screen (§16.5).
struct Outcome: Equatable {
    let plan: MatchPlan
    let score: [Int]
    let overtime: Bool
    let result: MatchResult
    let codes: [String]?
    /// The two sides' full names, home first — shown under the codes (§16.5); nil in a drill.
    let names: [String]?
    let colours: [TeamColours]
    let drillGoals: Int?
}

/// The system keyboard for the create screen's name and code (§16.1): what is being typed, into
/// which field, read by the hidden text field of the SwiftUI layer.
@MainActor @Observable
final class Keyboard {
    enum Field: Equatable { case name, code }
    private(set) var field: Field?
    var text = "" {
        didSet { if field != nil, text != oldValue { onChange?(text) } }
    }
    @ObservationIgnored private var onChange: ((String) -> Void)?
    @ObservationIgnored private var onEnd: (() -> Void)?

    func begin(_ field: Field, text: String, onChange: @escaping (String) -> Void, onEnd: @escaping () -> Void) {
        let previous = self.onEnd
        self.onChange = nil
        self.onEnd = nil
        previous?()
        self.text = text
        self.onChange = onChange
        self.onEnd = onEnd
        self.field = field
    }

    /// Typing is over (done, the keyboard dismissed, or the screen left).
    func end() {
        guard field != nil else { return }
        field = nil
        onChange = nil
        let done = onEnd
        onEnd = nil
        done?()
    }
}
