import Foundation
import os
import RealityKit
import UIKit

/// THROWAWAY (SMASH-5): the clickable motion sketch — Title → Season hub → Match HUD → Result,
/// and the coach's board — over the Oasis world, built only from the UI kit, for the owner to
/// judge the 3D UI's feel on a phone (AGENTS: "Click-dummy new UI first"). Every transition is a
/// camera swoop with things tumbling out and in; nothing cuts.
@MainActor
final class SketchScene {
    let root = Entity()
    let stage: UIStage
    private let world: OasisWorld
    private let stats = FrameStats()
    private let log = Logger(subsystem: "in.nann.smashhockey", category: "sketch")
    private var screens: [SketchScreenID: SketchScreen] = [:]
    private(set) var current: SketchScreenID?
    private var title: TitleScreen!
    private var hub: HubScreen!
    private var match: MatchScreen!
    private var result: ResultScreen!
    private var coach: CoachScreen!

    private init(stage: UIStage, world: OasisWorld) {
        self.stage = stage
        self.world = world
        root.addChild(world.root)
        root.addChild(stage.root)
    }

    static func make(viewSize: CGSize, insets: UIEdgeInsets) async throws -> SketchScene {
        let motion = try MotionTokens.load()
        try TextMesh.registerFont()
        let start = CameraPose(eye: [0, 30, -70], target: [0, 4, 0])
        let world = try await OasisWorld.load(eye: start.eye)
        let stage = UIStage(pose: start, viewSize: viewSize, insets: insets, motion: motion)
        let scene = SketchScene(stage: stage, world: world)
        scene.build()
        return scene
    }

    private func build() {
        let go: Go = { [weak self] id in self?.go(to: id) }
        title = TitleScreen(stage: stage, go: go)
        hub = HubScreen(stage: stage, go: go)
        match = MatchScreen(stage: stage, world: world.root, go: go)
        result = ResultScreen(stage: stage, go: go)
        coach = CoachScreen(stage: stage, go: go)
        screens = [.title: title, .hub: hub, .match: match, .result: result, .coach: coach]
        match.onFinished = { [weak self] home, away in
            guard let self else { return }
            self.result.setScore(home, away)
            self.hub.applyMatchday()
            self.go(to: .result)
        }
        self.go(to: .title)
    }

    /// The one way between screens: the old one's parts hop away, the camera swoops, the new
    /// one's parts tumble in as it arrives.
    func go(to id: SketchScreenID) {
        guard id != current, let next = screens[id] else { return }
        log.info("screen \(id.rawValue, privacy: .public) t=\(self.stage.time, format: .fixed(precision: 2))")
        if let c = current { screens[c]?.hide() }
        let first = current == nil
        current = id
        stage.rig.swoop(to: next.pose, roll: first ? 0 : 0.12)
        next.show(after: first ? 0.9 : 0.45)
    }

    /// The one clock (ADR 0005): the scene's update event, once per rendered frame.
    func update(_ dt: Double) {
        stats.record(dt)
        let step = min(dt, 0.1)
        if let c = current { screens[c]?.update(step) }
        stage.update(step)
        world.setFogEye(stage.rig.pose.eye)
    }

    // MARK: autoplay (-sketchAutoplay)

    /// Walks the whole sketch on a timer, through the same actions a finger fires, so every
    /// screen and mid-transition frame can be captured from the simulator.
    func startAutoplay() {
        let steps: [(Double, @MainActor (SketchScene) -> Void)] = [
            (4.0, { $0.tap($0.title.training) }),
            (5.0, { $0.tap($0.title.play) }),
            (10.0, { $0.tap($0.hub.playMatch) }),
            (19.0, { $0.tap($0.match.pause) }),
            (22.0, { $0.tap($0.match.resume) }),
            // the match finishes on its own (~45 s) and swoops to the result
            (52.0, { $0.tap($0.result.next) }),
            (58.0, { $0.tap($0.hub.back) }),
            (62.0, { $0.tap($0.title.coach) }),
            (65.0, { $0.drag($0.coach.sliders[0], to: 0.85) }),
            (66.0, { $0.drag($0.coach.sliders[1], to: 0.2) }),
            (67.0, { $0.drag($0.coach.sliders[2], to: 0.7) }),
            (69.0, { $0.tap($0.coach.back) }),
        ]
        for (t, run) in steps { stage.after(t) { [weak self] in if let self { run(self) } } }
    }

    /// A pretend finger on the button's projected rectangle: the overlay's frame, fed back through
    /// the stage's own ray hit-test — so autoplay proves projection and picking agree.
    private func tap(_ b: BlockButton) {
        guard let p = centre(of: b.semantics.id) else { return }
        stage.touchDown(at: p)
        stage.after(0.14) { [weak self] in self?.stage.touchUp(at: p) }
    }

    /// A pretend drag along a slider, from its value to `value`, in eight moves.
    private func drag(_ s: Slider3D, to value: Double) {
        guard let r = stage.semanticsModel.nodes.first(where: { $0.id == s.semantics.id })?.frame else {
            log.error("autoplay: \(s.semantics.id, privacy: .public) is not on screen"); return
        }
        // The rail spans the node's box minus 0.1 m of grab room each side (Slider3D.bounds).
        let pad = r.width * 0.1 / CGFloat(s.length + 0.2)
        func x(_ v: Double) -> CGFloat { r.minX + pad + (r.width - 2 * pad) * v }
        let y = r.midY + r.height * 0.2
        stage.touchDown(at: CGPoint(x: x(s.value), y: y))
        let from = s.value
        for i in 1...8 {
            let v = from + (value - from) * Double(i) / 8
            stage.after(Double(i) * 0.05) { [weak self] in self?.stage.touchMoved(to: CGPoint(x: x(v), y: y)) }
        }
        stage.after(0.5) { [weak self] in self?.stage.touchUp(at: CGPoint(x: x(value), y: y)) }
    }

    private func centre(of id: String) -> CGPoint? {
        guard let r = stage.semanticsModel.nodes.first(where: { $0.id == id })?.frame else {
            log.error("autoplay: \(id, privacy: .public) is not on screen")
            return nil
        }
        return CGPoint(x: r.midX, y: r.midY)
    }
}
