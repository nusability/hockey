import RealityKit
import SmashCore

/// A team's detail behind its row in the league table (spec §16.3a): the full name over its kit,
/// where it stands, what it has played, won, drawn and lost, its goals, its last three matches as
/// a form strip and the fixture it plays next. The player's own team also gets the way to change
/// its name and kit (§16.1). It tips up in front of the hub like the drills' intro card and is
/// dismissed the same way. The twin of Android's TeamDetail.kt.
@MainActor
final class TeamDetailPanel {
    private(set) var parts: [Presentable] = []
    private unowned let screen: Screen
    private let panel: Panel

    init(screen: Screen, team: TeamKey, career: CareerRecord, season: SeasonRecord, onEdit: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        self.screen = screen
        let m = screen.motion
        let d = season.detail(of: team, career: career)
        let mine = team == career.team
        let kit = career.kit(of: team)
        panel = screen.child(Panel(size: [1.66, 1.62, 0.14], colour: C.paper, entrance: .tumble, motion: m),
                             at: at(0, 0.02, z: 0.5), on: screen.layer)
        parts.append(panel)
        let face = panel.content

        // The team: its kit, its code, and — the point of the screen — its full name (§16.3, "3").
        let chip = Blocks.slab([0.34, 0.22, 0.05], Int(kit.primary), corner: 0.03)
        chip.position = [-0.61, 0.66, 0.02]
        face.addChild(chip)
        screen.letters(career.short(of: team), height: 0.09, colour: Int(kit.secondary), maxWidth: 0.3,
                       at: [-0.61, 0.66, 0.05], on: face)
        screen.letters(Names.team(team, career), height: 0.085, colour: mine ? C.pinkInk : C.ink, maxWidth: 1.0,
                       align: .leading, at: [-0.4, 0.66, 0.01], on: face)

        let r = d.row
        screen.letters(L(.detailPlace, Names.ordinal(d.position), r.points), height: 0.055, colour: C.greenInk,
                       maxWidth: 1.44, align: .leading, at: [-0.76, 0.48, 0.01], on: face)
        screen.letters(L(.detailPlayed, r.played), height: 0.045, colour: C.ink, maxWidth: 0.5, align: .leading,
                       at: [-0.76, 0.37, 0.01], on: face)
        screen.letters(L(.detailRecord, r.won, r.drawn, r.lost), height: 0.045, colour: C.ink, maxWidth: 0.9,
                       align: .trailing, at: [0.76, 0.37, 0.01], on: face)
        let gd = r.goalDifference > 0 ? "+\(r.goalDifference)" : "\(r.goalDifference)"
        screen.letters("\(L(.detailGoals, r.goalsFor, r.goalsAgainst)) · \(L(.tableGd)) \(gd)", height: 0.045,
                       colour: C.ink, maxWidth: 1.44, align: .leading, at: [-0.76, 0.26, 0.01], on: face)

        // The form strip: the last three, most recent first, fewer early in a season (§16.3a).
        screen.letters(L(.detailForm), height: 0.045, colour: C.greenInk, maxWidth: 0.9, align: .leading,
                       at: [-0.76, 0.13, 0.01], on: face)
        if d.form.isEmpty {
            screen.letters(L(.detailNone), height: 0.05, colour: C.disabledInk, maxWidth: 1.44, at: [0, -0.04, 0.01], on: face)
        }
        for (i, f) in d.form.enumerated() {
            row(f, career: career, y: 0.02 - Float(i) * 0.16, on: face)
        }

        screen.letters(L(.detailNext), height: 0.045, colour: C.greenInk, maxWidth: 0.9, align: .leading,
                       at: [-0.76, -0.46, 0.01], on: face)
        screen.letters(next(d, career: career, team: team), height: 0.05, colour: C.ink, maxWidth: 1.44,
                       align: .leading, at: [-0.76, -0.57, 0.01], on: face)

        let close = screen.child(BlockButton(L(.commonBack), id: "hub_detail_close_button", style: .quiet,
                                             size: [0.56, 0.28], textHeight: 0.08, motion: m, action: onClose),
                                 at: at(mine ? -0.46 : 0, -0.72), on: face)
        parts.append(close)
        if mine {
            let edit = screen.child(BlockButton(L(.teamEditButton), id: "hub_detail_edit_button", style: .primary,
                                                size: [0.86, 0.3], textHeight: 0.1, motion: m, action: onEdit),
                                    at: at(0.36, -0.72), on: face)
            parts.append(edit)
        }
        for (i, p) in parts.enumerated() { p.show(after: Double(i) * m.staggerSeconds * 3) }
    }

    /// One match of the form strip: won, drawn or lost as a coloured badge, where it was played,
    /// the opponent's full name, and the score.
    private func row(_ f: FormMatch, career: CareerRecord, y: Float, on face: Entity) {
        let colour = f.kind == .won ? C.green : f.kind == .drawn ? C.sun : C.pink
        let badge = Blocks.slab([0.13, 0.13, 0.04], colour, corner: 0.03)
        badge.position = [-0.7, y, 0.02]
        face.addChild(badge)
        screen.letters(L(Self.kindKey(f.kind)), height: 0.06, colour: C.ink, maxWidth: 0.11, at: [-0.7, y, 0.05], on: face)
        let venue = L(f.home ? .detailHome : .detailAway)
        let cup = f.cup ? " · \(L(.hubCupTab))" : ""
        screen.letters("\(venue) \(Names.team(f.opponent, career))\(cup)", height: 0.05, colour: C.ink, maxWidth: 1.0,
                       align: .leading, at: [-0.58, y, 0.01], on: face)
        let ot = f.overtime ? " \(L(.hudOt))" : ""
        screen.letters("\(f.goalsFor):\(f.goalsAgainst)\(ot)", height: 0.06, colour: C.ink, maxWidth: 0.34,
                       align: .trailing, at: [0.76, y, 0.01], on: face)
    }

    /// The fixture the team plays next, in words: where, against whom, in which round.
    private func next(_ d: TeamDetail, career: CareerRecord, team: TeamKey) -> String {
        guard let f = d.next else { return L(.detailNoNext) }
        let home = f.home == team
        let other = home ? f.away : f.home
        return "\(L(home ? .detailHome : .detailAway)) \(Names.team(other, career)) · \(Names.matchday(Season.plan[f.matchday]))"
    }

    static func kindKey(_ k: FormKind) -> CopyKey {
        switch k {
        case .won: .detailWon
        case .drawn: .detailDrawn
        case .lost: .detailLost
        }
    }

    /// Hops away and takes its parts off the stage — the way the drills' intro card is dismissed.
    func leave() {
        for p in parts.reversed() { p.hide(after: 0) }
        let entity = panel.entity
        screen.stage.after(0.9) { [weak screen] in screen?.stage.remove(under: entity) }
    }
}
