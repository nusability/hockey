import RealityKit
import SmashCore

/// A save, a steal or a block pops at the spot (spec §8.8): a flat ring that grows and fades on real
/// time, in the kind's colour. Four at once at most; a fifth takes the oldest. The twin of Pops.kt.
@MainActor
final class Pops {
    typealias P = Presentation.Pop
    let root = Entity()
    private var rings: [(e: ModelEntity, age: Double, colour: UInt32)] = []
    private var next = 0

    init() throws {
        let mesh = try Shapes.ring(inner: Float(1 - P.width), outer: 1, segments: 32).resource()
        for _ in 0..<4 {
            let e = ModelEntity(mesh: mesh, materials: [Materials.flat(P.save, opacity: P.opacity)])
            e.isEnabled = false
            root.addChild(e)
            rings.append((e, .infinity, P.save))
        }
    }

    func pop(_ kind: PopKind, x: Double, z: Double) {
        let colour: UInt32 = switch kind {
        case .save: P.save
        case .steal: P.steal
        case .block: P.block
        }
        rings[next].age = 0
        rings[next].colour = colour
        rings[next].e.position = [Float(x), 0.05, Float(z)]
        rings[next].e.isEnabled = true
        next = (next + 1) % rings.count
    }

    func advance(_ dt: Double) {
        for i in rings.indices where rings[i].age < P.seconds {
            rings[i].age += dt
            let t = min(rings[i].age / P.seconds, 1)
            let e = rings[i].e
            guard t < 1 else { e.isEnabled = false; continue }
            e.scale = SIMD3(repeating: Float(P.radiusFrom + (P.radiusTo - P.radiusFrom) * t))
            e.model?.materials = [Materials.flat(rings[i].colour, opacity: max(P.opacity * (1 - t), 0.001))]
        }
    }
}
