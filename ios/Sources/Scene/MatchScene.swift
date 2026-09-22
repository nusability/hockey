import Observation
import QuartzCore
import RealityKit
import SmashCore
import UIKit
import os

/// What the SwiftUI layer reads from the scene: the pause button's projected rectangle, for the
/// accessibility overlay (ADR 0005), and whether the match is paused.
@MainActor @Observable
final class MatchOverlay {
    var pauseRect: CGRect?
    var paused = false
}

/// The match on screen (SMASH-8, SMASH-9): a `Match` from the core, drawn in its world, with the
/// camera and the slow motion of §8.6, the finger of §5.3 and a minimal HUD. One RealityKit scene,
/// one camera, one clock — the scene's update event (ADR 0005). The twin of Android's MatchScene.
@MainActor
final class MatchScene {
    let root = Entity()
    let overlay = MatchOverlay()
    var reduceMotion = false

    private var plan: MatchPlan
    private var seed: UInt64
    private var match: Match
    private var snapshot: MatchSnapshot
    private var orbitPeriod: Double
    private let motion: MotionTokens
    private let materials: Materials
    private let stats = FrameStats()
    private let latency = InputLatency()
    private let log = Logger(subsystem: "in.nann.smashhockey", category: "match")

    private var stage: WorldStage?
    private var actors: Actors?
    private var confetti: Confetti?
    private var hud: Hud?
    /// The camera, with the HUD hanging from it (ADR 0005); it never shakes — the world does.
    private let camera = PerspectiveCamera()
    /// The world and everything in it: what the camera shake moves.
    private let world = Entity()
    private var director = Director()

    private var viewSize = CGSize(width: 1, height: 1)
    private var safeTop = 0.0, safeBottom = 0.0
    /// Ticks owed but not run, as a fraction of one — how far past the snapshot to draw (§4.2).
    private var phase = 0.0
    private var clock = 0.0
    private var celebrating: Int?
    private var endedFor = 0.0
    private var loading = false

    init(plan: MatchPlan, seed: UInt64) throws {
        self.plan = plan
        self.seed = seed
        motion = try MotionTokens.load()
        materials = try Materials()
        try TextMesh.registerFont()
        (match, orbitPeriod) = plan.start(seed: seed)
        snapshot = match.snapshot
        camera.camera.fieldOfViewOrientation = .vertical
        camera.camera.near = Float(Presentation.Camera.near)
        camera.camera.far = Float(Presentation.Camera.far)
        root.addChild(camera)
        root.addChild(world)
    }

    // MARK: building

    /// Loads the plan's world and builds everything in it. Nothing is drawn until it is ready.
    func build() async throws {
        loading = true
        defer { loading = false }
        let stage = try await WorldStage.load(plan.world, materials: materials)
        let actors = try Actors(first: snapshot, colours: plan.colours(seed: seed), sport: plan.world.sport,
                                orbitPeriod: orbitPeriod, materials: materials, look: stage.look)
        let confetti = try Confetti(materials: materials, look: stage.look)
        let hud = Hud(motion: motion, codes: plan.codes(seed: seed), colours: plan.colours(seed: seed))
        [self.stage?.root, self.actors?.root, self.confetti?.root, self.hud?.root].forEach { $0?.removeFromParent() }
        world.addChild(stage.root)
        world.addChild(actors.root)
        world.addChild(confetti.root)
        camera.addChild(hud.root)
        (self.stage, self.actors, self.confetti, self.hud) = (stage, actors, confetti, hud)
        hud.resize(width: viewSize.width, height: viewSize.height, safeTop: safeTop, safeBottom: safeBottom)
        hud.show(snapshot, drillGoals: drillGoals)
        log.info("world \(self.plan.world.rawValue, privacy: .public) seed \(self.seed)")
    }

    private var drillGoals: Int? { if case .drill(let d) = plan { d.goals } else { nil } }

    func resize(_ size: CGSize, safeTop top: Double, safeBottom bottom: Double) {
        viewSize = size
        safeTop = top
        safeBottom = bottom
        hud?.resize(width: size.width, height: size.height, safeTop: top, safeBottom: bottom)
    }

    // MARK: the frame — the one clock

    /// Called from the scene's update event, once per rendered frame, with its real delta.
    func update(_ dt: Double) {
        stats.record(dt)
        let real = min(max(dt, 0), Tuning.Time.maxRealGap)
        clock += real
        guard let actors, let hud else { return }

        if !overlay.paused {
            director.reduceMotion = reduceMotion
            director.update(realSeconds: real, directorInput())
            let scale = director.timeScale
            let ran = match.advance(realSeconds: dt, timeScale: scale)
            phase = min(max(phase + real * scale / Tuning.Time.tickSeconds - Double(ran), 0), 0.999)
            if ran > 0 {
                latency.ticked(now: CACurrentMediaTime())
                snapshot = match.snapshot
                for e in match.drainEvents() { handle(e) }
                hud.show(snapshot, drillGoals: drillGoals)
            }
        }
        if snapshot.state != .goal { celebrating = nil }
        actors.update(snapshot, ahead: overlay.paused ? 0 : phase * Tuning.Time.tickSeconds,
                      celebrating: celebrating, clock: clock)
        confetti?.advance(real)
        hud.advance(real, bannerSeconds: 1.6)
        let pose = director.pose
        camera.look(at: SIMD3<Float>(pose.target), from: SIMD3<Float>(pose.eye), relativeTo: nil)
        camera.camera.fieldOfViewInDegrees = Float(pose.fov)
        world.position = -SIMD3<Float>(director.shakeOffset)
        // The HUD keeps its size on screen while the field of view breathes: across only, not in depth.
        let base = tan(Presentation.Camera.fov / 2 * .pi / 180)
        let zoom = Float(tan(pose.fov / 2 * .pi / 180) / base)
        hud.root.scale = SIMD3(zoom, zoom, 1)
        project()
        afterTheEnd(real)
    }

    private func directorInput() -> DirectorInput {
        let b = snapshot.ball
        return DirectorInput(state: match.state, shotAboutToScore: match.shotAboutToScore,
                             lastShotDistance: match.lastShotDistance, ball: SIMD2(b.x, b.z),
                             ballVelocity: SIMD2(b.vx, b.vz), carrierTeam: b.carrier.map { snapshot.players[$0].team })
    }

    /// What the match emitted: the camera, the confetti and the banners react.
    private func handle(_ e: MatchEvent) {
        switch e {
        case .goal(let team, _, _, let ownGoal):
            let goalZ = (team == 0 ? 1.0 : -1.0) * Tuning.Pitch.goalLineZ
            director.goalScored(goalZ: goalZ, ballX: snapshot.ball.x, lastShotDistance: match.lastShotDistance)
            confetti?.burst(goalZ: Float(goalZ))
            celebrating = team
            let ours = team == 0
            banner(ours ? "event.goal" : "event.goalAgainst", colour: ours ? Presentation.Aim.shot : Presentation.Hud.text)
            log.info("goal team \(team) own \(ownGoal) score \(self.snapshot.score[0])-\(self.snapshot.score[1])")
        case .post:
            director.knock(Presentation.Camera.Shake.post)
        case .board(let speed):
            director.knock(Presentation.Camera.Shake.board * min(speed / 12, 1))
        case .drillInterrupted(let why):
            let key = switch why {
            case .saved: "event.saved"
            case .stolen: "event.stolen"
            case .wrongNet: "event.wrongNet"
            case .noAssist: "event.passFirst"
            case .deadBall: "event.reset"
            }
            banner(key, colour: Presentation.Hud.clock)
        case .end(let result):
            let key = switch result { case .won: "result.win"; case .lost: "result.loss"; case .drawn: "result.draw" }
            banner(key, colour: Presentation.Hud.clock)
            log.info("end \(result.rawValue, privacy: .public)")
        case .shot(let by, let kind):
            log.info("shot by \(by) \(kind.rawValue, privacy: .public)")
        default:
            break
        }
    }

    private func banner(_ key: String, colour: UInt32) {
        hud?.raise(String(localized: String.LocalizationValue(key)), colour: colour, reduceMotion: reduceMotion)
    }

    /// A finished match or drill: the demo moves to the next world; anything else waits for a tap.
    private func afterTheEnd(_ dt: Double) {
        guard snapshot.state == .ended else { endedFor = 0; return }
        endedFor += dt
        if case .demo(let n) = plan, endedFor > 4, !loading { restart(.demo(round: n + 1)) }
    }

    /// The next match or the retry — one tap, no interstitial (principle A2).
    private func restart(_ next: MatchPlan) {
        let worldChanges = next.world != plan.world
        plan = next
        seed = MatchPlan.seed()
        (match, orbitPeriod) = next.start(seed: seed)
        snapshot = match.snapshot
        director = Director()
        phase = 0
        endedFor = 0
        hud?.raise(nil, reduceMotion: reduceMotion)
        if worldChanges {
            Task { try? await build() }
        } else if let stage {
            actors?.root.removeFromParent()
            actors = try? Actors(first: snapshot, colours: plan.colours(seed: seed), sport: plan.world.sport,
                                 orbitPeriod: orbitPeriod, materials: materials, look: stage.look)
            if let a = actors { world.addChild(a.root) }
            hud?.show(snapshot, drillGoals: drillGoals)
        }
    }

    // MARK: the finger (§5.3)

    /// A touch landed at `point`: true when a HUD control took it — it never reaches the match.
    func touchIsUI(at point: CGPoint) -> Bool {
        guard let hud else { return false }
        let (origin, dir) = ray(point)
        if hit(hud.pauseButton, origin: origin, dir: dir) {
            togglePause()
            return true
        }
        if overlay.paused { return true }
        if snapshot.state == .ended, !isDemo {
            restart(plan)                                   // a retry is one tap (§10, A2)
            return true
        }
        return false
    }

    private var isDemo: Bool { if case .demo = plan { true } else { false } }

    /// The finger went down on the pitch (the first one) or the last one lifted (§5.3). Handed to
    /// the match at once; it applies at the next tick boundary (§4.1).
    func finger(down: Bool, touchTime: Double) {
        match.hold(down)
        latency.edge(down: down, touch: touchTime, handled: CACurrentMediaTime())
        if !down { log.info("lift aim \(String(describing: self.snapshot.aim), privacy: .public)") }
    }

    func togglePause() { setPaused(!overlay.paused) }

    /// Pause (the button, or the app leaving the foreground, §8.7): the match stops, the UI doesn't.
    func setPaused(_ on: Bool) {
        guard overlay.paused != on else { return }
        overlay.paused = on
        hud?.setPaused(on)
    }

    // MARK: hit-testing and projection (our own, ADR 0005)

    private var aspect: Float { Float(viewSize.width / max(viewSize.height, 1)) }
    private var tanHalf: Float { tan(camera.camera.fieldOfViewInDegrees / 2 * .pi / 180) }

    private func ray(_ p: CGPoint) -> (SIMD3<Float>, SIMD3<Float>) {
        let ndcX = Float(2 * p.x / viewSize.width - 1), ndcY = Float(1 - 2 * p.y / viewSize.height)
        let world = camera.transformMatrix(relativeTo: nil)
        let dir = simd_make_float3(world * SIMD4(ndcX * tanHalf * aspect, ndcY * tanHalf, -1, 0))
        return (simd_make_float3(world.columns.3), dir)
    }

    private func hit(_ e: Entity, origin: SIMD3<Float>, dir: SIMD3<Float>) -> Bool {
        let b = e.visualBounds(relativeTo: e)
        let o = e.convert(position: origin, from: nil), d = e.convert(direction: dir, from: nil)
        var tMin: Float = 0, tMax = Float.greatestFiniteMagnitude
        for a in 0..<3 {
            if abs(d[a]) < 1e-8 {
                if o[a] < b.min[a] || o[a] > b.max[a] { return false }
            } else {
                let t1 = (b.min[a] - o[a]) / d[a], t2 = (b.max[a] - o[a]) / d[a]
                tMin = max(tMin, min(t1, t2)); tMax = min(tMax, max(t1, t2))
                if tMin > tMax { return false }
            }
        }
        return true
    }

    /// The pause button's rectangle on screen, for the accessibility overlay.
    private func project() {
        guard let button = hud?.pauseButton else { return }
        let b = button.visualBounds(relativeTo: button)
        var lo = CGPoint(x: CGFloat.greatestFiniteMagnitude, y: .greatestFiniteMagnitude), hi = CGPoint(x: -lo.x, y: -lo.y)
        for x in [b.min.x, b.max.x] { for y in [b.min.y, b.max.y] { for z in [b.min.z, b.max.z] {
            let v = camera.convert(position: button.convert(position: SIMD3(x, y, z), to: nil), from: nil)
            guard v.z < 0 else { continue }
            let sx = CGFloat(((v.x / -v.z) / (tanHalf * aspect) + 1) / 2) * viewSize.width
            let sy = CGFloat((1 - (v.y / -v.z) / tanHalf) / 2) * viewSize.height
            lo = CGPoint(x: min(lo.x, sx), y: min(lo.y, sy)); hi = CGPoint(x: max(hi.x, sx), y: max(hi.y, sy))
        } } }
        let rect = lo.x < hi.x ? CGRect(x: lo.x, y: lo.y, width: hi.x - lo.x, height: hi.y - lo.y).integral : nil
        if rect != overlay.pauseRect { overlay.pauseRect = rect }
    }
}
