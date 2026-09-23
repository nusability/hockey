/// Support positions (spec §7.4), the offer a team-mate makes near the goal, and the shape every
/// non-chaser keeps (§7.5).
extension Match {
    // MARK: §7.4 — support

    /// The six support slots around the ball (or its carrier), shared out greedily in roster order;
    /// this player's slot, shifted away from a crowding opponent. `offer` is true when this player
    /// took the receiving slot (§7.4), whose spot keeps its shape.
    func supportTarget(_ i: Int) -> (spot: Vec, offer: Bool) {
        typealias S = Tuning.AI.Support
        let team = players[i].team
        let dir = Pitch.direction(team)
        let pushUp = effectiveTactics(team).pushUp
        let reference = ball.carrier.map { players[$0].pos } ?? ball.pos
        let flip: Double = reference.x >= 0 ? -1 : 1
        let gz = Pitch.attackGoalZ(team)
        // §7.4 — the offer: an own carrier inside `offerRange` of the goal turns the highest slot
        // into a receiving position for one named team-mate, on their own side of the pitch in
        // front of the goal, on the 8-15 band from the carrier.
        var offerSlot: Int?
        var offerTaker: Int?
        if let c = ball.carrier, players[c].team == team,
           Pitch.length(players[c].pos.x, gz - players[c].pos.z) < S.offerRange,
           let o = offerTakerIndex(team, goalZ: gz) {
            offerSlot = S.offerIndex
            offerTaker = o
        }
        var slots: [(spot: Vec, role: Role)] = []
        for (k, slot) in S.slots.enumerated() {
            if k == offerSlot {
                slots.append((offerSpot(carrier: ball.carrier!, taker: offerTaker!, goalZ: gz, dir: dir), slot.role))
                continue
            }
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
        var tookOffer = false
        // The offer is filled first, by the team-mate it was drawn for, so someone always makes it.
        if let k = offerSlot, let o = offerTaker {
            free[k] = false
            if o == i { mine = slots[k].spot; tookOffer = true }
        }
        for m in outfield(team) where m != ball.carrier {
            if tookOffer && m == i { continue }
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
        if tookOffer { return (f, true) }
        if let o = nearest(to: f, among: rosters[1 - team]), o.distance < S.crowdedDistance {
            let n = Pitch.unit(f.x - players[o.index].pos.x, f.z - players[o.index].pos.z)
            f = Vec(x: f.x + n.x * S.crowdedShiftAcross, z: f.z + n.z * S.crowdedShiftAlong)
        }
        return (f, false)
    }

    /// Who makes the offer: the forward nearest the goal the team attacks — any other outfield
    /// player when the team has no other forward — so the offer never changes side under them.
    func offerTakerIndex(_ team: Int, goalZ: Double) -> Int? {
        var candidates = outfield(team).filter { $0 != ball.carrier && players[$0].role == .forward }
        if candidates.isEmpty { candidates = outfield(team).filter { $0 != ball.carrier } }
        var best: Int?
        var bestDistance = Double.infinity
        for q in candidates {
            let d = Pitch.length(players[q].pos.x, goalZ - players[q].pos.z)
            if d < bestDistance { bestDistance = d; best = q }
        }
        return best
    }

    /// The receiving position (§7.4): `offerX` across on the taker's own side of the pitch and
    /// `offerGoalInset` in front of the goal line they attack, brought onto the 8-15 band from the
    /// carrier and kept inside the sidelines.
    func offerSpot(carrier: Int, taker: Int, goalZ: Double, dir: Double) -> Vec {
        typealias S = Tuning.AI.Support
        let from = players[carrier].pos
        let side: Double = players[taker].pos.x >= 0 ? 1 : -1
        var x = S.offerX * side
        var z = goalZ - dir * S.offerGoalInset
        let d = Pitch.length(x - from.x, z - from.z)
        let want = Pitch.clamp(d, S.offerMin, S.offerMax)
        if want != d {
            let n = d > Tuning.Sim.clearEpsilon ? Vec(x: (x - from.x) / d, z: (z - from.z) / d) : Vec(x: 1, z: 0)
            x = from.x + n.x * want
            z = from.z + n.z * want
        }
        let inset = Tuning.Pitch.halfWidth - S.sidelineInset
        return Vec(x: Pitch.clamp(x, -inset, inset), z: z)
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
            * (S.spotPushBase + S.spotPushPerPushUp * effectiveTactics(p.team).pushUp) * S.spotPushFactor * k
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
            * (S.zonePushBase + S.zonePushPerPushUp * effectiveTactics(p.team).pushUp)
        return Vec(x: p.home.x + (ball.pos.x - p.home.x) * S.zoneAcross, z: p.home.z + (ball.pos.z - p.home.z) * follow)
    }

    /// Discipline, the distance from the ball, the spacing from team-mates and the crease (§7.5).
    func shaped(_ i: Int, _ target: Vec, possession: Possession) -> Vec {
        typealias S = Tuning.AI.Shape
        let team = players[i].team
        let discipline = effectiveTactics(team).discipline
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
