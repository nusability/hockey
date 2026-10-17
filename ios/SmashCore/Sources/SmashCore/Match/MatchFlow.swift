/// The match's states and restarts (spec §8, §10, §4.6).
extension Match {
    // MARK: §4.5 step 2 — timers and expiries

    mutating func advanceStateMachine(_ dt: Double) {
        guard state != .play && state != .ended else { return }
        stateTimer -= dt
        guard stateTimer <= 0 else { return }
        switch state {
        case .faceOff:
            state = .play
            let a = Pitch.twoPi * rng.uniform()
            ball.vel = Vec(x: Tuning.Match.dropSpeed * DetMath.cos(a), z: Tuning.Match.dropSpeed * DetMath.sin(a))
            emit(.play)
        case .ready:
            state = .play
            emit(.play)
        case .whistle:
            setUpFaceOff(at: restartSpot)
        case .lost:
            resetDrill()
        case .goal:
            if let drill {
                if score[0] >= drill.goals { finish(.won) } else { resetDrill() }
            } else if overtime {
                finish(Match.result(score))
            } else {
                setUpFaceOff(at: Tuning.Pitch.faceoffCenter)
            }
        case .periodEnd:
            if period < Tuning.Match.periods {
                period += 1
                clock = periodSeconds
            } else {
                overtime = true
                clock = 0
            }
            setUpFaceOff(at: Tuning.Pitch.faceoffCenter)
        case .play, .ended:
            break
        }
    }

    // MARK: §4.5 step 3 — the clock

    mutating func runClock(_ dt: Double) {
        if overtime { return }   // sudden death: the clock stops mattering (§8.4)
        clock -= dt
        guard clock <= 0 else { return }
        clock = 0
        if drill != nil {
            finish(.lost)
        } else if period < Tuning.Match.periods {
            enter(.periodEnd, for: Tuning.Match.periodPause)
            emit(.periodEnd(period: period))
        } else if cup && score[0] == score[1] {
            enter(.periodEnd, for: Tuning.Match.overtimePause)
            emit(.periodEnd(period: period))
        } else {
            emit(.periodEnd(period: period))
            finish(Match.result(score))
        }
    }

    static func result(_ score: [Int]) -> MatchResult {
        score[0] > score[1] ? .won : (score[0] < score[1] ? .lost : .drawn)
    }

    mutating func enter(_ next: MatchState, for seconds: Double) {
        state = next
        stateTimer = seconds
    }

    mutating func finish(_ outcome: MatchResult) {
        state = .ended
        stateTimer = 0
        result = outcome
        emit(.end(result: outcome))
    }

    // MARK: §4.5 step 8 — a ball nobody collects (§6.5)

    mutating func checkDeadBall(_ dt: Double) {
        let slow = ball.carrier == nil && Pitch.length(ball.vel.x, ball.vel.z) < Tuning.Ball.deadSpeed
        deadTimer = slow ? deadTimer + dt : 0
        guard deadTimer >= Tuning.Ball.deadTime else { return }
        deadTimer = 0
        guard state == .play else { return }
        if drill != nil {
            interruptDrill(.deadBall)
            return
        }
        var best = Pitch.faceOffSpots[0]
        var bestDistance = Double.infinity
        for spot in Pitch.faceOffSpots {
            let d = Pitch.length(spot.x - ball.pos.x, spot.z - ball.pos.z)
            if d < bestDistance { bestDistance = d; best = spot }
        }
        restartSpot = best
        enter(.whistle, for: Tuning.Ball.whistleDelay)
        ball.carrier = nil
        ball.vel = Vec(x: ball.vel.x * Tuning.Ball.deadSlowFactor, z: ball.vel.z * Tuning.Ball.deadSlowFactor)
        emit(.whistle)
    }

    // MARK: Goals (§8.5, §10)

    mutating func scoreGoal(for team: Int) {
        guard state == .play else { return }
        var scorer = ball.lastTouch
        if let s = scorer, players[s].team != team, let r = ball.lastReleaser, players[r].team == team {
            scorer = r
        }
        let ownGoal = scorer.map { players[$0].team != team } ?? false
        var assist: Int?
        if let a = ball.assist, let s = scorer, !ownGoal, a != s, players[a].team == team { assist = a }
        if let drill {
            if team == 1 && drill.rule != .freePlay { interruptDrill(.wrongNet); return }
            if team == 0 && drill.rule == .assist && assist == nil { interruptDrill(.noAssist); return }
        }
        score[team] += 1
        enter(.goal, for: drill == nil ? Tuning.Match.goalCelebration : Tuning.Training.goalReset)
        ball.carrier = nil
        netRoll = (Pitch.ownGoalZ(1 - team), Pitch.direction(1 - team))
        emit(.goal(team: team, scorer: scorer, assist: assist, ownGoal: ownGoal))
    }

    mutating func interruptDrill(_ reason: DrillInterruption) {
        guard state == .play else { return }
        enter(.lost, for: Tuning.Training.lostReset)
        emit(.drillInterrupted(reason))
    }

    // MARK: Restarts (§4.6, §8.2, §10)

    /// Clears what every face-off and drill reset clears (§4.6). Think timers are kept.
    mutating func clearForRestart() {
        ball.carrier = nil
        ball.vel = .zero
        ball.lastTouch = nil
        ball.lastReleaser = nil
        ball.assist = nil
        ball.pending = nil
        for i in players.indices {
            players[i].vel = .zero
            players[i].target = nil
            players[i].pickupCooldown = 0
            players[i].holdTime = 0
            players[i].decision = nil
            players[i].mark = nil
            players[i].expectPass = 0
            players[i].stealContact = 0
            players[i].challengeUntil = 0
            players[i].onTheBall = false
            players[i].patrolFresh = true
        }
        looseTimer = 0
        deadTimer = 0
        alert = [0, 0]
        inZone = [false, false]
        crossingCarrier = nil
        crossingZ = 0
        netRoll = nil
    }

    /// A face-off (§8.2): the ball on the spot, each team lined up by roster slot around it.
    mutating func setUpFaceOff(at spot: Spot) {
        if let start = trainingSpawn {
            spawnTraining(start)
            return
        }
        enter(.faceOff, for: Tuning.Match.faceoffTime)
        clearForRestart()
        ball.pos = Vec(x: spot.x, z: spot.z)
        typealias M = Tuning.Match
        for i in players.indices {
            let team = players[i].team
            let dir = Pitch.direction(team)
            let side = dir
            let gz = Pitch.ownGoalZ(team)
            var x: Double
            var z: Double
            switch players[i].slot {
            case 0: x = 0; z = gz + dir * M.faceoffGoalieOut
            case 1: x = spot.x - M.faceoffWingSide * side; z = spot.z - dir * M.faceoffWingBack
            case 2: x = spot.x + M.faceoffWingSide * side; z = spot.z - dir * M.faceoffWingBack
            case 3: x = spot.x - M.faceoffInnerSide * side; z = spot.z - dir * M.faceoffInnerBack
            case 4: x = spot.x; z = spot.z - dir * M.faceoffCenterBack
            default: x = spot.x + M.faceoffInnerSide * side; z = spot.z - dir * M.faceoffInnerBack
            }
            x = Pitch.clamp(x, -M.faceoffClampX, M.faceoffClampX)
            z = Pitch.clamp(z, -M.faceoffClampZ, M.faceoffClampZ)
            if !players[i].isGoalie && dir * (z - gz) < M.faceoffGoalLineMin { z = gz + dir * M.faceoffGoalLineMin }
            players[i].pos = Vec(x: x, z: z)
            players[i].facing = team == 0 ? 0 : Pitch.pi
        }
        emit(.faceOff(spot: spot))
    }

    /// A drill reset (§10): everyone to their start, the ball orbiting from behind the named player,
    /// then 1.4 s of "get ready".
}

/// How a training restart places the ball (training only). See `Match.trainingSpawn`.
public enum TrainingStart: Sendable {
    /// Team 0 holds it, this far from the goal it attacks. Teaches finishing.
    case ours(Double)
    /// Nobody holds it, this far from the goal team 0 attacks. Teaches winning a loose ball.
    case loose(Double)
    /// Team 1 holds it, this far from the goal **team 0 defends**. Teaches taking it back.
    case theirs(Double)
}

extension Match {

    /// Restarts play from a training situation rather than a face-off.
    ///
    /// Everyone is jittered so the policy meets a spread of positions rather than one rehearsed
    /// tableau, and the side without the ball is placed goal-side of it so the situation is a real
    /// contest and not a walk-in.
    mutating func spawnTraining(_ start: TrainingStart) {
        enter(.ready, for: Tuning.Training.ready)
        clearForRestart()

        func jitter(_ scale: Double) -> Double { (spawnRNG.uniform() * 2.0 - 1.0) * scale }

        let dir = Pitch.direction(0)
        let ballX = jitter(8.0)
        let ballZ: Double
        switch start {
        case .ours(let d), .loose(let d): ballZ = Pitch.attackGoalZ(0) - dir * d
        case .theirs(let d): ballZ = Pitch.ownGoalZ(0) + dir * d
        }

        /// Places one side: `holds` gets the ball, the other is pushed goal-side of it.
        /// `defendingTeam` is the side whose goal the ball is heading toward.
        func place(_ team: Int, holds: Bool) -> Int? {
            var holder: Int?
            let toward = Pitch.direction(team)
            for (n, i) in rosters[team].enumerated() {
                if players[i].isGoalie {
                    players[i].pos = Vec(x: 0, z: Pitch.ownGoalZ(team) + toward * 2.5)
                } else if holds && holder == nil {
                    holder = i
                    players[i].pos = Match.clampToPlay(Vec(x: ballX, z: ballZ))
                } else {
                    // With the ball: spread behind it, i.e. back toward our own goal. Without:
                    // between the ball and the goal we **defend**, which is the opposite way again.
                    //
                    // `toward` is the direction this team attacks, so goal-side of the ball for a
                    // defender is `-toward`. Getting that sign wrong put every defender upfield of
                    // the ball and turned each rung into a walk-in: one arm was scoring 14 goals a
                    // match from 24 m before this was caught.
                    let along = holds ? -toward * (2.0 + Double(n) * 2.0)
                                      : -toward * (1.6 + Double(n) * 1.4)
                    players[i].pos = Match.clampToPlay(
                        Vec(x: ballX + jitter(holds ? 10.0 : 7.0), z: ballZ + along + jitter(3.5)))
                }
                players[i].vel = .zero
                players[i].facing = Pitch.heading(0 - players[i].pos.x,
                                                  Pitch.attackGoalZ(team) - players[i].pos.z)
            }
            return holder
        }

        var holder: Int?
        switch start {
        case .ours:
            holder = place(0, holds: true); _ = place(1, holds: false)
        case .theirs:
            _ = place(0, holds: false); holder = place(1, holds: true)
        case .loose:
            // Neither side holds it and neither is favoured: both arrive from their own side.
            _ = place(0, holds: false); _ = place(1, holds: false)
            ball.pos = Match.clampToPlay(Vec(x: ballX, z: ballZ))
            ball.vel = .zero
        }

        if let h = holder {
            ball.orbit = Pitch.wrap(players[h].facing + Pitch.pi)
            takeBall(h, reorient: false)
        }
        emit(.ready)
    }

    mutating func resetDrill() {
        guard let drill else { return }
        enter(.ready, for: Tuning.Training.ready)
        clearForRestart()
        for i in players.indices {
            players[i].pos = players[i].start
            players[i].facing = players[i].team == 0 ? 0 : Pitch.pi
        }
        let holder = rosters[0][drill.ballTo]
        ball.orbit = Pitch.wrap(players[holder].facing + Pitch.pi)
        takeBall(holder, reorient: false)
        emit(.ready)
    }
}
