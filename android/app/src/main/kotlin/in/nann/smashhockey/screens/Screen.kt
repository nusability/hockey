package `in`.nann.smashhockey.screens

import `in`.nann.smashhockey.core.feel.TextLayout
import `in`.nann.smashhockey.game.Game
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.ui.CameraPose
import `in`.nann.smashhockey.ui.generated.DesignTokens
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Presentable
import `in`.nann.smashhockey.ui.UIStage
import `in`.nann.smashhockey.ui.UiElement
import `in`.nann.smashhockey.ui.UiNode
import `in`.nann.smashhockey.ui.Xform

typealias C = DesignTokens.Colour
typealias S = DesignTokens.Size

/** A rest pose in a screen's layout: at (x, y, z), tilted by [tilt] radians about Z. */
fun at(x: Float, y: Float, z: Float = 0f, tilt: Float = 0f): Xform = Xform.at(x, y, z, tilt)

/**
 * A screen of §16 — the twin of iOS's `Screen`: where the camera stands for it and what arrives
 * when it does — built fresh from the save each time it is entered, so it never shows stale
 * numbers, and taken apart once its parts have hopped away. A menu stands in the world at its
 * camera pose; the match HUD hangs from the camera (ADR 0005).
 */
open class Screen private constructor(val pose: CameraPose, val game: Game, hud: Boolean) {
    val stage: UIStage = game.stage
    val kit = stage.kit
    val motion = stage.motion
    /** Everything of this screen hangs under here; removing it removes the screen. */
    val layer: UiNode
    /** What goes when the screen does: the menu's whole frame, or the HUD's layer. */
    private val removable: UiNode
    val top: Float
    val bottom: Float
    /** Everything that arrives with the screen, in arrival order. */
    private val parts = ArrayList<Presentable>()

    /** A menu standing in the world at [pose]. */
    constructor(pose: CameraPose, game: Game) : this(pose, game, false)

    /** A layer on the camera-parented HUD rig (the match). */
    constructor(game: Game) : this(CameraPose(0f, 0f, 0f, 0f, 0f, 1f), game, true)

    init {
        if (hud) {
            layer = kit.node(stage.hud.node)
            removable = layer
            top = stage.hud.top
            bottom = stage.hud.bottom
        } else {
            val frame = stage.frame(pose)
            layer = kit.node(frame.node)
            removable = frame.node
            top = frame.top
            bottom = frame.bottom
        }
    }

    /** Adds [e] under [parent] (the layer by default) as one of the parts that arrive and leave with the screen. */
    fun <E : Presentable> part(e: E, rest: Xform, parent: UiNode = layer): E {
        stage.add(e, parent)
        e.rest.set(rest)
        parts += e
        return e
    }

    /** Adds [e] under [parent] without making it one of the arrivals — a child that rides on a part. */
    fun <E : UiElement> child(e: E, rest: Xform = Xform(), parent: UiNode): E {
        stage.add(e, parent)
        if (e is Presentable) e.rest.set(rest)
        return e
    }

    /** Fixed lettering on a part: centred on (x, y, z) (or starting / ending there), shrunk to [maxWidth]. */
    fun letters(text: String, height: Float, colour: Int, maxWidth: Float? = null, align: Label3D.Align = Label3D.Align.CENTRE,
                x: Float = 0f, y: Float = 0f, z: Float = 0f, parent: UiNode): UiNode {
        val holder = kit.node(parent)
        place(holder, text, height, colour, maxWidth, align, x, y, z)
        return holder
    }

    /** Re-letters what [letters] made. */
    fun reletter(holder: UiNode, text: String, height: Float, colour: Int, maxWidth: Float? = null,
                 align: Label3D.Align = Label3D.Align.CENTRE, x: Float = 0f, y: Float = 0f, z: Float = 0f) {
        place(holder, text, height, colour, maxWidth, align, x, y, z)
    }

    /**
     * Lettering on a slab: at most two centred lines when it is given a width to stay inside (§16),
     * and a shrink only when a line still has nowhere to break.
     */
    private fun place(holder: UiNode, text: String, height: Float, colour: Int, maxWidth: Float?,
                      align: Label3D.Align, x: Float, y: Float, z: Float) {
        for (line in holder.childNodes.toList()) kit.destroy(line)
        val room = maxWidth?.toDouble()
        val lines = room?.let { TextLayout.caption(text, height.toDouble(), it) } ?: listOf(text)
        for ((i, line) in lines.withIndex()) {
            val row = kit.node(holder)
            row.setPosition(0f, TextLayout.stackY(i, lines.size, height.toDouble()).toFloat(), 0f)
            kit.text(line, height, colour, row)
        }
        val w = TextLayout.widest(lines, height.toDouble())
        val k = TextLayout.fit(w, room).toFloat()
        holder.setScale(k)
        holder.setPosition(x + TextLayout.alignX(align.shared, w * k).toFloat(), y, z)
    }

    /** Arrivals, one after another on the stagger token. */
    open fun show(after: Double) {
        val stagger = motion.staggerSeconds * 1.6
        for (i in parts.indices) parts[i].show(after + i * stagger)
    }

    /** Departures, quicker, last-in first-out; the layer goes once they are gone. */
    open fun leave() {
        val stagger = motion.staggerSeconds * 0.5
        for ((i, p) in parts.asReversed().withIndex()) p.hide(i * stagger)
        val gone = removable
        stage.after(Presentation.Screens.leaveSeconds) { stage.remove(gone) }
    }

    /** Real time, every frame, while the screen is current. */
    open fun update(dt: Double) {}
}
