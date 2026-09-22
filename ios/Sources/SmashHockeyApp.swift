import SwiftUI
import UIKit

@main
struct SmashHockeyApp: App {
    var body: some Scene {
        WindowGroup {
            SpikeView()
                // A game in front holds the screen on; the system still sleeps it when the app leaves.
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}
