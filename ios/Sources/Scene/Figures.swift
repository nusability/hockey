import simd

/// The match's toys, built from primitives (the twin of Android's Figures.kt — the same shapes,
/// sizes and facet counts). A figure stands on y = 0 and faces +Z; its parts use the material
/// slots below.
enum Figures {
    enum Slot {
        static let primary = 0, secondary = 1, skin = 2, stick = 3, dark = 4
    }

    /// An outfield player: chunky legs, a round-shouldered shirt, a big head with a cap, and a
    /// stick held down to the right. About 2.1 m tall, 0.9 m across — a toy, not an athlete.
    static func outfield() -> MeshKit {
        var k = MeshKit()
        k.slot = Slot.secondary
        k.frustum(x: -0.17, y0: 0, y1: 0.5, r0: 0.15, r1: 0.17, segments: 8)
        k.frustum(x: 0.17, y0: 0, y1: 0.5, r0: 0.15, r1: 0.17, segments: 8)
        k.slot = Slot.primary
        k.frustum(y0: 0.45, y1: 1.12, r0: 0.4, r1: 0.45, segments: 10)
        k.sphere(SIMD3(0, 1.12, 0), radius: 0.45, rings: 6, segments: 10, upper: true)
        head(&k, y: 1.66, radius: 0.34, cap: Slot.secondary)
        stick(&k)
        return k
    }

    /// A goalie: wider, padded legs in the kit's primary, a shirt in its secondary, a helmet with a
    /// cage, a blocker — plainly not an outfield player.
    static func goalie() -> MeshKit {
        var k = MeshKit()
        k.slot = Slot.primary
        k.box(SIMD3(-0.24, 0.32, 0.06), SIMD3(0.36, 0.64, 0.4))
        k.box(SIMD3(0.24, 0.32, 0.06), SIMD3(0.36, 0.64, 0.4))
        k.slot = Slot.secondary
        k.frustum(y0: 0.55, y1: 1.18, r0: 0.5, r1: 0.52, segments: 10)
        k.sphere(SIMD3(0, 1.18, 0), radius: 0.52, rings: 6, segments: 10, upper: true)
        k.slot = Slot.primary
        k.box(SIMD3(-0.62, 0.95, 0.2), SIMD3(0.3, 0.42, 0.3))          // the blocker
        head(&k, y: 1.74, radius: 0.36, cap: Slot.primary)
        k.slot = Slot.stick
        k.box(SIMD3(0, 1.68, 0.36), SIMD3(0.46, 0.34, 0.06))            // the cage
        k.box(SIMD3(0.55, 0.5, 0.45), SIMD3(0.12, 1.0, 0.12))
        k.slot = Slot.dark
        k.box(SIMD3(0.55, 0.06, 0.62), SIMD3(0.22, 0.12, 0.5))
        return k
    }

    private static func head(_ k: inout MeshKit, y: Float, radius r: Float, cap: Int) {
        k.slot = Slot.skin
        k.sphere(SIMD3(0, y, 0), radius: r, rings: 6, segments: 10)
        k.slot = cap
        k.sphere(SIMD3(0, y + 0.06, -0.02), radius: r * 1.06, rings: 6, segments: 10, upper: true)
        k.box(SIMD3(0, y + 0.07, r * 0.95), SIMD3(r * 1.3, 0.06, r * 0.7))   // the peak
        k.slot = Slot.dark
        k.box(SIMD3(-r * 0.36, y - 0.04, r * 0.92), SIMD3(0.08, 0.11, 0.06))
        k.box(SIMD3(r * 0.36, y - 0.04, r * 0.92), SIMD3(0.08, 0.11, 0.06))
    }

    /// The stick: a shaft from the right hand down and forward, and a dark blade on the ground.
    private static func stick(_ k: inout MeshKit) {
        let saved = k.transform
        k.slot = Slot.stick
        k.transform = saved * .translation(SIMD3(0.5, 0.52, 0.5)) * .rotation(-0.72, SIMD3(1, 0, 0))
        k.box(.zero, SIMD3(0.09, 1.25, 0.09))
        k.transform = saved
        k.slot = Slot.dark
        k.box(SIMD3(0.44, 0.06, 0.98), SIMD3(0.34, 0.12, 0.1))
        k.transform = saved
    }

    /// A training dummy (§10): a traffic cone on a dark disc, radius 0.9 like its body.
    static func dummy(height h: Float) -> MeshKit {
        var k = MeshKit()
        k.slot = Slot.dark
        k.frustum(y0: 0, y1: 0.12, r0: 0.9, r1: 0.9, segments: 12)
        k.slot = Slot.primary
        k.frustum(y0: 0.12, y1: h * 0.45, r0: 0.72, r1: 0.72 * 0.55 + 0.07, segments: 12)
        k.frustum(y0: h * 0.62, y1: h, r0: 0.72 * 0.38 + 0.05, r1: 0.06, segments: 12)
        k.slot = Slot.secondary
        k.frustum(y0: h * 0.45, y1: h * 0.62, r0: 0.72 * 0.55 + 0.07, r1: 0.72 * 0.38 + 0.05, segments: 12)
        return k
    }

    /// The field ball: a faceted sphere of the ball's radius, resting on the ground.
    static func ball(radius r: Float) -> MeshKit {
        var k = MeshKit()
        k.sphere(SIMD3(0, r, 0), radius: r, rings: 6, segments: 10)
        return k
    }

    /// The puck (ice, §1): a flat disc of the ball's radius.
    static func puck(radius r: Float, height h: Float) -> MeshKit {
        var k = MeshKit()
        k.frustum(y0: 0, y1: h, r0: r, r1: r, segments: 14)
        return k
    }

    /// A unit strip on the ground: x in ±0.5, z from 0 to 1 — scaled into the aim line.
    static func strip() -> MeshKit {
        var k = MeshKit()
        k.quad(SIMD3(-0.5, 0, 0), SIMD3(-0.5, 0, 1), SIMD3(0.5, 0, 1), SIMD3(0.5, 0, 0))
        return k
    }

    /// The aim line's arrowhead: a unit triangle pointing down +Z from z = 0.
    static func arrowhead() -> MeshKit {
        var k = MeshKit()
        k.triangle(SIMD3(-0.5, 0, 0), SIMD3(0, 0, 1), SIMD3(0.5, 0, 0))
        return k
    }

    /// A flat ring of radius 1 (scaled to size) and the given relative width.
    static func ring(width: Float) -> MeshKit {
        var k = MeshKit()
        k.annulus(inner: 1 - width / 2, outer: 1 + width / 2, y: 0, segments: 40)
        return k
    }

    /// A confetti piece: a thin square card.
    static func card() -> MeshKit {
        var k = MeshKit()
        k.box(.zero, SIMD3(1, 0.08, 0.7))
        return k
    }
}
