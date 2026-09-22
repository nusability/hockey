import Foundation
import os

/// Measures input → tick latency (spec §5.3, conventions: input latency is sacred): from the
/// touch's own timestamp to the moment the tick that applies it has run, in the same clock
/// (`CACurrentMediaTime`, which `UITouch.timestamp` shares). Logged under the category `input`
/// after every edge, with a running summary — `log stream --predicate 'category == "input"'`.
@MainActor
final class InputLatency {
    private let log = Logger(subsystem: "in.nann.smashhockey", category: "input")
    private var waiting: [(touch: Double, handled: Double, down: Bool)] = []
    private var samples: [Double] = []

    /// A finger edge reached the match (`hold`), at `handled`; the touch happened at `touch`.
    func edge(down: Bool, touch: Double, handled: Double) {
        waiting.append((touch, handled, down))
    }

    /// Ticks have run at `now`: every edge waiting has been applied (§4.1).
    func ticked(now: Double) {
        for w in waiting {
            let ms = (now - w.touch) * 1000
            samples.append(ms)
            let sorted = samples.sorted()
            func p(_ q: Double) -> Double { sorted[Int(Double(sorted.count - 1) * q)] }
            log.info("\(w.down ? "hold" : "lift", privacy: .public) touch→handler \((w.handled - w.touch) * 1000, format: .fixed(precision: 2), privacy: .public) ms, touch→tick \(ms, format: .fixed(precision: 2), privacy: .public) ms | n=\(sorted.count) p50=\(p(0.5), format: .fixed(precision: 2), privacy: .public) p95=\(p(0.95), format: .fixed(precision: 2), privacy: .public) max=\(sorted.last!, format: .fixed(precision: 2), privacy: .public)")
        }
        waiting.removeAll()
    }
}
