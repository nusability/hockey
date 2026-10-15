/// The learned policy's observation and its decoded action (spec §7).
///
/// **This file is the riskiest code in the policy**, and not for the reason it looks. The forward
/// pass in `DetPolicy` is a dull loop the toolchains guarantee; *this* is ~100 values assembled from
/// match state by hand, and it will be assembled again by hand in Kotlin. Relative frames,
/// mirroring, which player occupies which slot, what a dummy contributes, the normalising
/// constants — every one of those is a place two written-twice ports diverge in a way that still
/// compiles and still passes each side's own tests. So:
///
///   * **Nothing here sorts.** Every player is read in roster order (§3), the order the spec already
///     makes every "for each player" run in, so there is no tiebreak to get wrong. The one ranking
///     the policy wants — how near to the ball this player is among its team-mates — comes from
///     `rankedByBallDistance`, which already has the spec's tie rule and is already pinned.
///   * **Every slot is fixed and padded.** A formation with fewer outfield players, or a drill with
///     dummies, leaves its slots zeroed with a `present` flag at 0 rather than shifting what follows.
///   * **The frame is the thinking player's attacking frame**: x and z both multiplied by the team's
///     direction, the same mirroring §3 applies to team 1's formation spots. That is a 180° rotation,
///     so one set of weights serves both teams without learning the pitch twice.
///   * Once the policy ships, `shared/vectors/policy/` pins this vector itself, not merely the match
///     it leads to (§4.7).
public enum PolicyInputs {
    public static let styleCount = 4
    /// Outfield slots the observation reserves per team (§3: every formation fields five).
    public static let outfieldSlots = 5
    public static let fieldsPerPlayer = 7

    public static let selfCount = 6
    public static let ballCount = 7
    public static let rankCount = 2
    public static let alertCount = 2
    public static let contextCount = 2
    public static let strengthCount = 1
    public static let goalieCount = 4
    public static let homeCount = 2
    /// Where the ball is *going*, and whether one is coming to me (5).
    public static let anticipationCount = 5
    /// What this player decided last time (2) — the policy's own memory. See `observe`.
    public static let memoryCount = 2

    public static let count = selfCount + ballCount + rankCount + alertCount + contextCount
        + strengthCount + styleCount
        + 2 * outfieldSlots * fieldsPerPlayer
        + goalieCount + homeCount + anticipationCount + memoryCount

    /// Two outputs: where to stand, as an offset from the formation spot (§7).
    public static let outputCount = 2

    // The action's scales, which are deliberately **not** the observation's. The offset is measured
    // from the formation spot, so it must span the pitch twice over: a player whose spot is at
    // x = −5 has to be able to reach x = +13.8, which is 1.25 half-widths away. Scaling the action
    // by a half-pitch would make that target literally unrepresentable — the squash saturates at 1
    // — and during the imitation bootstrap it would mean fitting labels the net cannot produce.
    public static let actionXScale = 2.0 * Tuning.Pitch.halfWidth
    public static let actionZScale = 2.0 * Tuning.Pitch.halfLength

    // Normalising divisors. Positions are in half-pitches, velocities in nominal top speeds, so
    // every input sits roughly in [−1, 1] without any input ever being clipped to a constant.
    public static let xScale = Tuning.Pitch.halfWidth
    public static let zScale = Tuning.Pitch.halfLength
    public static let velocityScale = 8.0
    public static let scoreScale = 5.0
    public static let alertScale = Tuning.AI.Alert.seconds
}

/// One thing §7's written rules did, in the form the net would have to produce to do the same:
/// what the player saw, and the **pre-squash** outputs that decode to the target it chose.
///
/// The label is pre-squash so the bootstrap is a plain regression with no activation in the way.
public struct TeachingSample: Sendable {
    public let observation: [Double]
    public let label: [Double]
}

extension Match {

    /// The inverse of `DetPolicy.squash`: `y / (1 − |y|)`, so `squash(unsquash(y)) == y`.
    ///
    /// Bounded well inside ±1 before inverting, because the inverse runs away at the ends and a
    /// label of 10⁶ would dominate the regression over every ordinary one. 0.95 maps to 19, which
    /// is already far past anything the net needs to say.
    static func unsquash(_ y: Double) -> Double {
        let c = Pitch.clamp(y, -0.95, 0.95)
        return c / (1.0 - c.magnitude)
    }

    /// Turns a target chosen by §7's rules into the label the net would need to emit for it.
    func teachingLabel(_ i: Int, target: Vec) -> [Double] {
        let dir = Pitch.direction(players[i].team)
        let home = players[i].home
        let yx = dir * (target.x - home.x) / PolicyInputs.actionXScale
        let yz = dir * (target.z - home.z) / PolicyInputs.actionZScale
        return [Match.unsquash(yx), Match.unsquash(yz)]
    }

    /// Everything the rules taught during this match, in order. Empty unless `teach()` was called.
    public var teaching: [TeachingSample] { teachingTape ?? [] }

    /// Starts recording what §7's rules decide, for the imitation bootstrap (§7).
    public mutating func teach() { teachingTape = [] }

    /// The observation for player `i`, in that player's attacking frame (§7).
    func observe(_ i: Int, ranking: [(index: Int, distance: Double)]) -> [Double] {
        typealias P = PolicyInputs
        let me = players[i]
        let team = me.team
        let other = 1 - team
        let dir = Pitch.direction(team)

        var o = [Double]()
        o.reserveCapacity(P.count)

        // Frame helpers. `place` maps a pitch point into the attacking frame; `offset` maps a
        // difference, which needs the same mirroring and no translation.
        func place(_ v: Vec) -> (Double, Double) { (dir * v.x / P.xScale, dir * v.z / P.zScale) }
        func offset(_ v: Vec) -> (Double, Double) {
            (dir * (v.x - me.pos.x) / P.xScale, dir * (v.z - me.pos.z) / P.zScale)
        }
        func velocity(_ v: Vec) -> (Double, Double) {
            (dir * v.x / P.velocityScale, dir * v.z / P.velocityScale)
        }

        // Self (6).
        let (sx, sz) = place(me.pos)
        let (svx, svz) = velocity(me.vel)
        o += [sx, sz, svx, svz, me.role == .defender ? 1 : 0, me.role == .forward ? 1 : 0]

        // The ball and who has it (7).
        let (bx, bz) = offset(ball.pos)
        let (bvx, bvz) = velocity(ball.vel)
        let carrier = ball.carrier
        let ownBall = carrier.map { players[$0].team == team } ?? false
        o += [bx, bz, bvx, bvz,
              ownBall ? 1 : 0,
              carrier != nil && !ownBall ? 1 : 0,
              carrier == nil ? 1 : 0]

        // How near the ball this player is, among its own outfield (2). Roster order on a tie,
        // which is `rankedByBallDistance`'s rule already (§7).
        let rank = ranking.firstIndex { $0.index == i } ?? ranking.count
        o += [Double(rank) / Double(P.outfieldSlots), rank == 0 ? 1 : 0]

        // The alert window, both ways (2) — §7.9 applies to both teams identically.
        o += [Pitch.clamp(alert[team] / P.alertScale, 0, 1),
              Pitch.clamp(alert[other] / P.alertScale, 0, 1)]

        // Where the match stands (2): the score from this team's side, and how far through it is.
        // `progress` is §7.10's own expression, so the policy sees what the rubberband used to read.
        let lead = Double(score[team] - score[other])
        let elapsed = Double(period - 1) * periodSeconds + (periodSeconds - clock)
        o += [Pitch.clamp(lead / P.scoreScale, -1, 1),
              Pitch.clamp(elapsed / (3.0 * periodSeconds), 0, 1)]

        // The dial (1) and this team's style (4).
        o.append(strength[team])
        o += style[team]

        // Team-mates then opponents, both in roster order, fixed slots, padded (35 + 35).
        for side in [team, other] {
            let outfielders = outfield(side)
            for slot in 0..<P.outfieldSlots {
                if slot < outfielders.count {
                    let k = outfielders[slot]
                    let p = players[k]
                    let (dx, dz) = offset(p.pos)
                    let (dvx, dvz) = velocity(p.vel)
                    o += [1, dx, dz, dvx, dvz,
                          carrier == k ? 1 : 0,
                          p.role == .defender ? 1 : 0]
                } else {
                    o += [0, 0, 0, 0, 0, 0, 0]
                }
            }
        }

        // Both goalies (4).
        for side in [team, other] {
            if let g = goalie(of: side) {
                let (gx, gz) = offset(players[g].pos)
                o += [gx, gz]
            } else {
                o += [0, 0]
            }
        }

        // This player's formation spot (2) — its role in the shape, without the net having to infer
        // it from the slot index.
        let (hx, hz) = place(me.home)
        o += [hx, hz]

        // Anticipation (5): where the ball is going, and whether one is on its way here.
        //
        // These are **features, not rules**. The policy still decides where to stand; it simply no
        // longer has to infer ballistics from a position and a velocity through two ReLU layers.
        // Why they are here: measured over 40 seeds, the learned side held the ball 0.288 of the
        // time against §7's 0.369 — it was losing the contest for a loose ball, which is the one
        // part of §7 built on exactly these two quantities (§7.1). Giving a net better inputs is
        // not the same as giving it the answer.
        let (cx, cz) = offset(chasePoint(i))
        let (ix, iz) = offset(interceptPoint(i))
        o += [cx, cz, ix, iz, Pitch.clamp(me.expectPass, 0, 1)]

        // Memory (2): where this player was already heading, in the same frame and scale the
        // action is written in, so "carry on" is the easiest thing for the net to say.
        //
        // Without this the policy is memoryless, and a memoryless policy re-decides from nothing
        // every 0.12–0.22 s. That is precisely the failure §7.2 exists to prevent — "the ordering
        // re-runs at every re-think and its tiebreaks flip as the two defenders move, so they swap
        // jobs several times a second … and they arrive in a bunch". §7 solves it with a 0.7 s
        // commitment held in `challengeUntil`; the policy cannot read that (it is §7's private
        // state, and the policy replaces §7), so it needs a memory of its own to build commitment
        // out of. It is also why §7's choices looked like noise to a regressor: §7's decision is a
        // function of the match **and its own memory**, and only the first half was on the input.
        let previous = me.target ?? me.home
        o += [dir * (previous.x - me.home.x) / PolicyInputs.actionXScale,
              dir * (previous.z - me.home.z) / PolicyInputs.actionZScale]

        precondition(o.count == P.count, "observe: built \(o.count) inputs, declared \(P.count)")
        return o
    }

    /// Puts a trained policy in charge of `teams`' off-ball outfield play (§7).
    ///
    /// The trainer's and the bench's hook, not the app's: until the policy ships, a `Match` nobody
    /// calls this on is the match `shared/vectors/match/` pins.
    public mutating func installPolicies(_ nets: [PolicyNet?],
                                         strength s: [Double] = [1, 1], style z: [[Double]]? = nil) {
        precondition(nets.count == 2, "installPolicies: one entry per team, nil for §7's rules")
        precondition(s.count == 2, "installPolicies: strength needs one value per team")
        policies = nets
        strength = s
        if let z {
            precondition(z.count == 2 && z.allSatisfy { $0.count == PolicyInputs.styleCount },
                         "installPolicies: style needs \(PolicyInputs.styleCount) values per team")
            style = z
        }
    }

    /// The common case: one net on team 0, §7's rules on team 1.
    public mutating func installPolicy(_ net: PolicyNet, teams: [Int],
                                       strength s: [Double] = [1, 1], style z: [[Double]]? = nil) {
        installPolicies([teams.contains(0) ? net : nil, teams.contains(1) ? net : nil],
                        strength: s, style: z)
    }

    /// Where the policy wants player `i` to stand: its **formation spot (§3) plus** what the two
    /// outputs ask for, in the attacking frame, mapped back out of the frame and clamped (§7).
    ///
    /// The offset is from the formation spot and not from the origin, and that choice is doing real
    /// work. Ten players share one set of weights, so an absolute target makes "every player stands
    /// in the same place" the behaviour at zero output — the whole side piles onto one point, which
    /// is both the worst thing it could do (§7.2) and a place the search struggles to climb out of,
    /// because differentiating ten players has to be learned before anything else can be. Anchored
    /// on the formation spot, zero output means *hold your shape*: already spread, defenders already
    /// deep, roles already distinct. The policy then learns when to leave it, which is the thing we
    /// actually want it to learn.
    ///
    /// This is a parameterisation, not a rule the policy obeys: the offset spans the pitch, so any
    /// target remains reachable from any spot. Nothing here decides where a player goes.
    func policyTarget(_ i: Int, net: PolicyNet, ranking: [(index: Int, distance: Double)]) -> Vec {
        let out = net.forward(observe(i, ranking: ranking))
        let dir = Pitch.direction(players[i].team)
        let fx = DetPolicy.squash(out[0]) * PolicyInputs.actionXScale
        let fz = DetPolicy.squash(out[1]) * PolicyInputs.actionZScale
        let home = players[i].home
        return Match.clampToPlay(Vec(x: home.x + dir * fx, z: home.z + dir * fz))
    }
}
