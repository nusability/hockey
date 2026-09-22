import Foundation

/// The motion vocabulary's spring (ADR 0005, `shared/data/motion.json`): named springs both
/// platforms read, integrated identically, so a bounce on iOS is the bounce on Android.
public struct SpringToken: Sendable, Hashable {
    public let stiffness: Double
    public let damping: Double

    public init(stiffness: Double, damping: Double) {
        self.stiffness = stiffness
        self.damping = damping
    }
}

/// A damped spring toward `target`, integrated with semi-implicit Euler in fixed 1/240 s substeps
/// — the same equations and step on both platforms, so a curve can be pinned by a golden vector.
public struct Spring: Sendable {
    public static let step = 1.0 / 240.0
    public let token: SpringToken
    public private(set) var value: Double
    public var velocity = 0.0
    public var target: Double
    private var carry = 0.0

    public init(_ token: SpringToken, initial: Double = 0) {
        self.token = token
        value = initial
        target = initial
    }

    public mutating func kick(_ impulse: Double) { velocity += impulse }

    /// Jumps to `v` and stops there — restarting a one-shot move.
    public mutating func snap(to v: Double) {
        value = v
        target = v
        velocity = 0
        carry = 0
    }

    /// Stops exactly on the target it is already at rest on, so a pose lands on its mark rather
    /// than a hair short of it for ever.
    public mutating func settle() {
        value = target
        velocity = 0
        carry = 0
    }

    /// At rest on its target (to well below anything visible).
    public var isSettled: Bool { abs(value - target) < 1e-3 && abs(velocity) < 1e-2 }

    public mutating func advance(_ dt: Double) {
        carry += dt
        while carry >= Spring.step {
            let a = -token.stiffness * (value - target) - token.damping * velocity
            velocity += a * Spring.step
            value += velocity * Spring.step
            carry -= Spring.step
        }
    }
}

/// An element's arrival and departure (conventions: UI) — the pure half of the UI kit's presence,
/// shared by both apps so a screen moves the same way on each, and so a test can pin it.
///
/// It **terminates**: an arrival ends on its exact pose, and a leave always reaches `hidden` —
/// whichever way it is being played. Both springs run whatever the motion setting is; Reduce
/// Motion only changes how the element is *drawn* (at rest, fading over `fadeSeconds`) and adds a
/// second way for a leave to finish. That is what keeps Reduce Motion turning on or off mid-flight
/// — Android reads the system setting every frame — from stranding an element half-gone on screen.
public struct UIPresence: Sendable {
    public enum Phase: Sendable, Hashable { case hidden, shown, leaving }

    public private(set) var phase = Phase.hidden
    /// 0…1, Reduce Motion's plain fade; 1 whenever the whimsical motion is playing.
    public private(set) var opacity = 0.0
    private var enter: Spring
    private var exit: Spring
    private var pending: (phase: Phase, delay: Double)?

    public init(enter: SpringToken, exit: SpringToken) {
        self.enter = Spring(enter)
        self.exit = Spring(exit)
    }

    public mutating func show(after delay: Double = 0) { pending = (.shown, delay) }

    public mutating func hide(after delay: Double = 0) {
        if phase == .hidden { pending = nil; return }     // an arrival not yet begun is cancelled
        pending = (.leaving, delay)
    }

    /// Visible or about to be: the element is (or will soon be) on screen.
    public var isVisible: Bool { phase != .hidden || pending?.phase == .shown }
    /// Arrived and not leaving — the only state in which it takes touches or reaches VoiceOver.
    public var isSettledIn: Bool { phase == .shown && pending == nil && enter.value > 0.85 }
    /// 0…1(+overshoot) progress of the arrival, for elements that stage their own children.
    public var arrival: Double { enter.value }
    /// 0…1 progress of the departure.
    public var departure: Double { exit.value }

    /// One frame. `fadeSeconds` is Reduce Motion's fade (`motion.json` `fade.seconds`).
    public mutating func advance(_ dt: Double, reduceMotion: Bool, fadeSeconds: Double) {
        if let p = pending {
            let left = p.delay - dt
            if left > 0 { pending = (p.phase, left) } else { begin(p.phase); pending = nil }
        }
        // Both springs run under either setting: never snap a target away, or the transition the
        // other setting was playing can no longer finish.
        enter.advance(dt)
        exit.advance(dt)
        if reduceMotion {
            let goal = phase == .shown ? 1.0 : 0.0
            let step = fadeSeconds > 0 ? dt / fadeSeconds : 1
            opacity = opacity < goal ? min(goal, opacity + step) : max(goal, opacity - step)
        } else {
            opacity = 1
        }
        // A leave is over when the way it is being drawn says it is — the spring has run out, or
        // the fade has. Either one ends it.
        if phase == .leaving, exit.value > 0.97 || exit.isSettled || (reduceMotion && opacity <= 0) {
            phase = .hidden
            exit.settle()
        }
        // Arrived means arrived, on the mark.
        if phase != .leaving, enter.isSettled { enter.settle() }
    }

    private mutating func begin(_ next: Phase) {
        switch next {
        case .shown:
            if phase != .shown { enter.snap(to: 0); exit.snap(to: 0); enter.target = 1 }
            phase = .shown
        case .leaving:
            guard phase != .hidden else { return }
            if phase != .leaving { exit.snap(to: 0); exit.target = 1 }
            phase = .leaving
        case .hidden:
            phase = .hidden
        }
    }
}
