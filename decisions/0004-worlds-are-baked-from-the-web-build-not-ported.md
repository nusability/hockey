# 0004 — Worlds are baked from the web build, not ported
Date: 2026-09-22 · Status: **proposed** — rides on ADR 0003's spike

## Context

The five worlds are ~4.3k lines of procedural Three.js (`web/js/worlds/*`): scenery generated at
load by code, with canvas-drawn textures and unseeded randomness. Porting that code procedurally
means ~8.6k lines of scene-building written twice, against two APIs, drifting forever — the
single largest duplication ADR 0001 would otherwise create.

## Decision

**A world's scenery is data, produced once from `web/`.**

- A Node script runs each world's build code with a **fixed seed** (replacing its
  `Math.random` with the seeded generator) and exports `shared/data/worlds/<id>.glb`, with the
  canvas textures baked in.
- Beside it, `<id>.anim.json` lists what moves: which nodes spin or pulse, which material
  parameters tick with time. Only these small animation hooks are implemented on each platform.
- Both apps load the same file. `web/` stays the authoring tool: a world is edited there, played
  there, and re-baked.
- The world contract in `web/js/worlds/README.md` gains the rules the bake needs (seeded
  randomness, animation declared rather than hidden in `update()`).

## Alternatives considered

- **Port the procedural code to Swift and Kotlin** — rejected on price (above).
- **Author the worlds in a DCC tool (Blender)** — a new pipeline and a new skill, and it
  abandons the worlds that already exist and look right.

## Consequences

- Worlds become identical across platforms by construction; pixel parity becomes possible.
- A world change is: edit in `web/`, re-bake, commit the `.glb` — and it is a spec change when
  the spec describes that world.
- Asset size moves from code into the bundle; budget stated per world (conventions: assets are
  budgeted).
- `web/` could later load the same `.glb`, collapsing the last copy — not required now.
