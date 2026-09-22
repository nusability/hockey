package `in`.nann.smashhockey.effects

import android.animation.ValueAnimator
import com.google.android.filament.Engine
import com.google.android.filament.Material
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Texture
import com.google.android.filament.TextureSampler
import com.google.android.filament.gltfio.FilamentAsset
import `in`.nann.smashhockey.core.generated.World as WorldId
import `in`.nann.smashhockey.effects.generated.FxBlend
import `in`.nann.smashhockey.effects.generated.FxCalm
import `in`.nann.smashhockey.effects.generated.FxMotion
import `in`.nann.smashhockey.effects.generated.FxShading
import `in`.nann.smashhockey.effects.generated.FxSpec
import `in`.nann.smashhockey.effects.generated.effects
import `in`.nann.smashhockey.engine.Assets
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.generated.WorldLook

/**
 * What is alive in a world (spec §13, ADR 0007) — the twin of iOS's WorldEffects. Every effect
 * shared/data/effects.toml declares for the world is the mesh `fx_<id>` in its asset; this binds it
 * to one of the six effect materials (fx_*.mat) with the declared numbers. From then on the GPU moves
 * it on Filament's own clock (`getUserTime`): no per-frame work here, nothing shared with the match.
 *
 * Reduce Motion (the system's "remove animations") is read once, at load: amplitudes and rates are
 * multiplied by [FxCalm] — calmer, never still. Effects are never culled: their shaders move them out
 * of the bounds the asset was measured in.
 */
class WorldEffects(
    private val engine: Engine,
    assets: Assets,
    asset: FilamentAsset,
    world: WorldId,
    look: WorldLook,
    palette: Texture,
) {
    private val materials = HashMap<String, Material>()
    private val instances = ArrayList<MaterialInstance>()

    init {
        val calm = !ValueAnimator.areAnimatorsEnabled()
        val amp = if (calm) FxCalm.amplitude else 1.0
        val speed = if (calm) FxCalm.speed else 1.0
        val sampler = TextureSampler(TextureSampler.MinFilter.NEAREST, TextureSampler.MagFilter.NEAREST,
            TextureSampler.WrapMode.CLAMP_TO_EDGE)
        val rm = engine.renderableManager
        for (spec in world.effects) {
            val name = "fx_${spec.id}"
            val entity = asset.getFirstEntityByName(name)
            if (entity == 0 || !rm.hasComponent(entity)) {
                throw IllegalStateException("worlds/${world.key} has no mesh named '$name' (shared/data/effects.toml declares it)")
            }
            val file = materialFile(spec)
            val mi = materials.getOrPut(file) { assets.material(engine, file) }.createInstance()
            instances += mi
            mi.setParameter("palette", palette, sampler)
            bind(mi, spec, look, amp, speed)
            val r = rm.getInstance(entity)
            rm.setCulling(r, false)
            rm.setCastShadows(r, false)
            rm.setReceiveShadows(r, false)
            for (i in 0 until rm.getPrimitiveCount(r)) rm.setMaterialInstanceAt(r, i, mi)
        }
    }

    /** Call after the asset's entities are gone. */
    fun destroy() {
        instances.forEach { engine.destroyMaterialInstance(it) }
        instances.clear()
        materials.values.forEach { engine.destroyMaterial(it) }
        materials.clear()
    }

    private fun materialFile(spec: FxSpec): String = when (spec.shading) {
        FxShading.LIT -> "fx_lit"
        FxShading.GLOW -> "fx_glow"
        FxShading.SOFT -> if (spec.blend == FxBlend.ADD) "fx_soft_add" else "fx_soft_alpha"
        FxShading.PARTICLES -> if (spec.blend == FxBlend.ADD) "fx_particle_add" else "fx_particle_alpha"
    }

    private fun bind(mi: MaterialInstance, spec: FxSpec, look: WorldLook, amp: Double, speed: Double) {
        fun f(v: Double) = v.toFloat()
        fun v3(name: String, v: List<Double>, k: Double) = mi.setParameter(name, f(v[0] * k), f(v[1] * k), f(v[2] * k))
        val p = spec.pulse
        mi.setParameter("pulseAmp", f(p[0]), f(p[1] * amp), f(p[3] * amp))
        mi.setParameter("pulseRate", f(p[2] * speed), f(p[4] * speed), 0f)
        if (spec.shading == FxShading.PARTICLES) {
            mi.setParameter("opacity", f(spec.opacity))
            mi.setParameter("size", f(spec.size))
            mi.setParameter("sizeSpread", f(spec.sizeSpread))
            v3("travel", spec.travel, speed)
            mi.setParameter("wrap", f(spec.wrap))
            v3("wobble", spec.wobble, amp)
            mi.setParameter("wobbleRate", f(spec.wobbleRate * speed))
            return
        }
        v3("swayAmp", spec.sway, amp)
        mi.setParameter("swayRate", f(spec.swayRate * speed))
        mi.setParameter("orbit", if (spec.motion == FxMotion.ORBIT) 1f else 0f)
        mi.setParameter("spin", f(spec.spin * speed))
        v3("pivot", spec.pivot, 1.0)
        mi.setParameter("ellipse", f(spec.ellipse))
        if (spec.shading == FxShading.LIT) Materials.light(mi, look)
        if (spec.shading == FxShading.SOFT) mi.setParameter("opacity", f(spec.opacity))
    }
}
