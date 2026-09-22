package `in`.nann.smashhockey.engine

import android.opengl.Matrix
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Flat-shaded low-poly geometry built from primitives — the twin of iOS's MeshKit.swift, same
 * shapes and facet counts, so a figure is the same figure on both platforms. Each triangle
 * carries its face normal. Parts are grouped by material slot: one mesh part per slot.
 */
class MeshKit {
    private class Part { val pos = ArrayList<Float>(); val nrm = ArrayList<Float>() }
    private val slots = sortedMapOf<Int, Part>()

    /** Applied to everything added until it changes (column-major, android.opengl.Matrix). */
    var transform: FloatArray = FloatArray(16).also { Matrix.setIdentityM(it, 0) }
    var slot = 0

    /** A triangle, counter-clockwise seen from its front; its normal follows the winding. */
    fun triangle(a: Vec3, b: Vec3, c: Vec3) {
        val pa = point(a); val pb = point(b); val pc = point(c)
        val n = (pb - pa).cross(pc - pa)
        val len = sqrt(n.dot(n))
        if (len < 1e-9f) return
        val part = slots.getOrPut(slot) { Part() }
        for (p in listOf(pa, pb, pc)) {
            part.pos += p.x; part.pos += p.y; part.pos += p.z
            part.nrm += n.x / len; part.nrm += n.y / len; part.nrm += n.z / len
        }
    }

    fun quad(a: Vec3, b: Vec3, c: Vec3, d: Vec3) { triangle(a, b, c); triangle(a, c, d) }

    private fun point(p: Vec3): Vec3 {
        val r = FloatArray(4)
        Matrix.multiplyMV(r, 0, transform, 0, floatArrayOf(p.x, p.y, p.z, 1f), 0)
        return Vec3(r[0], r[1], r[2])
    }

    // ---------------------------------------------------------------- primitives

    /** A box centred on [c]. */
    fun box(c: Vec3, size: Vec3) {
        val hx = size.x / 2; val hy = size.y / 2; val hz = size.z / 2
        fun v(x: Int, y: Int, z: Int) = Vec3(c.x + x * hx, c.y + y * hy, c.z + z * hz)
        quad(v(-1, -1, 1), v(1, -1, 1), v(1, 1, 1), v(-1, 1, 1))
        quad(v(1, -1, -1), v(-1, -1, -1), v(-1, 1, -1), v(1, 1, -1))
        quad(v(-1, 1, 1), v(1, 1, 1), v(1, 1, -1), v(-1, 1, -1))
        quad(v(-1, -1, -1), v(1, -1, -1), v(1, -1, 1), v(-1, -1, 1))
        quad(v(1, -1, 1), v(1, -1, -1), v(1, 1, -1), v(1, 1, 1))
        quad(v(-1, -1, -1), v(-1, -1, 1), v(-1, 1, 1), v(-1, 1, -1))
    }

    /** A capped frustum along +y; a cone has r1 = 0, a cylinder r0 = r1. */
    fun frustum(x: Float = 0f, z: Float = 0f, y0: Float, y1: Float, r0: Float, r1: Float, segments: Int) {
        fun ring(i: Int, r: Float, y: Float): Vec3 {
            val a = i.toFloat() / segments * 2f * PI.toFloat()
            return Vec3(x + r * sin(a), y, z + r * cos(a))
        }
        val top = Vec3(x, y1, z); val bottom = Vec3(x, y0, z)
        for (i in 0 until segments) {
            val a0 = ring(i, r0, y0); val b0 = ring(i + 1, r0, y0); val a1 = ring(i, r1, y1); val b1 = ring(i + 1, r1, y1)
            if (r1 > 0) quad(a0, b0, b1, a1) else triangle(a0, b0, top)
            if (r1 > 0) triangle(top, a1, b1)
            triangle(bottom, b0, a0)
        }
    }

    /** A faceted sphere; [upper] keeps only the top half (a dome), capped flat. */
    fun sphere(c: Vec3, radius: Float, rings: Int, segments: Int, upper: Boolean = false) {
        fun p(i: Int, j: Int): Vec3 {
            val theta = i.toFloat() / rings * PI.toFloat()
            val phi = j.toFloat() / segments * 2f * PI.toFloat()
            return Vec3(c.x + radius * sin(theta) * sin(phi), c.y + radius * cos(theta), c.z + radius * sin(theta) * cos(phi))
        }
        val last = if (upper) rings / 2 else rings
        for (i in 0 until last) for (j in 0 until segments) {
            val a = p(i, j); val b = p(i + 1, j); val cc = p(i + 1, j + 1); val d = p(i, j + 1)
            when (i) {
                0 -> triangle(a, b, cc)
                rings - 1 -> triangle(a, b, d)
                else -> quad(a, b, cc, d)
            }
        }
        if (upper) for (j in 0 until segments) triangle(c, p(last, j + 1), p(last, j))
    }

    /** A flat ring on the ground plane, facing up. */
    fun annulus(inner: Float, outer: Float, y: Float, segments: Int) {
        for (i in 0 until segments) {
            val a0 = i.toFloat() / segments * 2f * PI.toFloat(); val a1 = (i + 1).toFloat() / segments * 2f * PI.toFloat()
            fun p(r: Float, a: Float) = Vec3(r * sin(a), y, r * cos(a))
            quad(p(inner, a0), p(outer, a0), p(outer, a1), p(inner, a1))
        }
    }

    // ---------------------------------------------------------------- output

    val usedSlots: List<Int> get() = slots.keys.toList()

    /** One part per slot, in slot order. */
    fun parts(): List<MeshData> = slots.values.map { part ->
        val p = part.pos.toFloatArray()
        var min = Vec3(Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE)
        var max = Vec3(-Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE)
        for (i in p.indices step 3) {
            min = Vec3(minOf(min.x, p[i]), minOf(min.y, p[i + 1]), minOf(min.z, p[i + 2]))
            max = Vec3(maxOf(max.x, p[i]), maxOf(max.y, p[i + 1]), maxOf(max.z, p[i + 2]))
        }
        MeshData(p, part.nrm.toFloatArray(), IntArray(p.size / 3) { it }, min, max)
    }

    companion object {
        fun translation(x: Float, y: Float, z: Float) = FloatArray(16).also { Matrix.setIdentityM(it, 0); Matrix.translateM(it, 0, x, y, z) }

        fun rotation(angle: Float, x: Float, y: Float, z: Float) =
            FloatArray(16).also { Matrix.setRotateM(it, 0, Math.toDegrees(angle.toDouble()).toFloat(), x, y, z) }

        fun times(a: FloatArray, b: FloatArray) = FloatArray(16).also { Matrix.multiplyMM(it, 0, a, 0, b, 0) }
    }
}
