/// What a match is asked to be (spec §8, §9, §12): who plays, where, how long, and who decides the
/// player's releases. Everything a `Match` does follows from this and its seed (§4.3).
public struct MatchSetup: Sendable, Hashable {
    /// The match stream's seed (§4.3).
    public var seed: UInt64
    public var sport: Sport
    /// Team 0 (the player's side, attacking +Z) and team 1.
    public var home: SideSetup
    public var away: SideSetup
    /// The chosen period length (§8.3, §12).
    public var periodSeconds: Double
    /// Seconds per revolution of every carrier's orbit (§5.1): the ball-spin setting, or the demo's.
    public var orbitPeriod: Double
    /// A cup match: level after three periods goes to sudden-death overtime (§8.4).
    public var cup: Bool
    public var control: Control

    public init(seed: UInt64, sport: Sport, home: SideSetup, away: SideSetup, periodSeconds: Double,
                orbitPeriod: Double, cup: Bool, control: Control) {
        self.seed = seed; self.sport = sport; self.home = home; self.away = away
        self.periodSeconds = periodSeconds; self.orbitPeriod = orbitPeriod; self.cup = cup
        self.control = control
    }

    /// The demo behind the menus (§9): both sides automatic, the demo's orbit period, league rules.
    public static func demo(seed: UInt64, world: World, home: SideSetup, away: SideSetup,
                            periodSeconds: Double) -> MatchSetup {
        MatchSetup(seed: seed, sport: world.sport, home: home, away: away, periodSeconds: periodSeconds,
                   orbitPeriod: Tuning.Orbit.demoPeriod, cup: false, control: .automatic)
    }
}

/// One side of a match: its rating (§2.1), tactics (§12) and formation (§3).
public struct SideSetup: Sendable, Hashable {
    public var rating: Int
    public var tactics: Tactics
    public var formation: Formation

    public init(rating: Int, tactics: Tactics, formation: Formation) {
        self.rating = rating; self.tactics = tactics; self.formation = formation
    }

    /// A club as an AI side: its rating and tactics, the balanced formation (§3).
    public static func club(_ club: Club) -> SideSetup {
        SideSetup(rating: club.rating, tactics: club.tactics, formation: .balanced)
    }
}

/// A training drill (§10): the drill, the seed, and the coach's settings that still apply.
public struct DrillSetup: Sendable, Hashable {
    public var drill: Drill
    public var seed: UInt64
    /// The coach's tactics for the player's side (§10, §12).
    public var tactics: Tactics
    public var orbitPeriod: Double

    public init(drill: Drill, seed: UInt64, tactics: Tactics, orbitPeriod: Double) {
        self.drill = drill; self.seed = seed; self.tactics = tactics; self.orbitPeriod = orbitPeriod
    }
}

/// Who decides team 0's outfield releases (§5.3, §9).
public enum Control: String, Sendable, Hashable, CaseIterable {
    /// The player's finger: team 0's outfield carriers wait for a lift.
    case player
    /// Both sides fully automatic — the demo (§9).
    case automatic
}

/// The match states (§8.1); `ready` and `lost` occur only in drills (§10).
public enum MatchState: String, Sendable, Hashable, CaseIterable {
    case faceOff = "faceoff", play, goal, whistle, periodEnd, ready, lost, ended
}

/// Why a drill was interrupted (§10).
public enum DrillInterruption: String, Sendable, Hashable, CaseIterable {
    /// The opposing goalie took the ball.
    case saved
    /// Anyone else on the defence took it.
    case stolen
    case wrongNet
    /// A drill that requires an assist saw a goal without one.
    case noAssist
    /// The ball went dead (§6.5).
    case deadBall
}

/// How a match or drill finished.
public enum MatchResult: String, Sendable, Hashable {
    case won, lost, drawn
}

/// What kind of release left the stick (§5.4, §8.6): aimed shots, unassisted releases and clears
/// are shot-type; passes are not.
public enum ReleaseKind: String, Sendable, Hashable {
    case shot, unassisted, clear
}

/// What something emitted during a tick, for presentation and audio to consume. Players are roster
/// indices (§3).
public enum MatchEvent: Sendable, Hashable {
    case faceOff(spot: Spot)
    /// Play starts: a face-off drops or a drill's "get ready" ends.
    case play
    /// A drill (re)starts its "get ready" (§10).
    case ready
    case pickup(player: Int)
    case pass(from: Int, to: Int)
    case shot(by: Int, kind: ReleaseKind)
    case steal(by: Int, from: Int)
    case save(by: Int)
    case block(by: Int)
    case post
    case board(speed: Double)
    case goal(team: Int, scorer: Int?, assist: Int?, ownGoal: Bool)
    case whistle
    /// Play whistled dead for offside (§8.9, the ice sport only): the offending team and the first
    /// of its players, in roster order, who was in the zone before the puck.
    case offside(team: Int, player: Int)
    case periodEnd(period: Int)
    case drillInterrupted(DrillInterruption)
    case end(result: MatchResult)
}
