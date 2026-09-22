import RealityKit
import SmashCore
import UIKit

/// The match's minimal HUD (spec §8; the kit stream restyles it): score, clock and period at the
/// top, a pause button in the corner, and a banner for goals and results — extruded text parented to
/// the camera at a fixed depth (ADR 0005), laid out from the frustum and the
/// safe area. Toon-shaded by the world's light like everything else (ADR 0006). The twin of
/// Android's Hud.kt.
@MainActor
final class Hud {
    typealias H = Presentation.Hud
    let root = Entity()
    private let depth = Float(H.depth)
    private let halfHeight: Float
    private var aspect: Float = 0.46
    private var safeTop: Float = 0          // fraction of the view height
    private var safeBottom: Float = 0

    private var score: Entity?
    private var clock: Entity?
    private var paused: Entity?
    private var banner: Entity?
    private var bannerSpring: Spring
    private var bannerTime = 0.0
    private var codes: [Entity] = []
    private var pips: [ModelEntity] = []
    private let pipOn: RealityKit.Material
    private let pipOff: RealityKit.Material
    private let materials: Materials
    private let look: WorldLook
    let pauseButton: ModelEntity
    private var scoreText = "", clockText = ""
    private var period = 0

    init(motion: MotionTokens, codes teamCodes: [String]?, colours: [TeamColours], materials: Materials,
         look: WorldLook) throws {
        self.materials = materials
        self.look = look
        func ui(_ rgb: UInt32) throws -> RealityKit.Material { try materials.toon(rgb, look: look) }
        pipOn = try ui(H.clock)
        pipOff = try ui(0x6B7280)
        halfHeight = Float(H.depth) * tan(Float(Presentation.Camera.hudFov) / 2 * .pi / 180)
        bannerSpring = Spring(motion.bouncy)
        let size = Float(H.buttonSize)
        pauseButton = ModelEntity(mesh: .generateBox(width: size, height: size, depth: size * 0.4),
                                  materials: [try ui(H.button)])
        for x in [-size * 0.14, size * 0.14] {
            let bar = ModelEntity(mesh: .generateBox(width: size * 0.12, height: size * 0.5, depth: size * 0.1),
                                  materials: [try ui(H.buttonLabel)])
            bar.position = SIMD3(x, 0, size * 0.22)
            pauseButton.addChild(bar)
        }
        root.addChild(pauseButton)
        if let teamCodes {
            codes = try zip(teamCodes, colours).map { code, c in
                TextMesh.entity(code, height: Float(H.clockHeight), depth: 0.03, material: try ui(c.primary))
            }
            codes.forEach { root.addChild($0) }
            for _ in 0..<Tuning.Match.periods {
                let pip = ModelEntity(mesh: .generateBox(width: 0.07, height: 0.07, depth: 0.02), materials: [pipOff])
                pips.append(pip)
                root.addChild(pip)
            }
        }
        layout()
    }

    /// The view's shape and its safe area (in points), for the layout.
    func resize(width: Double, height: Double, safeTop top: Double, safeBottom bottom: Double) {
        aspect = Float(width / max(height, 1))
        safeTop = Float(top / max(height, 1))
        safeBottom = Float(bottom / max(height, 1))
        layout()
    }

    /// The HUD's colours: toon, lit by the world. A colour that fails to build falls back to flat.
    private func ui(_ rgb: UInt32) -> RealityKit.Material {
        (try? materials.toon(rgb, look: look)) ?? Materials.flat(rgb)
    }

    private var top: Float { halfHeight * (1 - 2 * safeTop) - halfHeight * Float(H.margin) }
    private var right: Float { halfHeight * aspect * (1 - Float(H.margin)) }

    private func layout() {
        let size = Float(H.buttonSize)
        pauseButton.position = SIMD3(right - size / 2, top - size / 2, -depth)
        score?.position = SIMD3(0, top - Float(H.scoreHeight) * 0.6, -depth)
        clock?.position = SIMD3(0, top - Float(H.scoreHeight) * 1.25 - Float(H.clockHeight) * 0.5, -depth)
        for (i, c) in codes.enumerated() {
            c.position = SIMD3((i == 0 ? -1 : 1) * 0.43, top - Float(H.scoreHeight) * 0.6, -depth)
        }
        for (i, p) in pips.enumerated() {
            p.position = SIMD3(Float(i - 1) * 0.11, top - Float(H.scoreHeight) * 1.25 - Float(H.clockHeight) * 1.7, -depth)
        }
        paused?.position = SIMD3(0, 0.25, -depth)
        banner?.position = SIMD3(0, halfHeight * 0.18, -depth)
    }

    /// Score, clock and period from the snapshot; a drill shows its goals against its target.
    func show(_ s: MatchSnapshot, drillGoals: Int?) {
        let text = drillGoals.map { "\(s.score[0]) / \($0)" } ?? "\(s.score[0]) : \(s.score[1])"
        if text != scoreText {
            scoreText = text
            score?.removeFromParent()
            score = TextMesh.entity(text, height: Float(H.scoreHeight), depth: 0.05, material: ui(H.text))
            root.addChild(score!)
        }
        let seconds = Int(s.clock.rounded(.up))
        let c = String(format: "%d:%02d", seconds / 60, seconds % 60)
        if c != clockText {
            clockText = c
            clock?.removeFromParent()
            clock = TextMesh.entity(c, height: Float(H.clockHeight), depth: 0.03, material: ui(H.clock))
            root.addChild(clock!)
        }
        if s.period != period {
            period = s.period
            for (i, p) in pips.enumerated() { p.model?.materials = [i < period ? pipOn : pipOff] }
        }
        layout()
    }

    /// A banner in the middle of the screen (a goal, a result, a drill's verdict); nil clears it.
    func raise(_ text: String?, colour: UInt32 = H.text, reduceMotion: Bool) {
        banner?.removeFromParent()
        banner = nil
        guard let text else { return }
        let b = TextMesh.entity(text, height: Float(H.bannerHeight), depth: 0.1, material: ui(colour))
        banner = b
        root.addChild(b)
        bannerTime = 0
        bannerSpring = Spring(bannerSpring.token, initial: reduceMotion ? 1 : 0)
        bannerSpring.target = 1
        layout()
    }

    func setPaused(_ on: Bool) {
        paused?.removeFromParent()
        paused = nil
        if on {
            let p = TextMesh.entity(String(localized: "pause.title"), height: Float(H.bannerHeight), depth: 0.1,
                                    material: ui(H.text))
            paused = p
            root.addChild(p)
        }
        layout()
    }

    /// Real time: the banner pops on its spring and leaves after a while.
    func advance(_ dt: Double, bannerSeconds: Double) {
        guard let b = banner else { return }
        bannerTime += dt
        if bannerTime > bannerSeconds { bannerSpring.target = 0 }
        bannerSpring.advance(dt)
        let s = Float(max(bannerSpring.value, 0))
        b.scale = SIMD3(repeating: s)
        if bannerTime > bannerSeconds && bannerSpring.value < 0.02 { raise(nil, reduceMotion: false) }
    }
}
