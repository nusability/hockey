package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.math.DetMath
import kotlin.math.PI
import kotlin.math.abs

// How players move (spec §3, §8.1, §10): toward their target in play, easing to a stop outside
// it, patrolling dummies on their rails, contact between players, and the boundary and nets.

/** §4.5 step 5. */
internal fun Match.movePlayers(dt: Double, live: Boolean) {
    val blend = 1.0 - DetMath.exp(-(Tuning.Player.accelerationRate * dt))
    for (p in players) {
        if (p.pickupCooldown > 0) p.pickupCooldown -= dt
        if (p.isDummy) {
            movePatrol(p, dt)
            continue
        }
        var wantX = 0.0
        var wantZ = 0.0
        val t = p.target
        if (live && t != null) {
            val dx = t.x - p.pos.x
            val dz = t.z - p.pos.z
            val d = Pitch.length(dx, dz)
            if (d > Tuning.Player.arriveDeadZone) {
                val speed = Pitch.lesser(p.topSpeed, Tuning.Player.arriveGain * d)
                wantX = dx / d * speed
                wantZ = dz / d * speed
            }
        }
        var vx = p.vel.x
        var vz = p.vel.z
        vx += (wantX - vx) * blend
        vz += (wantZ - vz) * blend
        if (!live) {
            vx *= Tuning.Match.easeFactor
            vz *= Tuning.Match.easeFactor
        }
        p.vel = Vec(vx, vz)
        p.pos = Vec(p.pos.x + vx * dt, p.pos.z + vz * dt)
        if (p.isGoalie) {
            p.facing = if (p.team == 0) 0.0 else PI
        } else if (Pitch.length(vx, vz) > Tuning.Player.turnMinSpeed) {
            val turn = Pitch.angleDiff(Pitch.heading(vx, vz), p.facing)
            p.facing = Pitch.wrap(p.facing + turn * Pitch.lesser(1.0, Tuning.Player.turnRate * dt))
        }
    }
}

/** A dummy: a static one stands, a patrolling one slides between its two points (§10). */
private fun Match.movePatrol(p: Athlete, dt: Double) {
    val patrol = p.patrol
    if (patrol == null) {
        p.vel = Vec.ZERO
        return
    }
    val start = p.start
    val k = 0.5 + 0.5 * DetMath.sin(time * patrol.speed + patrol.phase)
    val next = Vec(start.x + (patrol.to.x - start.x) * k, start.z + (patrol.to.z - start.z) * k)
    if (p.patrolFresh) {
        p.vel = Vec.ZERO
        p.patrolFresh = false
    } else {
        p.vel = Vec((next.x - p.pos.x) / dt, (next.z - p.pos.z) / dt)
    }
    p.pos = next
}

/** §4.5 step 6: one pass over every pair in roster order, positions updated in place (§3). */
internal fun Match.resolveContacts() {
    val n = players.size
    for (i in 0 until n) {
        val a = players[i]
        for (j in i + 1 until n) {
            val b = players[j]
            val dx = b.pos.x - a.pos.x
            val dz = b.pos.z - a.pos.z
            val d = Pitch.length(dx, dz)
            val reach = a.radius + b.radius
            if (!(d < reach && d > Tuning.Sim.contactEpsilon)) continue
            val aFixed = a.isDummy
            val bFixed = b.isDummy
            if (aFixed && bFixed) continue
            val nx = dx / d
            val nz = dz / d
            val overlap = reach - d
            val pa = if (aFixed) 0.0 else if (bFixed) overlap else overlap / 2
            val pb = if (bFixed) 0.0 else if (aFixed) overlap else overlap / 2
            a.pos = Vec(a.pos.x - nx * pa, a.pos.z - nz * pa)
            b.pos = Vec(b.pos.x + nx * pb, b.pos.z + nz * pb)
            val closing = (b.vel.x - a.vel.x) * nx + (b.vel.z - a.vel.z) * nz
            if (closing < 0) {
                val half = closing * 0.5
                if (!aFixed) a.vel = Vec(a.vel.x + nx * half, a.vel.z + nz * half)
                if (!bFixed) b.vel = Vec(b.vel.x - nx * half, b.vel.z - nz * half)
            }
        }
    }
}

/** Everyone but a dummy is kept inside the boundary and out of both nets (§3). */
internal fun Match.constrainPlayers() {
    val pitch = Tuning.Pitch
    for (p in players) {
        if (p.isDummy) continue
        val r = p.radius
        val b = Pitch.boundary(p.pos.x, p.pos.z, sport.cornerRadius)
        if (b.distance > -r) {
            val n = b.normal
            val pen = b.distance + r
            p.pos = Vec(p.pos.x - n.x * pen, p.pos.z - n.z * pen)
            val vn = p.vel.x * n.x + p.vel.z * n.z
            if (vn > 0) p.vel = Vec(p.vel.x - n.x * vn, p.vel.z - n.z * vn)
        }
        for (team in 0 until 2) {
            val gz = Pitch.ownGoalZ(team)
            val dir = Pitch.direction(team)
            val back = gz - dir * pitch.goalDepth
            val zMin = Pitch.lesser(gz, back) - r
            val zMax = Pitch.greater(gz, back) + r
            val hx = pitch.goalMouthWidth / 2 + r
            val x = p.pos.x
            val z = p.pos.z
            if (!(abs(x) < hx && z > zMin && z < zMax)) continue
            val outLeft = x + hx
            val outRight = hx - x
            val outFront = if (dir > 0) zMax - z else z - zMin
            val outBack = if (dir > 0) z - zMin else zMax - z
            val least = Pitch.lesser(Pitch.lesser(outLeft, outRight), Pitch.lesser(outFront, outBack))
            p.pos = if (least == outLeft) {
                Vec(-hx, z)
            } else if (least == outRight) {
                Vec(hx, z)
            } else if (least == outFront) {
                Vec(x, if (dir > 0) zMax else zMin)
            } else {
                Vec(x, if (dir > 0) zMin else zMax)
            }
        }
    }
}
