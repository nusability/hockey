package `in`.nann.smashhockey.ui

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
        val lines = wrap(kit, text, height, width)
        val step = height * lineSpacing
        blockHeight = height + step * maxOf(0, lines.size - 1)
        for ((i, line) in lines.withIndex()) {
            val holder = kit.node(node)
            val m = kit.text(line, height, colour, holder)
            val w = kit.width(m)
            val fit = if (w > width) width / w else 1f
            holder.setScale(fit)
            val x = when (align) {
                Label3D.Align.CENTRE -> 0f
                Label3D.Align.LEADING -> -width / 2 + w * fit / 2
                Label3D.Align.TRAILING -> width / 2 - w * fit / 2
            }
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

    companion object {
        /** Greedy wrap: as many words on a line as fit [width], measured on the lettering itself. */
        fun wrap(kit: Kit, text: String, height: Float, width: Float): List<String> {
            val space = height * 0.3f
            val lines = ArrayList<String>()
            var line = ""
            var lineWidth = 0f
            for (word in text.split(' ').filter { it.isNotEmpty() }) {
                val w = kit.measure(word, height)
                if (line.isEmpty()) {
                    line = word; lineWidth = w
                } else if (lineWidth + space + w <= width) {
                    line += " $word"; lineWidth += space + w
                } else {
                    lines += line
                    line = word; lineWidth = w
                }
            }
            if (line.isNotEmpty()) lines += line
            return lines
        }
    }
}
