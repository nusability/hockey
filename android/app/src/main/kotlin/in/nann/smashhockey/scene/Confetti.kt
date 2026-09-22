package `in`.nann.smashhockey.scene

import android.opengl.Matrix
import com.google.android.filament.Engine
import com.google.android.filament.Scene
import `in`.nann.smashhockey.engine.Geometry
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.engine.Node
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.generated.WorldLook

/**
 * A goal's confetti (spec §8.8), the prototype's burst — the twin of iOS's Confetti.swift: cards in
 * the scoring side's primary, secondary and white, thrown sideways and up from the scored-in net,
 * falling, bouncing and tumbling on real time. Presentation only: its randomness is its own
 * generator, never a match stream (§4.3).
 */
class Confetti(
    private val engine: Engine,
    private val scene: Scene,
    parent: Int,
    materials: Materials,
    look: WorldLook,
    colours: List<TeamColours>,
) {
    private val c = Presentation.Celebration
    private val geometry = Geometry(engine, Shapes.card(c.size))
    /** Per side, the three card colours: primary, secondary, white. */
    private val palettes = colours.map { k -> listOf(k.primary, k.secondary, 0xFFFFFF).map { materials.toon(it, look) } }
    private class Piece(val node: Node) {
        var vx = 0f; var vy = 0f; var vz = 0f; var rx = 0f; var ry = 0f; var wx = 0f; var wy = 0f; var life = 0f
        var alive = false
    }
    private val pieces: List<Piece>
    private var state = 0x5EEDL
    private var live = 0

    init {
        pieces = (0 until c.pieces).map { i ->
            val e = geometry.renderable(listOf(palettes[0][i % 3]), shadows = false)
            Piece(Node(engine, parent, existing = e))
        }
    }

    /** A presentation-only SplitMix64 draw in [0, 1). */
    private fun next(): Float {
        state += -0x61c8864680b583ebL
        var z = state
        z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
        z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
        return ((z xor (z ushr 31)) ushr 40).toFloat() / (1 shl 24).toFloat()
    }

    private fun u(lo: Double, hi: Double) = (lo + (hi - lo) * next()).toFloat()

    /** Throws the confetti from the net on goal line [goalZ], in [team]'s colours. */
    fun burst(goalZ: Float, team: Int) {
        val rm = engine.renderableManager
        val side = c.sideways
        for ((i, p) in pieces.withIndex()) {
            rm.setMaterialInstanceAt(rm.getInstance(p.node.entity), 0, palettes[team][i % 3])
            p.node.x = u(-c.spread, c.spread); p.node.y = u(c.height[0], c.height[1]); p.node.z = goalZ + u(-c.depth, c.depth)
            p.vx = u(-side, side); p.vy = u(c.up[0], c.up[1]); p.vz = u(-side, side)
            p.rx = u(0.0, 6.0); p.ry = u(0.0, 6.0); p.wx = u(-c.spin, c.spin); p.wy = u(-c.spin, c.spin)
            p.life = u(c.life[0], c.life[1])
            if (!p.alive) { scene.addEntity(p.node.entity); p.alive = true }
            place(p)
        }
        live = pieces.size
    }

    /** Real time: fall, bounce, tumble; a card whose life is over goes. */
    fun advance(dt: Double) {
        if (live == 0) return
        val t = dt.toFloat()
        val g = c.gravity.toFloat(); val floor = c.floor.toFloat()
        for (p in pieces) {
            if (!p.alive) continue
            p.life -= t
            if (p.life <= 0f) { scene.removeEntity(p.node.entity); p.alive = false; live--; continue }
            p.vy -= g * t
            val n = p.node
            n.x += p.vx * t; n.y += p.vy * t; n.z += p.vz * t
            if (n.y < floor) {
                n.y = floor; p.vy *= -c.bounce.toFloat(); p.vx *= c.friction.toFloat(); p.vz *= c.friction.toFloat()
            }
            p.rx += p.wx * t; p.ry += p.wy * t
            place(p)
        }
    }

    /** Rotation Rx(rx)·Ry(ry), the prototype's order. */
    private fun place(p: Piece) {
        val m = FloatArray(16)
        Matrix.setRotateM(m, 0, Math.toDegrees(p.rx.toDouble()).toFloat(), 1f, 0f, 0f)
        Matrix.rotateM(m, 0, Math.toDegrees(p.ry.toDouble()).toFloat(), 0f, 1f, 0f)
        p.node.rotation = m
        p.node.apply()
    }

    fun destroy() {
        pieces.forEach { if (it.alive) scene.removeEntity(it.node.entity) }
        geometry.destroy()
    }
}
