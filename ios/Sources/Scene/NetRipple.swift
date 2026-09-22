import RealityKit
import SmashCore
import simd

/// The nets' sheets and their ripple (spec §8.8): each goal's back and roof carry a light sheet (the
/// prototype's net under its cords); a goal sends a wave through the scored-in net's sheets from
/// where the ball struck — displacement along the sheet's outward normal of
/// `amplitude · e^(−decay·t) · sin(frequency·t − k·r) · e^(−r/reach)`, r the distance from the
/// strike, t real seconds since the goal — for `seconds`, then rest. The twin of NetRipple.kt.
@MainActor
final class NetRipple {
    typealias N = Presentation.Net
    let root = Entity()
    private struct Sheet {
        let mesh: DynamicMesh
        let rest: [SIMD3<Float>]
        let normal: SIMD3<Float>
    }
    /// Per goal (index 0: −z, 1: +z), its back and roof.
    private var sheets: [[Sheet]] = []
    private var ripple: (goal: Int, strike: SIMD3<Float>, age: Double)?

    init() throws {
        let hw = Float(Tuning.Pitch.goalMouthWidth / 2), h = Float(N.height)
        let line = Float(Tuning.Pitch.goalLineZ), depth = Float(Tuning.Pitch.goalDepth)
        let cols = N.columns, rows = N.rows
        let material = Materials.flat(N.colour, opacity: N.opacity)
        for sign in [Float(-1), 1] {
            let back = (0...rows).flatMap { r in (0...cols).map { c in
                SIMD3<Float>(-hw + 2 * hw * Float(c) / Float(cols), h * Float(r) / Float(rows), sign * (line + depth))
            } }
            let roof = (0...rows).flatMap { r in (0...cols).map { c in
                SIMD3<Float>(-hw + 2 * hw * Float(c) / Float(cols), h, sign * (line + depth * Float(r) / Float(rows)))
            } }
            var pair: [Sheet] = []
            for (rest, normal) in [(back, SIMD3<Float>(0, 0, sign)), (roof, SIMD3<Float>(0, 1, 0))] {
                let lo = rest.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) } - 1
                let hi = rest.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) } + 1
                let mesh = try DynamicMesh(vertexCount: rest.count, triangles: DynamicMesh.grid(columns: cols, rows: rows),
                                           bounds: BoundingBox(min: lo, max: hi))
                mesh.write { v in for (i, p) in rest.enumerated() { v[i] = .init(position: p, uv: .zero) } }
                root.addChild(ModelEntity(mesh: mesh.resource, materials: [material]))
                pair.append(Sheet(mesh: mesh, rest: rest, normal: normal))
            }
            sheets.append(pair)
        }
    }

    /// A goal into the net on goal line `goalZ`, the ball at `x` across it.
    func goal(goalZ: Double, x: Double) {
        let hw = Tuning.Pitch.goalMouthWidth / 2
        let z = (goalZ > 0 ? 1.0 : -1.0) * (Tuning.Pitch.goalLineZ + Tuning.Pitch.goalDepth)
        ripple = (goalZ > 0 ? 1 : 0, SIMD3(Float(min(max(x, -hw), hw)), 0.36, Float(z)), 0)
    }

    func advance(_ dt: Double) {
        guard var r = ripple else { return }
        r.age += dt
        let done = r.age >= N.seconds
        let t = r.age
        let envelope = N.amplitude * exp(-N.decay * t)
        for sheet in sheets[r.goal] {
            sheet.mesh.write { v in
                for (i, p) in sheet.rest.enumerated() {
                    let d = Double(simd_distance(p, r.strike))
                    let off = done ? 0 : envelope * sin(N.frequency * t - N.k * d) * exp(-d / N.reach)
                    v[i] = .init(position: p + sheet.normal * Float(off), uv: .zero)
                }
            }
        }
        ripple = done ? nil : r
    }
}
