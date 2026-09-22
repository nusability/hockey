import Observation
import RealityKit
import SwiftUI
import UIKit

/// What the SwiftUI layer reads from the scene: the button's projected rectangle, for the
/// accessibility overlay.
@MainActor @Observable
final class SpikeOverlay {
    var buttonRect: CGRect?
}

/// The renderer spike's vertical slice (SMASH-2), the twin of Android's SpikeScene: the Oasis
/// world, a floating title, a camera-parented score HUD and one 3D button that squashes on a
/// spring. Every placement number mirrors Android's so the two can be laid side by side.
@MainActor
final class SpikeScene {
    let root = Entity()
    let overlay = SpikeOverlay()
    let buttonLabelText = String(localized: "play.button")
    var viewSize = CGSize(width: 1, height: 1)
    var reduceMotion = false

    private let camera = PerspectiveCamera()
    private let fovDegrees: Float = 50
    private let hudDepth: Float = 4
    private let eye = SIMD3<Float>(0, 24, -46)
    private let motion: MotionTokens
    private let stats = FrameStats()
    private var press: Spring
    private var fade = 0.0
    private var time = 0.0
    private var goals = 0
    private var clockText = ""

    private var title = Entity()
    private var probe = Entity()
    private var button = ModelEntity()
    private var buttonMaterial = PhysicallyBasedMaterial()
    private var labelMaterial = PhysicallyBasedMaterial()
    private var buttonLabel = Entity()
    private var score: Entity?
    private var clock: Entity?

    init() throws {
        motion = try MotionTokens.load()
        press = Spring(motion.bouncy)
        try TextMesh.registerFont()
    }

    // MARK: building

    func build() async throws {
        // The world and its light as the match draws them (WorldStage): the spike's Oasis.
        let stage = try await WorldStage.load(.oasis, materials: try await Materials.load())
        root.addChild(stage.root)

        camera.camera.fieldOfViewInDegrees = fovDegrees
        camera.camera.fieldOfViewOrientation = .vertical
        camera.camera.near = 0.1
        camera.camera.far = 500
        camera.look(at: SIMD3(0, 0, 2), from: eye, relativeTo: nil)
        root.addChild(camera)

        buildTitle()
        score = replaceText(score, "0 : 0", height: 0.2, depth: 0.05, rgb: 0xFFFFFF, fromTop: 0.82)
        buildButton()
    }

    private func buildTitle() {
        title = TextMesh.entity(String(localized: "app.name"), height: 2.0, depth: 0.55, material: lit(0xFFF4D6))
        title.position = SIMD3(0, 4.5, 18)
        root.addChild(title)
        probe = TextMesh.entity(String(localized: "umlaut.probe"), height: 1.1, depth: 0.35, material: lit(0xFF6B6B))
        probe.position = SIMD3(0, 1.6, 17)
        probe.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        root.addChild(probe)
    }

    private func buildButton() {
        buttonMaterial = lit(0xFFC83D)
        labelMaterial = lit(0x1E1B4B)
        button = ModelEntity(mesh: .generateBox(width: 0.95, height: 0.34, depth: 0.16), materials: [buttonMaterial])
        button.position = SIMD3(0, -hudHalfHeight * 0.62, -hudDepth)
        button.components.set(DynamicLightShadowComponent(castsShadow: false))
        camera.addChild(button)
        buttonLabel = TextMesh.entity(buttonLabelText, height: 0.15, depth: 0.04, material: labelMaterial)
        buttonLabel.position = SIMD3(0, 0, 0.09)
        button.addChild(buttonLabel)
    }

    private var hudHalfHeight: Float { hudDepth * tan(fovDegrees / 2 * .pi / 180) }

    private func replaceText(_ old: Entity?, _ text: String, height: Float, depth: Float, rgb: Int, fromTop: Float) -> Entity {
        old?.removeFromParent()
        let node = TextMesh.entity(text, height: height, depth: depth, material: lit(rgb))
        node.position = SIMD3(0, hudHalfHeight * fromTop, -hudDepth)
        camera.addChild(node)
        return node
    }

    private func lit(_ rgb: Int) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                                          blue: CGFloat(rgb & 0xFF) / 255, alpha: 1))
        m.roughness = 0.6
        m.metallic = 0.0
        return m
    }

    // MARK: frame

    /// The one clock (ADR 0005): called from the scene's update event, once per rendered frame.
    func update(_ dt: Double) {
        stats.record(dt)
        let step = min(dt, 0.1)
        time += step
        press.advance(step)
        if fade > 0 { fade = max(0, fade - step / motion.fadeSeconds) }

        title.position.y = 4.5 + 0.3 * Float(sin(time * 1.4))
        title.orientation = simd_quatf(angle: .pi + 0.12 * Float(sin(time * 0.9)), axis: [0, 1, 0])

        let s = Float(press.value)
        let bulge = 1 + Float(motion.pressBulge) * s
        button.scale = SIMD3(bulge, 1 - Float(motion.pressSquash) * s, bulge)
        let alpha = Float(1 - 0.6 * fade)
        setAlpha(alpha)

        let remaining = max(0, 120 - Int(time) % 121)
        let text = String(format: "%d:%02d", remaining / 60, remaining % 60)
        if text != clockText {
            clockText = text
            clock = replaceText(clock, text, height: 0.11, depth: 0.03, rgb: 0xFFE8A3, fromTop: 0.69)
        }
        project()
    }

    private var lastAlpha: Float = 1
    private func setAlpha(_ alpha: Float) {
        guard alpha != lastAlpha else { return }
        lastAlpha = alpha
        buttonMaterial.blending = alpha < 1 ? .transparent(opacity: .init(floatLiteral: alpha)) : .opaque
        labelMaterial.blending = buttonMaterial.blending
        button.model?.materials = [buttonMaterial]
        for case let model as ModelEntity in buttonLabel.children { model.model?.materials = [labelMaterial] }
    }

    // MARK: input and projection

    /// A touch on the view: our own hit-test against the 3D UI. True when the UI took it.
    @discardableResult
    func tap(at point: CGPoint) -> Bool {
        let (origin, dir) = ray(point)
        guard hit(button, origin: origin, dir: dir) else { return false }
        pressButton()
        return true
    }

    /// The button's action — reached by a tap on the 3D button or through the accessibility overlay.
    func pressButton() {
        if reduceMotion { fade = 1 } else { press.kick(motion.pressKick) }
        goals = (goals + 1) % 10
        score = replaceText(score, "\(goals) : 0", height: 0.2, depth: 0.05, rgb: 0xFFFFFF, fromTop: 0.82)
    }

    private var aspect: Float { Float(viewSize.width / max(viewSize.height, 1)) }

    private func ray(_ p: CGPoint) -> (SIMD3<Float>, SIMD3<Float>) {
        let ndcX = Float(2 * p.x / viewSize.width - 1)
        let ndcY = Float(1 - 2 * p.y / viewSize.height)
        let t = tan(fovDegrees / 2 * .pi / 180)
        let dirView = SIMD3<Float>(ndcX * t * aspect, ndcY * t, -1)
        let world = camera.transformMatrix(relativeTo: nil)
        let dir = simd_make_float3(world * SIMD4(dirView, 0))
        let origin = simd_make_float3(world.columns.3)
        return (origin, dir)
    }

    /// Ray against the entity's own-space bounds (the same slab test as Android's Node.hit).
    private func hit(_ e: Entity, origin: SIMD3<Float>, dir: SIMD3<Float>) -> Bool {
        let bounds = e.visualBounds(relativeTo: e)
        let o = e.convert(position: origin, from: nil)
        let d = e.convert(direction: dir, from: nil)
        var tMin: Float = 0, tMax = Float.greatestFiniteMagnitude
        for a in 0..<3 {
            if abs(d[a]) < 1e-8 {
                if o[a] < bounds.min[a] || o[a] > bounds.max[a] { return false }
            } else {
                let t1 = (bounds.min[a] - o[a]) / d[a], t2 = (bounds.max[a] - o[a]) / d[a]
                tMin = max(tMin, min(t1, t2)); tMax = min(tMax, max(t1, t2))
                if tMin > tMax { return false }
            }
        }
        return true
    }

    /// Projects the button's bounds to the screen for the accessibility overlay.
    private func project() {
        let b = button.visualBounds(relativeTo: button)
        let t = tan(fovDegrees / 2 * .pi / 180)
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for x in [b.min.x, b.max.x] { for y in [b.min.y, b.max.y] { for z in [b.min.z, b.max.z] {
            let world = button.convert(position: SIMD3(x, y, z), to: nil)
            let v = camera.convert(position: world, from: nil)
            guard v.z < 0 else { continue }
            let nx = (v.x / -v.z) / (t * aspect), ny = (v.y / -v.z) / t
            let sx = CGFloat((nx + 1) / 2) * viewSize.width, sy = CGFloat((1 - ny) / 2) * viewSize.height
            minX = min(minX, sx); maxX = max(maxX, sx); minY = min(minY, sy); maxY = max(maxY, sy)
        } } }
        let rect = minX < maxX ? CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral : nil
        if rect != overlay.buttonRect { overlay.buttonRect = rect }
    }
}
