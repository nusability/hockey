// Fits the policy to §7's written rules before self-play starts improving on them (SMASH-72).
//
// ## Why bootstrap at all
//
// Emergent team play from pure self-play is real, and it is a *compute-scale* phenomenon: OpenAI
// Five found it on ~128,000 cores over months. On one M1 the search spends its whole budget
// rediscovering things §7 already knows — that you move toward a loose ball, that a defender holds
// its depth — and never reaches the part we are actually paying for. Imitation buys that back:
// minutes of regression put the net at roughly today's competence, and self-play starts from there.
// AlphaGo did the same thing for the same reason.
//
// Two further things it buys. It bounds the downside — a policy that begins as a copy of §7 cannot
// end up worse than §7 unless the search makes it so, and we would see that. And it is the honest
// way to produce the `strength` ladder later: the bootstrap checkpoint is a natural rung, a side
// that plays exactly as well as today's AI.
//
// The cost, stated plainly: the result is "learned, starting from your rules" rather than "learned
// from nothing". A from-scratch arm answers that question separately; this one is for getting
// something worth watching.
import Foundation
import SmashCore

/// A two-hidden-layer ReLU MLP with Adam, matching `PolicyNet`'s shapes and parameter order
/// exactly. Written here rather than in the core because **this is not simulation code**: nothing
/// about the fitting has to be deterministic across platforms, only the forward pass it produces,
/// and that is `DetPolicy`'s job.
struct Backprop {
    let nIn: Int, nH: Int, nOut: Int

    var w0: [Double], b0: [Double]
    var w1: [Double], b1: [Double]
    var w2: [Double], b2: [Double]

    // Adam's moments, one per parameter, in the same layout.
    private var m: [Double], v: [Double]
    private var t = 0
    let lr: Double
    let beta1 = 0.9, beta2 = 0.999, eps = 1e-8

    init(nIn: Int, nH: Int, nOut: Int, seed: UInt64, lr: Double = 1e-3) {
        self.nIn = nIn; self.nH = nH; self.nOut = nOut; self.lr = lr
        var g = Gauss(seed: seed)
        // He initialisation: variance 2/fan-in keeps ReLU activations from collapsing or exploding
        // through the layers.
        func he(_ count: Int, _ fanIn: Int) -> [Double] {
            let s = (2.0 / Double(fanIn)).squareRoot()
            return (0..<count).map { _ in g.normal() * s }
        }
        w0 = he(nH * nIn, nIn);  b0 = [Double](repeating: 0, count: nH)
        w1 = he(nH * nH, nH);    b1 = [Double](repeating: 0, count: nH)
        w2 = he(nOut * nH, nH);  b2 = [Double](repeating: 0, count: nOut)
        let dim = PolicyNet.parameterCount(nIn: nIn, nHidden: nH, nOut: nOut)
        m = [Double](repeating: 0, count: dim)
        v = [Double](repeating: 0, count: dim)
    }

    var parameters: [Double] { w0 + b0 + w1 + b1 + w2 + b2 }

    /// Scatters a flat parameter vector back into the layers — the inverse of `parameters`, so a
    /// gradient check can move one parameter at a time through the same forward pass.
    mutating func load(_ flat: [Double]) {
        var k = 0
        func take(_ n: Int) -> [Double] { defer { k += n }; return Array(flat[k..<(k + n)]) }
        w0 = take(nH * nIn); b0 = take(nH)
        w1 = take(nH * nH);  b1 = take(nH)
        w2 = take(nOut * nH); b2 = take(nOut)
    }

    /// One Adam step on the mean squared error over `batch`. Returns the loss before the step.
    ///
    /// `dropTail` hides the last few inputs on a random `dropProbability` of samples. It exists for
    /// exactly one input group — the policy's memory of its own previous target — and for one
    /// reason: without it the fit is a fraud. §7's target barely moves between re-thinks, so
    /// "repeat what you said last time" drives squared error to almost nothing (measured: 0.0584
    /// → 0.0012) while learning nothing about hockey. At rollout that is a fixed point: every
    /// player freezes wherever it first went, possession collapses to 0.21 and the side concedes
    /// 1.83 a match. Hiding the memory half the time forces the net to solve the task from the
    /// state, and to treat its own history as a tiebreak rather than an answer.
    mutating func step(_ batch: ArraySlice<TeachingSample>, dropTail: Int = 0,
                       dropProbability: Double = 0, rng: inout Gauss) -> Double {
        let n = Double(batch.count)
        var g = Grads(nIn: nIn, nH: nH, nOut: nOut)
        var loss = 0.0

        for sample in batch {
            var x = sample.observation
            if dropTail > 0 && rng.uniform() < dropProbability {
                for k in (x.count - dropTail)..<x.count { x[k] = 0 }
            }
            let f = forward(x)
            // dL/dy for the mean squared error, averaged over the batch and the outputs.
            var dy = [Double](repeating: 0, count: nOut)
            for o in 0..<nOut {
                let e = f.y[o] - sample.label[o]
                loss += e * e
                dy[o] = 2.0 * e / (n * Double(nOut))
            }
            backward(x, f, dy: dy, into: &g)
        }

        apply(g.flat)
        return loss / (n * Double(nOut))
    }

    /// The gradient sums for a batch, in `PolicyNet`'s parameter order.
    struct Grads {
        var w0: [Double], b0: [Double], w1: [Double], b1: [Double], w2: [Double], b2: [Double]

        init(nIn: Int, nH: Int, nOut: Int) {
            w0 = [Double](repeating: 0, count: nH * nIn); b0 = [Double](repeating: 0, count: nH)
            w1 = [Double](repeating: 0, count: nH * nH);  b1 = [Double](repeating: 0, count: nH)
            w2 = [Double](repeating: 0, count: nOut * nH); b2 = [Double](repeating: 0, count: nOut)
        }

        var flat: [Double] { w0 + b0 + w1 + b1 + w2 + b2 }
    }

    /// One forward pass, keeping the pre-activations the backward pass has to gate on.
    func forward(_ x: [Double]) -> (y: [Double], z0: [Double], a0: [Double], z1: [Double], a1: [Double]) {
        var z0 = b0
        for o in 0..<nH { let r = o * nIn; var s = b0[o]; for i in 0..<nIn { s += w0[r + i] * x[i] }; z0[o] = s }
        let a0 = z0.map { $0 > 0 ? $0 : 0 }
        var z1 = b1
        for o in 0..<nH { let r = o * nH; var s = b1[o]; for i in 0..<nH { s += w1[r + i] * a0[i] }; z1[o] = s }
        let a1 = z1.map { $0 > 0 ? $0 : 0 }
        var y = b2
        for o in 0..<nOut { let r = o * nH; var s = b2[o]; for i in 0..<nH { s += w2[r + i] * a1[i] }; y[o] = s }
        return (y, z0, a0, z1, a1)
    }

    /// Accumulates one sample's gradients into `g`, given `dy` = dL/dy from the caller.
    ///
    /// **One backward pass in this project, not two.** The imitation fit hands it the squared-error
    /// gradient; a policy-gradient trainer hands it the surrogate's. Neither keeps its own copy of
    /// the chain rule, because two copies is how a gradient goes quietly wrong — and a quietly wrong
    /// gradient looks exactly like a policy that will not learn, which is a week of blaming the
    /// reward.
    func backward(_ x: [Double],
                  _ f: (y: [Double], z0: [Double], a0: [Double], z1: [Double], a1: [Double]),
                  dy: [Double], into g: inout Grads) {
        // Output layer.
        var da1 = [Double](repeating: 0, count: nH)
        for o in 0..<nOut {
            let r = o * nH
            g.b2[o] += dy[o]
            for i in 0..<nH { g.w2[r + i] += dy[o] * f.a1[i]; da1[i] += dy[o] * w2[r + i] }
        }
        // Second hidden layer, gated by its own pre-activation.
        var da0 = [Double](repeating: 0, count: nH)
        for o in 0..<nH {
            let d = f.z1[o] > 0 ? da1[o] : 0
            if d == 0 { continue }
            let r = o * nH
            g.b1[o] += d
            for i in 0..<nH { g.w1[r + i] += d * f.a0[i]; da0[i] += d * w1[r + i] }
        }
        // First hidden layer.
        for o in 0..<nH {
            let d = f.z0[o] > 0 ? da0[o] : 0
            if d == 0 { continue }
            let r = o * nIn
            g.b0[o] += d
            for i in 0..<nIn { g.w0[r + i] += d * x[i] }
        }
    }

    /// Adam, over the flat parameter vector, then scattered back into the layers.
    mutating func apply(_ grad: [Double]) {
        t += 1
        var flat = parameters
        let bc1 = 1.0 - Foundation.pow(beta1, Double(t))
        let bc2 = 1.0 - Foundation.pow(beta2, Double(t))
        for k in flat.indices {
            m[k] = beta1 * m[k] + (1 - beta1) * grad[k]
            v[k] = beta2 * v[k] + (1 - beta2) * grad[k] * grad[k]
            flat[k] -= lr * (m[k] / bc1) / (((v[k] / bc2).squareRoot()) + eps)
        }
        var k = 0
        func take(_ n: Int) -> [Double] { defer { k += n }; return Array(flat[k..<(k + n)]) }
        w0 = take(nH * nIn); b0 = take(nH)
        w1 = take(nH * nH);  b1 = take(nH)
        w2 = take(nOut * nH); b2 = take(nOut)
    }
}
