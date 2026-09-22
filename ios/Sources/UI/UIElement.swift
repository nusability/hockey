import RealityKit
import UIKit

/// What every frame hands a UI element: the tokens, the time, and whether to be calm.
struct UIContext {
    let motion: MotionTokens
    let reduceMotion: Bool
    let time: Double
}

/// A piece of the 3D UI: one entity subtree with its own motion, advanced by the stage's clock.
@MainActor
protocol UIElement: AnyObject {
    var entity: Entity { get }
    func update(_ dt: Double, _ ctx: UIContext)
}

/// An element that arrives and leaves on its own motion (see `Presence`).
@MainActor
protocol Presentable: UIElement {
    func show(after delay: Double)
    func hide(after delay: Double)
}

/// What a node tells the accessibility overlay about itself (ADR 0005). The overlay is derived
/// from these every frame — never hand-placed.
struct Semantics: Equatable {
    enum Trait: Equatable { case button, adjustable, staticText, header }
    /// The stable id, the same on both platforms: `<surface>_<action>_button` and friends.
    let id: String
    var label: String
    var value: String?
    let trait: Trait
    var isEnabled = true
}

/// An element VoiceOver can find: it declares semantics and the box (in `boundsEntity`'s own
/// space) that the overlay projects to the screen.
@MainActor
protocol Semantic: UIElement {
    var semantics: Semantics { get }
    var boundsEntity: Entity { get }
    var bounds: BoundingBox { get }
    /// On screen and settled enough to be found (not arriving, leaving or hidden).
    var isPresent: Bool { get }
}

/// A world-space ray from a touch.
struct TouchRay {
    let origin: SIMD3<Float>
    let direction: SIMD3<Float>

    /// The ray in `e`'s own space.
    @MainActor func local(to e: Entity) -> TouchRay {
        TouchRay(origin: e.convert(position: origin, from: nil), direction: e.convert(direction: direction, from: nil))
    }

    /// Distance along the ray to `box` (in the ray's space), nil on a miss — the slab test, the
    /// same as Android's Node.hit.
    func hit(_ box: BoundingBox) -> Float? {
        var tMin: Float = 0, tMax = Float.greatestFiniteMagnitude
        for a in 0..<3 {
            if abs(direction[a]) < 1e-8 {
                if origin[a] < box.min[a] || origin[a] > box.max[a] { return nil }
            } else {
                let t1 = (box.min[a] - origin[a]) / direction[a], t2 = (box.max[a] - origin[a]) / direction[a]
                tMin = max(tMin, min(t1, t2)); tMax = min(tMax, max(t1, t2))
                if tMin > tMax { return nil }
            }
        }
        return tMin
    }

    /// Where the ray crosses the z = 0 plane of its space, nil if it runs parallel.
    var onPlane: SIMD3<Float>? {
        guard abs(direction.z) > 1e-6 else { return nil }
        return origin + direction * (-origin.z / direction.z)
    }
}

/// A Semantic that takes touches. The stage's own ray test finds it; the overlay's activation
/// and adjust actions route to the same code a finger does.
@MainActor
protocol Interactive: Semantic {
    func touchDown(_ ray: TouchRay)
    func touchMoved(_ ray: TouchRay)
    /// `inside`: the finger lifted over the element — a button fires only then.
    func touchUp(_ ray: TouchRay, inside: Bool)
    func activate()
    func adjust(by steps: Int)
}

extension Interactive {
    func touchMoved(_ ray: TouchRay) {}
    func adjust(by steps: Int) {}
}

/// The UI's building blocks: rounded slabs and lettering, their meshes and materials made once.
/// UI materials are plain lit PBR — no fog (the fog shader is the world's) — and nothing in the
/// UI casts a shadow (ADR 0005).
@MainActor
enum Blocks {
    private struct BoxKey: Hashable { let w: Float; let h: Float; let d: Float; let r: Float }
    private static var boxes: [BoxKey: MeshResource] = [:]
    private static var materials: [Int: PhysicallyBasedMaterial] = [:]

    static func material(_ rgb: Int) -> PhysicallyBasedMaterial {
        if let m = materials[rgb] { return m }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: colour(rgb))
        m.roughness = 0.5
        m.metallic = 0.0
        m.clearcoat = .init(floatLiteral: 0.4)    // toy plastic
        materials[rgb] = m
        return m
    }

    static func colour(_ rgb: Int) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    static func box(_ size: SIMD3<Float>, corner: Float = DesignTokens.Size.corner) -> MeshResource {
        let r = min(corner, size.x / 2, size.y / 2, size.z / 2)
        let key = BoxKey(w: size.x, h: size.y, d: size.z, r: r)
        if let m = boxes[key] { return m }
        let m = MeshResource.generateBox(width: size.x, height: size.y, depth: size.z, cornerRadius: r)
        boxes[key] = m
        return m
    }

    static func slab(_ size: SIMD3<Float>, _ rgb: Int, corner: Float = DesignTokens.Size.corner) -> ModelEntity {
        model(box(size, corner: corner), rgb)
    }

    static func model(_ mesh: MeshResource, _ rgb: Int) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [material(rgb)])
        e.components.set(DynamicLightShadowComponent(castsShadow: false))
        return e
    }

    /// Centred extruded text with its front face toward +Z. Depth follows the height by token.
    static func text(_ s: String, height: Float, _ rgb: Int) -> ModelEntity {
        let e = model(TextMesh.mesh(s, height: height, depth: height * DesignTokens.Size.textDepthRatio), rgb)
        centre(e)
        return e
    }

    /// Replaces a text model's string in place, keeping it centred.
    static func retext(_ e: ModelEntity, _ s: String, height: Float) {
        e.model?.mesh = TextMesh.mesh(s, height: height, depth: height * DesignTokens.Size.textDepthRatio)
        centre(e)
    }

    static func recolour(_ e: ModelEntity, _ rgb: Int) {
        e.model?.materials = [material(rgb)]
    }

    private static func centre(_ e: ModelEntity) {
        guard let b = e.model?.mesh.bounds else { return }
        e.position = SIMD3(-b.center.x, -b.center.y, -b.min.z)   // back face on z = 0
    }

    static func width(of e: ModelEntity) -> Float { e.model?.mesh.bounds.extents.x ?? 0 }
}
