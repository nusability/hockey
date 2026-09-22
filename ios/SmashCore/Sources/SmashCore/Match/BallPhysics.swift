/// The ball (spec §6): carried on the orbit, loose on the pitch, won and stolen.
extension Match {
    // MARK: §4.5 step 7

    mutating func moveLiveBall(_ dt: Double) {
        if let c = ball.carrier {
            moveCarriedBall(c, dt)
        } else {
            moveLooseBall(dt)
        }
    }

    /// Outside play a carried ball follows its carrier (orbiting only in a drill's "get ready"), a
    /// scored ball rolls on in the net, and a loose ball stays put (§4.5, §8.1).
    mutating func moveIdleBall(_ dt: Double) {
        if let c = ball.carrier {
            if state == .ready { ball.orbit = Pitch.wrap(ball.orbit + omega * dt * ball.orbitDirection) }
            placeOnOrbit(c)
        } else if state == .goal, let net = netRoll {
            rollInNet(net.goalZ, net.direction, dt)
        }
    }

    /// The ball on its carrier's orbit, moving with them (§5.1).
    mutating func placeOnOrbit(_ c: Int) {
        ball.pos = orbitPoint(c)
        ball.vel = players[c].vel
    }

    func orbitPoint(_ c: Int) -> Vec {
        let r = Tuning.Orbit.radius
        return Vec(x: players[c].pos.x + r * DetMath.sin(ball.orbit), z: players[c].pos.z + r * DetMath.cos(ball.orbit))
    }

    mutating func moveCarriedBall(_ c: Int, _ dt: Double) {
        ball.orbit = Pitch.wrap(ball.orbit + omega * dt * ball.orbitDirection)
        placeOnOrbit(c)
        if let pending = ball.pending {
            if pending.player != c {
                ball.pending = nil
            } else if let snap = snap(c, orbit: ball.orbit) {
                release(c, to: snap, accuracy: Tuning.Release.playerAccuracy)
                return
            } else if time >= pending.deadline {
                releaseUnassisted(c, kind: .unassisted)
                return
            }
        }
        if !players[c].isGoalie { checkSteal(from: c, dt) }
    }

    // MARK: Loose (§6.2)

    mutating func moveLooseBall(_ dt: Double) {
        let r = sport.ballRadius
        let v = Pitch.length(ball.vel.x, ball.vel.z)
        if v > 0 {
            let drop = Pitch.lesser(v, sport.ballFriction * dt + v * sport.ballDrag * dt)
            let f = (v - drop) / v
            ball.vel = Vec(x: ball.vel.x * f, z: ball.vel.z * f)
            if v > Tuning.Ball.maxSpeed {
                let s = Tuning.Ball.maxSpeed / v
                ball.vel = Vec(x: ball.vel.x * s, z: ball.vel.z * s)
            }
        }
        let prev = ball.pos
        ball.pos = Vec(x: ball.pos.x + ball.vel.x * dt, z: ball.pos.z + ball.vel.z * dt)

        for team in 0..<2 where hitNet(of: team, prev: prev, radius: r) { return }
        for team in 0..<2 { hitPosts(of: team, radius: r) }
        hitBoundary(radius: r)
        deflectOffPlayers(radius: r)
        pickUp(radius: r)
    }

    /// The net team `team` defends (§6.2). Returns true when a goal ended the ball's update.
    mutating func hitNet(of team: Int, prev: Vec, radius r: Double) -> Bool {
        typealias P = Tuning.Pitch
        let gz = Pitch.ownGoalZ(team)
        let dir = Pitch.direction(team)
        let hw = P.goalMouthWidth / 2 + P.netFrameMargin
        let back = gz - dir * (P.goalDepth + P.netFrameMargin)
        let zMin = Pitch.lesser(gz, back) - r
        let zMax = Pitch.greater(gz, back) + r
        guard ball.pos.x.magnitude < hw + r && ball.pos.z > zMin && ball.pos.z < zMax else { return false }
        let wasInFront = dir * (prev.z - gz) >= -(r * Tuning.Ball.goalLineMargin)
        if wasInFront && prev.x.magnitude < P.goalMouthWidth / 2 - Tuning.Ball.goalMouthInset * r {
            if dir * (ball.pos.z - gz) < -(r * Tuning.Ball.goalLineMargin) {
                scoreGoal(for: 1 - team)
                return true
            }
            return false
        }
        if wasInFront { return false }
        let pushSide = hw + r - ball.pos.x.magnitude
        let pushBack = dir > 0 ? ball.pos.z - zMin : zMax - ball.pos.z
        if pushSide < pushBack {
            ball.pos.x += ball.pos.x >= 0 ? pushSide : -pushSide
            ball.vel.x = -ball.vel.x * sport.wallRestitution
        } else {
            ball.pos.z += dir > 0 ? -pushBack : pushBack
            ball.vel.z = -ball.vel.z * sport.wallRestitution
        }
        return false
    }

    mutating func hitPosts(of team: Int, radius r: Double) {
        typealias P = Tuning.Pitch
        let gz = Pitch.ownGoalZ(team)
        for sx in [-1.0, 1.0] {
            let px = sx * P.postX
            let dx = ball.pos.x - px
            let dz = ball.pos.z - gz
            let d = Pitch.length(dx, dz)
            let reach = r + P.postRadius
            guard d < reach && d > Tuning.Sim.contactEpsilon else { continue }
            let nx = dx / d
            let nz = dz / d
            ball.pos = Vec(x: px + nx * reach, z: gz + nz * reach)
            let vn = ball.vel.x * nx + ball.vel.z * nz
            if vn < 0 {
                let j = (1 + P.postRestitution) * vn
                ball.vel = Vec(x: ball.vel.x - j * nx, z: ball.vel.z - j * nz)
                emit(.post)
            }
        }
    }

    mutating func hitBoundary(radius r: Double) {
        let (sd, n) = Pitch.boundary(ball.pos.x, ball.pos.z, corner: sport.cornerRadius)
        guard sd > -r else { return }
        let pen = sd + r
        ball.pos = Vec(x: ball.pos.x - n.x * pen, z: ball.pos.z - n.z * pen)
        let vn = ball.vel.x * n.x + ball.vel.z * n.z
        guard vn > 0 else { return }
        let j = (1 + sport.wallRestitution) * vn
        ball.vel = Vec(x: ball.vel.x - j * n.x, z: ball.vel.z - j * n.z)
        if vn > Tuning.Ball.boardHitSpeed { emit(.board(speed: vn)) }
    }

    mutating func deflectOffPlayers(radius r: Double) {
        for i in players.indices {
            let p = players[i]
            let dx = ball.pos.x - p.pos.x
            let dz = ball.pos.z - p.pos.z
            let d = Pitch.length(dx, dz)
            let reach = p.radius + r
            guard d < reach && d > Tuning.Sim.contactEpsilon else { continue }
            let nx = dx / d
            let nz = dz / d
            ball.pos = Vec(x: p.pos.x + nx * reach, z: p.pos.z + nz * reach)
            let vn = (ball.vel.x - p.vel.x) * nx + (ball.vel.z - p.vel.z) * nz
            guard vn < 0 else { continue }
            let restitution = p.isGoalie ? Tuning.Ball.goalieRestitution : Tuning.Ball.playerRestitution
            let j = (1 + restitution) * vn
            ball.vel = Vec(x: ball.vel.x - j * nx, z: ball.vel.z - j * nz)
            if p.isGoalie { emit(.save(by: i)) } else if p.isDummy { emit(.block(by: i)) }
        }
    }

    // MARK: Picking it up (§6.3)

    mutating func pickUp(radius r: Double) {
        var best: Int?
        var bestDistance = Double.infinity
        for i in players.indices where !players[i].isDummy && players[i].pickupCooldown <= 0 {
            let p = players[i]
            let reach = p.isGoalie ? p.radius + r + Tuning.Ball.pickupReachGoalieExtra : Tuning.Ball.pickupReachOutfield
            let d = Pitch.distance(ball.pos, p.pos)
            if d < reach && d < bestDistance { best = i; bestDistance = d }
        }
        guard let i = best else { return }
        let p = players[i]
        let relative = Pitch.length(ball.vel.x - p.vel.x, ball.vel.z - p.vel.z)
        let limit: Double
        if p.isGoalie {
            limit = Tuning.Ball.pickupLimitGoalie
        } else if let t = ball.lastTouch, players[t].team == p.team {
            limit = Tuning.Ball.pickupLimitOwnTouch
        } else {
            limit = Tuning.Ball.pickupLimitOther
        }
        if relative < limit {
            takeBall(i, reorient: true)
        } else {
            ball.lastTouch = i
        }
    }

    /// Player `p` wins the ball (§5.1, §6.3, §6.4). `reorient` is false only for a drill's start,
    /// whose orbit angle is set from behind the player.
    mutating func takeBall(_ p: Int, reorient: Bool) {
        let previous = ball.carrier
        if previous == p { return }
        if let prev = previous, players[prev].team != players[p].team {
            players[prev].pickupCooldown = Tuning.Ball.stealLoserCooldown
            emit(.steal(by: p, from: prev))
        } else if reorient {
            emit(.pickup(player: p))
        }
        if let t = ball.lastTouch, t != p, players[t].team == players[p].team {
            ball.assist = t
        } else {
            ball.assist = nil
        }
        ball.carrier = p
        ball.wonAt = time
        ball.vel = .zero
        ball.pending = nil
        if reorient { ball.orbit = Pitch.heading(ball.pos.x - players[p].pos.x, ball.pos.z - players[p].pos.z) }
        ball.orbitDirection = orbitDirection(for: p)
        ball.pos = orbitPoint(p)
        ball.lastTouch = p
        players[p].holdTime = 0
        players[p].decision = nil
        if let drill, drill.rule != .freePlay, players[p].team == 1, state == .play {
            interruptDrill(players[p].isGoalie ? .saved : .stolen)
        }
    }

    // MARK: Stealing it (§6.4)

    mutating func checkSteal(from c: Int, _ dt: Double) {
        guard time - ball.wonAt >= Tuning.Ball.settleTime else { return }
        let carrierTeam = players[c].team
        for i in rosters[1 - carrierTeam] where !players[i].isDummy && players[i].pickupCooldown <= 0 {
            let p = players[i]
            let reach = p.isGoalie ? p.radius + Tuning.Ball.stealReachGoalieExtra : Tuning.Ball.stealReachOutfield
            if Pitch.distance(ball.pos, p.pos) < reach {
                players[i].stealContact = p.stealContact + dt
            } else {
                players[i].stealContact = Pitch.greater(0, p.stealContact - dt * Tuning.Ball.stealDecayFactor)
            }
            if players[i].stealContact >= Tuning.Ball.stealTime {
                players[i].stealContact = 0
                takeBall(i, reorient: true)
                return
            }
        }
    }

    // MARK: After a goal (§8.1)

    /// A scored ball rolls on inside the net: it slows by exp(−4·dt) and bounces off the net's back
    /// and sides keeping 20 % of its speed.
    mutating func rollInNet(_ goalZ: Double, _ dir: Double, _ dt: Double) {
        let r = sport.ballRadius
        ball.pos = Vec(x: ball.pos.x + ball.vel.x * dt, z: ball.pos.z + ball.vel.z * dt)
        let f = DetMath.exp(-(Tuning.Ball.netRollDrag * dt))
        ball.vel = Vec(x: ball.vel.x * f, z: ball.vel.z * f)
        let back = goalZ - dir * (Tuning.Pitch.goalDepth - r)
        if dir > 0 ? ball.pos.z < back : ball.pos.z > back {
            ball.pos.z = back
            ball.vel.z = -ball.vel.z * Tuning.Ball.netRollBounce
        }
        let hw = Tuning.Pitch.goalMouthWidth / 2 - r
        if ball.pos.x.magnitude > hw {
            ball.pos.x = ball.pos.x >= 0 ? hw : -hw
            ball.vel.x = -ball.vel.x * Tuning.Ball.netRollBounce
        }
    }
}
