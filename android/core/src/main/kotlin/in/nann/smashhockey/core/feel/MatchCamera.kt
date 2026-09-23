package `in`.nann.smashhockey.core.feel

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * Where the match camera stands (spec §8.6) — the pure half of the director, so one test can walk
 * the ball over every square metre of the pitch and pin what the camera does. Its tunables are the
 * apps' presentation (`presentation.toml [camera]`), handed in by the caller; nothing here is on
 * the simulation path. The iOS twin is `SmashCore/Feel/MatchCamera.swift`.
 */
class MatchCamera(val params: Params, aspect: Double) {

    /** Eye, look-at target, vertical field of view (degrees). */
    data class Pose(
        val eyeX: Double, val eyeY: Double, val eyeZ: Double,
        val atX: Double, val atY: Double, val atZ: Double,
        val fov: Double,
    ) {
        companion object {
            fun mix(a: Pose, b: Pose, w: Double) = Pose(
                a.eyeX + (b.eyeX - a.eyeX) * w, a.eyeY + (b.eyeY - a.eyeY) * w, a.eyeZ + (b.eyeZ - a.eyeZ) * w,
                a.atX + (b.atX - a.atX) * w, a.atY + (b.atY - a.atY) * w, a.atZ + (b.atZ - a.atZ) * w,
                a.fov + (b.fov - a.fov) * w,
            )
        }
    }

    /** `presentation.toml [camera]` plus the two pitch numbers the framing needs, handed in whole. */
    data class Params(
        val height: Double, val back: Double, val look: Double, val follow: Double,
        val minZ: Double, val maxZ: Double, val rate: Double,
        val halfWidth: Double, val fitNear: Double, val minFov: Double, val maxFov: Double,
        val buildupHeight: Double, val buildupBack: Double, val buildupFov: Double,
        val buildupWeight: Double, val buildupRate: Double,
        val goalRadius: Double, val goalHeight: Double, val goalRise: Double, val goalStartAngle: Double,
        val goalSweep: Double, val goalSweepSeconds: Double, val goalLookHeight: Double, val goalFov: Double,
        val goalWeight: Double, val goalRateIn: Double, val goalRateOut: Double,
        val reduceGoalWeight: Double, val reduceBuildupWeight: Double,
        /**
         * The pitch (§1) and §8.6's shot window: the goal line's |z|, the post's |x| and how far
         * either side of the posts still counts, and how many seconds ahead a shot is framed.
         */
        val goalLineZ: Double, val postX: Double, val postMargin: Double, val shotHorizon: Double,
    )

    /**
     * What the director is framing this frame. The caller owns the decision (it owns the time
     * scale); [Goal] carries the real seconds since the goal was scored.
     */
    sealed interface Mode {
        data object Play : Mode
        data object Buildup : Mode
        data class Goal(val seconds: Double) : Mode
    }

    /** Where the ball is and where it is going, in metres and metres per second. */
    data class Ball(val x: Double, val z: Double, val vx: Double, val vz: Double)

    var pose: Pose = playPose(0.0, aspect, params)
        private set
    private var focusZ = 0.0
    private var weight = 0.0
    private var drama = pose
    private var scoredZ = 0.0
    private var scoredSide = 1.0
    private var scoredX = 0.0
    private var scored = false
    /**
     * The goal a build-up has committed to, held for as long as the build-up runs. Re-choosing it
     * every frame is what let a ball rattling behind a net throw the camera from end to end.
     */
    private var framing: Double? = null

    /** A goal was scored in the net on goal line [goalZ] (§8.5). */
    fun goalScored(goalZ: Double, ballX: Double) {
        scoredZ = goalZ
        scoredSide = if (ballX >= 0) 1.0 else -1.0
        scoredX = ballX.coerceIn(-1.5, 1.5)
        scored = true
    }

    /** Whether a goal is still being shown — the blend back to the play camera has not finished. */
    val isShowingGoal get() = scored

    /** One frame of real time. [aspect] is the view's width over its height. */
    fun advance(dt: Double, mode: Mode, ball: Ball, aspect: Double, reduceMotion: Boolean): Pose {
        val p = params
        // The focus eases toward a share of the ball's z, clamped to the pitch's window.
        val want = (ball.z * p.follow).coerceIn(p.minZ, p.maxZ)
        focusZ += (want - focusZ) * (1 - exp(-dt * p.rate))
        val play = playPose(focusZ, aspect, p)

        var wanted = 0.0
        var blendRate = p.buildupRate
        when (mode) {
            is Mode.Goal -> {
                framing = null
                drama = goalPose(mode.seconds, ball.x, reduceMotion)
                wanted = if (reduceMotion) p.reduceGoalWeight else p.goalWeight
                blendRate = p.goalRateIn
            }
            Mode.Buildup -> {
                // Committed once and held: a velocity that flips sign cannot swap ends mid-blend.
                if (framing == null) framing = buildupGoalZ(ball, p)
                framing?.let {
                    drama = buildupPose(it, ball)
                    wanted = if (reduceMotion) p.reduceBuildupWeight else p.buildupWeight
                }
                // No goal to frame (the ball is behind a line, or running nowhere near a mouth):
                // the play camera keeps it, eased back to rather than cut to.
            }
            Mode.Play -> {
                // The commitment is let go only once the blend has run out, so the next build-up
                // starts from the play camera. Swapping the framed goal while the drama pose still
                // carries weight is a cut, and at frame rate it is the jitter.
                if (weight < 0.002) framing = null
                if (scored) blendRate = p.goalRateOut
            }
        }
        weight += (wanted - weight) * (1 - exp(-dt * blendRate))
        if (mode == Mode.Play && weight < 0.002) scored = false
        pose = Pose.mix(play, drama, weight)
        return pose
    }

    /** A shot about to score: low behind the ball, looking along it at the net it is heading for. */
    private fun buildupPose(gz: Double, ball: Ball): Pose {
        val p = params
        val outward = if (gz >= 0) 1.0 else -1.0
        // The crossing is only ever read within the shot window, and never off the pitch: an
        // almost-parallel shot cannot throw the look-at into the next county.
        val t = if (abs(ball.vz) > 1e-6) ((gz - ball.z) / ball.vz).coerceIn(0.0, p.shotHorizon) else 0.0
        val hitX = (ball.x + ball.vx * t).coerceIn(-p.halfWidth, p.halfWidth)
        return Pose(ball.x * 0.6, p.buildupHeight, gz - outward * p.buildupBack,
            hitX * 0.5, 0.6, gz, p.buildupFov)
    }

    /** The goal camera: beside the net on the side the ball came from, sweeping round behind it. */
    private fun goalPose(t: Double, ballX: Double, reduceMotion: Boolean): Pose {
        val p = params
        if (!scored) return drama
        val outward = if (scoredZ >= 0) 1.0 else -1.0
        val run = if (reduceMotion) 0.0 else min(t, p.goalSweepSeconds)
        val a = p.goalStartAngle - run * p.goalSweep
        return Pose(scoredX + scoredSide * sin(a) * p.goalRadius, p.goalHeight + run * p.goalRise,
            scoredZ + outward * cos(a) * p.goalRadius,
            ballX * 0.4, p.goalLookHeight, scoredZ - outward * 0.5, p.goalFov)
    }

    companion object {
        /**
         * The goal a build-up may frame: the one the ball is **still in front of** and will cross
         * inside the posts within `shotHorizon` seconds. Null once the ball is behind a goal line —
         * a ball rattling around behind the net is not a shot about to score, whatever the sign of
         * its z velocity says, and framing it by that sign is what threw the camera between the two
         * ends at frame rate.
         */
        fun buildupGoalZ(ball: Ball, p: Params): Double? {
            if (abs(ball.vz) <= 1e-6 || abs(ball.z) > p.goalLineZ) return null
            for (side in doubleArrayOf(-1.0, 1.0)) {
                val gz = side * p.goalLineZ
                val t = (gz - ball.z) / ball.vz
                if (t < 0 || t > p.shotHorizon) continue
                if (abs(ball.x + ball.vx * t) <= p.postX + p.postMargin) return gz
            }
            return null
        }

        /**
         * High and steep behind the focus, looking up the pitch, the field of view fitted each frame
         * so the pitch's width fills the screen.
         */
        fun playPose(focusZ: Double, aspect: Double, p: Params): Pose {
            val eyeZ = focusZ - p.back
            val nearZ = focusZ - p.fitNear
            val d = sqrt(p.height * p.height + (eyeZ - nearZ) * (eyeZ - nearZ))
            val hfov = 2 * atan(p.halfWidth / d)
            val vfov = 2 * atan(tan(hfov / 2) / max(aspect, 0.01)) * 180 / PI
            return Pose(0.0, p.height, eyeZ, 0.0, 0.0, focusZ + p.look, vfov.coerceIn(p.minFov, p.maxFov))
        }
    }
}
