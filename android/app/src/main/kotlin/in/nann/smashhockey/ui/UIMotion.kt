package `in`.nann.smashhockey.ui

import kotlin.math.max
import kotlin.math.min
import `in`.nann.smashhockey.core.feel.UIPresence
import `in`.nann.smashhockey.engine.Spring

/** How an element arrives. Leaving is always the same goofy exit: a hop, a spin, a fall. */
sealed class Entrance {
    /** Grows from nothing, stretching tall as it overshoots. */
    data object Pop : Entrance()
    /** Tips up from lying flat, like a sign on a hinge. */
    data object Tumble : Entrance()
    /** Falls in from above and squashes on landing. */
    data object Drop : Entrance()
    /** Rolls in from the left or the right. */
    data class Slide(val fromLeft: Boolean) : Entrance()
}

/**
 * An element's arrival and departure on screen: the core's [UIPresence] (which decides *when* an
 * element is arriving, arrived, leaving or gone, and is pinned by `FeelTest`) plus this app's half —
 * how it is posed while it does. `pop` in, `soft` out, and under Reduce Motion plain fades of
 * `fade.seconds` with no movement at all (conventions: UI). The twin of iOS's `Presence`.
 */
class Presence(var style: Entrance, motion: Motion) {
    private val core = UIPresence(motion.spring(SpringName.POP), motion.spring(SpringName.SOFT))

    val phase: UIPresence.Phase get() = core.phase

    // Scratch for apply(): nothing is allocated per frame.
    private val pose = Xform()
    private val turn = Quat()
    private val spinQ = Quat()

    fun show(after: Double = 0.0) = core.show(after)

    fun hide(after: Double = 0.0) = core.hide(after)

    /** Visible or about to be: the element is (or will soon be) on screen. */
    val isVisible: Boolean get() = core.isVisible

    /** Arrived and not leaving — the only state in which it takes touches or reaches TalkBack. */
    val isSettledIn: Boolean get() = core.isSettledIn

    /** 0…1(+overshoot) progress of the arrival, for elements that stage their own children. */
    val arrival: Double get() = core.arrival

    fun advance(dt: Double, ctx: UiContext) = core.advance(dt, ctx.reduceMotion, ctx.motion.fadeSeconds)

    /** Poses [node] at [rest] bent by the arrival or departure, and fades it under Reduce Motion. */
    fun apply(node: UiNode, rest: Xform, reduceMotion: Boolean) {
        val visible = core.phase != UIPresence.Phase.HIDDEN
        node.enabled = visible
        if (!visible) return
        if (reduceMotion) {
            node.setTransform(rest)
            node.opacity = core.opacity.toFloat()
            return
        }
        val a = core.arrival.toFloat()
        val x = core.departure.toFloat()
        var ox = 0f; var oy = 0f; var oz = 0f
        var kx = 1f; var ky = 1f; var kz = 1f
        turn.identity()
        when (val s = style) {
            Entrance.Pop -> {
                val g = max(0f, a)
                kx = g - (g - 1) * 0.5f; ky = g + (g - 1) * 0.9f; kz = g
            }
            Entrance.Tumble -> {
                turn.axisAngle((1 - a) * 1.5f, 1f, 0f, 0f)
                oy = -(1 - a) * 0.25f
                val g = min(1f, max(0f, a) * 2.5f)
                kx = g; ky = g; kz = g
            }
            Entrance.Drop -> {
                oy = (1 - a) * 1.4f
                val squash = max(0f, a - 1) * 2.2f
                kx = 1 + squash * 0.6f; ky = 1 - squash; kz = 1 + squash * 0.6f
            }
            is Entrance.Slide -> {
                val side = if (s.fromLeft) -1f else 1f
                ox = side * (1 - a) * 2.4f
                turn.axisAngle(-side * (1 - a) * 1.2f, 0f, 0f, 1f)
            }
        }
        if (x > 0.001f) {
            val spin = if (rest.tx >= 0) 1f else -1f
            ox += spin * x * 0.35f; oy += x * 0.45f - x * x * 1.9f; oz += 0.15f * x
            turn.mul(spinQ.axisAngle(-spin * x * 1.4f, 0f, 0f, 1f), turn)
            val k = 1 - 0.45f * x
            kx *= k; ky *= k; kz *= k
        }
        pose.set(rest)
        pose.tx += ox; pose.ty += oy; pose.tz += oz
        pose.rot.mul(rest.rot, turn)
        pose.sx = rest.sx * kx; pose.sy = rest.sy * ky; pose.sz = rest.sz * kz
        node.setTransform(pose)
        node.opacity = if (x > 0.6f) 1 - (x - 0.6f) / 0.4f else 1f
    }
}

/**
 * A jelly wobble — a twist about Z and a swell — on the `wobbly` spring: the celebration, the
 * "nope" of a disabled button, the thud of a flipped score.
 */
class Jiggle(token: `in`.nann.smashhockey.engine.SpringToken) {
    private val twist = Spring(token)
    private val swell = Spring(token)
    private val q = Quat()

    /** [twist] in radians/s of angular kick, [swell] in scale units/s. */
    fun kick(twist: Double, swell: Double) {
        this.twist.kick(twist)
        this.swell.kick(swell)
    }

    fun advance(dt: Double, reduceMotion: Boolean) {
        if (reduceMotion) { twist.snap(0.0); swell.snap(0.0); return }
        twist.advance(dt)
        swell.advance(dt)
    }

    /** The twist as a rotation (a scratch quaternion — read it, don't keep it). */
    val rotation: Quat get() = q.axisAngle(twist.value.toFloat(), 0f, 0f, 1f)
    val scale: Float get() = 1 + swell.value.toFloat()
}
