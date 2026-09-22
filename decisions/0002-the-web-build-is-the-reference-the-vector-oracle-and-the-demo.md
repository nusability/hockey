# 0002 — The web build is the reference, the vector oracle, and the demo
Date: 2026-09-22 · Status: **accepted**

## Context

The game was built as a web page, and it is the only place the game exists today. ADR 0001
ports it to two native codebases. That leaves the web build with no store to ship to, but with
three things nothing else in the repository can do yet: it is the only playable version, the
only place feel has been tuned, and the only implementation that could record what "correct"
means before either port exists.

## Decision

The web build moves to **`web/`** and keeps three roles:

1. **The parity reference.** For feel, AI behaviour and look, `web/` is what the apps are
   measured against until the spec has absorbed it. Where the apps deliberately move past it,
   the spec says so and the spec wins.
2. **The vector oracle.** Once its simulation is seeded, `web/` records the golden vectors in
   `shared/vectors/` that both native suites replay. It is the one implementation that does not
   need porting to produce them, and it is the one whose behaviour the owner has actually played
   and approved.
3. **The prototype stage and the web demo.** Feel-dependent mechanics, AI tuning and balance are
   tried there first (AGENTS: prototype before spec). It stays published on GitHub Pages
   (`.github/workflows/pages.yml`), which uploads `web/` only — the spec, ADRs and native projects
   are never published.

It stays **no-build, vanilla JS + Three.js**. It is **not frozen**, unlike flashybird's
prototypes: during the port it is still where the game is tuned.

## Alternatives considered

- **Freeze it now** (flashybird's end state). Premature: the port needs a place to tune the AI
  and feel quickly, and the game is still young.
- **Leave it at the repo root.** Pages would publish the whole repository, and the root would mix
  a web page with the harness and two native projects.
- **Record vectors from one of the native apps instead.** Circular: the first port to exist would
  define correctness for the second, and neither has been played by the owner.

## Consequences

- **A change to `web/`'s simulation that moves a recorded vector is a spec change** — the
  exemption `web/` enjoys ends where the vectors begin. Rendering, audio and menus in `web/`
  stay exempt.
- `Math.random()` is banned from the web simulation path once seeding lands; it remains fine in
  rendering and audio.
- When both apps are at parity and the game has shipped, revisit: freeze `web/` into a demo
  (as flashybird's landing page did), or keep it as the prototype stage.
