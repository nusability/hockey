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

    /** The field ball: a smooth sphere of the ball's radius, resting on the ground. */
    fun ball(r: Float) = MeshKit().apply { smoothSphere(Vec3(0f, r, 0f), r, 14, 18) }

    /** The puck (ice, §1): a flat cylinder of the ball's radius. */
    fun puck(r: Float, h: Float) = MeshKit().apply { cylinder(0f, h, r, r, 18) }

    /** A flat disc of radius 1 on the ground (scaled to size). */
    fun disc() = MeshKit().apply { disc(1f, 0f, 20) }

    /** A unit strip on the ground: x in ±0.5, z from 0 to 1. */
    fun strip() = MeshKit().apply { quad(Vec3(-0.5f, 0f, 0f), Vec3(-0.5f, 0f, 1f), Vec3(0.5f, 0f, 1f), Vec3(0.5f, 0f, 0f)) }

    /** The aim line's arrowhead: a unit triangle pointing down +Z. */
    fun arrowhead() = MeshKit().apply { triangle(Vec3(-0.5f, 0f, 0f), Vec3(0f, 0f, 1f), Vec3(0.5f, 0f, 0f)) }

    /** A flat ring from radius [inner] to [outer] on the ground. */
    fun ring(inner: Float, outer: Float, segments: Int = 40) = MeshKit().apply { annulus(inner, outer, 0f, segments) }

    /** A confetti piece: a thin square card. */
    fun card() = MeshKit().apply { box(Vec3(0f, 0f, 0f), Vec3(1f, 0.08f, 0.7f)) }
}
