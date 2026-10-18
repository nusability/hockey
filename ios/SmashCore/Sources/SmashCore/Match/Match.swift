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
    /// The period's length in seconds (§12) — public because the row a finished match reports names
    /// it, and the app must not have to guess at what the setup chose (§18.2).
    public let periodSeconds: Double
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
    /// How hard this match tilts back toward whoever is behind (§7.10). Drawn once, at set-up;
    /// a drill has none. Presentation never shows it — it is exposed for the bench and the tests.
    public internal(set) var temperament = 0.0
    /// Each team's tilt (§7.10): positive is *chase* — the side behind — negative is *hold*, the
    /// side ahead, and both are zero at a level or a one-goal score. Recomputed each step in play.
    var balance = [0.0, 0.0]
    /// Whether the ball was inside each team's attacking zone last step (§8.9, the ice sport only).
    var inZone = [false, false]
    /// Offside (§8.9), counted for the bench and the tests and read by no rule: the zone entries an
    /// attack made, those that were offside, and those of those the referee let go.
    public internal(set) var offsideEntries = 0
    public internal(set) var offsideStrays = 0
    public internal(set) var offsideMissed = 0
    // MARK: The learned policy (§7)

    /// The trained policy driving off-ball outfield play, or `nil` for §7's written rules.
    ///
    /// Set by the trainer and the bench only. The shipped app leaves it `nil`, so with it unset the
    /// match is the one the golden vectors already pin — which is how this hook is kept honest: if
    /// `shared/vectors/match/` stays green, nothing here changed a tick. It is exposed for the same
    /// reason `streamState` and `temperament` are (§4.7).
    /// One entry per team: a trained policy, or `nil` for §7's written rules. Per team rather than
    /// one net and a list, because the two sides are routinely *different* nets — a candidate is
    /// scored against §7 for an absolute yardstick and against the current best for self-play, and
    /// late on, two rungs of the `strength` ladder meet each other.
    var policies: [PolicyNet?] = [nil, nil]
    /// When non-nil, every hand-written re-think appends what it saw and what it chose, so a net
    /// can be fitted to §7's rules before self-play starts improving on them.
    var teachingTape: [TeachingSample]?
    /// Training only: both keepers stand aside, leaving the nets open (§7.8 untouched otherwise).
    ///
    /// A curriculum step, not a rule. A policy learning from random weights never scores, so a
    /// goal-difference reward is flat and teaches nothing — the search cannot climb what it cannot
    /// reach. With the nets open a shot on target counts, so "move the ball toward their goal"
    /// becomes learnable, and the keepers come back once it can finish.
    public var openNets = false
    /// Training only: how much of §6.3.1 to forgive, 0 for none and 1 for all of it.
    ///
    /// A curriculum step, not a rule. **0 is the shipped game** and the golden vectors, so nothing
    /// a player meets depends on this; at 1 a ball from behind is collected exactly as it was
    /// before §6.3.1 existed.
    ///
    /// Why it has to exist: §6.3.1 took away the free possession a random policy used to bootstrap
    /// itself on. §7 is barely troubled by the rule — it assigns a chaser to the ball and holds it
    /// 0.28 of the time — but a search starting from noise never gathers the ball at all, both
    /// sides of a self-play pair stop contesting, neither is punished, and the reward goes flat:
    /// measured, 91.6 % of a self-play match with the ball loose and a best fitness that did not
    /// move in 56 iterations. Forgiving the rule early buys back the gradient, and tightening it
    /// to 0 before anything is believed means the policy is finally judged under the real rule.
    ///
    /// **It only ever tightens.** A curriculum that loosens again teaches the policy to straddle
    /// both worlds, the same reason the nets stay shut once they are shut (`openNets`).
    public var collectEase = 0.0
    /// Training only: a policy-gradient trainer's seam into every policy decision, or `nil`.
    ///
    /// Evolution strategies needed only a score per match and could treat the match as a black box.
    /// A method that assigns credit through time has to see each decision and explore around it, so
    /// this hands the trainer what the player saw and what the net said, and takes back the outputs
    /// to use. `nil` - every app, every vector, every test - is `net.forward` and nothing else.
    public var policyHook: PolicyHook?
    /// Training only: a crude scripted opponent per team, or `nil`.
    ///
    /// Sparring partners, not tactics. Self-play against one's own lineage drifts into private
    /// equilibria — measured: both sides stopped contesting the ball, neither was punished for it,
    /// and the result collapsed the moment it met §7. A policy that must also beat an opponent that
    /// only chases, and one that only blocks, cannot sign that kind of truce. They are deliberately
    /// too stupid to be worth imitating; their job is to punish laziness, not to teach play.
    public var sparring: [Sparring?] = [nil, nil]
    /// Training only: running costs something.
    ///
    /// Without it, covering the pitch end to end at top speed is free, and a side that collapses
    /// every player onto its own goal and then sprints them all forward again pays nothing for it.
    /// That is most of why the bus is such a strong strategy here and such a weak one in a real
    /// match — real legs run out. Drains with speed, recovers while slow, and never takes a player
    /// below `Tuning` minimum pace, so a tired side is slower, not stranded.
    public var stamina = false
    /// Training only: how play restarts, instead of at a face-off spot. `nil` is the real game.
    ///
    /// The cure for a reward that cannot be reached. From random weights the chain needed to score
    /// — win the ball, carry it, turn, wait for the orbit, release on the right beat — is far too
    /// long to stumble into, so every match ends 0–0 and the search has nothing to climb.
    ///
    /// The rungs chain backwards from the goal. Handed the ball six metres out, the last link is
    /// learnable on its own; back away and it joins the links one at a time. The later rungs take
    /// the ball *away* again, because a ladder made only of `ours` teaches finishing and never
    /// teaches winning possession — measured, after 110 iterations of full matches: a side that
    /// offered nearly twice §7's passing options and reached the attacking third a quarter as often.
    ///
    /// **It shapes which situations the policy meets, never what it should do in them.**
    public var trainingSpawn: TrainingStart?
    /// Draws for the training spawn. Its own stream: the match's (§4.3) must not move.
    public var spawnRNG = SplitMix64(seed: 0)
    /// Each team's `strength` (§7): the one dial on how well the policy plays. 1 is its best.
    var strength = [1.0, 1.0]
    /// Each team's style vector (§7) — what makes two clubs play unlike each other.
    var style = [[Double]](repeating: [Double](repeating: 0, count: PolicyInputs.styleCount), count: 2)

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
        drawTemperament()
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

    /// The match's temperament (§7.10), drawn once at set-up before the first re-thinks (§4.3).
    /// A drill has none and draws nothing.
    mutating func drawTemperament() {
        typealias B = Tuning.AI.Balance
        temperament = Pitch.clamp(B.temperamentBase + rng.noise(B.temperamentNoise), 0, B.temperamentMax)
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
            updateBalance()
            updateAlert(dt)
            if ball.carrier != nil { looseTimer = 0 } else { looseTimer += dt }
            thinkTeam(0, dt)
            thinkTeam(1, dt)
        }
        movePlayers(dt, live: live)                          // 5
        spendEnergy(dt)
        resolveContacts()                                    // 6
        constrainPlayers()
        if live { moveLiveBall(dt) } else { moveIdleBall(dt) } // 7
        if live { checkOffside() }                           // 8
        if live { checkDeadBall(dt) }
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
