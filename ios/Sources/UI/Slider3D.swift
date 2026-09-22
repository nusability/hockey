import Foundation
import RealityKit

/// A puck on a rail, for the coach's board values 0–1. Grab it anywhere on the row and drag; the
/// puck chases the finger on the `bouncy` spring, leans into the direction it travels and
/// squashes while held. The fill behind it shows the value. VoiceOver adjusts it in steps.
/// With `stops`, the value clicks between that many evenly spaced positions (the board's period
/// length and ball spin, §12), and `format` writes the readout.
@MainActor
final class Slider3D: Interactive, Presentable {
    let entity = Entity()
    private let body = Entity()
    private let fill: ModelEntity
    private let puck = Entity()
    private let title: ModelEntity
    private let readout: ModelEntity
    private(set) var semantics: Semantics
    var rest = Transform()
    var presence: Presence
    private(set) var value: Double
    var onChange: ((Double) -> Void)?
    let length: Float
    private let step: Double
    private let stops: Int?
    private let format: (Double) -> String
    private var knob: Spring
    private var grab: Spring
    private var held = false
    private let motion: MotionTokens
    private let rowHeight: Float = 0.34

    init(_ title: String, id: String, value: Double, length: Float = 1.4, step: Double = 0.05, stops: Int? = nil,
         format: ((Double) -> String)? = nil, entrance: Entrance = .slide(fromLeft: true), motion: MotionTokens) {
        self.value = value
        self.length = length
        self.stops = stops
        self.step = stops.map { 1 / Double($0 - 1) } ?? step
        self.format = format ?? Self.percent
        self.motion = motion
        semantics = Semantics(id: id, label: title, value: self.format(value), trait: .adjustable)
        presence = Presence(entrance, motion: motion)
        knob = Spring(motion.bouncy, initial: value)
        grab = Spring(motion.bouncy)

        let railH = DesignTokens.Size.railHeight
        let rail = Blocks.slab([length + railH, railH, railH], DesignTokens.Colour.rail, corner: railH / 2)
        fill = Blocks.slab([1, railH * 1.25, railH * 1.25], DesignTokens.Colour.sun, corner: 0.0)
        let r = DesignTokens.Size.knobRadius
        let disc = Blocks.model(.generateCylinder(height: DesignTokens.Size.knobDepth, radius: r), DesignTokens.Colour.ink)
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        let cap = Blocks.model(.generateCylinder(height: DesignTokens.Size.knobDepth * 0.3, radius: r * 0.55), DesignTokens.Colour.cream)
        cap.orientation = disc.orientation
        cap.position.z = DesignTokens.Size.knobDepth * 0.5
        puck.addChild(disc)
        puck.addChild(cap)
        puck.position.z = railH

        self.title = Blocks.text(title, height: DesignTokens.Size.textBody, DesignTokens.Colour.cream)
        readout = Blocks.text(self.format(value), height: DesignTokens.Size.textBody, DesignTokens.Colour.sun)
        let titleNode = Entity(), readoutNode = Entity()
        titleNode.addChild(self.title)
        readoutNode.addChild(readout)
        titleNode.position = [-length / 2 + Blocks.width(of: self.title) / 2, 0.12, 0]
        readoutNode.position = [length / 2 - 0.12, 0.12, 0]

        entity.addChild(body)
        body.addChild(rail)
        body.addChild(fill)
        body.addChild(puck)
        body.addChild(titleNode)
        body.addChild(readoutNode)
        entity.isEnabled = false
    }

    private static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    var boundsEntity: Entity { entity }
    var bounds: BoundingBox {
        BoundingBox(min: [-length / 2 - 0.1, -rowHeight / 2 + 0.02, -0.1], max: [length / 2 + 0.1, rowHeight / 2, 0.15])
    }
    var isPresent: Bool { presence.isSettledIn }

    func show(after delay: Double) { presence.show(after: delay) }
    func hide(after delay: Double) { held = false; presence.hide(after: delay) }

    func set(_ v: Double, notify: Bool = true) {
        let c = min(1, max(0, v))
        let q = stops.map { n in (c * Double(n - 1)).rounded() / Double(n - 1) } ?? (c / 0.01).rounded() * 0.01
        guard q != value else { return }
        if notify, (q / step).rounded(.down) != (value / step).rounded(.down) { KitSound.step() }       // a step crossed
        value = q
        knob.target = q
        semantics.value = format(q)
        Blocks.retext(readout, format(q), height: DesignTokens.Size.textBody)
        if notify { onChange?(q) }
    }

    private func follow(_ ray: TouchRay) {
        guard let p = ray.onPlane else { return }   // the stage hands rays in our own space
        set(Double((p.x + length / 2) / length))
    }

    func touchDown(_ ray: TouchRay) {
        held = true
        grab.target = 1
        grab.kick(motion.kick(.grab))
        follow(ray)
    }

    func touchMoved(_ ray: TouchRay) { if held { follow(ray) } }

    func touchUp(_ ray: TouchRay, inside: Bool) {
        held = false
        grab.target = 0
    }

    func activate() { grab.kick(motion.kick(.grab)) }

    /// The stop the value sits on, with `stops`.
    var stopIndex: Int { Int((value * Double((stops ?? 101) - 1)).rounded()) }

    func adjust(by steps: Int) {
        set(((value + Double(steps) * step) / step).rounded() * step)
        grab.kick(motion.kick(.grab))
    }

    func update(_ dt: Double, _ ctx: UIContext) {
        presence.advance(dt, ctx)
        presence.apply(to: entity, rest: rest, reduceMotion: ctx.reduceMotion)
        guard entity.isEnabled else { return }
        if ctx.reduceMotion {
            knob.snap(to: value)
            grab.snap(to: held ? 1 : 0)
        } else {
            knob.advance(dt)
            grab.advance(dt)
        }
        let k = Float(min(1.08, max(-0.08, knob.value)))
        let x = -length / 2 + k * length
        puck.position.x = x
        let g = Float(grab.value)
        // Lean into the travel, squash while held.
        let lean = Float(max(-0.5, min(0.5, knob.velocity * 0.12)))
        puck.orientation = simd_quatf(angle: -lean, axis: [0, 0, 1])
        puck.scale = SIMD3(1 + 0.25 * g, 1 + 0.25 * g, 1 - 0.3 * g)
        let w = max(0.001, x + length / 2)
        fill.scale.x = w
        fill.position.x = -length / 2 + w / 2
    }
}
