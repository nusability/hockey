import RealityKit
import SwiftUI
import UIKit

/// The game on screen: one RealityView with everything drawn in it (ADR 0005), a transparent
/// multi-touch surface above it — the stage's own hit-test first, the match's finger (§5.3) for
/// whatever the UI does not take — the derived semantics overlay, and a hidden text field that
/// brings up the system keyboard for the create screen's name and code (§16.1).
struct GameView: View {
    let launch: MatchPlan?
    @State private var game: Game?
    @State private var failure: String?
    @State private var updates: EventSubscription?
    @FocusState private var typing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase

    var body: some View {
        GeometryReader { geo in
            let full = CGSize(width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                              height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
            ZStack {
                if let game {
                    RealityView { content in
                        content.camera = .virtual
                        content.add(game.root)
                        updates = content.subscribe(to: SceneEvents.Update.self) { event in
                            MainActor.assumeIsolated { game.update(event.deltaTime) }
                        }
                    }
                    TouchSurface(game: game)
                    SemanticsOverlay(model: game.stage.semanticsModel, stage: game.stage)
                    KeyboardField(keyboard: game.keyboard, typing: $typing)
                } else if let failure {
                    Text(failure).foregroundStyle(.white).padding()
                }
            }
            .frame(width: full.width, height: full.height)
            .background(Color.black)
            .ignoresSafeArea()
            .onChange(of: reduceMotion) { _, r in game?.reduceMotion = r }
            .onChange(of: phase) { _, p in
                guard p != .active, let g = game else { return }
                g.pause(true)                                              // §8.7
                // The other of the two moments anything is sent (§18.8): the app is leaving.
                g.telemetry.flush(installId: g.device.installId)
            }
            .task {
                guard game == nil, failure == nil else { return }
                do {
                    let insets = UIEdgeInsets(top: geo.safeAreaInsets.top, left: geo.safeAreaInsets.leading,
                                              bottom: geo.safeAreaInsets.bottom, right: geo.safeAreaInsets.trailing)
                    let g = try await Game.make(viewSize: full, insets: insets, launch: launch)
                    g.reduceMotion = reduceMotion
                    game = g
                } catch {
                    failure = "\(error)"
                }
            }
        }
    }
}

/// The hidden field the system keyboard types into. It follows the game's keyboard: focused while
/// a field is being edited, and editing ends when the keyboard goes away.
private struct KeyboardField: View {
    @Bindable var keyboard: Keyboard
    var typing: FocusState<Bool>.Binding

    var body: some View {
        TextField("", text: $keyboard.text)
            .focused(typing)
            .textInputAutocapitalization(keyboard.field == .code ? .characters : .words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit { keyboard.end() }
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: keyboard.field) { _, f in typing.wrappedValue = f != nil }
            .onChange(of: typing.wrappedValue) { _, t in if !t { keyboard.end() } }
    }
}

/// Every finger on the screen. A finger that lands on a 3D control belongs to the UI (the first
/// such finger drives it); every other finger is the match's while a match is being played: the
/// first one down holds, the last one up releases (§5.3). Touches arrive on the main thread, like
/// the scene's update.
private struct TouchSurface: UIViewRepresentable {
    let game: Game

    func makeUIView(context: Context) -> Surface {
        let v = Surface()
        v.game = game
        v.isMultipleTouchEnabled = true
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ v: Surface, context: Context) { v.game = game }

    final class Surface: UIView {
        weak var game: Game?
        private var ui: ObjectIdentifier?
        private var onPitch = Set<ObjectIdentifier>()

        override func layoutSubviews() {
            super.layoutSubviews()
            game?.pitch.aspect = bounds.width / max(bounds.height, 1)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let game else { return }
            for t in touches {
                let p = t.location(in: self)
                if ui == nil, game.touchDown(at: p) {
                    ui = ObjectIdentifier(t)
                } else if game.pitchTakesFingers {
                    let first = onPitch.isEmpty
                    onPitch.insert(ObjectIdentifier(t))
                    if first { game.finger(down: true, touchTime: t.timestamp) }
                }
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let game else { return }
            for t in touches where ObjectIdentifier(t) == ui { game.stage.touchMoved(to: t.location(in: self)) }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

        private func lift(_ touches: Set<UITouch>) {
            guard let game else { return }
            for t in touches {
                let id = ObjectIdentifier(t)
                if id == ui {
                    ui = nil
                    game.stage.touchUp(at: t.location(in: self))
                } else if onPitch.remove(id) != nil, onPitch.isEmpty {
                    game.finger(down: false, touchTime: t.timestamp)
                }
            }
        }
    }
}
