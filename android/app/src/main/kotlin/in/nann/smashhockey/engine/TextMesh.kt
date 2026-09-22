package `in`.nann.smashhockey.engine

import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import earcut4j.Earcut
import `in`.nann.smashhockey.core.feel.TextLayout
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Extruded 3D lettering from the shared font (ADR 0005). The outline comes from the platform's
 * own font engine — the same outlines RealityKit's `generateText` reads on iOS — flattened,
 * sorted into shapes with holes, triangulated with earcut, and extruded.
 *
 * Output is in metres, **in the font's own space**: the pen starts at x = 0 on a baseline at
 * y = 0, [height] is the cap height the text is laid out at, and the front face points down +Z.
 * The mesh is deliberately *not* centred on its own ink: where a string sits is decided by the
 * core's `TextLayout` from the font's metrics, so the two platforms place a word the same way
 * whatever their meshers report (see `Kit.text`).
 */
object TextMesh {
    private const val LAYOUT_SIZE = 100f      // text is laid out at 100 px, then scaled
    private const val FLATNESS = 0.35f        // px of error allowed when flattening curves

    fun build(text: String, typeface: Typeface, height: Float, depth: Float): MeshData {
        val paint = Paint().apply {
            this.typeface = typeface
            textSize = LAYOUT_SIZE
        }
        val path = Path()
        paint.getTextPath(text, 0, text.length, 0f, 0f, path)
        // One em is TextLayout.em(height) metres, and the path is laid out at LAYOUT_SIZE px per em.
        val scale = (TextLayout.em(height.toDouble()) / LAYOUT_SIZE).toFloat()
        val contours = contoursOf(path, scale)
        val shapes = shapesOf(contours)
        return extrude(shapes, depth)
    }

    /** Splits [Path.approximate]'s point list into closed contours (y flipped to point up). */
    private fun contoursOf(path: Path, scale: Float): List<List<Vec2>> {
        val pts = path.approximate(FLATNESS)
        val contours = mutableListOf<MutableList<Vec2>>()
        var current = mutableListOf<Vec2>()
        var previousFraction = -1f
        var i = 0
        while (i < pts.size) {
            val fraction = pts[i]
            val p = Vec2(pts[i + 1] * scale, -pts[i + 2] * scale)
            // Two consecutive points with the same fraction mark a jump to a new contour.
            if (i > 0 && fraction == previousFraction && current.isNotEmpty()) {
                contours += current
                current = mutableListOf()
            }
            if (current.isEmpty() || current.last().distanceTo(p) > 1e-5f) current += p
            previousFraction = fraction
            i += 3
        }
        contours += current
        return contours
            .map { c -> if (c.size > 1 && c.first().distanceTo(c.last()) < 1e-5f) c.dropLast(1) else c }
            .filter { it.size >= 3 && abs(signedArea(it)) > 1e-7f }
    }

    private class Shape(val outer: List<Vec2>, val holes: MutableList<List<Vec2>> = mutableListOf())

    /**
     * Groups contours into outer shapes and their holes by nesting depth, not by winding: a
     * contour inside an odd number of others is a hole of the smallest contour containing it.
     * Outers are made counter-clockwise and holes clockwise, so solid is always on the left.
     */
    private fun shapesOf(contours: List<List<Vec2>>): List<Shape> {
        val depth = contours.map { c -> contours.count { o -> o !== c && contains(o, c[0]) } }
        val shapes = mutableMapOf<Int, Shape>()
        contours.forEachIndexed { i, c ->
            if (depth[i] % 2 == 0) shapes[i] = Shape(orient(c, ccw = true))
        }
        contours.forEachIndexed { i, c ->
            if (depth[i] % 2 == 1) {
                val parent = contours.indices
                    .filter { depth[it] == depth[i] - 1 && contains(contours[it], c[0]) }
                    .minByOrNull { abs(signedArea(contours[it])) }
                    ?: return@forEachIndexed
                shapes[parent]?.holes?.add(orient(c, ccw = false))
            }
        }
        return shapes.values.toList()
    }

    private fun extrude(shapes: List<Shape>, depth: Float): MeshData {
        val out = MeshBuilder()
        val front = depth / 2f
        val back = -depth / 2f
        for (shape in shapes) {
            val rings = listOf(shape.outer) + shape.holes
            val flat = DoubleArray(rings.sumOf { it.size } * 2)
            val holeStarts = IntArray(shape.holes.size)
            var k = 0
            rings.forEachIndexed { r, ring ->
                if (r > 0) holeStarts[r - 1] = k / 2
                for (p in ring) { flat[k++] = p.x.toDouble(); flat[k++] = p.y.toDouble() }
            }
            val all = rings.flatten()
            val tris = Earcut.earcut(flat, if (holeStarts.isEmpty()) null else holeStarts, 2)
            for (t in tris.indices step 3) {
                val a = all[tris[t]]; val b = all[tris[t + 1]]; val c = all[tris[t + 2]]
                out.triangle(Vec3(a.x, a.y, front), Vec3(b.x, b.y, front), Vec3(c.x, c.y, front), Vec3(0f, 0f, 1f))
                out.triangle(Vec3(a.x, a.y, back), Vec3(c.x, c.y, back), Vec3(b.x, b.y, back), Vec3(0f, 0f, -1f))
            }
            for (ring in rings) {
                for (j in ring.indices) {
                    val a = ring[j]; val b = ring[(j + 1) % ring.size]
                    val dx = b.x - a.x; val dy = b.y - a.y
                    val len = sqrt(dx * dx + dy * dy)
                    if (len < 1e-7f) continue
                    val n = Vec3(dy / len, -dx / len, 0f)          // solid is on the left: outward is right
                    out.quad(Vec3(a.x, a.y, front), Vec3(b.x, b.y, front), Vec3(b.x, b.y, back), Vec3(a.x, a.y, back), n)
                }
            }
        }
        return out.build()
    }

    private fun signedArea(c: List<Vec2>): Float {
        var s = 0f
        for (i in c.indices) { val a = c[i]; val b = c[(i + 1) % c.size]; s += a.x * b.y - b.x * a.y }
        return s / 2f
    }

    private fun orient(c: List<Vec2>, ccw: Boolean): List<Vec2> =
        if ((signedArea(c) > 0) == ccw) c else c.reversed()

    private fun contains(poly: List<Vec2>, p: Vec2): Boolean {
        var inside = false
        var j = poly.size - 1
        for (i in poly.indices) {
            val a = poly[i]; val b = poly[j]
            if ((a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) inside = !inside
            j = i
        }
        return inside
    }
}
