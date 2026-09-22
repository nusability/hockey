package `in`.nann.smashhockey.engine

import com.google.android.filament.Engine
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Scene
import com.google.android.filament.Texture
import com.google.android.filament.TextureSampler
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import com.google.android.filament.EntityManager

/**
 * A world from `shared/assets/worlds/<id>/<id>.glb` (ADR 0005). Materials are bound by name: the
 * `sky` mesh gets our unlit, unfogged sky material; everything else keeps gltfio's lit material
 * and casts and receives the sun's shadow.
 */
class World(private val engine: Engine, scene: Scene, assets: Assets, id: String) {
    private val materials = UbershaderProvider(engine)
    private val loader = AssetLoader(engine, materials, EntityManager.get())
    private val resources = ResourceLoader(engine)
    private val asset: FilamentAsset
    private val skyMaterial = assets.material(engine, "sky")
    private val skyInstance: MaterialInstance
    private val palette: Texture

    init {
        asset = loader.createAsset(assets.bytes("worlds/$id/$id.glb"))
            ?: throw IllegalStateException("worlds/$id/$id.glb is not a loadable glTF")
        resources.loadResources(asset)
        asset.releaseSourceData()

        val rm = engine.renderableManager
        for (e in asset.renderableEntities) {
            val r = rm.getInstance(e)
            rm.setCastShadows(r, true)
            rm.setReceiveShadows(r, true)
        }

        palette = assets.texture(engine, "worlds/$id/palette.png")
        skyInstance = skyMaterial.createInstance().apply {
            setParameter("baseColorMap", palette, TextureSampler(
                TextureSampler.MinFilter.LINEAR, TextureSampler.MagFilter.LINEAR, TextureSampler.WrapMode.CLAMP_TO_EDGE))
        }
        val sky = asset.getFirstEntityByName("sky")
        if (sky == 0) throw IllegalStateException("worlds/$id has no mesh named 'sky'")
        val skyRenderable = rm.getInstance(sky)
        rm.setMaterialInstanceAt(skyRenderable, 0, skyInstance)
        rm.setCastShadows(skyRenderable, false)
        rm.setReceiveShadows(skyRenderable, false)

        scene.addEntities(asset.entities)
    }

    fun destroy() {
        loader.destroyAsset(asset)
        engine.destroyMaterialInstance(skyInstance)
        engine.destroyMaterial(skyMaterial)
        engine.destroyTexture(palette)
        resources.destroy()
        loader.destroy()
        materials.destroyMaterials()
        materials.destroy()
    }
}
