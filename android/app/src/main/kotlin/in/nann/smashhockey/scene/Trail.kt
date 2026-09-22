package `in`.nann.smashhockey.scene

import com.google.android.filament.Box
import com.google.android.filament.Engine
import com.google.android.filament.Scene
import `in`.nann.smashhockey.engine.DynamicMesh
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.generated.Presentation
import kotlin.math.sqrt

/**
 * The loose ball's trail (spec §8.8) — the twin of iOS's BallTrail.swift: a ribbon through where the ball
 * was over the last `trail.seconds` of match time, tapering from `trail.width` at the ball to nothing
 * and fading with it (trail.mat), faded in and out with the ball's speed above `trail.min_speed`.
 * Horizontal, at the ball's centre height.
 */
class Trail(engine: Engine, private val scene: Scene, private val materials: Materials, private val height: Float) {
    private val t = Presentation.Trail
    private val n = t.samples
    private val xs = DoubleArray(n); private val zs = DoubleArray(n); private val ts = DoubleArray(n)
    private var count = 0
    private val material = materials.trail(t.colour)
    private val mesh = DynamicMesh(engine, n * 2, IntArray((n - 1) * 6) { i ->
        val seg = i / 6; val a = seg * 2
        intArrayOf(a, a + 1, a + 2, a + 1, a + 3, a + 2)[i % 6]
    }, material, withUv = true, bounds = Box(0f, 0f, 0f, 40f, 5f, 40f))
    private val xyz = FloatArray(n * 6)
    private val uv = FloatArray(n * 4)
    private var visible = false

    init { mesh.draw(0) }

    /**
     * One frame: the ball drawn at (x, z) at match [time], moving at [speed]; [loose] false (carried)
     * clears the trail.
     */
    fun update(x: Double, z: Double, time: Double, speed: Double, loose: Boolean) {
        if (!loose) { count = 0; setVisible(false); return }
        if (count > 0 && time <= ts[0]) { xs[0] = x; zs[0] = z } else {
            for (i in minOf(count, n - 1) downTo 1) { xs[i] = xs[i - 1]; zs[i] = zs[i - 1]; ts[i] = ts[i - 1] }
            xs[0] = x; zs[0] = z; ts[0] = time
            count = minOf(count + 1, n)
        }
        while (count > 1 && time - ts[count - 1] > t.seconds) count--
        val f = ((speed - t.minSpeed) / t.fadeSpeed).coerceIn(0.0, 1.0)
        if (count < 2 || f <= 0.0) { setVisible(false); return }
        materials.set(material, t.colour, t.opacity * f)
        for (i in 0 until count) {
            val u = ((time - ts[i]) / t.seconds).coerceIn(0.0, 1.0)
            // Across the travel at this point: from the neighbour toward the ball.
            val j0 = maxOf(i - 1, 0); val j1 = minOf(i + 1, count - 1)
            var dx = xs[j0] - xs[j1]; var dz = zs[j0] - zs[j1]
            val l = sqrt(dx * dx + dz * dz)
            if (l > 1e-6) { dx /= l; dz /= l } else { dx = 0.0; dz = 1.0 }
            val half = t.width / 2 * (1 - u)
            val px = -dz * half; val pz = dx * half
            val k = i * 6
            xyz[k] = (xs[i] + px).toFloat(); xyz[k + 1] = height; xyz[k + 2] = (zs[i] + pz).toFloat()
            xyz[k + 3] = (xs[i] - px).toFloat(); xyz[k + 4] = height; xyz[k + 5] = (zs[i] - pz).toFloat()
            uv[i * 4] = u.toFloat(); uv[i * 4 + 1] = 0f; uv[i * 4 + 2] = u.toFloat(); uv[i * 4 + 3] = 1f
        }
        mesh.update(xyz, uv)
        mesh.draw((count - 1) * 6)
        setVisible(true)
    }

    private fun setVisible(on: Boolean) {
        if (on == visible) return
        visible = on
        if (on) scene.addEntity(mesh.entity) else scene.removeEntity(mesh.entity)
    }

    fun destroy() {
        if (visible) scene.removeEntity(mesh.entity)
        mesh.destroy()
        materials.release(listOf(material))
    }
}
