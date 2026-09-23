import RealityKit
import SmashCore
import simd

/// The goals' nets (spec §8.8) — the whole net, cords and film, drawn and moved by the app.
///
/// The world's asset carries the goal *frame* alone (ADR 0008): posts and crossbar. Everything laced
/// to it is here, so that everything the player reads as "the net" moves. Each goal is four sheets —
/// back, roof and two sides (core `GoalNet`) — and each sheet is a cord grid over a translucent film.
/// A net is cloth, so it always breathes: every node sways along its sheet's outward normal by
/// `sway.amplitude · bell · sin(2π·t / sway.seconds + sway.wave·(x + z))`, and on a goal a damped
/// wave from where the ball struck rides on top of it. Reduce Motion keeps `sway.reduce_motion` of
/// the sway — applied once, here.
///
/// Both nets are two meshes — every film, and every cord — written in the pitch's frame on entities
/// that never move, bounded by `GoalNet.extent`, which a test walks every vertex of every frame of
/// the sway and of a goal against (SMASH-33). The twin of NetRipple.kt.
@MainActor
final class NetRipple {
    typealias N = Presentation.Net
    let root = Entity()

    /// `presentation.toml [net]` and `[net.sway]`, the numbers both platforms move the net by.
    static let params = GoalNet.Params(
        height: N.height, columns: N.columns, rows: N.rows, depth: N.depth, cord: N.cord,
        cordLift: N.cordLift, sway: N.Sway.amplitude, swaySeconds: N.Sway.seconds, wave: N.Sway.wave,
        calm: N.Sway.reduceMotion, ripple: N.amplitude, decay: N.decay, frequency: N.frequency,
        k: N.k, reach: N.reach, seconds: N.seconds)

    /// One vertex of a net: where it rests, along which normal it moves, how freely (`bell`), how far
    /// it already stands off its sheet at rest (a cord's lift), and which goal it belongs to.
    private struct Vertex {
        let rest: SIMD3<Float>
        let node: SIMD3<Double>
        let normal: SIMD3<Float>
        let bell: Double
        let lift: Float
        let goal: Int
    }

    private let film: DynamicMesh
    private let cords: DynamicMesh
    private let filmModel: ModelEntity
    private let cordModel: ModelEntity
    private var filmVertices: [Vertex] = []
    private var cordVertices: [Vertex] = []
    /// Per goal (0: −z, the player's own end; 1: +z), the ripple running in it.
    private var ripple: [(strike: SIMD3<Double>, age: Double)] = [(.zero, -1), (.zero, -1)]
    private var clock = 0.0

    init() throws {
        let p = Self.params
        var filmTris: [UInt16] = []
        var cordTris: [UInt16] = []
        for (goal, sign) in [Double(-1), 1].enumerated() {
            for sheet in GoalNet.sheets(sign, p) {
                Self.addFilm(sheet, goal: goal, into: &filmVertices, &filmTris)
                Self.addCords(sheet, goal: goal, cord: p.cord, lift: p.cordLift,
                              into: &cordVertices, &cordTris)
            }
        }
        let e = GoalNet.extent(p)
        let bounds = BoundingBox(min: [Float(-e.x), Float(e.yLow), Float(-e.z)],
                                 max: [Float(e.x), Float(e.yHigh), Float(e.z)])
        film = try DynamicMesh(vertexCount: filmVertices.count, triangles: filmTris, bounds: bounds)
        cords = try DynamicMesh(vertexCount: cordVertices.count, triangles: cordTris, bounds: bounds)
        filmModel = ModelEntity(mesh: film.resource, materials: [Materials.flat(N.colour, opacity: N.opacity)])
        cordModel = ModelEntity(mesh: cords.resource, materials: [Materials.flat(N.colour)])
        DrawOrder.set(filmModel, DrawOrder.net)          // the film is see-through; the cords are not
        root.addChild(filmModel)
        root.addChild(cordModel)
        advance(0, reduceMotion: false)
    }

    /// The cords take the world's own net colour (teams.toml `net`); the film keeps `[net] colour`.
    func paint(_ world: World) {
        cordModel.model?.materials = [Materials.flat(world.netColour)]
    }

    /// A goal into the net on goal line `goalZ`, the ball at `x` across it.
    func goal(goalZ: Double, x: Double) {
        let strike = GoalNet.strike(goalZ: goalZ, ballX: x, Self.params)
        ripple[goalZ > 0 ? 1 : 0] = (SIMD3(strike.x, strike.y, strike.z), 0)
    }

    /// One frame of real time: the cloth sways always, a goal's ripple rides on top of it.
    func advance(_ dt: Double, reduceMotion: Bool) {
        clock += dt
        for i in ripple.indices where ripple[i].age >= 0 { ripple[i].age += dt }
        write(film, filmVertices, reduceMotion: reduceMotion)
        write(cords, cordVertices, reduceMotion: reduceMotion)
    }

    private func write(_ mesh: DynamicMesh, _ vertices: [Vertex], reduceMotion: Bool) {
        let p = Self.params
        let (t, r) = (clock, ripple)
        mesh.write { v in
            for (i, q) in vertices.enumerated() {
                let hit = r[q.goal]
                let d = GoalNet.offset(x: q.node.x, y: q.node.y, z: q.node.z, bell: q.bell, t: t,
                                       reduceMotion: reduceMotion, strikeX: hit.strike.x,
                                       strikeY: hit.strike.y, strikeZ: hit.strike.z, age: hit.age, p)
                v[i] = .init(position: q.rest + q.normal * (Float(d) + q.lift), uv: .zero)
            }
        }
    }

    // MARK: the two meshes

    /// A sheet's film: its grid of nodes, two triangles a cell.
    private static func addFilm(_ sheet: GoalNet.Sheet, goal: Int,
                                into vertices: inout [Vertex], _ triangles: inout [UInt16]) {
        let base = UInt16(vertices.count)
        for j in 0...sheet.rows {
            for i in 0...sheet.columns {
                vertices.append(vertex(sheet, i, j, goal: goal, shift: .zero, lift: 0))
            }
        }
        triangles += DynamicMesh.grid(columns: sheet.columns, rows: sheet.rows).map { $0 + base }
    }

    /// A sheet's cords: a thin ribbon along every grid line, both ways, standing `lift` off the film.
    private static func addCords(_ sheet: GoalNet.Sheet, goal: Int, cord: Double, lift: Double,
                                 into vertices: inout [Vertex], _ triangles: inout [UInt16]) {
        let half = cord / 2
        let (a, u) = (sheet.acrossUnit, sheet.upUnit)
        // Along `across` — one ribbon per row of nodes, widened along `up`.
        for j in 0...sheet.rows {
            strip(sheet, goal: goal, lift: lift, count: sheet.columns,
                  node: { (i: Int) in (i, j) }, shift: SIMD3(Float(u.x), Float(u.y), Float(u.z)) * Float(half),
                  into: &vertices, &triangles)
        }
        // Along `up` — one ribbon per column of nodes, widened along `across`.
        for i in 0...sheet.columns {
            strip(sheet, goal: goal, lift: lift, count: sheet.rows,
                  node: { (j: Int) in (i, j) }, shift: SIMD3(Float(a.x), Float(a.y), Float(a.z)) * Float(half),
                  into: &vertices, &triangles)
        }
    }

    /// One cord: `count` + 1 nodes, two vertices each (either side of the line), a quad per segment.
    private static func strip(_ sheet: GoalNet.Sheet, goal: Int, lift: Double, count: Int,
                              node: (Int) -> (Int, Int), shift: SIMD3<Float>,
                              into vertices: inout [Vertex], _ triangles: inout [UInt16]) {
        let base = UInt16(vertices.count)
        for k in 0...count {
            let (i, j) = node(k)
            vertices.append(vertex(sheet, i, j, goal: goal, shift: -shift, lift: lift))
            vertices.append(vertex(sheet, i, j, goal: goal, shift: shift, lift: lift))
        }
        for k in 0..<count {
            let q = base + UInt16(2 * k)
            triangles += [q, q + 2, q + 1, q + 1, q + 2, q + 3]
        }
    }

    private static func vertex(_ sheet: GoalNet.Sheet, _ i: Int, _ j: Int, goal: Int,
                               shift: SIMD3<Float>, lift: Double) -> Vertex {
        let node = sheet.point(i, j)
        let n = sheet.normal
        return Vertex(rest: SIMD3(Float(node.x), Float(node.y), Float(node.z)) + shift,
                      node: SIMD3(node.x, node.y, node.z),
                      normal: SIMD3(Float(n.x), Float(n.y), Float(n.z)),
                      bell: sheet.bell(i, j), lift: Float(lift), goal: goal)
    }
}
