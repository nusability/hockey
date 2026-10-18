import Foundation
import SmashCore

/// Proximal policy optimisation: a trainer that assigns credit **through time**.
///
/// Why this exists at all. Evolution strategies — everything else in this target — scores a whole
/// match and keeps the weights that won. It never learns *which* of eighteen thousand moments was
/// the mistake, so every behaviour anyone wanted had to be restated as a per-match statistic for it
/// to chase, and each statistic was then gamed: a side was paid to stand near the ball and stood
/// near the ball without ever taking it; paid for spacing, it filed down the middle perfectly
/// spaced. The measured end of that road was a policy 1.3 m wide winning 0.4 balls a match against
/// §7's 2.2.
///
/// PPO propagates the consequence of a decision backwards to the decision, so "the ball went in"
/// can pay the pass that set it up. That is what makes a nearly-bare objective viable, which is the
/// point — the goal is a side that *plays*, not one that satisfies six proxies.
///
/// What it needs from the simulation is `Match.policyHook`: the observation, the net's own output,
/// and the right to substitute an explored action. Sampling lives here rather than in the core so
/// the log-density below is exact rather than an approximation of whatever the core happened to do.
enum PPO {

    // MARK: - The policy distribution
    //
    // A diagonal Gaussian over the three outputs, with a fixed standard deviation that anneals.
    // Fixed rather than learned deliberately: a learned deviation is the usual first thing to
    // collapse, and when it collapses the policy stops exploring and the run dies quietly.

    /// log N(a; mean, sigma) summed over the outputs.
    static func logProb(_ a: [Double], mean: [Double], sigma: Double) -> Double {
        let c = -0.5 * Foundation.log(2 * Double.pi) - Foundation.log(sigma)
        var s = 0.0
        for k in a.indices {
            let d = (a[k] - mean[k]) / sigma
            s += c - 0.5 * d * d
        }
        return s
    }

    /// d(log N)/d(mean), which is what the chain rule needs to reach the weights.
    static func dLogProbDMean(_ a: [Double], mean: [Double], sigma: Double) -> [Double] {
        var g = [Double](repeating: 0, count: a.count)
        for k in a.indices { g[k] = (a[k] - mean[k]) / (sigma * sigma) }
        return g
    }

    // MARK: - Gradient check
    //
    // The backward pass is the one piece of this that fails *silently*: a wrong gradient does not
    // crash, it produces a policy that will not learn, which is indistinguishable from a reward
    // that does not work. So it is checked against finite differences before anything is trained,
    // on both losses that use it.

    /// Compares the analytic gradient with a central finite difference on a small net, for the
    /// squared error and for PPO's clipped surrogate.
    ///
    /// Returns the worst relative error of each **and the magnitude of each analytic gradient**,
    /// because the first version of this check passed at 7e-24 by comparing zero with zero: with a
    /// random action three standard deviations from the mean the ratio underflows, the gradient
    /// vanishes, and the finite difference vanishes with it. A green light that proves nothing is
    /// worse than a red one. So the action is drawn as the policy would actually draw it, and the
    /// old log-probability is set just off the current one, which is the regime PPO spends its life
    /// in - ratio near 1, inside the clip, gradient flowing.
    static func gradientCheck(seed: UInt64 = 7) -> (mse: Double, surrogate: Double,
                                                   mseNorm: Double, surrogateNorm: Double) {
        let nIn = 9, nH = 7, nOut = 3
        var g = Gauss(seed: seed)
        let x = (0..<nIn).map { _ in g.normal() }
        let label = (0..<nOut).map { _ in g.normal() }
        let sigma = 0.4
        let advantage = 0.7
        let clip = 0.2

        var bp = Backprop(nIn: nIn, nH: nH, nOut: nOut, seed: seed, lr: 0)
        // An action the policy plausibly drew, and an old log-probability just off the current one,
        // so the ratio lands near 1 and the clip does not bind.
        let mean0 = bp.forward(x).y
        let action = mean0.map { $0 + sigma * g.normal() }
        let logpOld = logProb(action, mean: mean0, sigma: sigma) - 0.05

        /// The two losses, as functions of the parameter vector, so finite differences can move one
        /// parameter at a time through exactly the code the analytic path uses.
        func losses(_ p: [Double]) -> (mse: Double, surrogate: Double) {
            var probe = bp
            probe.load(p)
            let y = probe.forward(x).y
            var mse = 0.0
            for o in 0..<nOut { let e = y[o] - label[o]; mse += e * e }
            mse /= Double(nOut)
            let ratio = Foundation.exp(logProb(action, mean: y, sigma: sigma) - logpOld)
            // PPO maximises the clipped surrogate, so the loss is its negation.
            let surrogate = -Swift.min(ratio * advantage,
                                       Swift.max(1 - clip, Swift.min(1 + clip, ratio)) * advantage)
            return (mse, surrogate)
        }

        let p0 = bp.parameters
        let f = bp.forward(x)

        // Analytic: squared error.
        var gm = Backprop.Grads(nIn: nIn, nH: nH, nOut: nOut)
        var dyM = [Double](repeating: 0, count: nOut)
        for o in 0..<nOut { dyM[o] = 2.0 * (f.y[o] - label[o]) / Double(nOut) }
        bp.backward(x, f, dy: dyM, into: &gm)

        // Analytic: the clipped surrogate. dL/dmean = dL/dratio · ratio · dlogp/dmean, and the
        // gradient is zero exactly where the clip binds — which is the whole mechanism.
        var gs = Backprop.Grads(nIn: nIn, nH: nH, nOut: nOut)
        let ratio = Foundation.exp(logProb(action, mean: f.y, sigma: sigma) - logpOld)
        let unclipped = ratio * advantage
        let clipped = Swift.max(1 - clip, Swift.min(1 + clip, ratio)) * advantage
        let dRatio = (unclipped <= clipped) ? -advantage : 0.0
        let dMean = dLogProbDMean(action, mean: f.y, sigma: sigma)
        var dyS = [Double](repeating: 0, count: nOut)
        for o in 0..<nOut { dyS[o] = dRatio * ratio * dMean[o] }
        bp.backward(x, f, dy: dyS, into: &gs)

        // Central differences.
        let h = 1e-6
        var worstM = 0.0, worstS = 0.0
        let am = gm.flat, asur = gs.flat
        for k in p0.indices {
            var up = p0, down = p0
            up[k] += h; down[k] -= h
            let lu = losses(up), ld = losses(down)
            let fdM = (lu.mse - ld.mse) / (2 * h)
            let fdS = (lu.surrogate - ld.surrogate) / (2 * h)
            worstM = Swift.max(worstM, relative(am[k], fdM))
            worstS = Swift.max(worstS, relative(asur[k], fdS))
        }
        func norm(_ v: [Double]) -> Double { v.reduce(0) { $0 + $1 * $1 }.squareRoot() }
        return (worstM, worstS, norm(am), norm(asur))
    }

    private static func relative(_ a: Double, _ b: Double) -> Double {
        let scale = Swift.max(1e-7, Swift.max(a.magnitude, b.magnitude))
        return (a - b).magnitude / scale
    }
}
