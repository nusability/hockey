package `in`.nann.smashhockey.ui

import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.generated.Presentation
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

/**
 * A player as the pitch draws it (ADR 0006) — the twin of iOS's `KitDisk`: a squat disk in the
 * kit's primary with a dot of the secondary on top, standing in a menu, tipped toward the viewer
 * and turning slowly. The create screen's live preview (§16.1) and, with [ball], the how-to-play
 * card's teacher (§16.8): a ball circling it at the orbit's pace and an aim line that turns pink
 * toward the goal (up) and green toward a team-mate (right), white otherwise (§5.2).
 */
class KitDisk(kit: Kit, private val radius: Float, primary: Int, secondary: Int, ball: Boolean = false) : Presentable {
    override val node = kit.node(null)
    override val rest = Xform()
    val presence = Presence(Entrance.Pop, kit.motion)
    private val tilt = kit.node(node)
    private val spinner = kit.node(tilt)
    private val bodyModel: UiNode
    private val dot: UiNode
    private val ballNode: UiNode?
    private val aim: UiNode?
    private val height = radius * (Presentation.Player.height / Tuning.Player.outfieldRadius).toFloat()
    private var spin = 0f
    private var orbit = 0.0
    private var aimColour = -1
    private val turn = Quat()

    init {
        tilt.setRotation(Quat().axisAngle(0.95f, 1f, 0f, 0f))
        tilt.setPosition(0f, -height / 2, 0f)
        bodyModel = kit.cylinder(height, radius, primary, spinner)
        bodyModel.setPosition(0f, height / 2, 0f)
        dot = kit.cylinder(height * 0.12f, radius * Presentation.Player.dot.toFloat(), secondary, spinner)
        dot.setPosition(0f, height + height * 0.06f, 0f)
        if (ball) {
            ballNode = kit.sphere(radius * 0.4f, Presentation.Ball.field, tilt)
            aim = kit.slab(radius * 0.18f, radius * 0.05f, 1f, Presentation.Aim.free, tilt, corner = 0f)
        } else {
            ballNode = null
            aim = null
        }
        node.enabled = false
    }

    fun recolour(primary: Int, secondary: Int) {
        bodyModel.recolour(primary)
        dot.recolour(secondary)
    }

    override fun show(after: Double) = presence.show(after)
    override fun hide(after: Double) = presence.hide(after)

    override fun update(dt: Double, ctx: UiContext) {
        presence.advance(dt, ctx)
        presence.apply(node, rest, ctx.reduceMotion)
        if (!node.enabled) return
        if (!ctx.reduceMotion) spin += dt.toFloat() * 0.5f
        spinner.setRotation(turn.axisAngle(spin, 0f, 1f, 0f))
        val b = ballNode ?: return
        val a = aim ?: return
        orbit += dt * 2 * PI / Tuning.Orbit.demoPeriod
        if (orbit > PI) orbit -= 2 * PI
        val r = radius * (Tuning.Orbit.radius / Tuning.Player.outfieldRadius).toFloat()
        val dx = sin(orbit).toFloat(); val dz = -cos(orbit).toFloat()
        b.setPosition(dx * r, height * 0.5f, dz * r)
        val length = r * 1.6f
        a.transform.tx = dx * (r + length / 2); a.transform.ty = height * 0.5f; a.transform.tz = dz * (r + length / 2)
        a.transform.rot.axisAngle(-orbit.toFloat(), 0f, 1f, 0f)
        a.transform.sz = length
        a.changed()
        // Up the card is the goal; to the right a team-mate (§5.2's colours).
        val kind = if (abs(orbit) < 0.4) 1 else if (abs(orbit - PI / 2) < 0.36) 0 else 2
        if (kind != aimColour) {
            aimColour = kind
            a.recolour(listOf(Presentation.Aim.pass, Presentation.Aim.shot, Presentation.Aim.free)[kind])
        }
    }
}
