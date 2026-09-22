import RealityKit
import simd

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

/// An element's arrival and departure, driven only by motion tokens: `pop` in, `soft` out, and
/// under Reduce Motion plain fades of `fade.seconds` with no movement at all (conventions: UI).
struct Presence {
    enum Phase { case hidden, shown, leaving }
    private(set) var phase = Phase.hidden
    var style: Entrance
    private var enter: Spring
    private var exit: Spring
    private var opacity = 0.0
    private var pending: (phase: Phase, delay: Double)?

    init(_ style: Entrance, motion: MotionTokens) {
        self.style = style
        enter = Spring(motion.spring(.pop))
        exit = Spring(motion.spring(.soft))
    }

    mutating func show(after delay: Double = 0) { pending = (.shown, delay) }
    mutating func hide(after delay: Double = 0) {
        if phase == .hidden { pending = nil; return }
        pending = (.leaving, delay)
    }

    /// Visible or about to be: the element is (or will soon be) on screen.
    var isVisible: Bool { phase != .hidden || pending?.phase == .shown }
    /// Arrived and not leaving — the only state in which it takes touches or reaches VoiceOver.
    var isSettledIn: Bool { phase == .shown && pending == nil && enter.value > 0.85 }
    /// 0…1(+overshoot) progress of the arrival, for elements that stage their own children.
    var arrival: Double { enter.value }

    mutating func advance(_ dt: Double, _ ctx: UIContext) {
        if let p = pending {
            let left = p.delay - dt
            if left > 0 { pending = (p.phase, left) } else { begin(p.phase); pending = nil }
        }
        if ctx.reduceMotion {
            let goal = phase == .shown ? 1.0 : 0.0
            let step = dt / ctx.motion.fadeSeconds
            opacity = opacity < goal ? min(goal, opacity + step) : max(goal, opacity - step)
            enter.snap(to: phase == .hidden ? 0 : 1)
            exit.snap(to: 0)
            if phase == .leaving && opacity == 0 { phase = .hidden }
            return
        }
        enter.advance(dt)
        exit.advance(dt)
        opacity = 1
        if phase == .leaving && exit.value > 0.97 { phase = .hidden }
    }

    private mutating func begin(_ next: Phase) {
        switch next {
        case .shown:
            if phase != .shown { enter.snap(to: 0); exit.snap(to: 0); enter.target = 1 }
            phase = .shown
        case .leaving:
            guard phase == .shown else { return }
            exit.target = 1
            phase = .leaving
        case .hidden:
            phase = .hidden
        }
    }

    /// Poses `e` at `rest` bent by the arrival or departure, and fades it under Reduce Motion.
    @MainActor func apply(to e: Entity, rest: Transform, reduceMotion: Bool) {
        let visible = phase != .hidden
        if e.isEnabled != visible { e.isEnabled = visible }
        guard visible else { return }
        if reduceMotion {
            e.transform = rest
            setOpacity(e, Float(opacity))
            return
        }
        let a = Float(enter.value), x = Float(exit.value)
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
