import RealityKit
import SmashCore

/// The season hub (spec §16.3): the next fixture in both kits with its round and world, and Play —
/// one tap to the face-off (A2); the league table with the player's row marked, or the cup bracket
/// with its results; and once the final is played, the season's end — champion, cup winner, the
/// player's place — and the next season. After a matchday the table's rows land where they stood
/// and hop to their new places. The twin of Android's HubScreen.kt.
@MainActor
final class HubScreen: Screen {
    private var tableParts: [Presentable] = []
    private var cupParts: [Presentable] = []
    private var tableTab: Tile!
    private var cupTab: Tile!
    private var showingCup = false
    private var card: Panel!
    /// The team detail standing in front of the table (§16.3a); nothing behind it takes a tap.
    private var detail: TeamDetailPanel?

    init(game: Game) {
        super.init(pose: CameraPose(Presentation.Screens.Hub.eye, Presentation.Screens.Hub.target), game: game)
        guard let career = game.save.career, let season = game.save.season else {
            preconditionFailure("the hub is reached only with a career and its season")
        }
        let m = motion
        let over = season.isFinished
        // Which season of the career this is (§15, §16.3), then the matchday.
        let header = L(.hubSeason, season.number) + " · " + (over ? L(.hubOver) : L(.hubHeader, season.matchday + 1, Season.plan.count))
        part(Label3D(header, height: 0.1, colour: C.paper, maxWidth: 1.7, entrance: .drop, motion: m), at: at(0, top - 0.14))
        card = part(Panel(size: [1.72, 0.74, S.slabDepth], colour: C.paper, entrance: .tumble, motion: m),
                    at: at(0, top - 0.62, tilt: -0.02))
        if over { seasonOver(career, season) } else if let f = game.save.playerFixture { fixture(career, season, f) }

        tableTab = part(tab(L(.hubTable), id: "hub_table_button") { [weak self] in self?.switchTo(cup: false) },
                        at: at(-0.3, top - 1.1))
        cupTab = part(tab(L(.hubCupTab), id: "hub_cup_button") { [weak self] in self?.switchTo(cup: true) },
                      at: at(0.3, top - 1.1))
        tableTab.isSelected = true
        table(career, season, top: top - 1.32)
        bracket(career, season, top: top - 1.38)

        part(BlockButton(L(.commonBack), id: "hub_back_button", style: .quiet, size: [0.5, 0.3], textHeight: 0.09, motion: m) {
            [weak game] in game?.go(.title)
        }, at: at(-0.62, bottom + 0.34))
        let go: BlockButton
        if over {
            go = BlockButton(L(.hubNextSeason), id: "hub_nextseason_button", style: .primary, size: [1.1, 0.36],
                             textHeight: 0.1, motion: m) { [weak game] in
                guard let game else { return }
                let seed = MatchPlan.seed()
                if game.commit({ try $0.startSeason(seed: seed) }) { game.go(.hub) }
            }
        } else {
            go = BlockButton(L(.hubPlay), id: "hub_play_button", style: .primary, size: [1.1, 0.36], textHeight: 0.13,
                             motion: m) { [weak game] in game?.play(.season) }
        }
        go.bobs = true
        part(go, at: at(0.3, bottom + 0.34))
    }

    private func tab(_ title: String, id: String, action: @escaping () -> Void) -> Tile {
        let t = Tile(size: [0.52, 0.18], colour: C.paper, selectedColour: C.green, id: id, label: title, motion: motion,
                     action: action)
        letters(title, height: 0.06, colour: C.ink, maxWidth: 0.46, at: [0, 0, 0], on: t.content)
        return t
    }

    // MARK: the card

    private func fixture(_ career: CareerRecord, _ season: SeasonRecord, _ f: Fixture) {
        for (team, x) in [(f.home, Float(-0.5)), (f.away, Float(0.5))] {
            let kit = career.kit(of: team)
            let chip = child(Panel(size: [0.56, 0.36, 0.08], colour: Int(kit.primary), entrance: .pop, motion: motion),
                             at: at(x, 0.11), on: card.content)
            chip.presence.show(after: 0)
            let stripe = Blocks.slab([0.1, 0.37, 0.085], Int(kit.secondary), corner: 0.01)
            stripe.position.x = -0.2
            chip.body.addChild(stripe)
            child(Label3D(career.short(of: team), height: 0.13, colour: Int(kit.secondary), maxWidth: 0.36, motion: motion),
                  at: at(0.05, 0), on: chip.content).show(after: 0)
            // Both clubs by their full names, not only their codes (§16.3).
            letters(Names.team(team, career), height: 0.048, colour: team == career.team ? C.pinkInk : C.ink,
                    maxWidth: 0.78, at: [x, -0.12, 0.01], on: card.content)
        }
        child(Label3D(L(.hubVs), height: 0.12, colour: C.pinkInk, maxWidth: 0.36, motion: motion), at: at(0, 0.11),
              on: card.content).show(after: 0)
        let step = Season.plan[season.matchday]
        let line = "\(Names.matchday(step)) · \(Names.world(career.homeWorld(of: f.home)))"
        child(Label3D(line, height: S.textSmall, colour: C.ink, maxWidth: 1.6, motion: motion), at: at(0, -0.28),
              on: card.content).show(after: 0)
    }

    private func seasonOver(_ career: CareerRecord, _ season: SeasonRecord) {
        let standings = season.table(career)
        let champion = standings[0].team
        let cupWinner = season.cupWinner ?? champion
        for (i, (label, team)) in [(L(.hubChampion), champion), (L(.hubCupWinner), cupWinner)].enumerated() {
            let y = 0.18 - Float(i) * 0.19
            letters(label, height: 0.045, colour: C.greenInk, maxWidth: 0.5, align: .leading, at: [-0.8, y, 0.01], on: card.content)
            let kit = career.kit(of: team)
            let chip = Blocks.slab([0.2, 0.13, 0.04], Int(kit.primary), corner: 0.02)
            chip.position = [-0.2, y, 0.02]
            card.content.addChild(chip)
            letters(career.short(of: team), height: 0.05, colour: Int(kit.secondary), maxWidth: 0.16, at: [-0.2, y, 0.04],
                    on: card.content)
            letters(Names.team(team, career), height: 0.055, colour: team == career.team ? C.pinkInk : C.ink, maxWidth: 0.66,
                    align: .leading, at: [-0.06, y, 0.01], on: card.content)
        }
        let place = (standings.firstIndex { $0.team == career.team } ?? 0) + 1
        letters(L(.hubPlace, Names.ordinal(place)), height: 0.06, colour: C.ink, maxWidth: 1.6, at: [0, -0.2, 0.01],
                on: card.content)
        if place == 1 || cupWinner == career.team {
            stage.after(1.2) { [weak self] in self?.card.celebrate(1.2) }
        }
    }

    // MARK: the table (§11.4)

    private func table(_ career: CareerRecord, _ season: SeasonRecord, top: Float) {
        let cols: [TableRow.Column] = [.init(at: 0.05, align: .centre), .init(at: 0.20, align: .leading),
                                       .init(at: 0.62, align: .centre), .init(at: 0.76, align: .centre),
                                       .init(at: 0.91, align: .centre)]
        let width: Float = 1.72
        let head = child(TableRow(["#", L(.tableTeam), L(.tablePlayed), L(.tableGd), L(.tablePoints)], columns: cols,
                                  size: [width, 0.09], id: "hub_table_header", colour: C.board, ink: C.paper,
                                  textHeight: S.textSmall, y: top, entrance: .tumble, motion: motion),
                         at: at(0, top), on: layer)
        tableParts.append(head)
        let step = S.rowHeight + S.rowGap + 0.02
        let rowY = (0..<8).map { top - 0.12 - Float($0) * step }
        let now = season.table(career)
        let before = game.tableBefore.flatMap { $0.count == now.count ? $0 : nil }
        game.tableBefore = nil
        func texts(_ i: Int, _ r: SmashCore.TableRow) -> [String] {
            ["\(i + 1)", career.short(of: r.team), "\(r.played)",
             r.goalDifference > 0 ? "+\(r.goalDifference)" : "\(r.goalDifference)", "\(r.points)"]
        }
        for (i, r) in now.enumerated() {
            let mine = r.team == career.team
            let kit = career.kit(of: r.team)
            let start = before?.firstIndex { $0.team == r.team } ?? i
            let shown = before?[start] ?? r
            let row = child(TableRow(texts(start, shown), columns: cols, size: [width, S.rowHeight + 0.02],
                                     id: "hub_table_row_\(r.team.rawValue)",
                                     colour: mine ? C.rowHighlight : (start % 2 == 0 ? C.rowLight : C.rowDark),
                                     kit: .init(primary: Int(kit.primary), secondary: Int(kit.secondary)),
                                     y: rowY[start], entrance: .slide(fromLeft: i % 2 == 0), motion: motion,
                                     hint: "\(Names.team(r.team, career)), \(L(.detailOpen))") { [weak self] in
                                         self?.openDetail(r.team)
                                     },
                            at: at(0, rowY[start]), on: layer)
            tableParts.append(row)
            guard before != nil else { continue }
            // Land in the old place with the old numbers, then take the new ones and hop over.
            stage.after(2.2) { [weak row] in
                guard let row else { return }
                row.set(texts(i, r))
                row.move(toY: rowY[i])
                if !mine { row.recolour(i % 2 == 0 ? C.rowLight : C.rowDark) }
            }
        }
    }

    // MARK: the cup (§11.1)

    private func bracket(_ career: CareerRecord, _ season: SeasonRecord, top: Float) {
        let rounds = CupRound.allCases
        let pitch: Float = 0.38
        for (c, round) in rounds.enumerated() {
            let count = 4 >> c
            let ties = season.cupTies(round)
            let x = -0.58 + Float(c) * 0.58
            cupParts.append(child(Label3D(Names.cupRound(round), height: 0.04, colour: C.paper, maxWidth: 0.54,
                                          entrance: .drop, motion: motion), at: at(x, top + 0.02), on: layer))
            for i in 0..<count {
                let span = Float(1 << c)
                let y = top - 0.2 - pitch * (Float(i) * span + (span - 1) / 2)
                let tie = child(Panel(size: [0.54, 0.3, 0.06], colour: C.paper, entrance: .pop, motion: motion),
                                at: at(x, y), on: layer)
                cupParts.append(tie)
                let f = i < ties.count ? ties[i] : nil
                for (line, team) in [f?.home, f?.away].enumerated() {
                    let ly: Float = line == 0 ? 0.065 : -0.065
                    let won = f.flatMap { SeasonRecord.winnerOf($0) } == team && team != nil
                    let ink = team == career.team ? C.pinkInk : (f?.score == nil || won ? C.ink : C.disabledInk)
                    letters(team.map { career.short(of: $0) } ?? "–", height: 0.05, colour: ink, align: .leading,
                            at: [-0.23, ly, 0.01], on: tie.content)
                    if let s = f?.score {
                        let goals = line == 0 ? s.home : s.away
                        letters(won && s.overtime ? "\(goals) \(L(.hudOt))" : "\(goals)", height: 0.05, colour: ink,
                                align: .trailing, at: [0.23, ly, 0.01], on: tie.content)
                    }
                }
            }
        }
    }

    // MARK: the team detail (§16.3a)

    /// Tapping a row tips its team's detail up in front of the table; the rows behind take no taps.
    private func openDetail(_ team: TeamKey) {
        guard detail == nil, let career = game.save.career, let season = game.save.season else { return }
        KitSound.sweep()
        detail = TeamDetailPanel(screen: self, team: team, career: career, season: season) { [weak game] in
            game?.go(.team(editing: true))
        } onClose: { [weak self] in
            self?.closeDetail()
        }
    }

    private func closeDetail() {
        detail?.leave()
        detail = nil
    }

    private func switchTo(cup: Bool) {
        guard cup != showingCup else { return }
        showingCup = cup
        tableTab.isSelected = !cup
        cupTab.isSelected = cup
        let stagger = motion.staggerSeconds
        for (i, p) in (cup ? tableParts : cupParts).enumerated() { p.hide(after: Double(i) * stagger * 0.3) }
        for (i, p) in (cup ? cupParts : tableParts).enumerated() { p.show(after: 0.25 + Double(i) * stagger * 0.6) }
    }

    override func show(after delay: Double) {
        super.show(after: delay)
        let stagger = motion.staggerSeconds * 1.6
        for (i, p) in (showingCup ? cupParts : tableParts).enumerated() { p.show(after: delay + 0.3 + Double(i) * stagger) }
    }

    override func leave() {
        for p in (detail?.parts ?? []) + tableParts + cupParts { p.hide(after: 0) }
        detail = nil
        super.leave()
    }
}

extension SeasonRecord {
    /// A played fixture's winner; nil when it is unplayed or level.
    static func winnerOf(_ f: Fixture) -> TeamKey? {
        guard let s = f.score, s.home != s.away else { return nil }
        return s.home > s.away ? f.home : f.away
    }
}
