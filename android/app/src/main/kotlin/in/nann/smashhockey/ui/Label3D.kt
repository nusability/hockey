package `in`.nann.smashhockey.ui

import kotlin.math.sin
import `in`.nann.smashhockey.core.feel.TextLayout
import `in`.nann.smashhockey.ui.generated.DesignTokens

/**
 * Extruded lettering from the shared font (ADR 0005), placed by its centre, its left or its right
 * edge — the twin of iOS's `Label3D`. Changing the text swaps in a cached mesh.
 *
 * A caption wider than [maxWidth] **wraps to two centred lines** before it is allowed to shrink
 * (spec §16.4, core `TextLayout.caption`): a long German label stays legible rather than being
 * squeezed to a smear. Only a caption with nowhere to break — one long word — still shrinks.
 */
class Label3D(
    private val kit: Kit,
    text: String,
    val height: Float,
    private var colour: Int,
    val align: Align = Align.CENTRE,
    /** Wider than this, the lettering wraps to two lines, and only then shrinks to fit. */
    val maxWidth: Float? = null,
    entrance: Entrance = Entrance.Pop,
) : Presentable {
    enum class Align { CENTRE, LEADING, TRAILING;

        /** The core's alignment — the kit and both platforms name the same three. */
        val shared: TextLayout.Align
            get() = when (this) {
                CENTRE -> TextLayout.Align.CENTRE
                LEADING -> TextLayout.Align.LEADING
                TRAILING -> TextLayout.Align.TRAILING
            }
    }

    override val node = kit.node(null)
    val body = kit.node(node)
    private val holders = ArrayList<UiNode>(2)
    private val models = ArrayList<UiNode>(2)
    var text = text
        private set
    override val rest = Xform()
    val presence = Presence(entrance, kit.motion)
    /** The widest line's layout width, before [body]'s shrink. */
    private var natural = 0f

    init {
        reletter()
        node.enabled = false
    }

    val width get() = natural * body.transform.sx

    fun set(newText: String) {
        if (newText == text) return
        text = newText
        reletter()
    }

    override fun show(after: Double) = presence.show(after)
    override fun hide(after: Double) = presence.hide(after)

    fun setColour(rgb: Int) {
        if (rgb == colour) return
        colour = rgb
        for (m in models) m.recolour(rgb)
    }

    /** Re-meshes the caption, wrapped to at most two lines, and re-aligns the block. */
    private fun reletter() {
        for (h in holders) kit.destroy(h)
        holders.clear()
        models.clear()
        val lines = maxWidth?.let { TextLayout.caption(text, height.toDouble(), it.toDouble()) } ?: listOf(text)
        for ((i, line) in lines.withIndex()) {
            val holder = kit.node(body)
            holder.setPosition(0f, TextLayout.stackY(i, lines.size, height.toDouble()).toFloat(), 0f)
            holders += holder
            models += kit.text(line, height, colour, holder)
        }
        natural = TextLayout.widest(lines, height.toDouble()).toFloat()
        body.setScale(TextLayout.fit(natural.toDouble(), maxWidth?.toDouble()).toFloat())
        body.transform.tx = TextLayout.alignX(align.shared, width.toDouble()).toFloat()
        body.changed()
    }

    override fun update(dt: Double, ctx: UiContext) {
        presence.advance(dt, ctx)
        presence.apply(node, rest, ctx.reduceMotion)
    }
}

/**
 * A word whose letters arrive one by one — each drops in, squashes, and then keeps bobbing on a
 * travelling wave — the twin of iOS's `WaveText`. The title's logo; also "GOAL!" and "FULL TIME".
 *
 * A banner too wide for the frame **wraps to two centred lines** (spec §16.4, core
 * `TextLayout.caption`) — "END OF PERIOD 1" and "ENDE 1. DRITTEL" break in the same place on both
 * phones — and only shrinks when there is nowhere to break.
 */
class WaveText(
    kit: Kit,
    text: String,
    height: Float,
    colour: Int,
    tracking: Float = 0.02f,
    bob: Float = 1f,
    maxWidth: Float = DesignTokens.Size.FRAME_WIDTH - 0.1f,
    id: String,
    /** How each letter arrives: dropped in by default; a big moment pops them (§16.4). */
    private val entrance: Entrance = Entrance.Drop,
) : Semantic, Presentable {
    private class Letter(val node: UiNode, val presence: Presence, val x: Float, val y: Float) { val pose = Xform() }

    override val node = kit.node(null)
    override val rest = Xform()
    override val semantics = Semantics(id, text, trait = Semantics.Trait.HEADER)
    private val letters = ArrayList<Letter>()
    private var shown = false
    private val bobScale = bob
    override val bounds: Bounds
    private val stagger = kit.motion.staggerSeconds
    private val fit: Float
    private val pose = Xform()

    init {
        val lines = TextLayout.caption(text, height.toDouble(), maxWidth.toDouble())
        var total = 0f
        for ((index, line) in lines.withIndex()) {
            var x = 0f
            val row = ArrayList<Pair<UiNode, Float>>()
            for (ch in line) {
                if (ch == ' ') { x += height * 0.35f; continue }
                val letter = kit.node(node)
                val m = kit.text(ch.toString(), height, colour, letter)
                val w = kit.width(m)
                row += letter to x + w / 2
                x += w + tracking
            }
            val lineWidth = maxOf(0f, x - tracking)
            total = maxOf(total, lineWidth)
            val y = TextLayout.stackY(index, lines.size, height.toDouble()).toFloat()
            for ((letter, cx) in row) letters += Letter(letter, Presence(entrance, kit.motion), cx - lineWidth / 2, y)
        }
        val halfHeight = maxOf(height * 0.6f, TextLayout.stackHeight(lines.size, height.toDouble()).toFloat() / 2)
        bounds = Bounds(-total / 2, -halfHeight, 0f, total / 2, halfHeight, height * 0.4f)
        fit = if (total > maxWidth) maxWidth / total else 1f
        node.enabled = false
    }

    override val boundsNode get() = node
    override val isPresent get() = shown && (letters.lastOrNull()?.presence?.isSettledIn ?: false)

    override fun show(after: Double) {
        shown = true
        for (i in letters.indices) letters[i].presence.show(after + i * stagger)
    }

    override fun hide(after: Double) {
        shown = false
        for (i in letters.indices) letters[i].presence.hide(after + i * stagger * 0.5)
    }

    override fun update(dt: Double, ctx: UiContext) {
        var anyVisible = false
        for (i in 0 until letters.size) if (letters[i].presence.isVisible) { anyVisible = true; break }
        node.enabled = anyVisible
        pose.set(rest)
        pose.sx *= fit; pose.sy *= fit; pose.sz *= fit
        node.setTransform(pose)
        if (!anyVisible) return
        val period = ctx.motion.idleBobSeconds
        for (i in 0 until letters.size) {
            val l = letters[i]
            l.presence.advance(dt, ctx)
            val t = l.pose.identity()
            t.tx = l.x
            t.ty = l.y
            if (!ctx.reduceMotion) {
                val phase = (ctx.time / period + i * 0.12) * 2 * Math.PI
                t.ty += sin(phase).toFloat() * ctx.motion.idleBobMetres.toFloat() * 2 * bobScale
                t.rot.axisAngle(sin(phase + 1).toFloat() * 0.05f * bobScale, 0f, 0f, 1f)
            }
            l.presence.apply(l.node, t, ctx.reduceMotion)
        }
    }
}
