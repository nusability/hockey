/// How players move (spec §3, §8.1, §10): toward their target in play, easing to a stop outside
/// it, patrolling dummies on their rails, contact between players, and the boundary and nets.
extension Match {
    // MARK: §4.5 step 5

    mutating func movePlayers(_ dt: Double, live: Bool) {
        let blend = 1.0 - DetMath.exp(-(Tuning.Player.accelerationRate * dt))
        for i in players.indices {
            if players[i].pickupCooldown > 0 { players[i].pickupCooldown -= dt }
            if players[i].isDummy {
                movePatrol(i, dt)
                continue
            }
            var want = Vec.zero
            if live, let t = players[i].target {
                let dx = t.x - players[i].pos.x
                let dz = t.z - players[i].pos.z
                let d = Pitch.length(dx, dz)
                if d > Tuning.Player.arriveDeadZone {
                    let speed = Pitch.lesser(players[i].topSpeed, Tuning.Player.arriveGain * d)
                    want = Vec(x: dx / d * speed, z: dz / d * speed)
                }
            }
            var v = players[i].vel
            v.x += (want.x - v.x) * blend
            v.z += (want.z - v.z) * blend
            if !live {
                v.x *= Tuning.Match.easeFactor
                v.z *= Tuning.Match.easeFactor
            }
            players[i].vel = v
            players[i].pos = Vec(x: players[i].pos.x + v.x * dt, z: players[i].pos.z + v.z * dt)
            if players[i].isGoalie {
                players[i].facing = players[i].team == 0 ? 0 : Pitch.pi
            } else if Pitch.length(v.x, v.z) > Tuning.Player.turnMinSpeed {
                let turn = Pitch.angleDiff(Pitch.heading(v.x, v.z), players[i].facing)
                players[i].facing = Pitch.wrap(players[i].facing + turn * Pitch.lesser(1, Tuning.Player.turnRate * dt))
            }
        }
    }

    /// A dummy: a static one stands, a patrolling one slides between its two points (§10).
    mutating func movePatrol(_ i: Int, _ dt: Double) {
        guard let patrol = players[i].patrol else {
            players[i].vel = .zero
            return
        }
        let start = players[i].start
        let k = 0.5 + 0.5 * DetMath.sin(time * patrol.speed + patrol.phase)
        let next = Vec(x: start.x + (patrol.to.x - start.x) * k, z: start.z + (patrol.to.z - start.z) * k)
        if players[i].patrolFresh {
            players[i].vel = .zero
            players[i].patrolFresh = false
        } else {
            players[i].vel = Vec(x: (next.x - players[i].pos.x) / dt, z: (next.z - players[i].pos.z) / dt)
        }
        players[i].pos = next
    }

    // MARK: §4.5 step 6

    /// One pass over every pair in roster order, positions updated in place (§3).
    mutating func resolveContacts() {
        let n = players.count
        for i in 0..<n {
            for j in (i + 1)..<n {
                let dx = players[j].pos.x - players[i].pos.x
                let dz = players[j].pos.z - players[i].pos.z
                let d = Pitch.length(dx, dz)
                let reach = players[i].radius + players[j].radius
                guard d < reach && d > Tuning.Sim.contactEpsilon else { continue }
                let aFixed = players[i].isDummy
                let bFixed = players[j].isDummy
                if aFixed && bFixed { continue }
                let nx = dx / d
                let nz = dz / d
                let overlap = reach - d
                let pa = aFixed ? 0 : (bFixed ? overlap : overlap / 2)
                let pb = bFixed ? 0 : (aFixed ? overlap : overlap / 2)
                players[i].pos = Vec(x: players[i].pos.x - nx * pa, z: players[i].pos.z - nz * pa)
                players[j].pos = Vec(x: players[j].pos.x + nx * pb, z: players[j].pos.z + nz * pb)
                let closing = (players[j].vel.x - players[i].vel.x) * nx + (players[j].vel.z - players[i].vel.z) * nz
                if closing < 0 {
                    let half = closing * 0.5
                    if !aFixed { players[i].vel = Vec(x: players[i].vel.x + nx * half, z: players[i].vel.z + nz * half) }
                    if !bFixed { players[j].vel = Vec(x: players[j].vel.x - nx * half, z: players[j].vel.z - nz * half) }
                }
            }
        }
    }

    /// Everyone but a dummy is kept inside the boundary and out of both nets; they may walk
    /// round and behind a net (§3).
    mutating func constrainPlayers() {
        typealias P = Tuning.Pitch
        for i in players.indices where !players[i].isDummy {
            let r = players[i].radius
            let (sd, n) = Pitch.boundary(players[i].pos.x, players[i].pos.z, corner: sport.cornerRadius)
            if sd > -r {
                let pen = sd + r
                players[i].pos = Vec(x: players[i].pos.x - n.x * pen, z: players[i].pos.z - n.z * pen)
                let vn = players[i].vel.x * n.x + players[i].vel.z * n.z
                if vn > 0 { players[i].vel = Vec(x: players[i].vel.x - n.x * vn, z: players[i].vel.z - n.z * vn) }
            }
            for team in 0..<2 {
                let gz = Pitch.ownGoalZ(team)
                let dir = Pitch.direction(team)
                let back = gz - dir * P.goalDepth
                let zMin = Pitch.lesser(gz, back) - r
                let zMax = Pitch.greater(gz, back) + r
                let hx = P.goalMouthWidth / 2 + r
                let x = players[i].pos.x
                let z = players[i].pos.z
                guard x.magnitude < hx && z > zMin && z < zMax else { continue }
                let outLeft = x + hx
                let outRight = hx - x
                let outFront = dir > 0 ? zMax - z : z - zMin
                let outBack = dir > 0 ? z - zMin : zMax - z
                let least = Pitch.lesser(Pitch.lesser(outLeft, outRight), Pitch.lesser(outFront, outBack))
                if least == outLeft {
                    players[i].pos.x = -hx
                } else if least == outRight {
                    players[i].pos.x = hx
                } else if least == outFront {
                    players[i].pos.z = dir > 0 ? zMax : zMin
                } else {
                    players[i].pos.z = dir > 0 ? zMin : zMax
                }
            }
        }
    }
}
