/// One match or training drill, simulated (spec §1–§8, §10).
///
/// A value: copying a `Match` forks it, which is how tests and the vector recorder look ahead. It
/// is pure — no clock, no randomness but its own SplitMix64 stream, no platform API — so the same
/// setup and the same input produce the same match to the bit here and on Android (§4.3–§4.7).
///
/// Drive it with `hold(_:)` (the finger) and `tick()` (1/120 s of match time, two 1/240 s steps),
/// or `advance(realSeconds:timeScale:)` to turn real time into ticks (§4.2). Read `snapshot` to
/// draw and `drainEvents()` for what happened.
public struct Match: Sendable {
    // MARK: Configuration
    let sport: Sport
    let control: Control
    let drill: Drill?
    let periodSeconds: Double
    let cup: Bool
    /// Radians per second of every orbit (§5.1).
    let omega: Double
    let tactics: [Tactics]
    let skill: [Double]
    /// Each team's roster indices, in roster order (§3).
    let rosters: [[Int]]

    // MARK: State
    var players: [Athlete]
    var ball = Ball()
    var rng: SplitMix64
    public internal(set) var state: MatchState = .faceOff
    var stateTimer = 0.0
    public internal(set) var clock: Double
    public internal(set) var period = 1
    public internal(set) var overtime = false
    public internal(set) var score = [0, 0]
    /// Match time (§4.1).
    public internal(set) var time = 0.0
    public internal(set) var ticks = 0
    public internal(set) var result: MatchResult?
    /// Seconds the ball has been loose in play (§7.1).
    var looseTimer = 0.0
    /// Seconds the ball has been loose and slow in play (§6.5).
    var deadTimer = 0.0
    /// Seconds each team is still on alert as the defending side (§7.9).
    var alert = [0.0, 0.0]
    /// The outfield carrier watched for a crossing of the centre line, and their z last step (§7.9).
    var crossingCarrier: Int?
    var crossingZ = 0.0
    var restartSpot = Tuning.Pitch.faceoffCenter
    /// Set while a scored ball rolls on in the net: the net's goal line and its team's direction.
    var netRoll: (goalZ: Double, direction: Double)?
    var events: [MatchEvent] = []

    // MARK: Input
    /// Finger edges since the last tick, applied at the next tick boundary (§4.1).
    var pendingInput: [Bool] = []
    public internal(set) var fingerDown = false
    var realClock = TickClock()

    // MARK: Setup

    /// A match (§8): rosters from the formations, the stream seeded, the first face-off at centre.
    public init(_ setup: MatchSetup) {
        precondition(setup.periodSeconds > 0 && setup.orbitPeriod > 0, "Match: period length and orbit period must be positive")
        sport = setup.sport
        control = setup.control
        drill = nil
        periodSeconds = setup.periodSeconds
        cup = setup.cup
        omega = Pitch.twoPi / setup.orbitPeriod
        let sides = [setup.home, setup.away]
        tactics = sides.map(\.tactics)
        skill = sides.map { Match.skill(rating: $0.rating) }
        var roster: [Athlete] = []
        for team in 0..<2 {
            let side = sides[team]
            let lineup = [LineupSpot(role: .goalie, spot: Formation.goalie)] + side.formation.players
            for (slot, spot) in lineup.enumerated() {
                let home = team == 0 ? Vec(x: spot.spot.x, z: spot.spot.z) : Vec(x: -spot.spot.x, z: -spot.spot.z)
                roster.append(Athlete(team: team, slot: slot, role: spot.role, home: home, speedFactor: 1,
                                      rating: side.rating, patrol: nil))
            }
        }
        players = roster
        rosters = Match.rosters(of: roster)
        rng = SplitMix64(seed: setup.seed)
        clock = setup.periodSeconds
        drawFirstThinks()
        setUpFaceOff(at: Tuning.Pitch.faceoffCenter)
    }

    /// A training drill (§10): its fixed lineups and ratings, the ball with the named player.
    public init(_ setup: DrillSetup) {
        precondition(setup.orbitPeriod > 0, "Match: orbit period must be positive")
        let drill = setup.drill
        self.drill = drill
        sport = drill.world.sport
        control = .player
        periodSeconds = drill.seconds
        cup = false
        omega = Pitch.twoPi / setup.orbitPeriod
        let realOpponents = drill.away.contains { $0.role == .defender || $0.role == .forward }
        let ratings = [Tuning.Training.playerRating,
                       realOpponents ? Tuning.Training.opponentRatingOutfield : Tuning.Training.opponentRating]
        var opponents = Tactics.defaults
        opponents.pressing = Tuning.Training.opponentPressing
        tactics = [setup.tactics, opponents]
        skill = ratings.map { Match.skill(rating: $0) }
        var roster: [Athlete] = []
        for (team, lineup) in [drill.home, drill.away].enumerated() {
            for (slot, p) in lineup.enumerated() {
                roster.append(Athlete(team: team, slot: slot, role: p.role, home: Vec(x: p.spot.x, z: p.spot.z),
                                      speedFactor: p.speed, rating: ratings[team], patrol: p.patrol))
            }
        }
        players = roster
        rosters = Match.rosters(of: roster)
        rng = SplitMix64(seed: setup.seed)
        clock = drill.seconds
        drawFirstThinks()
        resetDrill()
    }

    /// `skill = clamp((rating − 60) / 30, 0, 1)` (§2.1).
    static func skill(rating: Int) -> Double {
        Pitch.clamp((Double(rating) - Tuning.Player.ratingOrigin) / Tuning.Player.skillSpan, 0, 1)
    }

    static func rosters(of players: [Athlete]) -> [[Int]] {
        (0..<2).map { team in players.indices.filter { players[$0].team == team } }
    }

    /// Each outfield player's first re-think falls at 0.2u, drawn in roster order (§7).
    mutating func drawFirstThinks() {
        for i in players.indices where players[i].isOutfield {
            players[i].thinkTimer = Tuning.AI.firstThinkSpread * rng.uniform()
        }
    }

    // MARK: Input and time

    /// The finger: `true` on touch-down, `false` when the last finger lifts. Applied at the next
    /// tick boundary, in order, so a tap shorter than a tick still releases (§4.1, §5.3).
    public mutating func hold(_ down: Bool) {
        pendingInput.append(down)
    }

    /// One tick: the input since the last tick, then two steps (§4.1).
    public mutating func tick() {
        for down in pendingInput {
            if down {
                fingerDown = true
            } else if fingerDown {
                fingerDown = false
                playerLift()
            }
        }
        pendingInput.removeAll(keepingCapacity: true)
        for _ in 0..<Tuning.Time.stepsPerTick { step() }
        ticks += 1
    }

    /// Runs the ticks `realSeconds` of real time at `timeScale` amount to (§4.2): the gap is
    /// clamped to 0.1 s, and the remainder carries to the next call. Returns the ticks run.
    @discardableResult
    public mutating func advance(realSeconds: Double, timeScale: Double) -> Int {
        let n = realClock.ticks(realSeconds: realSeconds, timeScale: timeScale)
        for _ in 0..<n { tick() }
        return n
    }

    /// Everything emitted since the last drain, in order.
    public mutating func drainEvents() -> [MatchEvent] {
        defer { events.removeAll(keepingCapacity: true) }
        return events
    }

    /// Which team is defending on alert (§7.9) — the sharpened defence a carried ball opens by
    /// crossing the centre line. Presentation may show it; it never changes a tick.
    public var alerted: [Bool] { [alert[0] > 0, alert[1] > 0] }

    /// The SplitMix64 stream's position — for the golden vectors (§4.7).
    public var streamState: UInt64 { rng.state }

    // MARK: The step (§4.5)

    mutating func step() {
        let dt = Tuning.Time.stepSeconds
        time += dt                                           // 1
        advanceStateMachine(dt)                              // 2
        let live = state == .play
        if live { runClock(dt) }                             // 3
        if live {                                            // 4
            updateAlert(dt)
            if ball.carrier != nil { looseTimer = 0 } else { looseTimer += dt }
            thinkTeam(0, dt)
            thinkTeam(1, dt)
        }
        movePlayers(dt, live: live)                          // 5
        resolveContacts()                                    // 6
        constrainPlayers()
        if live { moveLiveBall(dt) } else { moveIdleBall(dt) } // 7
        if live { checkDeadBall(dt) }                        // 8
    }

    mutating func emit(_ event: MatchEvent) { events.append(event) }

    // MARK: Roster queries

    /// Team `team`'s outfield players (defenders and forwards), in roster order.
    func outfield(_ team: Int) -> [Int] { rosters[team].filter { players[$0].isOutfield } }

    func goalie(of team: Int) -> Int? { rosters[team].first { players[$0].isGoalie } }

    /// The roster index nearest `point` among `candidates` (the first on a tie), and its distance.
    func nearest(to point: Vec, among candidates: [Int]) -> (index: Int, distance: Double)? {
        var best: (Int, Double)?
        for j in candidates {
            let d = Pitch.distance(players[j].pos, point)
            if best == nil || d < best!.1 { best = (j, d) }
        }
        return best
    }

    /// Whether team 0's outfield releases wait for the player's finger (§5.3).
    func isPlayerControlled(_ i: Int) -> Bool {
        control == .player && players[i].team == 0 && !players[i].isGoalie
    }
}
