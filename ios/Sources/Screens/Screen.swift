import RealityKit
import SmashCore

/// A screen of §16: where the camera stands for it and what arrives when it does — built fresh
/// from the save each time it is entered, so it never shows stale numbers, and taken apart once
/// its parts have hopped away. A menu stands in the world at its camera pose; the match HUD hangs
/// from the camera (ADR 0005). The twin of Android's Screen.kt.
@MainActor
class Screen {
    let pose: CameraPose
    unowned let game: Game
    var stage: UIStage { game.stage }
    var motion: MotionTokens { game.stage.motion }
    /// Everything of this screen hangs under here; removing it removes the screen.
    let layer = Entity()
    let top: Float
    let bottom: Float
    /// Everything that arrives with the screen, in arrival order.
    private(set) var parts: [Presentable] = []

    /// A menu standing in the world at `pose`.
    init(pose: CameraPose, game: Game) {
        self.pose = pose
        self.game = game
        let frame = game.stage.frame(at: pose)
        frame.entity.addChild(layer)
        top = frame.top
        bottom = frame.bottom
    }

    /// A layer on the camera-parented HUD rig (the match).
    init(hudOf game: Game) {
        pose = game.stage.rig.pose
        self.game = game
        game.stage.hud.entity.addChild(layer)
        top = game.stage.hud.top
        bottom = game.stage.hud.bottom
    }

    /// Adds `e` to the stage under `parent` (the screen's layer by default) as one of the parts that
    /// arrive and leave with the screen.
    @discardableResult
    func part<E: Presentable>(_ e: E, at rest: Transform, on parent: Entity? = nil) -> E {
        stage.add(e, to: parent ?? layer)
        e.rest = rest
        parts.append(e)
        return e
    }

    /// Adds `e` to the stage under `parent` without making it one of the arrivals — a child that
    /// rides on a part, or something the screen shows and hides itself.
    @discardableResult
    func child<E: UIElement>(_ e: E, at rest: Transform = Transform(), on parent: Entity) -> E {
        stage.add(e, to: parent)
        if let p = e as? Presentable { p.rest = rest }
        return e
    }

    /// Fixed lettering on a part: centred on `p` (or starting / ending there), shrunk to `maxWidth`.
    @discardableResult
    func letters(_ text: String, height: Float, colour: Int, maxWidth: Float? = nil, align: Label3D.Align = .centre,
                 at p: SIMD3<Float>, on parent: Entity) -> Entity {
        let node = Entity()
        parent.addChild(node)
        Screen.place(node, text, height: height, colour: colour, maxWidth: maxWidth, align: align, at: p)
        return node
    }

    /// Re-letters what `letters` made.
    func reletter(_ node: Entity, _ text: String, height: Float, colour: Int, maxWidth: Float? = nil,
                  align: Label3D.Align = .centre, at p: SIMD3<Float>) {
        Screen.place(node, text, height: height, colour: colour, maxWidth: maxWidth, align: align, at: p)
    }

    /// Lettering on a slab: at most two centred lines when it is given a width to stay inside
    /// (§16), and a shrink only when a line still has nowhere to break.
    private static func place(_ node: Entity, _ text: String, height: Float, colour: Int, maxWidth: Float?,
                              align: Label3D.Align, at p: SIMD3<Float>) {
        for child in node.children.map({ $0 }) { child.removeFromParent() }
        let room = maxWidth.map(Double.init)
        let lines = room.map { TextLayout.caption(text, height: Double(height), width: $0) } ?? [text]
        for (i, line) in lines.enumerated() {
            let holder = Entity()
            holder.position.y = Float(TextLayout.stackY(i, of: lines.count, height: Double(height)))
            holder.addChild(Blocks.text(line, height: height, colour))
            node.addChild(holder)
        }
        let w = TextLayout.widest(lines, height: Double(height))
        let k = Float(TextLayout.fit(w, room))
        node.scale = SIMD3(repeating: k)
        node.position = p + SIMD3(Float(TextLayout.alignX(align, width: w * Double(k))), 0, 0)
    }

    /// Arrivals, one after another on the stagger token.
    func show(after delay: Double) {
        let stagger = motion.staggerSeconds * 1.6
        for (i, p) in parts.enumerated() { p.show(after: delay + Double(i) * stagger) }
    }

    /// Departures, quicker, last-in first-out; the layer goes once they are gone.
    func leave() {
        let stagger = motion.staggerSeconds * 0.5
        for (i, p) in parts.reversed().enumerated() { p.hide(after: Double(i) * stagger) }
        let layer = self.layer
        stage.after(Presentation.Screens.leaveSeconds) { [weak stage] in stage?.remove(under: layer) }
    }

    /// Real time, every frame, while the screen is current.
    func update(_ dt: Double) {}
}

/// A rest pose in a screen's layout: at (x, y, z), tilted by `tilt` radians about Z.
func at(_ x: Float, _ y: Float, z: Float = 0, tilt: Float = 0) -> Transform {
    Transform(scale: .one, rotation: simd_quatf(angle: tilt, axis: [0, 0, 1]), translation: [x, y, z])
}

typealias C = DesignTokens.Colour
typealias S = DesignTokens.Size
