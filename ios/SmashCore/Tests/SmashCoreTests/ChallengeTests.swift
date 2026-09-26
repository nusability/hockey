import Testing
@testable import SmashCore

/// §7.2: one challenger goes for the ball and the rest cover, and the role does not churn. The twin
/// of Android's `ChallengeTest.kt`.
@Suite struct ChallengeTests {
    /// A match in play with team 1 carrying, so team 0 is the defending side.
    static func theirBall() -> (Match, carrier: Int) {
        let side = SideSetup(rating: 75, tactics: .defaults, formation: Formation.allCases[0])
        var m = Match(MatchSetup(seed: 11, sport: .field, home: side, away: side, periodSeconds: 120,
                                 orbitPeriod: 2.0, cup: false, control: .automatic))
        while m.state != .play { m.tick() }
        _ = m.drainEvents()
        let carrier = m.players.indices.first { m.players[$0].team == 1 && m.players[$0].isOutfield }!
        // Park everyone else in a corner: only the defenders a test places are candidates.
        for i in m.players.indices where i != carrier {
            m.players[i].pos = Vec(x: 13, z: Double(i) * 0.9 - 28)
            m.players[i].vel = .zero
        }
        m.players[carrier].pos = Vec(x: 0, z: 0)
        m.players[carrier].vel = .zero
        m.ball.carrier = carrier
        // Pin the orbit, so "nearest to the ball" is a property of where the defenders stand and
        // not of where the ball happens to be swinging.
        m.ball.orbit = 0
        m.ball.pos = m.orbitPoint(carrier)
        return (m, carrier)
    }

    @Test func onlyTheFirstChallengerGoesForTheBall() {
        var (m, carrier) = Self.theirBall()
        // Two defenders close enough to both be picked.
        let mine = m.players.indices.filter { m.players[$0].team == 0 && m.players[$0].isOutfield }
        m.players[mine[0]].pos = Vec(x: -3, z: -4)
        m.players[mine[1]].pos = Vec(x: 3, z: -4)
        let chosen = m.pickChallengers(0, carrier: carrier)
        #expect(chosen.count >= 2, "the case needs two challengers (\(chosen.count))")

        let ball = m.challengePoint()
        let cover = m.coverPoint(chosen[1], primary: chosen[0])
        // The one on the ball aims at the ball; the other does not.
        #expect(Pitch.distance(ball, m.ball.pos) < 2.5)
        #expect(Pitch.distance(cover, m.ball.pos) > Tuning.AI.Challenge.coverAhead - 1)
        // And the cover point is goal-side of the carrier — between it and the goal it attacks.
        let gz = Pitch.ownGoalZ(0)
        let dir = Pitch.direction(0)
        #expect(-dir * (cover.z - m.players[carrier].pos.z) > 0,
                "the cover point is not goal-side of the carrier")
        #expect(Pitch.length(cover.x, gz - cover.z) < Pitch.length(m.players[carrier].pos.x, gz - m.players[carrier].pos.z),
                "the cover point is no nearer the goal than the carrier")
    }

    /// The bug that mattered most: the two defenders must not keep swapping jobs.
    @Test func theRoleDoesNotChurnWhileTheCommitmentLasts() {
        var (m, carrier) = Self.theirBall()
        let mine = m.players.indices.filter { m.players[$0].team == 0 && m.players[$0].isOutfield }
        // Both goal-side, so the sort's last tiebreak is distance to the ball. One starts clearly
        // nearer and therefore takes the ball.
        m.players[mine[0]].pos = Vec(x: -1.0, z: -4)
        m.players[mine[1]].pos = Vec(x: 6.0, z: -4)
        let first = m.pickChallengers(0, carrier: carrier)[0]
        #expect(first == mine[0], "the near one should have taken the ball")

        // Now walk them past each other so the ORDERING genuinely crosses over — the flip that used
        // to hand the job back and forth several times a second.
        var handovers = 0
        var previous = first
        var sawTheOrderCross = false
        for step in 1...40 {
            m.players[mine[0]].pos = Vec(x: -1.0 - Double(step) * 0.2, z: -4)
            m.players[mine[1]].pos = Vec(x: 6.0 - Double(step) * 0.2, z: -4)
            if Pitch.distance(m.players[mine[1]].pos, m.ball.pos)
                < Pitch.distance(m.players[mine[0]].pos, m.ball.pos) { sawTheOrderCross = true }
            let now = m.pickChallengers(0, carrier: carrier)[0]
            if now != previous { handovers += 1; previous = now }
        }
        #expect(sawTheOrderCross, "the case never actually crossed the ordering over")
        #expect(handovers == 0, "the job changed hands \(handovers) times inside one commitment")
        #expect(previous == first)
    }

    /// …but it is not sticky forever: once the commitment lapses, someone else can take it.
    @Test func onceTheCommitmentLapsesTheJobCanPassOn() {
        var (m, carrier) = Self.theirBall()
        let mine = m.players.indices.filter { m.players[$0].team == 0 && m.players[$0].isOutfield }
        m.players[mine[0]].pos = Vec(x: -2, z: -4)
        m.players[mine[1]].pos = Vec(x: 8, z: -9)
        let first = m.pickChallengers(0, carrier: carrier)[0]
        // Let the commitment run out, and make the other one plainly the better candidate.
        m.time += Tuning.AI.Challenge.commitTime + 0.01
        m.players[first].pos = Vec(x: 12, z: -12)
        let other = mine.first { $0 != first }!
        m.players[other].pos = Vec(x: 0.5, z: -2)
        #expect(m.pickChallengers(0, carrier: carrier)[0] == other,
                "the job never passed on after the commitment lapsed")
    }

    /// §4.6: a restart clears the role along with the commitment.
    @Test func aRestartClearsTheRole() {
        var (m, carrier) = Self.theirBall()
        let mine = m.players.indices.filter { m.players[$0].team == 0 && m.players[$0].isOutfield }
        m.players[mine[0]].pos = Vec(x: -3, z: -4)
        m.players[mine[1]].pos = Vec(x: 3, z: -4)
        _ = m.pickChallengers(0, carrier: carrier)
        #expect(m.players.contains { $0.onTheBall })
        m.clearForRestart()
        #expect(!m.players.contains { $0.onTheBall }, "a restart left someone still on the ball")
        #expect(!m.players.contains { $0.challengeUntil > 0 })
    }

    /// The cover point keeps its distance from the player going in, whichever side they are on.
    @Test func theCoverPointStaysClearOfThePlayerGoingIn() {
        var (m, carrier) = Self.theirBall()
        let mine = m.players.indices.filter { m.players[$0].team == 0 && m.players[$0].isOutfield }
        for primarySide in [-1.0, 1.0] {
            m.players[mine[0]].pos = Vec(x: primarySide * 2, z: -3)
            m.players[mine[1]].pos = Vec(x: -primarySide * 2, z: -5)
            let chosen = m.pickChallengers(0, carrier: carrier)
            guard chosen.count >= 2 else { continue }
            let cover = m.coverPoint(chosen[1], primary: chosen[0])
            let gap = Pitch.distance(cover, m.players[chosen[0]].pos)
            #expect(gap >= Tuning.AI.Challenge.coverMinGap - 1e-9,
                    "the cover point sat \(gap) from the player going in")
        }
    }
}
