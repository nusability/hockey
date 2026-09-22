import SwiftUI

/// The empty shell (spec: platform-delta row "Neither app implements §1–§9 yet"). It launches and
/// shows the title; the scene surface arrives with ADR 0003's spike.
@main
struct SmashHockeyApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(red: 0x1E / 255, green: 0x1B / 255, blue: 0x4B / 255).ignoresSafeArea()
                VStack(spacing: 8) {
                    Text("app.name").font(.system(size: 34, weight: .heavy, design: .rounded))
                    Text("menu.tagline").font(.system(size: 16)).opacity(0.8)
                }
                .foregroundStyle(.white)
            }
        }
    }
}
