import RealityKit
import SmashCore

/// Extruded lettering from the shared font (ADR 0005), placed by its centre, its left or its
/// right edge. Changing the text re-meshes through TextMesh's cache.
///
/// A caption wider than `maxWidth` **wraps to two centred lines** before it is allowed to shrink
/// (spec §16.4, core `TextLayout.caption`): a long German label stays legible rather than being
/// squeezed to a smear. Only a caption with nowhere to break — one long word — still shrinks.
@MainActor
final class Label3D: Presentable {
    /// The core's three alignments, so the kit and both platforms name the same thing.
    typealias Align = TextLayout.Align

    let entity = Entity()
    let body = Entity()
    private var models: [ModelEntity] = []
    private(set) var text: String
    let height: Float
    let align: Align
    var rest = Transform()
    var presence: Presence
    private var colour: Int
    /// Wider than this, the lettering wraps to two lines, and only then shrinks to fit.
    let maxWidth: Float?
    /// The widest line's layout width, before `body`'s shrink.
    private var natural: Float = 0

    init(_ text: String, height: Float, colour: Int, align: Align = .centre, maxWidth: Float? = nil,
         entrance: Entrance = .pop, motion: MotionTokens) {
        self.maxWidth = maxWidth
        self.text = text
        self.height = height
        self.align = align
        self.colour = colour
        presence = Presence(entrance, motion: motion)
        entity.addChild(body)
        reletter()
        entity.isEnabled = false
    }

    var width: Float { natural * body.scale.x }

    func set(_ newText: String) {
        guard newText != text else { return }
        text = newText
        reletter()
    }

    func show(after delay: Double) { presence.show(after: delay) }
    func hide(after delay: Double) { presence.hide(after: delay) }

    func setColour(_ rgb: Int) {
        guard rgb != colour else { return }
        colour = rgb
        for m in models { Blocks.recolour(m, rgb) }
    }

    /// Re-meshes the caption, wrapped to at most two lines, and re-aligns the block.
    private func reletter() {
        for m in models { m.parent?.removeFromParent() }
        models = []
        let lines = maxWidth.map { TextLayout.caption(text, height: Double(height), width: Double($0)) } ?? [text]
        for (i, line) in lines.enumerated() {
            let holder = Entity()
            holder.position.y = Float(TextLayout.stackY(i, of: lines.count, height: Double(height)))
            let m = Blocks.text(line, height: height, colour)
            holder.addChild(m)
            body.addChild(holder)
            models.append(m)
        }
        natural = Float(TextLayout.widest(lines, height: Double(height)))
        body.scale = SIMD3(repeating: Float(TextLayout.fit(Double(natural), maxWidth.map(Double.init))))
        body.position.x = Float(TextLayout.alignX(align, width: Double(width)))
    }

    func update(_ dt: Double, _ ctx: UIContext) {
        presence.advance(dt, ctx)
        presence.apply(to: entity, rest: rest, reduceMotion: ctx.reduceMotion)
    }
}

/// A word whose letters arrive one by one — each drops in, squashes, and then keeps bobbing on
/// a travelling wave. The title's logo; also "GOAL!" and "FULL TIME".
///
/// A banner too wide for the frame **wraps to two centred lines** (spec §16.4, core
/// `TextLayout.caption`) — "END OF PERIOD 1" and "ENDE 1. DRITTEL" break in the same place on both
/// phones — and only shrinks when there is nowhere to break.
@MainActor
final class WaveText: Semantic, Presentable {
    let entity = Entity()
    var rest = Transform()
    let semantics: Semantics
    private var letters: [(node: Entity, model: ModelEntity, presence: Presence, x: Float, y: Float)] = []
    private var shown = false
    private let bobScale: Float
    private let bounds_: BoundingBox
    private let stagger: Double

    private var fit: Float = 1

    init(_ text: String, height: Float, colour: Int, tracking: Float = 0.02, bob: Float = 1,
         maxWidth: Float = DesignTokens.Size.frameWidth - 0.1, entrance: Entrance = .drop, id: String, motion: MotionTokens) {
        semantics = Semantics(id: id, label: text, trait: .header)
        bobScale = bob
        stagger = motion.staggerSeconds
        let lines = TextLayout.caption(text, height: Double(height), width: Double(maxWidth))
        var parts: [(ModelEntity, Float, Float)] = []
        var total: Float = 0
        for (index, line) in lines.enumerated() {
            var x: Float = 0
            var row: [(ModelEntity, Float)] = []
            for ch in line {
                let s = String(ch)
                if s == " " { x += height * 0.35; continue }
                let m = Blocks.text(s, height: height, colour)
                let w = Blocks.width(of: m)
                row.append((m, x + w / 2))
                x += w + tracking
            }
            let lineWidth = max(0, x - tracking)
            total = max(total, lineWidth)
            let y = Float(TextLayout.stackY(index, of: lines.count, height: Double(height)))
            for (m, cx) in row { parts.append((m, cx - lineWidth / 2, y)) }
        }
        for (m, cx, cy) in parts {
            let node = Entity()
            node.addChild(m)
            entity.addChild(node)
            letters.append((node, m, Presence(entrance, motion: motion), cx, cy))
        }
        let halfHeight = max(height * 0.6, Float(TextLayout.stackHeight(lines.count, height: Double(height))) / 2)
        bounds_ = BoundingBox(min: [-total / 2, -halfHeight, 0], max: [total / 2, halfHeight, height * 0.4])
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
            t.translation.y = letters[i].y
            if !ctx.reduceMotion {
                let phase = (ctx.time / period + Double(i) * 0.12) * 2 * .pi
                t.translation.y += Float(sin(phase)) * Float(ctx.motion.idleBobMetres) * 2 * bobScale
                t.rotation = simd_quatf(angle: Float(sin(phase + 1)) * 0.05 * bobScale, axis: [0, 0, 1])
            }
            letters[i].presence.apply(to: letters[i].node, rest: t, reduceMotion: ctx.reduceMotion)
        }
    }
}
