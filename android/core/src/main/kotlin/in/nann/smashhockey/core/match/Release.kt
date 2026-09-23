package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.math.DetMath
import kotlin.math.abs

// One-touch control (spec §5): where the orbit turns, what a release snaps to, the player's lift
// with its late grace and pending release, and how the ball leaves.

/** What lifting the finger now would do (§5.3). */
enum class LiftOutcome {
    /** Nothing: no player-controlled carrier in play. */
    NONE,
    /** Snaps now (rule 1). */
    SNAP,
    /** Snaps through the late grace (rule 2). */
    LATE_GRACE,
    /** Held pending (rule 3). */
    PENDING,
    /** Leaves unassisted (rule 4). */
    UNASSISTED,
}

// §5.1 — which way the ball turns

/** +1 or −1: toward the goal when in range, else the best team-mate; +1 with no target. */
internal fun Match.orbitDirection(p: Int): Double {
    val o = Tuning.Orbit
    val me = players[p]
    val gz = Pitch.attackGoalZ(me.team)
    val dGoal = Pitch.length(0.0 - me.pos.x, gz - me.pos.z)
    var aim: Double? = null
    if (dGoal < o.spinGoalRange && abs(me.pos.x) < o.spinGoalMaxX) {
        aim = Pitch.heading(0.0 - me.pos.x, gz - me.pos.z)
    } else {
        val dir = Pitch.direction(me.team)
        val opponents = rosters[1 - me.team]
        var best: Int? = null
        var bestScore = Double.NEGATIVE_INFINITY
        for (m in outfield(me.team)) {
            if (m == p) continue
            val d = Pitch.distance(players[m].pos, me.pos)
            if (d < o.spinMateMinDistance) continue
            val openness = nearest(players[m].pos, opponents)?.let { Pitch.lesser(o.spinOpennessCap, it.distance) }
                ?: o.spinOpennessCap
            val progress = dir * (players[m].pos.z - me.pos.z)
            val score = openness + o.spinProgressWeight * progress - o.spinDistanceWeight * Pitch.greater(0.0, d - o.spinDistanceFree)
            if (score > bestScore) {
                bestScore = score
                best = m
            }
        }
        if (best != null) aim = Pitch.heading(players[best].pos.x - me.pos.x, players[best].pos.z - me.pos.z)
    }
    val a = aim ?: return 1.0
    return if (Pitch.angleDiff(a, ball.orbit) >= 0) 1.0 else -1.0
}

// §5.2 — what a release would snap to

/** The snap at orbit angle [a] for carrier [c], with everyone where they are now. */
internal fun Match.snap(c: Int, a: Double): Snap? {
    val o = Tuning.Orbit
    val me = players[c]
    var pass: Int? = null
    var passDiff = Double.POSITIVE_INFINITY
    for (m in outfield(me.team)) {
        if (m == c || isOffsideReceiver(m)) continue
        val lead = leadPoint(m, c)
        val diff = abs(Pitch.angleDiff(Pitch.heading(lead.x - me.pos.x, lead.z - me.pos.z), a))
        if (diff < o.passWindow && diff < passDiff) {
            pass = m
            passDiff = diff
        }
    }
    val gz = Pitch.attackGoalZ(me.team)
    val goalDiff = abs(Pitch.angleDiff(Pitch.heading(0.0 - me.pos.x, gz - me.pos.z), a))
    val dGoal = Pitch.length(0.0 - me.pos.x, gz - me.pos.z)
    val closing = Pitch.clamp((o.goalWindowWidenDistance - dGoal) / o.goalWindowWidenDistance, 0.0, 1.0)
    val window = o.goalWindow + o.goalWindowWiden * closing
    if (goalDiff < window && (pass == null || goalDiff < o.goalOverPassRatio * passDiff || dGoal < o.goalForceDistance)) {
        return Snap.Shot
    }
    return pass?.let { Snap.Pass(it) }
}

/** A team-mate's lead position for a snap (§5.2). */
internal fun Match.leadPoint(m: Int, c: Int): Vec {
    val o = Tuning.Orbit
    val d = Pitch.distance(players[m].pos, players[c].pos)
    val t = d / Pitch.greater(o.leadSpeedMin, o.leadSpeedBase + o.leadSpeedPerMetre * d)
    return Vec(
        players[m].pos.x + o.leadVelocityFactor * players[m].vel.x * t,
        players[m].pos.z + o.leadVelocityFactor * players[m].vel.z * t,
    )
}

// §5.3 — the player's lift

fun Match.previewLift(): LiftOutcome {
    val c = ball.carrier
    if (state != MatchState.PLAY || c == null || !isPlayerControlled(c)) return LiftOutcome.NONE
    if (snap(c, ball.orbit) != null) return LiftOutcome.SNAP
    if (lateSnap(c) != null) return LiftOutcome.LATE_GRACE
    if (earlySnapInstant(c) != null) return LiftOutcome.PENDING
    return LiftOutcome.UNASSISTED
}

private fun Match.lateSnap(c: Int): Snap? {
    for (g in Tuning.Release.lateGrace) {
        val s = snap(c, ball.orbit - omega * g * ball.orbitDirection)
        if (s != null) return s
    }
    return null
}

private fun Match.earlySnapInstant(c: Int): Double? =
    Tuning.Release.earlyLook.firstOrNull { snap(c, ball.orbit + omega * it * ball.orbitDirection) != null }

internal fun Match.playerLift() {
    val c = ball.carrier
    if (state != MatchState.PLAY || c == null || !isPlayerControlled(c)) return
    val accuracy = Tuning.Release.playerAccuracy
    val now = snap(c, ball.orbit)
    if (now != null) {
        release(c, now, accuracy)
        return
    }
    val late = lateSnap(c)
    if (late != null) {
        release(c, late, accuracy)
        return
    }
    val e = earlySnapInstant(c)
    if (e != null) {
        ball.pending = PendingRelease(c, time + e + Tuning.Release.pendingFallback)
        return
    }
    releaseUnassisted(c, ReleaseKind.UNASSISTED)
}

// §5.4 — how the ball leaves

internal fun Match.release(c: Int, snap: Snap, accuracy: Double) {
    when (snap) {
        is Snap.Pass -> pass(c, snap.to, accuracy)
        Snap.Shot -> shoot(c, accuracy, Tuning.Release.shotSpeed)
    }
}

internal fun Match.pass(c: Int, m: Int, accuracy: Double) {
    val r = Tuning.Release
    val d = Pitch.distance(players[m].pos, players[c].pos)
    val speed = Pitch.clamp(r.passSpeedBase + r.passSpeedPerMetre * d, r.passSpeedMin, r.passSpeedMax)
    val t = d / speed
    var aimX = players[m].pos.x + Tuning.Orbit.leadVelocityFactor * players[m].vel.x * t
    var aimZ = players[m].pos.z + Tuning.Orbit.leadVelocityFactor * players[m].vel.z * t
    val spread = r.passNoise * (r.passNoiseOffset - accuracy)
    aimX += rng.noise(spread)
    aimZ += rng.noise(spread)
    if (!launch(c, aimX - players[c].pos.x, aimZ - players[c].pos.z, speed)) return
    players[m].expectPass = r.passExpectation
    players[m].thinkTimer = 0.0
    emit(MatchEvent.Pass(c, m))
}

internal fun Match.shoot(c: Int, accuracy: Double, power: Double) {
    val r = Tuning.Release
    val team = players[c].team
    val gz = Pitch.attackGoalZ(team)
    var half = Tuning.Pitch.postX - r.shotPostInset
    // §7.9: against an alerted defence, distance takes the corner away — from 20 out the shot goes
    // straight at the keeper, from 10 in it still picks its side.
    if (alert[1 - team] > 0) {
        val a = Tuning.AI.Alert
        val d = Pitch.length(0.0 - players[c].pos.x, gz - players[c].pos.z)
        half *= Pitch.clamp((a.placeFull - d) / a.placeSpan, 0.0, 1.0)
    }
    val g = goalieOf(1 - team)
    var aimX = if (g != null) {
        if (players[g].pos.x > 0) -half else half
    } else {
        if (rng.uniform() < r.shotSideChance) -half else half
    }
    if (rng.uniform() < r.shotPullChance) aimX *= r.shotPull
    aimX += rng.noise(r.shotNoise * (r.shotNoiseOffset - accuracy))
    if (!launch(c, aimX - players[c].pos.x, gz - players[c].pos.z, power)) return
    noteShot(c, ReleaseKind.SHOT)
}

/** Along the orbit direction at 24: the player's unassisted release, or an AI clear. */
internal fun Match.releaseUnassisted(c: Int, kind: ReleaseKind) {
    if (!launch(c, DetMath.sin(ball.orbit), DetMath.cos(ball.orbit), Tuning.Release.freeSpeed)) return
    noteShot(c, kind)
}

/** A shot-type release (§8.6): remember its distance to goal for presentation. */
private fun Match.noteShot(c: Int, kind: ReleaseKind) {
    val gz = Pitch.attackGoalZ(players[c].team)
    ball.lastShotDistance = Pitch.length(0.0 - players[c].pos.x, gz - players[c].pos.z)
    emit(MatchEvent.Shot(c, kind))
}

/**
 * The ball leaves carrier [c] from the orbit point along ([dx], [dz]) at [speed], plus 20 % of the
 * carrier's velocity. False (nothing happens) for a direction without length.
 */
private fun Match.launch(c: Int, dx: Double, dz: Double, speed: Double): Boolean {
    val r = Tuning.Release
    val n = Pitch.unit(dx, dz)
    if (n.x == 0.0 && n.z == 0.0) return false
    val me = players[c]
    var from = orbitPoint(c)
    if (abs(from.z) > r.goalGuardZ && abs(from.x) < r.goalGuardX) {
        from = Vec(me.pos.x, Pitch.clamp(me.pos.z, -r.goalGuardClampZ, r.goalGuardClampZ))
    }
    ball.carrier = null
    ball.pending = null
    ball.pos = from
    ball.vel = Vec(n.x * speed + me.vel.x * r.carrierVelocityInherit, n.z * speed + me.vel.z * r.carrierVelocityInherit)
    ball.lastReleaser = c
    ball.lastTouch = c
    ball.lastReleaseTime = time
    me.pickupCooldown = r.releaserCooldown
    return true
}
