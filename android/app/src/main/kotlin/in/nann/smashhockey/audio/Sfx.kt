package `in`.nann.smashhockey.audio

import android.content.res.AssetFileDescriptor
import android.content.res.AssetManager
import android.media.AudioAttributes
import android.media.MediaMetadataRetriever
import android.media.SoundPool
import android.util.Log
import `in`.nann.smashhockey.core.feel.SoundMix
import `in`.nann.smashhockey.core.feel.VoicePool
import `in`.nann.smashhockey.core.generated.SoundBus
import `in`.nann.smashhockey.core.generated.SoundCue
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.generated.Presentation
import java.io.FileNotFoundException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import kotlin.random.Random

/**
 * The game's sound (spec §8.8, shared/data/sounds.toml) — the twin of iOS's Audio.swift, on SoundPool.
 *
 * Why SoundPool: every event is a short one-shot, and SoundPool decodes each file once into PCM in
 * memory and starts it on the low-latency (fast mixer) path where the device has one, with what the
 * bank needs built in — a per-stream rate (0.5–2, the time scale and the pitch spread), left/right
 * volume (the pan), a stream ceiling and a stop. Oboe or AAudio would buy a few milliseconds more at
 * the price of NDK C++, our own decoder, resampler and mixer — code of a kind this app has none of.
 * Its streams play on the media volume (USAGE_GAME), so the volume keys and the silent modes govern it.
 *
 * Every event's files (both sports') are checked at launch: a declared file missing from the package
 * fails the launch, naming it. An event without files is silent by declaration. Which of the voices
 * a play takes is the core's [VoicePool]; which variant and at what pitch, [SoundMix]. Sounds made on
 * the pitch follow §8.6's time scale while they play and pan with where they happened.
 */
class Sfx(private val assets: AssetManager) {
    private val pool = SoundPool.Builder()
        .setMaxStreams(Presentation.Sound.voices)
        .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
        .build()
    private val ids = HashMap<String, Int>()
    /** Seconds per file, measured off the main thread; a file not yet measured counts as [UNMEASURED]. */
    private val seconds = ConcurrentHashMap<String, Double>()
    private val voices = VoicePool(Presentation.Sound.voices)
    private class Stream(val id: Int, val pitch: Double, val onPitch: Boolean)
    private val streams = arrayOfNulls<Stream>(Presentation.Sound.voices)
    private val last = HashMap<SoundCue, Int>()
    private class Later(val at: Double, val cue: SoundCue, val x: Double?)
    private val later = ArrayList<Later>()
    private var now = 0.0
    private var timeScale = 1.0
    /** Which sport's variants play: the world on the pitch (§1). */
    var sport = Sport.FIELD

    init {
        val names = SoundCue.entries.flatMap { c -> (c.spec.field + c.spec.ice).map { it to c } }.distinctBy { it.first }
        val measure = ArrayList<String>()
        for ((name, cue) in names) {
            val fd = open(name, cue)
            ids[name] = fd.use { pool.load(it, 1) }
            measure += name
        }
        Executors.newSingleThreadExecutor().apply {
            execute {
                for (name in measure) {
                    val r = MediaMetadataRetriever()
                    try {
                        assets.openFd(path(name)).use { r.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
                        r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toDoubleOrNull()?.let { seconds[name] = it / 1000 }
                    } catch (e: Exception) {
                        Log.w(TAG, "could not measure ${path(name)}", e)
                    } finally {
                        r.release()
                    }
                }
            }
            shutdown()
        }
    }

    private fun path(name: String) = "sounds/$name.ogg"

    private fun open(name: String, cue: SoundCue): AssetFileDescriptor = try {
        assets.openFd(path(name))
    } catch (e: FileNotFoundException) {
        throw IllegalStateException("${path(name)} is not packaged — shared/data/sounds.toml declares it for '${cue.key}' " +
            "(shared/assets/sounds/$name.ogg)", e)
    }

    /** Plays [cue] — at [x] across the pitch when it was made there — now or [delay] real seconds from now. */
    fun play(cue: SoundCue, x: Double? = null, delay: Double = 0.0) {
        if (delay > 0) { later += Later(now + delay, cue, x); return }
        val files = cue.spec.files(sport)
        if (files.isEmpty()) return
        val v = SoundMix.variant(files.size, last[cue], Random.nextDouble())
        last[cue] = v
        val name = files[v]
        val id = ids.getValue(name)
        val spec = cue.spec
        val pitch = SoundMix.pitch(spec.pitchSemitones, Random.nextDouble())
        val onPitch = x != null && spec.bus == SoundBus.MATCH
        val rate = SoundMix.rate(pitch, timeScale, onPitch, Presentation.Sound.minRate, Presentation.Sound.maxRate)
        val slot = voices.claim(cue, now, (seconds[name] ?: UNMEASURED) / rate) ?: return
        streams[slot]?.let { pool.stop(it.id) }
        val (l, r) = SoundMix.stereo(SoundMix.pan(if (onPitch) x else null, Presentation.Sound.pan))
        val a = SoundMix.amplitude(spec.gainDb)
        val stream = pool.play(id, (a * l).toFloat(), (a * r).toFloat(), spec.priority, 0, rate.toFloat())
        streams[slot] = if (stream == 0) null else Stream(stream, pitch, onPitch)
    }

    /**
     * One frame of real time [dt]; [scale] is §8.6's time scale now (0 while the match is paused): the
     * delayed plays that are due go, and the sounds made on the pitch follow the scale.
     */
    fun update(dt: Double, scale: Double) {
        now += dt
        val changed = scale != timeScale
        timeScale = scale
        if (later.isNotEmpty()) {
            val due = later.filter { it.at <= now }
            later.removeAll(due.toSet())
            due.forEach { play(it.cue, it.x) }
        }
        if (!changed) return
        for (s in streams) {
            if (s == null || !s.onPitch) continue
            if (scale <= 0.0) pool.pause(s.id) else {
                pool.resume(s.id)
                pool.setRate(s.id, SoundMix.rate(s.pitch, scale, true, Presentation.Sound.minRate, Presentation.Sound.maxRate).toFloat())
            }
        }
    }

    /** Leaving a match: what is still to come is dropped, and the crowd falls silent. */
    fun clearLater() {
        later.clear()
        ambience?.let { pool.stop(it) }
        ambience = null
    }

    private var ambience: Int? = null

    /** The crowd under a player's match, looped — when the bank has one (silent by declaration otherwise). */
    fun crowd() {
        if (ambience != null) return
        val spec = SoundCue.AMBIENCE_CROWD.spec
        val name = spec.files(sport).firstOrNull() ?: return
        val a = SoundMix.amplitude(spec.gainDb).toFloat() * 0.7071f
        ambience = pool.play(ids.getValue(name), a, a, spec.priority, -1, 1f).takeIf { it != 0 }
    }

    fun pause() = pool.autoPause()
    fun resume() = pool.autoResume()
    fun release() = pool.release()

    private companion object {
        const val TAG = "SmashSfx"
        /** The voice budget for a file whose length is still being measured. */
        const val UNMEASURED = 1.0
    }
}
