/// Automatic play, one team at a time (spec §7): who thinks when, the alert window (§7.9), the
/// loose ball (§7.1), the challengers (§7.2) and defending (§7.3). Support and shape are in
/// `Shape.swift`, the carrier in `CarrierAI.swift`, the goalie in `GoalieAI.swift`.
extension Match {
    enum Possession { case own, theirs, loose }

    mutating func thinkTeam(_ team: Int, _ dt: Double) {
        let carrier = ball.carrier
        let possession: Possession = carrier == nil ? .loose : (players[carrier!].team == team ? .own : .theirs)
        let ranking = rankedByBallDistance(team)
        let challengers = possession == .theirs ? pickChallengers(team, carrier: carrier!) : []
        let blocker = possession == .theirs && alert[team] > 0
            ? pickLaneBlocker(team, carrier: carrier!, challengers: challengers) : nil
        for i in rosters[team] where !players[i].isDummy {
            players[i].thinkTimer -= dt
            if players[i].isGoalie {
                thinkGoalie(i, dt)
                continue
            }
            if carrier == i {
                players[i].holdTime += dt
                thinkCarrier(i)
                continue
            }
            if players[i].thinkTimer > 0 { continue }
            players[i].thinkTimer = Tuning.AI.thinkBase + Tuning.AI.thinkSpread * rng.uniform()
            rethink(i, possession: possession, ranking: ranking, challengers: challengers, blocker: blocker)
        }
    }

    /// A non-carrying outfield player's new target (§7.1–§7.5).
    mutating func rethink(_ i: Int, possession: Possession, ranking: [(index: Int, distance: Double)],
                          challengers: [Int], blocker: Int?) {
        typealias L = Tuning.AI.Loose
        if players[i].expectPass > 0 { players[i].expectPass -= Tuning.Release.passExpectationDecay }
        var target: Vec
        var chasing = false
        var defending = false
        switch possession {
        case .loose:
            let rank = ranking.firstIndex { $0.index == i } ?? ranking.count
            let pressing = tactics[players[i].team].pressing
            let many = pressing > L.twoChasersPressing || (ranking.first?.distance ?? 0) > L.twoChasersDistance
                || looseTimer > L.twoChasersLooseTime
            if players[i].expectPass > 0 {
                target = routeAroundNet(i, interceptPoint(i))
                chasing = true
            } else if rank < (many ? 2 : 1) {
                target = routeAroundNet(i, chasePoint(i))
                chasing = true
            } else {
                target = supportTarget(i).spot
            }
        case .theirs:
            if challengers.contains(i) {
                target = challengePoint()
                chasing = true
            } else if i == blocker {
                target = laneBlockPoint(team: players[i].team, carrier: ball.carrier!)
                chasing = true
            } else {
                target = defendTarget(i)
                defending = true
            }
        case .own:
            let s = supportTarget(i)
            target = s.spot
            chasing = chasing || s.offer
        }
        if !defending { players[i].mark = nil }
        if !chasing { target = shaped(i, target, possession: possession) }
        players[i].target = Match.clampToPlay(target)
    }

    /// The team's outfield players by distance to the ball, nearest first, roster order on a tie.
    func rankedByBallDistance(_ team: Int) -> [(index: Int, distance: Double)] {
        outfield(team).map { (index: $0, distance: Pitch.distance(players[$0].pos, ball.pos)) }
            .sorted { $0.distance < $1.distance || ($0.distance == $1.distance && $0.index < $1.index) }
    }

    static func clampToPlay(_ v: Vec) -> Vec {
        typealias S = Tuning.AI.Shape
        return Vec(x: Pitch.clamp(v.x, -S.clampX, S.clampX), z: Pitch.clamp(v.z, -S.clampZ, S.clampZ))
    }

    // MARK: §7.1 — the loose ball

    /// The point on the ball's line of travel nearest the player, ahead of the ball only; the ball
    /// itself when it is slower than 2.
    func interceptPoint(_ i: Int) -> Vec {
        let speed = Pitch.length(ball.vel.x, ball.vel.z)
        if speed < Tuning.AI.Loose.expectSlowBall { return ball.pos }
        let ux = ball.vel.x / speed
        let uz = ball.vel.z / speed
        let t = Pitch.greater(0, (players[i].pos.x - ball.pos.x) * ux + (players[i].pos.z - ball.pos.z) * uz)
        return Vec(x: ball.pos.x + ux * t, z: ball.pos.z + uz * t)
    }

    /// Where the ball will be: position + 0.7 × velocity × t, t = clamp(d / max(top, 1), 0, 1.2).
    func chasePoint(_ i: Int) -> Vec {
        typealias L = Tuning.AI.Loose
        let d = Pitch.distance(players[i].pos, ball.pos)
        let t = Pitch.clamp(d / Pitch.greater(players[i].topSpeed, L.chaseSpeedFloor), 0, L.chaseTimeMax)
        return Vec(x: ball.pos.x + L.chaseLead * ball.vel.x * t, z: ball.pos.z + L.chaseLead * ball.vel.z * t)
    }

    /// A chase target at or behind a goal line near the net, for a chaser still in front of it,
    /// becomes the net's corner waypoint on the chaser's side.
    func routeAroundNet(_ i: Int, _ target: Vec) -> Vec {
        typealias L = Tuning.AI.Loose
        let me = players[i].pos
        for team in 0..<2 {
            let gz = Pitch.ownGoalZ(team)
            let dir = Pitch.direction(team)
            guard dir * (target.z - gz) < L.cornerLineMargin && target.x.magnitude <= L.cornerCenterX
                && dir * (me.z - gz) > L.cornerLineMargin else { continue }
            let side: Double = me.x >= 0 ? 1 : -1
            return Vec(x: side * L.cornerWaypointX, z: gz + dir * L.cornerWaypointInFront)
        }
        return target
    }

    // MARK: §7.2 — challengers

    /// Who goes in for the ball: the committed, then the goal-side, then the nearest; each chosen one
    /// stays committed for 0.7 s.
    mutating func pickChallengers(_ team: Int, carrier: Int) -> [Int] {
        typealias C = Tuning.AI.Challenge
        let t = tactics[team]
        let pressRange = (C.pressRangeBase + C.pressRangePerPressing * t.pressing) * (1 - C.pressRangeDiscipline * t.discipline)
        let most = t.pressing > C.pressingThreshold ? C.challengersPressing : C.challengers
        var candidates: [(index: Int, committed: Bool, goalSide: Bool, distance: Double)] = []
        for q in outfield(team) {
            let committed = players[q].challengeUntil > time
            let goalSide = isGoalSide(q, of: carrier)
            let d = Pitch.distance(players[q].pos, ball.pos)
            if committed || d < (goalSide ? C.goalSideRange : pressRange) {
                candidates.append((q, committed, goalSide, d))
            }
        }
        candidates.sort { a, b in
            if a.committed != b.committed { return a.committed }
            if a.goalSide != b.goalSide { return a.goalSide }
            if a.distance != b.distance { return a.distance < b.distance }
            return a.index < b.index
        }
        let chosen = candidates.prefix(most).map(\.index)
        for q in chosen { players[q].challengeUntil = time + C.commitTime }
        return chosen
    }

    /// At least 0.5 nearer their own goal than the carrier, within 7 of the carrier's route to it.
    func isGoalSide(_ q: Int, of carrier: Int) -> Bool {
        typealias C = Tuning.AI.Challenge
        let dir = Pitch.direction(players[q].team)
        guard dir * players[carrier].pos.z - dir * players[q].pos.z >= C.goalSideMargin else { return false }
        let goal = Vec(x: 0, z: Pitch.ownGoalZ(players[q].team))
        return Pitch.segmentDistance(players[q].pos, players[carrier].pos, goal) < C.goalSideRoute
    }

    /// Where the ball will be 0.3 s ahead on its orbit, plus the carrier's travel.
    func challengePoint() -> Vec {
        typealias C = Tuning.AI.Challenge
        let c = players[ball.carrier!]
        let a = ball.orbit + omega * C.orbitLead * ball.orbitDirection
        let r = Tuning.Orbit.radius
        return Vec(x: c.pos.x + r * DetMath.sin(a) + c.vel.x * C.orbitLead,
                   z: c.pos.z + r * DetMath.cos(a) + c.vel.z * C.orbitLead)
    }

    // MARK: §7.9 — the alert window

    /// Counts the alert down, ends it when the alerted team wins the ball, and opens a new one when
    /// an outfield carrier crosses the centre line toward the goal they attack.
    mutating func updateAlert(_ dt: Double) {
        for t in 0..<2 where alert[t] > 0 {
            alert[t] -= dt
            if alert[t] < 0 { alert[t] = 0 }
        }
        if let c = ball.carrier { alert[players[c].team] = 0 }
        guard let c = ball.carrier, players[c].isOutfield else {
            crossingCarrier = nil
            return
        }
        // Inside `closeRange` the attack is in on goal: the window is over and §7.8's ordinary
        // keeper takes it, so the alert never touches the finish it was not aimed at.
        let gz = Pitch.attackGoalZ(players[c].team)
        if Pitch.length(0.0 - players[c].pos.x, gz - players[c].pos.z) < Tuning.AI.Alert.closeRange {
            alert[1 - players[c].team] = 0
        }
        let dir = Pitch.direction(players[c].team)
        let z = players[c].pos.z
        if crossingCarrier == c && dir * crossingZ <= 0 && dir * z > 0 {
            alert[1 - players[c].team] = Tuning.AI.Alert.seconds
        }
        crossingCarrier = c
        crossingZ = z
    }

    /// Who steps into the shooting lane: the outfield player nearest that spot who is not already a
    /// challenger (roster order on a tie).
    func pickLaneBlocker(_ team: Int, carrier: Int, challengers: [Int]) -> Int? {
        let spot = laneBlockPoint(team: team, carrier: carrier)
        var best: Int?
        var bestDistance = Double.infinity
        for q in outfield(team) where !challengers.contains(q) {
            let d = Pitch.distance(players[q].pos, spot)
            if d < bestDistance { bestDistance = d; best = q }
        }
        return best
    }

    /// On the line from the carrier to the goal this team defends, `min(4.5, 0.35 × d)` in front of
    /// the carrier.
    func laneBlockPoint(team: Int, carrier: Int) -> Vec {
        typealias A = Tuning.AI.Alert
        let from = players[carrier].pos
        let goal = Vec(x: 0, z: Pitch.ownGoalZ(team))
        let d = Pitch.distance(from, goal)
        let n = Pitch.unit(goal.x - from.x, goal.z - from.z)
        let ahead = Pitch.lesser(A.laneAheadMax, A.laneAheadFraction * d)
        return Vec(x: from.x + n.x * ahead, z: from.z + n.z * ahead)
    }

    // MARK: §7.3 — defending

    mutating func defendTarget(_ i: Int) -> Vec {
        typealias D = Tuning.AI.Defend
        let team = players[i].team
        let dir = Pitch.direction(team)
        let covering = tactics[team].covering
        var taken: [Int] = []
        for q in rosters[team] where q != i { if let m = players[q].mark { taken.append(m) } }
        var mark: Int?
        var best = Double.infinity
        for o in outfield(1 - team) where o != ball.carrier && !taken.contains(o) {
            let depth = -dir * players[o].pos.z
            let danger = Pitch.distance(players[i].pos, players[o].pos) - D.dangerDepthWeight * depth
            if danger < best { best = danger; mark = o }
        }
        if let o = mark, rng.uniform() < D.markChanceBase + D.markChancePerCovering * covering {
            players[i].mark = o
            let goal = Vec(x: 0, z: Pitch.ownGoalZ(team))
            let n = Pitch.unit(goal.x - players[o].pos.x, goal.z - players[o].pos.z)
            let gap = D.markDistanceBase + D.markDistancePerLoose * (1 - covering)
            return Vec(x: players[o].pos.x + n.x * gap, z: players[o].pos.z + n.z * gap)
        }
        players[i].mark = nil
        var f = formationSpot(i, k: D.holdK)
        if dir * f.z > dir * ball.pos.z - D.ballGoalSideTrigger { f.z = ball.pos.z - dir * D.ballGoalSideOffset }
        return f
    }
}
