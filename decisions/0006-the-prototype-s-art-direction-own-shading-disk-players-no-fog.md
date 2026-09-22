# 0006 — The prototype's art direction: our own shading, disk players, no fog
Date: 2026-09-22 · Status: **accepted** · Narrows ADR 0002 (the look now carries over) and ADR 0005
(how materials are written)

## Context

The first builds on the owner's phones (spec 0.5.0) looked wrong: washed out to white on iOS,
more saturated on Android, fogged, with toy-figure players. The owner's verdict: *"the art
direction of the web prototype was miles ahead. I want that."* — players as disks, no
anthropomorphising, the prototype's worlds, and no fog: *"for this kind of graphics we don't
need no fog."*

What the prototype actually does (`web/js/render.js`): every surface a Lambert or toon material;
one hemisphere light (sky/ground colours) plus one sun; no tone mapping, sRGB out, so colours
land at full strength; players are squat team-coloured cylinders with a secondary-colour dot on
top (goalies a ring, dummies a grey cone-ish body with an orange stripe) and a soft disc shadow
under each; the pitch surface painted onto a canvas texture; the sky a CSS gradient.

The apps had drifted to each engine's physically based lighting and tone mapping — which is
both why they looked washed out and why the two platforms disagreed (RealityKit's tone mapper
cannot be turned off).

## Decision

1. **Our own shading on both platforms, one formula**: `colour = albedo × (hemisphere(n) +
   sunColour × sunStrength × max(0, n·l))`, with `hemisphere(n)` the mix of ground and sky colour
   by `0.5 + 0.5·n.y` — the prototype's Lambert + HemisphereLight — and a two-band toon variant
   for players and posts. Written as an **unlit** material that computes this itself (a
   RealityKit `CustomMaterial` surface shader; a Filament unlit material), so **no engine tone
   mapping and no engine lighting touch the colour**, and iOS and Android produce the same pixels
   for the same inputs. Per-world hemisphere/sun values live in `shared/data`.
2. **No fog.** Removed from both platforms and from the declarations.
3. **No dynamic shadow maps.** Players and the ball carry the prototype's soft **disc shadow**;
   world scenery may carry shade painted into its palette. (The prototype had real sun shadows;
   giving them up is the price of identical, engine-independent shading — revisit only if the
   owner misses them.)
4. **Players are disks**, exactly the prototype's shapes and proportions (radius from spec §3,
   height 0.45, primary body, secondary top dot; goalie ring; dummies grey with an orange
   stripe), the carrier's green selection ring included. No figures, no faces.
5. **Worlds are re-authored in Blender to match the prototype's worlds closely** — their contents,
   layout, palette, sky gradient and pitch painting — using `web/js/worlds/*` and `render.js` as
   the visual reference. The web code is read, never run or exported (the owner chose this over
   baking, keeping `web/` out of the pipeline).

## Consequences

- The Android–iOS saturation delta (SMASH-13) closes by construction; the permanent "not pixel
  identical" row in the spec narrows to anti-aliasing and rasterisation.
- Lighting is ours to own: every material is one of a handful of named shaders on each platform,
  kept in step by the formula above and its constants in `shared/data`.
- The five Blender worlds from wave 1 are re-authored, not patched.
- Sun shadows are gone until someone wants them back enough to pay for a shadow pass in two
  custom shading pipelines.
