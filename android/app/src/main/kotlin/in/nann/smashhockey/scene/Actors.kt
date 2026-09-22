package `in`.nann.smashhockey.scene

import com.google.android.filament.Engine
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Scene
import `in`.nann.smashhockey.core.generated.Role
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.match.MatchSnapshot
import `in`.nann.smashhockey.core.match.MatchState
import `in`.nann.smashhockey.engine.Geometry
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.engine.MeshKit
import `in`.nann.smashhockey.engine.Node
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.generated.WorldLook
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
 * Everything that moves in a match, drawn from its snapshot (spec §5, §8): the twelve players as the
 * prototype's disks (ADR 0006), the ball or puck, the orbit ring and the aim line (§5.2) — the twin
 * of iOS's Actors.swift.
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
    look: WorldLook,
) {
    private val p = Presentation.Player
    private val a = Presentation.Aim
    private val omega = 2 * PI / orbitPeriod
    private val geometries = HashMap<String, Geometry>()
    private val entities = ArrayList<Int>()
    private val players: List<Node>
    private class Shadow(val entity: Int, val rest: MaterialInstance, val carrier: MaterialInstance)
    private val shadows = ArrayList<Shadow>()
    private var carrierShown: Int? = null
    private val ball: Node
    private val ballDisc: Node
    private val orbit: Node
    private val aim: Node
    private val arrow: Node
    private val target: Node
    private val aimColours = listOf(a.pass, a.shot, a.free).map { materials.flat(it, a.opacity) }
    private var aimKind = -1
    private val shown = HashMap<Node, Boolean>()

    init {
        fun geo(key: String, kit: () -> MeshKit) = geometries.getOrPut(key) { Geometry(engine, kit()) }
        /** A renderable of [g] in [m] under [under]; flat marks draw after what they lie on. */
        fun part(g: Geometry, m: MaterialInstance, under: Int, priority: Int = 4): Node {
            val e = g.renderable(listOf(m), shadows = false, priority = priority)
            scene.addEntity(e); entities += e
            return Node(engine, under, existing = e)
        }
        val d = Presentation.Dummy
        players = first.players.map { pl ->
            val r = pl.radius.toFloat()
            val dummy = pl.role == Role.DUMMY
            val primary = if (dummy) d.body else colours[pl.team].primary
            val secondary = if (dummy) d.stripe else colours[pl.team].secondary
            val h = (if (dummy) d.height else p.height).toFloat()
            val group = Node(engine, parent)
            part(geo("body$r/$h") { Shapes.body(r, h) }, materials.toon(primary, look), group.entity)
            when (pl.role) {
                Role.GOALIE -> part(geo("ring$r") { Shapes.goalieRing(r, h) }, materials.flat(secondary), group.entity, 5)
                Role.DUMMY -> part(geo("stripe$r") { Shapes.stripe(r) }, materials.toon(secondary, look), group.entity)
                else -> part(geo("dot$r") { Shapes.dot(r, h) }, materials.flat(secondary), group.entity, 5)
            }
            val rest = materials.flat(primary, p.shadowOpacity)
            val shadow = part(geo("shadow$r") { Shapes.shadow(r) }, rest, group.entity, 5)
            shadows += Shadow(shadow.entity, rest, materials.flat(primary, p.carrierShadowOpacity))
            group
        }

        val b = Presentation.Ball
        val r = first.ball.radius.toFloat()
        ball = if (sport == Sport.ICE) part(geo("puck") { Shapes.puck(r, b.puckHeight.toFloat()) }, materials.toon(b.ice, look), parent)
        else part(geo("ball") { Shapes.ball(r) }, materials.toon(b.field, look), parent)
        ballDisc = part(geo("disc") { Shapes.disc() }, materials.flat(b.disc, b.discOpacity), parent, 5)
        ballDisc.scale(b.discRadius.toFloat())

        fun mark(key: String, kit: () -> MeshKit, m: MaterialInstance) = part(geo(key, kit), m, parent, 6)
        val orbitRadius = Tuning.Orbit.radius.toFloat(); val half = a.orbitWidth.toFloat() / 2
        orbit = mark("orbit", { Shapes.ring(orbitRadius - half, orbitRadius + half, 48) }, materials.flat(a.orbit, a.orbitOpacity))
        aim = mark("strip", { Shapes.strip() }, aimColours[0])
        arrow = mark("arrow", { Shapes.arrowhead() }, aimColours[0])
        val rr = Tuning.Player.outfieldRadius.toFloat()
        target = mark("target", { Shapes.ring(rr + p.targetInner.toFloat(), rr + p.targetOuter.toFloat(), 32) },
            materials.flat(p.target, p.targetOpacity))
        listOf(orbit, aim, arrow, target).forEach { show(it, false) }
    }

    private fun show(n: Node, on: Boolean) {
        if (shown[n] == on) return
        shown[n] = on
        engine.renderableManager.setLayerMask(engine.renderableManager.getInstance(n.entity), 0xFF, if (on) 0x01 else 0x00)
    }

    /** Draws snapshot [s], [ahead] match seconds past its tick; [celebrating]'s players hop on real [clock]. */
    fun update(s: MatchSnapshot, ahead: Double, celebrating: Int?, clock: Double) {
        val xs = DoubleArray(s.players.size); val zs = DoubleArray(s.players.size)
        s.players.forEachIndexed { i, pl ->
            xs[i] = pl.x + pl.vx * ahead; zs[i] = pl.z + pl.vz * ahead
            val n = players[i]
            n.x = xs[i].toFloat(); n.z = zs[i].toFloat()
            n.y = if (celebrating == pl.team && pl.role != Role.DUMMY) (p.hop * abs(sin(clock * p.hopRate + i * 0.9))).toFloat() else 0f
            // A running player leans into its run, as the prototype's did.
            val speed = sqrt(pl.vx * pl.vx + pl.vz * pl.vz)
            val lean = if (speed > 0.5) min(speed * p.lean, p.maxLean) else 0.0
            n.pitch = if (speed > 0.5) (pl.vz / speed * lean).toFloat() else 0f
            n.roll = if (speed > 0.5) (-pl.vx / speed * lean).toFloat() else 0f
            n.apply()
        }

        // The disc under the carrier darkens.
        val carrier = s.ball.carrier
        if (carrier != carrierShown) {
            val rm = engine.renderableManager
            carrierShown?.let { rm.setMaterialInstanceAt(rm.getInstance(shadows[it].entity), 0, shadows[it].rest) }
            carrier?.let { rm.setMaterialInstanceAt(rm.getInstance(shadows[it].entity), 0, shadows[it].carrier) }
            carrierShown = carrier
        }

        val b = s.ball
        var bx = b.x + b.vx * ahead; var bz = b.z + b.vz * ahead
        var angle = b.orbit
        val c = b.carrier
        if (c != null) {
            angle += b.orbitDirection * omega * ahead
            bx = xs[c] + Tuning.Orbit.radius * sin(angle); bz = zs[c] + Tuning.Orbit.radius * cos(angle)
            orbit.x = xs[c].toFloat(); orbit.y = 0.025f; orbit.z = zs[c].toFloat(); orbit.apply()
        }
        ball.x = bx.toFloat(); ball.z = bz.toFloat(); ball.apply()
        ballDisc.x = bx.toFloat(); ballDisc.y = 0.02f; ballDisc.z = bz.toFloat(); ballDisc.apply()
        show(orbit, c != null)
        drawAim(s, xs, zs, bx, bz, angle, clock)
    }

    /**
     * The aim line (§5.2): toward where a release now would go, coloured by what it would snap to —
     * a pass (with the green ring under the receiver), a shot, or nothing.
     */
    private fun drawAim(s: MatchSnapshot, xs: DoubleArray, zs: DoubleArray, bx: Double, bz: Double, angle: Double, clock: Double) {
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
                val pl = s.players[m]
                val d = dist(xs[m] - xs[c], zs[m] - zs[c])
                val o = Tuning.Orbit
                val t = d / max(o.leadSpeedMin, o.leadSpeedBase + o.leadSpeedPerMetre * d)
                val lx = xs[m] + o.leadVelocityFactor * pl.vx * t; val lz = zs[m] + o.leadVelocityFactor * pl.vz * t
                val len = dist(lx - bx, lz - bz); val dn = dist(lx - xs[c], lz - zs[c])
                ex = bx + (lx - xs[c]) / dn * len; ez = bz + (lz - zs[c]) / dn * len
                colour = 0
                show(target, true)
                target.x = xs[m].toFloat(); target.y = 0.03f; target.z = zs[m].toFloat()
                target.scale((1 + sin(clock * p.targetPulseRate) * p.targetPulse).toFloat()); target.apply()
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
            for (n in listOf(aim, arrow)) rm.setMaterialInstanceAt(rm.getInstance(n.entity), 0, aimColours[colour])
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
        entities.forEach { scene.removeEntity(it) }
        geometries.values.forEach { it.destroy() }
        players.forEach { engine.destroyEntity(it.entity); com.google.android.filament.EntityManager.get().destroy(it.entity) }
    }
}
