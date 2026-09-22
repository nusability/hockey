package `in`.nann.smashhockey.ui

import `in`.nann.smashhockey.core.generated.SoundCue

/**
 * The UI kit's sounds (spec §8.8, §16): what a component plays when it is pressed, refused, flipped,
 * landed, swooped past or stepped. The kit only names the event; the game's playback layer, set here
 * once, plays it. Silent until then (a kit sketch without sound is a genuine state).
 */
object KitSound {
    var play: ((SoundCue) -> Unit)? = null

    fun press() = play?.invoke(SoundCue.UI_BUTTON_PRESS)
    fun refuse() = play?.invoke(SoundCue.UI_ERROR)
    fun flip() = play?.invoke(SoundCue.UI_DIGIT_FLIP)
    fun land() = play?.invoke(SoundCue.UI_PANEL_POP)
    fun swoop() = play?.invoke(SoundCue.UI_CAMERA_WHOOSH_LONG)
    fun sweep() = play?.invoke(SoundCue.UI_CAMERA_WHOOSH_SHORT)
    fun step() = play?.invoke(SoundCue.UI_SLIDER_TICK)
}
