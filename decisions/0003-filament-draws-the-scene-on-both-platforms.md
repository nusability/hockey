# 0003 — Filament draws the scene on both platforms
Date: 2026-09-22 · Status: **proposed** — accepted when the renderer spike (Stori `SLAP`) passes
its criteria below; if it fails, the fallback named under *What would change it* applies.

## Context

ADR 0001 gives us two native codebases, so the 3D scene is drawn twice. What the scene needs,
counted from `web/js/render.js` and `web/js/worlds/*` (2026-09-22):

- **Materials:** no PBR anywhere — 64 Lambert, 33 unlit, 4 toon, 3 Phong; 4 custom shaders
  (twinkling stars, glow halo, snow, mist) and 3 patched stock shaders (palm sway, flag wave,
  glowing caps).
- **Geometry:** 20 instanced meshes (up to 230 pines, 160 confetti), 9 point clouds (3,400 stars,
  2,200 snowflakes), 6 sprites, line-drawn goal nets; 16 additive and 23 double-sided materials.
- **Light:** one hemisphere, one sun with a 2048² soft shadow map, one point light, linear fog.
- **Textures:** 20 drawn at runtime with a 2D canvas, including the 1024×2048 pitch.
- **Budget:** each world states ~45–53k triangles and 25–28 draw calls; rink + 12 players ~60 more.
- **Randomness:** the worlds call unseeded `Math.random` 35 times — no two loads look alike, so
  pixel parity is impossible as things stand.

A real scene graph, but a small, old-fashioned one: no PBR, no post-processing, one shadow.
Flashybird's hand-rolled renderer (~200 lines of projection math) does not scale to it.

## The question

What renders the 3D scene on iOS and on Android?

## Decision

**Google Filament, called directly (not through SceneView), on both platforms** — Metal backend
on iOS, OpenGL ES 3.0 on Android (Vulkan later, if it earns it).

- **Worlds are baked, not ported** (ADR 0004): each world is one glTF both apps load.
- **Materials are declared once**: ~8 Filament material sources (matte, toon, shiny,
  unlit/additive, wind, stars, halo, mist) in `shared/materials/`, compiled by Filament's `matc`
  at build time. They are shader *descriptions*, like `shared/data` — this is recorded as an
  amendment to ADR 0001's "no shared executable code of ours" when this ADR is accepted.
- **Each platform owns** its frame loop (`CADisplayLink` / `Choreographer`: advance the 1/120 s
  simulation, render once), the camera and goal director, players, aim line and confetti.
  Filament owns drawing. SwiftUI / Compose own HUD and menus **above an opaque 3D surface** (Metal
  layer / `SurfaceView`).
- **The sky moves into the scene.** The web draws it in CSS behind a transparent canvas; on
  Android a transparent surface forces the costlier `TextureView`, and the sky would live in two
  places.
- 120 Hz is requested on ProMotion; dynamic resolution protects thermals.
- **Minimum OS (proposed):** iOS 17, Android API 26. Filament forces neither.

## Alternatives considered

- **RealityKit on iOS + Filament on Android** — rejected on merit: two engines, two lighting
  models, parity becomes a permanent tuning job; USDZ vs glTF; a third shader dialect. Buys a
  first-party engine and no C++ on iOS. **This is the fallback** if the spike fails.
- **SceneKit** — rejected on merit: soft-deprecated at WWDC25 (maintenance only).
- **Hand-rolled Metal + GLES** — rejected on price: ~2–3k lines per platform (loader, instancing,
  ~8 shaders in two languages, shadow map, transparency sorting, fog, culling) — two mini-engines
  kept in step by eye, and every low-end Android driver bug our own.
- **SceneView** — its iOS side is RealityKit (no parity), and on Android it adds a scene model iOS
  does not have.

## Consequences

- **C++ interop on iOS** (Swift C++ interop or a thin Objective-C++ layer, ~300 lines of glue);
  crashes can land in C++ frames.
- **Packaging is ours on iOS.** Filament ships on iOS only via CocoaPods, which goes read-only on
  2026-12-02; SPM support is an open upstream request. We build and vendor our own XCFramework
  with our own script.
- A few MB of binary per platform/ABI.
- Filament is PBR-first; the matte/toon look needs our own materials, tuned once against `web/`.
- Point clouds become instanced quads.
- The parity rig compares iOS against Android (same glb, same materials) — near-pixel — and both
  against `web/` by eye.

## The spike that decides it

One baked world (**Oasis**: wind shaders, sprites, points, shadow, additive blending) in
Filament on a **low-end Android phone** and an **iPhone**, same `.glb`, same compiled materials:

- 60 fps sustained through a 6-minute soak, thermal state logged;
- iOS app-size delta measured;
- the XCFramework built by our own script;
- a side-by-side screenshot sheet whose difference is under a threshold fixed before the spike.

## What would change it

If Filament's Metal backend cannot hold 60 fps without throttling on the spike devices, or its
iOS build cannot be vendored cleanly once CocoaPods closes: RealityKit on iOS, Filament on
Android, and looser parity written into the delta table.
