import RealityKit
import SmashCore

/// The match's HUD (spec §16.4) on the camera-parented rig (ADR 0005), at the top edge, clear of
/// the pitch: both teams' short codes on their kit colours, the score and the clock as flip digits,
/// the period as three pips (or OT), and a pause button in the corner. Goals flip the score and
/// wobble the board; banners pop in the middle. A drill shows its goals of the target and the
/// clock (§10). It runs on real time, so §8.6's slow motion leaves it at full speed. The twin of
/// Android's MatchHud.kt.
@MainActor
final class MatchHud: Screen {
    private let plan: MatchPlan
    private let drillGoals: Int?
    private var board: Panel!
    private var scores: [FlipDigits?] = [nil, nil]
    private var shownScore = [0, 0]
    private var clock: FlipDigits!
    private var pips: [ModelEntity] = []
    private var overtime: Label3D?
    private var pause: BlockButton!
    private var pausePanel: Panel!
    private var pauseParts: [Presentable] = []
    private var banner: WaveText?
    private var shownOvertime = false
    private var shownPeriod = 1

    init(game: Game, plan: MatchPlan, kickoff: Kickoff) {
        self.plan = plan
        drillGoals = kickoff.drillGoals
        super.init(hudOf: game)
        let m = motion
        let b = Self.board
        board = part(Panel(size: [Float(b.boardWidth), 0.38, 0.12], colour: C.board, entrance: .drop, motion: m),
                     at: at(-0.12, top - 0.26))
        if let goals = drillGoals {
            let digits = child(FlipDigits(Scoreboard.drill(scored: 0, target: goals), cardSize: Self.card,
                                          id: "match_goals", label: L(.hudGoals), motion: m),
                               at: at(0, 0, z: 0.05), on: board.content)
            digits.onLanded = { [weak self] in self?.board.thud() }
            digits.show(after: 0)
            scores[0] = digits
        } else {
            for i in 0..<2 {
                let colours = kickoff.colours[i]
                let chip = child(Panel(size: [Self.chip, 0.26, 0.06], colour: Int(colours.primary), entrance: .pop, motion: m),
                                 at: at(i == 0 ? -Float(b.chipX) : Float(b.chipX), 0), on: board.content)
                chip.show(after: 0)
                child(Label3D(kickoff.codes?[i] ?? "", height: 0.085, colour: Int(colours.secondary),
                              maxWidth: Self.chip - 0.04, motion: m), on: chip.content).show(after: 0)
            }
            for side in 0..<2 { scores[side] = makeScore(side, Scoreboard.score(0)) }
            child(Label3D(":", height: 0.12, colour: C.cardInk, motion: m), on: board.content).show(after: 0)
        }
        let seconds = kickoff.match.snapshot.clock
        // The clock's cards are silent: only the last five seconds of a period are counted down
        // audibly (§8.5), and a clack a second reads as a tick that never stops.
        clock = part(FlipDigits(Names.clock(seconds), cardSize: [0.11, 0.15], id: "match_clock", label: L(.matchClock),
                                entrance: .drop, face: .clock, motion: m), at: at(-0.12, top - 0.6))
        if drillGoals == nil {
            let holder = part(Panel(size: [0.36, 0.13, 0.05], colour: C.board, entrance: .drop, motion: m),
                              at: at(0.34, top - 0.6))
            for i in 0..<Tuning.Match.periods {
                let pip = Blocks.slab([0.07, 0.07, 0.03], i == 0 ? C.sun : C.disabledShade, corner: 0.02)
                pip.position = [Float(i - 1) * 0.1, 0, 0.01]
                holder.content.addChild(pip)
                pips.append(pip)
            }
            // In overtime "OT" takes the clock's place (§16.4).
            overtime = child(Label3D(L(.hudOt), height: 0.11, colour: C.pink, entrance: .pop, motion: m),
                             at: at(-0.12, top - 0.6, z: 0.06), on: layer)
        }
        pause = part(BlockButton("", id: "match_pause_button", label: L(.hudPause), style: .quiet, size: [0.26, 0.26], textHeight: 0.11,
                                 glyph: .pause, entrance: .pop, motion: m) { [weak game] in game?.pause(true) },
                     at: at(0.72, top - 0.26))
        buildPausePanel(plan.isSeason)
    }

    /// The board's measures (§16.4), derived once from one card so both apps lay it out the same:
    /// two cards a side, a colon between them, a team chip outside each.
    static let card = SIMD2<Float>(0.14, 0.20)
    static let chip: Float = 0.30
    static let board = Scoreboard.metrics(card: Double(card.x), gap: Double(card.x) * 0.08,
                                          colon: 0.084, chip: Double(chip), margin: 0.03)

    private func makeScore(_ side: Int, _ text: String) -> FlipDigits {
        let x = Float(Self.board.scoreX)
        let d = child(FlipDigits(text, cardSize: Self.card, id: side == 0 ? "match_home_score" : "match_away_score",
                                 label: L(side == 0 ? .matchScoreHome : .matchScoreAway), motion: motion),
                      at: at(side == 0 ? -x : x, 0, z: 0.05), on: board.content)
        d.onLanded = { [weak self] in self?.board.thud() }
        d.show(after: 0)
        return d
    }

    private func buildPausePanel(_ season: Bool) {
        let m = motion
        let height: Float = season ? 1.3 : 1.1
        pausePanel = child(Panel(size: [1.4, height, 0.12], colour: C.paper, entrance: .tumble, motion: m),
                           at: at(0, 0, z: 0.4), on: layer)
        let y0 = height / 2
        child(Label3D(L(.pauseTitle), height: 0.15, colour: C.ink, maxWidth: 1.2, motion: m),
              at: at(0, y0 - 0.2), on: pausePanel.content).show(after: 0)
        if season {
            child(Label3D(L(.pauseForfeit), height: 0.06, colour: C.pinkInk, maxWidth: 1.25, motion: m),
                  at: at(0, y0 - 0.4), on: pausePanel.content).show(after: 0)
        }
        let resume = child(BlockButton(L(.pauseResume), id: "pause_resume_button", style: .primary, size: [1.0, 0.3],
                                       motion: m) { [weak game] in game?.pause(false) },
                           at: at(0, -height / 2 + 0.58), on: pausePanel.content)
        let quit = child(BlockButton(L(.pauseQuit), id: "pause_quit_button", style: .danger, size: [1.0, 0.3],
                                     motion: m) { [weak game] in game?.quit() },
                         at: at(0, -height / 2 + 0.22), on: pausePanel.content)
        pauseParts = [pausePanel, resume, quit]
    }

    func setPaused(_ on: Bool) {
        if on {
            for (i, p) in pauseParts.enumerated() { p.show(after: Double(i) * motion.staggerSeconds * 2) }
            KitSound.sweep()
        } else {
            for p in pauseParts.reversed() { p.hide(after: 0) }
        }
        pause.isEnabled = !on
    }

    override func leave() {
        for p in pauseParts { p.hide(after: 0) }
        banner?.hide(after: 0)
        overtime?.hide(after: 0)
        super.leave()
    }

    // MARK: what the match says

    func event(_ e: MatchEvent) {
        switch e {
        case .goal(let team, _, _, _):
            board.celebrate(team == 0 ? 1 : 0.5)
        case .end:
            pause.isEnabled = false
        default:
            break
        }
    }

    /// A banner the match raised (§16.4, core `MatchCues`): its words in its style for its seconds.
    func show(_ b: Banner) {
        typealias P = Presentation.Banner
        let (colour, height): (UInt32, Double) = switch b.style {
        case .good: (P.good, P.heightGood)
        case .bad: (P.bad, P.heightBad)
        case .warn: (P.warn, P.heightWarn)
        case .info: (P.info, P.heightInfo)
        }
        raise(L(b.key, arguments: b.args), colour: Int(colour), height: Float(height), seconds: b.seconds, pop: b.style == .good)
    }

    /// A word in the middle of the screen: letters drop in (a good one pops), bob, and hop away.
    private func raise(_ text: String, colour: Int, height: Float, seconds: Double, pop: Bool) {
        if let old = banner {
            old.hide(after: 0)
            stage.after(0.8) { [weak stage] in stage?.remove(under: old.entity) }
        }
        let b = child(WaveText(text, height: height, colour: colour, bob: pop ? 2.5 : 1.5, entrance: pop ? .pop : .drop,
                               id: "match_banner_header", motion: motion),
                      at: at(0, 0.35, z: 0.3, tilt: 0.06), on: layer)
        b.show(after: 0)
        banner = b
        stage.after(seconds) { [weak self, weak b] in
            guard let self, let b, self.banner === b else { return }
            b.hide(after: 0)
            self.stage.after(0.8) { [weak stage = self.stage] in stage?.remove(under: b.entity) }
            self.banner = nil
        }
    }

    // MARK: the frame

    override func update(_ dt: Double) {
        guard game.pitch.plan == plan, let s = game.pitch.snapshot else { return }
        if let goals = drillGoals {
            scores[0]?.set(Scoreboard.drill(scored: s.score[0], target: goals))
        } else {
            // The board always holds two cards a side, so a tenth goal flips the tens card rather
            // than rebuilding anything (§16.4).
            for side in 0..<2 where s.score[side] != shownScore[side] {
                scores[side]?.set(Scoreboard.score(s.score[side]))
                scores[side]?.celebrate()
                shownScore[side] = s.score[side]
            }
        }
        if !s.overtime { clock.set(Names.clock(s.clock)) }
        if s.period != shownPeriod {
            shownPeriod = s.period
            for (i, pip) in pips.enumerated() { Blocks.recolour(pip, i < s.period ? C.sun : C.disabledShade) }
        }
        if s.overtime != shownOvertime {
            shownOvertime = s.overtime
            if s.overtime {
                clock.hide(after: 0)            // "OT" replaces the clock (§16.4)
                overtime?.show(after: 0.25)
            }
        }
    }
}
