package `in`.nann.smashhockey.engine

import com.google.android.filament.Box
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.IndexBuffer
import com.google.android.filament.MaterialInstance
import com.google.android.filament.RenderableManager
import com.google.android.filament.SurfaceOrientation
import com.google.android.filament.VertexBuffer
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.sqrt

data class Vec2(val x: Float, val y: Float) {
    fun distanceTo(o: Vec2): Float { val dx = x - o.x; val dy = y - o.y; return sqrt(dx * dx + dy * dy) }
}

data class Vec3(val x: Float, val y: Float, val z: Float) {
    operator fun minus(o: Vec3) = Vec3(x - o.x, y - o.y, z - o.z)
    fun cross(o: Vec3) = Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    fun dot(o: Vec3) = x * o.x + y * o.y + z * o.z
}

/** Flat-shaded triangle soup with per-vertex normals, and its local bounds. */
class MeshData(val positions: FloatArray, val normals: FloatArray, val indices: IntArray, val min: Vec3, val max: Vec3) {
    val vertexCount get() = positions.size / 3
}

class MeshBuilder {
    private val pos = ArrayList<Float>()
    private val nrm = ArrayList<Float>()

    /** Adds a triangle facing [n], fixing its winding if it was given the other way round. */
    fun triangle(a: Vec3, b: Vec3, c: Vec3, n: Vec3) {
        val facing = (b - a).cross(c - a).dot(n)
        if (abs(facing) < 1e-12f) return
        val (p1, p2) = if (facing > 0) b to c else c to b
        for (p in listOf(a, p1, p2)) { pos += p.x; pos += p.y; pos += p.z; nrm += n.x; nrm += n.y; nrm += n.z }
    }

    fun quad(a: Vec3, b: Vec3, c: Vec3, d: Vec3, n: Vec3) { triangle(a, b, c, n); triangle(a, c, d, n) }

    /** An axis-aligned box centred on the origin. */
    fun box(sx: Float, sy: Float, sz: Float): MeshBuilder {
        val x = sx / 2; val y = sy / 2; val z = sz / 2
        quad(Vec3(-x, -y, z), Vec3(x, -y, z), Vec3(x, y, z), Vec3(-x, y, z), Vec3(0f, 0f, 1f))
        quad(Vec3(x, -y, -z), Vec3(-x, -y, -z), Vec3(-x, y, -z), Vec3(x, y, -z), Vec3(0f, 0f, -1f))
        quad(Vec3(-x, y, z), Vec3(x, y, z), Vec3(x, y, -z), Vec3(-x, y, -z), Vec3(0f, 1f, 0f))
        quad(Vec3(-x, -y, -z), Vec3(x, -y, -z), Vec3(x, -y, z), Vec3(-x, -y, z), Vec3(0f, -1f, 0f))
        quad(Vec3(x, -y, z), Vec3(x, -y, -z), Vec3(x, y, -z), Vec3(x, y, z), Vec3(1f, 0f, 0f))
        quad(Vec3(-x, -y, -z), Vec3(-x, -y, z), Vec3(-x, y, z), Vec3(-x, y, -z), Vec3(-1f, 0f, 0f))
        return this
    }

    fun build(centre: Boolean = false): MeshData {
        val p = pos.toFloatArray()
        var min = Vec3(Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE)
        var max = Vec3(-Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE)
        for (i in p.indices step 3) {
            min = Vec3(minOf(min.x, p[i]), minOf(min.y, p[i + 1]), minOf(min.z, p[i + 2]))
            max = Vec3(maxOf(max.x, p[i]), maxOf(max.y, p[i + 1]), maxOf(max.z, p[i + 2]))
        }
        if (p.isEmpty()) { min = Vec3(0f, 0f, 0f); max = min }
        if (centre && p.isNotEmpty()) {
            val cx = (min.x + max.x) / 2; val cy = (min.y + max.y) / 2
            for (i in p.indices step 3) { p[i] -= cx; p[i + 1] -= cy }
            min = Vec3(min.x - cx, min.y - cy, min.z); max = Vec3(max.x - cx, max.y - cy, max.z)
        }
        return MeshData(p, nrm.toFloatArray(), IntArray(p.size / 3) { it }, min, max)
    }
}

/** A mesh uploaded to Filament as one renderable entity. Destroy it when it is replaced. */
class GpuMesh(private val engine: Engine, data: MeshData, material: MaterialInstance) {
    val entity: Int = EntityManager.get().create()
    val min = data.min
    val max = data.max
    private val vertexBuffer: VertexBuffer
    private val indexBuffer: IndexBuffer

    init {
        val n = data.vertexCount
        val positions = direct(n * 12).also { b -> data.positions.forEach { b.putFloat(it) }; b.flip() }
        val normals = direct(n * 12).also { b -> data.normals.forEach { b.putFloat(it) }; b.flip() }
        val quats = direct(n * 16)
        SurfaceOrientation.Builder().vertexCount(n).normals(normals.asFloatBuffer()).build()
            .getQuatsAsFloat(quats.asFloatBuffer())
        vertexBuffer = VertexBuffer.Builder()
            .bufferCount(2)
            .vertexCount(n)
            .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 12)
            .attribute(VertexBuffer.VertexAttribute.TANGENTS, 1, VertexBuffer.AttributeType.FLOAT4, 0, 16)
            .build(engine)
        vertexBuffer.setBufferAt(engine, 0, positions)
        vertexBuffer.setBufferAt(engine, 1, quats)
        val indices = direct(data.indices.size * 4).also { b -> data.indices.forEach { b.putInt(it) }; b.flip() }
        indexBuffer = IndexBuffer.Builder()
            .indexCount(data.indices.size)
            .bufferType(IndexBuffer.Builder.IndexType.UINT)
            .build(engine)
        indexBuffer.setBuffer(engine, indices)
        val cx = (min.x + max.x) / 2; val cy = (min.y + max.y) / 2; val cz = (min.z + max.z) / 2
        RenderableManager.Builder(1)
            .boundingBox(Box(cx, cy, cz, (max.x - min.x) / 2 + 0.01f, (max.y - min.y) / 2 + 0.01f, (max.z - min.z) / 2 + 0.01f))
            .geometry(0, RenderableManager.PrimitiveType.TRIANGLES, vertexBuffer, indexBuffer)
            .material(0, material)
            .castShadows(false)
            .receiveShadows(false)
            .build(engine, entity)
    }

    fun destroy() {
        engine.destroyEntity(entity)
        engine.destroyVertexBuffer(vertexBuffer)
        engine.destroyIndexBuffer(indexBuffer)
        EntityManager.get().destroy(entity)
    }

    private fun direct(bytes: Int): ByteBuffer = ByteBuffer.allocateDirect(bytes).order(ByteOrder.nativeOrder())
}
