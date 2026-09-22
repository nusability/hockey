import RealityKit
import SmashCore
import simd

/// Running text in the world: the words wrapped greedily into lines no wider than `width`, one
/// extruded line each, stacked and centred on the element's origin. A drill's hint, a help card, the
/// refusal. VoiceOver reads it whole. The twin of Android's Paragraph.kt.
@MainActor
final class Paragraph: Semantic, Presentable {
    let entity = Entity()
    var rest = Transform()
    var presence: Presence
    let semantics: Semantics
    /// The height of the whole block, top of the first line to the bottom of the last.
    let blockHeight: Float
    private let width: Float

    init(_ text: String, height: Float, colour: Int, width: Float, align: Label3D.Align = .centre,
         lineSpacing: Float = 1.45, id: String, entrance: Entrance = .tumble, motion: MotionTokens) {
        self.width = width
        semantics = Semantics(id: id, label: text, trait: .staticText)
        presence = Presence(entrance, motion: motion)
        let lines = TextLayout.wrap(text, height: Double(height), width: Double(width))
        let step = height * lineSpacing
        blockHeight = height + step * Float(max(0, lines.count - 1))
        for (i, line) in lines.enumerated() {
            let m = Blocks.text(line, height: height, colour)
            let node = Entity()
            node.addChild(m)
            let w = Blocks.width(of: m)
            let fit = Float(TextLayout.fit(Double(w), Double(width)))
            node.scale = SIMD3(repeating: fit)
            let edge: Float = switch align {
            case .centre: 0
            case .leading: -width / 2
            case .trailing: width / 2
            }
            let x = edge + Float(TextLayout.alignX(align, width: Double(w * fit)))
            node.position = [x, blockHeight / 2 - height / 2 - Float(i) * step, 0]
            entity.addChild(node)
        }
        entity.isEnabled = false
    }

    var boundsEntity: Entity { entity }
    var bounds: BoundingBox {
        BoundingBox(min: [-width / 2, -blockHeight / 2, 0], max: [width / 2, blockHeight / 2, 0.02])
    }
    var isPresent: Bool { presence.isSettledIn }

    func show(after delay: Double) { presence.show(after: delay) }
    func hide(after delay: Double) { presence.hide(after: delay) }

    func update(_ dt: Double, _ ctx: UIContext) {
        presence.advance(dt, ctx)
        presence.apply(to: entity, rest: rest, reduceMotion: ctx.reduceMotion)
    }
}
