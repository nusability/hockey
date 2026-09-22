import RealityKit
import SmashCore
import simd

/// The loose ball's trail (spec §8.8): a ribbon through where the ball was over the last
/// `Trail.seconds` of match time — full width at the ball tapering to nothing, fading as it goes —
/// shown while the ball runs faster than `Trail.minSpeed`, faded in over `fadeSpeed`. A horizontal
/// ribbon at the ball's centre height. The twin of Android's Trail.kt.
@MainActor
final class BallTrail {
    typealias T = Presentation.Trail
    let entity: ModelEntity
    private let mesh: DynamicMesh
    private var material: ShaderGraphMaterial
    private var samples: [(p: SIMD2<Double>, t: Double)] = []
    private let height: Float
    private var shownOpacity = -1.0

    init(ballRadius: Double, feel: FeelMaterials.Set) throws {
        let n = T.samples
        var tris: [UInt16] = []
        for i in 0..<(n - 1) {
            let a = UInt16(2 * i)
            tris += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
        }
        let bounds = BoundingBox(min: [-40, -1, -40], max: [40, 2, 40])
        mesh = try DynamicMesh(vertexCount: 2 * n, triangles: tris, bounds: bounds)
        material = feel.trail
        FeelMaterials.colour(&material, T.colour)
        entity = ModelEntity(mesh: mesh.resource, materials: [material])
        entity.isEnabled = false
        height = Float(ballRadius)
    }

    /// One frame: the ball drawn at `ball` at match time `time`, loose or not, at `speed`.
    func update(ball: SIMD2<Double>, time: Double, loose: Bool, speed: Double) {
        guard loose else { samples.removeAll(); entity.isEnabled = false; return }
        if let last = samples.last, time < last.t { samples.removeAll() }       // a new match or a restart
        if samples.last?.t != time { samples.append((ball, time)) } else { samples[samples.count - 1].p = ball }
        samples.removeAll { time - $0.t > T.seconds }
        if samples.count > T.samples { samples.removeFirst(samples.count - T.samples) }
        let f = min(max((speed - T.minSpeed) / T.fadeSpeed, 0), 1)
        guard f > 0, samples.count >= 2 else { entity.isEnabled = false; return }
        entity.isEnabled = true
        let opacity = (T.opacity * f * 50).rounded() / 50
        if opacity != shownOpacity {
            shownOpacity = opacity
            FeelMaterials.set(&material, "Opacity", opacity)
            entity.model?.materials = [material]
        }
        let pts = samples.reversed().map(\.p)       // newest first
        let n = T.samples
        mesh.write { v in
            for i in 0..<n {
                let k = min(i, pts.count - 1)
                let p = pts[k]
                let age = min(1, (time - samples[samples.count - 1 - k].t) / T.seconds)
                let u = i < pts.count ? age : 1
                let next = pts[min(k + 1, pts.count - 1)], prev = pts[max(k - 1, 0)]
                var d = prev - next
                if simd_length(d) < 1e-6 { d = SIMD2(0, 1) }
                d = simd_normalize(d)
                let side = SIMD2(-d.y, d.x) * (T.width / 2 * (1 - u))
                let a = 1 - Float(u)
                v[2 * i] = .init(position: [Float(p.x + side.x), height, Float(p.y + side.y)], uv: [a, 0])
                v[2 * i + 1] = .init(position: [Float(p.x - side.x), height, Float(p.y - side.y)], uv: [a, 1])
            }
        }
    }
}

/// How the ball turns (spec §8.8): the field ball rolls along its travel, the puck spins.
struct BallSpin {
    private(set) var orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
    private var last: SIMD2<Double>?

    mutating func advance(to p: SIMD2<Double>, radius: Double, puck: Bool, realDt: Double) -> simd_quatf {
        defer { last = p }
        if puck {
            orientation = simd_quatf(angle: Float(Presentation.Trail.puckSpin * realDt), axis: [0, 1, 0]) * orientation
            return orientation
        }
        guard let l = last else { return orientation }
        let d = p - l
        let dist = simd_length(d)
        guard dist > 1e-6, dist < 3 else { return orientation }      // a jump (a restart) does not spin it
        let axis = SIMD3<Float>(Float(d.y / dist), 0, Float(-d.x / dist))
        orientation = simd_normalize(simd_quatf(angle: Float(dist / radius), axis: axis) * orientation)
        return orientation
    }
}
