package `in`.nann.smashhockey.engine

import com.google.android.filament.Colors
import com.google.android.filament.Engine
import com.google.android.filament.MaterialInstance

/**
 * The scene's own materials (ADR 0005: bound by name, written twice from one formula) — the twin
 * of iOS's Materials.swift: the toys (`actor`: lit, under the view's fog), the marks on the pitch
 * (`overlay`: unlit, see-through, fogged) and the 3D UI (`ui_lit`: lit, never reached by fog — the
 * HUD sits well inside the fog's start). One instance per colour, reused.
 */
class Materials(private val engine: Engine, assets: Assets) {
    private val actor = assets.material(engine, "actor")
    private val overlay = assets.material(engine, "overlay")
    private val ui = assets.material(engine, "ui_lit")
    private val instances = HashMap<String, MaterialInstance>()

    fun actor(rgb: Int): MaterialInstance = instances.getOrPut("a$rgb") {
        actor.createInstance().also { mi -> linear(rgb).let { mi.setParameter("baseColor", Colors.RgbType.LINEAR, it[0], it[1], it[2]) } }
    }

    fun overlay(rgb: Int, alpha: Double): MaterialInstance = instances.getOrPut("o$rgb/$alpha") {
        overlay.createInstance().also { mi ->
            linear(rgb).let { mi.setParameter("baseColor", Colors.RgbType.LINEAR, it[0], it[1], it[2]) }
            mi.setParameter("alpha", alpha.toFloat())
        }
    }

    fun ui(rgb: Int): MaterialInstance = instances.getOrPut("u$rgb") {
        ui.createInstance().also { mi ->
            linear(rgb).let { mi.setParameter("baseColor", Colors.RgbType.LINEAR, it[0], it[1], it[2]) }
            mi.setParameter("alpha", 1f)
        }
    }

    fun destroy() {
        instances.values.forEach { engine.destroyMaterialInstance(it) }
        listOf(actor, overlay, ui).forEach { engine.destroyMaterial(it) }
    }

    private fun linear(rgb: Int) = World.linear(rgb)
}
