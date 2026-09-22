package `in`.nann.smashhockey.ui

import android.graphics.Typeface
import android.util.SparseArray
import com.google.android.filament.Box
import com.google.android.filament.Colors
import com.google.android.filament.Engine
import com.google.android.filament.IndexBuffer
import com.google.android.filament.Material
import com.google.android.filament.MaterialInstance
import com.google.android.filament.RenderableManager
import com.google.android.filament.Scene
import com.google.android.filament.SurfaceOrientation
import com.google.android.filament.VertexBuffer
import `in`.nann.smashhockey.engine.Assets
import `in`.nann.smashhockey.engine.MeshData
import `in`.nann.smashhockey.engine.MeshKit
import `in`.nann.smashhockey.engine.TextMesh
import `in`.nann.smashhockey.engine.Vec3
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.sqrt

/**
 * How the UI is painted: one material, one instance per (colour, opacity step), made once and
 * reused. This is the only place the kit touches a material — when the look stream replaces
 * `ui_lit`, [instance] is the function to change.
 */
class Palette(private val engine: Engine, assets: Assets) {
    private val material: Material = assets.material(engine, "ui_lit")
    private val instances = SparseArray<MaterialInstance>()

    /** The instance painting [rgb] (sRGB 0xRRGGBB) at [alpha]; opaque ones write depth. */
    fun instance(rgb: Int, alpha: Float): MaterialInstance {
        val level = level(alpha)
        val key = (level shl 24) or (rgb and 0xFFFFFF)
        instances[key]?.let { return it }
        val a = level.toFloat() / LEVELS
        val c = Colors.toLinear(Colors.RgbType.SRGB, ((rgb shr 16) and 0xFF) / 255f, ((rgb shr 8) and 0xFF) / 255f, (rgb and 0xFF) / 255f)
        val mi = material.createInstance().apply {
            setParameter("baseColor", Colors.RgbType.LINEAR, c[0], c[1], c[2])
            setParameter("alpha", a)
            setDepthWrite(level == LEVELS)     // solid blocks occlude each other; fading ones don't
        }
        instances.put(key, mi)
        return mi
    }

    fun destroy() {
        for (i in 0 until instances.size()) engine.destroyMaterialInstance(instances.valueAt(i))
        instances.clear()
        engine.destroyMaterial(material)
    }

    companion object {
        /** Opacity is quantised to twentieths, so a fade reuses a handful of instances. */
        const val LEVELS = 20
        fun level(alpha: Float): Int = (alpha.coerceIn(0f, 1f) * LEVELS + 0.5f).toInt()
    }
}

/** Geometry uploaded once and drawn by any number of nodes (a flip digit, a slab size). */
class SharedMesh internal constructor(engine: Engine, data: MeshData) {
    val minX = data.min.x; val minY = data.min.y; val minZ = data.min.z
    val maxX = data.max.x; val maxY = data.max.y; val maxZ = data.max.z
    val width get() = maxX - minX
    internal val vertexBuffer: VertexBuffer
    internal val indexBuffer: IndexBuffer
    internal val indexCount: Int
    internal val box = Box((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2,
        (maxX - minX) / 2 + 0.01f, (maxY - minY) / 2 + 0.01f, (maxZ - minZ) / 2 + 0.01f)

    init {
        // An empty string still gets a (degenerate) triangle, so every node draws something valid.
        val positions = if (data.vertexCount > 0) data.positions else FloatArray(9)
        val normals = if (data.vertexCount > 0) data.normals else floatArrayOf(0f, 0f, 1f, 0f, 0f, 1f, 0f, 0f, 1f)
        val indices = if (data.vertexCount > 0) data.indices else intArrayOf(0, 1, 2)
        val n = positions.size / 3
        val pos = direct(n * 12).also { b -> positions.forEach { b.putFloat(it) }; b.flip() }
        val nrm = direct(n * 12).also { b -> normals.forEach { b.putFloat(it) }; b.flip() }
        val quats = direct(n * 16)
        SurfaceOrientation.Builder().vertexCount(n).normals(nrm.asFloatBuffer()).build().getQuatsAsFloat(quats.asFloatBuffer())
        vertexBuffer = VertexBuffer.Builder().bufferCount(2).vertexCount(n)
            .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 12)
            .attribute(VertexBuffer.VertexAttribute.TANGENTS, 1, VertexBuffer.AttributeType.FLOAT4, 0, 16)
            .build(engine)
        vertexBuffer.setBufferAt(engine, 0, pos)
        vertexBuffer.setBufferAt(engine, 1, quats)
        indexCount = indices.size
        val idx = direct(indices.size * 4).also { b -> indices.forEach { b.putInt(it) }; b.flip() }
        indexBuffer = IndexBuffer.Builder().indexCount(indices.size).bufferType(IndexBuffer.Builder.IndexType.UINT).build(engine)
        indexBuffer.setBuffer(engine, idx)
    }

    internal fun destroy(engine: Engine) {
        engine.destroyVertexBuffer(vertexBuffer)
        engine.destroyIndexBuffer(indexBuffer)
    }

    private fun direct(bytes: Int): ByteBuffer = ByteBuffer.allocateDirect(bytes).order(ByteOrder.nativeOrder())
}

/**
 * The UI's building blocks — the twin of iOS's `Blocks`: rounded slabs, discs and lettering, each
 * mesh made once per size (per string, for text) and shared by every node that draws it, and the
 * nodes themselves. UI renderables never cast or receive shadows (ADR 0005).
 */
class Kit(val engine: Engine, val scene: Scene, assets: Assets, private val typeface: Typeface, val motion: Motion) {
    val palette = Palette(engine, assets)
    private val boxes = HashMap<BoxKey, SharedMesh>()
    private val texts = HashMap<TextKey, SharedMesh>()
    private val shapes = HashMap<String, SharedMesh>()
    private val nodes = ArrayList<UiNode>(512)
    private val dirty = ArrayList<UiNode>(256)
    private val scratch = FloatArray(16)

    private data class BoxKey(val w: Float, val h: Float, val d: Float, val r: Float)
    private data class TextKey(val text: String, val height: Float, val depth: Float)

    // ------------------------------------------------------------------ nodes

    /** An empty node under [parent] (or under a raw Filament entity, e.g. the camera). */
    fun node(parent: UiNode?, parentEntity: Int? = null): UiNode = UiNode(this, parent, parentEntity, null, 0).also { nodes += it }

    fun model(mesh: SharedMesh, rgb: Int, parent: UiNode?): UiNode = UiNode(this, parent, null, mesh, rgb).also { nodes += it }

    /** A rounded slab of size (w, h, d), centred. */
    fun slab(w: Float, h: Float, d: Float, rgb: Int, parent: UiNode?, corner: Float = DesignTokens.Size.CORNER): UiNode =
        model(box(w, h, d, corner), rgb, parent)

    /** A disc of [radius] and [height] along its Y axis, centred. */
    fun cylinder(height: Float, radius: Float, rgb: Int, parent: UiNode?): UiNode =
        model(shapes.getOrPut("c$height/$radius") {
            SharedMesh(engine, MeshKit().apply { frustum(y0 = -height / 2, y1 = height / 2, r0 = radius, r1 = radius, segments = 28) }.parts()[0])
        }, rgb, parent)

    fun sphere(radius: Float, rgb: Int, parent: UiNode?): UiNode =
        model(shapes.getOrPut("s$radius") {
            SharedMesh(engine, MeshKit().apply { sphere(Vec3(0f, 0f, 0f), radius, 12, 18) }.parts()[0])
        }, rgb, parent)

    /**
     * Centred extruded lettering with its back face on z = 0 and its front toward +Z. Depth
     * follows the height by token.
     */
    fun text(s: String, height: Float, rgb: Int, parent: UiNode?): UiNode =
        model(textMesh(s, height), rgb, parent).also { centre(it) }

    /** Replaces a text node's string in place, keeping it centred. Cached meshes: no re-meshing. */
    fun retext(node: UiNode, s: String, height: Float) {
        node.remesh(textMesh(s, height))
        centre(node)
    }

    fun width(node: UiNode): Float = node.mesh?.width ?: 0f

    private fun centre(node: UiNode) {
        val m = node.mesh ?: return
        node.setPosition(-(m.minX + m.maxX) / 2, -(m.minY + m.maxY) / 2, -m.minZ)
    }

    private fun textMesh(s: String, height: Float): SharedMesh {
        val depth = height * DesignTokens.Size.TEXT_DEPTH_RATIO
        return texts.getOrPut(TextKey(s, height, depth)) { SharedMesh(engine, TextMesh.build(s, typeface, height, depth)) }
    }

    private fun box(w: Float, h: Float, d: Float, corner: Float): SharedMesh {
        val r = minOf(corner, w / 2, h / 2, d / 2)
        return boxes.getOrPut(BoxKey(w, h, d, r)) { SharedMesh(engine, RoundedBox.build(w, h, d, r)) }
    }

    // ------------------------------------------------------------------ Filament plumbing

    internal fun buildRenderable(entity: Int, mesh: SharedMesh, mi: MaterialInstance) {
        RenderableManager.Builder(1)
            .boundingBox(mesh.box)
            .geometry(0, RenderableManager.PrimitiveType.TRIANGLES, mesh.vertexBuffer, mesh.indexBuffer, 0, mesh.indexCount)
            .material(0, mi)
            .castShadows(false)
            .receiveShadows(false)
            .build(engine, entity)
        scene.addEntity(entity)
    }

    internal fun swapGeometry(entity: Int, mesh: SharedMesh) {
        val rm = engine.renderableManager
        val ri = rm.getInstance(entity)
        rm.setGeometryAt(ri, 0, RenderableManager.PrimitiveType.TRIANGLES, mesh.vertexBuffer, mesh.indexBuffer, 0, mesh.indexCount)
        rm.setAxisAlignedBoundingBox(ri, mesh.box)
    }

    internal fun markDirty(node: UiNode) { dirty += node }

    /** Writes every changed transform to Filament — once per frame, after all motion ran. */
    fun flush() {
        for (i in 0 until dirty.size) dirty[i].commit(scratch)
        dirty.clear()
    }

    fun destroy() {
        for (i in nodes.indices.reversed()) nodes[i].destroy()
        nodes.clear()
        dirty.clear()
        (boxes.values + texts.values + shapes.values).forEach { it.destroy(engine) }
        boxes.clear(); texts.clear(); shapes.clear()
        palette.destroy()
    }
}

/**
 * A box with rounded edges and corners and smooth normals — RealityKit's
 * `generateBox(cornerRadius:)`. Each face is a grid whose outer rows wrap round the edges: every
 * grid point is pushed out from the box shrunk by [r] onto the rounding radius.
 */
internal object RoundedBox {
    private const val ARC = 3     // segments per quarter round

    fun build(w: Float, h: Float, d: Float, r: Float): MeshData {
        val half = floatArrayOf(w / 2, h / 2, d / 2)
        val coords = Array(3) { axis(half[it], r) }
        val pos = ArrayList<Float>(1200); val nrm = ArrayList<Float>(1200); val idx = ArrayList<Int>(1800)
        val p = FloatArray(3)
        var vertex = 0
        for (axis in 0..2) for (sign in intArrayOf(-1, 1)) {
            val a = (axis + 1) % 3; val b = (axis + 2) % 3
            val ca = coords[a]; val cb = coords[b]
            val base = vertex
            for (i in ca.indices) for (j in cb.indices) {
                p[axis] = sign * half[axis]; p[a] = ca[i]; p[b] = cb[j]
                var nx = 0f; var ny = 0f; var nz = 0f
                val inner = FloatArray(3) { c -> p[c].coerceIn(-(half[c] - r), half[c] - r) }
                val dx = p[0] - inner[0]; val dy = p[1] - inner[1]; val dz = p[2] - inner[2]
                val len = sqrt(dx * dx + dy * dy + dz * dz)
                if (len > 1e-7f) { nx = dx / len; ny = dy / len; nz = dz / len } else when (axis) {
                    0 -> nx = sign.toFloat(); 1 -> ny = sign.toFloat(); else -> nz = sign.toFloat()
                }
                pos += inner[0] + nx * r; pos += inner[1] + ny * r; pos += inner[2] + nz * r
                nrm += nx; nrm += ny; nrm += nz
                vertex++
            }
            for (i in 0 until ca.size - 1) for (j in 0 until cb.size - 1) {
                val v00 = base + i * cb.size + j; val v10 = v00 + cb.size; val v01 = v00 + 1; val v11 = v10 + 1
                if (sign > 0) { idx += v00; idx += v10; idx += v11; idx += v00; idx += v11; idx += v01 }
                else { idx += v00; idx += v11; idx += v10; idx += v00; idx += v01; idx += v11 }
            }
        }
        return MeshData(pos.toFloatArray(), nrm.toFloatArray(), idx.toIntArray(),
            Vec3(-half[0], -half[1], -half[2]), Vec3(half[0], half[1], half[2]))
    }

    /** Grid lines along one axis: through each rounded end in [ARC] steps, flat in between. */
    private fun axis(half: Float, r: Float): FloatArray {
        if (r <= 1e-6f) return floatArrayOf(-half, half)
        val out = ArrayList<Float>()
        for (i in 0..ARC) out += -half + r * i / ARC
        for (i in 0..ARC) out += (half - r) + r * i / ARC
        val dedup = ArrayList<Float>()
        for (v in out) if (dedup.isEmpty() || v - dedup.last() > 1e-6f) dedup += v
        return dedup.toFloatArray()
    }
}
