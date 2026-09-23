package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Role
import `in`.nann.smashhockey.core.generated.Tuning
import kotlin.math.PI
import kotlin.math.abs

// Goalies (spec §7.8): positioning, reading a shot, smothering, and playing the ball out. While
// its team is on alert (§7.9) it reads sooner, leads fully and goes the whole way across.

internal fun Match.thinkGoalie(g: Int, dt: Double) {
    if (ball.carrier == g) {
        goalieWithBall(g, dt)
        return
    }
    val gl = Tuning.AI.Goalie
    val team = players[g].team
    val dir = Pitch.direction(team)
    val gz = Pitch.ownGoalZ(team)
    val s = skill[team]
    val al = Tuning.AI.Alert
    val alerted = alert[team] > 0
    var aimX = ball.pos.x
    val released = ball.lastReleaseTime
    var delay = gl.readBase + gl.readPerUnskill * (1 - s)
    if (alerted) delay *= al.goalieReadScale
    // §7.10 — a side that is behind has its keeper read sooner. Never the other way round: a
    // defence is only ever sharpened, never dulled, so no goal is handed to anyone (A0).
    delay *= (1 - Tuning.AI.Balance.chaseGoalieRead * chase(team))
    val reacted = released == null || time - released > delay
    val towards = dir * ball.vel.z < -gl.readSpeed && reacted
    if (towards) {
        val t = (gz - ball.pos.z) / ball.vel.z
        val lead = if (alerted) al.goalieLead else gl.readLeadBase + gl.readLeadPerSkill * s
        if (t > 0 && t < gl.readHorizon) aimX = ball.pos.x + ball.vel.x * t * lead
    }
    val toBall = Pitch.unit(ball.pos.x, ball.pos.z - gz)
    val out = gl.outBase + gl.outPerSkill * s
    var x = toBall.x * out * gl.xScale
    var z = gz + toBall.z * out
    if (towards) x = aimX * (if (alerted) al.goalieAimFactor else gl.readAimFactor)
    val xLimit = Tuning.Pitch.postX + gl.xLimitExtra
    x = Pitch.clamp(x, -xLimit, xLimit)
    z = gz + dir * Pitch.clamp(dir * (z - gz), gl.frontMin, gl.frontMax)
    if (ball.carrier == null && Pitch.distance(players[g].pos, ball.pos) < gl.smotherRange &&
        Pitch.length(ball.vel.x, ball.vel.z) < gl.smotherSpeed && abs(ball.pos.x) < gl.smotherMaxX &&
        dir * (ball.pos.z - gz) < gl.smotherLine
    ) {
        x = ball.pos.x
        z = ball.pos.z
    }
    players[g].target = Vec(x, z)
}

/**
 * With the ball it stands still; after 0.4 s it picks the most open team-mate and releases when
 * the orbit points at them (no lead) — or clears once it points up the pitch — or after 2.5 s.
 */
private fun Match.goalieWithBall(g: Int, dt: Double) {
    val gl = Tuning.AI.Goalie
    val me = players[g]
    val team = me.team
    me.holdTime += dt
    if (me.decision == null && me.holdTime > gl.holdBeforePass) {
        var best: Int? = null
        var bestScore = Double.NEGATIVE_INFINITY
        for (m in outfield(team)) {
            val open = nearest(players[m].pos, rosters[1 - team])?.let { Pitch.clamp(it.distance, 0.0, gl.opennessCap) }
                ?: gl.opennessCap
            var score = open
            if (laneBlocked(me.pos, players[m].pos, team, Tuning.AI.Carrier.passLaneWidth)) score -= gl.blockedPenalty
            if (players[m].role == Role.DEFENDER) score += gl.defenderBonus
            score += rng.noise(gl.pickNoise)
            if (score > bestScore) {
                bestScore = score
                best = m
            }
        }
        me.decision = if (best != null) CarrierDecision.Pass(best) else CarrierDecision.Clear
    }
    val decision = me.decision
    if (decision != null) {
        val aim = if (decision is CarrierDecision.Pass) {
            Pitch.heading(players[decision.to].pos.x - me.pos.x, players[decision.to].pos.z - me.pos.z)
        } else {
            if (team == 0) 0.0 else PI
        }
        if (abs(Pitch.angleDiff(aim, ball.orbit)) < gl.releaseWindow || me.holdTime > gl.releaseTimeout) {
            if (decision is CarrierDecision.Pass) pass(g, decision.to, gl.passAccuracy) else releaseUnassisted(g, ReleaseKind.CLEAR)
            me.decision = null
            me.holdTime = 0.0
            return
        }
    }
    me.target = me.pos
}
