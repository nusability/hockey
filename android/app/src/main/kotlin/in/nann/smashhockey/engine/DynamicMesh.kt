package `in`.nann.smashhockey.engine

import com.google.android.filament.Box
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.IndexBuffer
import com.google.android.filament.MaterialInstance
import com.google.android.filament.RenderableManager
import com.google.android.filament.VertexBuffer
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * A mesh whose vertices move every frame (the ball's trail, the rippling nets): positions (and an
 * optional uv0) rewritten in place, its triangles fixed, how many of them are drawn set per frame.
 * Unlit materials only — it carries no tangents. [bounds] is a generous fixed box (centre, half-extent).
 */
class DynamicMesh(
    private val engine: Engine,
    val vertexCapacity: Int,
    indices: IntArray,
    material: MaterialInstance,
    withUv: Boolean,
    bounds: Box,
    priority: Int = 6,
) {
    val entity: Int = EntityManager.get().create()
    private val vb: VertexBuffer
    private val ib: IndexBuffer
    private val positions = direct(vertexCapacity * 12)
    private val uvs = if (withUv) direct(vertexCapacity * 8) else null
    private val indexCount = indices.size

    init {
        val b = VertexBuffer.Builder().bufferCount(if (withUv) 2 else 1).vertexCount(vertexCapacity)
            .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, 12)
        if (withUv) b.attribute(VertexBuffer.VertexAttribute.UV0, 1, VertexBuffer.AttributeType.FLOAT2, 0, 8)
        vb = b.build(engine)
        val ibuf = direct(indices.size * 4).also { buf -> indices.forEach { buf.putInt(it) }; buf.flip() }
        ib = IndexBuffer.Builder().indexCount(indices.size).bufferType(IndexBuffer.Builder.IndexType.UINT).build(engine)
        ib.setBuffer(engine, ibuf)
        update(FloatArray(vertexCapacity * 3), if (withUv) FloatArray(vertexCapacity * 2) else null)
        RenderableManager.Builder(1)
            .boundingBox(bounds)
            .geometry(0, RenderableManager.PrimitiveType.TRIANGLES, vb, ib)
            .material(0, material)
            .castShadows(false).receiveShadows(false)
            .priority(priority)
            .build(engine, entity)
    }

    /** Rewrites every vertex: xyz per vertex, and uv per vertex when the mesh has them. */
    fun update(xyz: FloatArray, uv: FloatArray? = null) {
        positions.clear(); xyz.forEach { positions.putFloat(it) }; positions.flip()
        vb.setBufferAt(engine, 0, positions)
        if (uv != null && uvs != null) {
            uvs.clear(); uv.forEach { uvs.putFloat(it) }; uvs.flip()
            vb.setBufferAt(engine, 1, uvs)
        }
    }

    /** Draws only the first [count] indices (a multiple of 3). */
    fun draw(count: Int) {
        val rm = engine.renderableManager
        rm.setGeometryAt(rm.getInstance(entity), 0, RenderableManager.PrimitiveType.TRIANGLES, vb, ib, 0, count.coerceIn(0, indexCount))
    }

    fun destroy() {
        engine.destroyEntity(entity)
        EntityManager.get().destroy(entity)
        engine.destroyVertexBuffer(vb)
        engine.destroyIndexBuffer(ib)
    }

    private fun direct(bytes: Int): ByteBuffer = ByteBuffer.allocateDirect(bytes).order(ByteOrder.nativeOrder())
}
