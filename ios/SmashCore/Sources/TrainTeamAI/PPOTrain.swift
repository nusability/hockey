import Foundation
import SmashCore

/// The PPO training loop: collect, estimate, update, repeat.
enum PPOTrain {

    /// One iteration's worth of what happened, for the log.
    struct Report {
        var goalsFor = 0.0, goalsAgainst = 0.0
        var steals = 0.0, stealsLost = 0.0
        var decisions = 0
        var collected = 0, sampled = 0
        /// The share of decisions that carried any reward at all, and the mean size of those that
        /// did. The plain mean is worthless here: a goal pays +1 to one side and −1 to the other,
        /// and in self-play both sides are the same network, so the average cancels to zero whether
        /// credit is reaching decisions or not.
        var rewarded = 0.0
        var rewardSize = 0.0
        var actorLoss = 0.0, criticLoss = 0.0
        var clipped = 0.0
        var sigma = 0.0
    }

    static func run(_ cfg: Config, outDir: String) {
        let nIn = PolicyInputs.count, nOut = PolicyInputs.outputCount
        var actor = Backprop(nIn: nIn, nH: cfg.hidden, nOut: nOut, seed: cfg.seed, lr: cfg.ppoLearningRate)
        // The critic judges a position's worth so the actor can be told whether a decision beat
        // expectation. One output, same observation, same machinery.
        var critic = Backprop(nIn: nIn, nH: cfg.hidden, nOut: 1, seed: cfg.seed &+ 1,
                              lr: cfg.ppoLearningRate)
        if let path = cfg.initFrom {
            let theta = readCheckpoint(path)
            precondition(theta.count == PolicyNet.parameterCount(nIn: nIn, nHidden: cfg.hidden, nOut: nOut),
                         "--init: wrong parameter count for this shape")
            actor.load(theta)
            print("starting from \(path)")
        }

        print("""
            PPO — \(nIn) → \(cfg.hidden) → \(cfg.hidden) → \(nOut), \
            \(cfg.ppoMatches) matches an iteration, \(cfg.ppoEpochs) epochs, \
            clip \(cfg.ppoClip), gamma \(cfg.ppoGamma), lambda \(cfg.ppoLambda)
            """)
        print("reward: \(cfg.ppoGoalReward) a goal, \(cfg.ppoStealReward) a steal won")
        print(" iter   goals      steals   decisions/used  paid%  |r|    actor     critic   clip%  sigma  nets   secs")

        var sigma = cfg.ppoSigma
        let started = Date()
        // A mutable copy: the old trainer's curriculum is driven from its own loop, so nothing here
        // would ever have advanced it — this run would have spent the night with the keepers stood
        // aside and §6.3.1 switched off, learning a game we do not ship.
        var live = cfg
        var canFinish = 0

        for iteration in 1...cfg.iterations {
            let t0 = Date()
            let net = PolicyNet(nIn: nIn, nHidden: cfg.hidden, nOut: nOut, parameters: actor.parameters)

            // ---- collect ------------------------------------------------------------------
            let localCfg = live
            let localSigma = sigma
            let rollouts = parallelRollouts(cfg.ppoMatches) { k in
                Rollouts.play(net, seed: iteration * 101 + k, cfg: localCfg, sigma: localSigma,
                              rngSeed: UInt64(bitPattern: Int64(iteration &* 7919 &+ k)))
            }

            var report = Report()
            report.sigma = sigma
            var batch: [Transition] = []
            for r in rollouts {
                report.goalsFor += r.goalsFor / Double(cfg.ppoMatches)
                report.goalsAgainst += r.goalsAgainst / Double(cfg.ppoMatches)
                report.steals += r.steals / Double(cfg.ppoMatches)
                report.stealsLost += r.stealsLost / Double(cfg.ppoMatches)
                report.decisions += r.decisions
                for (_, traj) in r.byPlayer {
                    var t = traj
                    // The critic's view of every state, before anything is updated.
                    for k in t.indices { t[k].value = critic.forward(t[k].observation).y[0] }
                    Rollouts.advantages(&t, gamma: cfg.ppoGamma, lambda: cfg.ppoLambda)
                    batch.append(contentsOf: t)
                }
            }
            guard !batch.isEmpty else { print("  no decisions collected — nothing to learn from"); return }
            // Advantages are computed on everything collected - a trajectory has to be whole for
            // credit to travel along it - and only then is the batch thinned to the update's
            // ceiling. Sampling uniformly keeps the paid decisions in proportion; dropping whole
            // trajectories would not.
            let collected = batch.count
            if batch.count > cfg.ppoSample {
                var pick = Gauss(seed: cfg.seed &+ UInt64(iteration) &+ 7777)
                for i in stride(from: batch.count - 1, to: 0, by: -1) {
                    let j = Int(pick.uniform() * Double(i + 1))
                    batch.swapAt(i, j)
                }
                batch.removeLast(batch.count - cfg.ppoSample)
            }
            report.sampled = batch.count
            report.collected = collected

            let hit = batch.filter { $0.reward != 0 }
            report.rewarded = Double(hit.count) / Double(batch.count)
            report.rewardSize = hit.isEmpty ? 0 : hit.reduce(0) { $0 + $1.reward.magnitude } / Double(hit.count)

            // Advantages are normalised across the batch: PPO is famously sensitive to their
            // scale, and a match that happens to contain six goals should not dominate one that
            // contains none.
            let meanAdv = batch.reduce(0) { $0 + $1.advantage } / Double(batch.count)
            let varAdv = batch.reduce(0) { $0 + ($1.advantage - meanAdv) * ($1.advantage - meanAdv) }
                / Double(batch.count)
            let sdAdv = Swift.max(varAdv.squareRoot(), 1e-8)
            for k in batch.indices { batch[k].advantage = (batch[k].advantage - meanAdv) / sdAdv }

            // ---- update -------------------------------------------------------------------
            var g = Gauss(seed: cfg.seed &+ UInt64(iteration))
            var clippedCount = 0, counted = 0
            for _ in 0..<cfg.ppoEpochs {
                for i in stride(from: batch.count - 1, to: 0, by: -1) {
                    let j = Int(g.uniform() * Double(i + 1))
                    batch.swapAt(i, j)
                }
                var start = 0
                while start < batch.count {
                    let end = Swift.min(start + cfg.ppoBatch, batch.count)
                    let slice = batch[start..<end]
                    let n = Double(slice.count)

                    var ga = Backprop.Grads(nIn: nIn, nH: cfg.hidden, nOut: nOut)
                    var gc = Backprop.Grads(nIn: nIn, nH: cfg.hidden, nOut: 1)
                    var aLoss = 0.0, cLoss = 0.0

                    for t in slice {
                        // Actor: the clipped surrogate.
                        let f = actor.forward(t.observation)
                        let logp = PPO.logProb(t.action, mean: f.y, sigma: localSigma)
                        let ratio = Foundation.exp(logp - t.logp)
                        let unclipped = ratio * t.advantage
                        let clamped = Swift.max(1 - cfg.ppoClip, Swift.min(1 + cfg.ppoClip, ratio))
                        let clipped = clamped * t.advantage
                        aLoss += -Swift.min(unclipped, clipped)
                        counted += 1
                        if clipped < unclipped { clippedCount += 1 }
                        // Gradient of the *loss*, so descent maximises the surrogate. Zero exactly
                        // where the clip binds — that is the mechanism, not an optimisation.
                        let dRatio = (unclipped <= clipped) ? -t.advantage / n : 0.0
                        let dMean = PPO.dLogProbDMean(t.action, mean: f.y, sigma: localSigma)
                        var dy = [Double](repeating: 0, count: nOut)
                        for o in 0..<nOut { dy[o] = dRatio * ratio * dMean[o] }
                        actor.backward(t.observation, f, dy: dy, into: &ga)

                        // Critic: squared error against the return.
                        let fv = critic.forward(t.observation)
                        let e = fv.y[0] - t.target
                        cLoss += e * e
                        critic.backward(t.observation, fv, dy: [2.0 * e / n], into: &gc)
                    }

                    actor.apply(ga.flat)
                    critic.apply(gc.flat)
                    report.actorLoss += aLoss / n
                    report.criticLoss += cLoss / n
                    start = end
                }
            }
            let updates = Double(cfg.ppoEpochs) * Swift.max(1, (Double(batch.count) / Double(cfg.ppoBatch)).rounded(.up))
            report.actorLoss /= updates
            report.criticLoss /= updates
            report.clipped = counted > 0 ? Double(clippedCount) / Double(counted) : 0

            // Exploration shrinks as the policy settles, with a floor so it never stops looking.
            sigma = Swift.max(cfg.ppoSigmaFloor, sigma * cfg.ppoSigmaDecay)

            // The keepers come back once it can finish, and once shut they stay shut — a curriculum
            // that oscillates teaches a policy to straddle both worlds and master neither.
            if live.openNets {
                canFinish = report.goalsFor >= cfg.closeNetsAt ? canFinish + 1 : 0
                if canFinish >= cfg.holdFor {
                    live.openNets = false
                    print(String(format: "  = scoring %.2f a match with the nets open - keepers back on from here",
                                 report.goalsFor))
                }
            }

            print(String(format: "%5d  %.2f-%.2f  %4.1f-%.1f  %8d/%-6d  %5.2f  %.2f  %+.5f  %7.4f  %4.1f  %.3f  %@  %6.1f",
                         iteration, report.goalsFor, report.goalsAgainst,
                         report.steals, report.stealsLost, report.decisions, report.sampled,
                         report.rewarded * 100, report.rewardSize,
                         report.actorLoss, report.criticLoss, report.clipped * 100, report.sigma,
                         live.openNets ? "open" : "shut", Date().timeIntervalSince(t0)))
            fflush(stdout)

            writeCheckpoint(actor.parameters, String(format: "iter-%04d", iteration))
            if cfg.replayEvery > 0 && iteration % cfg.replayEvery == 0 {
                writeReplay(actor.parameters, to: String(format: "%@/replay-%04d.html", outDir, iteration),
                            seed: cfg.replaySeed)
            }
        }
        print(String(format: "done — %.1f min", Date().timeIntervalSince(started) / 60))
    }

    /// `parallelScores`' twin for rollouts.
    private static func parallelRollouts(_ n: Int, _ body: @escaping @Sendable (Int) -> Rollout) -> [Rollout] {
        final class Slots: @unchecked Sendable {
            var values: [Rollout]
            init(_ n: Int) { values = Array(repeating: Rollout(), count: n) }
        }
        let slots = Slots(n)
        DispatchQueue.concurrentPerform(iterations: n) { k in slots.values[k] = body(k) }
        return slots.values
    }
}
