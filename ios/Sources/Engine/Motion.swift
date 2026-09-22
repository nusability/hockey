import Foundation

/// The motion vocabulary (ADR 0005, `shared/data/motion.json`): named springs and fades that both
/// platforms read, integrated identically, so a bounce on iOS is the bounce on Android.
struct SpringToken: Sendable {
    let stiffness: Double
    let damping: Double
}

struct MotionTokens: Sendable {
    let bouncy: SpringToken
    let soft: SpringToken
    let fadeSeconds: Double
    let pressKick: Double
    let pressSquash: Double
    let pressBulge: Double

    static func load(bundle: Bundle = .main) throws -> MotionTokens {
        guard let url = bundle.url(forResource: "motion", withExtension: "json") else {
            throw AssetError.missing("motion.json — shared/data/motion.json is not in the app bundle")
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        func token(_ name: String) throws -> SpringToken {
            guard let s = file.spring[name] else { throw AssetError.missing("motion.json has no spring '\(name)'") }
            return SpringToken(stiffness: s.stiffness, damping: s.damping)
        }
        return MotionTokens(
            bouncy: try token("bouncy"),
            soft: try token("soft"),
            fadeSeconds: file.fade.seconds,
            pressKick: file.press.kick,
            pressSquash: file.press.squash,
            pressBulge: file.press.bulge)
    }

    private struct File: Decodable {
        struct Spring: Decodable { let stiffness: Double; let damping: Double }
        struct Fade: Decodable { let seconds: Double }
        struct Press: Decodable { let kick: Double; let squash: Double; let bulge: Double }
        let spring: [String: Spring]
        let fade: Fade
        let press: Press
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
