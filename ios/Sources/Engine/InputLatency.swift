import Foundation
import SmashCore
import os

/// Measures input → tick latency (spec §5.3, conventions: input latency is sacred): from the
/// touch's own timestamp to the moment the tick that applies it has run, in the same clock
/// (`CACurrentMediaTime`, which `UITouch.timestamp` shares). Logged under the category `input`
/// after every edge, with a running summary — `log stream --predicate 'category == "input"'`.
///
/// The summary is a `Samples` histogram, so it costs the same on the first tap of a session as on
/// the thousandth. It used to keep every sample since launch in an array and sort a copy of it on
/// every edge — **on the input path**, the one place A0 says nothing may be added, and growing with
/// the session (SMASH-58). An instrument that measures latency may not add it.
@MainActor
final class InputLatency {
    private let log = Logger(subsystem: "in.nann.smashhockey", category: "input")
    private var waiting: [(touch: Double, handled: Double, down: Bool)] = []
    private var samples = Samples()

    /// A finger edge reached the match (`hold`), at `handled`; the touch happened at `touch`.
    func edge(down: Bool, touch: Double, handled: Double) {
        waiting.append((touch, handled, down))
    }

    /// Ticks have run at `now`: every edge waiting has been applied (§4.1).
    func ticked(now: Double) {
        for w in waiting {
            let ms = (now - w.touch) * 1000
            samples.add(ms)
            log.info("\(w.down ? "hold" : "lift", privacy: .public) touch→handler \((w.handled - w.touch) * 1000, format: .fixed(precision: 2), privacy: .public) ms, touch→tick \(ms, format: .fixed(precision: 2), privacy: .public) ms | n=\(self.samples.count) p50=\(self.samples.quantile(0.5), format: .fixed(precision: 2), privacy: .public) p95=\(self.samples.quantile(0.95), format: .fixed(precision: 2), privacy: .public) max=\(self.samples.peak, format: .fixed(precision: 2), privacy: .public)")
        }
        waiting.removeAll(keepingCapacity: true)
    }
}
