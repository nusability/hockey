package `in`.nann.smashhockey.ui

import com.google.android.filament.Camera
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import `in`.nann.smashhockey.engine.Spring

/** Where the camera stands for a screen, and what it looks at. */
class CameraPose(val ex: Float, val ey: Float, val ez: Float, val tx: Float, val ty: Float, val tz: Float) {
    companion object {
        fun of(eye: FloatArray, target: FloatArray) = CameraPose(eye[0], eye[1], eye[2], target[0], target[1], target[2])
    }
}

/**
 * The one camera, and how it gets between screens — the twin of iOS's `CameraRig`: a swoop along
 * an arc on the `swoop` spring — up and over, a little roll into the turn, a little overshoot on
 * arrival. Interrupt it and the next swoop starts from wherever the camera is. Under Reduce Motion
 * it cuts.
 */
class CameraRig(private val camera: Camera, start: CameraPose, motion: Motion) {
    /** The current vertical field of view: the menus' own, or the match camera's while tracking it. */
    var fovDegrees = MENU_FOV
        private set
    private var from = start
    private var to = start
    private var fromFov = MENU_FOV
    private var toFov = MENU_FOV
    private var follow: (() -> Pair<CameraPose, Double>)? = null
    private val progress = Spring(motion.spring(SpringName.SWOOP), 1.0)
    private var arc = 0f
    private var roll = 0f

    // The current pose, unpacked so the frame allocates nothing.
    var ex = start.ex; private set
    var ey = start.ey; private set
    var ez = start.ez; private set
    private var gx = start.tx; private var gy = start.ty; private var gz = start.tz

    /** The camera's world matrix (column-major), updated every [update]. */
    val world = FloatArray(16)
    private val model = DoubleArray(16)

    init { place(0f) }

    /** Screens further apart swoop higher; [roll] tilts the horizon into the turn (radians). */
    fun swoop(pose: CameraPose, arc: Float? = null, roll: Float = 0.1f) {
        KitSound.swoop()
        follow = null
        begin(pose, MENU_FOV, arc, roll)
    }

    /** Swoops onto a moving pose and then follows it exactly — the match camera (§8.6). */
    fun track(roll: Float = 0.1f, source: () -> Pair<CameraPose, Double>) {
        val (pose, fov) = source()
        KitSound.swoop()
        follow = source
        begin(pose, fov, null, roll)
    }

    private fun begin(pose: CameraPose, fov: Double, arc: Float?, roll: Float) {
        from = CameraPose(ex, ey, ez, gx, gy, gz)
        fromFov = fovDegrees
        toFov = fov
        to = pose
        val dx = to.ex - from.ex; val dy = to.ey - from.ey; val dz = to.ez - from.ez
        this.arc = arc ?: min(8f, sqrt(dx * dx + dy * dy + dz * dz) * 0.25f)
        // y of cross(from.forward, to.forward): which way the view turns.
        val fx = from.tx - from.ex; val fz = from.tz - from.ez
        val tx = to.tx - to.ex; val tz = to.tz - to.ez
        val turning = fz * tx - fx * tz
        this.roll = if (turning >= 0) roll else -roll
        progress.snap(0.0)
        progress.target = 1.0
    }

    val isMoving get() = !progress.isSettled

    fun update(dt: Double, reduceMotion: Boolean) {
        follow?.let { val (p, f) = it(); to = p; toFov = f }
        if (reduceMotion) progress.snap(1.0) else progress.advance(dt)
        val p = progress.value.toFloat()
        val bump = 4 * p * (1 - p)
        ex = from.ex + (to.ex - from.ex) * p
        ey = from.ey + (to.ey - from.ey) * p + arc * max(0f, bump)
        ez = from.ez + (to.ez - from.ez) * p
        gx = from.tx + (to.tx - from.tx) * p
        gy = from.ty + (to.ty - from.ty) * p
        gz = from.tz + (to.tz - from.tz) * p
        fovDegrees = fromFov + (toFov - fromFov) * p.coerceIn(0f, 1f)
        place(roll * bump)
    }

    /** Looks from the eye at the target (up = +Y), rolled about the view axis, and hands it to Filament. */
    private fun place(roll: Float) {
        basis(ex, ey, ez, gx, gy, gz, world)
        if (roll != 0f) {
            val c = cos(roll); val s = sin(roll)
            for (i in 0..2) {
                val x = world[i]; val y = world[4 + i]
                world[i] = x * c + y * s
                world[4 + i] = -x * s + y * c
            }
        }
        for (i in 0..15) model[i] = world[i].toDouble()
        camera.setModelMatrix(model)
    }

    /** Where the camera would be with [pose] (no roll) — for building a screen's frame before it arrives. */
    fun transform(pose: CameraPose): Xform {
        val m = FloatArray(16)
        basis(pose.ex, pose.ey, pose.ez, pose.tx, pose.ty, pose.tz, m)
        return Xform().apply {
            tx = pose.ex; ty = pose.ey; tz = pose.ez
            rot.fromBasis(m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10])
        }
    }

    companion object {
        /** The field of view every menu is laid out for. */
        const val MENU_FOV = 50.0

        /** RealityKit's `look(at:from:)`: −Z toward the target, +Y as up as it can be. */
        private fun basis(ex: Float, ey: Float, ez: Float, tx: Float, ty: Float, tz: Float, m: FloatArray) {
            var zx = ex - tx; var zy = ey - ty; var zz = ez - tz
            val zl = sqrt(zx * zx + zy * zy + zz * zz); zx /= zl; zy /= zl; zz /= zl
            // x = up × z, up = (0, 1, 0)
            var xx = zz; var xy = 0f; var xz = -zx
            val xl = sqrt(xx * xx + xz * xz); xx /= xl; xz /= xl
            // y = z × x
            val yx = zy * xz - zz * xy; val yy = zz * xx - zx * xz; val yz = zx * xy - zy * xx
            m[0] = xx; m[1] = xy; m[2] = xz; m[3] = 0f
            m[4] = yx; m[5] = yy; m[6] = yz; m[7] = 0f
            m[8] = zx; m[9] = zy; m[10] = zz; m[11] = 0f
            m[12] = ex; m[13] = ey; m[14] = ez; m[15] = 1f
        }
    }
}
