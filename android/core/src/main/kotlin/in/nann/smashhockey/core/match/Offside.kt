package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Spot
import `in`.nann.smashhockey.core.generated.Tuning

/**
 * Offside, the ice sport's one extra rule (spec §8.9): an attacker may not be in the zone before
 * the puck is. The rule itself, the referee who sometimes misses it, and the line the automatic
 * play holds so it mostly does not happen (§7.4).
 *
 * Everything here is inert for a field sport and in a drill — [offsideApplies] is the one gate.
 */

/** Whether §8.9 is in force: the ice sport, in a match. A drill is never whistled offside (§10). */
internal val Match.offsideApplies: Boolean get() = sport.offside && drill == null

/**
 * How far past the blue line it attacks the point [z] is, for team [team]. Positive is inside the
 * attacking zone.
 */
internal fun Match.zoneDepth(team: Int, z: Double): Double =
    Pitch.direction(team) * z - Tuning.Pitch.blueLineZ

/**
 * Whether the ball's centre is inside the zone team [team] attacks (§8.9: the centre is what the
 * line is judged on, so the call reads off the ball's position and nothing finer).
 */
internal fun Match.ballInAttackingZone(team: Int): Boolean = zoneDepth(team, ball.pos.z) > 0

/**
 * The zone team [team] attacks, once entered, stays entered until the ball is `clearDepth` clear of
 * the line again (§8.9) — so a puck rattling on the line is one entry, not twenty.
 */
internal fun Match.zoneStillHeld(team: Int): Boolean =
    zoneDepth(team, ball.pos.z) > -Tuning.Offside.clearDepth

// §4.5 step 8 — the call

/** Judges both teams' zone entries, team 0 then team 1 (§8.9). A whistle ends the check. */
internal fun Match.checkOffside() {
    if (!offsideApplies || state != MatchState.PLAY) return
    for (team in 0 until 2) {
        val held = if (inZone[team]) zoneStillHeld(team) else ballInAttackingZone(team)
        val last = ball.lastTouch
        val entering = held && !inZone[team] && last != null && players[last].team == team
        // The entry is recorded whether or not it is whistled, so the same puck sitting in the zone
        // — or rattling on the line — is judged once and not again on the next step.
        inZone[team] = held
        if (!entering) continue
        offsideEntries += 1
        val offender = offender(team) ?: continue
        offsideStrays += 1
        // The referee misses some (§8.9): one draw, at the call.
        if (rng.uniform() < Tuning.Offside.missChance) {
            offsideMissed += 1
            continue
        }
        whistleOffside(team, offender)
        return
    }
}

/**
 * The first of team [team]'s outfield players, in roster order, standing offside as the ball
 * enters: past the line by more than the margin, and neither the carrier nor the last touch.
 */
internal fun Match.offender(team: Int): Int? = outfield(team).firstOrNull { i ->
    i != ball.carrier && i != ball.lastTouch &&
        zoneDepth(team, players[i].pos.z) > Tuning.Offside.playerMargin
}

/**
 * The whistle (§8.9): play stops exactly as a dead ball does (§6.5), and the restart is the
 * neutral-zone face-off spot nearest the puck on the side of centre it entered.
 */
internal fun Match.whistleOffside(team: Int, offender: Int) {
    restartSpot = offsideRestartSpot(team)
    enter(MatchState.WHISTLE, Tuning.Ball.whistleDelay)
    ball.carrier = null
    ball.vel = Vec(ball.vel.x * Tuning.Ball.deadSlowFactor, ball.vel.z * Tuning.Ball.deadSlowFactor)
    emit(MatchEvent.Offside(team, offender))
}

/**
 * Of the four neutral spots (§1), the one nearest `(the ball's x, direction × 7.0)` — the two on
 * the entered zone's side of centre, and of those the one on the ball's side of the pitch.
 */
internal fun Match.offsideRestartSpot(team: Int): Spot {
    val referenceX = ball.pos.x
    val referenceZ = Pitch.direction(team) * Tuning.Offside.faceoffReferenceZ
    var best = Tuning.Pitch.faceoffNeutral[0]
    var bestDistance = Double.POSITIVE_INFINITY
    for (spot in Tuning.Pitch.faceoffNeutral) {
        val d = Pitch.length(spot.x - referenceX, spot.z - referenceZ)
        if (d < bestDistance) {
            bestDistance = d
            best = spot
        }
    }
    return best
}

// §7.4 — the line the attack holds

/**
 * A non-carrying player's target pulled back to just short of the blue line while the ball is still
 * short of it (§7.4). This is the whole of the AI's respect for the rule in its movement: it leaves
 * the slack a skater's momentum can still eat, which is where a stray run comes from.
 */
internal fun Match.heldAtLine(i: Int, target: Vec): Vec {
    val o = Tuning.Offside
    if (!offsideApplies || i == ball.carrier) return target
    val team = players[i].team
    if (zoneDepth(team, ball.pos.z) >= -o.puckMargin || zoneDepth(team, target.z) <= -o.holdBack) return target
    return Vec(target.x, Pitch.direction(team) * (Tuning.Pitch.blueLineZ - o.holdBack))
}

// §5.2, §7.6 — a team-mate who cannot be passed to

/**
 * Whether a pass to [i] now would put them offside: they are in the zone their team attacks and the
 * ball is not. The aim never snaps to them (§5.2) and an AI carrier's score is penalised for them
 * (§7.6) — the same predicate, so the arrow and the AI agree.
 */
internal fun Match.isOffsideReceiver(i: Int): Boolean {
    if (!offsideApplies) return false
    val team = players[i].team
    return zoneDepth(team, players[i].pos.z) > 0 && !ballInAttackingZone(team)
}

/**
 * Who the whistle would name if the ball entered the zone now — what the apps mark (§8.9, A0).
 * Exactly [offender]'s predicate, for every player, so the mark never lies.
 */
val Match.offsidePlayers: List<Boolean>
    get() {
        if (!offsideApplies || state != MatchState.PLAY) return List(players.size) { false }
        return players.indices.map { i ->
            val team = players[i].team
            players[i].isOutfield && i != ball.carrier && i != ball.lastTouch &&
                zoneDepth(team, players[i].pos.z) > Tuning.Offside.playerMargin && !ballInAttackingZone(team)
        }
    }
