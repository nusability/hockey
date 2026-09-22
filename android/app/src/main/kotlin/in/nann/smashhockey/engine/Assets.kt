package `in`.nann.smashhockey.engine

import android.content.res.AssetManager
import android.graphics.BitmapFactory
import com.google.android.filament.Engine
import com.google.android.filament.Material
import com.google.android.filament.Texture
import com.google.android.filament.android.TextureHelper
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Reads packaged assets. A missing asset is a build fault, so it fails loud with its path. */
class Assets(private val manager: AssetManager) {

    fun bytes(path: String): ByteBuffer {
        val data = try {
            manager.open(path).use { it.readBytes() }
        } catch (e: java.io.IOException) {
            throw IllegalStateException("asset '$path' is not packaged — check shared/ and the assets srcDirs", e)
        }
        return ByteBuffer.allocateDirect(data.size).order(ByteOrder.nativeOrder()).put(data).also { it.flip() }
    }

    fun json(path: String): JSONObject = JSONObject(String(manager.open(path).use { it.readBytes() }))

    fun material(engine: Engine, name: String): Material {
        val buffer = bytes("materials/$name.filamat")
        return Material.Builder().payload(buffer, buffer.remaining()).build(engine)
    }

    /** An sRGB texture from a PNG, one mip level — the palette textures are nearest-sampled swatches. */
    fun texture(engine: Engine, path: String): Texture {
        val bitmap = manager.open(path).use { BitmapFactory.decodeStream(it) }
            ?: throw IllegalStateException("asset '$path' is not a decodable image")
        val texture = Texture.Builder()
            .width(bitmap.width)
            .height(bitmap.height)
            .levels(1)
            .sampler(Texture.Sampler.SAMPLER_2D)
            .format(Texture.InternalFormat.SRGB8_A8)
            .build(engine)
        TextureHelper.setBitmap(engine, texture, 0, bitmap)
        return texture
    }
}
