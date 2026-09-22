package `in`.nann.smashhockey.ui

import `in`.nann.smashhockey.core.feel.TextLayout

/**
 * Running text in the world — the twin of iOS's `Paragraph`: the words wrapped greedily into
 * lines no wider than [width], one extruded line each, stacked and centred on the element's
 * origin. A drill's hint, a help card, the refusal. TalkBack reads it whole.
 */
class Paragraph(
    kit: Kit,
    text: String,
    height: Float,
    colour: Int,
    private val width: Float,
    align: Label3D.Align = Label3D.Align.CENTRE,
    lineSpacing: Float = 1.45f,
    id: String,
    entrance: Entrance = Entrance.Tumble,
) : Semantic, Presentable {
    override val node = kit.node(null)
    override val rest = Xform()
    val presence = Presence(entrance, kit.motion)
    override val semantics = Semantics(id, text, trait = Semantics.Trait.STATIC_TEXT)
    /** The height of the whole block, top of the first line to the bottom of the last. */
    val blockHeight: Float

    init {
        val lines = TextLayout.wrap(text, height.toDouble(), width.toDouble())
        val step = height * lineSpacing
        blockHeight = height + step * maxOf(0, lines.size - 1)
        for ((i, line) in lines.withIndex()) {
            val holder = kit.node(node)
            val m = kit.text(line, height, colour, holder)
            val w = kit.width(m)
            val fit = TextLayout.fit(w.toDouble(), width.toDouble()).toFloat()
            holder.setScale(fit)
            val edge = when (align) {
                Label3D.Align.CENTRE -> 0f
                Label3D.Align.LEADING -> -width / 2
                Label3D.Align.TRAILING -> width / 2
            }
            val x = edge + TextLayout.alignX(align.shared, (w * fit).toDouble()).toFloat()
            holder.setPosition(x, blockHeight / 2 - height / 2 - i * step, 0f)
        }
        node.enabled = false
    }

    override val boundsNode get() = node
    override val bounds = Bounds(-width / 2, -blockHeight / 2, 0f, width / 2, blockHeight / 2, 0.02f)
    override val isPresent get() = presence.isSettledIn

    override fun show(after: Double) = presence.show(after)
    override fun hide(after: Double) = presence.hide(after)

    override fun update(dt: Double, ctx: UiContext) {
        presence.advance(dt, ctx)
        presence.apply(node, rest, ctx.reduceMotion)
    }

}
