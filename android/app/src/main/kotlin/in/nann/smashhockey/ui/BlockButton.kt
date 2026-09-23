package `in`.nann.smashhockey.ui

import `in`.nann.smashhockey.ui.generated.DesignTokens.Colour
import `in`.nann.smashhockey.ui.generated.DesignTokens.Size
import kotlin.math.max
import kotlin.math.sin
import `in`.nann.smashhockey.core.feel.TextLayout
import `in`.nann.smashhockey.engine.Spring

/**
 * A chunky toy key: a rounded cap sitting in a darker base — the twin of iOS's `BlockButton`.
 * Touch-down squashes the cap and holds it squashed; lifting lets it spring back through a
 * stretch — and fires, if the finger is still on it. A disabled button greys out and shakes its
 * head ("nope") instead.
 */
class BlockButton(
    private val kit: Kit,
    title: String,
    id: String,
    private val style: Style = Style.PRIMARY,
    width: Float = Size.BUTTON_WIDTH,
    height: Float = Size.BUTTON_HEIGHT,
    textHeight: Float = Size.TEXT_BUTTON,
    entrance: Entrance = Entrance.Drop,
    /** What TalkBack reads, when the caption alone does not say it ("II" is Pause). */
    label: String? = null,
    var action: () -> Unit,
) : Interactive, Presentable {
    class Style(val cap: Int, val base: Int, val ink: Int) {
        companion object {
            val PRIMARY = Style(Colour.SUN, Colour.SUN_SHADE, Colour.INK)
            val SECONDARY = Style(Colour.GREEN, Colour.GREEN_INK, Colour.INK)
            val QUIET = Style(Colour.PAPER, Colour.PAPER_SHADE, Colour.INK)
            val DANGER = Style(Colour.PINK, Colour.PINK_INK, Colour.INK)
            val DISABLED = Style(Colour.DISABLED, Colour.DISABLED_SHADE, Colour.DISABLED_INK)
        }
    }

    override val node = kit.node(null)
    private val body = kit.node(node)
    private val base: UiNode
    private val cap: UiNode
    private val holders = ArrayList<UiNode>(2)
    private val labels = ArrayList<UiNode>(2)
    val w = width
    /**
     * How tall the key stands. A caption too wide for the cap wraps to two lines (§16.4) rather
     * than shrinking to a smear, and the key grows to hold them — so the words sit on it, not
     * over it.
     */
    val h = maxOf(height, (TextLayout.stackHeight(
        TextLayout.caption(title, textHeight.toDouble(), TextLayout.room(width.toDouble(), textHeight.toDouble())).size,
        textHeight.toDouble()) + 2 * textHeight * TextLayout.MARGIN_PER_HEIGHT).toFloat())
    override val semantics = Semantics(id, label ?: title, trait = Semantics.Trait.BUTTON)
    private val labelNode: UiNode
    private val textHeight = textHeight
    override val rest = Xform()
    val presence = Presence(entrance, kit.motion)
    /** A gentle idle bob — for the one button a screen wants the thumb on. */
    var bobs = false
    private val motion = kit.motion
    private val press = Spring(motion.bouncy)
    private val nope = Jiggle(motion.spring(SpringName.WOBBLY))
    private var held = false
    private val bobbed = Xform()
    private val bobTurn = Quat()

    init {
        val d = Size.BUTTON_DEPTH
        val inset = Size.BUTTON_BASE_INSET
        base = kit.slab(w - 2 * inset, h - 2 * inset, d * 0.5f, style.base, node)
        base.setPosition(0f, 0f, -d * 0.3f)
        cap = kit.slab(w, h, d, style.cap, body)
        labelNode = kit.node(body)
        labelNode.setPosition(0f, 0f, d / 2)
        letter(title)
        node.enabled = false
    }

    /**
     * Lays the caption out on the cap: at most two centred lines, a margin of lettering either
     * side, and a shrink only when a line still has nowhere to break.
     */
    private fun letter(title: String) {
        for (holder in holders) kit.destroy(holder)
        holders.clear()
        labels.clear()
        val ink = if (semantics.isEnabled) style.ink else Style.DISABLED.ink
        val room = TextLayout.room(w.toDouble(), textHeight.toDouble())
        val lines = TextLayout.caption(title, textHeight.toDouble(), room)
        for ((i, line) in lines.withIndex()) {
            val holder = kit.node(labelNode)
            holder.setPosition(0f, TextLayout.stackY(i, lines.size, textHeight.toDouble()).toFloat(), 0f)
            holders += holder
            labels += kit.text(line, textHeight, ink, holder)
        }
        labelNode.setScale(TextLayout.fit(TextLayout.widest(lines, textHeight.toDouble()), room).toFloat())
    }

    /**
     * A new caption (and TalkBack label). The key keeps the height it was built at, so a screen's
     * row of buttons stays a row: a longer caption wraps and, if it must, shrinks within it.
     */
    fun retitle(title: String) {
        letter(title)
        semantics.label = title
    }

    var isEnabled: Boolean
        get() = semantics.isEnabled
        set(v) {
            if (v == semantics.isEnabled) return
            semantics.isEnabled = v
            val s = if (v) style else Style.DISABLED
            cap.recolour(s.cap)
            base.recolour(s.base)
            for (m in labels) m.recolour(s.ink)
        }

    override val boundsNode get() = node
    override val bounds = Bounds(-w / 2 - 0.02f, -h / 2 - 0.03f, -Size.BUTTON_DEPTH / 2,
        w / 2 + 0.02f, h / 2 + 0.03f, Size.BUTTON_DEPTH / 2)     // a little forgiving
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
        press.kick(motion.pressKick * 0.5)
    }

    override fun touchUp(ray: TouchRay, inside: Boolean) {
        if (!held) return
        held = false
        press.target = 0.0
        press.kick(-motion.pressKick * 0.6)      // spring back through a stretch
        if (inside) { KitSound.press(); action() }
    }

    /** TalkBack's activation, and the sketch's autoplay: the same squash and the same action. */
    override fun activate() {
        if (!isEnabled) { nope.kick(motion.kick(KickName.NOPE), 0.0); KitSound.refuse(); return }
        press.kick(motion.pressKick)
        KitSound.press()
        action()
    }

    override fun update(dt: Double, ctx: UiContext) {
        presence.advance(dt, ctx)
        bobbed.set(rest)
        if (bobs && !ctx.reduceMotion && presence.isSettledIn) {
            val phase = ctx.time / ctx.motion.idleBobSeconds * 2 * Math.PI
            bobbed.ty += sin(phase).toFloat() * ctx.motion.idleBobMetres.toFloat()
            bobbed.rot.mul(rest.rot, bobTurn.axisAngle(sin(phase * 0.5).toFloat() * 0.03f, 0f, 0f, 1f))
        }
        presence.apply(node, bobbed, ctx.reduceMotion)
        if (!node.enabled) return

        if (ctx.reduceMotion) press.snap(if (held) motion.pressHold * 0.3 else 0.0)    // a small, still dip while held
        else press.advance(dt)
        nope.advance(dt, ctx.reduceMotion)
        val s = press.value.toFloat()
        val bulge = 1 + motion.pressBulge.toFloat() * s
        val j = nope.scale
        body.transform.sx = bulge * j; body.transform.sy = (1 - motion.pressSquash.toFloat() * s) * j; body.transform.sz = bulge * j
        body.transform.tz = -0.04f * max(0f, s)
        body.transform.rot.set(nope.rotation)
        body.changed()
    }
}
