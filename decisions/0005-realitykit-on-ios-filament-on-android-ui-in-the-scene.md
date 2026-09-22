# 0005 — RealityKit on iOS, Filament on Android, and the UI lives in the scene
Date: 2026-09-22 · Status: **proposed** — accepted when the vertical-slice spike (Stori `SLAP-2`)
passes; supersedes 0003 (0004 withdrawn)

## Context

Two stand-alone implementations sharing config and some assets, nothing else (ADR 0001); `web/`
is a gameplay prototype only (ADR 0002). The owner's brief for the UI: **menus, scoreboards and
the HUD are 3D objects** that bounce, flip and squash — goofy and whimsical in ways widget
toolkits don't allow.

So the renderer now carries the whole product surface: the match scene (sized in 0003's
Context: no PBR, ~50k triangles and ~28 draw calls per world, one shadow, linear fog, instanced
scenery, point clouds), plus localized 3D text, animation, hit-testing, screen transitions and
accessibility. Every screen, every transition and the asset pipeline accrete on this choice.

## The question

What renders the scene *and* the UI on each platform, and does the UI share the match's scene,
camera and clock?

## Decision

**iOS: RealityKit**, hosted in `RealityView` with a virtual camera. **Android: Filament, called
directly**, with a thin Kotlin node layer of our own. One scene, one camera, one clock per
platform — and the UI lives in that scene.

- **One clock, the renderer's frame.** iOS: a RealityKit `System.update` drains the fixed 1/120 s
  accumulator (no separate `CADisplayLink` — two clocks behind one picture is a defect). Android:
  one `Choreographer` callback steps the simulation, updates Filament, renders — main thread.
  Simulation time and UI time are two timelines derived from that one delta: the goal-cam slow
  motion scales the simulation only, so the UI keeps bouncing at real speed.
- **The UI is part of the scene graph.** The HUD is a rig parented to the camera at fixed depth,
  laid out from the frustum and the safe-area insets the host view reports. Menus and scoreboards
  are world objects; a screen transition is a camera move. UI materials ignore fog and cast no
  shadow. No second overlay camera.
- **Text is extruded meshes from one shared font file** (`shared/assets/`). iOS:
  `MeshResource.generateText`. Android: `Paint.getTextPath` → `Path.approximate` → earcut →
  extrude (~300–400 lines, cached per string). Same outlines, so the lettering matches; system
  text size scales the meshes and layout reflows.
- **Motion is our own spring/tween integrator on both** (~150 lines each), its constants being the
  motion tokens in `shared/data/`. Identical equations and constants ⇒ identical feel, and a
  spring curve can be pinned by a golden vector. RealityKit's animation API is not used for UI.
- **Hit-testing is our own ray-vs-bounds test** on UI nodes, synchronous in the touch handler, on
  both (avoids Filament's asynchronous pick).
- **Accessibility is a derived semantics overlay.** Each UI node declares its a11y id, copy key,
  traits and action; every frame a transparent SwiftUI / Compose layer projects them into
  invisible accessibility elements. It is output, like pixels — never hand-authored. VoiceOver and
  TalkBack get a real tree; `<surface>_<action>_button` ids stay testable; activation routes to
  the same action a tap fires. Reduce Motion swaps springs for fades.
- **What stays native:** the host views (opaque `SurfaceView`; the sky is drawn in the scene), the
  semantics overlay, and the StoreKit / Play Billing sheets.
- **Assets are data; materials are bound by name.** `shared/assets/` holds glTF (vertex colours,
  merged static batches), textures, the font, sounds. RealityKit does not load glTF, so a build
  step converts to USDZ for iOS. Each platform binds material slots by name to its own ~8 native
  materials — hemisphere + Lambert sun + linear fog, written twice from one formula in the spec,
  palette and fog numbers from `shared/data/`. RealityKit has no distance fog: it is computed in
  a `CustomMaterial` shader.
- **Minimum OS: iOS 18, Android API 26.** Don't depend on `MeshInstancesComponent` (iOS 26):
  static scenery is merged in the asset, stars are one mesh.

## Parity this buys

Geometry, textures, text and motion are identical by construction. Shading and shadow softness are
close, not identical — "same look to a player's eye", checked by eye on a screenshot sheet. **Pixel
parity is off the table**; when this ADR is accepted that becomes a permanent row in the spec's
platform-delta table.

## Alternatives considered

- **Filament on iOS too** (0003) — rejected on price. Its argument was shared materials, now
  excluded. What remains is C++ interop, a self-vendored XCFramework (CocoaPods read-only
  2026-12-02, SPM unofficial), and hand-building text, animation, hit-testing and accessibility on
  iOS as well — to buy one lighting model.
- **SceneKit** — rejected on merit: soft-deprecated at WWDC25, maintenance only.
- **Hand-rolled Metal / GLES / Vulkan** — rejected on price: two mini-engines and every low-end
  driver bug.
- **SceneView** — rejected on merit: fast-churning 4.x API, a Compose-declared scene is the wrong
  shape for a loop we own at 120 Hz, and its iOS side is RealityKit anyway.
- **libGDX** — rejected on merit: wants the activity lifecycle, 2D text, GLES2-era 3D API.
- **Korge** — rejected on merit: 3D not production-grade.

## Consequences

- Two lighting models, tuned twice; a permanent parity delta row.
- Android carries ~1–1.5k lines of UI plumbing (text, springs, layout, a11y) that RealityKit
  partly hands iOS.
- A glTF → USDZ conversion step in the iOS build.
- Spec: minimum OS lines; the UI sections are specified per screen as each is designed.

## The spike that decides it

One vertical slice on both platforms: **one world as a shared asset, a camera-parented score HUD,
one menu button** — DE/EN extruded text, a spring bounce, the tap hit-test, VoiceOver and TalkBack
through the overlay. 6-minute soak at 60 fps on the weakest Android and an iPhone, thermal state
logged. Fix the frame-time percentile and the by-eye screenshot bar **before** starting.

Must also prove: `RealityView` lets us cap/request the frame rate (else fall back to
`ARView(cameraMode: .nonAR)`, same entity graph); Android text triangulation handles glyph holes
and umlauts — the piece most likely to kill the approach.

## What would change it

If RealityKit cannot hold 60 fps with fog and a shadow on the spike iPhone, or gives no frame-rate
control, Filament on both becomes worth the lost text, animation and accessibility.
