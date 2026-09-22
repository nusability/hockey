import RealityKit

/// A card you can press: a slab with anything on its face — a club, a kit swatch, a world, a
/// formation, a drill, a text field. Touch-down sinks it, lifting springs it back and fires if the
/// finger is still on it; a selected tile lifts toward you in its highlight colour with a happy
/// wobble; a disabled one greys out and shakes its head. Children go on `content`, whose z = 0 is
/// the face. The twin of Android's Tile.kt.
@MainActor
final class Tile: Interactive, Presentable {
    let entity = Entity()
    let body = Entity()
    let content = Entity()
    private let slab: ModelEntity
    private let halo: ModelEntity?
    let size: SIMD2<Float>
    private(set) var semantics: Semantics
    var rest = Transform()
    var presence: Presence
    var action: () -> Void
    private let colour: Int
    private let selectedColour: Int
    private let motion: MotionTokens
    private var press: Spring
    private var lift: Spring
    private var nope: Jiggle
    private var held = false

    init(size: SIMD2<Float>, colour: Int, selectedColour: Int = DesignTokens.Colour.sun,
         depth: Float = DesignTokens.Size.slabDepth * 0.8, halo: Bool = false, id: String, label: String,
         entrance: Entrance = .pop, motion: MotionTokens, action: @escaping () -> Void) {
        self.size = size
        self.colour = colour
        self.selectedColour = selectedColour
        self.motion = motion
        self.action = action
        semantics = Semantics(id: id, label: label, trait: .button)
        presence = Presence(entrance, motion: motion)
        press = Spring(motion.bouncy)
        lift = Spring(motion.spring(.pop))
        nope = Jiggle(motion.spring(.wobbly))
        slab = Blocks.slab([size.x, size.y, depth], colour, corner: min(DesignTokens.Size.corner, size.y * 0.3))
        // A swatch keeps its own colour when chosen: a cream frame behind it says so instead.
        self.halo = halo ? Blocks.slab([size.x + 0.04, size.y + 0.04, depth * 0.6], DesignTokens.Colour.cream,
                                       corner: min(DesignTokens.Size.corner, size.y * 0.3)) : nil
        content.position.z = depth / 2
        entity.addChild(body)
        if let h = self.halo {
            h.position.z = -depth * 0.3
            h.isEnabled = false
            body.addChild(h)
        }
        body.addChild(slab)
        body.addChild(content)
        entity.isEnabled = false
    }

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            semantics.isSelected = isSelected
            paint()
            lift.target = isSelected ? 1 : 0
            if isSelected { nope.kick(twist: 0, swell: motion.kick(.celebrate) * 0.25) }
        }
    }

    var isEnabled: Bool {
        get { semantics.isEnabled }
        set {
            guard newValue != semantics.isEnabled else { return }
            semantics.isEnabled = newValue
            paint()
        }
    }

    func relabel(_ label: String) { semantics.label = label }

    private func paint() {
        Blocks.recolour(slab, !isEnabled ? DesignTokens.Colour.disabled : isSelected ? selectedColour : colour)
        halo?.isEnabled = isSelected
    }

    var boundsEntity: Entity { entity }
    var bounds: BoundingBox {
        let h = SIMD3(size.x / 2, size.y / 2, DesignTokens.Size.slabDepth / 2)
        return BoundingBox(min: -h, max: h)
    }
    var isPresent: Bool { presence.isSettledIn }

    func show(after delay: Double) { presence.show(after: delay) }
    func hide(after delay: Double) {
        held = false
        press.target = 0
        presence.hide(after: delay)
    }

    func touchDown(_ ray: TouchRay) {
        guard isEnabled else { nope.kick(twist: motion.kick(.nope), swell: 0); return }
        held = true
        press.target = motion.pressHold
        press.kick(motion.pressKick * 0.4)
    }

    func touchUp(_ ray: TouchRay, inside: Bool) {
        guard held else { return }
        held = false
        press.target = 0
        press.kick(-motion.pressKick * 0.5)
        if inside { action() }
    }

    func activate() {
        guard isEnabled else { nope.kick(twist: motion.kick(.nope), swell: 0); return }
        press.kick(motion.pressKick)
        action()
    }

    func update(_ dt: Double, _ ctx: UIContext) {
        presence.advance(dt, ctx)
        presence.apply(to: entity, rest: rest, reduceMotion: ctx.reduceMotion)
        guard entity.isEnabled else { return }
        if ctx.reduceMotion {
            press.snap(to: held ? motion.pressHold * 0.3 : 0)
            lift.snap(to: lift.target)
        } else {
            press.advance(dt)
            lift.advance(dt)
        }
        nope.advance(dt, reduceMotion: ctx.reduceMotion)
        let s = Float(press.value) * 0.5, l = Float(lift.value)
        let grow = (1 + 0.05 * l) * nope.scale
        body.scale = SIMD3(grow * (1 + 0.04 * s), grow * (1 - 0.1 * s), grow)
        body.position.z = 0.05 * l - 0.03 * max(0, s)
        body.orientation = nope.rotation
    }
}
