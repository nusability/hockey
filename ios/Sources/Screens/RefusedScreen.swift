import RealityKit
import SmashCore

/// A save that cannot be read (spec §15): the game says so on a screen of its own and never opens
/// as if the player were new. The file stays on the phone, untouched, beside the new one; the one
/// way on is to start over. The twin of Android's RefusedScreen.kt.
@MainActor
final class RefusedScreen: Screen {
    init(game: Game, why: String) {
        super.init(pose: CameraPose(Presentation.Screens.Refused.eye, Presentation.Screens.Refused.target), game: game)
        let m = motion
        part(WaveText(L(.refusedTitle), height: 0.15, colour: C.pink, bob: 0.4, id: "refused_title_header", motion: m),
             at: at(0, top - 0.5))
        let card = part(Panel(size: [1.66, 1.2, 0.14], colour: C.paper, entrance: .tumble, motion: m), at: at(0, top - 1.45))
        child(Paragraph(L(.refusedBody), height: 0.07, colour: C.ink, width: 1.44, id: "refused_body", motion: m),
              at: at(0, 0.08), on: card.content).show(after: 0)
        // The reason, small, for whoever is asked to look at the phone.
        child(Label3D(why, height: 0.035, colour: C.disabledInk, maxWidth: 1.44, motion: m), at: at(0, -0.45),
              on: card.content).show(after: 0)
        let go = part(BlockButton(L(.refusedStartOver), id: "refused_startover_button", style: .danger, size: [1.3, 0.38],
                                  textHeight: 0.13, motion: m) { [weak game] in game?.startOver() }, at: at(0, bottom + 0.4))
        go.bobs = true
    }
}
