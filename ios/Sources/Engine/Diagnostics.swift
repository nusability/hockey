import Darwin
import Foundation
import os

/// A one-line-a-second diagnostic behind `-diagnose aim` (spec §5.2): what the aim arrow is doing,
/// how many RealityKit materials and meshes the scene has handed the renderer since launch, and the
/// app's own footprint. Off unless the launch argument asks for it, so it costs a `Bool` test per
/// frame in a normal build — it exists so a failure only the owner's phone shows can be read from a
/// log instead of guessed at. The twin of Android's Diagnostics.kt.
@MainActor
enum Diagnostics {
    /// `-diagnose aim` on the launch arguments.
    static let aim = UserDefaults.standard.string(forKey: "diagnose") == "aim"

    private static let log = Logger(subsystem: "in.nann.smashhockey", category: "diagnose")
    private static var last = -1.0

    /// Materials handed to a `ModelComponent` since launch — every one is a resource the renderer
    /// takes ownership of, so a count that climbs with the clock is per-frame churn.
    private(set) static var materialWrites = 0
    /// Meshes built since launch (`MeshKit.resource`, `generateText`, `LowLevelMesh`).
    private(set) static var meshes = 0

    static func materialWritten() { materialWrites += 1 }
    static func meshBuilt() { meshes += 1 }

    /// The app's physical footprint in MB.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let ok = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) == KERN_SUCCESS
            }
        }
        return ok ? (Double(info.phys_footprint) / 1_048_576).rounded() : -1
    }

    /// Logs `line()` at most once a real second; `line` is not built on the frames in between.
    static func second(_ clock: Double, _ line: () -> String) {
        guard aim, clock - last >= 1 else { return }
        last = clock
        let s = line()
        log.info("""
            t=\(clock, format: .fixed(precision: 0))s mem=\(footprintMB(), format: .fixed(precision: 0))MB \
            materials=\(materialWrites) meshes=\(meshes) \(s, privacy: .public)
            """)
    }
}
