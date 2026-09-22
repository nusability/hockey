import RealityKit
import SmashCore

/// One row of a table — a league table line, a list entry. A slab with cells of lettering laid
/// out by column, an optional kit chip, and a slot it springs to: re-rank the table and the rows
/// hop past each other into their new places.
@MainActor
final class TableRow: Semantic, Presentable {
    struct Column {
        /// The column's centre, as a share of the row width from its left edge (0…1).
        let at: Float
        let align: Label3D.Align
    }

    struct Kit { let primary: Int; let secondary: Int }

    let entity = Entity()
    private let body = Entity()
    private let slab: ModelEntity
    private var cells: [ModelEntity] = []
    private var cellNodes: [Entity] = []
    private let columns: [Column]
    let size: SIMD2<Float>
    var rest = Transform()
    var presence: Presence
    private(set) var semantics: Semantics
    private var slot: Spring
    private var hop: Jiggle
    private let textHeight: Float
    private let motion: MotionTokens

    init(_ texts: [String], columns: [Column], size: SIMD2<Float>, id: String,
         colour: Int, ink: Int = DesignTokens.Colour.ink, kit: Kit? = nil, kitAt: Float = 0.13,
         textHeight: Float = DesignTokens.Size.textBody, y: Float = 0,
         entrance: Entrance = .slide(fromLeft: true), motion: MotionTokens) {
        precondition(texts.count == columns.count, "one text per column")
        self.columns = columns
        self.size = size
        self.textHeight = textHeight
        self.motion = motion
        presence = Presence(entrance, motion: motion)
        slot = Spring(motion.spring(.pop), initial: Double(y))
        hop = Jiggle(motion.spring(.wobbly))
        semantics = Semantics(id: id, label: texts.joined(separator: ", "), trait: .staticText)
        let depth = DesignTokens.Size.slabDepth * 0.6
        slab = Blocks.slab([size.x, size.y, depth], colour, corner: size.y * 0.3)
        entity.addChild(body)
        body.addChild(slab)
        for (text, col) in zip(texts, columns) {
            let m = Blocks.text(text, height: textHeight, ink)
            let node = Entity()
            node.addChild(m)
            node.position.z = depth / 2
            body.addChild(node)
            cells.append(m)
            cellNodes.append(node)
            place(node, m, col)
        }
        if let kit {
            let chip = Entity()
            let shirt = Blocks.slab([size.y * 0.62, size.y * 0.62, depth * 0.8], kit.primary, corner: size.y * 0.12)
            let stripe = Blocks.slab([size.y * 0.2, size.y * 0.64, depth * 0.84], kit.secondary, corner: 0.005)
            chip.addChild(shirt)
            chip.addChild(stripe)
            chip.position = [-size.x / 2 + kitAt * size.x, 0, depth / 2]
            body.addChild(chip)
        }
        rest.translation.y = y
        entity.isEnabled = false
    }

    private func place(_ node: Entity, _ m: ModelEntity, _ col: Column) {
        let cx = -size.x / 2 + col.at * size.x
        let w = Blocks.width(of: m)
        switch col.align {
        case .centre: node.position.x = cx
        case .leading: node.position.x = cx + w / 2
        case .trailing: node.position.x = cx - w / 2
        }
    }

    var boundsEntity: Entity { entity }
    var bounds: BoundingBox {
        BoundingBox(min: [-size.x / 2, -size.y / 2, -0.03], max: [size.x / 2, size.y / 2, 0.03])
    }
    var isPresent: Bool { presence.isSettledIn }

    func show(after delay: Double) { presence.show(after: delay) }
    func hide(after delay: Double) { presence.hide(after: delay) }

    func set(_ texts: [String]) {
        for i in cells.indices where i < texts.count {
            Blocks.retext(cells[i], texts[i], height: textHeight)
            place(cellNodes[i], cells[i], columns[i])
        }
        semantics.label = texts.joined(separator: ", ")
    }

    func recolour(_ rgb: Int) { Blocks.recolour(slab, rgb) }

    /// Springs to a new vertical slot, with a hop if it moved.
    func move(toY y: Float) {
        guard abs(Double(y) - slot.target) > 0.001 else { return }
        let up = Double(y) > slot.target
        slot.target = Double(y)
        hop.kick(twist: (up ? 1 : -1) * motion.kick(.celebrate) * 0.25, swell: motion.kick(.celebrate) * 0.2)
    }

    func update(_ dt: Double, _ ctx: UIContext) {
        if ctx.reduceMotion { slot.snap(to: slot.target) } else { slot.advance(dt) }
        rest.translation.y = Float(slot.value)
        // A row climbing the table comes forward to pass over the others; a falling one ducks back.
        rest.translation.z = Float(max(-0.08, min(0.12, (slot.target - slot.value) * 0.5)))
        presence.advance(dt, ctx)
        presence.apply(to: entity, rest: rest, reduceMotion: ctx.reduceMotion)
        guard entity.isEnabled else { return }
        hop.advance(dt, reduceMotion: ctx.reduceMotion)
        body.orientation = hop.rotation
        body.scale = SIMD3(repeating: hop.scale)
    }
}
