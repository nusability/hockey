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

/// Until the menus exist: `-scene match` (with `-quick home,away,world`, `-drill N` or `-demo`,
/// see MatchPlan) plays a match; otherwise the SMASH-5 motion sketch opens for the owner to judge.
private struct AppRoot: View {
    private let plan = Result { try MatchPlan.fromLaunch() }

    var body: some View {
        switch plan {
        case .success(let p?): MatchScreen(plan: p)
        case .success(nil): SketchView()
        case .failure(let e): Text("\(e)").foregroundStyle(.white).padding()
        }
    }
}
