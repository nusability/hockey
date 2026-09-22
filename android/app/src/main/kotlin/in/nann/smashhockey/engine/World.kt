package `in`.nann.smashhockey.engine

import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Scene
import com.google.android.filament.Texture
import com.google.android.filament.TextureSampler
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import `in`.nann.smashhockey.core.generated.World as WorldId
import `in`.nann.smashhockey.generated.WorldLook
import `in`.nann.smashhockey.generated.look

/**
 * One of the five worlds (spec §13) on stage, from `shared/assets/worlds/<id>/<id>.glb` (ADR 0005),
 * with its look (teams.toml [world.look]) — the twin of iOS's WorldStage. Materials are bound by
 * name: the `sky` mesh gets our unlit sky, everything else our `world` shader lit by the world's
 * look (ADR 0006). No lights, no fog, no shadows: the shading is ours.
 */
class World(private val engine: Engine, private val scene: Scene, assets: Assets, val id: WorldId) {
    val look: WorldLook = id.look
    private val gltfMaterials = UbershaderProvider(engine)
    private val loader = AssetLoader(engine, gltfMaterials, EntityManager.get())
    private val resources = ResourceLoader(engine)
    private val asset: FilamentAsset
    private val skyMaterial = assets.material(engine, "sky")
    private val worldMaterial = assets.material(engine, "world")
    private val skyInstance: MaterialInstance
    private val worldInstance: MaterialInstance
    private val palette: Texture

    /** The asset's root entity — parent it to move the whole world (the camera shake). */
    val root: Int get() = asset.root

    init {
        asset = loader.createAsset(assets.bytes("worlds/${id.key}/${id.key}.glb"))
            ?: throw IllegalStateException("worlds/${id.key}/${id.key}.glb is not a loadable glTF")
        resources.loadResources(asset)
        asset.releaseSourceData()

        palette = assets.texture(engine, "worlds/${id.key}/palette.png")
        skyInstance = skyMaterial.createInstance().apply {
            setParameter("baseColorMap", palette, TextureSampler(
                TextureSampler.MinFilter.LINEAR, TextureSampler.MagFilter.LINEAR, TextureSampler.WrapMode.CLAMP_TO_EDGE))
        }
        worldInstance = worldMaterial.createInstance().apply {
            setParameter("palette", palette, TextureSampler(
                TextureSampler.MinFilter.NEAREST, TextureSampler.MagFilter.NEAREST, TextureSampler.WrapMode.CLAMP_TO_EDGE))
            Materials.light(this, look)
        }
        val sky = asset.getFirstEntityByName("sky")
        if (sky == 0) throw IllegalStateException("worlds/${id.key} has no mesh named 'sky'")
        val rm = engine.renderableManager
        for (e in asset.renderableEntities) {
            val r = rm.getInstance(e)
            rm.setCastShadows(r, false)
            rm.setReceiveShadows(r, false)
            val instance = if (e == sky) skyInstance else worldInstance
            for (i in 0 until rm.getPrimitiveCount(r)) rm.setMaterialInstanceAt(r, i, instance)
        }
        scene.addEntities(asset.entities)
    }

    fun destroy() {
        scene.removeEntities(asset.entities)
        loader.destroyAsset(asset)
        engine.destroyMaterialInstance(skyInstance)
        engine.destroyMaterialInstance(worldInstance)
        engine.destroyMaterial(skyMaterial)
        engine.destroyMaterial(worldMaterial)
        engine.destroyTexture(palette)
        resources.destroy()
        loader.destroy()
        gltfMaterials.destroyMaterials()
        gltfMaterials.destroy()
    }
}
