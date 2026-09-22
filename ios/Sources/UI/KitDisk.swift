import Foundation
import RealityKit
import SmashCore

/// A player as the pitch draws it (ADR 0006) — a squat disk in the kit's primary with a dot of the
/// secondary on top — standing in a menu, tipped toward the viewer and turning slowly. The create
/// screen's live preview (§16.1) and, with `ball`, the how-to-play card's teacher (§16.8): a ball
/// circling it at the orbit's pace and an aim line that turns pink toward the goal (up) and green
/// toward a team-mate (right), white otherwise (§5.2). The twin of Android's KitDisk.kt.
@MainActor
final class KitDisk: Presentable {
    let entity = Entity()
    var rest = Transform()
    var presence: Presence
    private let spinner = Entity()
    private let bodyModel: ModelEntity
    private let dot: ModelEntity
    private let ball: ModelEntity?
    private let aim: ModelEntity?
    private let radius: Float
    private var spin: Float = 0
    private var orbit = 0.0
    private var aimColour = -1

    init(radius: Float, primary: Int, secondary: Int, ball withBall: Bool = false, motion: MotionTokens) {
        self.radius = radius
        presence = Presence(.pop, motion: motion)
        let height = radius * Float(Presentation.Player.height / Tuning.Player.outfieldRadius)
        bodyModel = Blocks.model(.generateCylinder(height: height, radius: radius), primary)
        bodyModel.position.y = height / 2
        dot = Blocks.model(.generateCylinder(height: height * 0.12, radius: radius * Float(Presentation.Player.dot)), secondary)
        dot.position.y = height + height * 0.06
        spinner.addChild(bodyModel)
        spinner.addChild(dot)
        let tilt = Entity()
        tilt.orientation = simd_quatf(angle: 0.95, axis: [1, 0, 0])
        tilt.position.y = -height / 2
        tilt.addChild(spinner)
        entity.addChild(tilt)
        if withBall {
            let b = Blocks.model(.generateSphere(radius: radius * 0.4), Int(Presentation.Ball.field))
            let line = Blocks.slab([radius * 0.18, radius * 0.05, 1], Int(Presentation.Aim.free), corner: 0)
            b.position.y = height * 0.5
            line.position.y = height * 0.5
            tilt.addChild(b)
            tilt.addChild(line)
            ball = b
            aim = line
        } else {
            ball = nil
            aim = nil
        }
        entity.isEnabled = false
    }

    func recolour(primary: Int, secondary: Int) {
        Blocks.recolour(bodyModel, primary)
        Blocks.recolour(dot, secondary)
    }

    func show(after delay: Double) { presence.show(after: delay) }
    func hide(after delay: Double) { presence.hide(after: delay) }

    func update(_ dt: Double, _ ctx: UIContext) {
        presence.advance(dt, ctx)
        presence.apply(to: entity, rest: rest, reduceMotion: ctx.reduceMotion)
        guard entity.isEnabled else { return }
        if !ctx.reduceMotion { spin += Float(dt) * 0.5 }
        spinner.orientation = simd_quatf(angle: spin, axis: [0, 1, 0])
        guard let ball, let aim else { return }
        orbit += dt * 2 * .pi / Tuning.Orbit.demoPeriod
        if orbit > .pi { orbit -= 2 * .pi }
        let r = radius * Float(Tuning.Orbit.radius / Tuning.Player.outfieldRadius)
        let dir = SIMD3<Float>(Float(sin(orbit)), 0, -Float(cos(orbit)))
        ball.position = SIMD3(dir.x * r, ball.position.y, dir.z * r)
        let length = r * 1.6
        aim.position = SIMD3(dir.x * (r + length / 2), aim.position.y, dir.z * (r + length / 2))
        aim.orientation = simd_quatf(angle: Float(-orbit), axis: [0, 1, 0])
        aim.scale = SIMD3(1, 1, length)
        // Up the card is the goal; to the right a team-mate (§5.2's colours).
        let kind = abs(orbit) < 0.4 ? 1 : abs(orbit - .pi / 2) < 0.36 ? 0 : 2
        if kind != aimColour {
            aimColour = kind
            Blocks.recolour(aim, Int([Presentation.Aim.pass, Presentation.Aim.shot, Presentation.Aim.free][kind]))
        }
    }
}
