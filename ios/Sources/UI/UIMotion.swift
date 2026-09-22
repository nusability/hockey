import RealityKit
import simd
import SmashCore

/// How an element arrives. Leaving is always the same goofy exit: a hop, a spin, a fall.
enum Entrance {
    /// Grows from nothing, stretching tall as it overshoots.
    case pop
    /// Tips up from lying flat, like a sign on a hinge.
    case tumble
    /// Falls in from above and squashes on landing.
    case drop
    /// Rolls in from the left or the right.
    case slide(fromLeft: Bool)
}

/// An element's arrival and departure on screen: the core's `UIPresence` (which decides *when* an
/// element is arriving, arrived, leaving or gone, and is pinned by `FeelTests`) plus this app's
/// half — how it is posed while it does. `pop` in, `soft` out, and under Reduce Motion plain fades
/// of `fade.seconds` with no movement at all (conventions: UI). The twin of Android's `Presence`.
struct Presence {
    var style: Entrance
    private var core: UIPresence

    init(_ style: Entrance, motion: MotionTokens) {
        self.style = style
        core = UIPresence(enter: motion.spring(.pop), exit: motion.spring(.soft))
    }

    mutating func show(after delay: Double = 0) { core.show(after: delay) }
    mutating func hide(after delay: Double = 0) { core.hide(after: delay) }

    /// Visible or about to be: the element is (or will soon be) on screen.
    var isVisible: Bool { core.isVisible }
    /// Arrived and not leaving — the only state in which it takes touches or reaches VoiceOver.
    var isSettledIn: Bool { core.isSettledIn }
    /// 0…1(+overshoot) progress of the arrival, for elements that stage their own children.
    var arrival: Double { core.arrival }

    mutating func advance(_ dt: Double, _ ctx: UIContext) {
        core.advance(dt, reduceMotion: ctx.reduceMotion, fadeSeconds: ctx.motion.fadeSeconds)
    }

    /// Poses `e` at `rest` bent by the arrival or departure, and fades it under Reduce Motion.
    @MainActor func apply(to e: Entity, rest: Transform, reduceMotion: Bool) {
        let visible = core.phase != .hidden
        if e.isEnabled != visible { e.isEnabled = visible }
        guard visible else { return }
        if reduceMotion {
            e.transform = rest
            setOpacity(e, Float(core.opacity))
            return
        }
        let a = Float(core.arrival), x = Float(core.departure)
        var offset = SIMD3<Float>.zero
        var scale = SIMD3<Float>(repeating: 1)
        var turn = simd_quatf(angle: 0, axis: [0, 0, 1])
        switch style {
        case .pop:
            let s = max(0, a)
            scale = SIMD3(s - (s - 1) * 0.5, s + (s - 1) * 0.9, s)
        case .tumble:
            turn = simd_quatf(angle: (1 - a) * 1.5, axis: [1, 0, 0])
            offset.y = -(1 - a) * 0.25
            scale = SIMD3(repeating: min(1, max(0, a) * 2.5))
        case .drop:
            offset.y = (1 - a) * 1.4
            let squash = max(0, a - 1) * 2.2
            scale = SIMD3(1 + squash * 0.6, 1 - squash, 1 + squash * 0.6)
        case .slide(let fromLeft):
            let side: Float = fromLeft ? -1 : 1
            offset.x = side * (1 - a) * 2.4
            turn = simd_quatf(angle: -side * (1 - a) * 1.2, axis: [0, 0, 1])
        }
        if x > 0.001 {
            let spin: Float = (rest.translation.x >= 0 ? 1 : -1)
            offset += SIMD3(spin * x * 0.35, x * 0.45 - x * x * 1.9, 0.15 * x)
            turn = simd_quatf(angle: -spin * x * 1.4, axis: [0, 0, 1]) * turn
            scale *= 1 - 0.45 * x
        }
        var t = rest
        t.translation += offset
        t.rotation = rest.rotation * turn
        t.scale = rest.scale * scale
        e.transform = t
        setOpacity(e, x > 0.6 ? 1 - (x - 0.6) / 0.4 : 1)
    }

    @MainActor private func setOpacity(_ e: Entity, _ o: Float) {
        if o >= 0.999 {
            if e.components.has(OpacityComponent.self) { e.components.remove(OpacityComponent.self) }
        } else {
            e.components.set(OpacityComponent(opacity: max(0, o)))
        }
    }
}

/// A jelly wobble — a twist about Z and a swell — on the `wobbly` spring: the celebration, the
/// "nope" of a disabled button, the thud of a flipped score.
struct Jiggle {
    private var twist: Spring
    private var swell: Spring

    init(_ token: SpringToken) {
        twist = Spring(token)
        swell = Spring(token)
    }

    /// `twist` in radians/s of angular kick, `swell` in scale units/s.
    mutating func kick(twist t: Double, swell s: Double) {
        twist.kick(t)
        swell.kick(s)
    }

    mutating func advance(_ dt: Double, reduceMotion: Bool) {
        if reduceMotion { twist.snap(to: 0); swell.snap(to: 0); return }
        twist.advance(dt)
        swell.advance(dt)
    }

    var rotation: simd_quatf { simd_quatf(angle: Float(twist.value), axis: [0, 0, 1]) }
    var scale: Float { 1 + Float(swell.value) }
}
