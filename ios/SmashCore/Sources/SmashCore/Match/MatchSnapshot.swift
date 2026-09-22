/// What a renderer draws (spec §5.2, §8): a read-only picture of the match after the last tick.
public struct MatchSnapshot: Sendable, Hashable {
    public struct Player: Sendable, Hashable {
        public let team: Int
        public let role: Role
        public let radius: Double
        public let x: Double
        public let z: Double
        public let vx: Double
        public let vz: Double
        /// The direction they face; `0` points down +Z.
        public let facing: Double
    }

    public struct Ball: Sendable, Hashable {
        public let x: Double
        public let z: Double
        public let vx: Double
        public let vz: Double
        public let radius: Double
        /// The carrier's roster index, or nil when loose.
        public let carrier: Int?
        /// The orbit angle in (−π, π] and its direction (+1 or −1).
        public let orbit: Double
        public let orbitDirection: Double
    }

    /// The aim line (§5.2): where a release now would go, and what it would snap to.
    public enum Aim: Sendable, Hashable {
        case pass(to: Int)
        case shot
        case unassisted
    }

    public let state: MatchState
    public let players: [Player]
    public let ball: Ball
    /// The carrier's aim line, when someone carries the ball.
    public let aim: Aim?
    /// True when the carrier waits for the player's finger (§5.3).
    public let playerCarrier: Bool
    /// Seconds left in the period (or the drill); 0 in overtime.
    public let clock: Double
    public let score: [Int]
    public let period: Int
    public let overtime: Bool
    public let time: Double
    public let result: MatchResult?
}

extension Match {
    public var snapshot: MatchSnapshot {
        let people = players.map {
            MatchSnapshot.Player(team: $0.team, role: $0.role, radius: $0.radius, x: $0.pos.x, z: $0.pos.z,
                                 vx: $0.vel.x, vz: $0.vel.z, facing: $0.facing)
        }
        let b = MatchSnapshot.Ball(x: ball.pos.x, z: ball.pos.z, vx: ball.vel.x, vz: ball.vel.z, radius: sport.ballRadius,
                                   carrier: ball.carrier, orbit: ball.orbit, orbitDirection: ball.orbitDirection)
        var aim: MatchSnapshot.Aim?
        if let c = ball.carrier {
            switch snap(c, orbit: ball.orbit) {
            case .pass(let m)?: aim = .pass(to: m)
            case .shot?: aim = .shot
            case nil: aim = .unassisted
            }
        }
        return MatchSnapshot(state: state, players: people, ball: b, aim: aim,
                             playerCarrier: ball.carrier.map(isPlayerControlled) ?? false,
                             clock: clock, score: score, period: period, overtime: overtime, time: time, result: result)
    }

    /// Distance to goal of the last shot-type release — aimed shots, unassisted releases and clears,
    /// never passes (§8.6). Nil before the first.
    public var lastShotDistance: Double? { ball.lastShotDistance }

    /// §8.6: the loose ball in play moving faster than 8 toward a goal mouth (within 0.8 of the
    /// posts) and crossing its line within 0.6 s. Presentation decides what to do about it.
    public var shotAboutToScore: Bool {
        typealias S = Tuning.SlowMotion
        guard state == .play, ball.carrier == nil,
              Pitch.length(ball.vel.x, ball.vel.z) > S.shotSpeed, ball.vel.z != 0 else { return false }
        for team in 0..<2 {
            let gz = Pitch.ownGoalZ(team)
            let t = (gz - ball.pos.z) / ball.vel.z
            guard t >= 0 && t <= S.shotHorizon else { continue }
            let crossing = ball.pos.x + ball.vel.x * t
            if crossing.magnitude <= Tuning.Pitch.postX + S.shotPostMargin { return true }
        }
        return false
    }
}
