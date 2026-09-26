/// One player on the pitch (spec §3): who they are, where they are, and what their automatic play
/// currently remembers (§7). Indexed by roster position everywhere.
struct Athlete: Sendable {
    let team: Int
    /// Position in the team's roster (face-off slots, §8.2).
    let slot: Int
    let role: Role
    let radius: Double
    let topSpeed: Double
    /// The formation spot (§3), for a team attacking its own +Z (team 1's already mirrored). In a
    /// drill it is the start spot.
    let home: Vec
    /// Where a drill reset puts them (§10).
    let start: Vec
    let patrol: Patrol?

    var pos: Vec
    var vel = Vec.zero
    var facing: Double

    // Automatic play (§7) and possession (§6).
    var target: Vec?
    var pickupCooldown = 0.0
    var holdTime = 0.0
    var decision: CarrierDecision?
    var mark: Int?
    var expectPass = 0.0
    var stealContact = 0.0
    /// Committed as a challenger while match time is below this (§7.2).
    var challengeUntil = 0.0
    /// True while this player is the challenger going for the **ball** rather than covering (§7.2).
    /// It is kept for as long as the commitment lasts so the two defenders do not swap jobs several
    /// times a second and end up in the same place.
    var onTheBall = false
    var thinkTimer = 0.0
    /// A patrolling dummy's next step reports zero velocity (§10: zero across a reset).
    var patrolFresh = true

    var isDummy: Bool { role == .dummy }
    var isGoalie: Bool { role == .goalie }
    /// Defenders and forwards: the players the rules call "outfield".
    var isOutfield: Bool { role == .defender || role == .forward }

    init(team: Int, slot: Int, role: Role, home: Vec, speedFactor: Double, rating: Int, patrol: Patrol?) {
        self.team = team
        self.slot = slot
        self.role = role
        self.home = home
        self.start = home
        self.patrol = patrol
        self.pos = home
        self.facing = team == 0 ? 0 : Pitch.pi
        switch role {
        case .goalie:
            radius = Tuning.Player.goalieRadius
            topSpeed = Tuning.Player.goalieTopSpeed * speedFactor
        case .dummy:
            radius = Tuning.Player.dummyRadius
            topSpeed = 0
        case .defender, .forward:
            radius = Tuning.Player.outfieldRadius
            let base = Tuning.Player.outfieldSpeedBase
                + (Double(rating) - Tuning.Player.ratingOrigin) * Tuning.Player.outfieldSpeedPerRating
            topSpeed = base * speedFactor
        }
    }
}

/// What an AI carrier has decided to do with the ball (§7.6, §7.8).
enum CarrierDecision: Sendable, Hashable {
    case shoot
    case pass(to: Int)
    case clear
}

/// The ball (spec §5, §6).
struct Ball: Sendable {
    var pos = Vec.zero
    var vel = Vec.zero
    var carrier: Int?
    /// The orbit angle, in (−π, π] (§5.1).
    var orbit = Pitch.pi
    /// +1 or −1: the direction the ball circles in.
    var orbitDirection = 1.0
    var lastTouch: Int?
    /// The last player to release it (§8.5).
    var lastReleaser: Int?
    var assist: Int?
    /// Match time the carrier won it (the settle window, §6.4).
    var wonAt = 0.0
    /// Match time of the last release of any kind (§7.8); nil before the first.
    var lastReleaseTime: Double?
    /// Distance to goal of the last shot-type release (§8.6); nil before the first.
    var lastShotDistance: Double?
    var pending: PendingRelease?
}

/// A player's release held until the ball snaps (§5.3).
struct PendingRelease: Sendable, Hashable {
    let player: Int
    /// Match time at which it leaves unassisted if nothing has snapped.
    let deadline: Double
}

/// What a release would snap to (§5.2).
enum Snap: Sendable, Hashable {
    case pass(to: Int)
    case shot
}
