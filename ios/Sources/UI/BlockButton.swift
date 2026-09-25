import RealityKit
import SmashCore

/// A chunky toy key: a rounded cap sitting in a darker base. Touch-down squashes the cap and
/// holds it squashed; lifting lets it spring back through a stretch — and fires, if the finger is
/// still on it. A disabled button greys out and shakes its head ("nope") instead.
@MainActor
final class BlockButton: Interactive, Presentable {
    struct Style {
        let cap: Int
        let base: Int
        let ink: Int
        static let primary = Style(cap: DesignTokens.Colour.sun, base: DesignTokens.Colour.sunShade, ink: DesignTokens.Colour.ink)
        static let secondary = Style(cap: DesignTokens.Colour.green, base: DesignTokens.Colour.greenInk, ink: DesignTokens.Colour.ink)
        static let quiet = Style(cap: DesignTokens.Colour.paper, base: DesignTokens.Colour.paperShade, ink: DesignTokens.Colour.ink)
        static let danger = Style(cap: DesignTokens.Colour.pink, base: DesignTokens.Colour.pinkInk, ink: DesignTokens.Colour.ink)
        static let disabled = Style(cap: DesignTokens.Colour.disabled, base: DesignTokens.Colour.disabledShade, ink: DesignTokens.Colour.disabledInk)
    }

    let entity = Entity()
    private let body = Entity()
    private let cap: ModelEntity
    private let base: ModelEntity
    private var labels: [ModelEntity] = []
    private let labelNode = Entity()
    private let textHeight: Float
    let size: SIMD2<Float>
    private(set) var semantics: Semantics
    var rest = Transform()
    var presence: Presence
    var action: () -> Void
    /// A gentle idle bob — for the one button a screen wants the thumb on.
    var bobs = false
    private let style: Style
    private let motion: MotionTokens
    private var press: Spring
    private var nope: Jiggle
    private var held = false

    /// A key's face can be a caption or a drawn **glyph** — a symbol some keys say better than a
    /// word, built from the kit's own slabs like everything else in the scene (ADR 0005), with its
    /// proportions declared once in `shared/data/design.json` so both apps draw one icon.
    enum Glyph {
        /// Two upright bars. It replaces the caption "II", which was two Latin capital I's.
        case pause
    }

    init(_ title: String, id: String, label: String? = nil, style: Style = .primary, size: SIMD2<Float>? = nil,
         textHeight: Float = DesignTokens.Size.textButton, glyph: Glyph? = nil, entrance: Entrance = .drop,
         motion: MotionTokens, action: @escaping () -> Void) {
        var s = size ?? SIMD2(DesignTokens.Size.buttonWidth, DesignTokens.Size.buttonHeight)
        // A caption too wide for the cap wraps to two lines (§16.4) rather than shrinking to a
        // smear — and the key grows tall enough to hold them, so the words sit on it, not over it.
        let capHeight = Double(textHeight)
        // A glyph is drawn at the height it is given and never wraps, so it never grows the key.
        if glyph == nil {
            let room = TextLayout.room(slabWidth: Double(s.x), textHeight: capHeight)
            let lines = TextLayout.caption(title, height: capHeight, width: room)
            let needed: Double = TextLayout.stackHeight(lines.count, height: capHeight)
                + 2 * capHeight * TextLayout.marginPerHeight
            s.y = max(s.y, Float(needed))
        }
        self.size = s
        self.style = style
        self.motion = motion
        self.action = action
        semantics = Semantics(id: id, label: label ?? title, trait: .button)
        presence = Presence(entrance, motion: motion)
        press = Spring(motion.bouncy)
        nope = Jiggle(motion.spring(.wobbly))
        let d = DesignTokens.Size.buttonDepth
        let inset = DesignTokens.Size.buttonBaseInset
        base = Blocks.slab([s.x - 2 * inset, s.y - 2 * inset, d * 0.5], style.base)
        base.position.z = -d * 0.3
        cap = Blocks.slab([s.x, s.y, d], style.cap)
        self.textHeight = textHeight
        labelNode.position.z = d / 2
        entity.addChild(base)
        entity.addChild(body)
        body.addChild(cap)
        body.addChild(labelNode)
        if let glyph { draw(glyph) } else { letter(title) }
        entity.isEnabled = false
    }

    /// Draws a glyph on the cap instead of a caption. The shapes are the kit's rounded slabs, sized
    /// from the design tokens as fractions of the glyph's own height, so the icon scales with the
    /// key and is identical on both platforms.
    private func draw(_ glyph: Glyph) {
        typealias S = DesignTokens.Size
        for m in labels { m.parent?.removeFromParent() }
        labels = []
        let ink = isEnabled ? style.ink : Style.disabled.ink
        switch glyph {
        case .pause:
            let w = textHeight * S.pauseBarWidth
            let offset = (w + textHeight * S.pauseBarGap) / 2
            for side in [-1, 1] as [Float] {
                let bar = Blocks.slab([w, textHeight, textHeight * S.pauseBarDepth], ink,
                                      corner: textHeight * S.pauseBarCorner)
                bar.position.x = side * offset
                labelNode.addChild(bar)
                labels.append(bar)
            }
        }
    }

    /// Lays the caption out on the cap: at most two centred lines, a margin of lettering either
    /// side, and a shrink only when a line still has nowhere to break.
    private func letter(_ title: String) {
        for m in labels { m.parent?.removeFromParent() }
        labels = []
        let room = TextLayout.room(slabWidth: Double(size.x), textHeight: Double(textHeight))
        let lines = TextLayout.caption(title, height: Double(textHeight), width: room)
        for (i, line) in lines.enumerated() {
            let holder = Entity()
            holder.position.y = Float(TextLayout.stackY(i, of: lines.count, height: Double(textHeight)))
            let m = Blocks.text(line, height: textHeight, isEnabled ? style.ink : Style.disabled.ink)
            holder.addChild(m)
            labelNode.addChild(holder)
            labels.append(m)
        }
        let widest = TextLayout.widest(lines, height: Double(textHeight))
        labelNode.scale = SIMD3(repeating: Float(TextLayout.fit(widest, room)))
    }

    /// A new caption (and VoiceOver label). The key keeps the height it was built at, so a screen's
    /// row of buttons stays a row: a longer caption wraps and, if it must, shrinks within it.
    func retitle(_ title: String) {
        letter(title)
        semantics.label = title
    }

    var isEnabled: Bool {
        get { semantics.isEnabled }
        set {
            guard newValue != semantics.isEnabled else { return }
            semantics.isEnabled = newValue
            let s = newValue ? style : .disabled
            Blocks.recolour(cap, s.cap)
            Blocks.recolour(base, s.base)
            for m in labels { Blocks.recolour(m, s.ink) }
        }
    }

    var boundsEntity: Entity { entity }
    var bounds: BoundingBox {
        let h = SIMD3(size.x / 2, size.y / 2, DesignTokens.Size.buttonDepth / 2)
        return BoundingBox(min: -h - [0.02, 0.03, 0], max: h + [0.02, 0.03, 0])   // a little forgiving
    }
    var isPresent: Bool { presence.isSettledIn }

    func show(after delay: Double) { presence.show(after: delay) }
    func hide(after delay: Double) {
        held = false
        press.target = 0
        presence.hide(after: delay)
    }

    func touchDown(_ ray: TouchRay) {
        guard isEnabled else {
            nope.kick(twist: motion.kick(.nope), swell: 0)
            KitSound.nope()
            return
        }
        held = true
        press.target = motion.pressHold
        press.kick(motion.pressKick * 0.5)
        KitSound.press()
    }

    func touchUp(_ ray: TouchRay, inside: Bool) {
        guard held else { return }
        held = false
        press.target = 0
        press.kick(-motion.pressKick * 0.6)      // spring back through a stretch
        if inside { action() }
    }

    /// VoiceOver's activation, and the sketch's autoplay: the same squash and the same action.
    func activate() {
        guard isEnabled else { nope.kick(twist: motion.kick(.nope), swell: 0); KitSound.nope(); return }
        press.kick(motion.pressKick)
        KitSound.press()
        action()
    }

    func update(_ dt: Double, _ ctx: UIContext) {
        presence.advance(dt, ctx)
        var r = rest
        if bobs && !ctx.reduceMotion && presence.isSettledIn {
            let phase = ctx.time / ctx.motion.idleBobSeconds * 2 * .pi
            r.translation.y += Float(sin(phase)) * Float(ctx.motion.idleBobMetres)
            r.rotation = r.rotation * simd_quatf(angle: Float(sin(phase * 0.5)) * 0.03, axis: [0, 0, 1])
        }
        presence.apply(to: entity, rest: r, reduceMotion: ctx.reduceMotion)
        guard entity.isEnabled else { return }

        if ctx.reduceMotion {
            press.snap(to: held ? motion.pressHold * 0.3 : 0)    // a small, still dip while held
        } else {
            press.advance(dt)
        }
        nope.advance(dt, reduceMotion: ctx.reduceMotion)
        let s = Float(press.value)
        let bulge = 1 + Float(motion.pressBulge) * s
        body.scale = SIMD3(bulge, 1 - Float(motion.pressSquash) * s, bulge) * nope.scale
        body.position.z = -0.04 * max(0, s)
        body.orientation = nope.rotation
    }
}
