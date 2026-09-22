import RealityKit
import SwiftUI

/// One RealityView with everything drawn in it (ADR 0005), and above it a transparent semantics
/// overlay: invisible accessibility elements projected from the 3D UI every frame. The overlay
/// takes no touches — they reach the view and our own hit-test, on touch-down.
struct SpikeView: View {
    @State private var scene: SpikeScene?
    @State private var failure: String?
    @State private var updates: EventSubscription?
    @State private var touching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
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
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if !touching { touching = true; scene.tap(at: v.startLocation) }
                        }
                        .onEnded { _ in touching = false })
                    .onAppear { scene.viewSize = geo.size; scene.reduceMotion = reduceMotion }
                    .onChange(of: geo.size) { _, s in scene.viewSize = s }
                    .onChange(of: reduceMotion) { _, r in scene.reduceMotion = r }

                    if let r = scene.overlay.buttonRect {
                        Color.clear
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                            .accessibilityElement()
                            .accessibilityLabel(scene.buttonLabelText)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("menu_play_button")
                            .accessibilityAction { scene.pressButton() }
                            .allowsHitTesting(false)
                    }
                } else if let failure {
                    Text(failure).foregroundStyle(.white).padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .task {
            do {
                let s = try SpikeScene()
                try await s.build()
                scene = s
            } catch {
                failure = "\(error)"
            }
        }
    }
}
