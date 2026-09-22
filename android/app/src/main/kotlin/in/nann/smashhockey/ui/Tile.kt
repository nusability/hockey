package `in`.nann.smashhockey.ui

import `in`.nann.smashhockey.engine.Spring
import `in`.nann.smashhockey.ui.generated.DesignTokens.Colour
import `in`.nann.smashhockey.ui.generated.DesignTokens.Size
import kotlin.math.max
import kotlin.math.min

/**
 * A card you can press — the twin of iOS's `Tile`: a slab with anything on its face — a club, a
 * kit swatch, a world, a formation, a drill, a text field. Touch-down sinks it, lifting springs it
 * back and fires if the finger is still on it; a selected tile lifts toward you in its highlight
 * colour with a happy wobble; a disabled one greys out and shakes its head. Children go on
 * [content], whose z = 0 is the face.
 */
class Tile(
    kit: Kit,
    val w: Float, val h: Float,
    private val colour: Int,
    private val selectedColour: Int = Colour.SUN,
    depth: Float = Size.SLAB_DEPTH * 0.8f,
    halo: Boolean = false,
    id: String,
    label: String,
    entrance: Entrance = Entrance.Pop,
    var action: () -> Unit,
) : Interactive, Presentable {
    override val node = kit.node(null)
    val body = kit.node(node)
    private val haloNode: UiNode?
    private val slab: UiNode
    val content: UiNode
    override val semantics = Semantics(id, label, trait = Semantics.Trait.BUTTON)
    override val rest = Xform()
    val presence = Presence(entrance, kit.motion)
    private val motion = kit.motion
    private val press = Spring(motion.bouncy)
    private val lift = Spring(motion.spring(SpringName.POP))
    private val nope = Jiggle(motion.spring(SpringName.WOBBLY))
    private var held = false

    init {
        val corner = min(Size.CORNER, h * 0.3f)
        // A swatch keeps its own colour when chosen: a paper frame behind it says so instead.
        haloNode = if (halo) kit.slab(w + 0.04f, h + 0.04f, depth * 0.6f, Colour.PAPER, body, corner).also {
            it.setPosition(0f, 0f, -depth * 0.3f)
            it.enabled = false
        } else null
        slab = kit.slab(w, h, depth, colour, body, corner)
        content = kit.node(body)
        content.setPosition(0f, 0f, depth / 2)
        node.enabled = false
    }

    var isSelected = false
        set(v) {
            if (v == field) return
            field = v
            semantics.isSelected = v
            paint()
            lift.target = if (v) 1.0 else 0.0
            if (v) nope.kick(0.0, motion.kick(KickName.CELEBRATE) * 0.25)
        }

    var isEnabled: Boolean
        get() = semantics.isEnabled
        set(v) {
            if (v == semantics.isEnabled) return
            semantics.isEnabled = v
            paint()
        }

    fun relabel(label: String) { semantics.label = label }

    private fun paint() {
        slab.recolour(if (!isEnabled) Colour.DISABLED else if (isSelected) selectedColour else colour)
        haloNode?.enabled = isSelected
    }

    override val boundsNode get() = node
    override val bounds = Bounds(-w / 2, -h / 2, -Size.SLAB_DEPTH / 2, w / 2, h / 2, Size.SLAB_DEPTH / 2)
    override val isPresent get() = presence.isSettledIn

    override fun show(after: Double) = presence.show(after)
    override fun hide(after: Double) {
        held = false
        press.target = 0.0
        presence.hide(after)
    }

    override fun touchDown(ray: TouchRay) {
        if (!isEnabled) { nope.kick(motion.kick(KickName.NOPE), 0.0); KitSound.refuse(); return }
        held = true
        press.target = motion.pressHold
        press.kick(motion.pressKick * 0.4)
    }

    override fun touchUp(ray: TouchRay, inside: Boolean) {
        if (!held) return
        held = false
        press.target = 0.0
        press.kick(-motion.pressKick * 0.5)
        if (inside) { KitSound.press(); action() }
    }

    override fun activate() {
        if (!isEnabled) { nope.kick(motion.kick(KickName.NOPE), 0.0); KitSound.refuse(); return }
        press.kick(motion.pressKick)
        KitSound.press()
        action()
    }

    override fun update(dt: Double, ctx: UiContext) {
        presence.advance(dt, ctx)
        presence.apply(node, rest, ctx.reduceMotion)
        if (!node.enabled) return
        if (ctx.reduceMotion) {
            press.snap(if (held) motion.pressHold * 0.3 else 0.0)
            lift.snap(lift.target)
        } else {
            press.advance(dt)
            lift.advance(dt)
        }
        nope.advance(dt, ctx.reduceMotion)
        val s = press.value.toFloat() * 0.5f
        val l = lift.value.toFloat()
        val grow = (1 + 0.05f * l) * nope.scale
        body.transform.sx = grow * (1 + 0.04f * s)
        body.transform.sy = grow * (1 - 0.1f * s)
        body.transform.sz = grow
        body.transform.tz = 0.05f * l - 0.03f * max(0f, s)
        body.transform.rot.set(nope.rotation)
        body.changed()
    }
}
