import RealityKit
import SmashCore

/// A save, a steal or a block pops at the spot (spec §8.8): a flat ring that grows and fades on real
/// time, in the kind's colour. Four at once at most; a fifth takes the oldest. The twin of Pops.kt.
///
/// Each ring is a mesh written in place — the radius and the fade go into its **vertices**, the fade
/// in `u` for the Trail shader to multiply its opacity by, as the ball's trail and the lock-on's
/// ring do. Nothing is handed to the renderer per frame: a material written on a frame is a resource
/// RealityKit takes ownership of and never gives back, and the end of that is the part no longer
/// being drawn (SMASH-24). Its vertices are the pitch's own coordinates on an entity that never
/// moves, bounded by `SceneMarks.popExtent` — a box a test walks every ring against (SMASH-33).
@MainActor
final class Pops {
    typealias P = Presentation.Pop
    let root = Entity()
    private static let segments = 32
    private struct Ring {
        let mesh: DynamicMesh
        let entity: ModelEntity
        var material: ShaderGraphMaterial
        var colour: UInt32
        var at: SIMD2<Float> = .zero
        var age = Double.infinity
    }
    private var rings: [Ring] = []
    private var next = 0

    init(feel: FeelMaterials.Set) throws {
        let n = Self.segments
        var tris: [UInt16] = []
        for i in 0..<n {
            let a = UInt16(2 * i)
            tris += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
        }
        let e = SceneMarks.popExtent(radius: P.radiusTo)
        let bounds = BoundingBox(min: [Float(-e.x), -1, Float(-e.z)], max: [Float(e.x), 1, Float(e.z)])
        for _ in 0..<4 {
            var material = feel.trail
            FeelMaterials.colour(&material, P.save)
            FeelMaterials.set(&material, "Opacity", P.opacity)
            let mesh = try DynamicMesh(vertexCount: 2 * (n + 1), triangles: tris, bounds: bounds)
            let entity = ModelEntity(mesh: mesh.resource, materials: [material])
            DrawOrder.set(entity, DrawOrder.pop)
            entity.isEnabled = false
            root.addChild(entity)
            rings.append(Ring(mesh: mesh, entity: entity, material: material, colour: P.save))
        }
    }

    func pop(_ kind: PopKind, x: Double, z: Double) {
        let colour: UInt32 = switch kind {
        case .save: P.save
        case .steal: P.steal
        case .block: P.block
        }
        // The colour is the one thing a material still says — written when this ring changes kind,
        // never on a frame.
        if rings[next].colour != colour {
            rings[next].colour = colour
            FeelMaterials.colour(&rings[next].material, colour)
            rings[next].entity.model?.materials = [rings[next].material]
            Diagnostics.materialWritten()
        }
        rings[next].age = 0
        rings[next].at = [Float(x), Float(z)]
        rings[next].entity.isEnabled = true
        next = (next + 1) % rings.count
    }

    func advance(_ dt: Double) {
        let n = Self.segments
        for i in rings.indices where rings[i].age < P.seconds {
            rings[i].age += dt
            let t = min(rings[i].age / P.seconds, 1)
            guard t < 1 else { rings[i].entity.isEnabled = false; continue }
            let outer = Float(P.radiusFrom + (P.radiusTo - P.radiusFrom) * t)
            let inner = outer * Float(1 - P.width)
            let (cx, cz) = (rings[i].at.x, rings[i].at.y)
            let fade = Float(1 - t)                      // the Trail shader multiplies opacity by u
            rings[i].mesh.write { v in
                for k in 0...n {
                    let a = Float(k) / Float(n) * 2 * .pi
                    let (s, c) = (sin(a), cos(a))
                    v[2 * k] = .init(position: [cx + inner * s, 0.05, cz + inner * c], uv: [fade, 0])
                    v[2 * k + 1] = .init(position: [cx + outer * s, 0.05, cz + outer * c], uv: [fade, 1])
                }
            }
        }
    }
}
