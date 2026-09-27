import Testing
@testable import SmashCore

/// §5.4: every release leaves **from the orbit point** — the one §5.1 has already kept out of both
/// nets — and from nowhere else. The twin of Android's `ReleasePointTest.kt`.
@Suite struct ReleasePointTests {
    static func match() -> Match {
        let side = SideSetup(rating: 50, tactics: .defaults, formation: Formation.allCases[0])
        return Match(MatchSetup(seed: 1, sport: .field, home: side, away: side, periodSeconds: 60,
                                orbitPeriod: 2.0, cup: false, control: .automatic))
    }

    /// The bug this test exists for: a carrier standing behind a net released the ball **through the
    /// cloth**, in front of the goal line, because §5.4 used to pull a release point with |z| > 25.7
    /// back to within 25.5. Nothing may move the ball at the moment it leaves.
    @Test func aReleaseFromBehindANetDoesNotJumpThroughIt() {
        var m = Self.match()
        m.ball.carrier = 0
        let gz = Pitch.ownGoalZ(0)                              // −26, the net team 0 defends
        let dir = Pitch.direction(0)                            // into this net is −z
        let deep = Tuning.Pitch.goalDepth + Tuning.Pitch.netFrameMargin
        var jumped = 0
        for xi in -14...14 {
            for zi in 0...8 {
                let spot = Vec(x: Double(xi) * 0.25,
                               z: gz - dir * (deep + m.players[0].radius + 0.05 + Double(zi) * 0.25))
                m.players[0].pos = spot
                m.constrainPlayers()
                guard (m.players[0].pos.x - spot.x).magnitude < 1e-12,
                      (m.players[0].pos.z - spot.z).magnitude < 1e-12 else { continue }
                for step in 0..<72 {
                    m.ball.orbit = Pitch.wrap(Double(step) * Pitch.twoPi / 72)
                    m.ball.pos = m.orbitPoint(0)
                    var n = m
                    n.releaseUnassisted(0, kind: .unassisted)
                    // Behind the line is where the ball was; in front of it is through the net.
                    if -dir * (n.ball.pos.z - gz) <= 0 { jumped += 1 }
                }
            }
        }
        #expect(jumped == 0, "\(jumped) releases from behind the net put the ball in front of it")
    }

    /// The general contract, both nets, every standable spot near them: the ball leaves from exactly
    /// where it stands. §5.1 is the only thing that ever moves it, and it has already run.
    @Test func aReleaseLeavesFromWhereTheBallStands() {
        var m = Self.match()
        m.ball.carrier = 0
        for team in 0..<2 {
            let gz = Pitch.ownGoalZ(team)
            let dir = Pitch.direction(team)
            for xi in -24...24 {
                for zi in -8...16 {
                    let spot = Vec(x: Double(xi) * 0.25, z: gz - dir * (Double(zi) * 0.25))
                    m.players[0].pos = spot
                    m.constrainPlayers()
                    guard (m.players[0].pos.x - spot.x).magnitude < 1e-12,
                          (m.players[0].pos.z - spot.z).magnitude < 1e-12 else { continue }
                    for step in 0..<24 {
                        m.ball.orbit = Pitch.wrap(Double(step) * Pitch.twoPi / 24)
                        let from = m.orbitPoint(0)
                        m.ball.pos = from
                        var n = m
                        n.releaseUnassisted(0, kind: .unassisted)
                        #expect(n.ball.pos == from,
                                "released from (\(n.ball.pos.x), \(n.ball.pos.z)) not (\(from.x), \(from.z))")
                    }
                }
            }
        }
    }
}
