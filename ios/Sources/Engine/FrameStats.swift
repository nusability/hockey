import Foundation
import SmashCore
import os

/// The spike's soak meter (SMASH-2): frame intervals and the thermal state, summarised to the log
/// every `window` seconds under the category `frames`, plus a running summary since launch.
/// Console.app filtered on `in.nann.smashhockey` during a 6-minute run is the whole measurement.
///
/// Both summaries are `Samples` — a fixed histogram — so the meter costs the same on the first frame
/// of a session as on the hundred-thousandth. It used to keep every frame time since launch in an
/// array and sort a copy of it every 10 s on the render thread, which made the game choppier the
/// longer it was played (SMASH-58).
@MainActor
final class FrameStats {
    private let log = Logger(subsystem: "in.nann.smashhockey", category: "frames")
    private let window: Double
    private var current = Samples()
    private var total = Samples()
    private var elapsed = 0.0
    private var worstThermal = ProcessInfo.ThermalState.nominal

    init(window: Double = 10) { self.window = window }

    func record(_ dt: Double) {
        guard dt > 0 else { return }
        current.add(dt * 1000)
        total.add(dt * 1000)
        elapsed += dt
        guard elapsed >= window else { return }
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal.rawValue > worstThermal.rawValue { worstThermal = thermal }
        log.info("window \(self.current.summary(), privacy: .public) thermal=\(thermal.rawValue) | total \(self.total.summary(), privacy: .public) worstThermal=\(self.worstThermal.rawValue)")
        current.reset()
        elapsed = 0
    }
}
