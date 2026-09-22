import Foundation

/// The motion vocabulary (ADR 0005, `shared/data/motion.json`): named springs and fades that both
/// platforms read, integrated identically, so a bounce on iOS is the bounce on Android.
struct SpringToken: Sendable {
    let stiffness: Double
    let damping: Double
}

/// The springs the UI may ask for, by name. Every one must be in motion.json (checked at load).
enum SpringName: String, CaseIterable, Sendable {
    case bouncy, soft, pop, snappy, wobbly, swoop
}

/// Named impulses (spring velocities) a component gives itself on an event.
enum KickName: String, CaseIterable, Sendable {
    case nope, celebrate, grab
}

struct MotionTokens: Sendable {
    let bouncy: SpringToken
    let soft: SpringToken
    let fadeSeconds: Double
    let pressKick: Double
    let pressSquash: Double
    let pressBulge: Double
    /// How far a held button stays squashed (0 = rest, 1 = full squash).
    let pressHold: Double
    /// The delay between siblings arriving or leaving one after another.
    let staggerSeconds: Double
    let idleBobMetres: Double
    let idleBobSeconds: Double
    private let springs: [SpringName: SpringToken]
    private let kicks: [KickName: Double]

    func spring(_ name: SpringName) -> SpringToken { springs[name]! }   // total by construction (load)
    func kick(_ name: KickName) -> Double { kicks[name]! }

    static func load(bundle: Bundle = .main) throws -> MotionTokens {
        guard let url = bundle.url(forResource: "motion", withExtension: "json") else {
            throw AssetError.missing("motion.json — shared/data/motion.json is not in the app bundle")
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        var springs: [SpringName: SpringToken] = [:]
        for name in SpringName.allCases {
            guard let s = file.spring[name.rawValue] else { throw AssetError.missing("motion.json has no spring '\(name.rawValue)'") }
            springs[name] = SpringToken(stiffness: s.stiffness, damping: s.damping)
        }
        var kicks: [KickName: Double] = [:]
        for name in KickName.allCases {
            guard let k = file.kick[name.rawValue] else { throw AssetError.missing("motion.json has no kick '\(name.rawValue)'") }
            kicks[name] = k
        }
        return MotionTokens(
            bouncy: springs[.bouncy]!,
            soft: springs[.soft]!,
            fadeSeconds: file.fade.seconds,
            pressKick: file.press.kick,
            pressSquash: file.press.squash,
            pressBulge: file.press.bulge,
            pressHold: file.press.hold,
            staggerSeconds: file.stagger.seconds,
            idleBobMetres: file.idle.bobMetres,
            idleBobSeconds: file.idle.bobSeconds,
            springs: springs,
            kicks: kicks)
    }

    private struct File: Decodable {
        struct Spring: Decodable { let stiffness: Double; let damping: Double }
        struct Fade: Decodable { let seconds: Double }
        struct Press: Decodable { let kick: Double; let squash: Double; let bulge: Double; let hold: Double }
        struct Stagger: Decodable { let seconds: Double }
        struct Idle: Decodable { let bobMetres: Double; let bobSeconds: Double }
        let spring: [String: Spring]
        let fade: Fade
        let press: Press
        let stagger: Stagger
        let idle: Idle
        let kick: [String: Double]
    }
}

enum AssetError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self { case .missing(let what): "asset missing: \(what)" }
    }
}

/// A damped spring toward `target`, integrated with semi-implicit Euler in fixed 1/240 s substeps
/// — the same equations and step on both platforms, so a curve can be pinned by a golden vector.
struct Spring {
    static let step = 1.0 / 240.0
    let token: SpringToken
    private(set) var value: Double
    var velocity = 0.0
    var target: Double
    private var carry = 0.0

    init(_ token: SpringToken, initial: Double = 0) {
        self.token = token
        value = initial
        target = initial
    }

    mutating func kick(_ impulse: Double) { velocity += impulse }

    /// Jumps to `v` and stops there — Reduce Motion, or restarting a one-shot move.
    mutating func snap(to v: Double) {
        value = v
        target = v
        velocity = 0
        carry = 0
    }

    /// At rest on its target (to well below anything visible).
    var isSettled: Bool { abs(value - target) < 1e-3 && abs(velocity) < 1e-2 }

    mutating func advance(_ dt: Double) {
        carry += dt
        while carry >= Spring.step {
            let a = -token.stiffness * (value - target) - token.damping * velocity
            velocity += a * Spring.step
            value += velocity * Spring.step
            carry -= Spring.step
        }
    }
}
