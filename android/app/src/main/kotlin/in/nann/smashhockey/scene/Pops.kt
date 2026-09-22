package `in`.nann.smashhockey.scene

import com.google.android.filament.Engine
import com.google.android.filament.Scene
import `in`.nann.smashhockey.core.feel.PopKind
import `in`.nann.smashhockey.engine.Geometry
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.engine.Node
import `in`.nann.smashhockey.generated.Presentation

/**
 * A save, a steal or a block pops at the spot (spec §8.8) — the twin of iOS's Pops.swift: a flat ring
 * `pop.width` of its radius wide grows from radius_from to radius_to over `pop.seconds` of real time,
 * fading out, in the kind's colour. Four at most at once; a fifth takes the oldest.
 */
class Pops(private val engine: Engine, private val scene: Scene, parent: Int, private val materials: Materials) {
    private val p = Presentation.Pop
    private val geometry = Geometry(engine, Shapes.ring((1 - p.width).toFloat(), 1f, 32))
    private class Ring(val node: Node, val material: com.google.android.filament.MaterialInstance) {
        var age = Double.POSITIVE_INFINITY; var colour = 0; var shown = false
    }
    private val rings = (0 until 4).map {
        val m = materials.flatOwned(p.save)
        Ring(Node(engine, parent, existing = geometry.renderable(listOf(m), shadows = false, priority = 6)), m)
    }

    fun pop(kind: PopKind, x: Double, z: Double) {
        val r = rings.maxBy { it.age }
        r.age = 0.0
        r.colour = when (kind) { PopKind.SAVE -> p.save; PopKind.STEAL -> p.steal; PopKind.BLOCK -> p.block }
        r.node.x = x.toFloat(); r.node.y = 0.05f; r.node.z = z.toFloat()
        if (!r.shown) { scene.addEntity(r.node.entity); r.shown = true }
        draw(r)
    }

    fun advance(dt: Double) {
        for (r in rings) {
            if (!r.shown) continue
            r.age += dt
            if (r.age >= p.seconds) { scene.removeEntity(r.node.entity); r.shown = false; continue }
            draw(r)
        }
    }

    private fun draw(r: Ring) {
        val t = (r.age / p.seconds).coerceIn(0.0, 1.0)
        r.node.scale((p.radiusFrom + (p.radiusTo - p.radiusFrom) * t).toFloat())
        r.node.apply()
        materials.set(r.material, r.colour, p.opacity * (1 - t))
    }

    fun destroy() {
        rings.forEach { if (it.shown) scene.removeEntity(it.node.entity) }
        geometry.destroy()
        materials.release(rings.map { it.material })
    }
}
