import RealityKit
import SmashCore

/// A team's detail (spec §16.3a) — **a screen of its own**, reached by tapping its row in the
/// league table: the hub's title, fixture card, table and buttons leave, the camera swoops here,
/// and Back swoops back. Nothing of the hub is left standing behind it, so there is one screen's
/// worth of controls on screen and the panel's edges are never in doubt.
///
/// It shows the full name over the kit, where the team stands, what it has played, won, drawn and
/// lost, its goals, its last three matches as a form strip and the fixture it plays next. The
/// player's own team also gets the way to change its name and kit (§16.1). The panel is built to
/// its content by `CardLayout`: its buttons sit inside its width, below the last line, and a club
/// name that wraps makes the panel taller rather than pushing the keys over the words.
/// The twin of Android's TeamDetail.kt.
@MainActor
final class DetailScreen: Screen {
    /// The panel's width in the design frame; its height follows what it carries.
    private static let cardWidth = 1.66

    init(game: Game, team: TeamKey) {
        super.init(pose: CameraPose(Presentation.Screens.Detail.eye, Presentation.Screens.Detail.target), game: game)
        guard let career = game.save.career, let season = game.save.season else {
            preconditionFailure("a team's detail is reached only from the season hub")
        }
        let m = motion
        let d = season.detail(of: team, career: career)
        let mine = team == career.team
        let kit = career.kit(of: team)
        let room = CardLayout.inner(width: Self.cardWidth)

        // What the panel says, in the order it says it — each line measured before anything is
        // built, so the panel can be made exactly tall enough to hold all of it (§16.3a).
        let r = d.row
        let name = Names.team(team, career)
        let nameRoom = room - 0.4
        let place = L(.detailPlace, Names.ordinal(d.position), r.points)
        let played = L(.detailPlayed, r.played)
        let record = L(.detailRecord, r.won, r.drawn, r.lost)
        let gd = r.goalDifference > 0 ? "+\(r.goalDifference)" : "\(r.goalDifference)"
        let goals = "\(L(.detailGoals, r.goalsFor, r.goalsAgainst)) · \(L(.tableGd)) \(gd)"
        let formRoom = room - 0.55
        let forms = d.form.map { Self.formLine($0, career: career) }
        let next = Self.next(d, career: career, team: team)

        var heights: [Double] = [
            max(0.22, CardLayout.blockHeight(name, height: 0.085, room: nameRoom)),
            CardLayout.blockHeight(place, height: 0.055, room: room),
            max(CardLayout.blockHeight(played, height: 0.045, room: 0.5),
                CardLayout.blockHeight(record, height: 0.045, room: 0.9)),
            CardLayout.blockHeight(goals, height: 0.045, room: room),
            CardLayout.blockHeight(L(.detailForm), height: 0.045, room: room),
        ]
        if forms.isEmpty {
            heights.append(CardLayout.blockHeight(L(.detailNone), height: 0.05, room: room))
        } else {
            heights += forms.map { max(0.15, CardLayout.blockHeight($0.line, height: 0.05, room: formRoom)) }
        }
        heights.append(CardLayout.blockHeight(L(.detailNext), height: 0.045, room: room))
        heights.append(CardLayout.blockHeight(next, height: 0.05, room: room))

        var keys = [CardLayout.Button(text: L(.commonBack), textHeight: 0.08, minWidth: 0.5, minHeight: 0.3)]
        if mine {
            keys.append(CardLayout.Button(text: L(.teamEditButton), textHeight: 0.1, minWidth: 0.7, minHeight: 0.34))
        }
        let card = CardLayout(width: Self.cardWidth, blocks: heights, buttons: keys)

        let panel = part(Panel(size: [Float(card.width), Float(card.height), 0.14], colour: C.paper, entrance: .tumble,
                               motion: m),
                         at: at(0, (top + bottom) / 2))
        let face = panel.content
        let left = Float(card.left), right = Float(card.right)
        var laid = 0
        func nextY() -> Float {
            defer { laid += 1 }
            return Float(card.blocks[laid].centreY)
        }

        // The team: its kit, its code, and — the point of the screen — its full name (§16.3, "3").
        var y = nextY()
        let chip = Blocks.slab([0.34, 0.22, 0.05], Int(kit.primary), corner: 0.03)
        chip.position = [left + 0.17, y, 0.02]
        face.addChild(chip)
        letters(career.short(of: team), height: 0.09, colour: Int(kit.secondary), maxWidth: 0.3,
                at: [left + 0.17, y, 0.05], on: face)
        letters(name, height: 0.085, colour: mine ? C.pinkInk : C.ink, maxWidth: Float(nameRoom), align: .leading,
                at: [left + 0.4, y, 0.01], on: face)

        y = nextY()
        letters(place, height: 0.055, colour: C.greenInk, maxWidth: Float(room), align: .leading, at: [left, y, 0.01], on: face)
        y = nextY()
        letters(played, height: 0.045, colour: C.ink, maxWidth: 0.5, align: .leading, at: [left, y, 0.01], on: face)
        letters(record, height: 0.045, colour: C.ink, maxWidth: 0.9, align: .trailing, at: [right, y, 0.01], on: face)
        y = nextY()
        letters(goals, height: 0.045, colour: C.ink, maxWidth: Float(room), align: .leading, at: [left, y, 0.01], on: face)

        // The form strip: the last three, most recent first, fewer early in a season (§16.3a).
        y = nextY()
        letters(L(.detailForm), height: 0.045, colour: C.greenInk, maxWidth: Float(room), align: .leading,
                at: [left, y, 0.01], on: face)
        if forms.isEmpty {
            y = nextY()
            letters(L(.detailNone), height: 0.05, colour: C.disabledInk, maxWidth: Float(room), at: [0, y, 0.01], on: face)
        }
        for f in forms {
            y = nextY()
            let badge = Blocks.slab([0.13, 0.13, 0.04], f.colour, corner: 0.03)
            badge.position = [left + 0.065, y, 0.02]
            face.addChild(badge)
            letters(f.badge, height: 0.06, colour: C.ink, maxWidth: 0.11, at: [left + 0.065, y, 0.05], on: face)
            letters(f.line, height: 0.05, colour: C.ink, maxWidth: Float(formRoom), align: .leading,
                    at: [left + 0.15, y, 0.01], on: face)
            letters(f.score, height: 0.06, colour: C.ink, maxWidth: 0.34, align: .trailing, at: [right, y, 0.01], on: face)
        }

        y = nextY()
        letters(L(.detailNext), height: 0.045, colour: C.greenInk, maxWidth: Float(room), align: .leading,
                at: [left, y, 0.01], on: face)
        y = nextY()
        letters(next, height: 0.05, colour: C.ink, maxWidth: Float(room), align: .leading, at: [left, y, 0.01], on: face)

        // The screen's own two controls, inside the panel and below everything it says.
        let back = card.buttons[0]
        part(BlockButton(L(.commonBack), id: "detail_back_button", style: .quiet,
                         size: [Float(back.width), Float(back.height)], textHeight: 0.08, motion: m) { [weak game] in
            game?.go(.hub)
        }, at: at(Float(back.centreX), Float(back.centreY)), on: face)
        if mine, card.buttons.count > 1 {
            let box = card.buttons[1]
            let edit = BlockButton(L(.teamEditButton), id: "detail_edit_button", style: .primary,
                                   size: [Float(box.width), Float(box.height)], textHeight: 0.1, motion: m) { [weak game] in
                game?.go(.team(editing: true))
            }
            edit.bobs = true
            part(edit, at: at(Float(box.centreX), Float(box.centreY)), on: face)
        }
    }

    /// One match of the form strip: won, drawn or lost as a coloured badge, where it was played,
    /// the opponent's full name, and the score.
    private static func formLine(_ f: FormMatch, career: CareerRecord) -> (colour: Int, badge: String, line: String, score: String) {
        let colour = f.kind == .won ? C.green : f.kind == .drawn ? C.sun : C.pink
        let venue = L(f.home ? .detailHome : .detailAway)
        let cup = f.cup ? " · \(L(.hubCupTab))" : ""
        let ot = f.overtime ? " \(L(.hudOt))" : ""
        return (colour, L(kindKey(f.kind)), "\(venue) \(Names.team(f.opponent, career))\(cup)",
                "\(f.goalsFor):\(f.goalsAgainst)\(ot)")
    }

    /// The fixture the team plays next, in words: where, against whom, in which round.
    private static func next(_ d: TeamDetail, career: CareerRecord, team: TeamKey) -> String {
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
}
