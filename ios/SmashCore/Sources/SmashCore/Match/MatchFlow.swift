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
