import Metal
import RealityKit
import UIKit

/// The Oasis world as the spike draws it (SMASH-2): the shared asset, its materials bound by name
/// (sky unlit, everything else lit with the fog shader), the sun with its one shadow and a fill.
/// Unlike the spike's fixed camera, the camera here moves, so the fog's eye follows it.
@MainActor
final class OasisWorld {
    let root = Entity()
    private var fogged: [(entity: Entity, model: ModelComponent)] = []
    private var fogEye = SIMD3<Float>(repeating: .greatestFiniteMagnitude)

    static func load(eye: SIMD3<Float>) async throws -> OasisWorld {
        let world = OasisWorld()
        let asset = try await Entity(named: "oasis", in: .main)
        try world.bindMaterials(asset)
        world.root.addChild(asset)
        world.addLights()
        world.setFogEye(eye)
        return world
    }

    /// The fog is measured from the camera (Fog.metal's custom parameter). Rewriting materials
    /// is not free, so it follows the camera in 0.5 m steps — far below what 45 m of fog-free
    /// distance can show.
    func setFogEye(_ eye: SIMD3<Float>) {
        guard simd_distance(eye, fogEye) > 0.5 else { return }
        fogEye = eye
        for (i, item) in fogged.enumerated() {
            var model = item.model
            model.materials = model.materials.map { m in
                guard var lit = m as? CustomMaterial else { return m }
                lit.custom.value = SIMD4(eye, 0)
                return lit
            }
            item.entity.components.set(model)
            fogged[i].model = model
        }
    }

    private func bindMaterials(_ world: Entity) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let library = device.makeDefaultLibrary() else {
            throw AssetError.missing("the app's Metal library (Fog.metal)")
        }
        let fog = CustomMaterial.SurfaceShader(named: "fogSurface", in: library)
        let skyShader = CustomMaterial.SurfaceShader(named: "skySurface", in: library)
        var sawSky = false
        try visit(world) { entity in
            guard var model = entity.components[ModelComponent.self] else { return }
            let isSky = entity.name == "sky" || entity.parent?.name == "sky"
            sawSky = sawSky || isSky
            model.materials = try model.materials.map { original -> RealityKit.Material in
                if isSky {
                    var sky = try CustomMaterial(from: original, surfaceShader: skyShader)
                    sky.faceCulling = .none
                    return sky
                }
                var lit = try CustomMaterial(from: original, surfaceShader: fog)
                // Double-sided like the glTF twin (ADR 0005 spike finding).
                lit.faceCulling = .none
                return lit
            }
            entity.components.set(model)
            if isSky {
                entity.components.set(DynamicLightShadowComponent(castsShadow: false))
            } else {
                fogged.append((entity, model))
            }
        }
        if !sawSky { throw AssetError.missing("oasis.usdz has no mesh named 'sky'") }
    }

    private func addLights() {
        let sun = DirectionalLight()
        sun.light.color = UIColor(red: 1.0, green: 0.95, blue: 0.86, alpha: 1)
        sun.light.intensity = 4200
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 160, depthBias: 1.5)
        let direction = simd_normalize(SIMD3<Float>(0.35, -1.0, 0.55))
        sun.look(at: .zero, from: -direction * 60, relativeTo: nil)
        root.addChild(sun)
        let fill = DirectionalLight()
        fill.light.color = UIColor(red: 1.0, green: 0.93, blue: 0.85, alpha: 1)
        fill.light.intensity = 1100
        fill.look(at: .zero, from: SIMD3(-direction.x, 0.6, -direction.z) * 60, relativeTo: nil)
        root.addChild(fill)
    }

    private func visit(_ e: Entity, _ body: (Entity) throws -> Void) rethrows {
        try body(e)
        for child in e.children { try visit(child, body) }
    }
}
