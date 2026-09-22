/// The simulation's only source of randomness (spec §4.3): a seeded SplitMix64 stream.
///
/// Every step is 64-bit integer arithmetic, and `uniform()` converts a 53-bit integer (exact) and
/// scales it by 2^−53 (exact), so the stream is bit-identical on every platform. The Android twin
/// is `in.nann.smashhockey.core.math.SplitMix64`; both replay shared/vectors/math/.
public struct SplitMix64: Sendable, Hashable {
    private typealias K = MathConstants.Splitmix

    /// The stream position. Storing it and restoring it with `init(state:)` resumes the stream
    /// exactly (a season stores its stream, §15).
    public private(set) var state: UInt64

    /// A stream seeded with `seed`; the first draw advances it before mixing.
    public init(seed: UInt64) {
        state = seed
    }

    /// A stream resumed at a stored position.
    public init(state: UInt64) {
        self.state = state
    }

    /// The next 64-bit output.
    public mutating func next() -> UInt64 {
        state = state &+ K.gamma
        var z = state
        z = (z ^ (z >> UInt64(K.shift1))) &* K.mix1
        z = (z ^ (z >> UInt64(K.shift2))) &* K.mix2
        return z ^ (z >> UInt64(K.shift3))
    }

    /// A double in [0, 1): the top 53 bits of the next output × 2^−53.
    public mutating func uniform() -> Double {
        Double(next() >> UInt64(K.mantissaShift)) * K.unit
    }

    /// `(u₁ + u₂ + u₃ − 1.5) × s` from three consecutive draws, summed left to right.
    public mutating func noise(_ s: Double) -> Double {
        let u1 = uniform()
        let u2 = uniform()
        let u3 = uniform()
        let sum = (u1 + u2) + u3
        return (sum - K.noiseCenter) * s
    }
}
