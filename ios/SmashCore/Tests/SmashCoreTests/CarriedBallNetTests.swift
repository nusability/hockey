import Testing
@testable import SmashCore

/// §5.1: the ball on a carrier's orbit is kept out of both nets' cloth, by the nearest of the net's
/// three ways out, without the orbit angle or any aim moving. The twin of Android's
/// `CarriedBallNetTest.kt`.
@Suite struct CarriedBallNetTests {
    static let gz = Pitch.ownGoalZ(1)                 // 26 — the goal team 0 attacks
    static let dir = Pitch.direction(1)               // −1: into this net is +z
    static let hw = Tuning.Pitch.goalMouthWidth / 2 + Tuning.Pitch.netFrameMargin
    static let deep = Tuning.Pitch.goalDepth + Tuning.Pitch.netFrameMargin

    /// How far inside the cloth a point is; 0 or less when it is clear of it.
    static func insideBy(_ p: Vec, radius r: Double) -> Double {
        let into = -dir * (p.z - gz)
        guard p.x.magnitude < hw + r && into > -r && into < deep + r else { return 0 }
        return Pitch.lesser(Pitch.lesser(into + r, deep + r - into), hw + r - p.x.magnitude)
    }

    static func match() -> Match {
        let side = SideSetup(rating: 50, tactics: .defaults, formation: Formation.allCases[0])
        return Match(MatchSetup(seed: 1, sport: .field, home: side, away: side, periodSeconds: 60,
                                orbitPeriod: 2.0, cup: false, control: .automatic))
    }

    /// The whole point: a carrier standing anywhere the rules allow, with the orbit swept right
    /// round, never puts the ball in the cloth.
    @Test func noCarrierAnywhereCanPutTheBallInTheCloth() {
        var m = Self.match()
        m.ball.carrier = 0
        var worst = 0.0
        var at = Vec.zero
        for xi in -60...60 {
            for zi in -40...40 {
                let spot = Vec(x: Double(xi) * 0.25, z: Self.gz - Self.dir * (Double(zi) * 0.25))
                m.players[0].pos = spot
                m.constrainPlayers()
                // Only spots a player may actually stand in count.
                guard (m.players[0].pos.x - spot.x).magnitude < 1e-12,
                      (m.players[0].pos.z - spot.z).magnitude < 1e-12 else { continue }
                for step in 0..<72 {
                    m.ball.orbit = Pitch.wrap(Double(step) * Pitch.twoPi / 72)
                    let d = Self.insideBy(m.orbitPoint(0), radius: m.sport.ballRadius)
                    if d > worst { worst = d; at = m.orbitPoint(0) }
                }
            }
        }
        // The clamp puts the ball exactly on the cloth's plane, and a plane cannot be landed on
        // exactly in binary — an epsilon either side of it is the arithmetic, not a way through.
        #expect(worst <= 1e-12, "ball reached \(worst) into the cloth at (\(at.x), \(at.z))")
    }

    @Test func aBallBehindTheNetLeavesByTheBack() {
        // A point 0.1 inside the back panel, well away from both sides.
        let p = Vec(x: 0.5, z: Self.gz - Self.dir * (Self.deep - 0.1))
        let out = Pitch.pushOutOfNet(p, team: 1, radius: Self.ballRadius)
        #expect(out.x == p.x)                                       // straight out, no sideways shove
        #expect(out.z == Self.gz - Self.dir * (Self.deep + Self.ballRadius))
    }

    @Test func aBallBesideTheNetLeavesBySideNotByTheLongWayRound() {
        // Deep in the net but a hand's width from the side panel: the side is nearest.
        let p = Vec(x: Self.hw - 0.05, z: Self.gz - Self.dir * (Self.deep / 2))
        let out = Pitch.pushOutOfNet(p, team: 1, radius: Self.ballRadius)
        #expect(out.z == p.z)
        #expect(out.x == Self.hw + Self.ballRadius)
    }

    /// The case that makes the mouth one of the three: a carrier a metre in front of the goal line
    /// has its ball swing over the line, and shoving it out of the back instead would teleport it
    /// the length of the net.
    @Test func aBallJustInsideTheMouthLeavesByTheMouth() {
        let p = Vec(x: 0, z: Self.gz - Self.dir * 0.2)
        let out = Pitch.pushOutOfNet(p, team: 1, radius: Self.ballRadius)
        #expect(out.x == 0)
        #expect(out.z == Self.gz + Self.dir * Self.ballRadius)
        // And it really is the short way: the back would have been over a metre and a half.
        #expect((out.z - p.z).magnitude < 1.0)
    }

    @Test func aBallClearOfTheNetIsNotMovedAtAll() {
        for p in [Vec(x: 0, z: 0), Vec(x: 0, z: Self.gz - Self.dir * -2),
                  Vec(x: Self.hw + Self.ballRadius + 0.01, z: Self.gz - Self.dir * 0.5),
                  Vec(x: 0, z: Self.gz - Self.dir * (Self.deep + Self.ballRadius + 0.01))] {
            let out = Pitch.pushOutOfNet(p, team: 1, radius: Self.ballRadius)
            #expect(out == p, "(\(p.x), \(p.z)) was moved to (\(out.x), \(out.z))")
        }
    }

    /// A0: the clamp moves the ball, never the aim. `snap` reads the carrier's position and the orbit
    /// angle, so a carrier whose ball is being held out of the net still aims where the arrow says.
    @Test func theAimIsUnchangedByTheClamp() {
        var m = Self.match()
        m.ball.carrier = 0
        // Behind the net, where the clamp bites hardest.
        m.players[0].pos = Vec(x: 0, z: Self.gz - Self.dir * (Self.deep + m.players[0].radius + 0.01))
        m.constrainPlayers()
        for step in 0..<72 {
            let a = Pitch.wrap(Double(step) * Pitch.twoPi / 72)
            m.ball.orbit = a
            let clamped = m.orbitPoint(0)
            // The snap at this angle is a pure function of the carrier and the angle — the ball's
            // clamped position is not one of its inputs.
            let before = m.snap(0, orbit: a)
            m.ball.pos = clamped
            #expect(m.snap(0, orbit: a) == before)
        }
    }

    static let ballRadius = Sport.field.ballRadius
}
