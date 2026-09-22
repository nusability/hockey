package `in`.nann.smashhockey.engine

import android.opengl.Matrix
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Flat-shaded low-poly geometry built from primitives — the twin of iOS's MeshKit.swift, same
 * shapes and facet counts, so a shape is the same shape on both platforms. Each triangle
 * carries its face normal unless given smooth ones. Parts are grouped by material slot: one mesh part per slot.
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

    /** A triangle with its own vertex normals (a smooth surface), counter-clockwise from its front. */
    fun triangle(a: Vec3, b: Vec3, c: Vec3, na: Vec3, nb: Vec3, nc: Vec3) {
        val pa = point(a); val pb = point(b); val pc = point(c)
        val n = (pb - pa).cross(pc - pa)
        if (sqrt(n.dot(n)) < 1e-9f) return
        val part = slots.getOrPut(slot) { Part() }
        for ((p, v) in listOf(pa to na, pb to nb, pc to nc)) {
            val d = direction(v)
            part.pos += p.x; part.pos += p.y; part.pos += p.z
            part.nrm += d.x; part.nrm += d.y; part.nrm += d.z
        }
    }

    private fun point(p: Vec3): Vec3 {
        val r = FloatArray(4)
        Matrix.multiplyMV(r, 0, transform, 0, floatArrayOf(p.x, p.y, p.z, 1f), 0)
        return Vec3(r[0], r[1], r[2])
    }

    private fun direction(n: Vec3): Vec3 {
        val r = FloatArray(4)
        Matrix.multiplyMV(r, 0, transform, 0, floatArrayOf(n.x, n.y, n.z, 0f), 0)
        val len = sqrt(r[0] * r[0] + r[1] * r[1] + r[2] * r[2])
        return Vec3(r[0] / len, r[1] / len, r[2] / len)
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

    /**
     * A smooth-sided frustum along +y from [y0] (radius [r0]) to [y1] (radius [r1]): its side's
     * normals run round it like the prototype's cylinders; [top] and [bottom] add flat caps.
     */
    fun cylinder(y0: Float, y1: Float, r0: Float, r1: Float, segments: Int, top: Boolean = true, bottom: Boolean = true) {
        val slope = (r0 - r1) / (y1 - y0)
        fun s(i: Int) = sin(i.toFloat() / segments * 2f * PI.toFloat())
        fun c(i: Int) = cos(i.toFloat() / segments * 2f * PI.toFloat())
        for (i in 0 until segments) {
            val s0 = s(i); val c0 = c(i); val s1 = s(i + 1); val c1 = c(i + 1)
            val a0 = Vec3(r0 * s0, y0, r0 * c0); val b0 = Vec3(r0 * s1, y0, r0 * c1)
            val a1 = Vec3(r1 * s0, y1, r1 * c0); val b1 = Vec3(r1 * s1, y1, r1 * c1)
            val n0 = Vec3(s0, slope, c0); val n1 = Vec3(s1, slope, c1)
            triangle(a0, b0, b1, n0, n1, n1)
            triangle(a0, b1, a1, n0, n1, n0)
            if (top) triangle(Vec3(0f, y1, 0f), a1, b1)
            if (bottom) triangle(Vec3(0f, y0, 0f), b0, a0)
        }
    }

    /** A smooth sphere (the prototype's ball), [rings] from pole to pole. */
    fun smoothSphere(c: Vec3, radius: Float, rings: Int, segments: Int) {
        fun n(i: Int, j: Int): Vec3 {
            val theta = i.toFloat() / rings * PI.toFloat()
            val phi = j.toFloat() / segments * 2f * PI.toFloat()
            return Vec3(sin(theta) * sin(phi), cos(theta), sin(theta) * cos(phi))
        }
        fun p(v: Vec3) = Vec3(c.x + radius * v.x, c.y + radius * v.y, c.z + radius * v.z)
        for (i in 0 until rings) for (j in 0 until segments) {
            val na = n(i, j); val nb = n(i + 1, j); val nc = n(i + 1, j + 1); val nd = n(i, j + 1)
            if (i > 0) triangle(p(na), p(nb), p(nd), na, nb, nd)
            if (i < rings - 1) triangle(p(nd), p(nb), p(nc), nd, nb, nc)
        }
    }

    /** A flat disc on the ground plane, facing up. */
    fun disc(radius: Float, y: Float, segments: Int) = annulus(0f, radius, y, segments)

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
