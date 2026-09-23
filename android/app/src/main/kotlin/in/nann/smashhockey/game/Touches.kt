package `in`.nann.smashhockey.game

import android.view.MotionEvent
import `in`.nann.smashhockey.ui.UIStage

/**
 * Every finger on the surface (spec §5.3), and which of the two things on screen it belongs to. A
 * finger that lands on a 3D control belongs to the UI (the first such finger drives it); every other
 * finger is the match's while a match is being played: the first one down holds, the last one up
 * releases.
 *
 * Nothing here may wait on anything (A0): a hold is registered on touch-down and a release on
 * touch-up, in the same frame.
 */
class Touches(private val game: Game) {
    /** The pointer the UI took, if it took one. */
    private var ui: Int? = null
    private val onPitch = HashSet<Int>()

    fun onTouch(e: MotionEvent): Boolean {
        val stage = game.stageRef.value ?: return true
        val i = e.actionIndex
        val id = e.getPointerId(i)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (ui == null && stage.touchDown(e.getX(i), e.getY(i))) {
                    ui = id
                } else if (pitchTakesFingers) {
                    val first = onPitch.isEmpty()
                    onPitch += id
                    if (first) game.pitch.hold(true, e.eventTime)
                }
            }
            MotionEvent.ACTION_MOVE -> ui?.let { u ->
                val at = e.findPointerIndex(u)
                if (at >= 0) stage.touchMoved(e.getX(at), e.getY(at))
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> lift(stage, id, e.getX(i), e.getY(i), e.eventTime)
            MotionEvent.ACTION_CANCEL -> for (k in 0 until e.pointerCount) lift(stage, e.getPointerId(k), e.getX(k), e.getY(k), e.eventTime)
        }
        return true
    }

    private fun lift(stage: UIStage, id: Int, x: Float, y: Float, time: Long) {
        if (id == ui) {
            ui = null
            stage.touchUp(x, y)
        } else if (onPitch.remove(id) && onPitch.isEmpty()) {
            game.pitch.hold(false, time)
        }
    }

    private val pitchTakesFingers
        get() = game.playing != null && game.pitch.plan == game.playing && !game.pitch.paused
}
