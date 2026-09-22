package `in`.nann.smashhockey.scene

import `in`.nann.smashhockey.engine.MeshKit
import `in`.nann.smashhockey.engine.Vec3
import `in`.nann.smashhockey.generated.Presentation

/**
 * The match's shapes, built from primitives — the twin of iOS's Shapes.swift: the same shapes,
 * sizes and facet counts. The players are the web prototype's disks (ADR 0006): a shape stands on
 * y = 0, centred on its player.
 */
object Shapes {
    private val P = Presentation.Player

    /** A player's body: a squat cylinder of the player's radius, narrower at the foot. */
    fun body(r: Float, h: Float) = MeshKit().apply { cylinder(0f, h, r * P.foot.toFloat(), r, P.segments) }

    /** The outfield player's dot on top of the body. */
    fun dot(r: Float, h: Float) = MeshKit().apply { disc(r * P.dot.toFloat(), h + 0.01f, 24) }

    /** The goalie's ring on top of the body. */
    fun goalieRing(r: Float, h: Float) = MeshKit().apply {
        annulus(r * P.ringInner.toFloat(), r * P.ringOuter.toFloat(), h + 0.01f, P.segments)
    }

    /** A dummy's band: an open cylinder just outside its body. */
    fun stripe(r: Float) = MeshKit().apply {
        val d = Presentation.Dummy
        val y = (d.height * d.stripeAt).toFloat(); val half = d.stripeHeight.toFloat() / 2; val rr = r * d.stripeGrow.toFloat()
        cylinder(y - half, y + half, rr, rr, P.segments, top = false, bottom = false)
    }

    /** The soft disc under a player: radius + the margin. */
    fun shadow(r: Float) = MeshKit().apply { disc(r + P.shadowMargin.toFloat(), 0.02f, 24) }

    /** The field ball: a smooth sphere of the ball's radius about its own centre (drawn one radius up, so it rolls about it). */
    fun ball(r: Float) = MeshKit().apply { smoothSphere(Vec3(0f, 0f, 0f), r, 14, 18) }

    /**
     * The aim arrow's ribbon (§5.2): unit long down +z in 12 segments, its width tapering from [near]
     * at z = 0 to [far] at z = 1, centred on x.
     */
    fun ribbon(near: Float, far: Float) = MeshKit().apply {
        val n = 12
        for (i in 0 until n) {
            val t0 = i.toFloat() / n; val t1 = (i + 1).toFloat() / n
            val w0 = (near + (far - near) * t0) / 2; val w1 = (near + (far - near) * t1) / 2
            quad(Vec3(-w0, 0f, t0), Vec3(-w1, 0f, t1), Vec3(w1, 0f, t1), Vec3(w0, 0f, t0))
        }
    }

    /**
     * The arrowhead (§5.2): the outline [head] — (x, z) of the tip, one wing and the notch; the other
     * wing mirrored — × [scale], its notch toward the ribbon.
     */
    fun arrowhead(head: List<Double>, scale: Float) = MeshKit().apply {
        fun v(x: Double, z: Double) = Vec3((x * scale).toFloat(), 0f, (z * scale).toFloat())
        val tip = v(head[0], head[1]); val notch = v(head[4], head[5])
        triangle(tip, v(head[2], head[3]), notch)
        triangle(tip, notch, v(-head[2], head[3]))
    }

    /** A unit quad standing up: x in ±0.5, y from 0 to 1 (the goal mouth's glow). */
    fun sheet() = MeshKit().apply { quad(Vec3(-0.5f, 0f, 0f), Vec3(0.5f, 0f, 0f), Vec3(0.5f, 1f, 0f), Vec3(-0.5f, 1f, 0f)) }

    /** The puck (ice, §1): a flat cylinder of the ball's radius. */
    fun puck(r: Float, h: Float) = MeshKit().apply { cylinder(0f, h, r, r, 18) }

    /** A flat disc of radius 1 on the ground (scaled to size). */
    fun disc() = MeshKit().apply { disc(1f, 0f, 20) }

    /** A unit strip on the ground: x in ±0.5, z from 0 to 1. */
    fun strip() = MeshKit().apply { quad(Vec3(-0.5f, 0f, 0f), Vec3(-0.5f, 0f, 1f), Vec3(0.5f, 0f, 1f), Vec3(0.5f, 0f, 0f)) }

    /** A flat ring from radius [inner] to [outer] on the ground. */
    fun ring(inner: Float, outer: Float, segments: Int = 40) = MeshKit().apply { annulus(inner, outer, 0f, segments) }

    /** A confetti piece (§8.8): a thin card of the declared size. */
    fun card(size: List<Double>) = MeshKit().apply {
        box(Vec3(0f, 0f, 0f), Vec3(size[0].toFloat(), size[1].toFloat(), size[2].toFloat()))
    }
}
