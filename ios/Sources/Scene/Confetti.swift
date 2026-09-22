import RealityKit
import simd

/// A goal's confetti: cards thrown up from the net, tumbling down on real time. Presentation only —
/// its randomness is its own generator, never a match stream (§4.3). The twin of Confetti.kt.
@MainActor
final class Confetti {
    typealias C = Presentation.Celebration
    let root = Entity()
    private var pieces: [(e: ModelEntity, v: SIMD3<Float>, spin: SIMD3<Float>)] = []
    private var age = Double.infinity
    private var rng = SplitMixLite(seed: 0x5EED)

    init(materials: Materials, look: WorldLook) throws {
        let mesh = try Figures.card().resource()
        let colours = try C.colours.map { try materials.actor($0, look: look) }
        for i in 0..<C.pieces {
            let e = ModelEntity(mesh: mesh, materials: [colours[i % colours.count]])
            e.components.set(DynamicLightShadowComponent(castsShadow: false))
            e.isEnabled = false
            root.addChild(e)
            pieces.append((e, .zero, .zero))
        }
    }

    /// Throws the confetti up from the net on goal line `goalZ`.
    func burst(goalZ: Float) {
        age = 0
        let size = Float(C.size)
        for i in pieces.indices {
            let a = rng.next() * 2 * .pi
            let up = 0.55 + 0.45 * rng.next()
            let speed = Float(C.speed) * (0.6 + 0.4 * rng.next())
            let out: Float = goalZ >= 0 ? -1 : 1
            pieces[i].v = SIMD3(cos(a) * (1 - up), up, sin(a) * (1 - up) * 0.6 + out * 0.25) * speed
            pieces[i].spin = SIMD3(rng.next() - 0.5, rng.next() - 0.5, rng.next() - 0.5) * 14
            let e = pieces[i].e
            e.position = SIMD3((rng.next() - 0.5) * 6, 1.2, goalZ + (rng.next() - 0.5) * 1.5)
            e.scale = SIMD3(repeating: size)
            e.isEnabled = true
        }
    }

    /// Real time: fall, flutter, shrink away at the end.
    func advance(_ dt: Double) {
        guard age < C.seconds else { return }
        age += dt
        let t = Float(dt), g = Float(C.gravity)
        let fade = Float(max(0, min(1, (C.seconds - age) / 0.6)))
        for i in pieces.indices {
            var p = pieces[i]
            p.v.y -= g * t
            p.v *= exp(-1.4 * t)
            p.e.position += p.v * t
            if p.e.position.y < 0.05 { p.e.position.y = 0.05; p.v = .zero }
            p.e.orientation = simd_quatf(angle: simd_length(p.spin) * t, axis: simd_normalize(p.spin)) * p.e.orientation
            p.e.scale = SIMD3(repeating: Float(C.size) * fade)
            p.e.isEnabled = age < C.seconds
            pieces[i] = p
        }
    }
}

/// A small presentation-only generator (never on the simulation path, §4.3).
struct SplitMixLite {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Float {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Float((z ^ (z >> 31)) >> 40) / Float(1 << 24)
    }
}
