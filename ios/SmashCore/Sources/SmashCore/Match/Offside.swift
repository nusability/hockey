/// Offside, the ice sport's one extra rule (spec §8.9): an attacker may not be in the zone before
/// the puck is. The rule itself, the referee who sometimes misses it, and the line the automatic
/// play holds so it mostly does not happen (§7.4).
///
/// Everything here is inert for a field sport and in a drill — `offsideApplies` is the one gate.
extension Match {
    /// Whether §8.9 is in force: the ice sport, in a match. A drill is never whistled offside (§10).
    var offsideApplies: Bool { sport.offside && drill == nil }

    /// How far past the blue line it attacks the point `z` is, for team `team`. Positive is inside
    /// the attacking zone.
    func zoneDepth(_ team: Int, _ z: Double) -> Double {
        Pitch.direction(team) * z - Tuning.Pitch.blueLineZ
    }

    /// Whether the ball's centre is inside the zone team `team` attacks (§8.9: the centre is what
    /// the line is judged on, so the call reads off the ball's position and nothing finer).
    func ballInAttackingZone(_ team: Int) -> Bool { zoneDepth(team, ball.pos.z) > 0 }

    /// The zone team `team` attacks, once entered, stays entered until the ball is `clearDepth`
    /// clear of the line again (§8.9) — so a puck rattling on the line is one entry, not twenty.
    func zoneStillHeld(_ team: Int) -> Bool { zoneDepth(team, ball.pos.z) > -Tuning.Offside.clearDepth }

    // MARK: §4.5 step 8 — the call

    /// Judges both teams' zone entries, team 0 then team 1 (§8.9). A whistle ends the check.
    mutating func checkOffside() {
        guard offsideApplies, state == .play else { return }
        for team in 0..<2 {
            let held = inZone[team] ? zoneStillHeld(team) : ballInAttackingZone(team)
            let entering = held && !inZone[team] && ball.lastTouch.map { players[$0].team == team } ?? false
            // The entry is recorded whether or not it is whistled, so the same puck sitting in the
            // zone — or rattling on the line — is judged once and not again on the next step.
            inZone[team] = held
            guard entering else { continue }
            offsideEntries += 1
            guard let offender = offender(of: team) else { continue }
            offsideStrays += 1
            // The referee misses some (§8.9): one draw, at the call.
            if rng.uniform() < Tuning.Offside.missChance { offsideMissed += 1; continue }
            whistleOffside(team: team, offender: offender)
            return
        }
    }

    /// The first of team `team`'s outfield players, in roster order, standing offside as the ball
    /// enters: past the line by more than the margin, and neither the carrier nor the last touch.
    func offender(of team: Int) -> Int? {
        outfield(team).first { i in
            i != ball.carrier && i != ball.lastTouch && zoneDepth(team, players[i].pos.z) > Tuning.Offside.playerMargin
        }
    }

    /// The whistle (§8.9): play stops exactly as a dead ball does (§6.5), and the restart is the
    /// neutral-zone face-off spot nearest the puck on the side of centre it entered.
    mutating func whistleOffside(team: Int, offender: Int) {
        restartSpot = offsideRestartSpot(team: team)
        enter(.whistle, for: Tuning.Ball.whistleDelay)
        ball.carrier = nil
        ball.vel = Vec(x: ball.vel.x * Tuning.Ball.deadSlowFactor, z: ball.vel.z * Tuning.Ball.deadSlowFactor)
        emit(.offside(team: team, player: offender))
    }

    /// Of the four neutral spots (§1), the one nearest `(the ball's x, direction × 7.0)` — the two
    /// on the entered zone's side of centre, and of those the one on the ball's side of the pitch.
    func offsideRestartSpot(team: Int) -> Spot {
        let reference = Vec(x: ball.pos.x, z: Pitch.direction(team) * Tuning.Offside.faceoffReferenceZ)
        var best = Tuning.Pitch.faceoffNeutral[0]
        var bestDistance = Double.infinity
        for spot in Tuning.Pitch.faceoffNeutral {
            let d = Pitch.length(spot.x - reference.x, spot.z - reference.z)
            if d < bestDistance { bestDistance = d; best = spot }
        }
        return best
    }

    // MARK: §7.4 — the line the attack holds

    /// A non-carrying player's target pulled back to just short of the blue line while the ball is
    /// still short of it (§7.4). This is the whole of the AI's respect for the rule in its movement:
    /// it leaves the slack a skater's momentum can still eat, which is where a stray run comes from.
    func heldAtLine(_ i: Int, _ target: Vec) -> Vec {
        typealias O = Tuning.Offside
        guard offsideApplies, i != ball.carrier else { return target }
        let team = players[i].team
        guard zoneDepth(team, ball.pos.z) < -O.puckMargin,
              zoneDepth(team, target.z) > -O.holdBack else { return target }
        return Vec(x: target.x, z: Pitch.direction(team) * (Tuning.Pitch.blueLineZ - O.holdBack))
    }

    // MARK: §5.2, §7.6 — a team-mate who cannot be passed to

    /// Whether a pass to `i` now would put them offside: they are in the zone their team attacks and
    /// the ball is not. The aim never snaps to them (§5.2) and an AI carrier's score is penalised
    /// for them (§7.6) — the same predicate, so the arrow and the AI agree.
    func isOffsideReceiver(_ i: Int) -> Bool {
        guard offsideApplies else { return false }
        let team = players[i].team
        return zoneDepth(team, players[i].pos.z) > 0 && !ballInAttackingZone(team)
    }

    /// Who the whistle would name if the ball entered the zone now — what the apps mark (§8.9, A0).
    /// Exactly `offender(of:)`'s predicate, for every player, so the mark never lies.
    public var offsidePlayers: [Bool] {
        guard offsideApplies, state == .play else { return [Bool](repeating: false, count: players.count) }
        return players.indices.map { i in
            guard players[i].isOutfield, i != ball.carrier, i != ball.lastTouch else { return false }
            let team = players[i].team
            return zoneDepth(team, players[i].pos.z) > Tuning.Offside.playerMargin && !ballInAttackingZone(team)
        }
    }
}
