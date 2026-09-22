package `in`.nann.smashhockey.ui

import kotlin.math.sin

/**
 * Extruded lettering from the shared font (ADR 0005), placed by its centre, its left or its right
 * edge — the twin of iOS's `Label3D`. Changing the text swaps in a cached mesh.
 */
class Label3D(
    private val kit: Kit,
    text: String,
    val height: Float,
    private var colour: Int,
    val align: Align = Align.CENTRE,
    /** Wider than this, the lettering shrinks to fit (a long German word in a short slot). */
    val maxWidth: Float? = null,
    entrance: Entrance = Entrance.Pop,
) : Presentable {
    enum class Align { CENTRE, LEADING, TRAILING }

    override val node = kit.node(null)
    val body = kit.node(node)
    private val model = kit.text(text, height, colour, body)
    var text = text
        private set
    override val rest = Xform()
    val presence = Presence(entrance, kit.motion)

    init {
        realign()
        node.enabled = false
    }

    val width get() = kit.width(model) * body.transform.sx

    fun set(newText: String) {
        if (newText == text) return
        text = newText
        kit.retext(model, newText, height)
        realign()
    }

    override fun show(after: Double) = presence.show(after)
    override fun hide(after: Double) = presence.hide(after)

    fun setColour(rgb: Int) {
        if (rgb == colour) return
        colour = rgb
        model.recolour(rgb)
    }

    private fun realign() {
        val natural = kit.width(model)
        val m = maxWidth
        body.setScale(if (m != null && natural > m) m / natural else 1f)
        body.transform.tx = when (align) {
            Align.CENTRE -> 0f
            Align.LEADING -> width / 2
            Align.TRAILING -> -width / 2
        }
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
) : Semantic, Presentable {
    private class Letter(val node: UiNode, val presence: Presence, val x: Float) { val pose = Xform() }

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
        var x = 0f
        val parts = ArrayList<Pair<UiNode, Float>>()
        for (ch in text) {
            if (ch == ' ') { x += height * 0.35f; continue }
            val letter = kit.node(node)
            val m = kit.text(ch.toString(), height, colour, letter)
            val w = kit.width(m)
            parts += letter to x + w / 2
            x += w + tracking
        }
        val total = x - tracking
        for ((letter, cx) in parts) letters += Letter(letter, Presence(Entrance.Drop, kit.motion), cx - total / 2)
        bounds = Bounds(-total / 2, -height * 0.6f, 0f, total / 2, height * 0.6f, height * 0.4f)
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
            if (!ctx.reduceMotion) {
                val phase = (ctx.time / period + i * 0.12) * 2 * Math.PI
                t.ty = sin(phase).toFloat() * ctx.motion.idleBobMetres.toFloat() * 2 * bobScale
                t.rot.axisAngle(sin(phase + 1).toFloat() * 0.05f * bobScale, 0f, 0f, 1f)
            }
            l.presence.apply(l.node, t, ctx.reduceMotion)
        }
    }
}
