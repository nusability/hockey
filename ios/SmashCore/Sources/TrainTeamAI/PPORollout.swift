import Foundation
import SmashCore

/// One decision and what it led to: the unit a trainer that assigns credit through time learns from.
struct Transition {
    let team: Int
    let observation: [Double]
    /// The net's own outputs at the moment of deciding — the mean of the distribution explored
    /// around, and what the update moves.
    let mean: [Double]
    /// What was actually done: the mean plus exploration noise.
    let action: [Double]
    /// The log-density of `action` under the policy that chose it, kept so the update can tell how
    /// far the policy has moved since.
    let logp: Double
    /// Everything that happened to this player's side between this decision and its next one.
    var reward = 0.0
    var value = 0.0
    var advantage = 0.0
    var target = 0.0
}

/// One match's worth of transitions, per player, in the order they decided.
struct Rollout {
    var byPlayer: [Int: [Transition]] = [:]
    var goalsFor = 0.0, goalsAgainst = 0.0
    var steals = 0.0, stealsLost = 0.0
    var picks = 0.0, picksLost = 0.0
    var decisions = 0
}

/// Collects rollouts by playing matches with the policy hook attached.
///
/// Every player of both sides is an actor sharing one set of weights, which is how a team game is
/// normally learned: eleven separate policies would need eleven times the experience and would
/// never share what one of them discovered. The mirroring in `PolicyInputs` is what makes it
/// legitimate — team 1 sees the pitch rotated, so one set of weights is not learning two games.
enum Rollouts {

    /// Plays one match and returns what every actor saw, did and got.
    ///
    /// Reward reaches a decision by the interval rule: whatever happens to a side between a
    /// player's decision and its next one is credited to that decision. It is the simplest honest
    /// answer to a problem with no clean one — a goal is the work of several players over several
    /// seconds, and nothing in the simulation says whose.
    static func play(_ net: PolicyNet, seed: Int, cfg: Config, sigma: Double,
                     rngSeed: UInt64) -> Rollout {
        var m = Match(setup(seed, periodSeconds: cfg.periodSeconds))
        m.installPolicies([net, net])      // self-play: one policy, both sides
        m.stamina = cfg.stamina
        m.openNets = cfg.openNets
        if cfg.rung < cfg.spawnLadder.count {
            m.trainingSpawn = cfg.spawnLadder[cfg.rung]
            m.spawnRNG = SplitMix64(seed: UInt64(bitPattern: Int64(seed &* 7919 &+ 13)))
        }
        if cfg.easeCollect && cfg.easeStep < cfg.easeLadder.count {
            m.collectEase = cfg.easeLadder[cfg.easeStep]
        }

        // The hook's scratch space. A box because the hook is a closure the match holds, and it has
        // to outlive each call to it.
        final class Tape: @unchecked Sendable {
            var out = Rollout()
            /// The index, within a player's own trajectory, of the decision still awaiting its
            /// reward — so a tick's events can find the decision they belong to.
            var open: [Int: Int] = [:]
            var gauss: Gauss
            init(seed: UInt64) { gauss = Gauss(seed: seed) }
        }
        let tape = Tape(seed: rngSeed)

        m.policyHook = { player, team, _, observation, mean in
            let action = mean.map { $0 + sigma * tape.gauss.normal() }
            let t = Transition(team: team, observation: observation, mean: mean, action: action,
                               logp: PPO.logProb(action, mean: mean, sigma: sigma))
            tape.out.byPlayer[player, default: []].append(t)
            tape.open[player] = tape.out.byPlayer[player]!.count - 1
            tape.out.decisions += 1
            return action
        }

        let teamOf = m.snapshot.players.map(\.team)
        /// Credits `r` to team `t`: every one of its players' decisions that is still awaiting one.
        func credit(_ t: Int, _ r: Double) {
            for (player, idx) in tape.open where teamOf[player] == t {
                tape.out.byPlayer[player]![idx].reward += r
            }
        }

        let maxTicks = Int(cfg.periodSeconds * 120.0 * 9.0)
        while m.result == nil && m.ticks < maxTicks {
            m.tick()
            for e in m.drainEvents() {
                switch e {
                case .goal(let team, _, _, _):
                    // The objective itself, and the only term here that is not a nudge.
                    credit(team, cfg.ppoGoalReward)
                    credit(1 - team, -cfg.ppoGoalReward)
                    if team == 0 { tape.out.goalsFor += 1 } else { tape.out.goalsAgainst += 1 }
                // **Winning the ball pays the winner and costs the loser nothing.**
                //
                // These were symmetric for one night, charged to whoever lost the ball, on the
                // argument that a race cannot be colluded over. That is backwards, and the run
                // showed it: a zero-sum reward is *indifferent* between "both of us contest hard"
                // and "neither of us bothers", because both net to nothing. Symmetry is what makes
                // idleness free. Loose-ball collection duly fell from 19 a match to 9 against §7's
                // ~90 - the term meant to make it chase the ball made chasing optional.
                //
                // Paid absolutely, going for the ball is strictly better than not, whatever the
                // opponent does, and no equilibrium of mutual idleness survives. Goals stay
                // symmetric: conceding one is genuinely bad, not merely an opportunity missed.
                case .steal(let by, _):
                    let t = teamOf[by]
                    credit(t, cfg.ppoStealReward)
                    if t == 0 { tape.out.steals += 1 } else { tape.out.stealsLost += 1 }
                case .pickup(let by):
                    let t = teamOf[by]
                    credit(t, cfg.ppoPickupReward)
                    if t == 0 { tape.out.picks += 1 } else { tape.out.picksLost += 1 }
                default:
                    break
                }
            }
        }
        m.policyHook = nil        // break the match's reference to the tape
        return tape.out
    }

    /// Generalised advantage estimation along one player's trajectory, bootstrapping zero at the
    /// end because a match genuinely ends — there is no continuation to estimate.
    static func advantages(_ traj: inout [Transition], gamma: Double, lambda: Double) {
        var nextValue = 0.0
        var running = 0.0
        for k in stride(from: traj.count - 1, through: 0, by: -1) {
            let delta = traj[k].reward + gamma * nextValue - traj[k].value
            running = delta + gamma * lambda * running
            traj[k].advantage = running
            traj[k].target = running + traj[k].value
            nextValue = traj[k].value
        }
    }
}
