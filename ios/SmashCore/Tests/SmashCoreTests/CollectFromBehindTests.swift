import Testing
@testable import SmashCore

/// §6.3.1: a ball arriving from behind an outfield player is not reliably collected — it is
/// gathered rarely, ricochets off them, or runs on past them. The twin of Android's
/// `CollectFromBehindTest.kt`.
@Suite struct CollectFromBehindTests {
    typealias B = Tuning.Ball

    /// A match with every player parked out of the way, so `pickUp` can only ever choose `subject`.
    /// Positions are set straight onto the athletes: nothing here is a legal match state, and
    /// nothing here constrains them back onto the pitch.
    static func match(seed: UInt64, control: Control = .automatic) -> Match {
        let side = SideSetup(rating: 50, tactics: .defaults, formation: Formation.allCases[0])
        var m = Match(MatchSetup(seed: seed, sport: .field, home: side, away: side,
                                 periodSeconds: 60, orbitPeriod: 2.0, cup: false, control: control))
        for i in m.players.indices { m.players[i].pos = Vec(x: 200 + Double(i), z: 200) }
        m.ball.carrier = nil
        m.ball.lastTouch = nil
        return m
    }

    /// An outfield player of `team` — roster index 0 is the goalie, whom §6.3.1 exempts.
    static func outfield(_ m: Match, team: Int = 0) -> Int {
        m.rosters[team].first { m.players[$0].isOutfield }!
    }

    /// Put `subject` at the origin facing `facing`, with the ball `1.0` away and closing at
    /// `speed` along `travel`, then run §6.3's pickup. Returns what became of it.
    enum Outcome: Equatable { case collected, ricocheted, ranOn }

    static func offer(_ m: inout Match, subject: Int, facing: Double, travel: Vec, speed: Double,
                      playerVel: Vec = .zero) -> Outcome {
        m.players[subject].pos = .zero
        m.players[subject].vel = playerVel
        m.players[subject].facing = facing
        m.players[subject].pickupCooldown = 0
        m.ball.carrier = nil
        m.ball.pos = Vec(x: 0, z: -1.0)
        m.ball.vel = Vec(x: travel.x * speed, z: travel.z * speed)
        m.events.removeAll()
        let before = m.ball.vel
        m.pickUp(radius: m.sport.ballRadius)
        if m.ball.carrier == subject { return .collected }
        if m.ball.vel == before { return .ranOn }
        return .ricocheted
    }

    /// A ball travelling +z meets a player facing +z from directly behind: the worst case.
    static func fromBehind(_ m: inout Match, subject: Int? = nil, speed: Double = 15) -> Outcome {
        offer(&m, subject: subject ?? outfield(m), facing: 0, travel: Vec(x: 0, z: 1), speed: speed)
    }

    // MARK: What is unaffected

    /// A ball met head-on is collected, every time, and **takes nothing from §4.3's stream** — the
    /// one property that keeps the rule from rewriting every ordinary pickup in the corpus.
    @Test func aBallMetHeadOnIsAlwaysCollectedAndCostsNoRandomness() {
        for seed in UInt64(0)..<200 {
            var m = Self.match(seed: seed)
            let state = m.rng.state
            let out = Self.offer(&m, subject: Self.outfield(m), facing: 0, travel: Vec(x: 0, z: -1), speed: 15)
            #expect(out == .collected)
            #expect(m.rng.state == state)
            #expect(m.events.isEmpty == false)   // a pickup, not a fumble
        }
    }

    /// The free cone is 60° wide either side of facing: at 59° nothing applies and no draw is made.
    @Test func insideTheSixtyDegreeConeNothingApplies() {
        let inside = Pitch.pi - 59.0 / 180.0 * Pitch.pi      // arrives 59° off the player's facing
        for seed in UInt64(0)..<200 {
            var m = Self.match(seed: seed)
            let state = m.rng.state
            let out = Self.offer(&m, subject: Self.outfield(m), facing: 0,
                                 travel: Vec(x: DetMath.sin(inside), z: DetMath.cos(inside)), speed: 15)
            #expect(out == .collected)
            #expect(m.rng.state == state)
        }
    }

    /// Past it, it bites: at 61° a draw is made and the ball is sometimes lost.
    @Test func justOutsideTheConeTheRuleStartsToBite() {
        let outside = Pitch.pi - 61.0 / 180.0 * Pitch.pi
        var lost = 0
        for seed in UInt64(0)..<400 {
            var m = Self.match(seed: seed)
            let state = m.rng.state
            let out = Self.offer(&m, subject: Self.outfield(m), facing: 0,
                                 travel: Vec(x: DetMath.sin(outside), z: DetMath.cos(outside)), speed: 15)
            #expect(m.rng.state != state)        // the draw happened
            if out != .collected { lost += 1 }
        }
        #expect(lost > 0)
    }

    /// **A slow roll stays collectable**, however far behind it comes from: under 4 relative, the
    /// speed factor is zero and no draw is made.
    @Test func aSlowRollFromBehindIsAlwaysCollected() {
        for seed in UInt64(0)..<200 {
            var m = Self.match(seed: seed)
            let state = m.rng.state
            #expect(Self.fromBehind(&m, speed: B.collectSlowSpeed - 0.5) == .collected)
            #expect(m.rng.state == state)
        }
    }

    /// A ball keeping pace with its receiver is at rest relative to them, so it is theirs however
    /// fast the two are moving down the pitch — the "trailing pass that barely catches you" case.
    @Test func aBallKeepingPaceWithItsReceiverIsCollected() {
        for seed in UInt64(0)..<100 {
            var m = Self.match(seed: seed)
            let out = Self.offer(&m, subject: Self.outfield(m), facing: 0, travel: Vec(x: 0, z: 1),
                                 speed: 14, playerVel: Vec(x: 0, z: 13))
            #expect(out == .collected)
        }
    }

    /// **Goalies are exempt** — §3 pins their facing down the pitch, so an angle from it means
    /// nothing. Their own low limit (9) is what guards them.
    @Test func goaliesAreExempt() {
        var m = Self.match(seed: 1)
        let keeper = m.players.indices.first { m.players[$0].isGoalie }!
        for seed in UInt64(0)..<100 {
            m.rng = SplitMix64(seed: seed)
            let state = m.rng.state
            // 8 is under the goalie's limit of 9, and arrives from straight behind their pinned facing.
            #expect(Self.fromBehind(&m, subject: keeper, speed: 8) == .collected)
            #expect(m.rng.state == state)
        }
    }

    // MARK: The three outcomes

    /// Straight from behind and at pace: collected 8 % of the time, and of the rest, 40 % ricochet
    /// and 60 % run on. The shares are the spec's, measured over a few thousand draws.
    @Test func straightFromBehindSplitsThreeWays() {
        var counts: [Outcome: Int] = [.collected: 0, .ricocheted: 0, .ranOn: 0]
        let trials = 4000
        for seed in UInt64(0)..<UInt64(trials) {
            var m = Self.match(seed: seed)
            counts[Self.fromBehind(&m), default: 0] += 1
        }
        let collected = Double(counts[.collected]!) / Double(trials)
        let ricochet = Double(counts[.ricocheted]!) / Double(trials)
        let ranOn = Double(counts[.ranOn]!) / Double(trials)
        #expect((collected - (1 - B.collectPressureWeight)).magnitude < 0.02)
        #expect((ricochet - B.collectPressureWeight * B.collectRicochetShare).magnitude < 0.03)
        #expect((ranOn - B.collectPressureWeight * (1 - B.collectRicochetShare)).magnitude < 0.03)
        // All three really happen — the point of the rule is that it is not a binary.
        #expect(counts.values.allSatisfy { $0 > 0 })
    }

    /// A fumble is a touch, it is emitted, and the fumbler cannot have the ball back — nor steal
    /// it — for 0.35 s. That cooldown is what makes this one event and not a coin flipped every step.
    @Test func aFumbleIsATouchAndCostsTheFumblerTheNextMoment() {
        var seen = 0
        for seed in UInt64(0)..<400 where seen < 20 {
            var m = Self.match(seed: seed)
            let subject = Self.outfield(m)
            guard Self.fromBehind(&m) != .collected else { continue }
            seen += 1
            #expect(m.ball.lastTouch == subject)
            #expect(m.players[subject].pickupCooldown == B.collectFumbleCooldown)
            #expect(m.events.contains { if case .fumble(subject, _) = $0 { true } else { false } })
            // Offered again on the very next step, still in reach, they cannot take it.
            m.ball.pos = Vec(x: 0, z: -1.0)
            m.pickUp(radius: m.sport.ballRadius)
            #expect(m.ball.carrier == nil)
        }
        #expect(seen == 20)
    }

    /// A ricochet keeps 55 % of the approach speed, in the player's frame, and goes somewhere
    /// within ±2.0 rad of where the ball was already headed.
    @Test func aRicochetKeepsItsShareOfTheSpeedAndStaysInItsCone() {
        var seen = 0
        for seed in UInt64(0)..<2000 where seen < 50 {
            var m = Self.match(seed: seed)
            let travel = Pitch.heading(0, 1)
            guard Self.fromBehind(&m) == .ricocheted else { continue }
            seen += 1
            let off = Pitch.length(m.ball.vel.x, m.ball.vel.z)   // the player is at rest here
            #expect((off - 15 * B.collectRicochetKeep).magnitude < 1e-9)
            let turned = Pitch.heading(m.ball.vel.x, m.ball.vel.z)
            #expect(Pitch.angleDiff(turned, travel).magnitude <= B.collectRicochetSpread + 1e-9)
        }
        #expect(seen == 50)
    }

    // MARK: Fair both ways

    /// **It is the player's rule too.** `.player` is the control scheme where team 0's carriers wait
    /// for the finger (§5), and under it the rule is unchanged — the core never branches on who is
    /// steering, because nobody steers a facing: §3 takes it from movement. The test that would
    /// catch an exemption smuggled in later.
    @Test func theRuleIsTheSameUnderThePlayersControl() {
        for seed in UInt64(0)..<300 {
            var auto = Self.match(seed: seed, control: .automatic)
            var finger = Self.match(seed: seed, control: .player)
            #expect(Self.fromBehind(&auto) == Self.fromBehind(&finger))
        }
    }

    /// **The rule is symmetric.** A team 1 player, who attacks the other way, is judged exactly as
    /// a team 0 player is: same facing, same arrival, same outcome, draw for draw.
    @Test func theRuleIsTheSameForBothTeams() {
        let reference = Self.match(seed: 7)
        let a = Self.outfield(reference, team: 0)
        let b = Self.outfield(reference, team: 1)
        for seed in UInt64(0)..<300 {
            var one = Self.match(seed: seed)
            var two = Self.match(seed: seed)
            #expect(Self.fromBehind(&one, subject: a) == Self.fromBehind(&two, subject: b))
        }
    }
}
