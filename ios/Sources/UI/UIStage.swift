import Observation
import RealityKit
import UIKit

/// One accessibility element, projected from a 3D node for the SwiftUI overlay.
struct A11yNode: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String?
    let trait: Semantics.Trait
    let isEnabled: Bool
    let isSelected: Bool
    let frame: CGRect
}

/// What the overlay reads: the projected nodes of this frame. Written only when it changed.
@MainActor @Observable
final class SemanticsModel {
    var nodes: [A11yNode] = []
}

/// The 3D UI's stage: the camera rig, the HUD rig, every element's clock, our own ray hit-test
/// (ADR 0005 — synchronous in the touch handler), and the derived accessibility overlay. Screens
/// add elements; the stage updates, hit-tests and projects them. Nothing else drives UI motion.
@MainActor
final class UIStage {
    let root = Entity()
    let rig: CameraRig
    let hud: ScreenFrame
    let motion: MotionTokens
    let semanticsModel = SemanticsModel()
    var reduceMotion = false
    private(set) var viewSize: CGSize
    private(set) var insets: UIEdgeInsets
    private(set) var time = 0.0
    private var elements: [UIElement] = []
    private var semantic: [Semantic] = []
    private var interactive: [Interactive] = []
    private var active: Interactive?
    /// A card standing in front of the screen (§16.6): while one is up, only what hangs under it
    /// takes fingers or reaches VoiceOver. Everything behind is inert, not merely disabled.
    private var modalRoot: Entity?
    private var timers: [(at: Double, run: () -> Void)] = []

    init(pose: CameraPose, viewSize: CGSize, insets: UIEdgeInsets, motion: MotionTokens) {
        self.motion = motion
        self.viewSize = viewSize
        self.insets = insets
        rig = CameraRig(pose, motion: motion)
        hud = ScreenFrame(fovDegrees: CameraRig.menuFov, viewSize: viewSize, insets: insets)
        root.addChild(rig.camera)
        rig.camera.addChild(hud.entity)
    }

    func resize(_ size: CGSize) { viewSize = size }

    /// Puts a card in front of everything: nothing outside `root` is touchable or findable until
    /// this is called again with nil. A finger held on something behind is let go without firing.
    func setModal(_ root: Entity?) {
        modalRoot = root
        if let a = active, !reachable(a.entity) { active = nil }
    }

    /// Whether `e` is reachable at all — always, unless a card stands in front of it.
    private func reachable(_ e: Entity) -> Bool {
        guard let root = modalRoot else { return true }
        var node: Entity? = e
        while let n = node {
            if n === root { return true }
            node = n.parent
        }
        return false
    }

    /// A world-standing frame for a screen seen from `pose`.
    func frame(at pose: CameraPose) -> ScreenFrame {
        let f = ScreenFrame(fovDegrees: CameraRig.menuFov, viewSize: viewSize, insets: insets)
        f.stand(before: rig.transform(at: pose), in: root)
        return f
    }

    /// Registers `element` and hangs it under `parent`. The stage drives it from now on.
    @discardableResult
    func add<E: UIElement>(_ element: E, to parent: Entity) -> E {
        parent.addChild(element.entity)
        elements.append(element)
        if let s = element as? Semantic { semantic.append(s) }
        if let i = element as? Interactive { interactive.append(i) }
        return element
    }

    /// Runs `body` after `seconds` of stage time — for choreography, never for input.
    func after(_ seconds: Double, _ body: @escaping () -> Void) {
        timers.append((time + seconds, body))
    }

    // MARK: frame

    func update(_ dt: Double) {
        time += dt
        if !timers.isEmpty {
            let due = timers.filter { $0.at <= time }
            timers.removeAll { $0.at <= time }
            for t in due { t.run() }
        }
        rig.update(dt, reduceMotion: reduceMotion)
        hud.zoom(fovDegrees: rig.fovDegrees)
        let ctx = UIContext(motion: motion, reduceMotion: reduceMotion, time: time)
        for e in elements { e.update(dt, ctx) }
        project()
    }

    // MARK: touches

    /// A finger went down at `point`: true when a present interactive element took it.
    @discardableResult
    func touchDown(at point: CGPoint) -> Bool {
        let ray = self.ray(point)
        active = pick(ray)
        active?.touchDown(ray.local(to: active!.boundsEntity))
        return active != nil
    }

    /// Whether a finger at `point` would land on a present interactive element.
    func wouldTake(_ point: CGPoint) -> Bool { pick(ray(point)) != nil }

    /// Forgets every element under `root` (a screen leaving for good) and takes `root` out of the
    /// scene. A finger on one of them is let go without firing.
    func remove(under root: Entity) {
        func inside(_ e: Entity) -> Bool {
            var node: Entity? = e
            while let n = node { if n === root { return true }; node = n.parent }
            return false
        }
        elements.removeAll { inside($0.entity) }
        semantic.removeAll { inside($0.entity) }
        interactive.removeAll { inside($0.entity) }
        if let a = active, inside(a.entity) { active = nil }
        if let m = modalRoot, inside(m) { modalRoot = nil }
        root.removeFromParent()
    }

    func touchMoved(to point: CGPoint) {
        guard let a = active else { return }
        a.touchMoved(ray(point).local(to: a.boundsEntity))
    }

    func touchUp(at point: CGPoint) {
        guard let a = active else { return }
        active = nil
        let local = ray(point).local(to: a.boundsEntity)
        a.touchUp(local, inside: a.isPresent && local.hit(a.bounds) != nil)
    }

    /// The nearest present interactive element under the ray. Disabled ones are hit too, so
    /// they can say no.
    private func pick(_ ray: TouchRay) -> Interactive? {
        var best: (Interactive, Float)?
        for i in interactive where i.isPresent && i.takesTouches && reachable(i.entity) {
            let local = ray.local(to: i.boundsEntity)
            guard let t = local.hit(i.bounds) else { continue }
            // Compare in world distance: local t is scaled by the node's scale.
            let world = simd_distance(ray.origin, i.boundsEntity.convert(position: local.origin + local.direction * t, to: nil))
            if best == nil || world < best!.1 { best = (i, world) }
        }
        return best?.0
    }

    private func ray(_ p: CGPoint) -> TouchRay {
        let aspect = Float(viewSize.width / max(viewSize.height, 1))
        let ndcX = Float(2 * p.x / viewSize.width - 1)
        let ndcY = Float(1 - 2 * p.y / viewSize.height)
        let t = tan(rig.fovDegrees / 2 * .pi / 180)
        let dirView = SIMD3<Float>(ndcX * t * aspect, ndcY * t, -1)
        let world = rig.camera.transformMatrix(relativeTo: nil)
        return TouchRay(origin: simd_make_float3(world.columns.3), direction: simd_make_float3(world * SIMD4(dirView, 0)))
    }

    // MARK: accessibility

    /// VoiceOver's activation of node `id` — the same action a tap fires.
    func activate(_ id: String) {
        interactive.first { $0.semantics.id == id && $0.isPresent && reachable($0.entity) }?.activate()
    }

    func adjust(_ id: String, by steps: Int) {
        interactive.first { $0.semantics.id == id && $0.isPresent && reachable($0.entity) }?.adjust(by: steps)
    }

    /// Projects every present semantic node's box to the screen: the overlay is output, like pixels.
    private func project() {
        let view = rig.camera.transformMatrix(relativeTo: nil).inverse
        let aspect = Float(viewSize.width / max(viewSize.height, 1))
        let t = tan(rig.fovDegrees / 2 * .pi / 180)
        var nodes: [A11yNode] = []
        for s in semantic where s.isPresent && reachable(s.entity) {
            let b = s.bounds
            let toView = view * s.boundsEntity.transformMatrix(relativeTo: nil)
            var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
            var behind = false
            for x in [b.min.x, b.max.x] { for y in [b.min.y, b.max.y] { for z in [b.min.z, b.max.z] {
                let v = toView * SIMD4(x, y, z, 1)
                guard v.z < 0 else { behind = true; continue }
                let nx = (v.x / -v.z) / (t * aspect), ny = (v.y / -v.z) / t
                let sx = CGFloat((nx + 1) / 2) * viewSize.width, sy = CGFloat((1 - ny) / 2) * viewSize.height
                minX = min(minX, sx); maxX = max(maxX, sx); minY = min(minY, sy); maxY = max(maxY, sy)
            } } }
            guard !behind, minX < maxX else { continue }
            let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
            guard rect.intersects(CGRect(origin: .zero, size: viewSize)) else { continue }
            let sem = s.semantics
            nodes.append(A11yNode(id: sem.id, label: sem.label, value: sem.value, trait: sem.trait,
                                  isEnabled: sem.isEnabled, isSelected: sem.isSelected, frame: rect))
        }
        if nodes != semanticsModel.nodes { semanticsModel.nodes = nodes }
    }
}
