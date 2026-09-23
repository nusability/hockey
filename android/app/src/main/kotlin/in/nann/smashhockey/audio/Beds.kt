package `in`.nann.smashhockey.audio

import android.content.res.AssetManager
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.PlaybackParams
import android.util.Log
import `in`.nann.smashhockey.core.feel.Atmosphere
import `in`.nann.smashhockey.core.feel.SoundMix
import `in`.nann.smashhockey.generated.AtmosphereData
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

/**
 * The looping layers (spec §8.8, shared/data/atmosphere.toml) — the two crowd beds, the swell over
 * them and the drum music. The twin of iOS's nodes in Game/Audio.swift.
 *
 * Why not [android.media.SoundPool] (which plays every one-shot, audio/Sfx.kt): its samples are
 * short by design — a minute of bed would not fit — and its looping restarts the buffer rather than
 * wrapping it. Why not MediaPlayer: `setLooping` leaves a gap at the seam, which on a bed is the one
 * thing you would hear, every time round. So each layer is one [AudioTrack] in `MODE_STATIC` with
 * hardware loop points over the whole decoded loop: it wraps sample-exactly and for ever, and only
 * its gain, its balance and its rate ever move. Tracks use `USAGE_GAME`, so the media volume and the
 * silent modes govern them like the rest of the game's sound.
 *
 * The files are decoded off the main thread; a layer that is not ready yet is simply silent. The
 * beds and the match's drums are decoded when a match starts and released when it ends — the menus
 * only ever hold their own loop.
 */
class Beds(private val assets: AssetManager) {
    /** One open loop: its track, and the constant rate the declaration gives it (the away bed's detune). */
    private class Layer(val track: AudioTrack, val rate: Double) {
        var holding = false
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val layers = ConcurrentHashMap<String, Layer>()
    private var matchOn = false
    private var menuOn = false

    /** The stadium and the match's drums, under a match of the player's (§8.8). */
    fun stadium(on: Boolean) {
        if (matchOn == on) return
        matchOn = on
        if (on) {
            AtmosphereData.beds.forEachIndexed { i, bed -> open(bedKey(i), bed.file, bed.rate) }
            open(MATCH, AtmosphereData.matchMusic.file, 1.0)
        } else {
            AtmosphereData.beds.indices.forEach { close(bedKey(it)) }
            close(MATCH)
        }
    }

    /** The menus' drums (§8.8), whenever no match of the player's is on. */
    fun menu(on: Boolean) {
        if (menuOn == on) return
        menuOn = on
        if (on) open(MENU, AtmosphereData.menuMusic.file, 1.0) else close(MENU)
    }

    /**
     * One frame: each layer's envelope read across its own `quietDb`…`loudDb`, scaled by the
     * player's two volumes (§12) and panned where the mapping puts it. A match layer at a time scale
     * of 0 (the match paused) holds where it is.
     */
    fun apply(l: Atmosphere.Levels, crowd: Double, music: Double) {
        AtmosphereData.beds.forEachIndexed { i, bed ->
            val level = when (bed.follows) {
                AtmosphereData.Follows.HOME -> l.home
                AtmosphereData.Follows.AWAY -> l.away
                AtmosphereData.Follows.SWELL -> l.swell
            }
            val pan = if (bed.follows == AtmosphereData.Follows.SWELL) bed.pan + l.swellPan else bed.pan
            set(layers[bedKey(i)], bed.quietDb + (bed.loudDb - bed.quietDb) * level, crowd, pan, l.rate, l.rate <= 0)
        }
        val m = AtmosphereData.matchMusic
        val duck = AtmosphereData.duckDepthDb * l.duck
        set(layers[MATCH], m.quietDb + (m.loudDb - m.quietDb) * l.music + duck, music, 0.0,
            if (m.followsTimeScale) l.rate else 1.0, m.followsTimeScale && l.rate <= 0)
        val n = AtmosphereData.menuMusic
        set(layers[MENU], n.quietDb + (n.loudDb - n.quietDb) * l.music + duck, music, 0.0, 1.0, false)
    }

    /** The app leaving the foreground: everything looping stops until it comes back. */
    fun pause() = layers.values.forEach { if (it.track.playState == AudioTrack.PLAYSTATE_PLAYING) it.track.pause() }

    fun resume() = layers.values.forEach { if (!it.holding) it.track.play() }

    fun release() {
        worker.shutdown()
        layers.values.forEach { it.track.pause(); it.track.release() }
        layers.clear()
    }

    @Suppress("DEPRECATION")
    private fun set(layer: Layer?, db: Double, volume: Double, pan: Double, rate: Double, hold: Boolean) {
        val l = layer ?: return
        val amplitude = (SoundMix.amplitude(db) * max(volume, 0.0)).toFloat()
        val (left, right) = SoundMix.stereo(clamp(pan, -1.0, 1.0))
        l.track.setStereoVolume(min(amplitude * left.toFloat(), 1f), min(amplitude * right.toFloat(), 1f))
        if (hold) {
            if (!l.holding) { l.track.pause(); l.holding = true }
            return
        }
        val speed = clamp(l.rate * rate, 0.25, 4.0).toFloat()
        if (l.track.playbackParams.speed != speed) {
            l.track.playbackParams = PlaybackParams().setSpeed(speed).setPitch(speed)
        }
        if (l.holding || l.track.playState != AudioTrack.PLAYSTATE_PLAYING) {
            l.holding = false
            l.track.play()
        }
    }

    private fun open(key: String, file: String, rate: Double) {
        if (layers.containsKey(key)) return
        worker.execute {
            try {
                val (pcm, sampleRate) = decode("sounds/$file.ogg")
                val track = AudioTrack.Builder()
                    .setAudioAttributes(
                        AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
                    )
                    .setAudioFormat(
                        AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(sampleRate).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build()
                    )
                    .setBufferSizeInBytes(pcm.size * 2)
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .build()
                track.write(pcm, 0, pcm.size)
                track.setLoopPoints(0, pcm.size, -1)
                @Suppress("DEPRECATION")
                track.setStereoVolume(0f, 0f)
                track.play()
                if (layers.putIfAbsent(key, Layer(track, rate)) != null) track.release()
            } catch (e: Exception) {
                Log.w(TAG, "the looping layer sounds/$file.ogg could not be opened", e)
            }
        }
    }

    private fun close(key: String) {
        val l = layers.remove(key) ?: return
        worker.execute {
            try {
                l.track.pause()
                l.track.release()
            } catch (e: IllegalStateException) {
                Log.w(TAG, "releasing a looping layer", e)
            }
        }
    }

    /** One packaged Ogg Vorbis loop, decoded whole into 16-bit mono PCM with its sample rate. */
    private fun decode(path: String): Pair<ShortArray, Int> {
        val extractor = MediaExtractor()
        assets.openFd(path).use { extractor.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                extractor.selectTrack(i)
                format = f
                break
            }
        }
        val track = format ?: error("$path has no audio track")
        val sampleRate = track.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        val channels = track.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val codec = MediaCodec.createDecoderByType(track.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(track, null, null, 0)
        codec.start()
        val out = ArrayList<ShortArray>()
        var total = 0
        val info = MediaCodec.BufferInfo()
        var fed = false
        var done = false
        while (!done) {
            if (!fed) {
                val index = codec.dequeueInputBuffer(TIMEOUT)
                if (index >= 0) {
                    val buffer = codec.getInputBuffer(index)!!
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) {
                        codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        fed = true
                    } else {
                        codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val index = codec.dequeueOutputBuffer(info, TIMEOUT)
            if (index >= 0) {
                if (info.size > 0) {
                    val chunk = mono(codec.getOutputBuffer(index)!!.order(ByteOrder.nativeOrder()),
                                     info.offset, info.size, channels)
                    out += chunk
                    total += chunk.size
                }
                codec.releaseOutputBuffer(index, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) done = true
            }
        }
        codec.stop()
        codec.release()
        extractor.release()
        val pcm = ShortArray(total)
        var at = 0
        for (chunk in out) {
            chunk.copyInto(pcm, at)
            at += chunk.size
        }
        return pcm to sampleRate
    }

    /** A decoded chunk folded to mono (our loops are mono, but a decoder may hand back stereo). */
    private fun mono(buffer: ByteBuffer, offset: Int, size: Int, channels: Int): ShortArray {
        buffer.position(offset)
        buffer.limit(offset + size)
        val shorts = buffer.asShortBuffer()
        val n = shorts.remaining()
        if (channels <= 1) {
            val out = ShortArray(n)
            shorts.get(out)
            return out
        }
        val out = ShortArray(n / channels)
        for (i in out.indices) {
            var sum = 0
            for (c in 0 until channels) sum += shorts.get(i * channels + c).toInt()
            out[i] = (sum / channels).toShort()
        }
        return out
    }

    private fun clamp(v: Double, lo: Double, hi: Double) = min(max(v, lo), hi)

    private fun bedKey(i: Int) = "bed$i"

    private companion object {
        const val TAG = "SmashBeds"
        const val MATCH = "music.match"
        const val MENU = "music.menu"
        const val TIMEOUT = 10_000L
    }
}
