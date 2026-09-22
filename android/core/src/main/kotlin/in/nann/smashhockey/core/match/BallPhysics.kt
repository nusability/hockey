package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.DrillRule
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.math.DetMath
import kotlin.math.abs

// The ball (spec §6): carried on the orbit, loose on the pitch, won and stolen.

/** §4.5 step 7, in play. */
internal fun Match.moveLiveBall(dt: Double) {
    val c = ball.carrier
    if (c != null) moveCarriedBall(c, dt) else moveLooseBall(dt)
}

/**
 * Outside play a carried ball follows its carrier (orbiting only in a drill's "get ready"), a
 * scored ball rolls on in the net, and a loose ball stays put (§4.5, §8.1).
 */
internal fun Match.moveIdleBall(dt: Double) {
    val c = ball.carrier
    val roll = netRoll
    if (c != null) {
        if (state == MatchState.READY) ball.orbit = Pitch.wrap(ball.orbit + omega * dt * ball.orbitDirection)
        placeOnOrbit(c)
    } else if (state == MatchState.GOAL && roll != null) {
        rollInNet(roll.first, roll.second, dt)
    }
}

/** The ball on its carrier's orbit, moving with them (§5.1). */
internal fun Match.placeOnOrbit(c: Int) {
    ball.pos = orbitPoint(c)
    ball.vel = players[c].vel
}

internal fun Match.orbitPoint(c: Int): Vec {
    val r = Tuning.Orbit.radius
    return Vec(players[c].pos.x + r * DetMath.sin(ball.orbit), players[c].pos.z + r * DetMath.cos(ball.orbit))
}

private fun Match.moveCarriedBall(c: Int, dt: Double) {
    ball.orbit = Pitch.wrap(ball.orbit + omega * dt * ball.orbitDirection)
    placeOnOrbit(c)
    val pending = ball.pending
    if (pending != null) {
        if (pending.player != c) {
            ball.pending = null
        } else {
            val snap = snap(c, ball.orbit)
            if (snap != null) {
                release(c, snap, Tuning.Release.playerAccuracy)
                return
            } else if (time >= pending.deadline) {
                releaseUnassisted(c, ReleaseKind.UNASSISTED)
                return
            }
        }
    }
    if (!players[c].isGoalie) checkSteal(c, dt)
}

// Loose (§6.2)

private fun Match.moveLooseBall(dt: Double) {
    val r = sport.ballRadius
    val v = Pitch.length(ball.vel.x, ball.vel.z)
    if (v > 0) {
        val drop = Pitch.lesser(v, sport.ballFriction * dt + v * sport.ballDrag * dt)
        val f = (v - drop) / v
        ball.vel = Vec(ball.vel.x * f, ball.vel.z * f)
        if (v > Tuning.Ball.maxSpeed) {
            val s = Tuning.Ball.maxSpeed / v
            ball.vel = Vec(ball.vel.x * s, ball.vel.z * s)
        }
    }
    val prev = ball.pos
    ball.pos = Vec(ball.pos.x + ball.vel.x * dt, ball.pos.z + ball.vel.z * dt)

    for (team in 0 until 2) if (hitNet(team, prev, r)) return
    for (team in 0 until 2) hitPosts(team, r)
    hitBoundary(r)
    deflectOffPlayers(r)
    pickUp(r)
}

/** The net team [team] defends (§6.2). True when a goal ended the ball's update. */
private fun Match.hitNet(team: Int, prev: Vec, r: Double): Boolean {
    val p = Tuning.Pitch
    val gz = Pitch.ownGoalZ(team)
    val dir = Pitch.direction(team)
    val hw = p.goalMouthWidth / 2 + p.netFrameMargin
    val back = gz - dir * (p.goalDepth + p.netFrameMargin)
    val zMin = Pitch.lesser(gz, back) - r
    val zMax = Pitch.greater(gz, back) + r
    val x = ball.pos.x
    val z = ball.pos.z
    if (!(abs(x) < hw + r && z > zMin && z < zMax)) return false
    val wasInFront = dir * (prev.z - gz) >= -(r * Tuning.Ball.goalLineMargin)
    if (wasInFront && abs(prev.x) < p.goalMouthWidth / 2 - Tuning.Ball.goalMouthInset * r) {
        if (dir * (z - gz) < -(r * Tuning.Ball.goalLineMargin)) {
            scoreGoal(1 - team)
            return true
        }
        return false
    }
    if (wasInFront) return false
    val pushSide = hw + r - abs(x)
    val pushBack = if (dir > 0) z - zMin else zMax - z
    if (pushSide < pushBack) {
        ball.pos = Vec(x + (if (x >= 0) pushSide else -pushSide), z)
        ball.vel = Vec(-ball.vel.x * sport.wallRestitution, ball.vel.z)
    } else {
        ball.pos = Vec(x, z + (if (dir > 0) -pushBack else pushBack))
        ball.vel = Vec(ball.vel.x, -ball.vel.z * sport.wallRestitution)
    }
    return false
}

private fun Match.hitPosts(team: Int, r: Double) {
    val p = Tuning.Pitch
    val gz = Pitch.ownGoalZ(team)
    for (sx in doubleArrayOf(-1.0, 1.0)) {
        val px = sx * p.postX
        val dx = ball.pos.x - px
        val dz = ball.pos.z - gz
        val d = Pitch.length(dx, dz)
        val reach = r + p.postRadius
        if (!(d < reach && d > Tuning.Sim.contactEpsilon)) continue
        val nx = dx / d
        val nz = dz / d
        ball.pos = Vec(px + nx * reach, gz + nz * reach)
        val vn = ball.vel.x * nx + ball.vel.z * nz
        if (vn < 0) {
            val j = (1 + p.postRestitution) * vn
            ball.vel = Vec(ball.vel.x - j * nx, ball.vel.z - j * nz)
            emit(MatchEvent.Post)
        }
    }
}

private fun Match.hitBoundary(r: Double) {
    val b = Pitch.boundary(ball.pos.x, ball.pos.z, sport.cornerRadius)
    if (b.distance <= -r) return
    val n = b.normal
    val pen = b.distance + r
    ball.pos = Vec(ball.pos.x - n.x * pen, ball.pos.z - n.z * pen)
    val vn = ball.vel.x * n.x + ball.vel.z * n.z
    if (vn <= 0) return
    val j = (1 + sport.wallRestitution) * vn
    ball.vel = Vec(ball.vel.x - j * n.x, ball.vel.z - j * n.z)
    if (vn > Tuning.Ball.boardHitSpeed) emit(MatchEvent.Board(vn))
}

private fun Match.deflectOffPlayers(r: Double) {
    for ((i, p) in players.withIndex()) {
        val dx = ball.pos.x - p.pos.x
        val dz = ball.pos.z - p.pos.z
        val d = Pitch.length(dx, dz)
        val reach = p.radius + r
        if (!(d < reach && d > Tuning.Sim.contactEpsilon)) continue
        val nx = dx / d
        val nz = dz / d
        ball.pos = Vec(p.pos.x + nx * reach, p.pos.z + nz * reach)
        val vn = (ball.vel.x - p.vel.x) * nx + (ball.vel.z - p.vel.z) * nz
        if (vn >= 0) continue
        val restitution = if (p.isGoalie) Tuning.Ball.goalieRestitution else Tuning.Ball.playerRestitution
        val j = (1 + restitution) * vn
        ball.vel = Vec(ball.vel.x - j * nx, ball.vel.z - j * nz)
        if (p.isGoalie) emit(MatchEvent.Save(i)) else if (p.isDummy) emit(MatchEvent.Block(i))
    }
}

// Picking it up (§6.3)

private fun Match.pickUp(r: Double) {
    var best: Int? = null
    var bestDistance = Double.POSITIVE_INFINITY
    for ((i, p) in players.withIndex()) {
        if (p.isDummy || p.pickupCooldown > 0) continue
        val reach = if (p.isGoalie) p.radius + r + Tuning.Ball.pickupReachGoalieExtra else Tuning.Ball.pickupReachOutfield
        val d = Pitch.distance(ball.pos, p.pos)
        if (d < reach && d < bestDistance) {
            best = i
            bestDistance = d
        }
    }
    val i = best ?: return
    val p = players[i]
    val relative = Pitch.length(ball.vel.x - p.vel.x, ball.vel.z - p.vel.z)
    val touch = ball.lastTouch
    val limit = when {
        p.isGoalie -> Tuning.Ball.pickupLimitGoalie
        touch != null && players[touch].team == p.team -> Tuning.Ball.pickupLimitOwnTouch
        else -> Tuning.Ball.pickupLimitOther
    }
    if (relative < limit) takeBall(i, reorient = true) else ball.lastTouch = i
}

/**
 * Player [p] wins the ball (§5.1, §6.3, §6.4). [reorient] is false only for a drill's start, whose
 * orbit angle is set from behind the player.
 */
internal fun Match.takeBall(p: Int, reorient: Boolean) {
    val previous = ball.carrier
    if (previous == p) return
    if (previous != null && players[previous].team != players[p].team) {
        players[previous].pickupCooldown = Tuning.Ball.stealLoserCooldown
        emit(MatchEvent.Steal(p, previous))
    } else if (reorient) {
        emit(MatchEvent.Pickup(p))
    }
    val t = ball.lastTouch
    ball.assist = if (t != null && t != p && players[t].team == players[p].team) t else null
    ball.carrier = p
    ball.wonAt = time
    ball.vel = Vec.ZERO
    ball.pending = null
    if (reorient) ball.orbit = Pitch.heading(ball.pos.x - players[p].pos.x, ball.pos.z - players[p].pos.z)
    ball.orbitDirection = orbitDirection(p)
    ball.pos = orbitPoint(p)
    ball.lastTouch = p
    players[p].holdTime = 0.0
    players[p].decision = null
    val d = drill
    if (d != null && d.rule != DrillRule.FREE_PLAY && players[p].team == 1 && state == MatchState.PLAY) {
        interruptDrill(if (players[p].isGoalie) DrillInterruption.SAVED else DrillInterruption.STOLEN)
    }
}

// Stealing it (§6.4)

internal fun Match.checkSteal(c: Int, dt: Double) {
    if (time - ball.wonAt < Tuning.Ball.settleTime) return
    val carrierTeam = players[c].team
    for (i in rosters[1 - carrierTeam]) {
        val p = players[i]
        if (p.isDummy || p.pickupCooldown > 0) continue
        val reach = if (p.isGoalie) p.radius + Tuning.Ball.stealReachGoalieExtra else Tuning.Ball.stealReachOutfield
        if (Pitch.distance(ball.pos, p.pos) < reach) {
            p.stealContact = p.stealContact + dt
        } else {
            p.stealContact = Pitch.greater(0.0, p.stealContact - dt * Tuning.Ball.stealDecayFactor)
        }
        if (p.stealContact >= Tuning.Ball.stealTime) {
            p.stealContact = 0.0
            takeBall(i, reorient = true)
            return
        }
    }
}

/**
 * A scored ball rolls on inside the net (§8.1): it slows by exp(−4·dt) and bounces off the net's
 * back and sides keeping 20 % of its speed.
 */
private fun Match.rollInNet(goalZ: Double, dir: Double, dt: Double) {
    val r = sport.ballRadius
    ball.pos = Vec(ball.pos.x + ball.vel.x * dt, ball.pos.z + ball.vel.z * dt)
    val f = DetMath.exp(-(Tuning.Ball.netRollDrag * dt))
    ball.vel = Vec(ball.vel.x * f, ball.vel.z * f)
    val back = goalZ - dir * (Tuning.Pitch.goalDepth - r)
    if (if (dir > 0) ball.pos.z < back else ball.pos.z > back) {
        ball.pos = Vec(ball.pos.x, back)
        ball.vel = Vec(ball.vel.x, -ball.vel.z * Tuning.Ball.netRollBounce)
    }
    val hw = Tuning.Pitch.goalMouthWidth / 2 - r
    if (abs(ball.pos.x) > hw) {
        ball.pos = Vec(if (ball.pos.x >= 0) hw else -hw, ball.pos.z)
        ball.vel = Vec(-ball.vel.x * Tuning.Ball.netRollBounce, ball.vel.z)
    }
}
