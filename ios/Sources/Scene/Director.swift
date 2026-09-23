import Foundation
import SmashCore
import simd

/// Where the camera is: its eye, what it looks at, and its vertical field of view (degrees).
struct DirectorPose: Equatable {
    var eye: SIMD3<Double>
    var target: SIMD3<Double>
    var fov: Double
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
///
/// Where the camera *stands* is the core's (`SmashCore.MatchCamera`), handed this file's numbers
/// from `presentation.toml`, so one test walks the ball over the whole pitch and pins the solve on
/// both platforms. What is left here is the time scale, the shake, and the app's end of the rig.
struct Director {
    typealias S = Tuning.SlowMotion
    typealias P = Presentation.Camera

    private(set) var timeScale = 1.0
    var reduceMotion = false
    /// The view's width over its height: the play camera fits the pitch's width to it.
    var aspect = 0.46

    // §8.6 — the goal's slow motion runs on real seconds since the goal.
    private var goalClock: Double?
    private var goalIsLong = false

    private var camera: MatchCamera
    private var shake = 0.0
    private var shakeClock = 0.0

    init() {
        camera = MatchCamera(Director.params, aspect: 0.46)
    }

    var pose: DirectorPose {
        let p = camera.pose
        return DirectorPose(eye: SIMD3(p.eyeX, p.eyeY, p.eyeZ), target: SIMD3(p.atX, p.atY, p.atZ), fov: p.fov)
    }

    /// A goal was scored in the net on goal line `goalZ` (§8.5).
    mutating func goalScored(goalZ: Double, ballX: Double, lastShotDistance: Double?) {
        goalClock = 0
        goalIsLong = (lastShotDistance ?? 0) > S.longShot
        camera.goalScored(goalZ: goalZ, ballX: ballX)
    }

    /// A shake's kick (§8.8: a goal, a post) of `amplitude` metres; Reduce Motion keeps a share of it.
    mutating func knock(_ amplitude: Double) {
        shake = max(shake, amplitude * (reduceMotion ? P.Shake.reduceMotion : 1))
    }

    /// One frame of real time: the time scale for the ticks to come, and the camera.
    mutating func update(realSeconds dt: Double, _ m: DirectorInput) {
        // §8.6 — the time scale.
        var target = 1.0
        var rate = S.easeRate
        var mode = MatchCamera.Mode.play
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
        if mode == .play, m.shotAboutToScore {
            mode = .buildup
            if (m.lastShotDistance ?? 0) <= S.longShot { target = S.shotScale }
        }
        timeScale += (target - timeScale) * (1 - exp(-dt * rate))

        camera.advance(dt, mode: mode,
                       ball: MatchCamera.Ball(x: m.ball.x, z: m.ball.y, vx: m.ballVelocity.x, vz: m.ballVelocity.y),
                       aspect: aspect, reduceMotion: reduceMotion)

        shakeClock += dt
        shake = max(0, shake - dt * P.Shake.decay)      // the prototype's linear fall-off
    }

    /// The camera shake as an offset of the world — the camera and the HUD hanging from it stay
    /// steady, so the HUD never shakes (ADR 0005: the HUD is parented to the camera). Up to half the
    /// kick either way, across and up, as the prototype's.
    var shakeOffset: SIMD3<Double> {
        guard shake > 0 else { return .zero }
        let w = 2 * Double.pi * P.Shake.frequency * shakeClock
        return SIMD3(sin(w), sin(w * 1.31 + 1.7), 0) * (shake / 2)
    }

    /// `presentation.toml [camera]` and the pitch numbers §8.6's shot window is measured in,
    /// handed to the core's solve. Declared once; nothing else reads these.
    static let params = MatchCamera.Params(
        height: P.Play.height, back: P.Play.back, look: P.Play.look, follow: P.Play.follow,
        minZ: P.Play.minZ, maxZ: P.Play.maxZ, rate: P.Play.rate, halfWidth: P.Play.halfWidth,
        fitNear: P.Play.fitNear, minFov: P.Play.minFov, maxFov: P.Play.maxFov,
        buildupHeight: P.Buildup.height, buildupBack: P.Buildup.back, buildupFov: P.Buildup.fov,
        buildupWeight: P.Buildup.weight, buildupRate: P.Buildup.rate,
        goalRadius: P.Goal.radius, goalHeight: P.Goal.height, goalRise: P.Goal.rise,
        goalStartAngle: P.Goal.startAngle, goalSweep: P.Goal.sweep, goalSweepSeconds: P.Goal.sweepSeconds,
        goalLookHeight: P.Goal.lookHeight, goalFov: P.Goal.fov, goalWeight: P.Goal.weight,
        goalRateIn: P.Goal.rateIn, goalRateOut: P.Goal.rateOut,
        reduceGoalWeight: P.ReduceMotion.goalWeight, reduceBuildupWeight: P.ReduceMotion.buildupWeight,
        goalLineZ: Tuning.Pitch.goalLineZ, postX: Tuning.Pitch.postX,
        postMargin: S.shotPostMargin, shotHorizon: S.shotHorizon)
}
