package `in`.nann.smashhockey.ui

import `in`.nann.smashhockey.core.feel.Scoreboard
import `in`.nann.smashhockey.ui.generated.DesignTokens.Colour
import kotlin.math.abs
import `in`.nann.smashhockey.engine.Spring

/**
 * One flip card: a dark tile with a character on each face. A change writes the new character on
 * the hidden face and turns the card half a revolution about its horizontal axis, top edge falling
 * toward the viewer like a split-flap, on the `snappy` spring — so it clacks a little past the
 * stop and settles. A card may show **nothing** ([Scoreboard.BLANK]) — the tens card of a
 * single-digit score — and flips from blank to a digit like any other change.
 */
private class FlipCard(
    private val kit: Kit,
    c: Char,
    parent: UiNode,
    w: Float, h: Float, depth: Float,
    private val textHeight: Float,
    cardColour: Int, ink: Int,
) {
    val node = kit.node(parent)
    private val faceNodes: Array<UiNode>
    private val faces = arrayOfNulls<UiNode>(2)
    private val ink = ink
    private val turn = Spring(kit.motion.spring(SpringName.SNAPPY))
    private var flips = 0
    var shown: Char = c
        private set
    private var queued: Char? = null
    var onLanded: (() -> Unit)? = null

    init {
        kit.slab(w, h, depth, cardColour, node, corner = minOf(w, h) * 0.12f)
        val frontNode = kit.node(node)
        val backNode = kit.node(node)
        frontNode.setPosition(0f, 0f, depth / 2)
        backNode.setPosition(0f, 0f, -depth / 2)
        // Upside down on the back: after half a turn about X it reads the right way up.
        backNode.setRotation(Quat().axisAngle(Math.PI.toFloat(), 1f, 0f, 0f))
        faceNodes = arrayOf(frontNode, backNode)
        // A hairline across the middle, the split-flap's split.
        kit.slab(w * 1.001f, h * 0.025f, depth * 1.02f, Colour.BOARD, node, corner = 0f)
        write(0, c)
        write(1, c)
    }

    /** Puts [c] on face [i] — a blank card carries no lettering at all. */
    private fun write(i: Int, c: Char) {
        if (c == Scoreboard.BLANK) {
            faces[i]?.let { kit.destroy(it) }
            faces[i] = null
            return
        }
        val face = faces[i]
        if (face != null) kit.retext(face, c.toString(), textHeight)
        else faces[i] = kit.text(c.toString(), textHeight, ink, faceNodes[i])
    }

    fun set(c: Char) {
        if (flipping) { queued = c; return }
        if (c == shown) return
        start(c)
    }

    private val flipping get() = abs(turn.value - turn.target) > 0.35

    private fun start(c: Char) {
        KitSound.flip()
        flips += 1
        write(flips % 2, c)
        shown = c
        turn.target = flips * Math.PI
    }

    fun update(dt: Double, reduceMotion: Boolean) {
        val wasFlipping = flipping
        if (reduceMotion) turn.snap(turn.target) else turn.advance(dt)
        node.transform.rot.axisAngle(turn.value.toFloat(), 1f, 0f, 0f)
        node.changed()
        if (wasFlipping && !flipping) onLanded?.invoke()
        val q = queued
        if (!flipping && q != null) {
            queued = null
            if (q != shown) start(q)
        }
    }
}

/**
 * A scoreboard number or clock whose characters flip like split-flap tiles when they change — the
 * twin of iOS's `FlipDigits`. Separators (":", "-", ".", "/") are fixed lettering between the cards;
 * a blank is **not** one — it is a card showing nothing, so a score can grow a digit without the
 * board changing shape.
 * [cardW]×[cardH] is one tile; the text height follows it.
 */
class FlipDigits(
    kit: Kit,
    initial: String,
    cardW: Float, cardH: Float,
    id: String,
    label: String,
    cardColour: Int = Colour.CARD,
    ink: Int = Colour.CARD_INK,
    entrance: Entrance = Entrance.Pop,
) : Semantic, Presentable {
    override val node = kit.node(null)
    val body = kit.node(node)
    override val rest = Xform()
    val presence = Presence(entrance, kit.motion)
    override val semantics = Semantics(id, label, initial, Semantics.Trait.STATIC_TEXT)
    private val cards = arrayOfNulls<FlipCard>(initial.length)
    private var text = initial
    private val jiggle = Jiggle(kit.motion.spring(SpringName.WOBBLY))
    private val motion = kit.motion
    override val bounds: Bounds
    /** Called when any card lands — a housing can thud with it. */
    var onLanded: (() -> Unit)? = null

    init {
        val depth = cardW * 0.35f
        val textHeight = cardH * 0.62f
        val gap = cardW * 0.08f
        val sepWidth = cardW * 0.45f
        val widths = FloatArray(initial.length) { if (isSeparator(initial[it])) sepWidth else cardW }
        val total = widths.sum() + gap * maxOf(0, widths.size - 1)
        var x = -total / 2
        for ((i, c) in initial.withIndex()) {
            val cx = x + widths[i] / 2
            if (isSeparator(c)) {
                val sep = kit.node(body)
                sep.setPosition(cx, 0f, 0f)
                kit.text(c.toString(), textHeight * 0.8f, ink, sep)
            } else {
                val card = FlipCard(kit, c, body, cardW, cardH, depth, textHeight, cardColour, ink)
                card.node.setPosition(cx, 0f, 0f)
                card.onLanded = { landed() }
                cards[i] = card
            }
            x += widths[i] + gap
        }
        bounds = Bounds(-total / 2, -cardH / 2, -depth / 2, total / 2, cardH / 2, depth / 2)
        node.enabled = false
    }

    override val boundsNode get() = node
    override val isPresent get() = presence.isSettledIn
    val width get() = bounds.width

    override fun show(after: Double) = presence.show(after)
    override fun hide(after: Double) = presence.hide(after)

    /** Shows [newText] (same length and separators as the initial text); changed cards flip. */
    fun set(newText: String) {
        require(newText.length == text.length) { "FlipDigits keeps its layout: '$newText' vs '$text'" }
        if (newText == text) return
        text = newText
        semantics.value = newText
        for (i in cards.indices) cards[i]?.set(newText[i])
    }

    /** The celebratory wobble — a goal. */
    fun celebrate() {
        val k = motion.kick(KickName.CELEBRATE)
        jiggle.kick(k * 0.4, k * 0.6)
    }

    private fun landed() {
        jiggle.kick(0.0, -motion.kick(KickName.CELEBRATE) * 0.08)
        onLanded?.invoke()
    }

    override fun update(dt: Double, ctx: UiContext) {
        presence.advance(dt, ctx)
        presence.apply(node, rest, ctx.reduceMotion)
        if (!node.enabled) return
        for (i in cards.indices) cards[i]?.update(dt, ctx.reduceMotion)
        jiggle.advance(dt, ctx.reduceMotion)
        body.transform.rot.set(jiggle.rotation)
        body.setScale(jiggle.scale)
    }

    private companion object {
        /** A character printed between the cards rather than on one. A blank is not one. */
        fun isSeparator(c: Char) = c == ':' || c == '-' || c == '.' || c == '/'
    }
}
