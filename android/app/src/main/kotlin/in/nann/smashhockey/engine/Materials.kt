package `in`.nann.smashhockey.engine

import com.google.android.filament.Colors
import com.google.android.filament.Engine
import com.google.android.filament.MaterialInstance
import `in`.nann.smashhockey.generated.WorldLook
import kotlin.math.sqrt

/**
 * The scene's own shaders (ADR 0006) — the prototype's look computed by us, the twin of iOS's
 * Materials.swift: `toon` (a flat colour, lit in two bands) and `flat` (an unlit colour at an
 * opacity) here, `world` (a world mesh's palette, lit) and `sky` with the world ([World]). All are
 * Filament **unlit** materials computing
 * `colour = albedo × (mix(ground, sky, 0.5 + 0.5·n.y) · hemiStrength + sun · sunStrength · band(n·l))`
 * themselves, so no engine light touches them; under the view's linear tone mapper the linear
 * result is encoded to sRGB once, exactly as iOS's unlit graphs with tone mapping off. One instance
 * per colour, reused.
 */
class Materials(private val engine: Engine, assets: Assets) {
    private val toon = assets.material(engine, "toon")
    private val flat = assets.material(engine, "flat")
    private val aim = assets.material(engine, "aim")
    private val glow = assets.material(engine, "glow")
    private val trail = assets.material(engine, "trail")
    private val instances = HashMap<String, MaterialInstance>()
    /** Instances whose parameters change every frame: one per user, never shared. */
    private val owned = ArrayList<MaterialInstance>()

    /** A toon-shaded flat colour, lit by [look]. */
    fun toon(rgb: Int, look: WorldLook): MaterialInstance = instances.getOrPut("t$rgb/$look") {
        toon.createInstance().also { mi ->
            linear(rgb).let { mi.setParameter("albedo", Colors.RgbType.LINEAR, it[0], it[1], it[2]) }
            light(mi, look)
            mi.setParameter("alpha", 1f)
            mi.setDepthWrite(true)
        }
    }

    /** An unlit colour at an opacity; draw it after what it lies on (priority 5 and up). */
    fun flat(rgb: Int, alpha: Double = 1.0): MaterialInstance = instances.getOrPut("f$rgb/$alpha") {
        flat.createInstance().also { mi ->
            linear(rgb).let { mi.setParameter("baseColor", Colors.RgbType.LINEAR, it[0], it[1], it[2]) }
            mi.setParameter("alpha", alpha.toFloat())
            mi.setDepthWrite(alpha >= 1.0)      // a solid dot or ring occludes; see-through marks don't
        }
    }

    /** A flat colour whose opacity its one user changes every frame ([set]); [release] it with its user. */
    fun flatOwned(rgb: Int): MaterialInstance = own(flat.createInstance(), rgb)

    /** The aim ribbon's chevrons (aim.mat): taper and scroll fixed; colour, opacity and chevron count per frame. */
    fun aim(near: Double, far: Double, scroll: Double): MaterialInstance = own(aim.createInstance(), 0xFFFFFF).also {
        it.setParameter("near", near.toFloat()); it.setParameter("far", far.toFloat())
        it.setParameter("scroll", scroll.toFloat()); it.setParameter("cells", 1f)
    }

    /** An additive glow (glow.mat); colour and opacity per frame. */
    fun glow(rgb: Int): MaterialInstance = own(glow.createInstance(), rgb)

    /** The trail's colour fading along the ribbon (trail.mat). */
    fun trail(rgb: Int): MaterialInstance = own(trail.createInstance(), rgb)

    private fun own(mi: MaterialInstance, rgb: Int): MaterialInstance {
        set(mi, rgb, 0.0); mi.setDepthWrite(false); owned += mi; return mi
    }

    /** Sets an owned instance's colour and opacity (each of these materials has both). */
    fun set(mi: MaterialInstance, rgb: Int, alpha: Double) {
        linear(rgb).let { mi.setParameter("baseColor", Colors.RgbType.LINEAR, it[0], it[1], it[2]) }
        mi.setParameter("alpha", alpha.toFloat())
    }

    /** Destroys owned instances whose user is going (after its renderables are). */
    fun release(mis: Collection<MaterialInstance>) {
        for (mi in mis) if (owned.remove(mi)) engine.destroyMaterialInstance(mi)
    }

    fun destroy() {
        instances.values.forEach { engine.destroyMaterialInstance(it) }
        instances.clear()
        owned.forEach { engine.destroyMaterialInstance(it) }
        owned.clear()
        listOf(toon, flat, aim, glow, trail).forEach { engine.destroyMaterial(it) }
    }

    companion object {
        /** Sets a world or toon instance's light: the hemisphere and the sun, premultiplied by their
         *  strengths, and the unit vector toward the sun. */
        fun light(mi: MaterialInstance, look: WorldLook) {
            fun set(name: String, rgb: Int, strength: Double) {
                val c = linear(rgb); val s = strength.toFloat()
                mi.setParameter(name, c[0] * s, c[1] * s, c[2] * s)
            }
            set("sky", look.hemiSky, look.hemiStrength)
            set("ground", look.hemiGround, look.hemiStrength)
            set("sun", look.sun, look.sunStrength)
            val d = sunDirection(look)
            mi.setParameter("sunDirection", d[0], d[1], d[2])
            // The world shader's band is max(0, n·l) and has no dark side to set.
            if (mi.material.hasParameter("shade")) mi.setParameter("shade", look.shade.toFloat())
        }

        /** The unit vector toward [look]'s sun. */
        fun sunDirection(look: WorldLook): FloatArray {
            val d = look.sunDirection
            val len = sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])
            return FloatArray(3) { (d[it] / len).toFloat() }
        }

        /** sRGB 0xRRGGBB to linear RGB — the same curve iOS's Materials.linear uses. */
        fun linear(rgb: Int): FloatArray =
            Colors.toLinear(Colors.RgbType.SRGB, ((rgb shr 16) and 0xFF) / 255f, ((rgb shr 8) and 0xFF) / 255f, (rgb and 0xFF) / 255f)
    }
}
