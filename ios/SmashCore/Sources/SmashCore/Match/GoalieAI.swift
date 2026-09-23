/// Goalies (spec §7.8): positioning, reading a shot, smothering, and playing the ball out. While
/// its team is on alert (§7.9) it reads sooner, leads fully and goes the whole way across.
extension Match {
    mutating func thinkGoalie(_ g: Int, _ dt: Double) {
        if ball.carrier == g {
            goalieWithBall(g, dt)
            return
        }
        typealias G = Tuning.AI.Goalie
        let team = players[g].team
        let dir = Pitch.direction(team)
        let gz = Pitch.ownGoalZ(team)
        let s = skill[team]
        typealias A = Tuning.AI.Alert
        let alerted = alert[team] > 0
        var aimX = ball.pos.x
        var delay = G.readBase + G.readPerUnskill * (1 - s)
        if alerted { delay = delay * A.goalieReadScale }
        // §7.10 — a side that is behind has its keeper read sooner. Never the other way round: a
        // defence is only ever sharpened, never dulled, so no goal is handed to anyone (A0).
        delay = delay * (1 - Tuning.AI.Balance.chaseGoalieRead * chase(team))
        let reacted = ball.lastReleaseTime.map { time - $0 > delay } ?? true
        let towards = dir * ball.vel.z < -G.readSpeed && reacted
        if towards {
            let t = (gz - ball.pos.z) / ball.vel.z
            let lead = alerted ? A.goalieLead : G.readLeadBase + G.readLeadPerSkill * s
            if t > 0 && t < G.readHorizon { aimX = ball.pos.x + ball.vel.x * t * lead }
        }
        let toBall = Pitch.unit(ball.pos.x, ball.pos.z - gz)
        let out = G.outBase + G.outPerSkill * s
        var x = toBall.x * out * G.xScale
        var z = gz + toBall.z * out
        if towards { x = aimX * (alerted ? A.goalieAimFactor : G.readAimFactor) }
        let xLimit = Tuning.Pitch.postX + G.xLimitExtra
        x = Pitch.clamp(x, -xLimit, xLimit)
        z = gz + dir * Pitch.clamp(dir * (z - gz), G.frontMin, G.frontMax)
        if ball.carrier == nil && Pitch.distance(players[g].pos, ball.pos) < G.smotherRange
            && Pitch.length(ball.vel.x, ball.vel.z) < G.smotherSpeed && ball.pos.x.magnitude < G.smotherMaxX
            && dir * (ball.pos.z - gz) < G.smotherLine {
            x = ball.pos.x
            z = ball.pos.z
        }
        players[g].target = Vec(x: x, z: z)
    }

    /// With the ball it stands still; after 0.4 s it picks the most open team-mate and releases when
    /// the orbit points at them (no lead) — or clears once it points up the pitch — or after 2.5 s.
    mutating func goalieWithBall(_ g: Int, _ dt: Double) {
        typealias G = Tuning.AI.Goalie
        let team = players[g].team
        players[g].holdTime += dt
        if players[g].decision == nil && players[g].holdTime > G.holdBeforePass {
            var best: Int?
            var bestScore = -Double.infinity
            for m in outfield(team) {
                let open = nearest(to: players[m].pos, among: rosters[1 - team])
                    .map { Pitch.clamp($0.distance, 0, G.opennessCap) } ?? G.opennessCap
                var score = open
                if laneBlocked(from: players[g].pos, to: players[m].pos, team: team, width: Tuning.AI.Carrier.passLaneWidth) {
                    score -= G.blockedPenalty
                }
                if players[m].role == .defender { score += G.defenderBonus }
                score += rng.noise(G.pickNoise)
                if score > bestScore { bestScore = score; best = m }
            }
            players[g].decision = best.map { .pass(to: $0) } ?? .clear
        }
        if let decision = players[g].decision {
            let aim: Double
            if case .pass(let m) = decision {
                aim = Pitch.heading(players[m].pos.x - players[g].pos.x, players[m].pos.z - players[g].pos.z)
            } else {
                aim = team == 0 ? 0 : Pitch.pi
            }
            if Pitch.angleDiff(aim, ball.orbit).magnitude < G.releaseWindow || players[g].holdTime > G.releaseTimeout {
                if case .pass(let m) = decision {
                    pass(g, to: m, accuracy: G.passAccuracy)
                } else {
                    releaseUnassisted(g, kind: .clear)
                }
                players[g].decision = nil
                players[g].holdTime = 0
                return
            }
        }
        players[g].target = players[g].pos
    }
}
