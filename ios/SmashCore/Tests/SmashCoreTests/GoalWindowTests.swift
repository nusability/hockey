import Testing
@testable import SmashCore

/// §5.2: the goal is as wide a target as it actually looks. The twin of Android's
/// `GoalWindowTest.kt`.
@Suite struct GoalWindowTests {
    static let dt = Tuning.Time.stepSeconds

    /// A drill match with the carrier and one team-mate placed by hand and everyone else parked, so
    /// only those two are candidates for a snap.
    static func twoPlayers(carrierAt me: Vec, mateAt mate: Vec) -> (Match, carrier: Int, mate: Int) {
        let side = SideSetup(rating: 75, tactics: .defaults, formation: Formation.allCases[0])
        var m = Match(MatchSetup(seed: 5, sport: .field, home: side, away: side, periodSeconds: 120,
                                 orbitPeriod: 2.0, cup: false, control: .player))
        while m.state != .play { m.tick() }
        _ = m.drainEvents()
        let mine = m.players.indices.filter { m.players[$0].team == 0 && m.players[$0].isOutfield }
        let c = mine[0], mate2 = mine[1]
        for i in m.players.indices where i != c && i != mate2 {
            m.players[i].pos = Vec(x: 13, z: Double(i) * 0.9 - 28)
            m.players[i].vel = .zero
        }
        m.players[c].pos = me
        m.players[c].vel = .zero
        m.players[mate2].pos = mate
        m.players[mate2].vel = .zero
        m.ball.carrier = c
        return (m, c, mate2)
    }

    static func radians(_ degrees: Double) -> Double { degrees * Pitch.pi / 180 }

    /// The window at a distance, as §5.2 states it.
    static func window(at d: Double) -> Double {
        typealias O = Tuning.Orbit
        return Pitch.clamp(DetMath.atan2(Tuning.Pitch.goalMouthWidth / 2 * O.goalAimGenerosity, d),
                           O.goalWindowMin, O.goalWindowMax)
    }

    @Test func theWindowIsTheGoalsOwnAngularHalfSize() {
        // It shrinks with distance — the property the old flat window did not have.
        var previous = Double.infinity
        for d in [3.0, 5, 9, 14, 20, 26, 35, 45] {
            let w = Self.window(at: d)
            #expect(w < previous, "the window did not shrink from \(previous) at \(d) away")
            previous = w
        }
        // And it is the arctangent, not something near it.
        #expect(Self.window(at: 20) == DetMath.atan2(3.0 * 1.25, 20))
        // Clamped at both ends.
        #expect(Self.window(at: 0.5) == Tuning.Orbit.goalWindowMax)
        #expect(Self.window(at: 1000) == Tuning.Orbit.goalWindowMin)
    }

    /// The owner's case: deep in your own half, a short pass to a team-mate 20° off the line to the
    /// far goal, and the release lands a little early. It must stay a pass.
    @Test func aReleaseMeantForATeamMateIsNotTakenByAGoalFortyMetresAway() {
        // The carrier stands on x = 0, so the goal it attacks lies at orbit angle 0 from here.
        let me = Vec(x: 0, z: -20)
        let mateAngle = Self.radians(20)
        let mate = Vec(x: 12 * DetMath.sin(mateAngle), z: -20 + 12 * DetMath.cos(mateAngle))
        var (m, c, _) = Self.twoPlayers(carrierAt: me, mateAt: mate)
        let dGoal = Pitch.length(0 - me.x, Pitch.attackGoalZ(0) - me.z)
        #expect(dGoal > 40, "the case is meant to be a long way out (\(dGoal))")

        // Let go anywhere from dead on the mate to 17° off it, toward the goal line.
        for offDegrees in [0.0, 5, 8, 11, 14, 17] {
            m.ball.orbit = Self.radians(20 - offDegrees)
            #expect(m.snap(c, orbit: m.ball.orbit) != .shot,
                    "released \(offDegrees)° off the mate and the goal took it")
        }
        // And aimed straight down the line at the goal it is STILL not a shot: from your own half
        // the goal is not offered at all. The release is free — the ball goes where the arrow
        // points, it is simply not an assisted shot on goal.
        m.ball.orbit = 0
        #expect(m.snap(c, orbit: 0) != .shot, "the goal was offered from the carrier's own half")
    }

    /// The other side of that: one step inside the attacking half, the goal is a target again.
    @Test func justInsideTheAttackingHalfTheGoalIsOfferedAgain() {
        typealias O = Tuning.Orbit
        let gz = Pitch.attackGoalZ(0)
        // Carrier on x = 0, so the goal lies at orbit angle 0; put it either side of the range.
        for (distance, wanted) in [(O.goalSnapRange - 0.5, true), (O.goalSnapRange + 0.5, false)] {
            var (m, c, _) = Self.twoPlayers(carrierAt: Vec(x: 0, z: gz - distance),
                                            mateAt: Vec(x: 9, z: gz - distance - 6))
            m.ball.orbit = 0
            #expect((m.snap(c, orbit: 0) == .shot) == wanted,
                    "at \(distance) from goal the shot snap was \(m.snap(c, orbit: 0).debugDescription)")
        }
    }

    /// Close in, nothing should have got harder: the mouth really is that big from there.
    @Test func closeInTheGoalIsAtLeastAsEasyToAimAtAsItWas() {
        for d in [2.0, 3, 4, 5] {
            // What the old rule gave: 0.40 widened by up to 0.30 closing from 14.
            let old = 0.40 + 0.30 * Pitch.clamp((14 - d) / 14, 0, 1)
            #expect(Self.window(at: d) >= old, "the window narrowed at \(d) away")
        }
    }

    /// And the far half of the same statement: from range it is much tighter than it was.
    @Test func fromRangeTheWindowIsAFractionOfWhatItWas() {
        for d in [20.0, 26, 35, 45] {
            #expect(Self.window(at: d) < 0.40 * 0.5, "the window is still wide at \(d) away")
        }
    }

    /// A0: the arrow cannot disagree with the release, because both read this one function. A shot
    /// snap and a shot release must come from the same test — so a release at an angle that snaps to
    /// a shot must actually leave as one.
    @Test func whatSnapsToAShotLeavesAsAShot() {
        // Inside the attacking half, where a shot is a shot.
        let me = Vec(x: 0, z: 8)
        var (m, c, _) = Self.twoPlayers(carrierAt: me, mateAt: Vec(x: 9, z: 14))
        m.ball.orbit = 0
        #expect(m.snap(c, orbit: 0) == .shot)
        m.hold(true)
        m.tick()
        m.hold(false)
        for _ in 0..<12 { m.tick() }
        let shots = m.drainEvents().filter { if case .shot = $0 { return true } else { return false } }
        #expect(!shots.isEmpty, "the snap said shot and no shot was emitted")
    }
}
