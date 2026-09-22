import simd

/// The match's shapes, built from primitives — the twin of Android's Shapes.kt, the same shapes,
/// sizes and facet counts. The players are the web prototype's disks (ADR 0006): a shape stands on
/// y = 0, centred on its player.
enum Shapes {
    typealias P = Presentation.Player

    /// A player's body: a squat cylinder of the player's radius, narrower at the foot.
    static func body(radius r: Float, height h: Float) -> MeshKit {
        var k = MeshKit()
        k.cylinder(y0: 0, y1: h, r0: r * Float(P.foot), r1: r, segments: P.segments)
        return k
    }

    /// The outfield player's dot on top of the body.
    static func dot(radius r: Float, height h: Float) -> MeshKit {
        var k = MeshKit()
        k.disc(radius: r * Float(P.dot), y: h + 0.01, segments: 24)
        return k
    }

    /// The goalie's ring on top of the body.
    static func goalieRing(radius r: Float, height h: Float) -> MeshKit {
        var k = MeshKit()
        k.annulus(inner: r * Float(P.ringInner), outer: r * Float(P.ringOuter), y: h + 0.01, segments: P.segments)
        return k
    }

    /// A dummy's band: an open cylinder just outside its body.
    static func stripe(radius r: Float) -> MeshKit {
        typealias D = Presentation.Dummy
        var k = MeshKit()
        let y = Float(D.height * D.stripeAt), half = Float(D.stripeHeight) / 2, rr = r * Float(D.stripeGrow)
        k.cylinder(y0: y - half, y1: y + half, r0: rr, r1: rr, segments: P.segments, top: false, bottom: false)
        return k
    }

    /// The soft disc under a player: radius + the margin.
    static func shadow(radius r: Float) -> MeshKit {
        var k = MeshKit()
        k.disc(radius: r + Float(P.shadowMargin), y: 0.02, segments: 24)
        return k
    }

    /// The field ball: a smooth sphere of the ball's radius, resting on the ground.
    static func ball(radius r: Float) -> MeshKit {
        var k = MeshKit()
        k.sphere(smooth: SIMD3(0, r, 0), radius: r, rings: 14, segments: 18)
        return k
    }

    /// The puck (ice, §1): a flat cylinder of the ball's radius.
    static func puck(radius r: Float, height h: Float) -> MeshKit {
        var k = MeshKit()
        k.cylinder(y0: 0, y1: h, r0: r, r1: r, segments: 18)
        return k
    }

    /// A flat disc of radius 1 on the ground (scaled to size).
    static func disc() -> MeshKit {
        var k = MeshKit()
        k.disc(radius: 1, y: 0, segments: 20)
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

    /// A flat ring from radius `inner` to `outer` on the ground.
    static func ring(inner: Float, outer: Float, segments: Int = 40) -> MeshKit {
        var k = MeshKit()
        k.annulus(inner: inner, outer: outer, y: 0, segments: segments)
        return k
    }

    /// A confetti piece: a thin square card.
    static func card() -> MeshKit {
        var k = MeshKit()
        k.box(.zero, SIMD3(1, 0.08, 0.7))
        return k
    }
}
