package `in`.nann.smashhockey.scene

import android.opengl.Matrix
import com.google.android.filament.Engine
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Scene
import `in`.nann.smashhockey.core.generated.Role
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.match.MatchSnapshot
import `in`.nann.smashhockey.engine.Geometry
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.engine.MeshKit
import `in`.nann.smashhockey.engine.Node
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.generated.WorldLook
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/** A side's kit colours, sRGB 0xRRGGBB. */
data class TeamColours(val primary: Int, val secondary: Int)

/**
 * Everything that moves in a match, drawn from its snapshot (spec §5, §8): the twelve players as the
 * prototype's disks (ADR 0006), the ball or puck — rolling or spinning, with its trail (§8.8) — the
 * aim arrow (§5.2, [AimArrow]) and the ring under a player the whistle would name offside (§8.9,
 * §16.4); the twin of iOS's Actors.swift.
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
    private val sport: Sport,
    orbitPeriod: Double,
    materials: Materials,
    look: WorldLook,
) {
    private val p = Presentation.Player
    private val omega = 2 * PI / orbitPeriod
    private val geometries = HashMap<String, Geometry>()
    private val entities = ArrayList<Int>()
    private val players: List<Node>
    private class Shadow(val entity: Int, val rest: MaterialInstance, val carrier: MaterialInstance)
    private val shadows = ArrayList<Shadow>()
    private var carrierShown: Int? = null
    private val ball: Node
    private val ballDisc: Node
    private val ballRadius = first.ball.radius
    private val aim = AimArrow(engine, scene, parent, materials, sport.cornerRadius)
    private val trail = Trail(engine, scene, materials, first.ball.radius.toFloat())
    private val offside = OffsideMarks(engine, scene, parent, first, colours, sport, materials)
    /** The ball's accumulated roll (field) or spin (puck), and where it was last drawn. */
    private val spin = FloatArray(16).also { Matrix.setIdentityM(it, 0) }
    private var lastBall: DoubleArray? = null
    private var lastClock = 0.0

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
    }

    /** Draws snapshot [s], [ahead] match seconds past its tick; [celebrating]'s players hop on real [clock]. */
    fun update(s: MatchSnapshot, ahead: Double, celebrating: Int?, clock: Double) {
        val dt = clock - lastClock              // taken before `roll` moves `lastClock` on
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
        }
        roll(bx, bz, clock)
        ball.x = bx.toFloat(); ball.y = if (sport == Sport.ICE) 0f else ballRadius.toFloat(); ball.z = bz.toFloat(); ball.apply()
        ballDisc.x = bx.toFloat(); ballDisc.y = 0.02f; ballDisc.z = bz.toFloat(); ballDisc.apply()
        trail.update(bx, bz, s.time + ahead, sqrt(b.vx * b.vx + b.vz * b.vz), c == null)
        aim.update(s, xs, zs, angle, clock)
        offside.update(s, xs, zs, dt)
    }

    /**
     * §8.8: the field ball rolls by its drawn travel — |Δ| / r about (Δz, 0, −Δx) — the puck spins
     * about its axis at a steady rate of real time.
     */
    private fun roll(x: Double, z: Double, clock: Double) {
        val dt = clock - lastClock
        lastClock = clock
        val last = lastBall
        lastBall = doubleArrayOf(x, z)
        val step = FloatArray(16)
        if (sport == Sport.ICE) {
            Matrix.setRotateM(step, 0, Math.toDegrees(Presentation.Trail.puckSpin * dt).toFloat(), 0f, 1f, 0f)
        } else {
            if (last == null) return
            val dx = x - last[0]; val dz = z - last[1]
            val d = sqrt(dx * dx + dz * dz)
            if (d < 1e-6 || d > 5) return          // a restart teleports the ball: no spin for that
            Matrix.setRotateM(step, 0, Math.toDegrees(d / ballRadius).toFloat(), (dz / d).toFloat(), 0f, (-dx / d).toFloat())
        }
        val out = FloatArray(16)
        Matrix.multiplyMM(out, 0, step, 0, spin, 0)
        System.arraycopy(out, 0, spin, 0, 16)
        ball.rotation = spin
    }

    fun destroy() {
        aim.destroy()
        trail.destroy()
        offside.destroy()
        entities.forEach { scene.removeEntity(it) }
        geometries.values.forEach { it.destroy() }
        players.forEach { engine.destroyEntity(it.entity); com.google.android.filament.EntityManager.get().destroy(it.entity) }
    }
}
