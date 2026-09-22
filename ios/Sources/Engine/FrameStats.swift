import Foundation
import os

/// The spike's soak meter (SMASH-2): frame intervals and the thermal state, summarised to the log
/// every `window` seconds under the category `frames`, plus a running summary since launch.
/// Console.app filtered on `in.nann.smashhockey` during a 6-minute run is the whole measurement.
@MainActor
final class FrameStats {
    private let log = Logger(subsystem: "in.nann.smashhockey", category: "frames")
    private let window: Double
    private var samples: [Double] = []
    private var all: [Double] = []
    private var elapsed = 0.0
    private var worstThermal = ProcessInfo.ThermalState.nominal

    init(window: Double = 10) { self.window = window }

    func record(_ dt: Double) {
        guard dt > 0 else { return }
        samples.append(dt * 1000)
        all.append(dt * 1000)
        elapsed += dt
        guard elapsed >= window else { return }
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal.rawValue > worstThermal.rawValue { worstThermal = thermal }
        log.info("window \(Self.summary(self.samples), privacy: .public) thermal=\(thermal.rawValue) | total \(Self.summary(self.all), privacy: .public) worstThermal=\(self.worstThermal.rawValue)")
        samples.removeAll(keepingCapacity: true)
        elapsed = 0
    }

    private static func summary(_ s: [Double]) -> String {
        guard !s.isEmpty else { return "n=0" }
        let sorted = s.sorted()
        func p(_ q: Double) -> Double { sorted[Int(Double(sorted.count - 1) * q)] }
        let fps = 1000 / (s.reduce(0, +) / Double(s.count))
        return String(format: "n=%d fps=%.1f p50=%.2f p95=%.2f p99=%.2f max=%.2f",
                      s.count, fps, p(0.5), p(0.95), p(0.99), sorted.last!)
    }
}
