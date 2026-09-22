package `in`.nann.smashhockey.scene

import `in`.nann.smashhockey.engine.MeshKit
import `in`.nann.smashhockey.engine.Vec3

/**
 * The match's toys, built from primitives — the twin of iOS's Figures.swift: the same shapes,
 * sizes and facet counts. A figure stands on y = 0 and faces +Z; its parts use the slots below.
 */
object Figures {
    object Slot { const val PRIMARY = 0; const val SECONDARY = 1; const val SKIN = 2; const val STICK = 3; const val DARK = 4 }

    /** An outfield player: chunky legs, a round-shouldered shirt, a big head with a cap, a stick. */
    fun outfield() = MeshKit().apply {
        slot = Slot.SECONDARY
        frustum(x = -0.17f, y0 = 0f, y1 = 0.5f, r0 = 0.15f, r1 = 0.17f, segments = 8)
        frustum(x = 0.17f, y0 = 0f, y1 = 0.5f, r0 = 0.15f, r1 = 0.17f, segments = 8)
        slot = Slot.PRIMARY
        frustum(y0 = 0.45f, y1 = 1.12f, r0 = 0.4f, r1 = 0.45f, segments = 10)
        sphere(Vec3(0f, 1.12f, 0f), 0.45f, 6, 10, upper = true)
        head(this, 1.66f, 0.34f, Slot.SECONDARY)
        stick(this)
    }

    /** A goalie: padded legs, a shirt in the secondary, a helmet with a cage, a blocker. */
    fun goalie() = MeshKit().apply {
        slot = Slot.PRIMARY
        box(Vec3(-0.24f, 0.32f, 0.06f), Vec3(0.36f, 0.64f, 0.4f))
        box(Vec3(0.24f, 0.32f, 0.06f), Vec3(0.36f, 0.64f, 0.4f))
        slot = Slot.SECONDARY
        frustum(y0 = 0.55f, y1 = 1.18f, r0 = 0.5f, r1 = 0.52f, segments = 10)
        sphere(Vec3(0f, 1.18f, 0f), 0.52f, 6, 10, upper = true)
        slot = Slot.PRIMARY
        box(Vec3(-0.62f, 0.95f, 0.2f), Vec3(0.3f, 0.42f, 0.3f))
        head(this, 1.74f, 0.36f, Slot.PRIMARY)
        slot = Slot.STICK
        box(Vec3(0f, 1.68f, 0.36f), Vec3(0.46f, 0.34f, 0.06f))
        box(Vec3(0.55f, 0.5f, 0.45f), Vec3(0.12f, 1.0f, 0.12f))
        slot = Slot.DARK
        box(Vec3(0.55f, 0.06f, 0.62f), Vec3(0.22f, 0.12f, 0.5f))
    }

    private fun head(k: MeshKit, y: Float, r: Float, cap: Int) = with(k) {
        slot = Slot.SKIN
        sphere(Vec3(0f, y, 0f), r, 6, 10)
        slot = cap
        sphere(Vec3(0f, y + 0.06f, -0.02f), r * 1.06f, 6, 10, upper = true)
        box(Vec3(0f, y + 0.07f, r * 0.95f), Vec3(r * 1.3f, 0.06f, r * 0.7f))
        slot = Slot.DARK
        box(Vec3(-r * 0.36f, y - 0.04f, r * 0.92f), Vec3(0.08f, 0.11f, 0.06f))
        box(Vec3(r * 0.36f, y - 0.04f, r * 0.92f), Vec3(0.08f, 0.11f, 0.06f))
    }

    private fun stick(k: MeshKit) = with(k) {
        val saved = transform
        slot = Slot.STICK
        transform = MeshKit.times(saved, MeshKit.times(MeshKit.translation(0.5f, 0.52f, 0.5f), MeshKit.rotation(-0.72f, 1f, 0f, 0f)))
        box(Vec3(0f, 0f, 0f), Vec3(0.09f, 1.25f, 0.09f))
        transform = saved
        slot = Slot.DARK
        box(Vec3(0.44f, 0.06f, 0.98f), Vec3(0.34f, 0.12f, 0.1f))
    }

    /** A training dummy (§10): a traffic cone on a dark disc. */
    fun dummy(h: Float) = MeshKit().apply {
        slot = Slot.DARK
        frustum(y0 = 0f, y1 = 0.12f, r0 = 0.9f, r1 = 0.9f, segments = 12)
        slot = Slot.PRIMARY
        frustum(y0 = 0.12f, y1 = h * 0.45f, r0 = 0.72f, r1 = 0.72f * 0.55f + 0.07f, segments = 12)
        frustum(y0 = h * 0.62f, y1 = h, r0 = 0.72f * 0.38f + 0.05f, r1 = 0.06f, segments = 12)
        slot = Slot.SECONDARY
        frustum(y0 = h * 0.45f, y1 = h * 0.62f, r0 = 0.72f * 0.55f + 0.07f, r1 = 0.72f * 0.38f + 0.05f, segments = 12)
    }

    fun ball(r: Float) = MeshKit().apply { sphere(Vec3(0f, r, 0f), r, 6, 10) }

    fun puck(r: Float, h: Float) = MeshKit().apply { frustum(y0 = 0f, y1 = h, r0 = r, r1 = r, segments = 14) }

    /** A unit strip on the ground: x in ±0.5, z from 0 to 1. */
    fun strip() = MeshKit().apply { quad(Vec3(-0.5f, 0f, 0f), Vec3(-0.5f, 0f, 1f), Vec3(0.5f, 0f, 1f), Vec3(0.5f, 0f, 0f)) }

    /** The aim line's arrowhead: a unit triangle pointing down +Z. */
    fun arrowhead() = MeshKit().apply { triangle(Vec3(-0.5f, 0f, 0f), Vec3(0f, 0f, 1f), Vec3(0.5f, 0f, 0f)) }

    fun ring(width: Float) = MeshKit().apply { annulus(1f - width / 2, 1f + width / 2, 0f, 40) }

    fun card() = MeshKit().apply { box(Vec3(0f, 0f, 0f), Vec3(1f, 0.08f, 0.7f)) }
}
