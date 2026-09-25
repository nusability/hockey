import RealityKit
import SmashCore

/// The title (spec §16.2): the logo drops in letter by letter and keeps bobbing; the season button
/// bobs for the thumb — continue the season, or on to the next once it is over; training, quick
/// match, the coach's board and how to play. The trophy counts when there are any. The twin of
/// Android's TitleScreen.kt.
@MainActor
final class TitleScreen: Screen {
    private var badge: Panel!

    init(game: Game) {
        super.init(pose: CameraPose(Presentation.Screens.Title.eye, Presentation.Screens.Title.target), game: game)
        let m = motion
        part(WaveText(L(.titleLogoTop), height: 0.36, colour: C.sun, id: "title_logo_header", motion: m),
             at: at(0, top - 0.45, tilt: 0.05))
        part(WaveText(L(.titleLogoBottom), height: 0.30, colour: C.paper, bob: 0.7, id: "title_logo2_header", motion: m),
             at: at(-0.05, top - 0.90, tilt: 0.05))
        badge = part(Panel(size: [0.42, 0.30, 0.12], colour: C.pink, entrance: .pop, motion: m),
                     at: at(0.62, top - 1.22, z: 0.05, tilt: -0.22))
        child(Label3D("3D", height: 0.16, colour: C.ink, motion: m), on: badge.content).presence.show(after: 0)
        // The buttons stand on the bottom edge; the trophies ride just above them.
        let y0 = bottom + 0.3
        if let c = game.save.career, c.leagueTitles + c.cups > 0 {
            part(Label3D(L(.titleTrophies, c.leagueTitles, c.cups), height: S.textSmall, colour: C.sun, maxWidth: 1.6,
                         entrance: .pop, motion: m), at: at(0, y0 + 1.6))
        }

        let over = game.save.season?.isFinished ?? true
        // 0.11 is the largest lettering at which every caption this key can carry — CONTINUE
        // SEASON, NEXT SEASON and both German strings — sits on one line in the 1.5 plate. Above
        // it CONTINUE SEASON wraps and the key grows into the trophies above it (§16). A hair
        // smaller than the secondary keys below: the plate's size and the sun colour carry the
        // hierarchy here, not the lettering.
        let season = part(BlockButton(L(over ? .titleNextSeason : .titleContinue), id: "title_season_button",
                                      style: .primary, size: [1.5, 0.4], textHeight: 0.11, motion: m) { [weak game] in
            guard let game else { return }
            let seed = MatchPlan.seed()
            if game.save.season == nil { game.commit { try $0.startSeason(seed: seed) } }
            game.go(.hub)
        }, at: at(0, y0 + 1.2))
        season.bobs = true
        part(BlockButton(L(.titleTraining), id: "title_training_button", style: .secondary, size: [1.5, 0.32], motion: m) {
            [weak game] in game?.go(.training(intro: nil))
        }, at: at(0, y0 + 0.78))
        part(BlockButton(L(.titleQuick), id: "title_quick_button", style: .secondary, size: [1.5, 0.32], motion: m) {
            [weak game] in game?.playQuick()
        }, at: at(0, y0 + 0.4))
        part(BlockButton(L(.titleCoach), id: "title_coach_button", style: .quiet, size: [0.72, 0.3], textHeight: 0.1,
                         motion: m) { [weak game] in game?.go(.coach) }, at: at(-0.39, y0))
        part(BlockButton(L(.titleHelp), id: "title_help_button", style: .quiet, size: [0.72, 0.3], textHeight: 0.1,
                         motion: m) { [weak game] in game?.go(.help) }, at: at(0.39, y0))
    }

    override func show(after delay: Double) {
        super.show(after: delay)
        stage.after(delay + 1.0) { [weak self] in self?.badge.celebrate(0.8) }
    }
}

extension Game {
    /// A quick match (§11.5): opponent and world drawn from a stream of its own, seeded now.
    func playQuick() {
        play(.quick(QuickMatch(seed: MatchPlan.seed(), player: save.sideTeam)))
    }
}
