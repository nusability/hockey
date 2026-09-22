import RealityKit
import SwiftUI
import UIKit

/// The match on screen: one RealityView (ADR 0005) under a transparent multi-touch surface — the
/// finger of §5.3 — and a semantics overlay that projects the 3D HUD's controls into invisible
/// accessibility elements. The overlay takes no touches.
struct MatchScreen: View {
    let plan: MatchPlan
    @State private var scene: MatchScene?
    @State private var failure: String?
    @State private var updates: EventSubscription?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack {
            if let scene {
                RealityView { content in
                    content.camera = .virtual
                    content.add(scene.root)
                    updates = content.subscribe(to: SceneEvents.Update.self) { event in
                        MainActor.assumeIsolated { scene.update(event.deltaTime) }
                    }
                }
                .ignoresSafeArea()
                TouchSurface(scene: scene).ignoresSafeArea()
                if let r = scene.overlay.pauseRect {
                    Color.clear
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .accessibilityElement()
                        .accessibilityLabel(String(localized: scene.overlay.paused ? "pause.resume" : "pause.title"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("match_pause_button")
                        .accessibilityAction { scene.togglePause() }
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
            } else if let failure {
                Text(failure).foregroundStyle(.white).padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .onChange(of: reduceMotion) { _, r in scene?.reduceMotion = r }
        .onChange(of: phase) { _, p in if p != .active { scene?.setPaused(true) } }   // §8.7
        .task {
            do {
                let s = try MatchScene(plan: plan, seed: MatchPlan.seed())
                s.reduceMotion = reduceMotion
                try await s.build()
                scene = s
            } catch {
                failure = "\(error)"
            }
        }
    }
}

/// Every finger on the screen (§5.3): the first one down on the pitch holds, the last one up
/// releases — any number of fingers. A touch that lands on a HUD control belongs to the UI and
/// never reaches the match. Touches are delivered on the main thread, like the scene's update.
private struct TouchSurface: UIViewRepresentable {
    let scene: MatchScene

    func makeUIView(context: Context) -> Surface {
        let v = Surface()
        v.scene = scene
        v.isMultipleTouchEnabled = true
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ v: Surface, context: Context) { v.scene = scene }

    final class Surface: UIView {
        weak var scene: MatchScene?
        private var onPitch = Set<ObjectIdentifier>()

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            report()
        }

        private func report() {
            scene?.resize(bounds.size, safeTop: safeAreaInsets.top, safeBottom: safeAreaInsets.bottom)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let scene else { return }
            for t in touches where !scene.touchIsUI(at: t.location(in: self)) {
                let first = onPitch.isEmpty
                onPitch.insert(ObjectIdentifier(t))
                if first { scene.finger(down: true, touchTime: t.timestamp) }
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

        private func lift(_ touches: Set<UITouch>) {
            guard let scene else { return }
            for t in touches where onPitch.remove(ObjectIdentifier(t)) != nil {
                if onPitch.isEmpty { scene.finger(down: false, touchTime: t.timestamp) }
            }
        }
    }
}
