/// A banner the match raises (spec §16.4): its copy and arguments, its style and how long it stands.
public struct Banner: Sendable, Hashable {
    public enum Style: String, Sendable, Hashable, CaseIterable {
        /// A goal of ours, a win: popped big in the sun colour.
        case good
        /// A goal against, a loss, a drill interrupted.
        case bad
        /// A dead-ball reset in a match.
        case warn
        /// The intro, periods, a drill's get ready.
        case info
    }

    public let key: CopyKey
    /// The copy's arguments in order (numbers already as text).
    public let args: [String]
    public let style: Style
    /// Real seconds it stands before it leaves.
    public let seconds: Double

    public init(_ key: CopyKey, _ args: [String] = [], style: Style, seconds: Double) {
        self.key = key
        self.args = args
        self.style = style
        self.seconds = seconds
    }
}

/// A haptic the match plays (spec §8.8); intensities 0–1.
public enum Haptic: Sendable, Hashable {
    /// Light: the aim entering a window, a countdown second.
    case tick(Double)
    /// A body blow: a release, the goal horn.
    case impact(Double)
    /// A sharp transient: a steal, a save, a post.
    case sharp(Double)
}

/// Where a save, a steal or a block pops (§8.8).
public enum PopKind: String, Sendable, Hashable, CaseIterable { case save, steal, block }

/// One reaction to what the match did (spec §8.8, §16.4). `delay` is real seconds from now.
public enum Cue: Sendable, Hashable {
    case banner(Banner)
    /// A sound; one made on the pitch carries the ball's `x` across it (it pans there and follows
    /// §8.6's time scale), every other plays at real speed, centred.
    case sound(SoundCue, x: Double?, delay: Double)
    case haptic(Haptic, delay: Double)
    /// A camera shake of this many metres (the prototype's kick, §8.8).
    case shake(Double)
    case pop(PopKind, x: Double, z: Double)
}

/// What the match's events and frames set off — the banners, sounds, haptics, shakes and pops (spec
/// §8.8, §16.4), decided once for both apps. It keeps the little memory the prototype's messages
/// needed (a face-off after a period's end names the period; a drill's get-ready says why), and
/// the countdown's and the aim's last state. The player's matches get everything; the demo behind
/// the menus (§9) only what is seen — the shakes and pops — never a banner, a sound or a haptic.
public struct MatchCues: Sendable {
    public struct Params: Sendable, Hashable {
        public var banner = Seconds()
        public var shakeGoal = 0.0
        public var shakePost = 0.0
        public var hapticWindow = 0.0
        public var releaseLow = 0.0
        public var releaseHigh = 0.0
        public var releaseSlow = 0.0
        public var releaseFast = 0.0
        public var hapticSharp = 0.0
        public var hapticGoal = 0.0
        public var goalPulses: [Double] = []
        public var hapticAgainst = 0.0
        public var hapticTick = 0.0
        public var shotSlow = 0.0
        public var shotFast = 0.0
        public var countdown = 0
        public var stingDelay = 0.0

        /// The banners' durations (presentation.toml [banner]).
        public struct Seconds: Sendable, Hashable {
            public var versus = 0.0, period = 0.0, periodEnd = 0.0, whistle = 0.0
            public var ready = 0.0, lost = 0.0, goal = 0.0, end = 0.0
            public init() {}
        }

        public init() {}
    }

    private let p: Params
    private let isDrill: Bool
    private let audible: Bool
    private var lastFlow: MatchEvent?
    private var lastTick: Int?
    private var aimWindow: MatchSnapshot.Aim?

    /// `drill`: a drill is on the pitch (§10). `audible`: the player's own match, not the demo.
    public init(_ params: Params, drill: Bool, audible: Bool) {
        p = params
        isDrill = drill
        self.audible = audible
    }

    /// The intro banner of a player's match (not a drill): "Home vs Away".
    public func intro(home: String, away: String) -> [Cue] {
        guard audible, !isDrill else { return [] }
        return [.banner(Banner(.eventVersus, [home, away], style: .info, seconds: p.banner.versus))]
    }

    /// What event `e` sets off; `s` is the match as it stands after the tick that emitted it.
    public mutating func hear(_ e: MatchEvent, _ s: MatchSnapshot) -> [Cue] {
        var out: [Cue] = []
        let b = p.banner
        func banner(_ key: CopyKey, _ args: [String] = [], _ style: Banner.Style, _ seconds: Double) {
            out.append(.banner(Banner(key, args, style: style, seconds: seconds)))
        }
        /// A sound; one made on the pitch (the ball's) is at the ball's x — it pans and follows §8.6.
        func sound(_ cue: SoundCue, onPitch: Bool = false, delay: Double = 0) {
            out.append(.sound(cue, x: onPitch ? s.ball.x : nil, delay: delay))
        }
        func haptic(_ h: Haptic, delay: Double = 0) { out.append(.haptic(h, delay: delay)) }
        func mine(_ i: Int) -> Bool { s.players[i].team == 0 && s.players[i].role != .goalie }

        switch e {
        case .goal(let team, _, _, _):
            out.append(.shake(p.shakeGoal))
            sound(.matchWhistleShort)
            sound(.uiConfettiPop)
            if team == 0 {
                banner(.eventGoal, [], .good, b.goal)
                sound(.matchGoalHorn)
                sound(.matchGoalCheer)
                for t in p.goalPulses { haptic(.impact(p.hapticGoal), delay: t) }
            } else {
                banner(.eventGoalAgainst, [], .bad, b.goal)
                sound(.matchGoalAgainst)
                haptic(.impact(p.hapticAgainst))
            }
        case .post:
            out.append(.shake(p.shakePost))
            sound(.matchPost, onPitch: true)
            haptic(.sharp(p.hapticSharp))
        case .board:
            sound(.matchBoard, onPitch: true)
        case .block(let i):
            sound(.matchBlock, onPitch: true)
            out.append(.pop(.block, x: s.players[i].x, z: s.players[i].z))
        case .save(let i):
            sound(.matchSave, onPitch: true)
            haptic(.sharp(p.hapticSharp))
            out.append(.pop(.save, x: s.players[i].x, z: s.players[i].z))
        case .steal(let by, _):
            sound(.matchSteal, onPitch: true)
            haptic(.sharp(p.hapticSharp))
            out.append(.pop(.steal, x: s.players[by].x, z: s.players[by].z))
        case .pickup(let i):
            if s.players[i].team == 0 { sound(.matchReceive, onPitch: true) }
        case .shot(let by, _):
            let speed = Pitch.length(s.ball.vx, s.ball.vz)
            sound(shot(speed), onPitch: true)
            if mine(by) { haptic(.impact(release(speed))) }
        case .pass(let from, _):
            sound(.matchPass, onPitch: true)
            if mine(from) { haptic(.impact(release(Pitch.length(s.ball.vx, s.ball.vz)))) }
        case .play:
            sound(.matchFaceoffDrop, onPitch: true)
        case .whistle:
            banner(.eventReset, [], .warn, b.whistle)
            sound(.matchWhistleShort)
        case .drillInterrupted(let why):
            let key: CopyKey = switch why {
            case .saved: .eventSaved
            case .stolen: .eventStolen
            case .wrongNet: .eventWrongNet
            case .noAssist: .eventPassFirst
            case .deadBall: .eventReset
            }
            banner(key, [], .bad, b.lost)
            sound(.matchWhistleShort)
        case .ready:
            let key: CopyKey = switch lastFlow {
            case .goal?: .eventNiceAgain
            case .drillInterrupted?: .eventAgain
            default: .eventGetReady
            }
            banner(key, [], .info, b.ready)
        case .periodEnd(let period):
            // The third period's end either leads to overtime or is the end itself (its banner).
            if s.state == .periodEnd {
                if period < Tuning.Match.periods {
                    banner(.eventPeriodEnd, ["\(period)"], .info, b.periodEnd)
                } else {
                    banner(.eventOvertime, [], .info, b.periodEnd)
                }
                sound(.matchWhistleEnd)
            }
        case .faceOff:
            if case .periodEnd? = lastFlow {
                if s.overtime { banner(.eventSuddenDeath, [], .info, b.period) } else { banner(.eventPeriod, ["\(s.period)"], .info, b.period) }
            }
        case .end(let result):
            let key: CopyKey = isDrill ? (result == .won ? .resultDrillWon : .resultTimeUp) : .eventFinal
            banner(key, [], result == .lost ? .bad : .good, b.end)
            sound(.matchWhistleEnd)
            sound(result == .lost ? .matchResultLose : .matchResultWin, delay: p.stingDelay)
        }
        switch e {
        case .goal, .drillInterrupted, .periodEnd, .faceOff, .whistle, .ready, .end: lastFlow = e
        default: break
        }
        return audible ? out : out.filter(\.isSeen)
    }

    /// Once per tick, after its events: the countdown of a period's (or a drill's) last seconds, and
    /// the aim of the player's carrier entering a pass or shot window.
    public mutating func frame(_ s: MatchSnapshot) -> [Cue] {
        guard audible else { return [] }
        var out: [Cue] = []
        if s.state == .play && !s.overtime {
            let secs = Int(s.clock.rounded(.up))
            if secs > p.countdown {
                lastTick = nil
            } else if secs >= 1, secs != lastTick {
                lastTick = secs
                out.append(.sound(.matchCountdownTick, x: nil, delay: 0))
                out.append(.haptic(.tick(p.hapticTick), delay: 0))
            }
        }
        let window: MatchSnapshot.Aim? = s.playerCarrier && s.state == .play ? s.aim.flatMap { $0 == .unassisted ? nil : $0 } : nil
        if let w = window, w != aimWindow { out.append(.haptic(.tick(p.hapticWindow), delay: 0)) }
        aimWindow = window
        return out
    }

    /// A shot's sound by its speed: the slowest third of shotSlow…shotFast soft, the middle medium,
    /// the fastest hard.
    func shot(_ speed: Double) -> SoundCue {
        let third = (p.shotFast - p.shotSlow) / 3
        return speed < p.shotSlow + third ? .matchShotSoft : speed < p.shotSlow + 2 * third ? .matchShotMedium : .matchShotHard
    }

    /// A release's impact: from releaseLow at releaseSlow m/s to releaseHigh at releaseFast.
    func release(_ speed: Double) -> Double { ramp(speed, p.releaseSlow, p.releaseFast, p.releaseLow, p.releaseHigh) }

    func ramp(_ v: Double, _ v0: Double, _ v1: Double, _ out0: Double, _ out1: Double) -> Double {
        guard v1 > v0 else { return out1 }
        let t = min(max((v - v0) / (v1 - v0), 0), 1)
        return out0 + (out1 - out0) * t
    }
}

extension Cue {
    /// A cue the demo keeps: what is seen, not heard or felt.
    var isSeen: Bool {
        switch self {
        case .shake, .pop: true
        case .banner, .sound, .haptic: false
        }
    }
}
