import RealityKit
import SmashCore

/// The offside mark (spec §16.4, §8.9) — the ice sport's only: a faded ring on the pitch under every
/// player the core reports offside, in their own kit's primary. It is the receiver's lock-on ring
/// (§5.2) made pale and unpulsed, and it fades in and out over `player.offside_fade` seconds of real
/// time as the core's answer changes, so a player who steps over the line and back does not flicker.
///
/// It is a **flat mark**, so it is drawn in the same group and order as the discs under the players
/// (`DrawOrder`) and cannot change places with them at the halfway line (SMASH-33's sibling). One
/// mesh per side carries that side's rings, written in place in the pitch's frame on an entity that
/// never moves and bounded by `SceneMarks.popExtent`; the fade rides in each vertex's `u`, which the
/// Trail shader multiplies its opacity by, because a material written on a frame is a resource
/// RealityKit never gives back (SMASH-24). The twin of OffsideMarks.kt.
@MainActor
final class OffsideMarks {
    typealias P = Presentation.Player
    let root = Entity()
    private static let segments = 28

    /// One side's rings: the players it draws for, their fades, and the mesh that holds them all.
    private struct Side {
        let mesh: DynamicMesh
        let entity: ModelEntity
        let players: [Int]
        var fade: [Double]
    }
    private var sides: [Side] = []
    private let radii: [Double]
    private let live: Bool

    /// `first` names the roster; `colours` its two kits. Nothing is built for a field match — the
    /// rule is the ice sport's (§8.9) — but the object stands so the pitch needs no second path.
    init(first: MatchSnapshot, colours: [TeamColours], sport: Sport, feel: FeelMaterials.Set) throws {
        live = sport == .ice
        radii = first.players.map(\.radius)
        guard live else { return }
        let n = Self.segments
        var tris: [UInt16] = []
        for i in 0..<n {
            let a = UInt16(2 * i)
            tris += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
        }
        let e = SceneMarks.popExtent(radius: Tuning.Player.outfieldRadius + P.targetOuter)
        let bounds = BoundingBox(min: [Float(-e.x), -1, Float(-e.z)], max: [Float(e.x), 1, Float(e.z)])
        for team in 0..<2 {
            // Goalies and dummies are never offside (§8.9), so they get no ring to write.
            let players = first.players.indices.filter {
                first.players[$0].team == team && [.defender, .forward].contains(first.players[$0].role)
            }
            var material = feel.trail
            FeelMaterials.colour(&material, colours[team].primary)
            FeelMaterials.set(&material, "Opacity", P.offsideOpacity)
            let mesh = try DynamicMesh(vertexCount: players.count * 2 * (n + 1),
                                       triangles: (0..<players.count).flatMap { p in
                                           tris.map { $0 + UInt16(p * 2 * (n + 1)) }
                                       },
                                       bounds: bounds)
            let entity = ModelEntity(mesh: mesh.resource, materials: [material])
            DrawOrder.set(entity, DrawOrder.offside)
            entity.isEnabled = false
            root.addChild(entity)
            sides.append(Side(mesh: mesh, entity: entity, players: players, fade: .init(repeating: 0, count: players.count)))
        }
    }

    /// One frame: `s.offside` says who the whistle would name now (§8.9), `positions` where each
    /// player is drawn, `dt` the real seconds since the last frame.
    func update(_ s: MatchSnapshot, positions: [SIMD2<Double>], dt: Double) {
        guard live else { return }
        let step = dt / max(P.offsideFade, 1e-6)
        for i in sides.indices {
            var any = false
            for (k, p) in sides[i].players.enumerated() {
                let want: Double = s.offside[p] ? 1 : 0
                let was = sides[i].fade[k]
                sides[i].fade[k] = was < want ? min(want, was + step) : max(want, was - step)
                if sides[i].fade[k] > 0 { any = true }
            }
            sides[i].entity.isEnabled = any
            guard any else { continue }
            write(sides[i], positions)
        }
    }

    private func write(_ side: Side, _ positions: [SIMD2<Double>]) {
        let n = Self.segments
        side.mesh.write { v in
            for (k, p) in side.players.enumerated() {
                let fade = Float(side.fade[k])
                let at = positions[p]
                let inner = Float(radii[p] + P.targetInner), outer = Float(radii[p] + P.targetOuter)
                let base = k * 2 * (n + 1)
                for j in 0...n {
                    let a = Float(j) / Float(n) * 2 * .pi
                    let (sn, cs) = (sin(a), cos(a))
                    v[base + 2 * j] = .init(position: [Float(at.x) + inner * sn, 0.03, Float(at.y) + inner * cs],
                                            uv: [fade, 0])
                    v[base + 2 * j + 1] = .init(position: [Float(at.x) + outer * sn, 0.03, Float(at.y) + outer * cs],
                                                uv: [fade, 1])
                }
            }
        }
    }
}
