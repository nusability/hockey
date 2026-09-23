import RealityKit
import SmashCore
import simd

/// The nets' sheets, their cloth sway and their ripple (spec §8.8): each goal's back and roof carry
/// a light sheet (the prototype's net under its cords).
///
/// A net is cloth, so it always breathes: every point sways along the sheet's outward normal by
/// `sway.amplitude · bell · sin(2π·t / sway.seconds + sway.wave·(x + z))`, `bell` being
/// `sin(π·u)·sin(π·v)` over the sheet's own grid — nothing at the edges it is laced to, most in the
/// middle. Reduce Motion keeps `sway.reduce_motion` of that: calmer, never frozen.
///
/// On top of it, a goal sends a wave through the scored-in net's sheets from where the ball struck —
/// `amplitude · e^(−decay·t) · sin(frequency·t − k·r) · e^(−r/reach)`, r the distance from the
/// strike, t real seconds since the goal — for `seconds`, then only the sway is left. The twin of
/// NetRipple.kt.
@MainActor
final class NetRipple {
    typealias N = Presentation.Net
    let root = Entity()
    private struct Sheet {
        let mesh: DynamicMesh
        let rest: [SIMD3<Float>]
        let normal: SIMD3<Float>
        /// How freely each point may sway: 0 where the net is laced to its frame, 1 in the middle.
        let bell: [Double]
        /// Where each point sits in the travelling wave, radians.
        let phase: [Double]
    }
    /// Per goal (index 0: −z, 1: +z), its back and roof.
    private var sheets: [[Sheet]] = []
    private var ripple: (goal: Int, strike: SIMD3<Float>, age: Double)?
    private var clock = 0.0

    init() throws {
        let hw = Float(Tuning.Pitch.goalMouthWidth / 2), h = Float(N.height)
        let line = Float(Tuning.Pitch.goalLineZ), depth = Float(Tuning.Pitch.goalDepth)
        let cols = N.columns, rows = N.rows
        let material = Materials.flat(N.colour, opacity: N.opacity)
        // (u, v) over the grid: u across the mouth, v up the back / out along the roof.
        let grid = (0...rows).flatMap { r in (0...cols).map { c in
            (u: Double(c) / Double(cols), v: Double(r) / Double(rows))
        } }
        for sign in [Float(-1), 1] {
            let back = grid.map { g in
                SIMD3<Float>(-hw + 2 * hw * Float(g.u), h * Float(g.v), sign * (line + depth))
            }
            let roof = grid.map { g in
                SIMD3<Float>(-hw + 2 * hw * Float(g.u), h, sign * (line + depth * Float(g.v)))
            }
            var pair: [Sheet] = []
            for (rest, normal) in [(back, SIMD3<Float>(0, 0, sign)), (roof, SIMD3<Float>(0, 1, 0))] {
                let lo = rest.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) } - 1
                let hi = rest.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) } + 1
                let mesh = try DynamicMesh(vertexCount: rest.count, triangles: DynamicMesh.grid(columns: cols, rows: rows),
                                           bounds: BoundingBox(min: lo, max: hi))
                mesh.write { v in for (i, p) in rest.enumerated() { v[i] = .init(position: p, uv: .zero) } }
                root.addChild(ModelEntity(mesh: mesh.resource, materials: [material]))
                pair.append(Sheet(mesh: mesh, rest: rest, normal: normal,
                                  bell: grid.map { sin(.pi * $0.u) * sin(.pi * $0.v) },
                                  phase: rest.map { N.Sway.wave * Double($0.x + $0.z) }))
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

    /// One frame of real time: the cloth sways always, a goal's ripple rides on top of it.
    func advance(_ dt: Double, reduceMotion: Bool) {
        clock += dt
        let swayAmplitude = N.Sway.amplitude * (reduceMotion ? N.Sway.reduceMotion : 1)
        let swayPhase = 2 * Double.pi * clock / N.Sway.seconds
        var r = ripple
        if r != nil { r!.age += dt }
        let rippling = r.map { $0.age < N.seconds } ?? false
        let envelope = rippling ? N.amplitude * exp(-N.decay * r!.age) : 0
        for goal in sheets.indices {
            let hit = rippling && r!.goal == goal
            for sheet in sheets[goal] {
                sheet.mesh.write { v in
                    for (i, p) in sheet.rest.enumerated() {
                        var off = swayAmplitude * sheet.bell[i] * sin(swayPhase + sheet.phase[i])
                        if hit {
                            let d = Double(simd_distance(p, r!.strike))
                            off += envelope * sin(N.frequency * r!.age - N.k * d) * exp(-d / N.reach)
                        }
                        v[i] = .init(position: p + sheet.normal * Float(off), uv: .zero)
                    }
                }
            }
        }
        ripple = rippling ? r : nil
    }
}
