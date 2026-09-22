package `in`.nann.smashhockey.ui

import `in`.nann.smashhockey.ui.DesignTokens.Colour
import `in`.nann.smashhockey.ui.DesignTokens.Size
import kotlin.math.max
import kotlin.math.min

/**
 * A puck on a rail, for the coach's board values 0–1 — the twin of iOS's `Slider3D`. Grab it
 * anywhere on the row and drag; the puck chases the finger on the `bouncy` spring, leans into the
 * direction it travels and squashes while held. The fill behind it shows the value. TalkBack
 * adjusts it in steps.
 */
class Slider3D(
    private val kit: Kit,
    title: String,
    id: String,
    value: Double,
    val length: Float = 1.4f,
    private val step: Double = 0.05,
    entrance: Entrance = Entrance.Slide(fromLeft = true),
) : Interactive, Presentable {
    override val node = kit.node(null)
    private val body = kit.node(node)
    private val fill: UiNode
    private val puck = kit.node(body)
    private val readout: UiNode
    override val semantics = Semantics(id, title, percent(value), Semantics.Trait.ADJUSTABLE)
    val rest = Xform()
    val presence = Presence(entrance, kit.motion)
    var value = value
        private set
    var onChange: ((Double) -> Unit)? = null
    private val motion = kit.motion
    private val knob = Spring(motion.bouncy, value)
    private val grab = Spring(motion.bouncy)
    private var held = false
    private val rowHeight = 0.34f

    init {
        val railH = Size.RAIL_HEIGHT
        kit.slab(length + railH, railH, railH, Colour.RAIL, body, corner = railH / 2)
        fill = kit.slab(1f, railH * 1.25f, railH * 1.25f, Colour.SUN, body, corner = 0f)
        val r = Size.KNOB_RADIUS
        val upright = Quat().axisAngle((Math.PI / 2).toFloat(), 1f, 0f, 0f)
        kit.cylinder(Size.KNOB_DEPTH, r, Colour.INK, puck).setRotation(upright)
        val cap = kit.cylinder(Size.KNOB_DEPTH * 0.3f, r * 0.55f, Colour.CREAM, puck)
        cap.setRotation(upright)
        cap.setPosition(0f, 0f, Size.KNOB_DEPTH * 0.5f)
        puck.setPosition(0f, 0f, railH)

        val titleNode = kit.node(body)
        val readoutNode = kit.node(body)
        val titleText = kit.text(title, Size.TEXT_BODY, Colour.CREAM, titleNode)
        readout = kit.text(percent(value), Size.TEXT_BODY, Colour.SUN, readoutNode)
        titleNode.setPosition(-length / 2 + kit.width(titleText) / 2, 0.12f, 0f)
        readoutNode.setPosition(length / 2 - 0.12f, 0.12f, 0f)
        node.enabled = false
    }

    override val boundsNode get() = node
    override val bounds = Bounds(-length / 2 - 0.1f, -rowHeight / 2 + 0.02f, -0.1f, length / 2 + 0.1f, rowHeight / 2, 0.15f)
    override val isPresent get() = presence.isSettledIn

    override fun show(after: Double) = presence.show(after)
    override fun hide(after: Double) { held = false; presence.hide(after) }

    fun set(v: Double, notify: Boolean = true) {
        val q = min(1.0, max(0.0, (v / 0.01).roundHalfAway() * 0.01))
        if (q == value) return
        value = q
        knob.target = q
        semantics.value = percent(q)
        kit.retext(readout, percent(q), Size.TEXT_BODY)
        if (notify) onChange?.invoke(q)
    }

    private fun follow(ray: TouchRay) {
        val x = ray.planeX() ?: return     // the stage hands rays in our own space
        set(((x + length / 2) / length).toDouble())
    }

    override fun touchDown(ray: TouchRay) {
        held = true
        grab.target = 1.0
        grab.kick(motion.kick(KickName.GRAB))
        follow(ray)
    }

    override fun touchMoved(ray: TouchRay) { if (held) follow(ray) }

    override fun touchUp(ray: TouchRay, inside: Boolean) {
        held = false
        grab.target = 0.0
    }

    override fun activate() = grab.kick(motion.kick(KickName.GRAB))

    override fun adjust(steps: Int) {
        set(((value + steps * step) / step).roundHalfAway() * step)
        grab.kick(motion.kick(KickName.GRAB))
    }

    override fun update(dt: Double, ctx: UiContext) {
        presence.advance(dt, ctx)
        presence.apply(node, rest, ctx.reduceMotion)
        if (!node.enabled) return
        if (ctx.reduceMotion) {
            knob.snap(value)
            grab.snap(if (held) 1.0 else 0.0)
        } else {
            knob.advance(dt)
            grab.advance(dt)
        }
        val k = min(1.08, max(-0.08, knob.value)).toFloat()
        val x = -length / 2 + k * length
        val g = grab.value.toFloat()
        // Lean into the travel, squash while held.
        val lean = max(-0.5, min(0.5, knob.velocity * 0.12)).toFloat()
        puck.transform.tx = x
        puck.transform.rot.axisAngle(-lean, 0f, 0f, 1f)
        puck.setScale(1 + 0.25f * g, 1 + 0.25f * g, 1 - 0.3f * g)
        val w = max(0.001f, x + length / 2)
        fill.transform.sx = w
        fill.transform.tx = -length / 2 + w / 2
        fill.changed()
    }

    private companion object {
        fun percent(v: Double) = "${(v * 100).roundHalfAway().toInt()}%"
        /** Swift's `rounded()`: half away from zero (Kotlin's `round` is half-even). */
        fun Double.roundHalfAway(): Double = if (this >= 0) kotlin.math.floor(this + 0.5) else -kotlin.math.floor(-this + 0.5)
    }
}
