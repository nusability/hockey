package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.math.DetMath
import kotlin.math.abs

// Automatic play, one team at a time (spec §7): who thinks when, the loose ball (§7.1), the
// challengers (§7.2) and defending (§7.3). Support and shape are in Shape.kt, the carrier in
// CarrierAi.kt, the goalie in GoalieAi.kt.

internal enum class Possession { OWN, THEIRS, LOOSE }

internal fun Match.thinkTeam(team: Int, dt: Double) {
    val carrier = ball.carrier
    val possession = when {
        carrier == null -> Possession.LOOSE
        players[carrier].team == team -> Possession.OWN
        else -> Possession.THEIRS
    }
    val ranking = rankedByBallDistance(team)
    val challengers = if (possession == Possession.THEIRS) pickChallengers(team, carrier!!) else emptyList()
    for (i in rosters[team]) {
        val p = players[i]
        if (p.isDummy) continue
        p.thinkTimer -= dt
        if (p.isGoalie) {
            thinkGoalie(i, dt)
            continue
        }
        if (carrier == i) {
            p.holdTime += dt
            thinkCarrier(i)
            continue
        }
        if (p.thinkTimer > 0) continue
        p.thinkTimer = Tuning.AI.thinkBase + Tuning.AI.thinkSpread * rng.uniform()
        rethink(i, possession, ranking, challengers)
    }
}

/** A non-carrying outfield player's new target (§7.1–§7.5). */
private fun Match.rethink(i: Int, possession: Possession, ranking: List<Match.Nearest>, challengers: List<Int>) {
    val l = Tuning.AI.Loose
    val p = players[i]
    if (p.expectPass > 0) p.expectPass -= Tuning.Release.passExpectationDecay
    var target: Vec
    var chasing = false
    var defending = false
    when (possession) {
        Possession.LOOSE -> {
            val found = ranking.indexOfFirst { it.index == i }
            val rank = if (found >= 0) found else ranking.size
            val pressing = tactics[p.team].pressing
            val many = pressing > l.twoChasersPressing || (ranking.firstOrNull()?.distance ?: 0.0) > l.twoChasersDistance ||
                looseTimer > l.twoChasersLooseTime
            if (p.expectPass > 0) {
                target = routeAroundNet(i, interceptPoint(i))
                chasing = true
            } else if (rank < (if (many) 2 else 1)) {
                target = routeAroundNet(i, chasePoint(i))
                chasing = true
            } else {
                target = supportTarget(i)
            }
        }
        Possession.THEIRS -> {
            if (i in challengers) {
                target = challengePoint()
                chasing = true
            } else {
                target = defendTarget(i)
                defending = true
            }
        }
        Possession.OWN -> target = supportTarget(i)
    }
    if (!defending) p.mark = null
    if (!chasing) target = shaped(i, target, possession)
    p.target = clampToPlay(target)
}

/** The team's outfield players by distance to the ball, nearest first, roster order on a tie. */
private fun Match.rankedByBallDistance(team: Int): List<Match.Nearest> =
    outfield(team).map { Match.Nearest(it, Pitch.distance(players[it].pos, ball.pos)) }
        .sortedWith { a, b ->
            when {
                a.distance < b.distance -> -1
                b.distance < a.distance -> 1
                else -> a.index.compareTo(b.index)
            }
        }

internal fun clampToPlay(v: Vec): Vec {
    val s = Tuning.AI.Shape
    return Vec(Pitch.clamp(v.x, -s.clampX, s.clampX), Pitch.clamp(v.z, -s.clampZ, s.clampZ))
}

// §7.1 — the loose ball

/** The point on the ball's line of travel nearest the player, ahead of it only; the ball itself below 2. */
private fun Match.interceptPoint(i: Int): Vec {
    val speed = Pitch.length(ball.vel.x, ball.vel.z)
    if (speed < Tuning.AI.Loose.expectSlowBall) return ball.pos
    val ux = ball.vel.x / speed
    val uz = ball.vel.z / speed
    val t = Pitch.greater(0.0, (players[i].pos.x - ball.pos.x) * ux + (players[i].pos.z - ball.pos.z) * uz)
    return Vec(ball.pos.x + ux * t, ball.pos.z + uz * t)
}

/** Where the ball will be: position + 0.7 × velocity × t, t = clamp(d / max(top, 1), 0, 1.2). */
private fun Match.chasePoint(i: Int): Vec {
    val l = Tuning.AI.Loose
    val d = Pitch.distance(players[i].pos, ball.pos)
    val t = Pitch.clamp(d / Pitch.greater(players[i].topSpeed, l.chaseSpeedFloor), 0.0, l.chaseTimeMax)
    return Vec(ball.pos.x + l.chaseLead * ball.vel.x * t, ball.pos.z + l.chaseLead * ball.vel.z * t)
}

/** A chase target at or behind a goal line near the net becomes the net's corner waypoint. */
private fun Match.routeAroundNet(i: Int, target: Vec): Vec {
    val l = Tuning.AI.Loose
    val me = players[i].pos
    for (team in 0 until 2) {
        val gz = Pitch.ownGoalZ(team)
        val dir = Pitch.direction(team)
        if (!(dir * (target.z - gz) < l.cornerLineMargin && abs(target.x) <= l.cornerCenterX &&
                dir * (me.z - gz) > l.cornerLineMargin)
        ) continue
        val side = if (me.x >= 0) 1.0 else -1.0
        return Vec(side * l.cornerWaypointX, gz + dir * l.cornerWaypointInFront)
    }
    return target
}

// §7.2 — challengers

private class Candidate(val index: Int, val committed: Boolean, val goalSide: Boolean, val distance: Double)

/** Who goes in for the ball: the committed, then the goal-side, then the nearest; committed 0.7 s. */
private fun Match.pickChallengers(team: Int, carrier: Int): List<Int> {
    val c = Tuning.AI.Challenge
    val t = tactics[team]
    val pressRange = (c.pressRangeBase + c.pressRangePerPressing * t.pressing) * (1 - c.pressRangeDiscipline * t.discipline)
    val most = if (t.pressing > c.pressingThreshold) c.challengersPressing else c.challengers
    val candidates = ArrayList<Candidate>()
    for (q in outfield(team)) {
        val committed = players[q].challengeUntil > time
        val goalSide = isGoalSide(q, carrier)
        val d = Pitch.distance(players[q].pos, ball.pos)
        if (committed || d < (if (goalSide) c.goalSideRange else pressRange)) candidates.add(Candidate(q, committed, goalSide, d))
    }
    val sorted = candidates.sortedWith { a, b ->
        when {
            a.committed != b.committed -> if (a.committed) -1 else 1
            a.goalSide != b.goalSide -> if (a.goalSide) -1 else 1
            a.distance < b.distance -> -1
            b.distance < a.distance -> 1
            else -> a.index.compareTo(b.index)
        }
    }
    val chosen = sorted.take(most).map { it.index }
    for (q in chosen) players[q].challengeUntil = time + c.commitTime
    return chosen
}

/** At least 0.5 nearer their own goal than the carrier, within 7 of the carrier's route to it. */
private fun Match.isGoalSide(q: Int, carrier: Int): Boolean {
    val c = Tuning.AI.Challenge
    val dir = Pitch.direction(players[q].team)
    if (!(dir * players[carrier].pos.z - dir * players[q].pos.z >= c.goalSideMargin)) return false
    val goal = Vec(0.0, Pitch.ownGoalZ(players[q].team))
    return Pitch.segmentDistance(players[q].pos, players[carrier].pos, goal) < c.goalSideRoute
}

/** Where the ball will be 0.3 s ahead on its orbit, plus the carrier's travel. */
private fun Match.challengePoint(): Vec {
    val ch = Tuning.AI.Challenge
    val c = players[ball.carrier!!]
    val a = ball.orbit + omega * ch.orbitLead * ball.orbitDirection
    val r = Tuning.Orbit.radius
    return Vec(
        c.pos.x + r * DetMath.sin(a) + c.vel.x * ch.orbitLead,
        c.pos.z + r * DetMath.cos(a) + c.vel.z * ch.orbitLead,
    )
}

// §7.3 — defending

private fun Match.defendTarget(i: Int): Vec {
    val df = Tuning.AI.Defend
    val team = players[i].team
    val dir = Pitch.direction(team)
    val covering = tactics[team].covering
    val taken = ArrayList<Int>()
    for (q in rosters[team]) {
        if (q == i) continue
        val m = players[q].mark
        if (m != null) taken.add(m)
    }
    var mark: Int? = null
    var best = Double.POSITIVE_INFINITY
    for (o in outfield(1 - team)) {
        if (o == ball.carrier || o in taken) continue
        val depth = -dir * players[o].pos.z
        val danger = Pitch.distance(players[i].pos, players[o].pos) - df.dangerDepthWeight * depth
        if (danger < best) {
            best = danger
            mark = o
        }
    }
    if (mark != null && rng.uniform() < df.markChanceBase + df.markChancePerCovering * covering) {
        players[i].mark = mark
        val goal = Vec(0.0, Pitch.ownGoalZ(team))
        val o = players[mark]
        val n = Pitch.unit(goal.x - o.pos.x, goal.z - o.pos.z)
        val gap = df.markDistanceBase + df.markDistancePerLoose * (1 - covering)
        return Vec(o.pos.x + n.x * gap, o.pos.z + n.z * gap)
    }
    players[i].mark = null
    val f = formationSpot(i, df.holdK)
    if (dir * f.z > dir * ball.pos.z - df.ballGoalSideTrigger) return Vec(f.x, ball.pos.z - dir * df.ballGoalSideOffset)
    return f
}
