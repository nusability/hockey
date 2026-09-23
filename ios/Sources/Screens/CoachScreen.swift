import Foundation
import RealityKit
import SmashCore

/// The coach's board (spec §16.7, §12): pressing, covering, push up and discipline on sliders, the
/// five formations drawn as disks on little pitches, period length and ball spin as stepped
/// sliders, and Reset. Every change is the save's at once (§15). The twin of Android's
/// CoachScreen.kt.
@MainActor
final class CoachScreen: Screen {
    private var sliders: [Slider3D] = []
    private var period: Slider3D!
    private var spin: Slider3D!
    private var formations: [Formation: Tile] = [:]
    private var board: Panel!

    init(game: Game) {
        super.init(pose: CameraPose(Presentation.Screens.Coach.eye, Presentation.Screens.Coach.target), game: game)
        let m = motion
        let b = game.save.board
        part(WaveText(L(.coachTitle), height: 0.16, colour: C.paper, bob: 0.6, id: "coach_title_header", motion: m),
             at: at(0, top - 0.22))
        board = part(Panel(size: [1.76, 1.4, 0.12], colour: C.chalk, entrance: .tumble, motion: m), at: at(0, top - 1.05))
        let tactics: [(CopyKey, String, Double)] = [(.coachPressing, "coach_pressing_field", b.pressing),
                                                    (.coachCovering, "coach_covering_field", b.covering),
                                                    (.coachPushUp, "coach_pushup_field", b.pushUp),
                                                    (.coachDiscipline, "coach_discipline_field", b.discipline)]
        for (i, (key, id, value)) in tactics.enumerated() {
            let s = part(Slider3D(L(key), id: id, value: value, length: 1.4, entrance: .slide(fromLeft: i % 2 == 0), motion: m),
                         at: at(0, 0.5 - Float(i) * 0.33, z: 0.02), on: board.content)
            s.onChange = { [weak self] _ in self?.changed() }
            sliders.append(s)
        }

        part(Label3D(L(.coachFormation), height: 0.045, colour: C.paper, align: .leading, motion: m), at: at(-0.86, top - 1.88))
        for (i, f) in Formation.allCases.enumerated() {
            let t = part(pitch(f), at: at(-0.72 + Float(i) * 0.36, top - 2.14))
            t.isSelected = f == b.formation
            formations[f] = t
        }

        let periods = Tuning.Board.periodSeconds, spins = Tuning.Board.ballSpinSeconds
        period = part(Slider3D(L(.coachPeriod), id: "coach_period_field", value: Self.share(b.periodSeconds, periods),
                               length: 1.4, stops: periods.count, format: { L(.coachSeconds, Int(Self.pick($0, periods))) },
                               motion: m), at: at(0, top - 2.5))
        spin = part(Slider3D(L(.coachSpin), id: "coach_spin_field", value: Self.share(b.ballSpinSeconds, spins),
                             length: 1.4, stops: spins.count,
                             format: { L(.coachSeconds, String(format: "%.1f", Self.pick($0, spins))) },
                             entrance: .slide(fromLeft: false), motion: m), at: at(0, top - 2.82))
        period.onChange = { [weak self] _ in self?.changed() }
        spin.onChange = { [weak self] _ in self?.changed() }

        // The board is where the player tunes their own team, so it is also where they change its
        // name and kit (§16.1, §16.7) — one tap from the title.
        let team = game.save.career != nil
        let wide: Float = team ? 0.56 : 0.78
        part(BlockButton(L(.coachReset), id: "coach_reset_button", style: .quiet, size: [wide, 0.32], textHeight: 0.1,
                         motion: m) { [weak self] in self?.reset() }, at: at(team ? -0.6 : -0.46, bottom + 0.3))
        if team {
            part(BlockButton(L(.teamEditButton), id: "coach_team_button", style: .secondary, size: [wide, 0.32],
                             textHeight: 0.09, motion: m) { [weak game] in game?.go(.team(editing: true)) },
                 at: at(0, bottom + 0.3))
        }
        part(BlockButton(L(.commonBack), id: "coach_back_button", style: .primary, size: [wide, 0.32], textHeight: 0.1,
                         motion: m) { [weak game] in game.map { $0.go($0.home) } }, at: at(team ? 0.6 : 0.46, bottom + 0.3))
    }

    /// A choice's place along its stepped slider (0…1), and back.
    static func share(_ v: Double, _ choices: [Double]) -> Double {
        Double(choices.firstIndex(of: v) ?? 0) / Double(choices.count - 1)
    }

    static func pick(_ share: Double, _ choices: [Double]) -> Double {
        choices[min(max(Int((share * Double(choices.count - 1)).rounded()), 0), choices.count - 1)]
    }

    /// A formation as its six disks on a little pitch, attacking up (§3).
    private func pitch(_ f: Formation) -> Tile {
        let t = Tile(size: [0.32, 0.4], colour: C.rail, selectedColour: C.green, id: "coach_formation_\(f.rawValue)_button",
                     label: L(f.nameKey), motion: motion) { [weak self] in self?.choose(f) }
        let line = Blocks.slab([0.28, 0.006, 0.01], C.chalk, corner: 0)
        line.position = [0, 0.03, 0.005]
        t.content.addChild(line)
        func disk(_ spot: Spot, _ rgb: Int) {
            let d = Blocks.model(.generateCylinder(height: 0.02, radius: 0.022), rgb)
            d.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            d.position = [Float(spot.x / 15) * 0.13, 0.03 + Float(spot.z / 28) * 0.15, 0.012]
            t.content.addChild(d)
        }
        disk(Formation.goalie, C.ink)
        for p in f.players { disk(p.spot, p.role == .defender ? C.paper : C.sun) }
        let name = L(f.nameKey).split(separator: " ").first.map(String.init) ?? ""
        letters(name, height: 0.034, colour: C.paper, maxWidth: 0.28, at: [0, -0.16, 0.01], on: t.content)
        return t
    }

    private func choose(_ f: Formation) {
        for (k, t) in formations { t.isSelected = k == f }
        changed(formation: f)
    }

    /// Everything on the board, as it stands, into the save (§12, §15).
    private func changed(formation: Formation? = nil) {
        var b = game.save.board
        b.pressing = sliders[0].value
        b.covering = sliders[1].value
        b.pushUp = sliders[2].value
        b.discipline = sliders[3].value
        if let formation { b.formation = formation }
        b.periodSeconds = Self.pick(period.value, Tuning.Board.periodSeconds)
        b.ballSpinSeconds = Self.pick(spin.value, Tuning.Board.ballSpinSeconds)
        game.setBoard(b)
    }

    /// "Reset" (§12): the defaults, or the picked club's tactics — and the board shows it.
    private func reset() {
        game.commit { $0.resetBoard() }
        let b = game.save.board
        for (s, v) in zip(sliders, [b.pressing, b.covering, b.pushUp, b.discipline]) { s.set(v, notify: false) }
        period.set(Self.share(b.periodSeconds, Tuning.Board.periodSeconds), notify: false)
        spin.set(Self.share(b.ballSpinSeconds, Tuning.Board.ballSpinSeconds), notify: false)
        for (k, t) in formations { t.isSelected = k == b.formation }
        board.celebrate(0.4)
    }
}
