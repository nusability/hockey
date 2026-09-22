import Metal
import RealityKit
import UIKit

/// The scene's few native materials (ADR 0005: bound by name, written twice from one formula), all
/// from Fog.metal: the world's palette, the toys, the marks on the pitch and the sky — the first
/// three fogged with the world's look. The twin of Android's material set (actor, overlay, sky and
/// gltfio's lit material under the view's fog).
@MainActor
final class Materials {
    private let world: CustomMaterial.SurfaceShader
    private let actor: CustomMaterial.SurfaceShader
    private let overlay: CustomMaterial.SurfaceShader
    private let sky: CustomMaterial.SurfaceShader

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let library = device.makeDefaultLibrary() else {
            throw AssetError.missing("the app's Metal library (Fog.metal)")
        }
        world = CustomMaterial.SurfaceShader(named: "fogSurface", in: library)
        actor = CustomMaterial.SurfaceShader(named: "actorSurface", in: library)
        overlay = CustomMaterial.SurfaceShader(named: "overlaySurface", in: library)
        sky = CustomMaterial.SurfaceShader(named: "skySurface", in: library)
    }

    /// The fog parameters every fogged material carries (Fog.metal's custom_parameter).
    static func fog(_ look: WorldLook) -> SIMD4<Float> {
        SIMD4(Float(look.fogStart), Float(look.fogDensity), Float(look.fogMax), Float(look.fog))
    }

    /// A world mesh's material: its palette, lit and fogged; both sides drawn (the assets are
    /// authored double-sided, and Android draws both sides too).
    func world(from original: RealityKit.Material, look: WorldLook) throws -> CustomMaterial {
        var m = try CustomMaterial(from: original, surfaceShader: world)
        m.custom.value = Materials.fog(look)
        m.faceCulling = .none
        return m
    }

    /// The sky dome: its palette gradient, unlit and unfogged, times the world's sky tint.
    func sky(from original: RealityKit.Material, look: WorldLook) throws -> CustomMaterial {
        var m = try CustomMaterial(from: original, surfaceShader: sky)
        m.custom.value = SIMD4(Materials.linear(look.sky), 1)
        m.faceCulling = .none
        return m
    }

    /// A toy's flat colour, lit and fogged.
    func actor(_ rgb: UInt32, look: WorldLook) throws -> CustomMaterial {
        var base = PhysicallyBasedMaterial()
        base.baseColor = .init(tint: Materials.colour(rgb))
        var m = try CustomMaterial(from: base, surfaceShader: actor)
        m.custom.value = Materials.fog(look)
        return m
    }

    /// A mark on the pitch: unlit, see-through, fogged; never casts a shadow.
    func overlay(_ rgb: UInt32, opacity: Double, look: WorldLook) throws -> CustomMaterial {
        var base = PhysicallyBasedMaterial()
        base.baseColor = .init(tint: Materials.colour(rgb))
        var m = try CustomMaterial(from: base, surfaceShader: overlay)
        m.custom.value = Materials.fog(look)
        m.blending = .transparent(opacity: .init(floatLiteral: Float(opacity)))
        m.faceCulling = .none
        return m
    }

    /// The 3D UI's surface: lit so blocks and letters read as objects, never fogged (ADR 0005).
    static func ui(_ rgb: UInt32) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: colour(rgb))
        m.roughness = 0.6
        m.metallic = 0.0
        return m
    }

    static func colour(_ rgb: UInt32) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    /// sRGB 0xRRGGBB to linear RGB — the same curve as Filament's `Colors.toLinear`.
    static func linear(_ rgb: UInt32) -> SIMD3<Float> {
        func f(_ c: UInt32) -> Float {
            let v = Float(c & 0xFF) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return SIMD3(f(rgb >> 16), f(rgb >> 8), f(rgb))
    }
}
