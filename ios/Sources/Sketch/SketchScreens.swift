import RealityKit

// THROWAWAY (SMASH-5): the motion sketch's screens, built only from the UI kit.

/// A screen of the sketch: where the camera stands for it and what arrives when it does.
@MainActor
class SketchScreen {
    let pose: CameraPose
    let stage: UIStage
    /// Everything that arrives, in arrival order.
    var parts: [Presentable] = []

    init(pose: CameraPose, stage: UIStage) {
        self.pose = pose
        self.stage = stage
    }

    @discardableResult
    func part<E: Presentable>(_ e: E, on parent: Entity) -> E {
        stage.add(e, to: parent)
        parts.append(e)
        return e
    }

    /// Arrivals, one after another on the stagger token.
    func show(after delay: Double) {
        let stagger = stage.motion.staggerSeconds * 1.6
        for (i, p) in parts.enumerated() { p.show(after: delay + Double(i) * stagger) }
    }

    /// Departures, quicker, last-in first-out.
    func hide() {
        let stagger = stage.motion.staggerSeconds * 0.5
        for (i, p) in parts.reversed().enumerated() { p.hide(after: Double(i) * stagger) }
    }

    func update(_ dt: Double) {}
}

private func at(_ x: Float, _ y: Float, z: Float = 0, tilt: Float = 0) -> Transform {
    Transform(scale: .one, rotation: simd_quatf(angle: tilt, axis: [0, 0, 1]), translation: [x, y, z])
}

typealias Go = @MainActor (SketchScreenID) -> Void

/// Title: the logo drops in letter by letter and keeps bobbing; Play bobs for the thumb;
/// Training is disabled (it shakes its head); Coach opens the board.
@MainActor
final class TitleScreen: SketchScreen {
    private(set) var play: BlockButton!
    private(set) var training: BlockButton!
    private(set) var coach: BlockButton!

    init(stage: UIStage, go: @escaping Go) {
        super.init(pose: CameraPose(eye: [0, 4.2, -22], target: [0, 6.2, 20]), stage: stage)
        let f = stage.frame(at: pose)
        let m = stage.motion
        let C = DesignTokens.Colour.self

        let smash = part(WaveText(L("title.logo.top"), height: 0.36, colour: C.sun, id: "title_logo_header", motion: m), on: f.entity)
        smash.rest = at(0, f.top - 0.45, tilt: 0.05)
        let hockey = part(WaveText(L("title.logo.bottom"), height: 0.30, colour: C.cream, bob: 0.7,
                                   id: "title_logo2_header", motion: m), on: f.entity)
        hockey.rest = at(-0.05, f.top - 0.90, tilt: 0.05)
        let badge = part(Panel(size: [0.42, 0.30, 0.12], colour: C.coral, entrance: .pop, motion: m), on: f.entity)
        badge.rest = at(0.62, f.top - 1.22, z: 0.05, tilt: -0.22)
        stage.add(Label3D("3D", height: 0.16, colour: C.cream, motion: m), to: badge.content).presence.show(after: 0)

        let tagline = part(Label3D(L("menu.tagline"), height: DesignTokens.Size.textSmall, colour: C.ink, maxWidth: 1.7,
                                   entrance: .tumble, motion: m), on: f.entity)
        tagline.rest = at(0, f.top - 1.55)

        let y0 = f.bottom + 1.25
        play = part(BlockButton(L("play.button"), id: "title_play_button", style: .primary,
                                size: [1.3, 0.38], textHeight: 0.15, motion: m) { go(.hub) }, on: f.entity)
        play.rest = at(0, y0)
        play.bobs = true
        training = part(BlockButton(L("title.training"), id: "title_training_button", style: .secondary,
                                    motion: m) {}, on: f.entity)
        training.rest = at(0, y0 - 0.46)
        training.isEnabled = false
        coach = part(BlockButton(L("title.coach"), id: "title_coach_button", style: .secondary,
                                 motion: m) { go(.coach) }, on: f.entity)
        coach.rest = at(0, y0 - 0.88)
        self.badge = badge
    }

    private var badge: Panel?

    override func show(after delay: Double) {
        super.show(after: delay)
        stage.after(delay + 1.0) { [weak self] in self?.badge?.celebrate(0.8) }
    }
}

/// Season hub: the next fixture in both kits, the league table, Play Match.
@MainActor
final class HubScreen: SketchScreen {
    private(set) var playMatch: BlockButton!
    private(set) var back: BlockButton!
    private var rows: [String: TableRow] = [:]
    private var rowY: [Float] = []
    private var standings = SketchData.before
    private var fixture: Panel?

    init(stage: UIStage, go: @escaping Go) {
        super.init(pose: CameraPose(eye: [-19, 10, -14], target: [2, 3, 8]), stage: stage)
        let f = stage.frame(at: pose)
        let m = stage.motion
        let C = DesignTokens.Colour.self
        let S = DesignTokens.Size.self

        let header = part(Label3D(L("hub.header"), height: 0.105, colour: C.cream, maxWidth: 1.7, entrance: .drop, motion: m), on: f.entity)
        header.rest = at(0, f.top - 0.14)

        // The fixture card: both clubs in their kits.
        let card = part(Panel(size: [1.72, 0.62, S.slabDepth], colour: C.cream, entrance: .tumble, motion: m), on: f.entity)
        card.rest = at(0, f.top - 0.62, tilt: -0.02)
        fixture = card
        let home = SketchData.clubs[SketchData.player]!, away = SketchData.clubs[SketchData.opponent]!
        for (club, x) in [(home, Float(-0.5)), (away, Float(0.5))] {
            let kit = stage.add(Panel(size: [0.56, 0.36, 0.08], colour: club.primary, entrance: .pop, motion: m), to: card.content)
            kit.rest = at(x, 0.05)
            kit.presence.show(after: 0)
            let stripe = Blocks.slab([0.1, 0.37, 0.085], club.secondary, corner: 0.01)
            stripe.position.x = -0.2
            kit.body.addChild(stripe)
            let code = stage.add(Label3D(club.code, height: 0.13, colour: club.secondary, maxWidth: 0.36, motion: m), to: kit.content)
            code.rest = at(0.05, 0)
            code.show(after: 0)
        }
        stage.add(Label3D(L("hub.vs"), height: 0.12, colour: C.coral, maxWidth: 0.36, motion: m), to: card.content).show(after: 0)
        let sub = stage.add(Label3D(L("hub.fixture"), height: S.textSmall, colour: C.ink, maxWidth: 1.6, motion: m), to: card.content)
        sub.rest = at(0, -0.225)
        sub.show(after: 0)

        // The table: a header line and eight rows that know how to re-rank.
        let cols: [TableRow.Column] = [.init(at: 0.05, align: .centre), .init(at: 0.20, align: .leading),
                                       .init(at: 0.62, align: .centre), .init(at: 0.76, align: .centre),
                                       .init(at: 0.91, align: .centre)]
        let width: Float = 1.72
        let top = f.top - 1.12
        let head = part(TableRow(["#", L("table.team"), L("table.played"), L("table.gd"), L("table.points")],
                                 columns: cols, size: [width, 0.09], id: "hub_table_header", colour: C.board,
                                 ink: C.cream, textHeight: S.textSmall, y: top, entrance: .tumble, motion: m), on: f.entity)
        _ = head
        let step = S.rowHeight + S.rowGap + 0.02
        rowY = (0..<8).map { top - 0.12 - Float($0) * step }
        for (i, s) in standings.enumerated() {
            let club = SketchData.clubs[s.code]!
            let mine = s.code == SketchData.player
            let row = part(TableRow(texts(i, s), columns: cols, size: [width, S.rowHeight + 0.02],
                                    id: "hub_table_row_\(s.code.lowercased())",
                                    colour: mine ? C.rowHighlight : (i % 2 == 0 ? C.rowLight : C.rowDark),
                                    kit: .init(primary: club.primary, secondary: club.secondary),
                                    y: rowY[i], entrance: .slide(fromLeft: i % 2 == 0), motion: m), on: f.entity)
            rows[s.code] = row
        }

        back = part(BlockButton(L("hub.back"), id: "hub_back_button", style: .quiet, size: [0.5, 0.3],
                                textHeight: 0.09, motion: m) { go(.title) }, on: f.entity)
        back.rest = at(-0.62, f.bottom + 0.34)
        playMatch = part(BlockButton(L("hub.play"), id: "hub_play_button", style: .primary, size: [1.1, 0.36],
                                     textHeight: 0.13, motion: m) { go(.match) }, on: f.entity)
        playMatch.rest = at(0.3, f.bottom + 0.34)
        playMatch.bobs = true
    }

    private func texts(_ i: Int, _ s: SketchStanding) -> [String] {
        ["\(i + 1)", s.code, "\(s.played)", s.goalDiff > 0 ? "+\(s.goalDiff)" : "\(s.goalDiff)", "\(s.points)"]
    }

    /// After the match: the next time the hub arrives, the rows land in their old places, take
    /// their new numbers and spring to their new ranks.
    func applyMatchday() { reshuffle = true }
    private var reshuffle = false

    override func show(after delay: Double) {
        super.show(after: delay)
        guard reshuffle else { return }
        reshuffle = false
        stage.after(delay + 2.2) { [weak self] in
            guard let self else { return }
            self.standings = SketchData.after
            for (i, s) in self.standings.enumerated() {
                guard let row = self.rows[s.code] else { continue }
                row.set(self.texts(i, s))
                row.move(toY: self.rowY[i])
                if s.code != SketchData.player {
                    row.recolour(i % 2 == 0 ? DesignTokens.Colour.rowLight : DesignTokens.Colour.rowDark)
                }
            }
            self.fixture?.celebrate(0.5)
        }
    }
}
