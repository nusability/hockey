import RealityKit
import SmashCore
import UIKit

/// One of the five worlds (spec §13) on stage: its shared asset `<id>.usdz`, its materials bound by
/// name — `sky` gets the unlit sky, everything else the world shader lit by the world's look
/// (teams.toml [world.look], ADR 0006). No lights, no fog: the shading is ours.
@MainActor
final class WorldStage {
    let world: World
    let look: WorldLook
    let root = Entity()

    private init(world: World) {
        self.world = world
        look = world.look
    }

    static func load(_ world: World, materials: Materials) async throws -> WorldStage {
        let stage = WorldStage(world: world)
        let asset = try await Entity(named: world.rawValue, in: .main)
        try stage.bind(asset, materials: materials)
        try await WorldEffects.attach(to: asset, world: world, look: stage.look)   // what is alive (ADR 0007)
        stage.root.addChild(asset)
        return stage
    }

    private func bind(_ asset: Entity, materials: Materials) throws {
        var sawSky = false
        try visit(asset) { entity in
            guard var model = entity.components[ModelComponent.self] else { return }
            let isSky = entity.name == "sky" || entity.parent?.name == "sky"
            sawSky = sawSky || isSky
            model.materials = try model.materials.map { original -> RealityKit.Material in
                isSky ? try Materials.sky(from: original) : try materials.world(from: original, look: look)
            }
            entity.components.set(model)
        }
        if !sawSky { throw AssetError.missing("\(world.rawValue).usdz has no mesh named 'sky'") }
    }

    private func visit(_ e: Entity, _ body: (Entity) throws -> Void) rethrows {
        try body(e)
        for child in e.children { try visit(child, body) }
    }
}
