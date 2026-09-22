import RealityKit

/// One flip card: a dark tile with a character on each face. A change writes the new character
/// on the hidden face and turns the card half a revolution about its horizontal axis, top edge
/// falling toward the viewer like a split-flap, on the `snappy` spring — so it clacks a little
/// past the stop and settles.
@MainActor
private final class FlipCard {
    let entity = Entity()
    private let faces: [ModelEntity]
    private var turn: Spring
    private var flips = 0
    private(set) var shown: Character
    private var queued: Character?
    private let textHeight: Float
    var onLanded: (() -> Void)?

    init(_ c: Character, size: SIMD2<Float>, depth: Float, textHeight: Float, cardColour: Int, ink: Int, motion: MotionTokens) {
        shown = c
        self.textHeight = textHeight
        turn = Spring(motion.spring(.snappy))
        let tile = Blocks.slab([size.x, size.y, depth], cardColour, corner: min(size.x, size.y) * 0.12)
        entity.addChild(tile)
        let front = Blocks.text(String(c), height: textHeight, ink)
        let back = Blocks.text(String(c), height: textHeight, ink)
        let frontNode = Entity(), backNode = Entity()
        frontNode.position.z = depth / 2
        backNode.position.z = -depth / 2
        // Upside down on the back: after half a turn about X it reads the right way up.
        backNode.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        frontNode.addChild(front)
        backNode.addChild(back)
        entity.addChild(frontNode)
        entity.addChild(backNode)
        // A hairline across the middle, the split-flap's split.
        let split = Blocks.slab([size.x * 1.001, size.y * 0.025, depth * 1.02], DesignTokens.Colour.board, corner: 0)
        entity.addChild(split)
        faces = [front, back]
    }

    func set(_ c: Character) {
        if flipping { queued = c; return }
        guard c != shown else { return }
        start(c)
    }

    private var flipping: Bool { abs(turn.value - turn.target) > 0.35 }

    private func start(_ c: Character) {
        flips += 1
        Blocks.retext(faces[flips % 2], String(c), height: textHeight)
        shown = c
        turn.target = Double(flips) * .pi
        KitSound.flip()
    }

    func update(_ dt: Double, reduceMotion: Bool) {
        let wasFlipping = flipping
        if reduceMotion { turn.snap(to: turn.target) } else { turn.advance(dt) }
        entity.orientation = simd_quatf(angle: Float(turn.value), axis: [1, 0, 0])
        if wasFlipping && !flipping { onLanded?() }
        if !flipping, let q = queued {
            queued = nil
            if q != shown { start(q) }
        }
    }
}

/// A scoreboard number or clock whose characters flip like split-flap tiles when they change.
/// Separators (":", "-", " ") are fixed lettering between the cards.
@MainActor
final class FlipDigits: Semantic, Presentable {
    let entity = Entity()
    let body = Entity()
    var rest = Transform()
    var presence: Presence
    private(set) var semantics: Semantics
    private var cards: [FlipCard?] = []
    private var text: String
    private var jiggle: Jiggle
    private let motion: MotionTokens
    private let bounds_: BoundingBox
    /// Called when any card lands — a housing can thud with it.
    var onLanded: (() -> Void)?

    /// `cardSize` is one tile; the text height follows it.
    init(_ initial: String, cardSize: SIMD2<Float>, id: String, label: String,
         cardColour: Int = DesignTokens.Colour.card, ink: Int = DesignTokens.Colour.cardInk,
         entrance: Entrance = .pop, motion: MotionTokens) {
        text = initial
        self.motion = motion
        semantics = Semantics(id: id, label: label, value: initial, trait: .staticText)
        presence = Presence(entrance, motion: motion)
        jiggle = Jiggle(motion.spring(.wobbly))
        let depth = cardSize.x * 0.35
        let textHeight = cardSize.y * 0.62
        let gap = cardSize.x * 0.08
        let sepWidth = cardSize.x * 0.45
        var widths: [Float] = []
        for c in initial { widths.append(Self.isSeparator(c) ? sepWidth : cardSize.x) }
        let total = widths.reduce(0, +) + gap * Float(max(0, widths.count - 1))
        var x = -total / 2
        entity.addChild(body)
        for (i, c) in initial.enumerated() {
            let cx = x + widths[i] / 2
            if Self.isSeparator(c) {
                let sep = Blocks.text(String(c), height: textHeight * 0.8, ink)
                let node = Entity()
                node.position = [cx, 0, 0]
                node.addChild(sep)
                body.addChild(node)
                cards.append(nil)
            } else {
                let card = FlipCard(c, size: cardSize, depth: depth, textHeight: textHeight,
                                    cardColour: cardColour, ink: ink, motion: motion)
                card.entity.position = [cx, 0, 0]
                body.addChild(card.entity)
                cards.append(card)
            }
            x += widths[i] + gap
        }
        bounds_ = BoundingBox(min: [-total / 2, -cardSize.y / 2, -depth / 2], max: [total / 2, cardSize.y / 2, depth / 2])
        for case let card? in cards { card.onLanded = { [weak self] in self?.landed() } }
        entity.isEnabled = false
    }

    private static func isSeparator(_ c: Character) -> Bool { c == ":" || c == "-" || c == " " || c == "." || c == "/" }

    var boundsEntity: Entity { entity }
    var bounds: BoundingBox { bounds_ }
    var isPresent: Bool { presence.isSettledIn }
    var width: Float { bounds_.extents.x }

    func show(after delay: Double) { presence.show(after: delay) }
    func hide(after delay: Double) { presence.hide(after: delay) }

    /// Shows `newText` (same length and separators as the initial text); changed cards flip.
    func set(_ newText: String) {
        precondition(newText.count == text.count, "FlipDigits keeps its layout: '\(newText)' vs '\(text)'")
        guard newText != text else { return }
        text = newText
        semantics.value = newText
        for (card, c) in zip(cards, newText) { card?.set(c) }
    }

    /// The celebratory wobble — a goal.
    func celebrate() {
        let k = motion.kick(.celebrate)
        jiggle.kick(twist: k * 0.4, swell: k * 0.6)
    }

    private func landed() {
        jiggle.kick(twist: 0, swell: -motion.kick(.celebrate) * 0.08)
        onLanded?()
    }

    func update(_ dt: Double, _ ctx: UIContext) {
        presence.advance(dt, ctx)
        presence.apply(to: entity, rest: rest, reduceMotion: ctx.reduceMotion)
        guard entity.isEnabled else { return }
        for case let card? in cards { card.update(dt, reduceMotion: ctx.reduceMotion) }
        jiggle.advance(dt, reduceMotion: ctx.reduceMotion)
        body.orientation = jiggle.rotation
        body.scale = SIMD3(repeating: jiggle.scale)
    }
}
