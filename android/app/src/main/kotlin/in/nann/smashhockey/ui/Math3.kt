package `in`.nann.smashhockey.ui

import android.opengl.Matrix
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * The little 3D maths the kit needs, mutable and in place so a frame allocates nothing: a
 * quaternion, a translate-rotate-scale transform (RealityKit's `Transform`), a box and a ray.
 */
class Quat(var x: Float = 0f, var y: Float = 0f, var z: Float = 0f, var w: Float = 1f) {
    fun identity(): Quat { x = 0f; y = 0f; z = 0f; w = 1f; return this }

    fun set(o: Quat): Quat { x = o.x; y = o.y; z = o.z; w = o.w; return this }

    /** A turn of [angle] radians about the unit axis (ax, ay, az). */
    fun axisAngle(angle: Float, ax: Float, ay: Float, az: Float): Quat {
        val h = angle / 2
        val s = sin(h)
        x = ax * s; y = ay * s; z = az * s; w = cos(h)
        return this
    }

    /** this = a · b (b applied first). Safe when this is a or b. */
    fun mul(a: Quat, b: Quat): Quat {
        val nx = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y
        val ny = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x
        val nz = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w
        val nw = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
        x = nx; y = ny; z = nz; w = nw
        return this
    }

    /** From an orthonormal basis (the columns of a rotation matrix). */
    fun fromBasis(m00: Float, m10: Float, m20: Float, m01: Float, m11: Float, m21: Float, m02: Float, m12: Float, m22: Float): Quat {
        val trace = m00 + m11 + m22
        if (trace > 0) {
            val s = kotlin.math.sqrt(trace + 1f) * 2
            w = 0.25f * s; x = (m21 - m12) / s; y = (m02 - m20) / s; z = (m10 - m01) / s
        } else if (m00 > m11 && m00 > m22) {
            val s = kotlin.math.sqrt(1f + m00 - m11 - m22) * 2
            w = (m21 - m12) / s; x = 0.25f * s; y = (m01 + m10) / s; z = (m02 + m20) / s
        } else if (m11 > m22) {
            val s = kotlin.math.sqrt(1f + m11 - m00 - m22) * 2
            w = (m02 - m20) / s; x = (m01 + m10) / s; y = 0.25f * s; z = (m12 + m21) / s
        } else {
            val s = kotlin.math.sqrt(1f + m22 - m00 - m11) * 2
            w = (m10 - m01) / s; x = (m02 + m20) / s; y = (m12 + m21) / s; z = 0.25f * s
        }
        return this
    }
}

/** Translation, rotation, non-uniform scale — composed as T · R · S. */
class Xform {
    var tx = 0f; var ty = 0f; var tz = 0f
    val rot = Quat()
    var sx = 1f; var sy = 1f; var sz = 1f

    fun set(o: Xform): Xform {
        tx = o.tx; ty = o.ty; tz = o.tz; rot.set(o.rot); sx = o.sx; sy = o.sy; sz = o.sz
        return this
    }

    fun identity(): Xform { tx = 0f; ty = 0f; tz = 0f; rot.identity(); sx = 1f; sy = 1f; sz = 1f; return this }

    /** Column-major 4×4, as Filament's TransformManager takes it. */
    fun toMatrix(m: FloatArray) {
        val x = rot.x; val y = rot.y; val z = rot.z; val w = rot.w
        val xx = x * x; val yy = y * y; val zz = z * z
        val xy = x * y; val xz = x * z; val yz = y * z
        val wx = w * x; val wy = w * y; val wz = w * z
        m[0] = (1 - 2 * (yy + zz)) * sx; m[1] = 2 * (xy + wz) * sx; m[2] = 2 * (xz - wy) * sx; m[3] = 0f
        m[4] = 2 * (xy - wz) * sy; m[5] = (1 - 2 * (xx + zz)) * sy; m[6] = 2 * (yz + wx) * sy; m[7] = 0f
        m[8] = 2 * (xz + wy) * sz; m[9] = 2 * (yz - wx) * sz; m[10] = (1 - 2 * (xx + yy)) * sz; m[11] = 0f
        m[12] = tx; m[13] = ty; m[14] = tz; m[15] = 1f
    }

    companion object {
        /** A rest pose in a frame: at (x, y, z), tilted by [tilt] radians about Z. */
        fun at(x: Float, y: Float, z: Float = 0f, tilt: Float = 0f): Xform = Xform().apply {
            tx = x; ty = y; tz = z
            rot.axisAngle(tilt, 0f, 0f, 1f)
        }
    }
}

/** An axis-aligned box in some node's own space. */
class Bounds(val minX: Float, val minY: Float, val minZ: Float, val maxX: Float, val maxY: Float, val maxZ: Float) {
    val width get() = maxX - minX
}

/** A ray from a touch, in world space or in some node's own space. */
class TouchRay(val ox: Float, val oy: Float, val oz: Float, val dx: Float, val dy: Float, val dz: Float) {

    /** This ray in [node]'s own space. */
    fun local(node: UiNode): TouchRay {
        val inv = FloatArray(16)
        Matrix.invertM(inv, 0, node.worldMatrix(), 0)
        return TouchRay(
            inv[0] * ox + inv[4] * oy + inv[8] * oz + inv[12],
            inv[1] * ox + inv[5] * oy + inv[9] * oz + inv[13],
            inv[2] * ox + inv[6] * oy + inv[10] * oz + inv[14],
            inv[0] * dx + inv[4] * dy + inv[8] * dz,
            inv[1] * dx + inv[5] * dy + inv[9] * dz,
            inv[2] * dx + inv[6] * dy + inv[10] * dz,
        )
    }

    /** Distance along the ray to [b] (in the ray's space), null on a miss — the slab test. */
    fun hit(b: Bounds): Float? {
        var tMin = 0f
        var tMax = Float.MAX_VALUE
        for (a in 0..2) {
            val o = when (a) { 0 -> ox; 1 -> oy; else -> oz }
            val d = when (a) { 0 -> dx; 1 -> dy; else -> dz }
            val lo = when (a) { 0 -> b.minX; 1 -> b.minY; else -> b.minZ }
            val hi = when (a) { 0 -> b.maxX; 1 -> b.maxY; else -> b.maxZ }
            if (abs(d) < 1e-8f) {
                if (o < lo || o > hi) return null
            } else {
                val t1 = (lo - o) / d
                val t2 = (hi - o) / d
                tMin = max(tMin, min(t1, t2)); tMax = min(tMax, max(t1, t2))
                if (tMin > tMax) return null
            }
        }
        return tMin
    }

    /** Where the ray crosses the z = 0 plane of its space (x only is needed), null if parallel. */
    fun planeX(): Float? {
        if (abs(dz) < 1e-6f) return null
        return ox + dx * (-oz / dz)
    }
}
