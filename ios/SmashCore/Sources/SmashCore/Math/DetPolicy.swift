/// The learned policy's forward pass (spec §4.4, §7).
///
/// Every value here is an IEEE-754 `Double` and every expression uses only `+`, `−` and `×`, in the
/// order written, never fused into a multiply-add — the same contract `DetMath` keeps, for the same
/// reason: iOS and Android compute the same match to the bit, which is what lets a replay be stored
/// as nothing but the ticks the finger moved, and what a cross-platform match would rest on.
///
/// The accumulation order is **part of the contract**, not an implementation detail:
///
///   for each layer, for output `o` ascending:
///       s ← bias[o]
///       for input `i` ascending:  s ← s + weight[o · nIn + i] · x[i]
///
/// No accumulation tree, no pairwise summation, no `fma`, no `Accelerate`, no SIMD by hand. The
/// loop is written the dull way deliberately: `swiftc -O` vectorises the multiplies but keeps the
/// serial add chain in written order (it contracts only under LLVM's `contract` flag, which Swift
/// never emits), and ART forms no floating-point multiply-accumulate at all and never vectorises a
/// `double` reduction. Both are semantic guarantees of the toolchains, not luck — but they are
/// guarantees about *this* shape of loop, so do not "optimise" it.
///
/// Hidden layers are ReLU, written as a comparison rather than `max` so that §4.4's
/// first-argument-on-a-tie rule never has to arbitrate a signed zero. Outputs are linear.
///
/// The net draws nothing. Every random draw stays at the sites §4.3 enumerates.
public enum DetPolicy {

    /// `y = W · x + b`, accumulated in the declared order. `w` is row-major: output-major, so
    /// `w[o * nIn + i]` is the weight from input `i` to output `o`.
    public static func layer(_ x: [Double], weight w: [Double], bias b: [Double],
                      inputs nIn: Int, outputs nOut: Int) -> [Double] {
        var y = [Double](repeating: 0, count: nOut)
        for o in 0..<nOut {
            let row = o * nIn
            var s = b[o]
            for i in 0..<nIn {
                s = s + w[row + i] * x[i]
            }
            y[o] = s
        }
        return y
    }

    /// ReLU, in place, as a comparison (§4.4).
    public static func relu(_ x: inout [Double]) {
        for i in x.indices {
            x[i] = x[i] > 0.0 ? x[i] : 0.0
        }
    }

    /// `x / (1 + |x|)` — the algebraic sigmoid: maps the whole line into (−1, 1) using nothing but
    /// `+`, `÷` and a magnitude, so it is exact under §4.4 where `tanh` would not be.
    ///
    /// It is here instead of a clamp because a clamp *kills training*: once an output passes ±1 every
    /// perturbation of the weights behind it produces the identical pinned target, the fitness
    /// landscape goes flat, and the search has nothing left to climb. This squashes without ever
    /// fully saturating, so there is always a gradient to follow.
    public static func squash(_ x: Double) -> Double {
        x / (1.0 + x.magnitude)
    }
}

/// A trained policy: two hidden ReLU layers and a linear output (spec §7).
///
/// Shapes and weights come from `shared/data/policy.toml` and `shared/assets/policy/` in the
/// shipped build; the trainer builds them in memory.
public struct PolicyNet: Sendable {
    public let nIn: Int
    public let nHidden: Int
    public let nOut: Int

    /// `nHidden × nIn`, output-major.
    let w0: [Double]
    let b0: [Double]
    /// `nHidden × nHidden`, output-major.
    let w1: [Double]
    let b1: [Double]
    /// `nOut × nHidden`, output-major.
    let w2: [Double]
    let b2: [Double]

    /// Every weight and bias, in the order the blob stores them: w0, b0, w1, b1, w2, b2.
    public var parameters: [Double] { w0 + b0 + w1 + b1 + w2 + b2 }

    public static func parameterCount(nIn: Int, nHidden: Int, nOut: Int) -> Int {
        nHidden * nIn + nHidden + nHidden * nHidden + nHidden + nOut * nHidden + nOut
    }

    /// Rebuilds a net from a flat parameter vector in `parameters`' order.
    public init(nIn: Int, nHidden: Int, nOut: Int, parameters p: [Double]) {
        precondition(p.count == PolicyNet.parameterCount(nIn: nIn, nHidden: nHidden, nOut: nOut),
                     "PolicyNet: parameter vector is \(p.count), expected "
                     + "\(PolicyNet.parameterCount(nIn: nIn, nHidden: nHidden, nOut: nOut))")
        self.nIn = nIn
        self.nHidden = nHidden
        self.nOut = nOut
        var k = 0
        func take(_ n: Int) -> [Double] { defer { k += n }; return Array(p[k..<(k + n)]) }
        w0 = take(nHidden * nIn)
        b0 = take(nHidden)
        w1 = take(nHidden * nHidden)
        b1 = take(nHidden)
        w2 = take(nOut * nHidden)
        b2 = take(nOut)
    }

    /// One forward pass, keeping both hidden layers — what `shared/vectors/policy/` pins, so a
    /// divergence is caught at the layer it happens in rather than only where it reaches the pitch.
    public func trace(_ observation: [Double]) -> (h0: [Double], h1: [Double], out: [Double]) {
        precondition(observation.count == nIn, "PolicyNet: observation is \(observation.count), expected \(nIn)")
        var h = DetPolicy.layer(observation, weight: w0, bias: b0, inputs: nIn, outputs: nHidden)
        DetPolicy.relu(&h)
        var g = DetPolicy.layer(h, weight: w1, bias: b1, inputs: nHidden, outputs: nHidden)
        DetPolicy.relu(&g)
        return (h, g, DetPolicy.layer(g, weight: w2, bias: b2, inputs: nHidden, outputs: nOut))
    }

    /// One forward pass, in the declared order (§4.4).
    public func forward(_ observation: [Double]) -> [Double] {
        precondition(observation.count == nIn, "PolicyNet: observation is \(observation.count), expected \(nIn)")
        var h = DetPolicy.layer(observation, weight: w0, bias: b0, inputs: nIn, outputs: nHidden)
        DetPolicy.relu(&h)
        var g = DetPolicy.layer(h, weight: w1, bias: b1, inputs: nHidden, outputs: nHidden)
        DetPolicy.relu(&g)
        return DetPolicy.layer(g, weight: w2, bias: b2, inputs: nHidden, outputs: nOut)
    }
}
