package `in`.nann.smashhockey.engine

import android.opengl.Matrix
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import kotlin.math.max
import kotlin.math.min

/**
 * A thin node layer over Filament's TransformManager (ADR 0005): a local position, yaw/pitch and
 * non-uniform scale, parented to another entity — the camera, for the HUD rig. It owns no
 * geometry; a [GpuMesh] may be attached as the node's own renderable.
 */
class Node(private val engine: Engine, parent: Int? = null, val mesh: GpuMesh? = null) {
    val entity: Int = mesh?.entity ?: EntityManager.get().create()
    private val tm = engine.transformManager
    private val instance: Int

    var x = 0f; var y = 0f; var z = 0f
    var yaw = 0f; var pitch = 0f
    var sx = 1f; var sy = 1f; var sz = 1f

    init {
        if (!tm.hasComponent(entity)) tm.create(entity)
        instance = tm.getInstance(entity)
        parent?.let { tm.setParent(instance, tm.getInstance(it)) }
    }

    /** Writes the local transform: translate · rotate(yaw about Y, then pitch about X) · scale. */
    fun apply() {
        val m = FloatArray(16)
        Matrix.setIdentityM(m, 0)
        Matrix.translateM(m, 0, x, y, z)
        Matrix.rotateM(m, 0, Math.toDegrees(yaw.toDouble()).toFloat(), 0f, 1f, 0f)
        Matrix.rotateM(m, 0, Math.toDegrees(pitch.toDouble()).toFloat(), 1f, 0f, 0f)
        Matrix.scaleM(m, 0, sx, sy, sz)
        tm.setTransform(instance, m)
    }

    fun worldMatrix(): FloatArray = FloatArray(16).also { tm.getWorldTransform(instance, it) }

    /**
     * Distance along the ray (world space) to this node's mesh bounds, or null on a miss. Our own
     * test, synchronous in the touch handler (ADR 0005) — never Filament's asynchronous pick.
     */
    fun hit(origin: FloatArray, dir: FloatArray): Float? {
        val m = mesh ?: return null
        val inv = FloatArray(16)
        if (!Matrix.invertM(inv, 0, worldMatrix(), 0)) return null
        val o = FloatArray(4); val d = FloatArray(4)
        Matrix.multiplyMV(o, 0, inv, 0, floatArrayOf(origin[0], origin[1], origin[2], 1f), 0)
        Matrix.multiplyMV(d, 0, inv, 0, floatArrayOf(dir[0], dir[1], dir[2], 0f), 0)
        var tMin = 0f; var tMax = Float.MAX_VALUE
        val lo = floatArrayOf(m.min.x, m.min.y, m.min.z); val hi = floatArrayOf(m.max.x, m.max.y, m.max.z)
        for (a in 0..2) {
            if (kotlin.math.abs(d[a]) < 1e-8f) {
                if (o[a] < lo[a] || o[a] > hi[a]) return null
            } else {
                val t1 = (lo[a] - o[a]) / d[a]; val t2 = (hi[a] - o[a]) / d[a]
                tMin = max(tMin, min(t1, t2)); tMax = min(tMax, max(t1, t2))
                if (tMin > tMax) return null
            }
        }
        return tMin
    }

    /** The eight corners of the mesh bounds in world space. */
    fun worldCorners(): List<FloatArray> {
        val m = mesh ?: return emptyList()
        val w = worldMatrix()
        val out = mutableListOf<FloatArray>()
        for (cx in listOf(m.min.x, m.max.x)) for (cy in listOf(m.min.y, m.max.y)) for (cz in listOf(m.min.z, m.max.z)) {
            val r = FloatArray(4)
            Matrix.multiplyMV(r, 0, w, 0, floatArrayOf(cx, cy, cz, 1f), 0)
            out += r
        }
        return out
    }
}
