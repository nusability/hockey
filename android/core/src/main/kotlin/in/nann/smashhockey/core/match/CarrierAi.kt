package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Tuning
import kotlin.math.abs

// An outfield carrier (spec §7.6–§7.7): the AI's decision and its wait for the orbit to line up,
// and every carrier's movement — the player's carriers included.

internal fun Match.thinkCarrier(i: Int) {
    val c = Tuning.AI.Carrier
    val p = players[i]
    val threat = nearestThreat(i)
    if (!isPlayerControlled(i)) {
        if (p.thinkTimer <= 0 && p.holdTime > c.decideAfter) {
            p.thinkTimer = c.rethinkBase + c.rethinkSpread * rng.uniform()
            if (p.decision == null) p.decision = decide(i, threat?.distance)
        }
        val decision = p.decision
        if (decision != null && releaseIfAligned(i, decision, threat?.distance)) return
    }
    p.target = carrierTarget(i, threat)
}

/** The nearest opponent who can steal, goalies excluded (§7.6). */
private fun Match.nearestThreat(i: Int): Match.Nearest? {
    val team = players[i].team
    val candidates = rosters[1 - team].filter { !players[it].isDummy && !players[it].isGoalie }
    return nearest(players[i].pos, candidates)
}

// §7.6 — the decision

private fun Match.decide(i: Int, threat: Double?): CarrierDecision? {
    val c = Tuning.AI.Carrier
    val me = players[i]
    val team = me.team
    val t = effectiveTactics(team)
    val goal = Vec(0.0, Pitch.attackGoalZ(team))
    val dGoal = Pitch.distance(me.pos, goal)
    val forced = (threat != null && threat < c.forcedThreat) || me.holdTime > c.forcedHold
    var laneClear = true
    for (o in rosters[1 - team]) {
        if (players[o].isGoalie) continue
        if (Pitch.segmentDistance(players[o].pos, me.pos, goal) < c.shootLaneWidth &&
            Pitch.distance(players[o].pos, me.pos) < dGoal
        ) {
            laneClear = false
            break
        }
    }
    val wantShot = dGoal < c.shootRangeBase + c.shootRangePerShooting * t.shooting &&
        (laneClear || dGoal < c.shootClose) && abs(me.pos.x) < c.shootMaxX
    if (wantShot && (rng.uniform() < c.shootChanceBase + c.shootChancePerShooting * t.shooting || forced)) {
        return CarrierDecision.Shoot
    }
    val dir = Pitch.direction(team)
    val ownGoal = Vec(0.0, Pitch.ownGoalZ(team))
    var best: Int? = null
    var bestScore = Double.NEGATIVE_INFINITY
    for (m in outfield(team)) {
        if (m == i) continue
        val d = Pitch.distance(me.pos, players[m].pos)
        if (d < c.passMin || d > c.passMax) continue
        val progress = dir * (players[m].pos.z - me.pos.z)
        val openness = nearest(players[m].pos, rosters[1 - team])?.let { Pitch.clamp(it.distance, 0.0, c.passOpennessCap) }
            ?: c.passOpennessCap
        var score = c.passOpennessWeight * openness + c.passProgressWeight * progress
        if (laneBlocked(me.pos, players[m].pos, team, c.passLaneWidth)) score -= c.passLanePenalty
        if (Pitch.segmentDistance(ownGoal, me.pos, players[m].pos) < c.passOwnGoalZone) score -= c.passOwnGoalPenalty
        if (progress < -c.passBackward) score += c.passBackwardWeight * (progress + c.passBackward)
        if (d > c.passLong) score -= c.passLongWeight * (d - c.passLong)
        if (isOffsideReceiver(m)) score -= c.passOffsidePenalty
        score += rng.noise(c.passNoise)
        if (score > bestScore) {
            bestScore = score
            best = m
        }
    }
    if (best != null && bestScore > c.passThreshold) {
        var urge = c.passChancePerPassing * t.passing
        if (threat != null && threat < c.passChanceThreatDistance) urge += c.passChanceThreat
        if (me.holdTime > c.passChanceHeldTime) urge += c.passChanceHeld
        if (rng.uniform() < urge || forced) return CarrierDecision.Pass(best)
    }
    if (!forced) return null
    if (best != null) return CarrierDecision.Pass(best)
    return if (dGoal < c.forcedShootRange) CarrierDecision.Shoot else CarrierDecision.Clear
}

/** Any opponent within [width] of the segment [from]–[to]. */
internal fun Match.laneBlocked(from: Vec, to: Vec, team: Int, width: Double): Boolean =
    rosters[1 - team].any { Pitch.segmentDistance(players[it].pos, from, to) < width }

/** Releases when the orbit has lined up with the decision's aim; true when the ball left. */
private fun Match.releaseIfAligned(i: Int, decision: CarrierDecision, threat: Double?): Boolean {
    val c = Tuning.AI.Carrier
    val me = players[i]
    val gz = Pitch.attackGoalZ(me.team)
    val aim = when (decision) {
        CarrierDecision.Shoot, CarrierDecision.Clear -> Pitch.heading(0.0 - me.pos.x, gz - me.pos.z)
        is CarrierDecision.Pass -> {
            val m = players[decision.to]
            val d = Pitch.distance(me.pos, m.pos)
            val t = d / Pitch.clamp(c.alignSpeedBase + c.alignSpeedPerMetre * d, c.alignSpeedMin, c.alignSpeedMax)
            val lx = m.pos.x + Tuning.Orbit.leadVelocityFactor * m.vel.x * t
            val lz = m.pos.z + Tuning.Orbit.leadVelocityFactor * m.vel.z * t
            Pitch.heading(lx - me.pos.x, lz - me.pos.z)
        }
    }
    val s = skill[me.team]
    var tolerance = c.alignToleranceBase + c.alignTolerancePerUnskill * (1 - s)
    if (threat != null && threat < c.alignPressedDistance) tolerance += c.alignTolerancePressed
    if (abs(Pitch.angleDiff(aim, ball.orbit)) >= tolerance) return false
    val accuracy = c.accuracyBase + c.accuracyPerSkill * s
    when (decision) {
        CarrierDecision.Shoot -> {
            val power = c.shotPowerBase + c.shotPowerPerSkill * s + c.shotPowerSpread * rng.uniform()
            shoot(i, accuracy, power)
        }
        is CarrierDecision.Pass -> pass(i, decision.to, accuracy)
        CarrierDecision.Clear -> releaseUnassisted(i, ReleaseKind.CLEAR)
    }
    me.decision = null
    return true
}

// §7.7 — every carrier's movement

private fun Match.carrierTarget(i: Int, threat: Match.Nearest?): Vec {
    val mv = Tuning.AI.Movement
    val me = players[i]
    val gz = Pitch.attackGoalZ(me.team)
    val n = Pitch.unit(0.0 - me.pos.x, gz - me.pos.z)
    var tx = me.pos.x + n.x * mv.ahead
    var tz = me.pos.z + n.z * mv.ahead
    if (threat != null && threat.distance < mv.swerveRange) {
        val th = players[threat.index]
        val away = Pitch.unit(me.pos.x - th.pos.x, me.pos.z - th.pos.z)
        val sideX = -n.z
        val sideZ = n.x
        val s = if (away.x * sideX + away.z * sideZ >= 0) 1.0 else -1.0
        tx += sideX * s * mv.swerveSide + away.x * mv.swerveAway
        tz += sideZ * s * mv.swerveSide + away.z * mv.swerveAway
    }
    for (o in rosters[1 - me.team]) {
        if (!players[o].isDummy) continue
        val d = Pitch.distance(players[o].pos, me.pos)
        if (d < mv.dummyRange) {
            val a = Pitch.unit(me.pos.x - players[o].pos.x, me.pos.z - players[o].pos.z)
            val push = mv.dummyPush * (mv.dummyRange - d)
            tx += a.x * push
            tz += a.z * push
        }
    }
    val dGoal = Pitch.length(0.0 - me.pos.x, gz - me.pos.z)
    if (dGoal < mv.goalApproach) {
        val side = if (me.pos.x >= 0) 1.0 else -1.0
        val drift = if (abs(me.pos.x) > mv.goalApproachCenterX) -side else side
        tx = me.pos.x + drift * mv.goalApproachSide
        tz = me.pos.z - (mv.goalApproach - dGoal) * mv.goalApproachPull * n.z
    }
    return clampToPlay(outOfCrease(me.team, Vec(tx, tz)))
}
