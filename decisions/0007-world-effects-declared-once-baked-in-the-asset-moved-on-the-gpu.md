# 0007 — World effects: declared once, baked into the asset, moved on the GPU
Date: 2026-09-22 · Status: **accepted** · Extends ADR 0006 (its shader set) and ADR 0005 (the asset contract)

## Context

The Blender re-author (ADR 0006 §5) left out everything in the prototype's worlds that moved, pulsed
or glowed over time — the owner calls it "very important". It has to come back on two engines that
share no code, without fog, shadow maps or engine lighting, within a Snapdragon 765G's 60 fps.

## Decision

1. **Declared once.** `shared/data/effects.toml` lists each world's effects: an id, a shading
   (`lit | glow | soft | particles`), a blend (`add | alpha`) for the blended ones, a motion
   (`none | sway | orbit`) and its numbers, a pulse `[base, a1, ω1, a2, ω2]`, particle numbers
   (size, spread, opacity, travel + wrap, wobble). `tools/generate-data.py` emits it into both apps
   (`Effects.swift`, `Effects.kt`); the world builds read the same file through the same parser.
   A `[calm]` table scales every amplitude and rate under Reduce Motion — calmer, never still.
2. **Baked into the asset.** Every effect is one extra mesh `fx_<id>` in its world's GLB/USDZ, next
   to the three core meshes (the contract check now requires exactly the declared ones). What a
   vertex needs — a weight / orbit-speed factor / falloff / sprite corner `w`, and a phase `p` — rides
   **inside its palette swatch**: the UV sits at `0.05 + 0.9·(w, p)` of its swatch cell instead of
   the centre, so nearest sampling still reads the colour, and position + normal + one UV set is all
   either exporter must keep. Particles are baked as flat quads round their spawn points (their
   layout from a seed of each effect's own), so both platforms place them identically by
   construction; the shader recovers the spawn point from the corner and hashes it for its
   randomness. Everything in the asset is in the game's frame; iOS turns RealityKit's object space
   (Blender's frame under the USD root's −90° turn) into it and back.
3. **Moved on the GPU, from time alone.** Every formula is closed-form in the renderer's clock
   (Filament `getUserTime`, RealityKit `ND_time_float`) — no per-frame CPU work, no buffer uploads,
   no hook into either platform's loop, nothing from the match's clock or random streams. The
   formulas (sway, orbit on ellipses about a vertical axis, pulse, particle travel/wrap/wobble,
   camera-facing sprites) are written once in `android/…/materials/fx_common.glsl` and node for node
   in `ios/Sources/Effects/FxMaterials.swift` (a small MaterialX graph builder, `FxGraph`).
4. **Shader variants added to ADR 0006's set** (world / toon / flat / sky): **fx lit** (the world
   formula + motion), **fx glow** (unlit palette × pulse + motion — the prototype's emissives),
   **fx soft** (palette × w² × opacity × pulse, additive or alpha, premultiplied — glow pools, halos,
   mist, cloud wisps, light shafts; still no fog), **fx particle** (camera-facing sprites, additive or
   alpha). Android: six `.mat` (blending is per material); iOS: four graphs (additive = premultiplied
   colour at opacity 0). Effects are never culled (their shaders move them beyond their bounds).
5. **The pitch contract holds wherever an effect goes**: the build checks orbits all the way round,
   sways at full reach, particles along their travel; only particles declared `over_pitch` (snow) may
   cross the boundary.

## Budgets (checked at build; 765G at 60 fps)

Core meshes ≤ 45k triangles, effects ≤ 12k per world. One draw call per effect.

| World | Extra draw calls | Particles (sprites) | Effect triangles |
|---|---|---|---|
| Magic Wood | 8 | 200 fireflies | 6,950 |
| Deep Space | 8 | 220 stars | 7,590 |
| Desert Oasis | 5 | 108 sparkles + 1 fire glow + 300 dust | 8,870 |
| Himalaya | 3 | 900 snowflakes | 3,788 |
| Ocean World | 7 | 228 bubbles + 120 motes | 6,108 |

Vertex cost is a few dozen ALU ops per vertex on ≤ 12k triangles; the fill cost is the soft layers
(mist, cloud, shafts, pools) — translucent, but few and mostly off the pitch.

## Alternatives considered

- **CPU-animated particles with one buffer upload per frame** — rejected: a per-frame hook in each
  platform's loop (owned by another stream), an upload per frame, and two update loops to keep in step,
  for motion that is a closed-form function of time anyway.
- **A second UV set / vertex colours for the motion data** — rejected: RealityKit's handling of extra
  USD primvars is not something we can rely on; the swatch UV is kept by every path.
- **Per-effect layouts generated at run time from a seed** — rejected: two RNG ports to keep bit-equal;
  baking makes placement identical by construction.

## Consequences

- A new effect is a toml entry and a few lines in its world script — and it lives on both platforms at
  once. A new *kind* of motion is a change to both shader implementations, together.
- Rotation is about the vertical only, orbits are ellipses of one ratio per effect (fish shapes stretch
  slightly round the ellipse; mantas orbit circles); the station's wheel, the planets' spin and the
  asteroid belt stay still. Particles pulse in size, not brightness (no varying crosses the stages).
- Reduce Motion is read at load, not live.
