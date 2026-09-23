import Foundation

/// Where the match camera stands (spec §8.6) — the pure half of the director, so one test can walk
/// the ball over every square metre of the pitch and pin what the camera does. Its tunables are the
/// apps' presentation (`presentation.toml [camera]`), handed in by the caller; nothing here is on
/// the simulation path. The Android twin is `core/feel/MatchCamera.kt`.
public struct MatchCamera: Sendable {
    /// Eye, look-at target, vertical field of view (degrees).
    public struct Pose: Sendable, Equatable {
        public var eyeX: Double, eyeY: Double, eyeZ: Double
        public var atX: Double, atY: Double, atZ: Double
        public var fov: Double

        public init(eyeX: Double, eyeY: Double, eyeZ: Double, atX: Double, atY: Double, atZ: Double, fov: Double) {
            self.eyeX = eyeX; self.eyeY = eyeY; self.eyeZ = eyeZ
            self.atX = atX; self.atY = atY; self.atZ = atZ
            self.fov = fov
        }

        public static func mix(_ a: Pose, _ b: Pose, _ w: Double) -> Pose {
            Pose(eyeX: a.eyeX + (b.eyeX - a.eyeX) * w, eyeY: a.eyeY + (b.eyeY - a.eyeY) * w,
                 eyeZ: a.eyeZ + (b.eyeZ - a.eyeZ) * w, atX: a.atX + (b.atX - a.atX) * w,
                 atY: a.atY + (b.atY - a.atY) * w, atZ: a.atZ + (b.atZ - a.atZ) * w,
                 fov: a.fov + (b.fov - a.fov) * w)
        }
    }

    /// `presentation.toml [camera]` plus the two pitch numbers the framing needs, handed in whole.
    public struct Params: Sendable, Hashable {
        public var height: Double, back: Double, look: Double, follow: Double
        public var minZ: Double, maxZ: Double, rate: Double
        public var halfWidth: Double, fitNear: Double, minFov: Double, maxFov: Double
        public var buildupHeight: Double, buildupBack: Double, buildupFov: Double
        public var buildupWeight: Double, buildupRate: Double
        public var goalRadius: Double, goalHeight: Double, goalRise: Double, goalStartAngle: Double
        public var goalSweep: Double, goalSweepSeconds: Double, goalLookHeight: Double, goalFov: Double
        public var goalWeight: Double, goalRateIn: Double, goalRateOut: Double
        public var reduceGoalWeight: Double, reduceBuildupWeight: Double
        /// The pitch (§1) and §8.6's shot window: the goal line's |z|, the post's |x| and how far
        /// either side of the posts still counts, and how many seconds ahead a shot is framed.
        public var goalLineZ: Double, postX: Double, postMargin: Double, shotHorizon: Double

        public init(height: Double, back: Double, look: Double, follow: Double, minZ: Double, maxZ: Double,
                    rate: Double, halfWidth: Double, fitNear: Double, minFov: Double, maxFov: Double,
                    buildupHeight: Double, buildupBack: Double, buildupFov: Double, buildupWeight: Double,
                    buildupRate: Double, goalRadius: Double, goalHeight: Double, goalRise: Double,
                    goalStartAngle: Double, goalSweep: Double, goalSweepSeconds: Double, goalLookHeight: Double,
                    goalFov: Double, goalWeight: Double, goalRateIn: Double, goalRateOut: Double,
                    reduceGoalWeight: Double, reduceBuildupWeight: Double, goalLineZ: Double, postX: Double,
                    postMargin: Double, shotHorizon: Double) {
            self.height = height; self.back = back; self.look = look; self.follow = follow
            self.minZ = minZ; self.maxZ = maxZ; self.rate = rate
            self.halfWidth = halfWidth; self.fitNear = fitNear; self.minFov = minFov; self.maxFov = maxFov
            self.buildupHeight = buildupHeight; self.buildupBack = buildupBack; self.buildupFov = buildupFov
            self.buildupWeight = buildupWeight; self.buildupRate = buildupRate
            self.goalRadius = goalRadius; self.goalHeight = goalHeight; self.goalRise = goalRise
            self.goalStartAngle = goalStartAngle; self.goalSweep = goalSweep; self.goalSweepSeconds = goalSweepSeconds
            self.goalLookHeight = goalLookHeight; self.goalFov = goalFov
            self.goalWeight = goalWeight; self.goalRateIn = goalRateIn; self.goalRateOut = goalRateOut
            self.reduceGoalWeight = reduceGoalWeight; self.reduceBuildupWeight = reduceBuildupWeight
            self.goalLineZ = goalLineZ; self.postX = postX; self.postMargin = postMargin
            self.shotHorizon = shotHorizon
        }
    }

    /// What the director is framing this frame. The caller owns the decision (it owns the time
    /// scale); `goal` carries the real seconds since the goal was scored.
    public enum Mode: Sendable, Equatable { case play, buildup, goal(Double) }

    /// Where the ball is and where it is going, in metres and metres per second.
    public struct Ball: Sendable, Equatable {
        public var x: Double, z: Double, vx: Double, vz: Double
        public init(x: Double, z: Double, vx: Double, vz: Double) {
            self.x = x; self.z = z; self.vx = vx; self.vz = vz
        }
    }

    public let params: Params
    public private(set) var pose: Pose
    private var focusZ = 0.0
    private var weight = 0.0
    private var drama: Pose
    private var scored: (z: Double, side: Double, x: Double)?
    /// The goal a build-up has committed to, held for as long as the build-up runs. Re-choosing it
    /// every frame is what let a ball rattling behind a net throw the camera from end to end.
    private var framing: Double?

    public init(_ params: Params, aspect: Double) {
        self.params = params
        let start = MatchCamera.playPose(focusZ: 0, aspect: aspect, params)
        pose = start
        drama = start
    }

    /// A goal was scored in the net on goal line `goalZ` (§8.5).
    public mutating func goalScored(goalZ: Double, ballX: Double) {
        scored = (goalZ, ballX >= 0 ? 1 : -1, min(max(ballX, -1.5), 1.5))
    }

    /// Whether a goal is still being shown — the blend back to the play camera has not finished.
    public var isShowingGoal: Bool { scored != nil }

    /// The goal a build-up may frame: the one the ball is **still in front of** and will cross
    /// inside the posts within `shotHorizon` seconds. Nil once the ball is behind a goal line —
    /// a ball rattling around behind the net is not a shot about to score, whatever the sign of its
    /// z velocity says, and framing it by that sign is what threw the camera between the two ends
    /// at frame rate.
    public static func buildupGoalZ(_ ball: Ball, _ p: Params) -> Double? {
        guard abs(ball.vz) > 1e-6, abs(ball.z) <= p.goalLineZ else { return nil }
        for side in [-1.0, 1.0] {
            let gz = side * p.goalLineZ
            let t = (gz - ball.z) / ball.vz
            guard t >= 0, t <= p.shotHorizon else { continue }
            if abs(ball.x + ball.vx * t) <= p.postX + p.postMargin { return gz }
        }
        return nil
    }

    /// One frame of real time. `aspect` is the view's width over its height.
    @discardableResult
    public mutating func advance(_ dt: Double, mode: Mode, ball: Ball, aspect: Double,
                                 reduceMotion: Bool) -> Pose {
        let p = params
        // The focus eases toward a share of the ball's z, clamped to the pitch's window.
        let want = min(max(ball.z * p.follow, p.minZ), p.maxZ)
        focusZ += (want - focusZ) * (1 - exp(-dt * p.rate))
        let play = MatchCamera.playPose(focusZ: focusZ, aspect: aspect, p)

        var wanted = 0.0
        var blendRate = p.buildupRate
        switch mode {
        case .goal(let t):
            framing = nil
            drama = goalPose(t, ballX: ball.x, reduceMotion: reduceMotion)
            wanted = reduceMotion ? p.reduceGoalWeight : p.goalWeight
            blendRate = p.goalRateIn
        case .buildup:
            // Committed once and held: a velocity that flips sign cannot swap ends mid-blend.
            if framing == nil { framing = MatchCamera.buildupGoalZ(ball, p) }
            if let gz = framing {
                drama = buildupPose(gz, ball: ball)
                wanted = reduceMotion ? p.reduceBuildupWeight : p.buildupWeight
            }
            // No goal to frame (the ball is behind a line, or running nowhere near a mouth): the
            // play camera keeps it, eased back to rather than cut to.
        case .play:
            // The commitment is let go only once the blend has run out, so the next build-up starts
            // from the play camera. Swapping the framed goal while the drama pose still carries
            // weight is a cut, and at frame rate it is the jitter.
            if weight < 0.002 { framing = nil }
            if scored != nil { blendRate = p.goalRateOut }
        }
        weight += (wanted - weight) * (1 - exp(-dt * blendRate))
        if mode == .play, weight < 0.002 { scored = nil }
        pose = Pose.mix(play, drama, weight)
        return pose
    }

    /// High and steep behind the focus, looking up the pitch, the field of view fitted each frame so
    /// the pitch's width fills the screen.
    public static func playPose(focusZ f: Double, aspect: Double, _ p: Params) -> Pose {
        let eyeZ = f - p.back, nearZ = f - p.fitNear
        let d = (p.height * p.height + (eyeZ - nearZ) * (eyeZ - nearZ)).squareRoot()
        let hfov = 2 * atan(p.halfWidth / d)
        let vfov = 2 * atan(tan(hfov / 2) / max(aspect, 0.01)) * 180 / .pi
        return Pose(eyeX: 0, eyeY: p.height, eyeZ: eyeZ, atX: 0, atY: 0, atZ: f + p.look,
                    fov: min(max(vfov, p.minFov), p.maxFov))
    }

    /// A shot about to score: low behind the ball, looking along it at the net it is heading for.
    private func buildupPose(_ gz: Double, ball: Ball) -> Pose {
        let p = params
        let outward = gz >= 0 ? 1.0 : -1.0
        // The crossing is only ever read within the shot window, and never off the pitch: an
        // almost-parallel shot cannot throw the look-at into the next county.
        let t = abs(ball.vz) > 1e-6 ? min(max((gz - ball.z) / ball.vz, 0), p.shotHorizon) : 0
        let hitX = min(max(ball.x + ball.vx * t, -p.halfWidth), p.halfWidth)
        return Pose(eyeX: ball.x * 0.6, eyeY: p.buildupHeight, eyeZ: gz - outward * p.buildupBack,
                    atX: hitX * 0.5, atY: 0.6, atZ: gz, fov: p.buildupFov)
    }

    /// The goal camera: beside the net on the side the ball came from, sweeping round behind it.
    private func goalPose(_ t: Double, ballX: Double, reduceMotion: Bool) -> Pose {
        let p = params
        guard let g = scored else { return drama }
        let outward = g.z >= 0 ? 1.0 : -1.0
        let run = reduceMotion ? 0 : min(t, p.goalSweepSeconds)
        let a = p.goalStartAngle - run * p.goalSweep
        return Pose(eyeX: g.x + g.side * sin(a) * p.goalRadius, eyeY: p.goalHeight + run * p.goalRise,
                    eyeZ: g.z + outward * cos(a) * p.goalRadius,
                    atX: ballX * 0.4, atY: p.goalLookHeight, atZ: g.z - outward * 0.5, fov: p.goalFov)
    }
}
