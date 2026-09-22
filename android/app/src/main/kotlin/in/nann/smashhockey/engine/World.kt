package `in`.nann.smashhockey.engine

import com.google.android.filament.Colors
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.IndirectLight
import com.google.android.filament.LightManager
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Scene
import com.google.android.filament.Texture
import com.google.android.filament.TextureSampler
import com.google.android.filament.View
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import `in`.nann.smashhockey.core.generated.World as WorldId
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.generated.WorldLook
import `in`.nann.smashhockey.generated.look

/**
 * One of the five worlds (spec §13) on stage, from `shared/assets/worlds/<id>/<id>.glb` (ADR 0005),
 * with its look (teams.toml [world.look]) — the twin of iOS's WorldStage. Materials are bound by
 * name: the `sky` mesh gets our unlit, unfogged sky material, tinted; everything else keeps gltfio's
 * lit material under the view's fog and casts and receives the sun's shadow. The light is the
 * world's colour and strength on the rig the spike calibrated against iOS's.
 */
class World(private val engine: Engine, private val scene: Scene, view: View, assets: Assets, val id: WorldId) {
    val look: WorldLook = id.look
    private val materials = UbershaderProvider(engine)
    private val loader = AssetLoader(engine, materials, EntityManager.get())
    private val resources = ResourceLoader(engine)
    private val asset: FilamentAsset
    private val skyMaterial = assets.material(engine, "sky")
    private val skyInstance: MaterialInstance
    private val palette: Texture
    private val sun = EntityManager.get().create()
    private val ibl: IndirectLight

    /** The asset's root entity — parent it to move the whole world (the camera shake). */
    val root: Int get() = asset.root

    init {
        asset = loader.createAsset(assets.bytes("worlds/${id.key}/${id.key}.glb"))
            ?: throw IllegalStateException("worlds/${id.key}/${id.key}.glb is not a loadable glTF")
        resources.loadResources(asset)
        asset.releaseSourceData()

        val rm = engine.renderableManager
        for (e in asset.renderableEntities) {
            val r = rm.getInstance(e)
            rm.setCastShadows(r, true)
            rm.setReceiveShadows(r, true)
        }

        palette = assets.texture(engine, "worlds/${id.key}/palette.png")
        val tint = linear(look.sky)
        skyInstance = skyMaterial.createInstance().apply {
            setParameter("baseColorMap", palette, TextureSampler(
                TextureSampler.MinFilter.LINEAR, TextureSampler.MagFilter.LINEAR, TextureSampler.WrapMode.CLAMP_TO_EDGE))
            setParameter("tint", tint[0], tint[1], tint[2])
        }
        val sky = asset.getFirstEntityByName("sky")
        if (sky == 0) throw IllegalStateException("worlds/${id.key} has no mesh named 'sky'")
        val skyRenderable = rm.getInstance(sky)
        rm.setMaterialInstanceAt(skyRenderable, 0, skyInstance)
        rm.setCastShadows(skyRenderable, false)
        rm.setReceiveShadows(skyRenderable, false)
        scene.addEntities(asset.entities)

        val d = Presentation.Light.sunDirection
        val sunColour = linear(look.sun)
        LightManager.Builder(LightManager.Type.SUN)
            .color(sunColour[0], sunColour[1], sunColour[2])
            .intensity((SUN_LUX * look.sunStrength).toFloat())
            .direction(d[0].toFloat(), d[1].toFloat(), d[2].toFloat())
            .sunAngularRadius(1.6f)
            .castShadows(true)
            .shadowOptions(LightManager.ShadowOptions().apply { mapSize = 2048 })
            .build(engine, sun)
        scene.addEntity(sun)
        val shade = linear(look.ambient)
        ibl = IndirectLight.Builder().irradiance(1, shade).intensity((IBL_LUX * look.ambientStrength).toFloat()).build(engine)
        scene.indirectLight = ibl

        val fog = linear(look.fog)
        view.fogOptions = View.FogOptions().apply {
            enabled = true
            distance = look.fogStart.toFloat()
            density = look.fogDensity.toFloat()
            heightFalloff = 0.0f
            maximumOpacity = look.fogMax.toFloat()
            color = fog
            cutOffDistance = 250f        // the sky dome (r = 320) stays out of the fog
        }
    }

    fun destroy() {
        scene.removeEntities(asset.entities)
        scene.removeEntity(sun)
        loader.destroyAsset(asset)
        engine.destroyMaterialInstance(skyInstance)
        engine.destroyMaterial(skyMaterial)
        engine.destroyTexture(palette)
        engine.destroyEntity(sun)
        EntityManager.get().destroy(sun)
        engine.destroyIndirectLight(ibl)
        resources.destroy()
        loader.destroy()
        materials.destroyMaterials()
        materials.destroy()
    }

    companion object {
        /** The spike's calibrated rig at strength 1: Filament lux for the sun and the irradiance. */
        private const val SUN_LUX = 80_000.0
        private const val IBL_LUX = 22_000.0

        /** sRGB 0xRRGGBB to linear RGB — the same curve iOS's Materials.linear uses. */
        fun linear(rgb: Int): FloatArray =
            Colors.toLinear(Colors.RgbType.SRGB, ((rgb shr 16) and 0xFF) / 255f, ((rgb shr 8) and 0xFF) / 255f, (rgb and 0xFF) / 255f)
    }
}
