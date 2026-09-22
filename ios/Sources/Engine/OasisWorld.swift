import RealityKit
import SmashCore
import UIKit

/// The Oasis world behind the UI sketch, shaded exactly as the match shades it (WorldStage, ADR
/// 0006): the world shader lit by the Oasis look, the sky unlit, no fog.
///
/// The two directional lights here light only the UI kit's physically based blocks, which are not
/// on our shading yet; the world's own materials are unlit and ignore them.
@MainActor
final class OasisWorld {
    let root = Entity()

    static func load(eye: SIMD3<Float>) async throws -> OasisWorld {
        let world = OasisWorld()
        let stage = try await WorldStage.load(.oasis, materials: try await Materials.load())
        world.root.addChild(stage.root)
        world.addLights(World.oasis.look)
        return world
    }

    /// There is no fog any more (ADR 0006); the sketch still reports the camera each frame.
    func setFogEye(_ eye: SIMD3<Float>) {}

    private func addLights(_ look: WorldLook) {
        let toward = Materials.sunDirection(look)
        let sun = DirectionalLight()
        sun.light.color = Materials.colour(look.sun)
        sun.light.intensity = 4200
        sun.look(at: .zero, from: toward * 60, relativeTo: nil)
        root.addChild(sun)
        let fill = DirectionalLight()
        fill.light.color = Materials.colour(look.hemiSky)
        fill.light.intensity = 1100
        fill.look(at: .zero, from: SIMD3(-toward.x, 0.6, -toward.z) * 60, relativeTo: nil)
        root.addChild(fill)
    }
}
