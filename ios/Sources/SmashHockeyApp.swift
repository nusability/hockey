import SwiftUI
import UIKit

@main
struct SmashHockeyApp: App {
    var body: some Scene {
        WindowGroup {
            AppRoot()
                // A game in front holds the screen on; the system still sleeps it when the app leaves.
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}

/// The game, opened where the developer shortcuts ask (`Launch`, `-scene match …`) — a player's
/// launch has none and opens on the save. A malformed shortcut fails loud.
private struct AppRoot: View {
    private let launch = Result { try Launch.plan() }

    var body: some View {
        switch launch {
        case .success(let plan): GameView(launch: plan)
        case .failure(let e): Text("\(e)").foregroundStyle(.white).padding()
        }
    }
}
