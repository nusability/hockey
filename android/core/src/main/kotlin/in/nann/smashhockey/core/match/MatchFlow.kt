package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.DrillRule
import `in`.nann.smashhockey.core.generated.Spot
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.math.DetMath
import kotlin.math.PI

// The match's states and restarts (spec §8, §10, §4.6).

/** §4.5 step 2: timers count down; an expired state moves on. */
internal fun Match.advanceStateMachine(dt: Double) {
    if (state == MatchState.PLAY || state == MatchState.ENDED) return
    stateTimer -= dt
    if (stateTimer > 0) return
    when (state) {
        MatchState.FACE_OFF -> {
            state = MatchState.PLAY
            val a = Pitch.TWO_PI * rng.uniform()
            ball.vel = Vec(Tuning.Match.dropSpeed * DetMath.cos(a), Tuning.Match.dropSpeed * DetMath.sin(a))
            emit(MatchEvent.Play)
        }
        MatchState.READY -> {
            state = MatchState.PLAY
            emit(MatchEvent.Play)
        }
        MatchState.WHISTLE -> setUpFaceOff(restartSpot)
        MatchState.LOST -> resetDrill()
        MatchState.GOAL -> {
            val d = drill
            when {
                d != null -> if (score[0] >= d.goals) finish(MatchResult.WON) else resetDrill()
                overtime -> finish(resultOf(score))
                else -> setUpFaceOff(Tuning.Pitch.faceoffCenter)
            }
        }
        MatchState.PERIOD_END -> {
            if (period < Tuning.Match.periods) {
                period += 1
                clock = periodSeconds
            } else {
                overtime = true
                clock = 0.0
            }
            setUpFaceOff(Tuning.Pitch.faceoffCenter)
        }
        MatchState.PLAY, MatchState.ENDED -> Unit
    }
}

/** §4.5 step 3: the clock; at zero the period, match or drill ends. */
internal fun Match.runClock(dt: Double) {
    if (overtime) return   // sudden death: the clock stops mattering (§8.4)
    clock -= dt
    if (clock > 0) return
    clock = 0.0
    when {
        drill != null -> finish(MatchResult.LOST)
        period < Tuning.Match.periods -> {
            enter(MatchState.PERIOD_END, Tuning.Match.periodPause)
            emit(MatchEvent.PeriodEnd(period))
        }
        cup && score[0] == score[1] -> {
            enter(MatchState.PERIOD_END, Tuning.Match.overtimePause)
            emit(MatchEvent.PeriodEnd(period))
        }
        else -> {
            emit(MatchEvent.PeriodEnd(period))
            finish(resultOf(score))
        }
    }
}

internal fun resultOf(score: IntArray): MatchResult = when {
    score[0] > score[1] -> MatchResult.WON
    score[0] < score[1] -> MatchResult.LOST
    else -> MatchResult.DRAWN
}

internal fun Match.enter(next: MatchState, seconds: Double) {
    state = next
    stateTimer = seconds
}

internal fun Match.finish(outcome: MatchResult) {
    state = MatchState.ENDED
    stateTimer = 0.0
    result = outcome
    emit(MatchEvent.End(outcome))
}

/** §4.5 step 8 — a ball nobody collects (§6.5). */
internal fun Match.checkDeadBall(dt: Double) {
    val slow = ball.carrier == null && Pitch.length(ball.vel.x, ball.vel.z) < Tuning.Ball.deadSpeed
    deadTimer = if (slow) deadTimer + dt else 0.0
    if (deadTimer < Tuning.Ball.deadTime) return
    deadTimer = 0.0
    if (state != MatchState.PLAY) return
    if (drill != null) {
        interruptDrill(DrillInterruption.DEAD_BALL)
        return
    }
    var best = Pitch.faceOffSpots[0]
    var bestDistance = Double.POSITIVE_INFINITY
    for (spot in Pitch.faceOffSpots) {
        val d = Pitch.length(spot.x - ball.pos.x, spot.z - ball.pos.z)
        if (d < bestDistance) {
            bestDistance = d
            best = spot
        }
    }
    restartSpot = best
    enter(MatchState.WHISTLE, Tuning.Ball.whistleDelay)
    ball.carrier = null
    ball.vel = Vec(ball.vel.x * Tuning.Ball.deadSlowFactor, ball.vel.z * Tuning.Ball.deadSlowFactor)
    emit(MatchEvent.Whistle)
}

/** A goal for [team] (§8.5), or a drill's interruption instead (§10). */
internal fun Match.scoreGoal(team: Int) {
    if (state != MatchState.PLAY) return
    var scorer = ball.lastTouch
    val releaser = ball.lastReleaser
    if (scorer != null && players[scorer].team != team && releaser != null && players[releaser].team == team) {
        scorer = releaser
    }
    val ownGoal = scorer != null && players[scorer].team != team
    val a = ball.assist
    val assist = if (a != null && scorer != null && !ownGoal && a != scorer && players[a].team == team) a else null
    val d = drill
    if (d != null) {
        if (team == 1 && d.rule != DrillRule.FREE_PLAY) {
            interruptDrill(DrillInterruption.WRONG_NET)
            return
        }
        if (team == 0 && d.rule == DrillRule.ASSIST && assist == null) {
            interruptDrill(DrillInterruption.NO_ASSIST)
            return
        }
    }
    score[team] += 1
    enter(MatchState.GOAL, if (drill == null) Tuning.Match.goalCelebration else Tuning.Training.goalReset)
    ball.carrier = null
    netRoll = Pair(Pitch.ownGoalZ(1 - team), Pitch.direction(1 - team))
    emit(MatchEvent.Goal(team, scorer, assist, ownGoal))
}

internal fun Match.interruptDrill(reason: DrillInterruption) {
    if (state != MatchState.PLAY) return
    enter(MatchState.LOST, Tuning.Training.lostReset)
    emit(MatchEvent.DrillInterrupted(reason))
}

/** Clears what every face-off and drill reset clears (§4.6). Think timers are kept. */
internal fun Match.clearForRestart() {
    ball.carrier = null
    ball.vel = Vec.ZERO
    ball.lastTouch = null
    ball.lastReleaser = null
    ball.assist = null
    ball.pending = null
    for (p in players) {
        p.vel = Vec.ZERO
        p.target = null
        p.pickupCooldown = 0.0
        p.holdTime = 0.0
        p.decision = null
        p.mark = null
        p.expectPass = 0.0
        p.stealContact = 0.0
        p.challengeUntil = 0.0
        p.onTheBall = false
        p.patrolFresh = true
    }
    looseTimer = 0.0
    deadTimer = 0.0
    alert[0] = 0.0
    alert[1] = 0.0
    inZone[0] = false
    inZone[1] = false
    crossingCarrier = null
    crossingZ = 0.0
    netRoll = null
}

/** A face-off (§8.2): the ball on the spot, each team lined up by roster slot around it. */
internal fun Match.setUpFaceOff(spot: Spot) {
    val m = Tuning.Match
    enter(MatchState.FACE_OFF, m.faceoffTime)
    clearForRestart()
    ball.pos = Vec(spot.x, spot.z)
    for (p in players) {
        val dir = Pitch.direction(p.team)
        val side = dir
        val gz = Pitch.ownGoalZ(p.team)
        var x: Double
        var z: Double
        when (p.slot) {
            0 -> { x = 0.0; z = gz + dir * m.faceoffGoalieOut }
            1 -> { x = spot.x - m.faceoffWingSide * side; z = spot.z - dir * m.faceoffWingBack }
            2 -> { x = spot.x + m.faceoffWingSide * side; z = spot.z - dir * m.faceoffWingBack }
            3 -> { x = spot.x - m.faceoffInnerSide * side; z = spot.z - dir * m.faceoffInnerBack }
            4 -> { x = spot.x; z = spot.z - dir * m.faceoffCenterBack }
            else -> { x = spot.x + m.faceoffInnerSide * side; z = spot.z - dir * m.faceoffInnerBack }
        }
        x = Pitch.clamp(x, -m.faceoffClampX, m.faceoffClampX)
        z = Pitch.clamp(z, -m.faceoffClampZ, m.faceoffClampZ)
        if (!p.isGoalie && dir * (z - gz) < m.faceoffGoalLineMin) z = gz + dir * m.faceoffGoalLineMin
        p.pos = Vec(x, z)
        p.facing = if (p.team == 0) 0.0 else PI
    }
    emit(MatchEvent.FaceOff(spot))
}

/** A drill reset (§10): everyone to their start, the ball orbiting from behind the named player. */
internal fun Match.resetDrill() {
    val d = drill ?: return
    enter(MatchState.READY, Tuning.Training.ready)
    clearForRestart()
    for (p in players) {
        p.pos = p.start
        p.facing = if (p.team == 0) 0.0 else PI
    }
    val holder = rosters[0][d.ballTo]
    ball.orbit = Pitch.wrap(players[holder].facing + PI)
    takeBall(holder, reorient = false)
    emit(MatchEvent.Ready)
}
