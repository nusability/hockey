import Testing
@testable import SmashCore

/// §7.8: a goalie reads a **shot** — a loose ball that will cross its line within the horizon — and
/// nothing else. The twin of Android's `GoalieReadTest.kt`.
@Suite struct GoalieReadTests {
    static let team = 1                                   // the goal team 0 attacks
    static var gz: Double { Pitch.ownGoalZ(team) }
    static var dir: Double { Pitch.direction(team) }      // −1: toward this goal is +z

    /// A match in play with everyone parked out of the way, so only the ball moves the keeper.
    static func inPlay() -> (Match, Int) {
        let side = SideSetup(rating: 75, tactics: .defaults, formation: Formation.allCases[0])
        var m = Match(MatchSetup(seed: 3, sport: .field, home: side, away: side, periodSeconds: 120,
                                 orbitPeriod: 2.0, cup: false, control: .automatic))
        while m.state != .play { m.tick() }
        _ = m.drainEvents()
        let g = m.players.indices.first { m.players[$0].team == team && m.players[$0].isGoalie }!
        for i in m.players.indices where i != g {
            m.players[i].pos = Vec(x: 13, z: Double(i) * 0.9 - 28)
            m.players[i].vel = .zero
        }
        m.ball.carrier = nil
        m.ball.lastReleaseTime = nil                      // no reaction delay in the way
        return (m, g)
    }

    /// Where §7.8's positioning line alone would put the keeper — the shading it does at range.
    static func lineOnly(_ m: Match, _ g: Int) -> Double {
        typealias G = Tuning.AI.Goalie
        let toBall = Pitch.unit(m.ball.pos.x, m.ball.pos.z - gz)
        let out = G.outBase + G.outPerSkill * m.skill[team]
        return Pitch.clamp(toBall.x * out * G.xScale, -(Tuning.Pitch.postX + G.xLimitExtra),
                           Tuning.Pitch.postX + G.xLimitExtra)
    }

    static func keeperTargetX(_ m: inout Match, _ g: Int) -> Double {
        m.thinkGoalie(g, Tuning.Time.stepSeconds)
        return m.players[g].target!.x
    }

    /// The bug this rule was rewritten for: a player carrying the ball at the goal is not a shot,
    /// however fast they skate. The keeper shades toward them and no more.
    @Test func aCarriedBallIsNeverReadAsAShot() {
        var (m, g) = Self.inPlay()
        // A carrier 25 out, well to one side, bearing down at speed.
        let carrier = m.players.indices.first { m.players[$0].team == 0 && m.players[$0].isOutfield }!
        m.players[carrier].pos = Vec(x: 5, z: Self.gz - Self.dir * -25)
        m.players[carrier].vel = Vec(x: 0, z: -Self.dir * 7)
        m.ball.carrier = carrier
        m.ball.pos = m.orbitPoint(carrier)
        m.ball.vel = m.players[carrier].vel
        let x = Self.keeperTargetX(&m, g)
        #expect(x == Self.lineOnly(m, g), "a carried ball moved the keeper off its line")
        // And the shading really is gentle: nowhere near the post it used to be dragged to.
        #expect(x.magnitude < 1.5, "the keeper shaded \(x) — that is a commitment, not a shade")
    }

    /// The other half: a loose ball that will not arrive is not a shot either. This is the branch
    /// that used to fall back to the ball's *current* x.
    @Test func aLooseBallThatWillNotArriveIsNotReadEither() {
        var (m, g) = Self.inPlay()
        // 30 out, drifting goalward at 5 m/s: six seconds away, well past the 2.5 s horizon.
        m.ball.pos = Vec(x: 6, z: Self.gz - Self.dir * -30)
        m.ball.vel = Vec(x: 0, z: -Self.dir * 5)
        let x = Self.keeperTargetX(&m, g)
        #expect(x == Self.lineOnly(m, g), "a ball six seconds away moved the keeper off its line")
    }

    /// And the rule still does its job: a real shot is read and the keeper goes across.
    @Test func aRealShotIsReadAndTheKeeperGoesAcross() {
        var (m, g) = Self.inPlay()
        // 15 out, travelling at 30 toward the line and across: half a second away.
        m.ball.pos = Vec(x: 0, z: Self.gz - Self.dir * -15)
        m.ball.vel = Vec(x: 4, z: -Self.dir * 30)
        let x = Self.keeperTargetX(&m, g)
        #expect(x != Self.lineOnly(m, g), "a real shot was not read")
        #expect(x > 0.5, "the keeper did not move toward the side the shot is going (\(x))")
    }

    /// A shot is only read once the keeper has had time to react to it (§7.8's delay), which is what
    /// stops a keeper being perfect the instant the ball leaves a stick.
    @Test func aShotIsNotReadBeforeTheKeeperHasReacted() {
        var (m, g) = Self.inPlay()
        m.ball.pos = Vec(x: 0, z: Self.gz - Self.dir * -15)
        m.ball.vel = Vec(x: 4, z: -Self.dir * 30)
        m.ball.lastReleaseTime = m.time                   // released this very step
        #expect(Self.keeperTargetX(&m, g) == Self.lineOnly(m, g), "the keeper read a shot with no delay")
    }

    /// A ball travelling *away* from the goal is never read, whatever its speed.
    @Test func aBallGoingTheOtherWayIsNotRead() {
        var (m, g) = Self.inPlay()
        m.ball.pos = Vec(x: 3, z: Self.gz - Self.dir * -10)
        m.ball.vel = Vec(x: 0, z: Self.dir * 30)          // straight back up the pitch
        #expect(Self.keeperTargetX(&m, g) == Self.lineOnly(m, g))
    }
}
