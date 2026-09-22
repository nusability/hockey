import RealityKit

/// A slab that things sit on: a fixture card, a scoreboard housing, the pause sign. It tumbles
/// (or pops, or drops) in, hops away on the way out, and jiggles when something happens to it.
/// Children go on `content`, whose z = 0 is the slab's front face.
@MainActor
final class Panel: Presentable {
    let entity = Entity()
    /// The panel's own wobble lives here; children move with it.
    let body = Entity()
    let content = Entity()
    let size: SIMD3<Float>
    var rest = Transform()
    var presence: Presence
    private var jiggle: Jiggle
    private let motion: MotionTokens

    init(size: SIMD3<Float>, colour: Int, entrance: Entrance = .tumble, corner: Float = DesignTokens.Size.corner,
         motion: MotionTokens) {
        self.size = size
        self.motion = motion
        presence = Presence(entrance, motion: motion)
        jiggle = Jiggle(motion.spring(.wobbly))
        let slab = Blocks.slab(size, colour, corner: corner)
        content.position.z = size.z / 2
        entity.addChild(body)
        body.addChild(slab)
        body.addChild(content)
        entity.isEnabled = false
    }

    func show(after delay: Double) { presence.show(after: delay) }
    func hide(after delay: Double) { presence.hide(after: delay) }
    var isSettledIn: Bool { presence.isSettledIn }

    /// A happy jelly wobble — a goal, a win. `strength` scales the celebrate kick.
    func celebrate(_ strength: Double = 1) {
        let k = motion.kick(.celebrate) * strength
        jiggle.kick(twist: k * 0.5, swell: k * 0.4)
    }

    /// A little thud — a flipped number landing on it.
    func thud() { jiggle.kick(twist: 0, swell: -motion.kick(.celebrate) * 0.15) }

    func update(_ dt: Double, _ ctx: UIContext) {
        let wasSettled = presence.isSettledIn
        presence.advance(dt, ctx)
        if !wasSettled, presence.isSettledIn { KitSound.pop() }         // it lands
        presence.apply(to: entity, rest: rest, reduceMotion: ctx.reduceMotion)
        guard entity.isEnabled else { return }
        jiggle.advance(dt, reduceMotion: ctx.reduceMotion)
        body.orientation = jiggle.rotation
        body.scale = SIMD3(repeating: jiggle.scale)
    }
}
