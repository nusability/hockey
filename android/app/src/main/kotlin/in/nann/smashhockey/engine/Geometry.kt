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

/**
 * A [MeshKit]'s parts uploaded once and shared by every renderable drawn with them (twelve players,
 * one outfield mesh) — each renderable brings its own material instance per part.
 */
class Geometry(private val engine: Engine, kit: MeshKit) {
    private val buffers: List<Pair<VertexBuffer, IndexBuffer>>
    private val bounds: Box
    private val entities = ArrayList<Int>()
    val partCount: Int

    init {
        val parts = kit.parts()
        partCount = parts.size
        buffers = parts.map { upload(it) }
        var lo = floatArrayOf(Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE)
        var hi = floatArrayOf(-Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE)
        for (p in parts) {
            lo = floatArrayOf(minOf(lo[0], p.min.x), minOf(lo[1], p.min.y), minOf(lo[2], p.min.z))
            hi = floatArrayOf(maxOf(hi[0], p.max.x), maxOf(hi[1], p.max.y), maxOf(hi[2], p.max.z))
        }
        bounds = Box((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2,
            (hi[0] - lo[0]) / 2 + 0.01f, (hi[1] - lo[1]) / 2 + 0.01f, (hi[2] - lo[2]) / 2 + 0.01f)
    }

    /** A new renderable entity drawing these parts with [materials] (one per part, in slot order). */
    fun renderable(materials: List<MaterialInstance>, shadows: Boolean, priority: Int = 4): Int {
        require(materials.size == partCount) { "Geometry: ${materials.size} materials for $partCount parts" }
        val entity = EntityManager.get().create()
        val b = RenderableManager.Builder(partCount).boundingBox(bounds).castShadows(shadows).receiveShadows(shadows)
            .priority(priority)
        buffers.forEachIndexed { i, (vb, ib) ->
            b.geometry(i, RenderableManager.PrimitiveType.TRIANGLES, vb, ib).material(i, materials[i])
        }
        b.build(engine, entity)
        entities += entity
        return entity
    }

    fun destroy() {
        entities.forEach { engine.destroyEntity(it); EntityManager.get().destroy(it) }
        buffers.forEach { (vb, ib) -> engine.destroyVertexBuffer(vb); engine.destroyIndexBuffer(ib) }
    }

    private fun upload(data: MeshData): Pair<VertexBuffer, IndexBuffer> {
        val n = data.vertexCount
        val positions = direct(n * 12).also { b -> data.positions.forEach { b.putFloat(it) }; b.flip() }
        val normals = direct(n * 12).also { b -> data.normals.forEach { b.putFloat(it) }; b.flip() }
        val quats = direct(n * 16)
        SurfaceOrientation.Builder().vertexCount(n).normals(normals.asFloatBuffer()).build()
            .getQuatsAsFloat(quats.asFloatBuffer())
        val vb = VertexBuffer.Builder().bufferCount(2).vertexCount(n)
            .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 12)
            .attribute(VertexBuffer.VertexAttribute.TANGENTS, 1, VertexBuffer.AttributeType.FLOAT4, 0, 16)
            .build(engine)
        vb.setBufferAt(engine, 0, positions)
        vb.setBufferAt(engine, 1, quats)
        val indices = direct(data.indices.size * 4).also { b -> data.indices.forEach { b.putInt(it) }; b.flip() }
        val ib = IndexBuffer.Builder().indexCount(data.indices.size).bufferType(IndexBuffer.Builder.IndexType.UINT).build(engine)
        ib.setBuffer(engine, indices)
        return vb to ib
    }

    private fun direct(bytes: Int): ByteBuffer = ByteBuffer.allocateDirect(bytes).order(ByteOrder.nativeOrder())
}
