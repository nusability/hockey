import Foundation
import SmashCore
import simd

/// Where the camera is: its eye, what it looks at, and its vertical field of view (degrees).
struct DirectorPose: Equatable {
    var eye: SIMD3<Double>
    var target: SIMD3<Double>
    var fov: Double

    static func mix(_ a: DirectorPose, _ b: DirectorPose, _ w: Double) -> DirectorPose {
        DirectorPose(eye: a.eye + (b.eye - a.eye) * w, target: a.target + (b.target - a.target) * w,
                   fov: a.fov + (b.fov - a.fov) * w)
    }
}

/// What the director reads from the match each frame (spec §8.6 queries, and where the ball is).
struct DirectorInput {
    var state: MatchState
    var shotAboutToScore: Bool
    var lastShotDistance: Double?
    var ball: SIMD2<Double>          // (x, z)
    var ballVelocity: SIMD2<Double>
    /// The team carrying the ball, if anyone does.
    var carrierTeam: Int?
}

/// Presentation time and the camera (spec §8.6; the twin of Android's Director.kt). The director
/// sets the time scale — how many ticks a real second holds — and never touches what a tick does
/// (§4.2). It runs on real time, so the camera and the UI move at full speed through slow motion.
struct Director {
    typealias S = Tuning.SlowMotion
    typealias P = Presentation.Camera

    private(set) var timeScale = 1.0
    private(set) var pose: DirectorPose
    var reduceMotion = false

    // §8.6 — the goal's slow motion runs on real seconds since the goal.
    private var goalClock: Double?
    private var goalIsLong = false
    private var goal: (z: Double, side: Double, x: Double)?

    // The play camera's focus and lead, and the dramatic cameras' blend.
    private var focus: SIMD2<Double>
    private var leadDirection = 1.0
    private var weight = 0.0
    private var drama: DirectorPose
    private var shake = 0.0
    private var shakeClock = 0.0

    init() {
        focus = SIMD2(0, 0)
        let start = Director.playPose(focus: SIMD2(0, 0))
        pose = start
        drama = start
    }

    /// A goal was scored in the net on goal line `goalZ` (§8.5).
    mutating func goalScored(goalZ: Double, ballX: Double, lastShotDistance: Double?) {
        goalClock = 0
        goalIsLong = (lastShotDistance ?? 0) > S.longShot
        goal = (goalZ, ballX >= 0 ? 1 : -1, min(max(ballX, -1.5), 1.5))
    }

    /// The ball rang a post, or smacked the boards (a board hit, §6.2).
    mutating func knock(_ amplitude: Double) {
        guard !reduceMotion else { return }
        shake = max(shake, amplitude)
        shakeClock = 0
    }

    /// One frame of real time: the time scale for the ticks to come, and the camera.
    mutating func update(realSeconds dt: Double, _ m: DirectorInput) {
        // §8.6 — the time scale.
        var target = 1.0
        var rate = S.easeRate
        var mode = Mode.play
        if var t = goalClock {
            if m.state != .goal {
                goalClock = nil
                timeScale = max(timeScale, S.leaveGoalMin)       // leaving a goal
            } else {
                t += dt
                goalClock = t
                mode = .goal(t)
                rate = S.goalEaseRate
                if !goalIsLong {
                    let back = min(max((t - S.goalHold) / S.goalEaseBack, 0), 1)
                    target = t < S.goalHold ? S.goalScale : S.goalScale + (1 - S.goalScale) * back
                }
            }
        }
        if case .play = mode, m.shotAboutToScore {
            mode = .buildup
            if (m.lastShotDistance ?? 0) <= S.longShot { target = S.shotScale }
        }
        timeScale += (target - timeScale) * (1 - exp(-dt * rate))

        // The camera.
        followPlay(dt, m)
        let play = Director.playPose(focus: focus)
        var wanted = 0.0
        var blendRate = P.Buildup.rate
        switch mode {
        case .goal(let t):
            drama = goalPose(t, ball: m.ball)
            wanted = reduceMotion ? P.ReduceMotion.goalWeight : P.Goal.weight
            blendRate = P.Goal.rateIn
        case .buildup:
            drama = buildupPose(m)
            wanted = reduceMotion ? P.ReduceMotion.buildupWeight : P.Buildup.weight
        case .play:
            if goal != nil { blendRate = P.Goal.rateOut }
        }
        weight += (wanted - weight) * (1 - exp(-dt * blendRate))
        if case .play = mode, weight < 0.002 { goal = nil }
        pose = DirectorPose.mix(play, drama, weight)

        shakeClock += dt
        shake *= exp(-dt * P.Shake.decay)
    }

    /// The camera shake as an offset of the world — the camera and the HUD hanging from it stay
    /// steady, so the HUD never shakes (ADR 0005: the HUD is parented to the camera).
    var shakeOffset: SIMD3<Double> {
        guard shake > 0.002 else { return .zero }
        let w = 2 * Double.pi * P.Shake.frequency * shakeClock
        return SIMD3(sin(w), sin(w * 1.31 + 1.7), 0) * shake
    }

    private enum Mode { case play, buildup, goal(Double) }

    // MARK: the play camera

    private mutating func followPlay(_ dt: Double, _ m: DirectorInput) {
        typealias C = P.Play
        let heading: Double
        if let team = m.carrierTeam {
            heading = team == 0 ? 1 : -1
        } else if abs(m.ballVelocity.y) > 4 {
            heading = m.ballVelocity.y > 0 ? 1 : -1
        } else {
            heading = leadDirection >= 0 ? 1 : -1
        }
        leadDirection += (heading - leadDirection) * (1 - exp(-dt * C.leadRate))
        let want = SIMD2(min(max(m.ball.x * C.followX, -C.maxX), C.maxX),
                         min(max(m.ball.y + C.lead * leadDirection, C.minZ), C.maxZ))
        focus += (want - focus) * (1 - exp(-dt * C.rate))
    }

    static func playPose(focus f: SIMD2<Double>) -> DirectorPose {
        typealias C = P.Play
        return DirectorPose(eye: SIMD3(f.x, C.height, f.y - C.back), target: SIMD3(f.x, 0, f.y + C.lookAhead), fov: P.fov)
    }

    // MARK: the dramatic cameras

    /// A shot about to score: low behind the ball, looking along it at the net.
    private func buildupPose(_ m: DirectorInput) -> DirectorPose {
        typealias B = P.Buildup
        let outward = m.ballVelocity.y >= 0 ? 1.0 : -1.0
        let gz = outward * Tuning.Pitch.goalLineZ
        let t = abs(m.ballVelocity.y) > 1e-6 ? (gz - m.ball.y) / m.ballVelocity.y : 0
        let hitX = m.ball.x + m.ballVelocity.x * max(t, 0)
        return DirectorPose(eye: SIMD3(m.ball.x * 0.6, B.height, gz - outward * B.back),
                          target: SIMD3(hitX * 0.5, 0.6, gz), fov: B.fov)
    }

    /// The goal camera: beside the net on the side the ball came from, sweeping round behind it.
    private func goalPose(_ t: Double, ball: SIMD2<Double>) -> DirectorPose {
        typealias G = P.Goal
        guard let g = goal else { return drama }
        let outward = g.z >= 0 ? 1.0 : -1.0
        let run = reduceMotion ? 0 : min(t, G.sweepSeconds)
        let a = G.startAngle - run * G.sweep
        let eye = SIMD3(g.x + g.side * sin(a) * G.radius, G.height + run * G.rise, g.z + outward * cos(a) * G.radius)
        let target = SIMD3(ball.x * 0.4, G.lookHeight, g.z - outward * 0.5)
        return DirectorPose(eye: eye, target: target, fov: G.fov)
    }
}
