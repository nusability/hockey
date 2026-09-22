import CoreText
import RealityKit
import SmashCore
import UIKit

/// Extruded 3D lettering from the shared font (ADR 0005), via RealityKit's own text mesher — the
/// same outlines Android's TextMesh flattens itself. [height] is the cap height in metres, the
/// text is centred on its bounds, and its front face points down +Z.
@MainActor
enum TextMesh {
    /// The font's own cap height, the unit every `height` in the kit is given in (FontMetrics).
    private static let capHeightPerEm = Float(FontMetrics.capHeight) / Float(FontMetrics.unitsPerEm)
    private static var registered = false

    static func registerFont() throws {
        guard !registered else { return }
        guard let url = Bundle.main.url(forResource: "LilitaOne-Regular", withExtension: "ttf") else {
            throw AssetError.missing("LilitaOne-Regular.ttf — shared/assets/fonts is not in the app bundle")
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            let reason = error?.takeRetainedValue().localizedDescription ?? "unknown"
            if !reason.contains("already registered") { throw AssetError.missing("font registration: \(reason)") }
        }
        registered = true
    }

    /// A node whose child is the centred text model — rotate and scale the node, not the model.
    static func entity(_ text: String, height: Float, depth: Float, material: RealityKit.Material) -> Entity {
        let mesh = mesh(text, height: height, depth: depth)
        let model = ModelEntity(mesh: mesh, materials: [material])
        let b = mesh.bounds
        model.position = SIMD3(-b.center.x, -b.center.y, -b.center.z)
        let node = Entity()
        node.addChild(model)
        return node
    }

    /// The extruded mesh for `text`, meshed once per (text, height, depth) and cached: a flip
    /// digit or a ticking clock asks for the same few strings over and over.
    static func mesh(_ text: String, height: Float, depth: Float) -> MeshResource {
        let key = MeshKey(text: text, height: height, depth: depth)
        if let cached = cache[key] { return cached }
        let size = CGFloat(height / capHeightPerEm)
        guard let font = UIFont(name: "LilitaOne", size: size) else {
            preconditionFailure("Lilita One is not registered — call TextMesh.registerFont() first")
        }
        let mesh = MeshResource.generateText(text, extrusionDepth: depth, font: font,
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byClipping)
        cache[key] = mesh
        Diagnostics.meshBuilt()
        return mesh
    }

    private struct MeshKey: Hashable { let text: String; let height: Float; let depth: Float }
    private static var cache: [MeshKey: MeshResource] = [:]
}
