import Foundation

/// The stadium and the drums (spec §8.8, `shared/data/atmosphere.toml`) — what the looping layers
/// under a match should be doing right now, decided once for both apps. The twin of Android's
/// `core/feel/Atmosphere.kt`.
///
/// It owns no audio and knows no file: it turns the match into five numbers between 0 and 1 — the
/// home crowd, the away crowd, the swell over both, the music, and how far the music is ducked —
/// plus where the swell sits across the stereo field and the rate the match layers play at. The
/// playback layers turn those into gains with each layer's own `quiet_db`/`loud_db`.
///
/// Nothing here restarts a loop: a bed comes up and goes down, it never begins again.
public struct Atmosphere: Sendable {
    /// The declared mapping (atmosphere.toml `[mapping]`, `[surge]`, `[music_mapping]`, `[duck]`,
    /// `[time_scale]`).
    public struct Params: Sendable, Hashable {
        /// `[mapping]`.
        public var shape = 1.6
        public var base = 0.0
        public var rise = 1.0
        public var hush = 0.0
        public var lateSeconds = 30.0
        public var lateRise = 0.0
        public var attackDanger = 0.0
        public var defendDanger = 0.0
        public var panSpan = 0.0
        public var surgeDecay = 1.0
        public var attackRate = 3.0
        public var releaseRate = 1.0
        /// `[surge]`.
        public var surge = Surge()
        /// `[music_mapping]`.
        public var music = Music()
        /// `[duck]` — the times only; the depth is the playback layer's, in dB.
        public var duckAttack = 0.05
        public var duckHold = 0.5
        public var duckRelease = 1.0
        /// `[time_scale]`.
        public var minRate = 0.42

        public struct Surge: Sendable, Hashable {
            public var kickoff = 0.0, goalFor = 0.0, goalAgainst = 0.0, save = 0.0
            public var post = 0.0, steal = 0.0, whistle = 0.0, periodEnd = 0.0, ended = 0.0
            public init() {}
        }

        public struct Music: Sendable, Hashable {
            public var base = 0.0, rise = 0.0, lateRise = 0.0, attackRate = 1.0, releaseRate = 1.0
            public init() {}
        }

        public init() {}
    }

    /// What the layers should be doing this frame. Every level is 0…1 — the playback layer reads
    /// each layer's `quiet_db`…`loud_db` across it.
    public struct Levels: Sendable, Hashable {
        /// The crowd behind the player's own goal, the crowd behind the other, and the swell over both.
        public var home = 0.0, away = 0.0, swell = 0.0
        /// Where the swell sits: −1 left … 1 right, leaning toward the end being attacked.
        public var swellPan = 0.0
        /// The match music.
        public var music = 0.0
        /// How far the music is ducked, 0 (not at all) … 1 (the declared depth).
        public var duck = 0.0
        /// The rate the match layers play at, following §8.6's time scale; 0 while the match is paused.
        public var rate = 1.0

        public init() {}
    }

    /// Which goal a shot about to score (§8.6) is heading for.
    public enum Danger: Sendable, Hashable {
        /// The player's own goal is the one under threat.
        case ours
        /// The other team's.
        case theirs
    }

    private let p: Params
    private var homeSurge = 0.0
    private var awaySurge = 0.0
    private var levels = Levels()
    private var duckFor = 0.0

    public init(_ params: Params) {
        p = params
        levels.rate = 1
    }

    /// The levels as they stand, without advancing anything.
    public var now: Levels { levels }

    /// What an event pushes into the crowd. A goal is the big one: the side that scored goes to the
    /// top, the side that conceded below its own floor.
    public mutating func hear(_ e: MatchEvent, _ s: MatchSnapshot) {
        let g = p.surge
        switch e {
        case .goal(let team, _, _, _):
            push(home: team == 0 ? g.goalFor : g.goalAgainst, away: team == 0 ? g.goalAgainst : g.goalFor)
        case .save(let i):
            side(s.players[i].team, g.save)
        case .steal(let by, _):
            side(s.players[by].team, g.steal)
        case .post:
            push(home: g.post, away: g.post)
        case .play:
            push(home: g.kickoff, away: g.kickoff)
        case .whistle, .drillInterrupted:
            push(home: g.whistle, away: g.whistle)
        case .periodEnd:
            push(home: g.periodEnd, away: g.periodEnd)
        case .end:
            push(home: g.ended, away: g.ended)
        default:
            break
        }
    }

    /// A one-shot that the music steps back under (atmosphere.toml `[duck].cues`), lasting `seconds`.
    public mutating func duck(seconds: Double) {
        duckFor = Swift.max(duckFor, Swift.max(seconds, 0) + p.duckHold)
    }

    /// One frame of real time. `s` is the match as it stands (nil outside a match: everything falls
    /// away); `danger` is §8.6's shot about to score and which goal it is heading for; `timeScale` is
    /// §8.6's, which the match layers follow.
    @discardableResult
    public mutating func update(_ dt: Double, _ s: MatchSnapshot?, danger: Danger?, timeScale: Double) -> Levels {
        let step = Swift.max(dt, 0)
        homeSurge *= exp(-p.surgeDecay * step)
        awaySurge *= exp(-p.surgeDecay * step)

        var attack = 0.0, defend = 0.0, late = 0.0
        if let s {
            let threat = clamp(s.ball.z / Tuning.Pitch.goalLineZ, -1, 1)
            attack = pow(Swift.max(0, threat), p.shape)
            defend = pow(Swift.max(0, -threat), p.shape)
            if s.overtime {
                late = 1
            } else if s.state == .play, p.lateSeconds > 0 {
                late = clamp((p.lateSeconds - s.clock) / p.lateSeconds, 0, 1)
            }
        }
        var homeDanger = 0.0, awayDanger = 0.0
        switch danger {
        case .theirs: homeDanger = p.attackDanger; awayDanger = p.defendDanger
        case .ours: homeDanger = p.defendDanger; awayDanger = p.attackDanger
        case nil: break
        }
        let live = s != nil
        let homeTarget = live ? clamp(p.base + attack * p.rise - defend * p.hush + late * p.lateRise + homeDanger + homeSurge, 0, 1) : 0
        let awayTarget = live ? clamp(p.base + defend * p.rise - attack * p.hush + late * p.lateRise + awayDanger + awaySurge, 0, 1) : 0
        levels.home = ease(levels.home, homeTarget, step)
        levels.away = ease(levels.away, awayTarget, step)
        levels.swell = ease(levels.swell, Swift.max(homeTarget, awayTarget), step)
        levels.swellPan = clamp(p.panSpan * (defend - attack), -1, 1)

        let m = p.music
        let musicTarget = live ? clamp(m.base + Swift.max(attack, defend) * m.rise + late * m.lateRise, 0, 1) : 0
        let mRate = musicTarget > levels.music ? m.attackRate : m.releaseRate
        levels.music += (musicTarget - levels.music) * (1 - exp(-mRate * step))

        duckFor = Swift.max(duckFor - step, 0)
        let duckTarget = duckFor > 0 ? 1.0 : 0.0
        let dRate = duckTarget > levels.duck ? 1 / Swift.max(p.duckAttack, 1e-3) : 1 / Swift.max(p.duckRelease, 1e-3)
        levels.duck += (duckTarget - levels.duck) * (1 - exp(-dRate * step))

        levels.rate = timeScale <= 0 ? 0 : Swift.max(Swift.min(timeScale, 1), p.minRate)
        return levels
    }

    private mutating func side(_ team: Int, _ amount: Double) {
        push(home: team == 0 ? amount : 0, away: team == 0 ? 0 : amount)
    }

    private mutating func push(home: Double, away: Double) {
        homeSurge += home
        awaySurge += away
    }

    /// A level eases toward its target — faster coming up than going down: a crowd rises quicker
    /// than it settles.
    private func ease(_ v: Double, _ target: Double, _ dt: Double) -> Double {
        let rate = target > v ? p.attackRate : p.releaseRate
        return v + (target - v) * (1 - exp(-rate * dt))
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(v, lo), hi) }
}
