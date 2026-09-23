import Foundation
import QuartzCore
import RealityKit
import SmashCore
import os

/// The pitch and whatever match is on it (spec §8, §9): a `Match` from the core, drawn in its
/// world — the players, the ball and its trail, the aim arrow, the confetti, the pops and the nets —
/// with the director's camera and slow motion (§8.6). The demo behind the menus and the player's own
/// matches are the same thing here; the game decides which one runs. What the match sets off (core
/// `MatchCues`, §8.8) is split here: what is seen happens on the pitch, the banners, sounds and
/// haptics go to the game. It never draws a HUD: the screens do. The twin of Android's Pitch.kt.
@MainActor
final class Pitch {
    /// The world and everything in it: what the camera shake moves.
    let root = Entity()
    var reduceMotion = false
    /// The view's width over its height, for the play camera's fit.
    var aspect = 0.46 { didSet { director.aspect = aspect } }
    /// A paused match stops; the camera and the UI don't (§8.7).
    var paused = false
    /// What the match emitted this frame, after the pitch itself has reacted.
    var onEvent: ((MatchEvent) -> Void)?
    /// The banners, sounds and haptics the match set off (§8.8, §16.4).
    var onCue: ((Cue) -> Void)?

    private(set) var plan: MatchPlan?
    private(set) var kickoff: Kickoff?
    private(set) var snapshot: MatchSnapshot?
    /// The running match — kept apart from `kickoff` so it is mutated in place, never copied.
    private var match: Match?
    /// Real seconds since the match ended; 0 while it runs.
    private(set) var endedFor = 0.0
    private let materials: Materials
    private let feel: FeelMaterials.Set
    private var world: WorldStage?
    private var loadingWorld: World?
    private var actors: Actors?
    private var confetti: Confetti?
    private let pops: Pops
    private let nets: NetRipple
    private var cues = MatchCues(MatchCues.Params(), drill: false, audible: false)
    private var director = Director()
    private let stats = FrameStats()
    private let latency = InputLatency()
    private let log = Logger(subsystem: "in.nann.smashhockey", category: "match")
    private var phase = 0.0
    private var clock = 0.0
    private var celebrating: Int?
    /// Bumped by every `start`, so a world that finishes loading for an older one is dropped.
    private var generation = 0

    init(materials: Materials, feel: FeelMaterials.Set) throws {
        self.materials = materials
        self.feel = feel
        pops = try Pops()
        nets = try NetRipple()
        root.addChild(pops.root)
        root.addChild(nets.root)
    }

    /// Puts `kickoff` on the pitch — at once when its world is the one standing, else once that
    /// world has loaded (the old one keeps playing until then).
    func start(_ plan: MatchPlan, _ kickoff: Kickoff) {
        generation += 1
        let mine = generation
        if let world, world.world == kickoff.world {
            loadingWorld = nil          // a load still under way is dropped (its generation is stale)
            place(plan, kickoff, in: world)
            return
        }
        loadingWorld = kickoff.world
        Task { [weak self] in
            guard let self else { return }
            do {
                let stage = try await WorldStage.load(kickoff.world, materials: self.materials)
                guard mine == self.generation else { return }
                self.world?.root.removeFromParent()
                self.world = stage
                self.root.addChild(stage.root)
                self.loadingWorld = nil
                self.place(plan, kickoff, in: stage)
            } catch {
                self.log.error("world \(kickoff.world.rawValue, privacy: .public) failed: \(error, privacy: .public)")
            }
        }
    }

    /// A world is on its way; the one standing still plays.
    var isLoading: Bool { loadingWorld != nil }

    /// The world standing now (or loading next).
    var worldShown: World? { loadingWorld ?? world?.world }

    /// §8.6's time scale — what a match sound's rate follows (§8.8).
    var timeScale: Double { paused ? 0 : director.timeScale }

    /// What the stadium reads this frame (§8.8): the player's match as it stands, and which goal a
    /// shot about to score (§8.6) is heading for. Nil behind the menus — the demo has no crowd (§9).
    var atmosphere: (snapshot: MatchSnapshot, danger: SmashCore.Atmosphere.Danger?)? {
        guard let match, let snapshot, let plan, !plan.isDemo else { return nil }
        let danger: SmashCore.Atmosphere.Danger? = match.shotAboutToScore ? (snapshot.ball.vz > 0 ? .theirs : .ours) : nil
        return (snapshot, danger)
    }

    private func place(_ plan: MatchPlan, _ kickoff: Kickoff, in stage: WorldStage) {
        do {
            let first = kickoff.match.snapshot
            let actors = try Actors(first: first, colours: kickoff.colours, sport: kickoff.world.sport,
                                    orbitPeriod: kickoff.orbitPeriod, materials: materials, feel: feel, look: stage.look)
            let confetti = try Confetti(materials: materials, look: stage.look)
            self.actors?.root.removeFromParent()
            self.confetti?.root.removeFromParent()
            root.addChild(actors.root)
            root.addChild(confetti.root)
            (self.actors, self.confetti) = (actors, confetti)
            self.plan = plan
            self.kickoff = kickoff
            match = kickoff.match
            snapshot = first
            director = Director()
            director.aspect = aspect
            phase = 0
            endedFor = 0
            celebrating = nil
            paused = false
            cues = MatchCues(Feedback.params, drill: plan.drill != nil, audible: !plan.isDemo)
            if let names = kickoff.names { for c in cues.intro(home: names[0], away: names[1]) { onCue?(c) } }
            log.info("kickoff \(String(describing: plan), privacy: .public) in \(kickoff.world.rawValue, privacy: .public)")
        } catch {
            log.error("the pitch failed to build: \(error, privacy: .public)")
        }
    }

    /// Whether a match of `plan` is on the pitch and running.
    func isPlaying(_ plan: MatchPlan) -> Bool { self.plan == plan && snapshot != nil }

    // MARK: the frame

    func update(_ dt: Double) {
        stats.record(dt)
        let real = min(max(dt, 0), Tuning.Time.maxRealGap)
        clock += real
        pops.advance(real)
        nets.advance(real)
        guard match != nil, let actors, var snapshot else { return }
        if !paused {
            director.reduceMotion = reduceMotion
            director.update(realSeconds: real, input(match!, snapshot))
            let scale = director.timeScale
            let ran = match!.advance(realSeconds: dt, timeScale: scale)
            phase = min(max(phase + real * scale / Tuning.Time.tickSeconds - Double(ran), 0), 0.999)
            if ran > 0 {
                latency.ticked(now: CACurrentMediaTime())
                snapshot = match!.snapshot
                self.snapshot = snapshot
                let events = match!.drainEvents()
                for e in events { handle(e, snapshot) }
                for c in cues.frame(snapshot) { perform(c) }
            }
        }
        if snapshot.state != .goal { celebrating = nil }
        actors.update(snapshot, ahead: paused ? 0 : phase * Tuning.Time.tickSeconds, dt: paused ? 0 : real,
                      celebrating: celebrating, clock: clock)
        confetti?.advance(real)
        root.position = -SIMD3<Float>(director.shakeOffset)
        if snapshot.state == .ended { endedFor += real } else { endedFor = 0 }
    }

    /// The director's camera: its pose and vertical field of view.
    var pose: (CameraPose, Float) {
        let p = director.pose
        return (CameraPose(eye: SIMD3<Float>(p.eye), target: SIMD3<Float>(p.target)), Float(p.fov))
    }

    private func input(_ match: Match, _ s: MatchSnapshot) -> DirectorInput {
        let b = s.ball
        return DirectorInput(state: match.state, shotAboutToScore: match.shotAboutToScore,
                             lastShotDistance: match.lastShotDistance, ball: SIMD2(b.x, b.z),
                             ballVelocity: SIMD2(b.vx, b.vz), carrierTeam: b.carrier.map { s.players[$0].team })
    }

    /// The camera, the confetti, the net and the celebration react, then what the event sets off
    /// (§8.8); then the game hears of it.
    private func handle(_ e: MatchEvent, _ s: MatchSnapshot) {
        let match = self.match!
        switch e {
        case .goal(let team, _, _, let ownGoal):
            let goalZ = (team == 0 ? 1.0 : -1.0) * Tuning.Pitch.goalLineZ
            director.goalScored(goalZ: goalZ, ballX: s.ball.x, lastShotDistance: match.lastShotDistance)
            if let colours = kickoff?.colours[team] { try? confetti?.burst(goalZ: Float(goalZ), colours: colours) }
            nets.goal(goalZ: goalZ, x: s.ball.x)
            celebrating = team
            log.info("goal team \(team) own \(ownGoal) score \(s.score[0])-\(s.score[1])")
        case .end(let result):
            log.info("end \(result.rawValue, privacy: .public)")
        default:
            break
        }
        for c in cues.hear(e, s) { perform(c) }
        onEvent?(e)
    }

    private func perform(_ c: Cue) {
        switch c {
        case .shake(let amount): director.knock(amount)
        case .pop(let kind, let x, let z): pops.pop(kind, x: x, z: z)
        case .banner, .sound, .haptic: onCue?(c)
        }
    }

    // MARK: the finger (§5.3)

    /// The finger went down on the pitch (the first one) or the last one lifted. Handed to the
    /// match at once; it applies at the next tick boundary (§4.1).
    func hold(_ down: Bool, touchTime: Double) {
        guard match != nil else { return }
        match!.hold(down)
        latency.edge(down: down, touch: touchTime, handled: CACurrentMediaTime())
    }
}
