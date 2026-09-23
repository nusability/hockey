package `in`.nann.smashhockey.scene

import `in`.nann.smashhockey.core.feel.MatchCamera
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.match.MatchState
import `in`.nann.smashhockey.generated.Presentation.Camera as P
import `in`.nann.smashhockey.core.generated.Tuning.SlowMotion as S
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.sin

/** Where the camera is: eye, look-at target, vertical field of view (degrees). */
data class CameraPose(val eye: DoubleArray, val target: DoubleArray, val fov: Double)

/** What the director reads from the match each frame (§8.6 queries, and where the ball is). */
data class DirectorInput(
    val state: MatchState,
    val shotAboutToScore: Boolean,
    val lastShotDistance: Double?,
    val ballX: Double, val ballZ: Double,
    val ballVx: Double, val ballVz: Double,
    val carrierTeam: Int?,
)

/**
 * Presentation time and the camera (spec §8.6) — the twin of iOS's Director.swift. It sets the
 * time scale — how many ticks a real second holds — and never touches what a tick does (§4.2). It
 * runs on real time, so the camera and the UI move at full speed through slow motion.
 *
 * Where the camera *stands* is the core's ([MatchCamera]), handed this file's numbers from
 * `presentation.toml`, so one test walks the ball over the whole pitch and pins the solve on both
 * platforms. What is left here is the time scale, the shake, and the app's end of the rig.
 */
class Director {
    var timeScale = 1.0; private set
    var reduceMotion = false
    /** The view's width over its height: the play camera fits the pitch's width to it. */
    var aspect = 0.46

    private var goalClock: Double? = null
    private var goalIsLong = false
    private val camera = MatchCamera(params, 0.46)
    private var shake = 0.0
    private var shakeClock = 0.0

    val pose: CameraPose
        get() {
            val p = camera.pose
            return CameraPose(doubleArrayOf(p.eyeX, p.eyeY, p.eyeZ), doubleArrayOf(p.atX, p.atY, p.atZ), p.fov)
        }

    fun goalScored(goalZ: Double, ballX: Double, lastShotDistance: Double?) {
        goalClock = 0.0
        goalIsLong = (lastShotDistance ?: 0.0) > S.longShot
        camera.goalScored(goalZ, ballX)
    }

    /**
     * A kick of [amplitude] metres (§8.8: a goal, a post) — the prototype's shake: it falls off
     * linearly at the decay rate; Reduce Motion keeps only a share of it.
     */
    fun knock(amplitude: Double) {
        val a = amplitude * if (reduceMotion) P.Shake.reduceMotion else 1.0
        if (a > shake) { shake = a; shakeClock = 0.0 }
    }

    /** One frame of real time: the time scale for the ticks to come, and the camera. */
    fun update(dt: Double, m: DirectorInput) {
        // §8.6 — the time scale.
        var target = 1.0
        var rate = S.easeRate
        var mode: MatchCamera.Mode = MatchCamera.Mode.Play
        goalClock?.let { t0 ->
            if (m.state != MatchState.GOAL) {
                goalClock = null
                timeScale = max(timeScale, S.leaveGoalMin)
            } else {
                val t = t0 + dt
                goalClock = t
                mode = MatchCamera.Mode.Goal(t)
                rate = S.goalEaseRate
                if (!goalIsLong) {
                    val back = ((t - S.goalHold) / S.goalEaseBack).coerceIn(0.0, 1.0)
                    target = if (t < S.goalHold) S.goalScale else S.goalScale + (1 - S.goalScale) * back
                }
            }
        }
        if (mode == MatchCamera.Mode.Play && m.shotAboutToScore) {
            mode = MatchCamera.Mode.Buildup
            if ((m.lastShotDistance ?: 0.0) <= S.longShot) target = S.shotScale
        }
        timeScale += (target - timeScale) * (1 - exp(-dt * rate))

        camera.advance(dt, mode, MatchCamera.Ball(m.ballX, m.ballZ, m.ballVx, m.ballVz), aspect, reduceMotion)

        shakeClock += dt
        shake = max(0.0, shake - dt * P.Shake.decay)
    }

    /** The camera shake as an offset of the world; the camera and its HUD stay steady. */
    val shakeOffset: DoubleArray
        get() {
            if (shake <= 0.0) return doubleArrayOf(0.0, 0.0, 0.0)
            val w = 2 * PI * P.Shake.frequency * shakeClock
            val half = shake / 2       // the prototype jittered by up to half the kick either way
            return doubleArrayOf(sin(w) * half, sin(w * 1.31 + 1.7) * half, 0.0)
        }

    companion object {
        /**
         * `presentation.toml [camera]` and the pitch numbers §8.6's shot window is measured in,
         * handed to the core's solve. Declared once; nothing else reads these.
         */
        val params = MatchCamera.Params(
            height = P.Play.height, back = P.Play.back, look = P.Play.look, follow = P.Play.follow,
            minZ = P.Play.minZ, maxZ = P.Play.maxZ, rate = P.Play.rate, halfWidth = P.Play.halfWidth,
            fitNear = P.Play.fitNear, minFov = P.Play.minFov, maxFov = P.Play.maxFov,
            buildupHeight = P.Buildup.height, buildupBack = P.Buildup.back, buildupFov = P.Buildup.fov,
            buildupWeight = P.Buildup.weight, buildupRate = P.Buildup.rate,
            goalRadius = P.Goal.radius, goalHeight = P.Goal.height, goalRise = P.Goal.rise,
            goalStartAngle = P.Goal.startAngle, goalSweep = P.Goal.sweep, goalSweepSeconds = P.Goal.sweepSeconds,
            goalLookHeight = P.Goal.lookHeight, goalFov = P.Goal.fov, goalWeight = P.Goal.weight,
            goalRateIn = P.Goal.rateIn, goalRateOut = P.Goal.rateOut,
            reduceGoalWeight = P.ReduceMotion.goalWeight, reduceBuildupWeight = P.ReduceMotion.buildupWeight,
            goalLineZ = Tuning.Pitch.goalLineZ, postX = Tuning.Pitch.postX,
            postMargin = S.shotPostMargin, shotHorizon = S.shotHorizon,
        )
    }
}
