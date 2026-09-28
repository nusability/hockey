import Testing
@testable import SmashCore

/// §5.4: the player's own shot goes where the arrow was pointing; an AI carrier's still goes to the
/// far side of the keeper. The twin of Android's `ShotAimTest.kt`.
@Suite struct ShotAimTests {
    static let gz = Pitch.attackGoalZ(0)                     // 26 — the goal team 0 attacks
    static let half = Tuning.Pitch.postX - Tuning.Release.shotPostInset   // 2.15

    static func match(control: Control = .player) -> Match {
        let side = SideSetup(rating: 75, tactics: .defaults, formation: Formation.allCases[0])
        return Match(MatchSetup(seed: 7, sport: .field, home: side, away: side, periodSeconds: 60,
                                orbitPeriod: 2.0, cup: false, control: control))
    }

    /// A carrier of the player's team `distance` out from the goal, the keeper parked at `keeperX`,
    /// the orbit set so the arrow points at `aimAt` on the goal line.
    static func rig(_ m: inout Match, distance: Double, keeperX: Double, aimAt: Double) -> Int {
        let c = m.outfield(0).first!
        m.state = .play
        m.players[c].pos = Vec(x: 0, z: gz - distance)
        m.players[c].vel = .zero
        if let g = m.goalie(of: 1) {
            m.players[g].pos = Vec(x: keeperX, z: gz - 1.2)
            m.players[g].vel = .zero
        }
        m.ball.carrier = c
        m.ball.orbitDirection = 1
        m.ball.orbit = Pitch.heading(aimAt - m.players[c].pos.x, gz - m.players[c].pos.z)
        m.ball.pos = m.orbitPoint(c)
        return c
    }

    /// Where the ball, having just left, crosses the goal line.
    static func crossing(_ m: Match) -> Double? {
        guard m.ball.carrier == nil, m.ball.vel.z != 0 else { return nil }
        let t = (gz - m.ball.pos.z) / m.ball.vel.z
        guard t > 0 else { return nil }
        return m.ball.pos.x + m.ball.vel.x * t
    }

    /// The owner's case, and the whole of the change: the arrow past the keeper, on the keeper's own
    /// side. The old rule sent every one of these to the other side.
    @Test func thePlayersShotGoesToTheSideTheArrowChose() {
        var wrongSide = 0
        var samples = 0
        var worstMiss = 0.0
        for keeperX in [-1.8, -0.9, 0.9, 1.8] {
            for distance in [7.0, 12.0, 18.0] {
                for k in -7...7 {
                    let aimAt = Double(k) * 0.35
                    if (aimAt - keeperX).magnitude < 0.5 { continue }   // "at the keeper" has no side
                    for _ in 0..<40 {
                        var m = Self.match()
                        _ = Self.rig(&m, distance: distance, keeperX: keeperX, aimAt: aimAt)
                        m.playerLift()
                        guard let x = Self.crossing(m) else { continue }
                        samples += 1
                        if (x - keeperX).sign != (aimAt - keeperX).sign { wrongSide += 1 }
                        worstMiss = Pitch.greater(worstMiss, (x - aimAt).magnitude)
                    }
                }
            }
        }
        #expect(samples > 2000)
        #expect(wrongSide == 0, "\(wrongSide) of \(samples) shots went to the other side of the keeper")
        // Only the noise of an accuracy-1 release (±0.3) and the orbit point's offset stand between
        // the spot aimed at and the spot hit.
        #expect(worstMiss < 0.8, "worst miss \(worstMiss) m from the spot aimed at")
    }

    /// The point the shot was *aimed* at, read back off its direction — which §5.4 measures from the
    /// carrier, not from the orbit point the ball leaves from. With a standing carrier this is the
    /// aim point exactly, so it is what to assert the clamp on.
    static func aimedAt(_ m: Match, _ c: Int) -> Double? {
        guard m.ball.carrier == nil, m.ball.vel.z != 0 else { return nil }
        let run = gz - m.players[c].pos.z
        guard m.ball.vel.z * run > 0 else { return nil }
        return m.players[c].pos.x + m.ball.vel.x * (run / m.ball.vel.z)
    }

    /// The assistance that stays: a release aimed outside the mouth still snaps to a shot (§5.2's
    /// window is a little wider than the goal), and it is kept off the post rather than sent wide.
    @Test func anArrowOutsideTheMouthIsKeptOffThePost() {
        var tested = 0
        for aimAt in [-4.0, -3.2, 3.2, 4.0] {
            var m = Self.match()
            let c = Self.rig(&m, distance: 12, keeperX: 0, aimAt: aimAt)
            guard m.snap(c, orbit: m.ball.orbit) == .shot else { continue }
            m.playerLift()
            guard let x = Self.aimedAt(m, c) else { continue }
            tested += 1
            // The clamp, plus the ±0.3 noise of an accuracy-1 release.
            #expect(x.magnitude <= Self.half + 0.31, "aimed \(aimAt), shot aimed at \(x)")
            #expect(x.sign == aimAt.sign)
        }
        #expect(tested > 0, "no release outside the mouth snapped to a shot — the case is untested")
    }

    /// An AI carrier has no arrow (§7.6), so the keeper still decides: the far side, every time.
    @Test func anAICarriersShotStillTakesTheFarSideOfTheKeeper() {
        for keeperX in [-1.8, 1.8] {
            var sameSideAsKeeper = 0
            for _ in 0..<200 {
                var m = Self.match(control: .automatic)
                // Aimed straight at the keeper — under the old rule and this one alike, an AI shot
                // ignores that and goes the other way.
                let c = Self.rig(&m, distance: 12, keeperX: keeperX, aimAt: keeperX)
                m.shoot(c, accuracy: 1, power: Tuning.Release.shotSpeed, aim: nil)
                guard let x = Self.crossing(m) else { continue }
                if x.sign == keeperX.sign { sameSideAsKeeper += 1 }
            }
            // The 25 % pull to 30 % of the corner can cross the middle once noise is added; the far
            // side is still where the great majority go.
            #expect(sameSideAsKeeper < 40, "\(sameSideAsKeeper)/200 AI shots went to the keeper's side")
        }
    }

    /// §5.3 rule 2 winds the orbit back to find a snap. That wound-back angle is the one the player
    /// released on, so it is the one that aims — not the angle the orbit has moved on to.
    @Test func theLateGraceAimsFromTheAngleThatSnapped() {
        var m = Self.match()
        let c = Self.rig(&m, distance: 12, keeperX: 1.8, aimAt: 0)
        // Just outside the goal window now, inside it one late-grace step ago.
        let toGoal = Pitch.heading(0 - m.players[c].pos.x, Self.gz - m.players[c].pos.z)
        let window = Pitch.clamp(DetMath.atan2(Tuning.Pitch.goalMouthWidth / 2 * Tuning.Orbit.goalAimGenerosity, 12),
                                 Tuning.Orbit.goalWindowMin, Tuning.Orbit.goalWindowMax)
        m.ball.orbit = Pitch.wrap(toGoal + window + 0.02)
        m.ball.pos = m.orbitPoint(c)
        #expect(m.snap(c, orbit: m.ball.orbit) == nil)
        let late = m.lateSnap(c)
        #expect(late?.snap == .shot)
        let aimedAt = m.goalLineCrossing(c, orbit: late!.orbit, goalZ: Self.gz)
        let nowAt = m.goalLineCrossing(c, orbit: m.ball.orbit, goalZ: Self.gz)
        // The two angles really do point at different parts of the goal, or this proves nothing.
        #expect((aimedAt! - nowAt!).magnitude > 0.5)
        m.playerLift()
        let x = Self.crossing(m)!
        #expect((x - Pitch.clamp(aimedAt!, -Self.half, Self.half)).magnitude < 0.8,
                "shot crossed \(x); the angle that snapped aimed at \(aimedAt!), the one now at \(nowAt!)")
    }

    /// The geometry itself: measured from the carrier, and nil when the release never meets the line.
    @Test func theCrossingIsMeasuredFromTheCarrier() {
        var m = Self.match()
        let c = Self.rig(&m, distance: 10, keeperX: 0, aimAt: 0)
        m.players[c].pos = Vec(x: 1, z: Self.gz - 10)
        // Straight up the pitch from (1, 16): crosses the line at x = 1, whatever the ball is doing.
        #expect((m.goalLineCrossing(c, orbit: 0, goalZ: Self.gz)! - 1).magnitude < 1e-9)
        // Pointing back up the pitch, away from that line: no crossing at all.
        #expect(m.goalLineCrossing(c, orbit: Pitch.wrap(Pitch.twoPi / 2), goalZ: Self.gz) == nil)
        // Along the line is not a special case: the crossing runs away to a huge x, and the clamp
        // in `shoot` takes it to the post on that side. Nothing here divides by zero or goes NaN.
        let alongTheLine = m.goalLineCrossing(c, orbit: Pitch.twoPi / 4, goalZ: Self.gz)!
        #expect(alongTheLine.isFinite && alongTheLine.magnitude > 1e6)
        #expect(Pitch.clamp(alongTheLine, -Self.half, Self.half) == Self.half)
    }
}
