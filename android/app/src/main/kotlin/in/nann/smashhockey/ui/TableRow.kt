package `in`.nann.smashhockey.ui

import `in`.nann.smashhockey.ui.generated.DesignTokens.Colour
import `in`.nann.smashhockey.ui.generated.DesignTokens.Size
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import `in`.nann.smashhockey.core.feel.TextLayout
import `in`.nann.smashhockey.engine.Spring

/**
 * One row of a table — a league table line, a list entry — the twin of iOS's `TableRow`. A slab
 * with cells of lettering laid out by column, an optional kit chip, and a slot it springs to:
 * re-rank the table and the rows hop past each other into their new places.
 */
class TableRow(
    private val kit: Kit,
    texts: List<String>,
    private val columns: List<Column>,
    val w: Float, val h: Float,
    id: String,
    colour: Int,
    ink: Int = Colour.INK,
    chip: KitColours? = null,
    kitAt: Float = 0.13f,
    private val textHeight: Float = Size.TEXT_BODY,
    y: Float = 0f,
    entrance: Entrance = Entrance.Slide(fromLeft = true),
    /** Said after the row's cells, so TalkBack names what opening it gives. */
    private val hint: String? = null,
    /** What a tap on the row does (§16.3a); null leaves it lettering that takes no fingers. */
    private val action: (() -> Unit)? = null,
) : Interactive, Presentable {
    /** A column's centre, as a share of the row width from its left edge (0…1). */
    class Column(val at: Float, val align: Label3D.Align)

    class KitColours(val primary: Int, val secondary: Int)

    companion object {
        private fun spoken(texts: List<String>, hint: String?) =
            (if (hint == null) texts else texts + hint).joinToString(", ")
    }

    override val node = kit.node(null)
    private val body = kit.node(node)
    private val slab: UiNode
    private val cells = ArrayList<UiNode>()
    private val cellNodes = ArrayList<UiNode>()
    override val rest = Xform()
    val presence = Presence(entrance, kit.motion)
    override val semantics = Semantics(
        id, spoken(texts, hint),
        trait = if (action == null) Semantics.Trait.STATIC_TEXT else Semantics.Trait.BUTTON,
    )
    private var held = false
    private val slot = Spring(kit.motion.spring(SpringName.POP), y.toDouble())
    private val hop = Jiggle(kit.motion.spring(SpringName.WOBBLY))
    private val motion = kit.motion

    init {
        require(texts.size == columns.size) { "one text per column" }
        val depth = Size.SLAB_DEPTH * 0.6f
        slab = kit.slab(w, h, depth, colour, body, corner = h * 0.3f)
        for ((text, col) in texts.zip(columns)) {
            val cell = kit.node(body)
            val m = kit.text(text, textHeight, ink, cell)
            cell.transform.tz = depth / 2
            cells += m
            cellNodes += cell
            place(cell, m, col)
        }
        if (chip != null) {
            val c = kit.node(body)
            kit.slab(h * 0.62f, h * 0.62f, depth * 0.8f, chip.primary, c, corner = h * 0.12f)
            kit.slab(h * 0.2f, h * 0.64f, depth * 0.84f, chip.secondary, c, corner = 0.005f)
            c.setPosition(-w / 2 + kitAt * w, 0f, depth / 2)
        }
        rest.ty = y
        node.enabled = false
    }

    private fun place(cell: UiNode, m: UiNode, col: Column) {
        val cx = -w / 2 + col.at * w
        cell.transform.tx = cx + TextLayout.alignX(col.align.shared, kit.width(m).toDouble()).toFloat()
        cell.changed()
    }

    override val boundsNode get() = node
    override val bounds = Bounds(-w / 2, -h / 2, -0.03f, w / 2, h / 2, 0.03f)
    override val isPresent get() = presence.isSettledIn

    override fun show(after: Double) = presence.show(after)
    override fun hide(after: Double) {
        held = false
        presence.hide(after)
    }

    fun set(texts: List<String>) {
        for (i in cells.indices) {
            if (i >= texts.size) break
            kit.retext(cells[i], texts[i], textHeight)
            place(cellNodes[i], cells[i], columns[i])
        }
        semantics.label = spoken(texts, hint)
    }

    fun recolour(rgb: Int) = slab.recolour(rgb)

    // ------ taps (§16.3a): a row with something to do sinks under the finger and opens on the lift

    override val takesTouches get() = action != null

    override fun touchDown(ray: TouchRay) {
        if (action == null) return
        held = true
        hop.kick(0.0, -motion.kick(KickName.CELEBRATE) * 0.2)
        KitSound.press()
    }

    override fun touchUp(ray: TouchRay, inside: Boolean) {
        if (!held) return
        held = false
        if (inside) action?.invoke()
    }

    override fun activate() {
        val a = action ?: return
        hop.kick(0.0, motion.kick(KickName.CELEBRATE) * 0.2)
        KitSound.press()
        a()
    }

    /** Springs to a new vertical slot, with a hop if it moved. */
    fun move(toY: Float) {
        if (abs(toY - slot.target) <= 0.001) return
        val up = toY > slot.target
        slot.target = toY.toDouble()
        val k = motion.kick(KickName.CELEBRATE)
        hop.kick((if (up) 1 else -1) * k * 0.25, k * 0.2)
    }

    override fun update(dt: Double, ctx: UiContext) {
        if (ctx.reduceMotion) slot.snap(slot.target) else slot.advance(dt)
        rest.ty = slot.value.toFloat()
        // A row climbing the table comes forward to pass over the others; a falling one ducks back.
        rest.tz = max(-0.08, min(0.12, (slot.target - slot.value) * 0.5)).toFloat()
        presence.advance(dt, ctx)
        presence.apply(node, rest, ctx.reduceMotion)
        if (!node.enabled) return
        hop.advance(dt, ctx.reduceMotion)
        body.transform.rot.set(hop.rotation)
        body.setScale(hop.scale)
    }
}
