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
        let materials = try await Materials.load()
        let stage = try await WorldStage.load(.oasis, materials: materials)
        world.root.addChild(stage.root)
        Blocks.light(with: materials, look: World.oasis.look)
        return world
    }

    /// There is no fog any more (ADR 0006); the sketch still reports the camera each frame.
    func setFogEye(_ eye: SIMD3<Float>) {}
}
