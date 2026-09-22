import RealityKit

/// Extruded lettering from the shared font (ADR 0005), placed by its centre, its left or its
/// right edge. Changing the text re-meshes through TextMesh's cache.
@MainActor
final class Label3D: Presentable {
    enum Align { case centre, leading, trailing }

    let entity = Entity()
    let body = Entity()
    private let model: ModelEntity
    private(set) var text: String
    let height: Float
    let align: Align
    var rest = Transform()
    var presence: Presence
    private var colour: Int
    /// Wider than this, the lettering shrinks to fit (a long German word in a short slot).
    let maxWidth: Float?

    init(_ text: String, height: Float, colour: Int, align: Align = .centre, maxWidth: Float? = nil,
         entrance: Entrance = .pop, motion: MotionTokens) {
        self.maxWidth = maxWidth
        self.text = text
        self.height = height
        self.align = align
        self.colour = colour
        presence = Presence(entrance, motion: motion)
        model = Blocks.text(text, height: height, colour)
        entity.addChild(body)
        body.addChild(model)
        realign()
        entity.isEnabled = false
    }

    var width: Float { Blocks.width(of: model) * body.scale.x }

    func set(_ newText: String) {
        guard newText != text else { return }
        text = newText
        Blocks.retext(model, newText, height: height)
        realign()
    }

    func show(after delay: Double) { presence.show(after: delay) }
    func hide(after delay: Double) { presence.hide(after: delay) }

    func setColour(_ rgb: Int) {
        guard rgb != colour else { return }
        colour = rgb
        Blocks.recolour(model, rgb)
    }

    private func realign() {
        let natural = Blocks.width(of: model)
        body.scale = SIMD3(repeating: maxWidth.map { natural > $0 ? $0 / natural : 1 } ?? 1)
        switch align {
        case .centre: body.position.x = 0
        case .leading: body.position.x = width / 2
        case .trailing: body.position.x = -width / 2
        }
    }

    func update(_ dt: Double, _ ctx: UIContext) {
        presence.advance(dt, ctx)
        presence.apply(to: entity, rest: rest, reduceMotion: ctx.reduceMotion)
    }
}

/// A word whose letters arrive one by one — each drops in, squashes, and then keeps bobbing on
/// a travelling wave. The title's logo; also "GOAL!" and "FULL TIME".
@MainActor
final class WaveText: Semantic, Presentable {
    let entity = Entity()
    var rest = Transform()
    let semantics: Semantics
    private var letters: [(node: Entity, model: ModelEntity, presence: Presence, x: Float)] = []
    private var shown = false
    private let bobScale: Float
    private let bounds_: BoundingBox
    private let stagger: Double

    private var fit: Float = 1

    init(_ text: String, height: Float, colour: Int, tracking: Float = 0.02, bob: Float = 1,
         maxWidth: Float = DesignTokens.Size.frameWidth - 0.1, id: String, motion: MotionTokens) {
        semantics = Semantics(id: id, label: text, trait: .header)
        bobScale = bob
        stagger = motion.staggerSeconds
        var x: Float = 0
        var parts: [(ModelEntity, Float)] = []
        for ch in text {
            let s = String(ch)
            if s == " " { x += height * 0.35; continue }
            let m = Blocks.text(s, height: height, colour)
            let w = Blocks.width(of: m)
            parts.append((m, x + w / 2))
            x += w + tracking
        }
        let total = x - tracking
        for (m, cx) in parts {
            let node = Entity()
            node.addChild(m)
            entity.addChild(node)
            letters.append((node, m, Presence(.drop, motion: motion), cx - total / 2))
        }
        bounds_ = BoundingBox(min: [-total / 2, -height * 0.6, 0], max: [total / 2, height * 0.6, height * 0.4])
        fit = total > maxWidth ? maxWidth / total : 1
        entity.isEnabled = false
    }

    var boundsEntity: Entity { entity }
    var bounds: BoundingBox { bounds_ }
    var isPresent: Bool { shown && (letters.last?.presence.isSettledIn ?? false) }

    func show(after delay: Double) {
        shown = true
        for i in letters.indices { letters[i].presence.show(after: delay + Double(i) * stagger) }
    }

    func hide(after delay: Double) {
        shown = false
        for i in letters.indices { letters[i].presence.hide(after: delay + Double(i) * stagger * 0.5) }
    }

    func update(_ dt: Double, _ ctx: UIContext) {
        let anyVisible = letters.contains { $0.presence.isVisible }
        if entity.isEnabled != anyVisible { entity.isEnabled = anyVisible }
        entity.transform = rest
        entity.scale *= fit
        guard anyVisible else { return }
        let period = ctx.motion.idleBobSeconds
        for i in letters.indices {
            letters[i].presence.advance(dt, ctx)
            var t = Transform()
            t.translation.x = letters[i].x
            if !ctx.reduceMotion {
                let phase = (ctx.time / period + Double(i) * 0.12) * 2 * .pi
                t.translation.y = Float(sin(phase)) * Float(ctx.motion.idleBobMetres) * 2 * bobScale
                t.rotation = simd_quatf(angle: Float(sin(phase + 1)) * 0.05 * bobScale, axis: [0, 0, 1])
            }
            letters[i].presence.apply(to: letters[i].node, rest: t, reduceMotion: ctx.reduceMotion)
        }
    }
}
