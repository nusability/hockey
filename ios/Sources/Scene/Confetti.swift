import RealityKit
import simd

/// A goal's confetti (spec §8.8), the prototype's burst: cards thrown from the scored-in net in the
/// scoring side's primary, secondary and white, sideways and high, falling, bouncing and tumbling on
/// real time. Presentation only — its randomness is its own generator, never a match stream (§4.3).
/// The twin of Confetti.kt.
@MainActor
final class Confetti {
    typealias C = Presentation.Celebration
    let root = Entity()
    private struct Piece {
        let e: ModelEntity
        var p = SIMD3<Float>.zero
        var v = SIMD3<Float>.zero
        var rx: Float = 0, ry: Float = 0, sx: Float = 0, sy: Float = 0
        var life: Float = 0
    }
    private var pieces: [Piece] = []
    private var alive = false
    private var rng = SplitMixLite(seed: 0x5EED)
    private let materials: Materials
    private let look: WorldLook

    init(materials: Materials, look: WorldLook) throws {
        self.materials = materials
        self.look = look
        var k = MeshKit()
        k.box(.zero, SIMD3(C.size.map(Float.init)))
        let mesh = try k.resource()
        for _ in 0..<C.pieces {
            let e = ModelEntity(mesh: mesh, materials: [])
            e.isEnabled = false
            root.addChild(e)
            pieces.append(Piece(e: e))
        }
    }

    private func r(_ lo: Float, _ hi: Float) -> Float { lo + (hi - lo) * rng.next() }

    /// Throws the confetti from the net on goal line `goalZ`, in the scorers' `colours`.
    func burst(goalZ: Float, colours: TeamColours) throws {
        let kit = try [colours.primary, colours.secondary, 0xFFFFFF].map { try materials.toon($0, look: look) }
        let s = Float(C.spread), d = Float(C.depth), side = Float(C.sideways), spin = Float(C.spin)
        for i in pieces.indices {
            var q = pieces[i]
            q.p = SIMD3(r(-s, s), r(Float(C.height[0]), Float(C.height[1])), goalZ + r(-d, d))
            q.v = SIMD3(r(-side, side), r(Float(C.up[0]), Float(C.up[1])), r(-side, side))
            q.rx = r(0, 6); q.ry = r(0, 6); q.sx = r(-spin, spin); q.sy = r(-spin, spin)
            q.life = r(Float(C.life[0]), Float(C.life[1]))
            q.e.model?.materials = [kit[i % 3]]
            q.e.isEnabled = true
            pieces[i] = q
        }
        alive = true
    }

    /// Real time: fall, bounce, tumble; a piece whose life is over is gone.
    func advance(_ dt: Double) {
        guard alive else { return }
        let t = Float(dt), g = Float(C.gravity), floor = Float(C.floor)
        var any = false
        for i in pieces.indices {
            var q = pieces[i]
            guard q.life > 0 else { continue }
            q.life -= t
            if q.life <= 0 { q.e.isEnabled = false; pieces[i] = q; continue }
            any = true
            q.v.y -= g * t
            q.p += q.v * t
            if q.p.y < floor {
                q.p.y = floor
                q.v.y *= -Float(C.bounce)
                q.v.x *= Float(C.friction)
                q.v.z *= Float(C.friction)
            }
            q.rx += q.sx * t
            q.ry += q.sy * t
            q.e.position = q.p
            q.e.orientation = simd_quatf(angle: q.rx, axis: [1, 0, 0]) * simd_quatf(angle: q.ry, axis: [0, 1, 0])
            pieces[i] = q
        }
        alive = any
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
