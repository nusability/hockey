import CoreGraphics
import Foundation
import RealityKit
import UIKit

/// The scene's four shaders (ADR 0006) — the prototype's look computed by us, the twin of Android's
/// world / toon / flat / sky materials:
///
/// - **world** — a world mesh: its palette texture, lit by the formula below;
/// - **toon** — a flat colour (players, posts, the ball), lit by the formula with the sun's term in
///   two bands, as the prototype's toon material;
/// - **uiToon** — the same shader for the 3D UI, read from the **object's own normal** instead of
///   the world's: a menu stands facing whichever camera pose its screen uses, so a key fixed in the
///   world falls on a different face of every screen and leaves most of them in the dark band —
///   which is what "washed out, in their own shadow" was. In the UI's own frame +Z is always the
///   face the player looks at, so `design.json`'s light means what it says on every screen and the
///   HUD, and nothing has to be rewritten as the camera moves;
/// - **flat** — an unlit colour at an opacity (the players' dots and rings, disc shadows, the aim line);
/// - **sky** — the dome's palette gradient, unlit.
///
/// `colour = albedo × (mix(ground, sky, 0.5 + 0.5·n.y) · hemiStrength + sun · sunStrength · band(n·l))`,
/// `band = max(0, n·l)` for the world and `n·l > 0.4 ? 1 : look.shade` for toon; n the normal — the
/// world's for the scene, the object's own for the UI —
/// l the unit vector toward the sun, every colour linear. No engine light and no tone mapping touch
/// it: world and toon are RealityKit shader graphs ending in the **unlit** surface with
/// `applyPostProcessToneMap` off, flat and sky are `UnlitMaterial(applyPostProcessToneMap: false)` —
/// so the linear result is encoded to sRGB once, by the view, exactly like Filament's unlit
/// materials under its linear tone mapper. (A `CustomMaterial` could compute the same colour but
/// cannot opt out of RealityKit's tone mapper before iOS 27.)
@MainActor
final class Materials {
    private let worldGraph: ShaderGraphMaterial
    private let toonGraph: ShaderGraphMaterial
    private let uiGraph: ShaderGraphMaterial
    private var toons: [ToonKey: ShaderGraphMaterial] = [:]

    private init(world: ShaderGraphMaterial, toon: ShaderGraphMaterial, ui: ShaderGraphMaterial) {
        worldGraph = world
        toonGraph = toon
        uiGraph = ui
    }

    /// Loads the two shader graphs (ShadingGraph.usda, written out at first use).
    static func load() async throws -> Materials {
        let url = try ShadingGraph.write()
        do {
            let world = try await ShaderGraphMaterial(named: "/Root/World", from: url)
            let toon = try await ShaderGraphMaterial(named: "/Root/Toon", from: url)
            let ui = try await ShaderGraphMaterial(named: "/Root/UIToon", from: url)
            return Materials(world: world, toon: toon, ui: ui)
        } catch {
            throw AssetError.missing("the shading graph (\(url.lastPathComponent)): \(error)")
        }
    }

    // MARK: the four shaders

    /// A world mesh's material: its palette (the base colour texture the asset was authored with),
    /// lit by the world's look; both sides drawn (the assets are double-sided, as on Android).
    func world(from original: RealityKit.Material, look: WorldLook) throws -> ShaderGraphMaterial {
        guard let palette = Materials.palette(of: original) else {
            throw AssetError.missing("a world material without its palette texture")
        }
        var m = worldGraph
        try Materials.light(&m, look)
        try m.setParameter(name: "Palette", value: .textureResource(palette))
        m.faceCulling = .none
        return m
    }

    /// A toon-shaded flat colour, lit by the world's look.
    func toon(_ rgb: UInt32, look: WorldLook) throws -> ShaderGraphMaterial {
        try shaded(toonGraph, rgb, look: look, ui: false)
    }

    /// The 3D UI's toon colour: the same formula read from the object's own normal, so the UI's
    /// light (design.json) lands on the face the player looks at whichever way a screen stands.
    func ui(_ rgb: UInt32, look: WorldLook) throws -> ShaderGraphMaterial {
        try shaded(uiGraph, rgb, look: look, ui: true)
    }

    private func shaded(_ graph: ShaderGraphMaterial, _ rgb: UInt32, look: WorldLook,
                        ui: Bool) throws -> ShaderGraphMaterial {
        let key = ToonKey(rgb: rgb, look: look, ui: ui)
        if let m = toons[key] { return m }
        var m = graph
        try Materials.light(&m, look)
        try m.setParameter(name: "Albedo", value: .color(Materials.linearColour(Materials.linear(rgb))))
        toons[key] = m
        return m
    }

    /// An unlit colour at an opacity, both sides drawn; see-through ones write no depth.
    static func flat(_ rgb: UInt32, opacity: Double = 1) -> UnlitMaterial {
        var m = UnlitMaterial(applyPostProcessToneMap: false)
        m.color = .init(tint: colour(rgb))
        m.faceCulling = .none
        if opacity < 1 {
            m.blending = .transparent(opacity: .init(floatLiteral: Float(opacity)))
            m.writesDepth = false
        }
        return m
    }

    /// The sky dome: its palette gradient, unlit.
    static func sky(from original: RealityKit.Material) throws -> UnlitMaterial {
        guard let palette = palette(of: original) else { throw AssetError.missing("the sky without its palette texture") }
        var m = UnlitMaterial(applyPostProcessToneMap: false)
        m.color = .init(tint: .white, texture: .init(palette))
        m.faceCulling = .none
        return m
    }

    // MARK: helpers

    private struct ToonKey: Hashable { let rgb: UInt32; let look: WorldLook; let ui: Bool }

    /// The hemisphere and the sun, premultiplied by their strengths, and the unit vector toward the sun.
    private static func light(_ m: inout ShaderGraphMaterial, _ look: WorldLook) throws {
        try m.setParameter(name: "Sky", value: .color(linearColour(linear(look.hemiSky) * Float(look.hemiStrength))))
        try m.setParameter(name: "Ground", value: .color(linearColour(linear(look.hemiGround) * Float(look.hemiStrength))))
        try m.setParameter(name: "Sun", value: .color(linearColour(linear(look.sun) * Float(look.sunStrength))))
        try m.setParameter(name: "SunDirection", value: .simd3Float(sunDirection(look)))
        try m.setParameter(name: "Shade", value: .float(Float(look.shade)))
    }

    static func sunDirection(_ look: WorldLook) -> SIMD3<Float> {
        let d = look.sunDirection
        return simd_normalize(SIMD3(Float(d[0]), Float(d[1]), Float(d[2])))
    }

    private static func palette(of m: RealityKit.Material) -> TextureResource? {
        if let p = m as? PhysicallyBasedMaterial { return p.baseColor.texture?.resource }
        if let u = m as? UnlitMaterial { return u.color.texture?.resource }
        if let s = m as? SimpleMaterial { return s.color.texture?.resource }
        return nil
    }

    /// A linear-light colour as a CGColor in the extended linear sRGB space, so RealityKit hands the
    /// graph these exact values.
    private static func linearColour(_ c: SIMD3<Float>) -> CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                components: [CGFloat(c.x), CGFloat(c.y), CGFloat(c.z), 1])!
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

/// The world and toon shaders as a RealityKit shader graph (MaterialX nodes in USD), written to the
/// temporary directory and loaded from there. Both end in the unlit surface with tone mapping off.
enum ShadingGraph {
    static func write() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shading", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try whitePixel().write(to: dir.appendingPathComponent("white.png"))
        let url = dir.appendingPathComponent("shading.usda")
        try usda.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A 1×1 white PNG: the palette input's default until a world's palette is bound.
    private static func whitePixel() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        guard let data = image.pngData() else { throw AssetError.missing("a white pixel") }
        return data
    }

    static var usda: String {
        """
        #usda 1.0
        (
            defaultPrim = "Root"
            metersPerUnit = 1
            upAxis = "Y"
        )

        def Xform "Root"
        {
        \(material("World", toon: false))
        \(material("Toon", toon: true))
        \(material("UIToon", toon: true, space: "object"))
        }

        """
    }

    /// One material: `colour = albedo × (mix(Ground, Sky, 0.5 + 0.5·n.y) + Sun · band(n·SunDirection))`,
    /// the toon band's dark side being the look's `Shade`.
    private static func material(_ name: String, toon: Bool, space: String = "world") -> String {
        let p = "/Root/\(name)"
        let albedoInput = toon
            ? "color3f inputs:Albedo = (1, 1, 1)"
            : "asset inputs:Palette = @white.png@"
        let albedo = toon ? "\(p).inputs:Albedo" : "\(p)/Palette.outputs:out"
        let band = toon
            ? """
                def Shader "Band"
                {
                    uniform token info:id = "ND_ifgreater_float"
                    float inputs:value1.connect = <\(p)/Facing.outputs:out>
                    float inputs:value2 = 0.4
                    float inputs:in1 = 1
                    float inputs:in2.connect = <\(p).inputs:Shade>
                    float outputs:out
                }
            """
            : """
                def Shader "Band"
                {
                    uniform token info:id = "ND_max_float"
                    float inputs:in1.connect = <\(p)/Facing.outputs:out>
                    float inputs:in2 = 0
                    float outputs:out
                }
            """
        let texture = toon ? "" : """
                def Shader "UV"
                {
                    uniform token info:id = "ND_texcoord_vector2"
                    int inputs:index = 0
                    float2 outputs:out
                }

                def Shader "Palette"
                {
                    uniform token info:id = "ND_image_color3"
                    asset inputs:file.connect = <\(p).inputs:Palette>
                    string inputs:filtertype = "closest"
                    float2 inputs:texcoord.connect = <\(p)/UV.outputs:out>
                    string inputs:uaddressmode = "clamp"
                    string inputs:vaddressmode = "clamp"
                    color3f outputs:out
                }
            """
        return """
            def Material "\(name)"
            {
                \(albedoInput)
                color3f inputs:Sky = (1, 1, 1)
                color3f inputs:Ground = (0, 0, 0)
                color3f inputs:Sun = (0, 0, 0)
                float3 inputs:SunDirection = (0, 1, 0)
                float inputs:Shade = 0.7
                token outputs:mtlx:surface.connect = <\(p)/Surface.outputs:out>
                token outputs:realitykit:vertex

                def Shader "Surface"
                {
                    uniform token info:id = "ND_realitykit_unlit_surfaceshader"
                    bool inputs:applyPostProcessToneMap = 0
                    color3f inputs:color.connect = <\(p)/Shaded.outputs:out>
                    bool inputs:hasPremultipliedAlpha = 0
                    float inputs:opacity = 1
                    token outputs:out
                }

                def Shader "Normal"
                {
                    uniform token info:id = "ND_normal_vector3"
                    string inputs:space = "\(space)"
                    float3 outputs:out
                }

                def Shader "Unit"
                {
                    uniform token info:id = "ND_normalize_vector3"
                    float3 inputs:in.connect = <\(p)/Normal.outputs:out>
                    float3 outputs:out
                }

                def Shader "Up"
                {
                    uniform token info:id = "ND_dotproduct_vector3"
                    float3 inputs:in1.connect = <\(p)/Unit.outputs:out>
                    float3 inputs:in2 = (0, 0.5, 0)
                    float outputs:out
                }

                def Shader "Weight"
                {
                    uniform token info:id = "ND_add_float"
                    float inputs:in1.connect = <\(p)/Up.outputs:out>
                    float inputs:in2 = 0.5
                    float outputs:out
                }

                def Shader "Hemi"
                {
                    uniform token info:id = "ND_mix_color3"
                    color3f inputs:fg.connect = <\(p).inputs:Sky>
                    color3f inputs:bg.connect = <\(p).inputs:Ground>
                    float inputs:mix.connect = <\(p)/Weight.outputs:out>
                    color3f outputs:out
                }

                def Shader "Facing"
                {
                    uniform token info:id = "ND_dotproduct_vector3"
                    float3 inputs:in1.connect = <\(p)/Unit.outputs:out>
                    float3 inputs:in2.connect = <\(p).inputs:SunDirection>
                    float outputs:out
                }

            \(band)

                def Shader "SunLight"
                {
                    uniform token info:id = "ND_multiply_color3FA"
                    color3f inputs:in1.connect = <\(p).inputs:Sun>
                    float inputs:in2.connect = <\(p)/Band.outputs:out>
                    color3f outputs:out
                }

                def Shader "Light"
                {
                    uniform token info:id = "ND_add_color3"
                    color3f inputs:in1.connect = <\(p)/Hemi.outputs:out>
                    color3f inputs:in2.connect = <\(p)/SunLight.outputs:out>
                    color3f outputs:out
                }

            \(texture)

                def Shader "Shaded"
                {
                    uniform token info:id = "ND_multiply_color3"
                    color3f inputs:in1.connect = <\(albedo)>
                    color3f inputs:in2.connect = <\(p)/Light.outputs:out>
                    color3f outputs:out
                }
            }
        """
    }
}
