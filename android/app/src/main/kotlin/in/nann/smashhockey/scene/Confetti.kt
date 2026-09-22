package `in`.nann.smashhockey.scene

import com.google.android.filament.Engine
import com.google.android.filament.Scene
import `in`.nann.smashhockey.engine.Geometry
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.engine.Node
import `in`.nann.smashhockey.generated.Presentation
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.sin

/**
 * A goal's confetti: cards thrown up from the net, tumbling down on real time — the twin of iOS's
 * Confetti.swift. Presentation only: its randomness is its own generator, never a match stream (§4.3).
 */
class Confetti(private val engine: Engine, private val scene: Scene, parent: Int, materials: Materials) {
    private val c = Presentation.Celebration
    private val geometry = Geometry(engine, Figures.card())
    private class Piece(val node: Node) { var vx = 0f; var vy = 0f; var vz = 0f; var sx = 0f; var sy = 0f; var sz = 0f }
    private val pieces: List<Piece>
    private var age = Double.POSITIVE_INFINITY
    private var state = 0x5EEDL
    private var visible = false

    init {
        val colours = c.colours.map { materials.actor(it) }
        pieces = (0 until c.pieces).map { i ->
            val e = geometry.renderable(listOf(colours[i % colours.size]), shadows = false)
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

    fun burst(goalZ: Float) {
        age = 0.0
        if (!visible) { pieces.forEach { scene.addEntity(it.node.entity) }; visible = true }
        for (p in pieces) {
            val a = next() * 2f * PI.toFloat()
            val up = 0.55f + 0.45f * next()
            val speed = c.speed.toFloat() * (0.6f + 0.4f * next())
            val out = if (goalZ >= 0) -1f else 1f
            p.vx = cos(a) * (1 - up) * speed; p.vy = up * speed; p.vz = (sin(a) * (1 - up) * 0.6f + out * 0.25f) * speed
            p.sx = (next() - 0.5f) * 14; p.sy = (next() - 0.5f) * 14; p.sz = (next() - 0.5f) * 14
            p.node.x = (next() - 0.5f) * 6; p.node.y = 1.2f; p.node.z = goalZ + (next() - 0.5f) * 1.5f
            p.node.scale(c.size.toFloat()); p.node.apply()
        }
    }

    fun advance(dt: Double) {
        if (age >= c.seconds) return
        age += dt
        if (age >= c.seconds) { pieces.forEach { scene.removeEntity(it.node.entity) }; visible = false; return }
        val t = dt.toFloat()
        val fade = ((c.seconds - age) / 0.6).coerceIn(0.0, 1.0).toFloat()
        val drag = exp(-1.4f * t)
        for (p in pieces) {
            p.vy -= c.gravity.toFloat() * t
            p.vx *= drag; p.vy *= drag; p.vz *= drag
            val n = p.node
            n.x += p.vx * t; n.y += p.vy * t; n.z += p.vz * t
            if (n.y < 0.05f) { n.y = 0.05f; p.vx = 0f; p.vy = 0f; p.vz = 0f }
            n.yaw += p.sy * t; n.pitch += p.sx * t; n.roll += p.sz * t
            n.scale(c.size.toFloat() * fade)
            n.apply()
        }
    }

    fun destroy() {
        if (visible) pieces.forEach { scene.removeEntity(it.node.entity) }
        geometry.destroy()
    }
}
