package `in`.nann.smashhockey.engine

import android.app.Activity
import android.os.Build
import android.view.Display
import android.view.Surface

/**
 * The display's highest refresh rate at its current resolution, asked for twice: the window's
 * preferred display mode (every API level we support) and, on API 30+, the surface's frame rate —
 * so a 90 or 120 Hz phone draws at 90 or 120 (spec platform deltas). Only the drawing speeds up: the
 * simulation still runs in its fixed ticks (§4).
 */
object RefreshRate {
    /** The mode with the highest refresh at [display]'s current resolution. */
    fun fastest(display: Display): Display.Mode {
        val now = display.mode
        return display.supportedModes
            .filter { it.physicalWidth == now.physicalWidth && it.physicalHeight == now.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: now
    }

    /** Prefers the fastest mode for [activity]'s window. */
    fun prefer(activity: Activity) {
        @Suppress("DEPRECATION")
        val display = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) activity.display else activity.windowManager.defaultDisplay)
            ?: return
        val mode = fastest(display)
        val w = activity.window
        w.attributes = w.attributes.apply { preferredDisplayModeId = mode.modeId }
    }

    /** Asks [surface] to be composed at the fastest rate [display] has (API 30+; a no-op before). */
    fun request(surface: Surface, display: Display?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || display == null || !surface.isValid) return
        surface.setFrameRate(fastest(display).refreshRate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
    }
}
