package `in`.nann.smashhockey.scene

import com.google.android.filament.Engine
import com.google.android.filament.Scene
import `in`.nann.smashhockey.core.generated.Role
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.match.MatchSnapshot
import `in`.nann.smashhockey.core.match.MatchState
import `in`.nann.smashhockey.engine.Geometry
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.engine.Node
import `in`.nann.smashhockey.generated.Presentation
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/** A side's kit colours, sRGB 0xRRGGBB. */
data class TeamColours(val primary: Int, val secondary: Int)

/**
 * Everything that moves in a match, drawn from its snapshot (spec §5, §8): the twelve toys, the
 * ball or puck, the orbit ring and the aim line (§5.2) — the twin of iOS's Actors.swift.
 *
 * Between ticks it extrapolates by at most one tick (`ahead`, match seconds) along the snapshot's
 * velocities — drawing only; the simulation is advanced by the core's tick clock alone (§4.2).
 */
class Actors(
    private val engine: Engine,
    private val scene: Scene,
    parent: Int,
    first: MatchSnapshot,
    colours: List<TeamColours>,
    sport: Sport,
    orbitPeriod: Double,
    materials: Materials,
) {
    private val f = Presentation.Figure
    private val a = Presentation.Aim
    private val omega = 2 * PI / orbitPeriod
    private val geometries = ArrayList<Geometry>()
    private val figures: List<Node>
    private val ball: Node
    private val orbit: Node
    private val aim: Node
    private val arrow: Node
    private val target: Node
    private val aimColours = listOf(a.pass, a.shot, a.free).map { materials.overlay(it, a.opacity) }
    private var aimKind = -1
    private val shown = HashMap<Node, Boolean>()

    init {
        fun geo(kit: `in`.nann.smashhockey.engine.MeshKit) = Geometry(engine, kit).also { geometries += it }
        val outfield = Figures.outfield(); val goalie = Figures.goalie(); val dummy = Figures.dummy(Presentation.Dummy.height.toFloat())
        val gOutfield = geo(outfield); val gGoalie = geo(goalie); val gDummy = geo(dummy)
        fun slots(kit: `in`.nann.smashhockey.engine.MeshKit, c: Map<Int, Int>) = kit.usedSlots.map { materials.actor(c.getValue(it)) }
        val palettes = colours.map {
            mapOf(Figures.Slot.PRIMARY to it.primary, Figures.Slot.SECONDARY to it.secondary, Figures.Slot.SKIN to f.skin,
                Figures.Slot.STICK to f.stick, Figures.Slot.DARK to f.eye)
        }
        val dummyColours = slots(dummy, mapOf(Figures.Slot.PRIMARY to Presentation.Dummy.cone,
            Figures.Slot.SECONDARY to Presentation.Dummy.stripe, Figures.Slot.DARK to Presentation.Dummy.base))
        figures = first.players.map { p ->
            val (g, m, s) = when (p.role) {
                Role.GOALIE -> Triple(gGoalie, slots(goalie, palettes[p.team]), f.scale * f.goalieScale)
                Role.DUMMY -> Triple(gDummy, dummyColours, 1.0)
                else -> Triple(gOutfield, slots(outfield, palettes[p.team]), f.scale)
            }
            node(g.renderable(m, shadows = true), parent).also { it.scale(s.toFloat()) }
        }
        val r = first.ball.radius.toFloat()
        val ballKit = if (sport == Sport.ICE) Figures.puck(r, Presentation.Ball.puckHeight.toFloat()) else Figures.ball(r)
        val ballColour = if (sport == Sport.ICE) Presentation.Ball.ice else Presentation.Ball.field
        ball = node(geo(ballKit).renderable(listOf(materials.actor(ballColour)), shadows = true), parent)

        fun mark(kit: `in`.nann.smashhockey.engine.MeshKit, colour: Int, alpha: Double) =
            node(geo(kit).renderable(listOf(materials.overlay(colour, alpha)), shadows = false, priority = 6), parent)
        val orbitRadius = Tuning.Orbit.radius.toFloat()
        orbit = mark(Figures.ring((a.orbitWidth / Tuning.Orbit.radius).toFloat()), a.orbit, a.orbitOpacity)
        orbit.sx = orbitRadius; orbit.sz = orbitRadius
        aim = mark(Figures.strip(), a.pass, a.opacity)
        arrow = mark(Figures.arrowhead(), a.pass, a.opacity)
        target = mark(Figures.ring(0.16f), a.pass, a.opacity)
        listOf(orbit, aim, arrow, target).forEach { show(it, false) }
    }

    private fun node(entity: Int, parent: Int): Node {
        scene.addEntity(entity)
        return Node(engine, parent, existing = entity)
    }

    private fun show(n: Node, on: Boolean) {
        if (shown[n] == on) return
        shown[n] = on
        engine.renderableManager.setLayerMask(engine.renderableManager.getInstance(n.entity), 0xFF, if (on) 0x01 else 0x00)
    }

    /** Draws snapshot [s], [ahead] match seconds past its tick; [celebrating]'s toys hop on real [clock]. */
    fun update(s: MatchSnapshot, ahead: Double, celebrating: Int?, clock: Double) {
        val xs = DoubleArray(s.players.size); val zs = DoubleArray(s.players.size)
        s.players.forEachIndexed { i, p ->
            xs[i] = p.x + p.vx * ahead; zs[i] = p.z + p.vz * ahead
            val n = figures[i]
            n.x = xs[i].toFloat(); n.z = zs[i].toFloat()
            n.y = if (celebrating == p.team && p.role != Role.DUMMY) (f.hop * abs(sin(clock * f.hopRate + i * 0.9))).toFloat() else 0f
            n.yaw = p.facing.toFloat()
            n.apply()
        }
        val b = s.ball
        var bx = b.x + b.vx * ahead; var bz = b.z + b.vz * ahead
        var angle = b.orbit
        val c = b.carrier
        if (c != null) {
            angle += b.orbitDirection * omega * ahead
            bx = xs[c] + Tuning.Orbit.radius * sin(angle); bz = zs[c] + Tuning.Orbit.radius * cos(angle)
            orbit.x = xs[c].toFloat(); orbit.y = 0.04f; orbit.z = zs[c].toFloat(); orbit.apply()
        }
        ball.x = bx.toFloat(); ball.z = bz.toFloat(); ball.apply()
        show(orbit, c != null)
        drawAim(s, xs, zs, bx, bz, angle)
    }

    /** The aim line (§5.2): toward where a release now would go, coloured by what it would snap to. */
    private fun drawAim(s: MatchSnapshot, xs: DoubleArray, zs: DoubleArray, bx: Double, bz: Double, angle: Double) {
        val c = s.ball.carrier
        val kind = s.aim
        if (!s.playerCarrier || c == null || kind == null || (s.state != MatchState.PLAY && s.state != MatchState.READY)) {
            show(aim, false); show(arrow, false); show(target, false)
            return
        }
        var ex: Double; var ez: Double
        var colour = 2
        show(target, false)
        when (kind) {
            is MatchSnapshot.Aim.Pass -> {
                val m = kind.to
                val p = s.players[m]
                val d = dist(xs[m] - xs[c], zs[m] - zs[c])
                val o = Tuning.Orbit
                val t = d / max(o.leadSpeedMin, o.leadSpeedBase + o.leadSpeedPerMetre * d)
                val lx = xs[m] + o.leadVelocityFactor * p.vx * t; val lz = zs[m] + o.leadVelocityFactor * p.vz * t
                val len = dist(lx - bx, lz - bz); val dn = dist(lx - xs[c], lz - zs[c])
                ex = bx + (lx - xs[c]) / dn * len; ez = bz + (lz - zs[c]) / dn * len
                colour = 0
                show(target, true)
                target.x = xs[m].toFloat(); target.y = 0.05f; target.z = zs[m].toFloat(); target.scale(a.targetRing.toFloat()); target.apply()
            }
            MatchSnapshot.Aim.Shot -> {
                val gz = if (s.players[c].team == 0) Tuning.Pitch.goalLineZ else -Tuning.Pitch.goalLineZ
                val len = dist(-bx, gz - bz); val dn = dist(-xs[c], gz - zs[c])
                ex = bx + (-xs[c]) / dn * len; ez = bz + (gz - zs[c]) / dn * len
                colour = 1
            }
            MatchSnapshot.Aim.Unassisted -> { ex = bx + a.freeLength * sin(angle); ez = bz + a.freeLength * cos(angle) }
        }
        if (colour != aimKind) {
            aimKind = colour
            val rm = engine.renderableManager
            for (n in listOf(aim, arrow, target)) rm.setMaterialInstanceAt(rm.getInstance(n.entity), 0, aimColours[colour])
        }
        val vx = ex - bx; val vz = ez - bz
        val length = dist(vx, vz).toFloat()
        val head = min(a.width.toFloat() * 3, length * 0.5f)
        val yaw = atan2(vx, vz).toFloat()
        val dx = (vx / max(length.toDouble(), 1e-4)).toFloat(); val dz = (vz / max(length.toDouble(), 1e-4)).toFloat()
        show(aim, true); show(arrow, true)
        aim.x = bx.toFloat(); aim.y = 0.07f; aim.z = bz.toFloat(); aim.yaw = yaw
        aim.sx = a.width.toFloat(); aim.sy = 1f; aim.sz = max(length - head, 0.01f); aim.apply()
        arrow.x = bx.toFloat() + dx * (length - head); arrow.y = 0.07f; arrow.z = bz.toFloat() + dz * (length - head); arrow.yaw = yaw
        arrow.sx = a.width.toFloat() * 2.6f; arrow.sy = 1f; arrow.sz = head; arrow.apply()
    }

    private fun dist(x: Double, z: Double) = sqrt(x * x + z * z)

    fun destroy() {
        (figures + listOf(ball, orbit, aim, arrow, target)).forEach { scene.removeEntity(it.entity) }
        geometries.forEach { it.destroy() }
    }
}
