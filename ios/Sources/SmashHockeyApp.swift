import SwiftUI
import UIKit

@main
struct SmashHockeyApp: App {
    var body: some Scene {
        WindowGroup {
            // The SMASH-5 motion sketch for the owner to judge on a phone; the SMASH-2 spike
            // (SpikeView) stays in the tree until the integrator retires it.
            SketchView()
                // A game in front holds the screen on; the system still sleeps it when the app leaves.
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}
