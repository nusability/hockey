import Foundation

/// A running summary of a stream of millisecond measurements — count, mean, peak and quantiles —
/// in **constant memory and constant time per sample**.
///
/// It exists because the two soak meters it serves (`FrameStats`, `InputLatency`) kept every sample
/// since launch in an array and re-sorted it on every measurement: one of them on the render thread
/// every 10 s, the other **on the input path on every touch edge**. The cost grew with the length of
/// the session, which is the one thing A0 forbids — an instrument that measures input latency may not
/// add it, and one that grows cannot be left in a shipping build. A fixed histogram cannot grow.
///
/// Quantiles are exact to within `step`; `count`, `mean` and `peak` are exact. This is a diagnostic
/// aid and takes no part in the simulation — nothing in §4's fixed steps reads it, and no vector
/// pins it.
public struct Samples: Sendable, Equatable {
    /// Milliseconds per bucket. Quantiles are reported to the middle of the bucket they fall in, so
    /// this is the whole of their error.
    public static let step = 0.25
    /// Buckets covering `0 ..< buckets × step` ms — 0–256 ms — plus one overflow bucket above it.
    public static let buckets = 1024

    private var counts: [Int]
    public private(set) var count = 0
    /// The sum of every sample, so the mean stays exact however many there have been.
    public private(set) var sum = 0.0
    /// The largest sample seen, exactly, whichever bucket it landed in.
    public private(set) var peak = 0.0

    public init() { counts = [Int](repeating: 0, count: Self.buckets + 1) }

    /// The mean in ms, or 0 with nothing measured.
    public var mean: Double { count == 0 ? 0 : sum / Double(count) }

    /// Measurements a second, from the mean — 0 with nothing measured, or with a mean of 0.
    public var rate: Double { mean <= 0 ? 0 : 1000 / mean }

    /// Records one measurement in ms. A value that is not finite is ignored rather than allowed to
    /// poison the sum; a negative one lands in the first bucket, which is where a clock that ran
    /// backwards belongs.
    public mutating func add(_ ms: Double) {
        guard ms.isFinite else { return }
        let i = ms <= 0 ? 0 : min(Int(ms / Self.step), Self.buckets)
        counts[i] += 1
        count += 1
        sum += ms
        if ms > peak { peak = ms }
    }

    /// The `q`-quantile in ms (`q` in 0…1), to within `step`. The same rank `q` picks out of a
    /// sorted array of `count` samples: `floor((count − 1) × q)`. 0 with nothing measured. A rank
    /// that falls in the overflow bucket reports `peak`, which is the only exact thing known about
    /// a sample that far out.
    ///
    /// The bucket is reported by its middle, which can sit above the largest sample that landed in
    /// it, so the result is capped at `peak`: a p99 above the max is nonsense in a log, and it makes
    /// `quantile(1) == peak` hold.
    public func quantile(_ q: Double) -> Double {
        guard count > 0 else { return 0 }
        let rank = Int(Double(count - 1) * min(max(q, 0), 1))
        var seen = 0
        for i in 0..<counts.count {
            seen += counts[i]
            guard seen > rank else { continue }
            guard i < Self.buckets else { return peak }
            return min((Double(i) + 0.5) * Self.step, peak)
        }
        return peak
    }

    /// Forgets everything, keeping the buckets allocated — a window starting over.
    public mutating func reset() {
        for i in counts.indices { counts[i] = 0 }
        count = 0
        sum = 0
        peak = 0
    }

    /// `n=… fps=… p50=… p95=… p99=… max=…`, the line both meters log.
    public func summary() -> String {
        guard count > 0 else { return "n=0" }
        return String(format: "n=%d fps=%.1f p50=%.2f p95=%.2f p99=%.2f max=%.2f",
                      count, rate, quantile(0.5), quantile(0.95), quantile(0.99), peak)
    }
}
