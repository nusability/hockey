/// One-touch control (spec §5): where the orbit turns, what a release snaps to, the player's lift
/// with its late grace and pending release, and how the ball leaves.
extension Match {
    // MARK: §5.1 — which way the ball turns

    /// +1 or −1: toward the goal when in range, else the best team-mate; +1 with no target.
    func orbitDirection(for p: Int) -> Double {
        typealias O = Tuning.Orbit
        let me = players[p]
        let gz = Pitch.attackGoalZ(me.team)
        let dGoal = Pitch.length(0.0 - me.pos.x, gz - me.pos.z)
        var aim: Double?
        if dGoal < O.spinGoalRange && me.pos.x.magnitude < O.spinGoalMaxX {
            aim = Pitch.heading(0.0 - me.pos.x, gz - me.pos.z)
        } else {
            let dir = Pitch.direction(me.team)
            let opponents = rosters[1 - me.team]
            var best: Int?
            var bestScore = -Double.infinity
            for m in outfield(me.team) where m != p {
                let d = Pitch.distance(players[m].pos, me.pos)
                if d < O.spinMateMinDistance { continue }
                let openness = nearest(to: players[m].pos, among: opponents).map { Pitch.lesser(O.spinOpennessCap, $0.distance) }
                    ?? O.spinOpennessCap
                let progress = dir * (players[m].pos.z - me.pos.z)
                let score = openness + O.spinProgressWeight * progress - O.spinDistanceWeight * Pitch.greater(0, d - O.spinDistanceFree)
                if score > bestScore { bestScore = score; best = m }
            }
            if let m = best { aim = Pitch.heading(players[m].pos.x - me.pos.x, players[m].pos.z - me.pos.z) }
        }
        guard let aim else { return 1 }
        return Pitch.angleDiff(aim, ball.orbit) >= 0 ? 1 : -1
    }

    // MARK: §5.2 — what a release would snap to

    /// The snap at orbit angle `a` for carrier `c`, with everyone where they are now.
    func snap(_ c: Int, orbit a: Double) -> Snap? {
        typealias O = Tuning.Orbit
        let me = players[c]
        var pass: Int?
        var passDiff = Double.infinity
        for m in outfield(me.team) where m != c {
            let lead = leadPoint(of: m, from: c)
            let diff = Pitch.angleDiff(Pitch.heading(lead.x - me.pos.x, lead.z - me.pos.z), a).magnitude
            if diff < O.passWindow && diff < passDiff { pass = m; passDiff = diff }
        }
        let gz = Pitch.attackGoalZ(me.team)
        let goalDiff = Pitch.angleDiff(Pitch.heading(0.0 - me.pos.x, gz - me.pos.z), a).magnitude
        let dGoal = Pitch.length(0.0 - me.pos.x, gz - me.pos.z)
        let closing = Pitch.clamp((O.goalWindowWidenDistance - dGoal) / O.goalWindowWidenDistance, 0, 1)
        let window = O.goalWindow + O.goalWindowWiden * closing
        if goalDiff < window && (pass == nil || goalDiff < O.goalOverPassRatio * passDiff || dGoal < O.goalForceDistance) {
            return .shot
        }
        return pass.map { .pass(to: $0) }
    }

    /// A team-mate's lead position for a snap (§5.2): position + 0.8 × velocity × t,
    /// t = distance / max(14, 11 + 0.55 × distance).
    func leadPoint(of m: Int, from c: Int) -> Vec {
        typealias O = Tuning.Orbit
        let d = Pitch.distance(players[m].pos, players[c].pos)
        let t = d / Pitch.greater(O.leadSpeedMin, O.leadSpeedBase + O.leadSpeedPerMetre * d)
        return Vec(x: players[m].pos.x + O.leadVelocityFactor * players[m].vel.x * t,
                   z: players[m].pos.z + O.leadVelocityFactor * players[m].vel.z * t)
    }

    // MARK: §5.3 — the player's lift

    /// What lifting the finger now would do.
    public enum LiftOutcome: Sendable, Hashable {
        /// Nothing: no player-controlled carrier in play.
        case none
        /// Snaps now (1).
        case snap
        /// Snaps through the late grace (2).
        case lateGrace
        /// Held pending (3).
        case pending
        /// Leaves unassisted (4).
        case unassisted
    }

    public func previewLift() -> LiftOutcome {
        guard state == .play, let c = ball.carrier, isPlayerControlled(c) else { return .none }
        if snap(c, orbit: ball.orbit) != nil { return .snap }
        if lateSnap(c) != nil { return .lateGrace }
        if earlySnapInstant(c) != nil { return .pending }
        return .unassisted
    }

    func lateSnap(_ c: Int) -> Snap? {
        for g in Tuning.Release.lateGrace {
            if let s = snap(c, orbit: ball.orbit - omega * g * ball.orbitDirection) { return s }
        }
        return nil
    }

    func earlySnapInstant(_ c: Int) -> Double? {
        Tuning.Release.earlyLook.first { snap(c, orbit: ball.orbit + omega * $0 * ball.orbitDirection) != nil }
    }

    mutating func playerLift() {
        guard state == .play, let c = ball.carrier, isPlayerControlled(c) else { return }
        let accuracy = Tuning.Release.playerAccuracy
        if let s = snap(c, orbit: ball.orbit) { release(c, to: s, accuracy: accuracy); return }
        if let s = lateSnap(c) { release(c, to: s, accuracy: accuracy); return }
        if let e = earlySnapInstant(c) {
            ball.pending = PendingRelease(player: c, deadline: time + e + Tuning.Release.pendingFallback)
            return
        }
        releaseUnassisted(c, kind: .unassisted)
    }

    // MARK: §5.4 — how the ball leaves

    mutating func release(_ c: Int, to snap: Snap, accuracy: Double) {
        switch snap {
        case .pass(let m): pass(c, to: m, accuracy: accuracy)
        case .shot: shoot(c, accuracy: accuracy, power: Tuning.Release.shotSpeed)
        }
    }

    mutating func pass(_ c: Int, to m: Int, accuracy: Double) {
        typealias R = Tuning.Release
        let d = Pitch.distance(players[m].pos, players[c].pos)
        let speed = Pitch.clamp(R.passSpeedBase + R.passSpeedPerMetre * d, R.passSpeedMin, R.passSpeedMax)
        let t = d / speed
        var aimX = players[m].pos.x + Tuning.Orbit.leadVelocityFactor * players[m].vel.x * t
        var aimZ = players[m].pos.z + Tuning.Orbit.leadVelocityFactor * players[m].vel.z * t
        let spread = R.passNoise * (R.passNoiseOffset - accuracy)
        aimX += rng.noise(spread)
        aimZ += rng.noise(spread)
        guard launch(c, aimX - players[c].pos.x, aimZ - players[c].pos.z, speed: speed) else { return }
        players[m].expectPass = R.passExpectation
        players[m].thinkTimer = 0
        emit(.pass(from: c, to: m))
    }

    mutating func shoot(_ c: Int, accuracy: Double, power: Double) {
        typealias R = Tuning.Release
        let team = players[c].team
        let gz = Pitch.attackGoalZ(team)
        var half = Tuning.Pitch.postX - R.shotPostInset
        // §7.9: against an alerted defence, distance takes the corner away — from 20 out the shot
        // goes straight at the keeper, from 10 in it still picks its side.
        if alert[1 - team] > 0 {
            typealias A = Tuning.AI.Alert
            let d = Pitch.length(0.0 - players[c].pos.x, gz - players[c].pos.z)
            half = half * Pitch.clamp((A.placeFull - d) / A.placeSpan, 0, 1)
        }
        var aimX: Double
        if let g = goalie(of: 1 - team) {
            aimX = players[g].pos.x > 0 ? -half : half
        } else {
            aimX = rng.uniform() < R.shotSideChance ? -half : half
        }
        if rng.uniform() < R.shotPullChance { aimX *= R.shotPull }
        aimX += rng.noise(R.shotNoise * (R.shotNoiseOffset - accuracy))
        guard launch(c, aimX - players[c].pos.x, gz - players[c].pos.z, speed: power) else { return }
        noteShot(c, kind: .shot)
    }

    /// Along the orbit direction at 24: the player's unassisted release, or an AI clear.
    mutating func releaseUnassisted(_ c: Int, kind: ReleaseKind) {
        guard launch(c, DetMath.sin(ball.orbit), DetMath.cos(ball.orbit), speed: Tuning.Release.freeSpeed) else { return }
        noteShot(c, kind: kind)
    }

    /// A shot-type release (§8.6): remember its distance to goal for presentation.
    mutating func noteShot(_ c: Int, kind: ReleaseKind) {
        let gz = Pitch.attackGoalZ(players[c].team)
        ball.lastShotDistance = Pitch.length(0.0 - players[c].pos.x, gz - players[c].pos.z)
        emit(.shot(by: c, kind: kind))
    }

    /// The ball leaves carrier `c` from the orbit point along (dx, dz) at `speed`, plus 20 % of
    /// the carrier's velocity. False (nothing happens) for a direction without length.
    mutating func launch(_ c: Int, _ dx: Double, _ dz: Double, speed: Double) -> Bool {
        typealias R = Tuning.Release
        let n = Pitch.unit(dx, dz)
        if n.x == 0 && n.z == 0 { return false }
        let me = players[c]
        var from = orbitPoint(c)
        if from.z.magnitude > R.goalGuardZ && from.x.magnitude < R.goalGuardX {
            from = Vec(x: me.pos.x, z: Pitch.clamp(me.pos.z, -R.goalGuardClampZ, R.goalGuardClampZ))
        }
        ball.carrier = nil
        ball.pending = nil
        ball.pos = from
        ball.vel = Vec(x: n.x * speed + me.vel.x * R.carrierVelocityInherit,
                       z: n.z * speed + me.vel.z * R.carrierVelocityInherit)
        ball.lastReleaser = c
        ball.lastTouch = c
        ball.lastReleaseTime = time
        players[c].pickupCooldown = R.releaserCooldown
        return true
    }
}
