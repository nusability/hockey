package `in`.nann.smashhockey.scene

import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.match.MatchState
import `in`.nann.smashhockey.generated.Presentation.Camera as P
import `in`.nann.smashhockey.core.generated.Tuning.SlowMotion as S
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan
import kotlin.math.atan

/** Where the camera is: eye, look-at target, vertical field of view (degrees). */
data class CameraPose(val eye: DoubleArray, val target: DoubleArray, val fov: Double) {
    companion object {
        fun mix(a: CameraPose, b: CameraPose, w: Double) = CameraPose(
            DoubleArray(3) { a.eye[it] + (b.eye[it] - a.eye[it]) * w },
            DoubleArray(3) { a.target[it] + (b.target[it] - a.target[it]) * w },
            a.fov + (b.fov - a.fov) * w,
        )
    }
}

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
 */
class Director {
    var timeScale = 1.0; private set
    var pose: CameraPose = playPose(0.0, 0.46); private set
    var reduceMotion = false
    /** The view's width over its height: the play camera fits the pitch's width to it. */
    var aspect = 0.46

    private var goalClock: Double? = null
    private var goalIsLong = false
    private var goalZ = 0.0; private var goalSide = 1.0; private var goalX = 0.0; private var hasGoal = false

    private var focusZ = 0.0
    private var weight = 0.0
    private var drama = pose
    private var shake = 0.0
    private var shakeClock = 0.0

    fun goalScored(goalZ: Double, ballX: Double, lastShotDistance: Double?) {
        goalClock = 0.0
        goalIsLong = (lastShotDistance ?: 0.0) > S.longShot
        this.goalZ = goalZ; goalSide = if (ballX >= 0) 1.0 else -1.0; goalX = ballX.coerceIn(-1.5, 1.5); hasGoal = true
    }

    /**
     * A kick of [amplitude] metres (§8.8: a goal, a post) — the prototype's shake: it falls off
     * linearly at the decay rate; Reduce Motion keeps only a share of it.
     */
    fun knock(amplitude: Double) {
        val a = amplitude * if (reduceMotion) P.Shake.reduceMotion else 1.0
        if (a > shake) { shake = a; shakeClock = 0.0 }
    }

    private sealed interface Mode { data object Play : Mode; data object Buildup : Mode; data class Goal(val t: Double) : Mode }

    fun update(dt: Double, m: DirectorInput) {
        // §8.6 — the time scale.
        var target = 1.0
        var rate = S.easeRate
        var mode: Mode = Mode.Play
        goalClock?.let { t0 ->
            if (m.state != MatchState.GOAL) {
                goalClock = null
                timeScale = max(timeScale, S.leaveGoalMin)
            } else {
                val t = t0 + dt
                goalClock = t
                mode = Mode.Goal(t)
                rate = S.goalEaseRate
                if (!goalIsLong) {
                    val back = ((t - S.goalHold) / S.goalEaseBack).coerceIn(0.0, 1.0)
                    target = if (t < S.goalHold) S.goalScale else S.goalScale + (1 - S.goalScale) * back
                }
            }
        }
        if (mode == Mode.Play && m.shotAboutToScore) {
            mode = Mode.Buildup
            if ((m.lastShotDistance ?: 0.0) <= S.longShot) target = S.shotScale
        }
        timeScale += (target - timeScale) * (1 - exp(-dt * rate))

        // The camera.
        followPlay(dt, m)
        val play = playPose(focusZ, aspect)
        var wanted = 0.0
        var blendRate = P.Buildup.rate
        when (val md = mode) {
            is Mode.Goal -> {
                drama = goalPose(md.t, m.ballX)
                wanted = if (reduceMotion) P.ReduceMotion.goalWeight else P.Goal.weight
                blendRate = P.Goal.rateIn
            }
            Mode.Buildup -> {
                drama = buildupPose(m)
                wanted = if (reduceMotion) P.ReduceMotion.buildupWeight else P.Buildup.weight
            }
            Mode.Play -> if (hasGoal) blendRate = P.Goal.rateOut
        }
        weight += (wanted - weight) * (1 - exp(-dt * blendRate))
        if (mode == Mode.Play && weight < 0.002) hasGoal = false
        pose = CameraPose.mix(play, drama, weight)
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

    /** The prototype's play camera: the focus eases toward a share of the ball's z. */
    private fun followPlay(dt: Double, m: DirectorInput) {
        val c = P.Play
        val want = (m.ballZ * c.follow).coerceIn(c.minZ, c.maxZ)
        focusZ += (want - focusZ) * (1 - exp(-dt * c.rate))
    }

    /**
     * High and steep behind the focus, looking up the pitch, the field of view fitted each frame so
     * the pitch's width fills the screen.
     */
    private fun playPose(focusZ: Double, aspect: Double): CameraPose {
        val c = P.Play
        val eyeZ = focusZ - c.back
        val nearZ = focusZ - c.fitNear
        val d = sqrt(c.height * c.height + (eyeZ - nearZ) * (eyeZ - nearZ))
        val hfov = 2 * atan(c.halfWidth / d)
        val vfov = Math.toDegrees(2 * atan(tan(hfov / 2) / max(aspect, 0.01)))
        return CameraPose(doubleArrayOf(0.0, c.height, eyeZ), doubleArrayOf(0.0, 0.0, focusZ + c.look), vfov.coerceIn(c.minFov, c.maxFov))
    }

    private fun buildupPose(m: DirectorInput): CameraPose {
        val b = P.Buildup
        val outward = if (m.ballVz >= 0) 1.0 else -1.0
        val gz = outward * Tuning.Pitch.goalLineZ
        val t = if (abs(m.ballVz) > 1e-6) (gz - m.ballZ) / m.ballVz else 0.0
        val hitX = m.ballX + m.ballVx * max(t, 0.0)
        return CameraPose(doubleArrayOf(m.ballX * 0.6, b.height, gz - outward * b.back), doubleArrayOf(hitX * 0.5, 0.6, gz), b.fov)
    }

    private fun goalPose(t: Double, ballX: Double): CameraPose {
        val g = P.Goal
        if (!hasGoal) return drama
        val outward = if (goalZ >= 0) 1.0 else -1.0
        val run = if (reduceMotion) 0.0 else min(t, g.sweepSeconds)
        val a = g.startAngle - run * g.sweep
        val eye = doubleArrayOf(goalX + goalSide * sin(a) * g.radius, g.height + run * g.rise, goalZ + outward * cos(a) * g.radius)
        return CameraPose(eye, doubleArrayOf(ballX * 0.4, g.lookHeight, goalZ - outward * 0.5), g.fov)
    }
}
