package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Role
import `in`.nann.smashhockey.core.generated.Tuning
import kotlin.math.abs

// Support positions (spec §7.4) and the shape every non-chaser keeps (§7.5).

// §7.4 — support

/**
 * The six support slots around the ball (or its carrier), shared out greedily in roster order;
 * this player's slot, shifted away from a crowding opponent.
 */
internal fun Match.supportTarget(i: Int): Vec {
    val s = Tuning.AI.Support
    val team = players[i].team
    val dir = Pitch.direction(team)
    val pushUp = tactics[team].pushUp
    val carrier = ball.carrier
    val reference = if (carrier != null) players[carrier].pos else ball.pos
    val flip = if (reference.x >= 0) -1.0 else 1.0
    val gz = Pitch.attackGoalZ(team)
    val spots = ArrayList<Vec>(s.slots.size)
    for (slot in s.slots) {
        var x = if (slot.mirror) slot.x * flip else reference.x + slot.x
        val depth = slot.z * (s.depthBase + s.depthPerPushUp * pushUp)
        var z = reference.z + dir * depth
        x = Pitch.clamp(x, -(Tuning.Pitch.halfWidth - s.sidelineInset), Tuning.Pitch.halfWidth - s.sidelineInset)
        val along = Pitch.clamp(dir * z, -(Tuning.Pitch.goalLineZ - s.ownGoalInset), Tuning.Pitch.goalLineZ - s.opponentGoalInset)
        z = along * dir
        if (Pitch.length(x, gz - z) < s.goalZone) x = if (x >= 0) Pitch.greater(x, s.goalZone) else Pitch.lesser(x, -s.goalZone)
        spots.add(keptClear(Vec(x, z), ball.pos, s.ballDistance))
    }
    val free = BooleanArray(spots.size) { true }
    var mine: Vec? = null
    for (m in outfield(team)) {
        if (m == carrier) continue
        val role = if (players[m].role == Role.DEFENDER) Role.DEFENDER else Role.FORWARD
        var best = -1
        var bestCost = Double.POSITIVE_INFINITY
        for (k in spots.indices) {
            if (!free[k]) continue
            val cost = Pitch.distance(players[m].pos, spots[k]) + (if (s.slots[k].role == role) 0.0 else s.roleMismatchCost)
            if (cost < bestCost) {
                bestCost = cost
                best = k
            }
        }
        if (best < 0) continue
        free[best] = false
        if (m == i) mine = spots[best]
    }
    var f = mine ?: formationSpot(i, Tuning.AI.Shape.kSupporting)
    val o = nearest(f, rosters[1 - team])
    if (o != null && o.distance < s.crowdedDistance) {
        val n = Pitch.unit(f.x - players[o.index].pos.x, f.z - players[o.index].pos.z)
        f = Vec(f.x + n.x * s.crowdedShiftAcross, f.z + n.z * s.crowdedShiftAlong)
    }
    return f
}

// §7.5 — shape, spacing and discipline

/** The home spot moved toward the ball (at most 0.9 of the way along the pitch). */
internal fun Match.formationSpot(i: Int, k: Double): Vec {
    val s = Tuning.AI.Shape
    val p = players[i]
    val defender = p.role == Role.DEFENDER
    val dir = Pitch.direction(p.team)
    val along = (if (defender) s.spotAlongDefender else s.spotAlongForward) *
        (s.spotPushBase + s.spotPushPerPushUp * tactics[p.team].pushUp) * s.spotPushFactor * k
    var z = p.home.z + (ball.pos.z - p.home.z) * Pitch.clamp(along, 0.0, s.spotMaxFraction)
    val x = p.home.x + (ball.pos.x - p.home.x) * (if (defender) s.spotAcrossDefender else s.spotAcrossForward)
    if (defender && dir * z > dir * ball.pos.z + s.defenderMaxAhead && dir * ball.pos.z < 0) {
        z = ball.pos.z - dir * s.defenderMaxAhead
    }
    return Vec(x, z)
}

/** The zone a disciplined player holds. */
private fun Match.zone(i: Int): Vec {
    val s = Tuning.AI.Shape
    val p = players[i]
    val follow = (if (p.role == Role.DEFENDER) s.zoneAlongDefender else s.zoneAlongForward) *
        (s.zonePushBase + s.zonePushPerPushUp * tactics[p.team].pushUp)
    return Vec(p.home.x + (ball.pos.x - p.home.x) * s.zoneAcross, p.home.z + (ball.pos.z - p.home.z) * follow)
}

/** Discipline, the distance from the ball, the spacing from team-mates and the crease (§7.5). */
internal fun Match.shaped(i: Int, target: Vec, possession: Possession): Vec {
    val s = Tuning.AI.Shape
    val team = players[i].team
    val discipline = tactics[team].discipline
    val z = zone(i)
    var t = Vec(target.x + (z.x - target.x) * discipline, target.z + (z.z - target.z) * discipline)
    t = keptClear(t, ball.pos, if (possession == Possession.THEIRS) s.ballDistanceDefending else s.ballDistance)
    val gap = if (possession == Possession.OWN) s.mateDistancePossession else s.mateDistanceOtherwise
    for (q in outfield(team)) {
        if (q == i) continue
        val dx = t.x - players[q].pos.x
        val dz = t.z - players[q].pos.z
        val d = Pitch.length(dx, dz)
        if (d < gap && d > Tuning.Sim.clearEpsilon) {
            val push = gap - d
            t = Vec(t.x + dx / d * push, t.z + dz / d * push)
        }
    }
    return outOfCrease(team, t)
}

/** [target] pushed to at least [distance] from [point] (along +x when it sits on it). */
internal fun keptClear(target: Vec, point: Vec, distance: Double): Vec {
    val dx = target.x - point.x
    val dz = target.z - point.z
    val d = Pitch.length(dx, dz)
    if (d >= distance) return target
    val n = if (d > Tuning.Sim.clearEpsilon) Vec(dx / d, dz / d) else Vec(1.0, 0.0)
    return Vec(point.x + n.x * distance, point.z + n.z * distance)
}

/** First at least 2.2 in front of their own goal line, then at least 3.2 + 1.2 from its centre. */
internal fun outOfCrease(team: Int, target: Vec): Vec {
    val s = Tuning.AI.Shape
    val gz = Pitch.ownGoalZ(team)
    val dir = Pitch.direction(team)
    var tx = target.x
    var tz = target.z
    val deepest = -(Tuning.Pitch.goalLineZ - s.goalLineMin)
    if (dir * tz < deepest) tz = dir * deepest
    val dx = tx
    val dz = tz - gz
    val d = Pitch.length(dx, dz)
    val keep = Tuning.Pitch.creaseRadius + s.creaseExtra
    if (d < keep && d > 0) {
        val nx = dx / d
        val nz = dz / d
        tx = nx * keep
        tz = gz + abs(nz) * keep * dir
    }
    return Vec(tx, tz)
}
