/// Support positions (spec §7.4) and the shape every non-chaser keeps (§7.5).
extension Match {
    // MARK: §7.4 — support

    /// The six support slots around the ball (or its carrier), shared out greedily in roster order;
    /// this player's slot, shifted away from a crowding opponent.
    func supportTarget(_ i: Int) -> Vec {
        typealias S = Tuning.AI.Support
        let team = players[i].team
        let dir = Pitch.direction(team)
        let pushUp = tactics[team].pushUp
        let reference = ball.carrier.map { players[$0].pos } ?? ball.pos
        let flip: Double = reference.x >= 0 ? -1 : 1
        let gz = Pitch.attackGoalZ(team)
        var slots: [(spot: Vec, role: Role)] = []
        for slot in S.slots {
            var x = slot.mirror ? slot.x * flip : reference.x + slot.x
            let depth = slot.z * (S.depthBase + S.depthPerPushUp * pushUp)
            var z = reference.z + dir * depth
            x = Pitch.clamp(x, -(Tuning.Pitch.halfWidth - S.sidelineInset), Tuning.Pitch.halfWidth - S.sidelineInset)
            let along = Pitch.clamp(dir * z, -(Tuning.Pitch.goalLineZ - S.ownGoalInset), Tuning.Pitch.goalLineZ - S.opponentGoalInset)
            z = along * dir
            if Pitch.length(x, gz - z) < S.goalZone { x = x >= 0 ? Pitch.greater(x, S.goalZone) : Pitch.lesser(x, -S.goalZone) }
            slots.append((keptClear(Vec(x: x, z: z), of: ball.pos, by: S.ballDistance), slot.role))
        }
        var free = Array(repeating: true, count: slots.count)
        var mine: Vec?
        for m in outfield(team) where m != ball.carrier {
            let role: Role = players[m].role == .defender ? .defender : .forward
            var best = -1
            var bestCost = Double.infinity
            for (k, slot) in slots.enumerated() where free[k] {
                let cost = Pitch.distance(players[m].pos, slot.spot) + (slot.role == role ? 0 : S.roleMismatchCost)
                if cost < bestCost { bestCost = cost; best = k }
            }
            guard best >= 0 else { continue }
            free[best] = false
            if m == i { mine = slots[best].spot }
        }
        var f = mine ?? formationSpot(i, k: Tuning.AI.Shape.kSupporting)
        if let o = nearest(to: f, among: rosters[1 - team]), o.distance < S.crowdedDistance {
            let n = Pitch.unit(f.x - players[o.index].pos.x, f.z - players[o.index].pos.z)
            f = Vec(x: f.x + n.x * S.crowdedShiftAcross, z: f.z + n.z * S.crowdedShiftAlong)
        }
        return f
    }

    // MARK: §7.5 — shape, spacing and discipline

    /// The home spot moved toward the ball: `(D 0.35 | F 0.55) × (0.6 + 0.8 × push up) × 2 × k`
    /// along the pitch (at most 0.9 of the way) and `(D 0.3 | F 0.4)` across.
    func formationSpot(_ i: Int, k: Double) -> Vec {
        typealias S = Tuning.AI.Shape
        let p = players[i]
        let defender = p.role == .defender
        let dir = Pitch.direction(p.team)
        let along = (defender ? S.spotAlongDefender : S.spotAlongForward)
            * (S.spotPushBase + S.spotPushPerPushUp * tactics[p.team].pushUp) * S.spotPushFactor * k
        var z = p.home.z + (ball.pos.z - p.home.z) * Pitch.clamp(along, 0, S.spotMaxFraction)
        let x = p.home.x + (ball.pos.x - p.home.x) * (defender ? S.spotAcrossDefender : S.spotAcrossForward)
        if defender && dir * z > dir * ball.pos.z + S.defenderMaxAhead && dir * ball.pos.z < 0 {
            z = ball.pos.z - dir * S.defenderMaxAhead
        }
        return Vec(x: x, z: z)
    }

    /// The zone a disciplined player holds.
    func zone(_ i: Int) -> Vec {
        typealias S = Tuning.AI.Shape
        let p = players[i]
        let follow = (p.role == .defender ? S.zoneAlongDefender : S.zoneAlongForward)
            * (S.zonePushBase + S.zonePushPerPushUp * tactics[p.team].pushUp)
        return Vec(x: p.home.x + (ball.pos.x - p.home.x) * S.zoneAcross, z: p.home.z + (ball.pos.z - p.home.z) * follow)
    }

    /// Discipline, the distance from the ball, the spacing from team-mates and the crease (§7.5).
    func shaped(_ i: Int, _ target: Vec, possession: Possession) -> Vec {
        typealias S = Tuning.AI.Shape
        let team = players[i].team
        let discipline = tactics[team].discipline
        let z = zone(i)
        var t = Vec(x: target.x + (z.x - target.x) * discipline, z: target.z + (z.z - target.z) * discipline)
        t = keptClear(t, of: ball.pos, by: possession == .theirs ? S.ballDistanceDefending : S.ballDistance)
        let gap = possession == .own ? S.mateDistancePossession : S.mateDistanceOtherwise
        for q in outfield(team) where q != i {
            let dx = t.x - players[q].pos.x
            let dz = t.z - players[q].pos.z
            let d = Pitch.length(dx, dz)
            if d < gap && d > Tuning.Sim.clearEpsilon {
                let push = gap - d
                t = Vec(x: t.x + dx / d * push, z: t.z + dz / d * push)
            }
        }
        return outOfCrease(team, t)
    }

    /// `target` pushed to at least `distance` from `point` (along +x when it sits on it).
    func keptClear(_ target: Vec, of point: Vec, by distance: Double) -> Vec {
        let dx = target.x - point.x
        let dz = target.z - point.z
        let d = Pitch.length(dx, dz)
        if d >= distance { return target }
        let n = d > Tuning.Sim.clearEpsilon ? Vec(x: dx / d, z: dz / d) : Vec(x: 1, z: 0)
        return Vec(x: point.x + n.x * distance, z: point.z + n.z * distance)
    }

    /// First at least 2.2 in front of their own goal line, then at least 3.2 + 1.2 from its centre.
    func outOfCrease(_ team: Int, _ target: Vec) -> Vec {
        typealias S = Tuning.AI.Shape
        let gz = Pitch.ownGoalZ(team)
        let dir = Pitch.direction(team)
        var t = target
        let deepest = -(Tuning.Pitch.goalLineZ - S.goalLineMin)
        if dir * t.z < deepest { t.z = dir * deepest }
        let dx = t.x
        let dz = t.z - gz
        let d = Pitch.length(dx, dz)
        let keep = Tuning.Pitch.creaseRadius + S.creaseExtra
        if d < keep && d > 0 {
            let nx = dx / d
            let nz = dz / d
            t = Vec(x: nx * keep, z: gz + nz.magnitude * keep * dir)
        }
        return t
    }
}
