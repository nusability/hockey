import RealityKit
import SwiftUI

/// THROWAWAY (SMASH-5): hosts the motion sketch — one RealityView with everything drawn in it
/// (ADR 0005) and the derived semantics overlay above it. Touches go to the stage's own
/// hit-test on touch-down; the overlay takes none.
struct SketchView: View {
    @State private var scene: SketchScene?
    @State private var failure: String?
    @State private var updates: EventSubscription?
    @State private var touching = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// The system setting, or `-sketchReduceMotion` to check the calm path without Settings.
    private var reduceMotion: Bool {
        systemReduceMotion || ProcessInfo.processInfo.arguments.contains("-sketchReduceMotion")
    }

    var body: some View {
        GeometryReader { geo in
            let full = CGSize(width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                              height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom)
            ZStack {
                if let scene {
                    RealityView { content in
                        content.camera = .virtual
                        content.add(scene.root)
                        updates = content.subscribe(to: SceneEvents.Update.self) { event in
                            MainActor.assumeIsolated { scene.update(event.deltaTime) }
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { v in
                            if !touching {
                                touching = true
                                scene.stage.touchDown(at: v.startLocation)
                            }
                            scene.stage.touchMoved(to: v.location)
                        }
                        .onEnded { v in
                            touching = false
                            scene.stage.touchUp(at: v.location)
                        })
                    .onAppear { scene.stage.reduceMotion = reduceMotion }
                    .onChange(of: full) { _, s in scene.stage.resize(s) }
                    .onChange(of: systemReduceMotion) { _, _ in scene.stage.reduceMotion = reduceMotion }

                    SemanticsOverlay(model: scene.stage.semanticsModel, stage: scene.stage)
                } else if let failure {
                    Text(failure).foregroundStyle(.white).padding()
                }
            }
            .frame(width: full.width, height: full.height)
            .background(Color.black)
            .ignoresSafeArea()
            .task {
                guard scene == nil, failure == nil else { return }
                do {
                    let insets = UIEdgeInsets(top: geo.safeAreaInsets.top, left: geo.safeAreaInsets.leading,
                                              bottom: geo.safeAreaInsets.bottom, right: geo.safeAreaInsets.trailing)
                    let s = try await SketchScene.make(viewSize: full, insets: insets)
                    scene = s
                    if ProcessInfo.processInfo.arguments.contains("-sketchAutoplay") { s.startAutoplay() }
                } catch {
                    failure = "\(error)"
                }
            }
        }
    }
}
