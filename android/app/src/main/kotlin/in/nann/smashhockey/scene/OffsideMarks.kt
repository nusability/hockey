package `in`.nann.smashhockey.scene

import com.google.android.filament.Engine
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Scene
import `in`.nann.smashhockey.core.generated.Role
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.match.MatchSnapshot
import `in`.nann.smashhockey.engine.Geometry
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.engine.Node
import `in`.nann.smashhockey.generated.Presentation
import kotlin.math.max
import kotlin.math.min

/**
 * The offside mark (spec §16.4, §8.9) — the ice sport's only, the twin of iOS's OffsideMarks.swift:
 * a faded ring on the pitch under every player the core reports offside, in their own kit's primary.
 * It is the receiver's lock-on ring (§5.2) made pale and unpulsed, and it fades in and out over
 * `player.offside_fade` seconds of real time as the core's answer changes, so a player who steps over
 * the line and back does not flicker.
 *
 * It is a **flat mark**, so it is drawn at the flat marks' own renderable priority — the band the
 * discs under the players use — and cannot change places with them wherever the play has got to.
 */
class OffsideMarks(
    private val engine: Engine,
    private val scene: Scene,
    parent: Int,
    first: MatchSnapshot,
    colours: List<TeamColours>,
    sport: Sport,
    private val materials: Materials,
) {
    private val p = Presentation.Player

    /** One player's ring: the node under them, its own material, and how far it has faded in. */
    private class Ring(
        val player: Int,
        val node: Node,
        val material: MaterialInstance,
        val colour: Int,
        val radius: Double,
    ) {
        var fade = 0.0
        var shown = false
    }

    private val live = sport == Sport.ICE
    private val geometry: Geometry?
    private val rings: List<Ring>

    init {
        // Goalies and drill dummies are never offside (§8.9), so only the outfield gets a ring.
        val outfield = first.players.indices.filter {
            first.players[it].role == Role.DEFENDER || first.players[it].role == Role.FORWARD
        }
        val radius = first.players.firstOrNull()?.radius ?: 0.0
        geometry = if (!live) null else Geometry(
            engine,
            Shapes.ring(((radius + p.targetInner) / (radius + p.targetOuter)).toFloat(), 1f, 28),
        )
        rings = if (geometry == null) emptyList() else outfield.map { i ->
            val kit = colours[first.players[i].team].primary
            val m = materials.flatOwned(kit)
            val e = geometry.renderable(listOf(m), shadows = false, priority = 5)
            Ring(i, Node(engine, parent, existing = e), m, kit, first.players[i].radius + p.targetOuter)
        }
    }

    /**
     * One frame: [s].offside says who the whistle would name now (§8.9), [xs]/[zs] where each player
     * is drawn, [dt] the real seconds since the last frame.
     */
    fun update(s: MatchSnapshot, xs: DoubleArray, zs: DoubleArray, dt: Double) {
        if (!live) return
        val step = dt / max(p.offsideFade, 1e-6)
        for (r in rings) {
            val want = if (s.offside[r.player]) 1.0 else 0.0
            r.fade = if (r.fade < want) min(want, r.fade + step) else max(want, r.fade - step)
            if (r.fade <= 0.0) {
                if (r.shown) { scene.removeEntity(r.node.entity); r.shown = false }
                continue
            }
            if (!r.shown) { scene.addEntity(r.node.entity); r.shown = true }
            r.node.x = xs[r.player].toFloat(); r.node.y = 0.03f; r.node.z = zs[r.player].toFloat()
            r.node.scale(r.radius.toFloat())
            r.node.apply()
            materials.set(r.material, r.colour, p.offsideOpacity * r.fade)
        }
    }

    fun destroy() {
        rings.forEach { if (it.shown) scene.removeEntity(it.node.entity) }
        geometry?.destroy()
        materials.release(rings.map { it.material })
    }
}
