package `in`.nann.smashhockey.core.feel

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * The motion vocabulary's spring (ADR 0005, `shared/data/motion.json`): named springs both platforms
 * read, integrated identically, so a bounce on Android is the bounce on iOS.
 */
data class SpringToken(val stiffness: Double, val damping: Double)

/**
 * A damped spring toward [target], integrated with semi-implicit Euler in fixed 1/240 s substeps —
 * the same equations, step and API as iOS's `Spring`, so a curve can be pinned by a golden vector.
 */
class Spring(val token: SpringToken, initial: Double = 0.0) {
    var value = initial
        private set
    var velocity = 0.0
    var target = initial
    private var carry = 0.0

    fun kick(impulse: Double) { velocity += impulse }

    /** Jumps to [v] and stops there — restarting a one-shot move. */
    fun snap(v: Double) {
        value = v
        target = v
        velocity = 0.0
        carry = 0.0
    }

    /**
     * Stops exactly on the target it is already at rest on, so a pose lands on its mark rather than
     * a hair short of it for ever.
     */
    fun settle() {
        value = target
        velocity = 0.0
        carry = 0.0
    }

    /** At rest on its target (to well below anything visible). */
    val isSettled: Boolean get() = abs(value - target) < 1e-3 && abs(velocity) < 1e-2

    fun advance(dt: Double) {
        carry += dt
        while (carry >= STEP) {
            val a = -token.stiffness * (value - target) - token.damping * velocity
            velocity += a * STEP
            value += velocity * STEP
            carry -= STEP
        }
    }

    companion object { const val STEP = 1.0 / 240.0 }
}

/**
 * An element's arrival and departure (conventions: UI) — the pure half of the UI kit's presence,
 * shared by both apps so a screen moves the same way on each, and so a test can pin it. The iOS twin
 * is `SmashCore.UIPresence`.
 *
 * It **terminates**: an arrival ends on its exact pose, and a leave always reaches [Phase.HIDDEN] —
 * whichever way it is being played. Both springs run whatever the motion setting is; Reduce Motion
 * only changes how the element is *drawn* (at rest, fading over `fadeSeconds`) and adds a second way
 * for a leave to finish. That is what keeps Reduce Motion turning on or off mid-flight — Android
 * reads the system setting every frame — from stranding an element half-gone on screen.
 */
class UIPresence(enter: SpringToken, exit: SpringToken) {
    enum class Phase { HIDDEN, SHOWN, LEAVING }

    var phase = Phase.HIDDEN
        private set

    /** 0…1, Reduce Motion's plain fade; 1 whenever the whimsical motion is playing. */
    var opacity = 0.0
        private set

    private val enter = Spring(enter)
    private val exit = Spring(exit)
    private var pendingPhase: Phase? = null
    private var pendingDelay = 0.0

    fun show(after: Double = 0.0) { pendingPhase = Phase.SHOWN; pendingDelay = after }

    fun hide(after: Double = 0.0) {
        if (phase == Phase.HIDDEN) { pendingPhase = null; return }   // an arrival not yet begun is cancelled
        pendingPhase = Phase.LEAVING
        pendingDelay = after
    }

    /** Visible or about to be: the element is (or will soon be) on screen. */
    val isVisible: Boolean get() = phase != Phase.HIDDEN || pendingPhase == Phase.SHOWN

    /** Arrived and not leaving — the only state in which it takes touches or reaches TalkBack. */
    val isSettledIn: Boolean get() = phase == Phase.SHOWN && pendingPhase == null && enter.value > 0.85

    /** 0…1(+overshoot) progress of the arrival, for elements that stage their own children. */
    val arrival: Double get() = enter.value

    /** 0…1 progress of the departure. */
    val departure: Double get() = exit.value

    /** One frame. [fadeSeconds] is Reduce Motion's fade (`motion.json` `fade.seconds`). */
    fun advance(dt: Double, reduceMotion: Boolean, fadeSeconds: Double) {
        pendingPhase?.let { p ->
            val left = pendingDelay - dt
            if (left > 0) pendingDelay = left else { pendingPhase = null; begin(p) }
        }
        // Both springs run under either setting: never snap a target away, or the transition the
        // other setting was playing can no longer finish.
        enter.advance(dt)
        exit.advance(dt)
        if (reduceMotion) {
            val goal = if (phase == Phase.SHOWN) 1.0 else 0.0
            val step = if (fadeSeconds > 0) dt / fadeSeconds else 1.0
            opacity = if (opacity < goal) min(goal, opacity + step) else max(goal, opacity - step)
        } else {
            opacity = 1.0
        }
        // A leave is over when the way it is being drawn says it is — the spring has run out, or the
        // fade has. Either one ends it.
        if (phase == Phase.LEAVING && (exit.value > 0.97 || exit.isSettled || (reduceMotion && opacity <= 0.0))) {
            phase = Phase.HIDDEN
            exit.settle()
        }
        // Arrived means arrived, on the mark.
        if (phase != Phase.LEAVING && enter.isSettled) enter.settle()
    }

    private fun begin(next: Phase) {
        when (next) {
            Phase.SHOWN -> {
                if (phase != Phase.SHOWN) { enter.snap(0.0); exit.snap(0.0); enter.target = 1.0 }
                phase = Phase.SHOWN
            }
            Phase.LEAVING -> {
                if (phase == Phase.HIDDEN) return
                if (phase != Phase.LEAVING) { exit.snap(0.0); exit.target = 1.0 }
                phase = Phase.LEAVING
            }
            Phase.HIDDEN -> phase = Phase.HIDDEN
        }
    }
}
