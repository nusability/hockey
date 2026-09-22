package `in`.nann.smashhockey.scene

import com.google.android.filament.Engine
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Scene
import `in`.nann.smashhockey.core.feel.AimArrow as Arrow
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.match.MatchSnapshot
import `in`.nann.smashhockey.core.match.MatchState
import `in`.nann.smashhockey.engine.Geometry
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.engine.MeshKit
import `in`.nann.smashhockey.engine.Node
import `in`.nann.smashhockey.generated.Presentation
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The aim arrow and its lock-on marker (spec §5.2) — the prototype's arrow exactly, for the player's
 * own carrier only, the twin of iOS's AimArrow.swift. The arrow is anchored at the carrier's centre
 * and turned by the orbit angle, so it points out through the ball: a chevron ribbon scrolling
 * outward over an additive glow, a notched arrowhead over its glow, the white orbit ring. When a
 * release would snap, the lock-on fades in: for a pass the receiver's pulsing ring and a dotted line
 * from the arrow's tip to the receiver's lead point; for a shot a glow across the goal mouth.
 */
class AimArrow(
    private val engine: Engine,
    private val scene: Scene,
    parent: Int,
    private val materials: Materials,
    private val corner: Double,
) {
    private val a = Presentation.Aim
    private val lock = Presentation.Aim.Lock
    private val p = Presentation.Player
    private val params = Arrow.Params(a.maxLength, a.minLength, a.passShort, a.shotShort, a.boardMargin, a.boardProbe, a.probeStep)
    private val geometries = ArrayList<Geometry>()
    private val entities = ArrayList<Int>()
    private val nodes = ArrayList<Node>()
    private val shown = HashMap<Node, Boolean>()

    private val group = Node(engine, parent).also { nodes += it }
    private val ribbonMat = materials.aim(a.ribbonNear, a.ribbonFar, a.scroll)
    private val glowMat = materials.glow(a.free)
    private val headMat = materials.flatOwned(a.free)
    private val headGlowMat = materials.glow(a.free)
    private val orbitMat = materials.flat(a.orbit, a.orbitOpacity)
    private val targetMat = materials.flatOwned(p.target)
    private val dotMat = materials.flatOwned(a.pass)
    private val mouthMat = materials.glow(a.shot)
    private val stripMat = materials.glow(a.shot)
    private val owned = listOf(ribbonMat, glowMat, headMat, headGlowMat, targetMat, dotMat, mouthMat, stripMat)

    private val ribbon: Node
    private val glow: Node
    private val head: Node
    private val headGlow: Node
    private val orbit: Node
    private val target: Node
    private val dots: List<Node>
    private val mouth: Node
    private val strip: Node

    /** What the arrow shows, decided by the core's state machine (both apps share the rules). */
    private val showing = Arrow.Showing()

    init {
        fun part(kit: MeshKit, m: MaterialInstance, under: Int, priority: Int = 6): Node {
            val g = Geometry(engine, kit).also { geometries += it }
            val e = g.renderable(listOf(m), shadows = false, priority = priority)
            scene.addEntity(e); entities += e
            return Node(engine, under, existing = e).also { nodes += it }
        }
        val start = (Tuning.Orbit.radius + a.start).toFloat()
        val lift = a.lift.toFloat()
        glow = part(Shapes.ribbon(a.glowNear.toFloat(), a.glowFar.toFloat()), glowMat, group.entity)
        glow.y = lift - 0.005f; glow.z = start
        ribbon = part(Shapes.ribbon(a.ribbonNear.toFloat(), a.ribbonFar.toFloat()), ribbonMat, group.entity, 7)
        ribbon.y = lift; ribbon.z = start
        headGlow = part(Shapes.arrowhead(a.head, (a.headScale * a.headGlow).toFloat()), headGlowMat, group.entity)
        headGlow.y = lift - 0.005f
        head = part(Shapes.arrowhead(a.head, a.headScale.toFloat()), headMat, group.entity, 7)
        head.y = lift + 0.005f
        val r = Tuning.Orbit.radius.toFloat(); val half = a.orbitWidth.toFloat() / 2
        orbit = part(Shapes.ring(r - half, r + half, 48), orbitMat, parent)
        val rr = Tuning.Player.outfieldRadius.toFloat()
        target = part(Shapes.ring(rr + p.targetInner.toFloat(), rr + p.targetOuter.toFloat(), 32), targetMat, parent)
        val dotKit = Shapes.ring(0f, lock.dot.toFloat() / 2, 12)
        val dotGeometry = Geometry(engine, dotKit).also { geometries += it }
        dots = (0 until DOTS).map {
            val e = dotGeometry.renderable(listOf(dotMat), shadows = false, priority = 6)
            scene.addEntity(e); entities += e
            Node(engine, parent, existing = e).also { n -> nodes += n }
        }
        mouth = part(Shapes.sheet(), mouthMat, parent)
        strip = part(Shapes.strip(), stripMat, parent)
        (listOf(group, ribbon, glow, head, headGlow, orbit, target, mouth, strip) + dots).forEach { show(it, false) }
    }

    private fun show(n: Node, on: Boolean) {
        if (shown[n] == on) return
        shown[n] = on
        engine.renderableManager.let { rm ->
            if (rm.hasComponent(n.entity)) rm.setLayerMask(rm.getInstance(n.entity), 0xFF, if (on) 0x01 else 0x00)
        }
    }

    private fun arrowShown(on: Boolean) = listOf(ribbon, glow, head, headGlow, orbit).forEach { show(it, on) }

    /**
     * Draws the arrow for snapshot [s] with everyone at their drawn positions ([xs], [zs]), the ball
     * at orbit [angle]; [clock] is real seconds (the pulses and the lock-on's fade).
     */
    fun update(s: MatchSnapshot, xs: DoubleArray, zs: DoubleArray, angle: Double, clock: Double) {
        val c = s.ball.carrier
        val kind = s.aim
        val look = showing.frame(s.state, s.playerCarrier, c, kind, clock, lock.fadeIn)
        if (!look.arrow || c == null || kind == null) {
            arrowShown(false); lockShown(null)
            return
        }
        arrowShown(true)
        orbit.x = xs[c].toFloat(); orbit.y = 0.025f; orbit.z = zs[c].toFloat(); orbit.apply()

        val team = s.players[c].team
        val goalZ = if (team == 0) Tuning.Pitch.goalLineZ else -Tuning.Pitch.goalLineZ
        val arrowKind = when (kind) {
            is MatchSnapshot.Aim.Pass -> Arrow.Kind.Pass(xs[kind.to], zs[kind.to])
            MatchSnapshot.Aim.Shot -> Arrow.Kind.Shot(goalZ)
            MatchSnapshot.Aim.Unassisted -> Arrow.Kind.Free
        }
        val len = Arrow.length(arrowKind, xs[c], zs[c], angle, corner, params)
        val snapped = look.snapped
        val colour = intArrayOf(a.free, a.pass, a.shot)[look.colour]
        val opacity = if (snapped) a.opacitySnapped + a.pulse * sin(clock * a.pulseRate) else a.opacityFree
        materials.set(ribbonMat, colour, opacity)
        ribbonMat.setParameter("cells", (len / a.chevron).toFloat())
        materials.set(headMat, colour, opacity)
        materials.set(glowMat, colour, if (snapped) a.glowSnapped else a.glowFree)
        materials.set(headGlowMat, colour, if (snapped) a.headGlowSnapped else a.headGlowFree)

        group.x = xs[c].toFloat(); group.z = zs[c].toFloat(); group.yaw = angle.toFloat(); group.apply()
        val start = Tuning.Orbit.radius + a.start
        for (n in listOf(ribbon, glow)) { n.sx = a.width.toFloat(); n.sy = 1f; n.sz = len.toFloat(); n.apply() }
        for (n in listOf(head, headGlow)) { n.z = (start + len).toFloat(); n.apply() }

        // The lock-on, faded in since this snap began (the core decides when that was).
        if (!snapped) { lockShown(null); return }
        val fade = look.fade
        lockShown(kind)
        when (kind) {
            is MatchSnapshot.Aim.Pass -> {
                val m = kind.to
                materials.set(targetMat, p.target, p.targetOpacity * fade)
                target.x = xs[m].toFloat(); target.y = 0.03f; target.z = zs[m].toFloat()
                target.scale((1 + sin(clock * p.targetPulseRate) * p.targetPulse).toFloat()); target.apply()
                val pl = s.players[m]
                val d = dist(xs[m] - xs[c], zs[m] - zs[c])
                val o = Tuning.Orbit
                val t = d / max(o.leadSpeedMin, o.leadSpeedBase + o.leadSpeedPerMetre * d)
                val lx = xs[m] + o.leadVelocityFactor * pl.vx * t; val lz = zs[m] + o.leadVelocityFactor * pl.vz * t
                val reach = start + len + a.head[1] * a.headScale
                dotted(xs[c] + sin(angle) * reach, zs[c] + cos(angle) * reach, lx, lz, fade)
            }
            else -> {
                val f = fade * (1 + lock.mouthPulse * sin(clock * a.pulseRate))
                materials.set(mouthMat, a.shot, lock.mouthOpacity * f)
                materials.set(stripMat, a.shot, lock.stripOpacity * f)
                val w = Tuning.Pitch.goalMouthWidth.toFloat()
                mouth.x = 0f; mouth.y = 0f; mouth.z = goalZ.toFloat(); mouth.sx = w; mouth.sy = lock.mouthHeight.toFloat(); mouth.sz = 1f
                mouth.apply()
                // The strip lies on the pitch from the line back toward the play.
                val back = if (goalZ > 0) -1f else 1f
                strip.x = 0f; strip.y = 0.03f; strip.z = goalZ.toFloat(); strip.yaw = if (back < 0) PI_F else 0f
                strip.sx = w; strip.sy = 1f; strip.sz = lock.mouthDepth.toFloat(); strip.apply()
            }
        }
    }

    private fun lockShown(kind: MatchSnapshot.Aim?) {
        val pass = kind is MatchSnapshot.Aim.Pass
        show(target, pass)
        if (!pass) dots.forEach { show(it, false) }
        val shot = kind == MatchSnapshot.Aim.Shot
        show(mouth, shot); show(strip, shot)
    }

    /** Dots every dot_gap metres from (x0, z0) to (x1, z1). */
    private fun dotted(x0: Double, z0: Double, x1: Double, z1: Double, fade: Double) {
        materials.set(dotMat, a.pass, lock.dotOpacity * fade)
        val d = dist(x1 - x0, z1 - z0)
        val n = if (d < lock.dotGap) 0 else min(DOTS, (d / lock.dotGap).toInt() + 1)
        for ((i, dot) in dots.withIndex()) {
            if (i >= n) { show(dot, false); continue }
            val t = i * lock.dotGap / d
            dot.x = (x0 + (x1 - x0) * t).toFloat(); dot.y = a.lift.toFloat(); dot.z = (z0 + (z1 - z0) * t).toFloat(); dot.apply()
            show(dot, true)
        }
    }

    private fun dist(x: Double, z: Double) = sqrt(x * x + z * z)

    fun destroy() {
        entities.forEach { scene.removeEntity(it) }
        geometries.forEach { it.destroy() }
        engine.destroyEntity(group.entity); com.google.android.filament.EntityManager.get().destroy(group.entity)
        materials.release(owned)
    }

    private companion object {
        const val DOTS = 40
        const val PI_F = Math.PI.toFloat()
    }
}
