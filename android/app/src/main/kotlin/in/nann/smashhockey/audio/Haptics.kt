package `in`.nann.smashhockey.audio

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import `in`.nann.smashhockey.core.feel.Haptic
import kotlin.math.roundToInt

/**
 * The match's haptics (spec §8.8) — the twin of iOS's Haptics (Game/Feedback.swift). On the system's word: when
 * "touch feedback" is off (Settings.System.HAPTIC_FEEDBACK_ENABLED = 0) nothing buzzes. API 30+ plays
 * the composition primitives the vibrator supports — a TICK for a tick, a CLICK scaled by intensity
 * for an impact or a sharp transient; older or simpler vibrators get a short one-shot pulse at the
 * intensity's amplitude.
 */
class Haptics(private val context: Context) {
    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }
    private val primitives: Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && vibrator?.let {
        it.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_TICK, VibrationEffect.Composition.PRIMITIVE_CLICK)
    } == true

    private val enabled: Boolean
        get() = Settings.System.getInt(context.contentResolver, Settings.System.HAPTIC_FEEDBACK_ENABLED, 1) != 0

    fun play(h: Haptic) {
        val v = vibrator ?: return
        if (!v.hasVibrator() || !enabled) return
        val (intensity, ms, primitive) = when (h) {
            is Haptic.Tick -> Triple(h.intensity, 10L, TICK)
            is Haptic.Impact -> Triple(h.intensity, (20 + 15 * h.intensity).toLong(), CLICK)
            is Haptic.Sharp -> Triple(h.intensity, 15L, CLICK)
        }
        val scale = intensity.coerceIn(0.0, 1.0).toFloat()
        if (scale <= 0f) return
        val effect = if (primitives && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val p = if (primitive == TICK) VibrationEffect.Composition.PRIMITIVE_TICK else VibrationEffect.Composition.PRIMITIVE_CLICK
            VibrationEffect.startComposition().addPrimitive(p, scale).compose()
        } else {
            VibrationEffect.createOneShot(ms, (255 * scale).roundToInt().coerceIn(1, 255))
        }
        v.vibrate(effect)
    }

    fun stop() { vibrator?.cancel() }

    private companion object {
        const val TICK = 0
        const val CLICK = 1
    }
}
