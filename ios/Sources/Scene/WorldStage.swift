import RealityKit
import SmashCore
import UIKit

/// One of the five worlds (spec §13) on stage: its shared asset `<id>.usdz`, its materials bound by
/// name (`sky` unlit and unfogged; everything else lit and fogged), and its light — the world's
/// look (teams.toml [world.look]) on the rig the spike calibrated against Android's (ADR 0005).
@MainActor
final class WorldStage {
    /// The spike's calibrated rig: RealityKit lux for the sun and the fill at strength 1.
    private static let sunLux: Float = 4200
    private static let fillLux: Float = 1100

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
        stage.root.addChild(asset)
        stage.light()
        return stage
    }

    private func bind(_ asset: Entity, materials: Materials) throws {
        var sawSky = false
        try visit(asset) { entity in
            guard var model = entity.components[ModelComponent.self] else { return }
            let isSky = entity.name == "sky" || entity.parent?.name == "sky"
            sawSky = sawSky || isSky
            model.materials = try model.materials.map { original -> RealityKit.Material in
                isSky ? try materials.sky(from: original, look: look) : try materials.world(from: original, look: look)
            }
            entity.components.set(model)
            if isSky { entity.components.set(DynamicLightShadowComponent(castsShadow: false)) }
        }
        if !sawSky { throw AssetError.missing("\(world.rawValue).usdz has no mesh named 'sky'") }
    }

    private func light() {
        let d = Presentation.Light.sunDirection
        let direction = simd_normalize(SIMD3<Float>(Float(d[0]), Float(d[1]), Float(d[2])))
        let sun = DirectionalLight()
        sun.light.color = Materials.colour(look.sun)
        sun.light.intensity = WorldStage.sunLux * Float(look.sunStrength)
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 160, depthBias: 1.5)
        sun.look(at: .zero, from: -direction * 60, relativeTo: nil)
        root.addChild(sun)
        let fill = DirectionalLight()
        fill.light.color = Materials.colour(look.ambient)
        fill.light.intensity = WorldStage.fillLux * Float(look.ambientStrength)
        fill.look(at: .zero, from: SIMD3(-direction.x, 0.6, -direction.z) * 60, relativeTo: nil)
        root.addChild(fill)
    }

    private func visit(_ e: Entity, _ body: (Entity) throws -> Void) rethrows {
        try body(e)
        for child in e.children { try visit(child, body) }
    }
}
