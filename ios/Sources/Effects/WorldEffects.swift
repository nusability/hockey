import RealityKit
import SmashCore
import UIKit

/// What is alive in a world (spec §13, ADR 0007) — the twin of Android's WorldEffects. Every effect
/// shared/data/effects.toml declares for the world is the mesh `fx_<id>` in its asset; this binds it to
/// one of the four effect shaders (FxMaterials) with the declared numbers. From then on the GPU moves
/// it on RealityKit's own clock: no per-frame work here, nothing shared with the match.
///
/// Reduce Motion is read once, at load: amplitudes and rates are multiplied by `FxCalm` — calmer, never
/// still. Effects are never culled: their shaders move them out of the bounds the asset was measured in.
@MainActor
enum WorldEffects {
    static func attach(to asset: Entity, world: World, look: WorldLook) async throws {
        let shaders = try await FxMaterials.load()
        let calm = UIAccessibility.isReduceMotionEnabled
        let amp = Float(calm ? FxCalm.amplitude : 1), speed = Float(calm ? FxCalm.speed : 1)
        for spec in world.effects {
            let name = "fx_\(spec.id)"
            guard let entity = modelEntity(named: name, in: asset), var model = entity.components[ModelComponent.self] else {
                throw AssetError.missing("\(world.rawValue).usdz has no mesh named '\(name)' (shared/data/effects.toml declares it)")
            }
            guard let palette = model.materials.lazy.compactMap(paletteTexture).first else {
                throw AssetError.missing("\(name) in \(world.rawValue).usdz without its palette texture")
            }
            var m: ShaderGraphMaterial
            switch spec.shading {
            case .lit: m = shaders.lit
            case .glow: m = shaders.glow
            case .soft: m = shaders.soft
            case .particles: m = shaders.particle
            }
            try m.setParameter(name: "Palette", value: .textureResource(palette))
            try bind(&m, spec, look, amp, speed)
            m.faceCulling = .none
            if spec.blend != .opaque { m.writesDepth = false }
            model.materials = model.materials.map { _ in m }
            model.boundsMargin = 1000
            entity.components.set(model)
        }
    }

    private static func bind(_ m: inout ShaderGraphMaterial, _ spec: FxSpec, _ look: WorldLook, _ amp: Float, _ speed: Float) throws {
        func v3(_ v: [Double], _ k: Float) -> MaterialParameters.Value {
            .simd3Float(SIMD3(Float(v[0]), Float(v[1]), Float(v[2])) * k)
        }
        let p = spec.pulse.map(Float.init)
        try m.setParameter(name: "PulseAmp", value: .simd3Float(SIMD3(p[0], p[1] * amp, p[3] * amp)))
        try m.setParameter(name: "PulseRate", value: .simd3Float(SIMD3(p[2] * speed, p[4] * speed, 0)))
        if spec.shading == .soft || spec.shading == .particles {
            try m.setParameter(name: "Opacity", value: .float(Float(spec.opacity)))
            try m.setParameter(name: "Additive", value: .float(spec.blend == .add ? 1 : 0))
        }
        if spec.shading == .particles {
            try m.setParameter(name: "Size", value: .float(Float(spec.size)))
            try m.setParameter(name: "SizeSpread", value: .float(Float(spec.sizeSpread)))
            try m.setParameter(name: "Travel", value: v3(spec.travel, speed))
            try m.setParameter(name: "Wrap", value: .float(Float(spec.wrap)))
            try m.setParameter(name: "Wobble", value: v3(spec.wobble, amp))
            try m.setParameter(name: "WobbleRate", value: .float(Float(spec.wobbleRate) * speed))
            return
        }
        try m.setParameter(name: "SwayAmp", value: v3(spec.sway, amp))
        try m.setParameter(name: "SwayRate", value: .float(Float(spec.swayRate) * speed))
        try m.setParameter(name: "Orbit", value: .float(spec.motion == .orbit ? 1 : 0))
        try m.setParameter(name: "Spin", value: .float(Float(spec.spin) * speed))
        try m.setParameter(name: "Pivot", value: v3(spec.pivot, 1))
        try m.setParameter(name: "Ellipse", value: .float(Float(spec.ellipse)))
        if spec.shading == .lit {
            func colour(_ rgb: UInt32, _ k: Double) -> MaterialParameters.Value {
                let c = Materials.linear(rgb) * Float(k)
                return .color(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                                      components: [CGFloat(c.x), CGFloat(c.y), CGFloat(c.z), 1])!)
            }
            try m.setParameter(name: "Sky", value: colour(look.hemiSky, look.hemiStrength))
            try m.setParameter(name: "Ground", value: colour(look.hemiGround, look.hemiStrength))
            try m.setParameter(name: "Sun", value: colour(look.sun, look.sunStrength))
            try m.setParameter(name: "SunDirection", value: .simd3Float(Materials.sunDirection(look)))
        }
    }

    /// The entity carrying `name`'s mesh: the prim itself or the Xform over it (USD puts the mesh
    /// under a transform of the same name).
    private static func modelEntity(named name: String, in root: Entity) -> Entity? {
        if root.name == name || root.parent?.name == name, root.components.has(ModelComponent.self) { return root }
        for child in root.children {
            if let e = modelEntity(named: name, in: child) { return e }
        }
        return nil
    }

    private static func paletteTexture(_ m: RealityKit.Material) -> TextureResource? {
        if let p = m as? PhysicallyBasedMaterial { return p.baseColor.texture?.resource }
        if let u = m as? UnlitMaterial { return u.color.texture?.resource }
        if let s = m as? ShaderGraphMaterial, case .textureResource(let t)? = s.getParameter(name: "Palette") { return t }
        return nil
    }
}
