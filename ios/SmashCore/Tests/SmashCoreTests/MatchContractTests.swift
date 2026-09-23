import Testing
@testable import SmashCore

/// The simulation's contracts that are easy to state (spec §4–§10), checked directly rather than
/// through the golden vectors. Android's `MatchContractTest` checks the same list.
@Suite struct MatchContractTests {
    static let dt = Tuning.Time.stepSeconds

    static func drill(_ d: Drill, seed: UInt64 = 7) -> Match {
        var m = Match(DrillSetup(drill: d, seed: seed, tactics: .defaults, orbitPeriod: 2.0))
        while m.state != .play { m.tick() }
        _ = m.drainEvents()
        return m
    }

    static let match = MatchSetup(seed: 42, sport: .field, home: .club(.mossfoxes), away: .club(.rocketlynx),
                                  periodSeconds: 60, orbitPeriod: 2.0, cup: false, control: .player)

    /// Places carrier 0 at the origin and team-mate 1 at (10, 0), both still: the pass lies at π/2,
    /// the goal at 0.
    static func passAtRightAngle() -> Match {
        var m = drill(.pass)
        m.players[0].pos = Vec(x: 0, z: 0)
        m.players[0].vel = .zero
        m.players[1].pos = Vec(x: 10, z: 0)
        m.players[1].vel = .zero
        m.ball.orbitDirection = 1
        return m
    }

    // MARK: §4.1–§4.2 — time

    @Test func sixtyAndOneTwentyHertzRunTheSameTicks() {
        for scale in [1.0, 0.45, 0.18] {
            var a = Match(Self.match)
            var b = Match(Self.match)
            var ticksA: [Int] = []
            for frame in 0..<3600 {
                if frame % 97 == 10 { a.hold(true); b.hold(true) }
                if frame % 97 == 60 { a.hold(false); b.hold(false) }
                a.advance(realSeconds: 1.0 / 60.0, timeScale: scale)
                b.advance(realSeconds: 1.0 / 120.0, timeScale: scale)
                b.advance(realSeconds: 1.0 / 120.0, timeScale: scale)
                #expect(a.ticks == b.ticks)
                #expect(a.drainEvents() == b.drainEvents())
                #expect(MatchVector.sample(a) == MatchVector.sample(b))
                ticksA.append(a.ticks)
            }
            #expect(ticksA.last! == Int((3600.0 / 60.0 * 120.0 * scale).rounded()))
        }
    }

    @Test func aFrameGapIsClampedToATenthOfASecond() {
        var m = Match(Self.match)
        #expect(m.advance(realSeconds: 5, timeScale: 1) == 12)
        #expect(m.advance(realSeconds: 1.0 / 60.0, timeScale: 0) == 0)
    }

    @Test func aTapShorterThanATickStillReleases() {
        var m = Self.passAtRightAngle()
        m.ball.orbit = Pitch.pi / 2
        m.hold(true)
        m.hold(false)
        m.tick()
        #expect(m.drainEvents().contains(.pass(from: 0, to: 1)))
    }

    // MARK: §4.6 — restarts

    @Test func aFaceOffClearsWhatARestartClearsAndKeepsThinkTimers() {
        var m = Match(MatchSetup.demo(seed: 3, world: .magicwood, home: .club(.mossfoxes), away: .club(.rocketlynx), periodSeconds: 120))
        while m.state != .goal { m.tick() }
        let timers = m.players.map(\.thinkTimer)
        while m.state == .goal { m.tick() }
        #expect(m.state == .faceOff)
        #expect(m.ball.carrier == nil && m.ball.vel == .zero && m.ball.lastTouch == nil && m.ball.lastReleaser == nil)
        #expect(m.ball.assist == nil && m.ball.pending == nil && m.looseTimer == 0)
        #expect(m.ball.pos == Vec(x: 0, z: 0))
        for p in m.players {
            #expect(p.vel == .zero && p.target == nil && p.pickupCooldown == 0 && p.holdTime == 0)
            #expect(p.decision == nil && p.mark == nil && p.expectPass == 0 && p.stealContact == 0 && p.challengeUntil == 0)
        }
        #expect(m.players.map(\.thinkTimer) == timers)
        // §8.2: team 0's centre forward (slot 4) stands 1.5 behind the spot, team 1's goalie 1.3 out.
        #expect(m.players[4].pos == Vec(x: 0, z: -1.5))
        #expect(m.players[6].pos.x == 0 && abs(m.players[6].pos.z - 24.7) < 1e-12)
    }

    @Test func aDrillResetPutsEveryoneBackAndTheBallBehindThePlayer() {
        var m = Self.drill(.goalie)
        m.ball.carrier = nil
        m.ball.pos = Vec(x: 0, z: 23.2)
        m.ball.vel = .zero
        m.tick()
        #expect(m.drainEvents().contains(.drillInterrupted(.saved)))
        while m.state == .lost { m.tick() }
        #expect(m.state == .ready)
        #expect(m.players.map(\.pos) == m.players.map(\.start))
        #expect(m.ball.carrier == 0)
    }

    // MARK: §5.2 — snapping

    @Test func aPassSnapsWithinPoint36() {
        var m = Self.passAtRightAngle()
        #expect(m.snap(0, orbit: Pitch.pi / 2 + 0.35) == .pass(to: 1))
        #expect(m.snap(0, orbit: Pitch.pi / 2 - 0.35) == .pass(to: 1))
        #expect(m.snap(0, orbit: Pitch.pi / 2 + 0.37) == nil)
        m.players[1].vel = Vec(x: 0, z: 5)   // leads: t = 10 / 16.5, lead z = 0.8 × 5 × t
        let lead = Pitch.heading(10, 0.8 * 5 * (10 / 16.5))
        #expect(m.snap(0, orbit: lead + 0.355) == .pass(to: 1))
        #expect(m.snap(0, orbit: lead + 0.365) == nil)
    }

    @Test func theGoalWindowWidensFrom14To0Away() {
        var m = Self.passAtRightAngle()
        #expect(m.snap(0, orbit: 0.39) == .shot)       // 26 away: 0.40
        #expect(m.snap(0, orbit: 0.41) == nil)
        m.players[0].pos = Vec(x: 0, z: 19)             // 7 away: 0.40 + 0.30 × 0.5
        m.players[1].pos = Vec(x: 10, z: 19)
        #expect(m.snap(0, orbit: 0.54) == .shot)
        #expect(m.snap(0, orbit: 0.56) == nil)
    }

    @Test func theGoalBeatsAPassOnlyWhenClearlyCloserInAngleOrWithin9() {
        var m = Self.passAtRightAngle()
        m.players[1].pos = Vec(x: 10 * DetMath.sin(0.2), z: 10 * DetMath.cos(0.2))
        #expect(m.snap(0, orbit: 0.1) == .pass(to: 1))   // goal 0.1 is not < 0.9 × 0.1
        #expect(m.snap(0, orbit: 0.05) == .shot)         // 0.05 < 0.9 × 0.15
        m.players[0].pos = Vec(x: 0, z: 18)              // within 9: the goal wins
        m.players[1].pos = Vec(x: 10 * DetMath.sin(0.2), z: 18 + 10 * DetMath.cos(0.2))
        #expect(m.snap(0, orbit: 0.19) == .shot)
    }

    // MARK: §5.3 — late grace and pending

    @Test func aLiftJustAfterTheWindowGoesThroughTheLateGrace() {
        var m = Self.passAtRightAngle()
        m.ball.orbit = Pitch.pi / 2 + 0.36 + m.omega * 0.1
        #expect(m.previewLift() == .lateGrace)
        m.hold(true); m.hold(false); m.tick()
        #expect(m.drainEvents().contains(.pass(from: 0, to: 1)))
    }

    /// Team-mate 1 at (−10, 0): the pass at −π/2, approached by a positive orbit from below, with
    /// the goal (at 0) behind it and nothing behind the orbit.
    static func passAhead() -> Match {
        var m = passAtRightAngle()
        m.players[1].pos = Vec(x: -10, z: 0)
        m.ball.orbit = -Pitch.pi / 2 - 0.36 - m.omega * 0.12
        return m
    }

    @Test func aLiftJustBeforeTheWindowIsHeldPendingAndFiresOnTheSnap() {
        var m = Self.passAhead()
        #expect(m.previewLift() == .pending)
        m.hold(true); m.hold(false); m.tick()
        #expect(m.ball.pending != nil && m.ball.carrier == 0)
        m.hold(true)                                       // a new touch does not cancel it
        var fired: [MatchEvent] = []
        for _ in 0..<30 where fired.isEmpty { m.tick(); fired = m.drainEvents().filter { if case .pass = $0 { true } else { false } } }
        #expect(fired == [.pass(from: 0, to: 1)])
    }

    @Test func aPendingReleaseIsCancelledWhenThePlayerLosesTheBall() {
        var m = Self.passAhead()
        m.hold(true); m.hold(false); m.tick()
        #expect(m.ball.pending != nil)
        m.takeBall(1, reorient: true)
        #expect(m.ball.pending == nil)
    }

    @Test func aLiftWithNothingToSnapLeavesUnassistedAt24() {
        var m = Self.passAtRightAngle()
        m.ball.orbit = -Pitch.pi / 2
        #expect(m.previewLift() == .unassisted)
        m.hold(true); m.hold(false); m.tick()
        #expect(m.drainEvents().contains(.shot(by: 0, kind: .unassisted)))
        #expect(m.lastShotDistance != nil)
    }

    // MARK: §6.4 — steal timing

    @Test func aStealNeedsTheSettleWindowThenPoint18OfContact() {
        var m = Self.drill(.sleepy)
        let carrier = m.ball.carrier!
        let thief = m.rosters[1][1]
        m.ball.wonAt = m.time
        var steps = 0
        while m.ball.carrier == carrier && steps < 1000 {
            m.time += Self.dt
            m.players[thief].pos = m.ball.pos
            m.checkSteal(from: carrier, Self.dt)
            steps += 1
        }
        let settle = Int((Tuning.Ball.settleTime / Self.dt).rounded())      // 108
        let contact = Int((Tuning.Ball.stealTime / Self.dt).rounded(.up))    // 44
        #expect(abs(steps - (settle + contact)) <= 1, "stole after \(steps) steps")
        #expect(m.ball.carrier == thief)
        #expect(m.players[carrier].pickupCooldown == Tuning.Ball.stealLoserCooldown)
    }

    @Test func contactIsLostTwiceAsFastOutOfReach() {
        var m = Self.drill(.sleepy)
        let carrier = m.ball.carrier!
        let thief = m.rosters[1][1]
        m.ball.wonAt = m.time - 1
        m.players[thief].pos = m.ball.pos
        for _ in 0..<20 { m.checkSteal(from: carrier, Self.dt) }
        m.players[thief].pos = Vec(x: m.ball.pos.x + 5, z: m.ball.pos.z)
        for _ in 0..<5 { m.checkSteal(from: carrier, Self.dt) }
        #expect(abs(m.players[thief].stealContact - 10 * Self.dt) < 1e-12)
        for _ in 0..<6 { m.checkSteal(from: carrier, Self.dt) }
        #expect(m.players[thief].stealContact == 0)
        #expect(m.ball.carrier == carrier)
    }

    // MARK: §10 — drill rules

    @Test func theWrongNetInterruptsADrill() {
        var m = Self.drill(.shot)
        m.ball.carrier = nil
        m.ball.lastTouch = 0
        m.ball.pos = Vec(x: 0, z: -24)
        m.ball.vel = Vec(x: 0, z: -25)
        for _ in 0..<30 { m.tick() }
        #expect(m.drainEvents().contains(.drillInterrupted(.wrongNet)))
        #expect(m.score == [0, 0] && m.state == .lost)
    }

    @Test func theGiveAndGoCountsOnlyAssistedGoals() {
        var m = Self.drill(.pass)
        m.players[0].pos = Vec(x: 0, z: 14)
        m.ball.orbit = 0
        m.shoot(0, accuracy: 1, power: 30)
        for _ in 0..<60 { m.tick() }
        #expect(m.drainEvents().contains(.drillInterrupted(.noAssist)))
        #expect(m.score == [0, 0])

        var n = Self.drill(.pass)
        n.ball.carrier = nil
        n.ball.lastTouch = 1
        n.takeBall(0, reorient: true)
        n.players[0].pos = Vec(x: 0, z: 14)
        n.shoot(0, accuracy: 1, power: 30)
        for _ in 0..<60 { n.tick() }
        #expect(n.drainEvents().contains(.goal(team: 0, scorer: 0, assist: 1, ownGoal: false)))
        #expect(n.score == [1, 0])
    }

    @Test func theDefenceTakingTheBallInterruptsWithTheReason() {
        var m = Self.drill(.sleepy)
        m.ball.carrier = nil
        m.ball.pos = Vec(x: m.players[m.rosters[1][1]].pos.x, z: m.players[m.rosters[1][1]].pos.z - 1.2)
        m.ball.vel = .zero
        m.tick()
        #expect(m.drainEvents().contains(.drillInterrupted(.stolen)))
    }

    @Test func aDrillIsLostWhenTheClockRunsOut() {
        var m = Match(DrillSetup(drill: .shot, seed: 1, tactics: .defaults, orbitPeriod: 2))
        while m.state != .ended { m.tick() }
        #expect(m.result == .lost && m.clock == 0)
        #expect(abs(m.ticks - Int((Tuning.Training.ready + Drill.shot.seconds) * 120)) <= 1)
    }

    @Test func aBallNobodyCollectsResetsADrill() {
        var m = Self.drill(.shot)
        m.ball.carrier = nil
        m.ball.pos = Vec(x: 0, z: -27.2)            // inside the net's frame: pushed out behind it
        m.ball.vel = .zero
        var reasons: [MatchEvent] = []
        for _ in 0..<(9 * 120) { m.tick(); reasons += m.drainEvents() }
        #expect(reasons.contains(.drillInterrupted(.deadBall)))
    }

    // MARK: §8.6 — what presentation reads

    @Test func aShotAboutToScoreIsReported() {
        var m = Self.drill(.shot)
        m.ball.carrier = nil
        m.ball.pos = Vec(x: 1, z: 20)
        m.ball.vel = Vec(x: 0, z: 20)
        #expect(m.shotAboutToScore)
        m.ball.vel = Vec(x: 0, z: 5)
        #expect(!m.shotAboutToScore)
        m.ball.vel = Vec(x: 20, z: 20)
        #expect(!m.shotAboutToScore)
    }

    // MARK: §7.10 — the rubberband

    /// The temperament is drawn once, in range, and is the seed's — and a drill has none.
    @Test func aMatchDrawsOneTemperamentAndADrillDrawsNone() {
        var m = Match(Self.match)
        let drawn = m.temperament
        #expect(drawn >= 0 && drawn <= Tuning.AI.Balance.temperamentMax)
        #expect(Match(Self.match).temperament == drawn)
        for _ in 0..<600 { m.tick() }
        #expect(m.temperament == drawn)
        #expect(Self.drill(.shot).temperament == 0)
    }

    /// Level, or one goal in it, and the board's numbers reach §7 untouched — to the bit.
    @Test func aCloseScoreLeavesEveryTacticExactlyAsTheBoardSetIt() {
        var m = Match(Self.match)
        for lead in [0, 1, -1] {
            m.score = [lead > 0 ? lead : 0, lead < 0 ? -lead : 0]
            m.period = 3
            m.clock = 0
            m.updateBalance()
            for team in 0..<2 {
                #expect(m.chase(team) == 0)
                #expect(m.hold(team) == 0)
                #expect(m.effectiveTactics(team) == m.tactics[team])
            }
        }
    }

    /// It helps whoever is behind, whichever side that is, by the same amount.
    @Test func theTiltIsSymmetricBetweenTheTwoSides() {
        var m = Match(Self.match)
        m.temperament = 1.0
        m.period = 2
        m.score = [5, 1]
        m.updateBalance()
        let chasing = m.chase(1)
        let holding = m.hold(0)
        #expect(chasing > 0 && chasing == holding)
        m.score = [1, 5]
        m.updateBalance()
        #expect(m.chase(0) == chasing)
        #expect(m.hold(1) == holding)
    }

    /// It grows with the lead and with the clock, and never past 1.
    @Test func theTiltGrowsWithTheLeadAndTheClock() {
        var m = Match(Self.match)
        m.temperament = 1.0
        func tilt(score: [Int], period: Int, clock: Double) -> Double {
            m.score = score; m.period = period; m.clock = clock
            m.updateBalance()
            return m.chase(1)
        }
        let early2 = tilt(score: [2, 0], period: 1, clock: 60)
        let late2 = tilt(score: [2, 0], period: 3, clock: 0)
        let late4 = tilt(score: [4, 0], period: 3, clock: 0)
        #expect(early2 > 0 && early2 < late2 && late2 <= late4)
        #expect(late4 <= Tuning.AI.Balance.tiltMax)
        m.temperament = Tuning.AI.Balance.temperamentMax
        #expect(tilt(score: [9, 0], period: 3, clock: 0) == Tuning.AI.Balance.tiltMax)
    }

    /// Only ever sharper, never softer (A0): the side ahead keeps its keeper and its marking, and
    /// loses only appetite — pressing, push up, shooting.
    @Test func theSideAheadIsNeverMadeWorseAtDefending() {
        var m = Match(Self.match)
        m.temperament = Tuning.AI.Balance.temperamentMax
        m.score = [6, 0]
        m.period = 3
        m.clock = 0
        m.updateBalance()
        let ahead = m.effectiveTactics(0)
        let behind = m.effectiveTactics(1)
        #expect(ahead.covering == m.tactics[0].covering)          // never dulled
        #expect(ahead.pressing < m.tactics[0].pressing)
        #expect(ahead.pushUp < m.tactics[0].pushUp)
        #expect(ahead.shooting < m.tactics[0].shooting)
        #expect(ahead.discipline > m.tactics[0].discipline)
        #expect(behind.covering > m.tactics[1].covering)
        #expect(behind.pressing > m.tactics[1].pressing)
        #expect(behind.pushUp > m.tactics[1].pushUp)
        #expect(behind.shooting == m.tactics[1].shooting)
    }

    /// A drill never tilts, whatever its score (§10).
    @Test func aDrillNeverTilts() {
        var m = Self.drill(.shot)
        m.score = [5, 0]
        m.updateBalance()
        #expect(m.chase(0) == 0 && m.chase(1) == 0 && m.hold(0) == 0 && m.hold(1) == 0)
    }

    // MARK: Performance (§4)

    @Test func aFullMatchRunsFarFasterThanRealTime() {
        let clock = ContinuousClock()
        var m = Match(MatchSetup.demo(seed: 9, world: .magicwood, home: .club(.mossfoxes), away: .club(.nebula), periodSeconds: 120))
        let elapsed = clock.measure { while m.state != .ended { m.tick() } }
        let simulated = Double(m.ticks) * Tuning.Time.tickSeconds
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        print("full 3 × 120 s match: \(m.ticks) ticks (\(simulated) s) in \(seconds) s — \(Int(simulated / seconds))× real time")
        #expect(simulated / seconds > 10)
    }
}
