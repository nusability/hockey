/// An outfield carrier (spec §7.6–§7.7): the AI's decision and its wait for the orbit to line up,
/// and every carrier's movement — the player's carriers included.
extension Match {
    mutating func thinkCarrier(_ i: Int) {
        typealias C = Tuning.AI.Carrier
        let threat = nearestThreat(to: i)
        if !isPlayerControlled(i) {
            if players[i].thinkTimer <= 0 && players[i].holdTime > C.decideAfter {
                players[i].thinkTimer = C.rethinkBase + C.rethinkSpread * rng.uniform()
                if players[i].decision == nil { players[i].decision = decide(i, threat: threat?.distance) }
            }
            if let decision = players[i].decision, releaseIfAligned(i, decision, threat: threat?.distance) {
                return
            }
        }
        players[i].target = carrierTarget(i, threat: threat)
    }

    /// The nearest opponent who can steal, goalies excluded (§7.6).
    func nearestThreat(to i: Int) -> (index: Int, distance: Double)? {
        let team = players[i].team
        let candidates = rosters[1 - team].filter { !players[$0].isDummy && !players[$0].isGoalie }
        return nearest(to: players[i].pos, among: candidates)
    }

    // MARK: §7.6 — the decision

    mutating func decide(_ i: Int, threat: Double?) -> CarrierDecision? {
        typealias C = Tuning.AI.Carrier
        let me = players[i]
        let team = me.team
        let t = effectiveTactics(team)
        let goal = Vec(x: 0, z: Pitch.attackGoalZ(team))
        let dGoal = Pitch.distance(me.pos, goal)
        let forced = (threat.map { $0 < C.forcedThreat } ?? false) || me.holdTime > C.forcedHold
        var laneClear = true
        for o in rosters[1 - team] where !players[o].isGoalie {
            if Pitch.segmentDistance(players[o].pos, me.pos, goal) < C.shootLaneWidth
                && Pitch.distance(players[o].pos, me.pos) < dGoal {
                laneClear = false
                break
            }
        }
        let wantShot = dGoal < C.shootRangeBase + C.shootRangePerShooting * t.shooting
            && (laneClear || dGoal < C.shootClose) && me.pos.x.magnitude < C.shootMaxX
        if wantShot && (rng.uniform() < C.shootChanceBase + C.shootChancePerShooting * t.shooting || forced) {
            return .shoot
        }
        let dir = Pitch.direction(team)
        let ownGoal = Vec(x: 0, z: Pitch.ownGoalZ(team))
        var best: Int?
        var bestScore = -Double.infinity
        for m in outfield(team) where m != i {
            let d = Pitch.distance(me.pos, players[m].pos)
            if d < C.passMin || d > C.passMax { continue }
            let progress = dir * (players[m].pos.z - me.pos.z)
            let openness = nearest(to: players[m].pos, among: rosters[1 - team])
                .map { Pitch.clamp($0.distance, 0, C.passOpennessCap) } ?? C.passOpennessCap
            var score = C.passOpennessWeight * openness + C.passProgressWeight * progress
            if laneBlocked(from: me.pos, to: players[m].pos, team: team, width: C.passLaneWidth) { score -= C.passLanePenalty }
            if Pitch.segmentDistance(ownGoal, me.pos, players[m].pos) < C.passOwnGoalZone { score -= C.passOwnGoalPenalty }
            if progress < -C.passBackward { score += C.passBackwardWeight * (progress + C.passBackward) }
            if d > C.passLong { score -= C.passLongWeight * (d - C.passLong) }
            if isOffsideReceiver(m) { score -= C.passOffsidePenalty }
            score += rng.noise(C.passNoise)
            if score > bestScore { bestScore = score; best = m }
        }
        if let m = best, bestScore > C.passThreshold {
            var urge = C.passChancePerPassing * t.passing
            if let d = threat, d < C.passChanceThreatDistance { urge += C.passChanceThreat }
            if me.holdTime > C.passChanceHeldTime { urge += C.passChanceHeld }
            if rng.uniform() < urge || forced { return .pass(to: m) }
        }
        guard forced else { return nil }
        if let m = best { return .pass(to: m) }
        return dGoal < C.forcedShootRange ? .shoot : .clear
    }

    /// Any opponent within `width` of the segment from → to.
    func laneBlocked(from: Vec, to: Vec, team: Int, width: Double) -> Bool {
        rosters[1 - team].contains { Pitch.segmentDistance(players[$0].pos, from, to) < width }
    }

    /// Releases when the orbit has lined up with the decision's aim; true when the ball left.
    mutating func releaseIfAligned(_ i: Int, _ decision: CarrierDecision, threat: Double?) -> Bool {
        typealias C = Tuning.AI.Carrier
        let me = players[i]
        let gz = Pitch.attackGoalZ(me.team)
        let aim: Double
        switch decision {
        case .shoot, .clear:
            aim = Pitch.heading(0.0 - me.pos.x, gz - me.pos.z)
        case .pass(let m):
            let d = Pitch.distance(me.pos, players[m].pos)
            let t = d / Pitch.clamp(C.alignSpeedBase + C.alignSpeedPerMetre * d, C.alignSpeedMin, C.alignSpeedMax)
            let lx = players[m].pos.x + Tuning.Orbit.leadVelocityFactor * players[m].vel.x * t
            let lz = players[m].pos.z + Tuning.Orbit.leadVelocityFactor * players[m].vel.z * t
            aim = Pitch.heading(lx - me.pos.x, lz - me.pos.z)
        }
        let s = skill[me.team]
        var tolerance = C.alignToleranceBase + C.alignTolerancePerUnskill * (1 - s)
        if let d = threat, d < C.alignPressedDistance { tolerance += C.alignTolerancePressed }
        guard Pitch.angleDiff(aim, ball.orbit).magnitude < tolerance else { return false }
        let accuracy = C.accuracyBase + C.accuracyPerSkill * s
        switch decision {
        case .shoot:
            let power = C.shotPowerBase + C.shotPowerPerSkill * s + C.shotPowerSpread * rng.uniform()
            shoot(i, accuracy: accuracy, power: power)
        case .pass(let m):
            pass(i, to: m, accuracy: accuracy)
        case .clear:
            releaseUnassisted(i, kind: .clear)
        }
        players[i].decision = nil
        return true
    }

    // MARK: §7.7 — every carrier's movement

    func carrierTarget(_ i: Int, threat: (index: Int, distance: Double)?) -> Vec {
        typealias M = Tuning.AI.Movement
        let me = players[i]
        let gz = Pitch.attackGoalZ(me.team)
        let n = Pitch.unit(0.0 - me.pos.x, gz - me.pos.z)
        var tx = me.pos.x + n.x * M.ahead
        var tz = me.pos.z + n.z * M.ahead
        if let th = threat, th.distance < M.swerveRange {
            let away = Pitch.unit(me.pos.x - players[th.index].pos.x, me.pos.z - players[th.index].pos.z)
            let sideX = -n.z
            let sideZ = n.x
            let s: Double = away.x * sideX + away.z * sideZ >= 0 ? 1 : -1
            tx += sideX * s * M.swerveSide + away.x * M.swerveAway
            tz += sideZ * s * M.swerveSide + away.z * M.swerveAway
        }
        for o in rosters[1 - me.team] where players[o].isDummy {
            let d = Pitch.distance(players[o].pos, me.pos)
            if d < M.dummyRange {
                let a = Pitch.unit(me.pos.x - players[o].pos.x, me.pos.z - players[o].pos.z)
                let push = M.dummyPush * (M.dummyRange - d)
                tx += a.x * push
                tz += a.z * push
            }
        }
        let dGoal = Pitch.length(0.0 - me.pos.x, gz - me.pos.z)
        if dGoal < M.goalApproach {
            let side: Double = me.pos.x >= 0 ? 1 : -1
            let drift = me.pos.x.magnitude > M.goalApproachCenterX ? -side : side
            tx = me.pos.x + drift * M.goalApproachSide
            tz = me.pos.z - (M.goalApproach - dGoal) * M.goalApproachPull * n.z
        }
        return Match.clampToPlay(outOfCrease(me.team, Vec(x: tx, z: tz)))
    }
}
