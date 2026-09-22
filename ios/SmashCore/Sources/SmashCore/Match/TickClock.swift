/// Turns real time into whole ticks (spec §4.2).
///
/// Real time is counted in integer units — a tick is `realUnitsPerTick` of them — so a display at
/// 60 Hz (two ticks per frame) and one at 120 Hz (one per frame) accumulate exactly the same count
/// and run exactly the same ticks. The time scale changes how many ticks a real second holds,
/// never what a tick does.
struct TickClock: Sendable, Hashable {
    private var units: Int64 = 0

    mutating func ticks(realSeconds: Double, timeScale: Double) -> Int {
        precondition(timeScale >= 0 && realSeconds.isFinite, "TickClock: a time scale is ≥ 0 and real time finite")
        let gap = Pitch.clamp(realSeconds, 0, Tuning.Time.maxRealGap)
        let perSecond = Double(Tuning.Time.stepsPerSecond / Tuning.Time.stepsPerTick) * Double(Tuning.Time.realUnitsPerTick)
        units += Int64((gap * timeScale * perSecond).rounded())
        let perTick = Int64(Tuning.Time.realUnitsPerTick)
        let n = units / perTick
        units -= n * perTick
        return Int(n)
    }
}
