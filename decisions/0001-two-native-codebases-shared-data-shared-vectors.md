# 0001 — Two native codebases, shared data, shared golden vectors
Date: 2026-09-22 · Status: **accepted**

## Context

Slapshot League exists as a web build: ~11k lines of vanilla JavaScript over Three.js, no build
step, served on GitHub Pages. It plays well; the goal is the App Store and Google Play, both, in
parallel, free-to-play with IAP.

The thing being ported is a real 3D scene — five procedurally built worlds (~3.8k lines of
scenery), players, a goal camera with slow motion — over a simulation of ~1.4k lines (`match.js`,
`ai.js`) stepped at a fixed 1/120 s, synthesised WebAudio sound, and DOM menus. The sister
project flashybird went two-native (its ADR 0017) with a renderer that was ~200 lines of shader
math; here the renderer is most of the code.

## The question

What does the app run on? Everything else — IAP, persistence, the spec's platform-delta table,
the test pipeline — accretes on this answer.

## Decision

**Two native codebases, sharing no executable code of ours.**

- **`ios/`** — Swift, SwiftUI, StoreKit 2.
- **`android/`** — Kotlin, Jetpack Compose, Play Billing.
- What draws the 3D scene on each platform is **ADR 0003**.
- Both are built **in parallel from the first commit**; neither is the port of the other. Both
  are ports of the spec, with `web/` as the reference for feel and look (ADR 0002).

Drift is fought by two mechanisms that are data rather than code, as in flashybird:

1. **`shared/data/`** — teams, drills, formations, tactics defaults, physics and AI constants,
   world declarations, design tokens and the copy live in one platform-neutral table and are
   **generated** into Swift and Kotlin. A hand-edited constant on either side is the bug the
   generator exists to make impossible.
2. **`shared/vectors/`** — seeded golden vectors: *(seed, input stream, sampled expected
   state)*, **recorded from the `web/` reference** and replayed by both platforms' suites. A
   mismatch is a red build on whichever platform moved.

## Alternatives considered

Weighed with the owner on 2026-09-22, with costs stated; the owner chose two native codebases.

**Capacitor wrap of the web build** (the recommendation at the time). One codebase, both stores
truly in parallel, the web demo is the same code, weeks rather than months. Costs: WebView
performance on low-end Android with five detailed worlds, about a frame of extra touch latency,
120 Hz not guaranteed, and a game that never feels fully native. Rejected by the owner on merit:
the product bar is native.

**Godot 4 rewrite.** One native codebase, mature mobile export, web export for a demo. Costs:
rewriting the whole game into a new toolchain and re-tuning feel inside an engine's physics and
camera. Rejected: the owner prefers owning the stack natively, as in flashybird.

**Kotlin Multiplatform / shared C++ or Rust core.** Would delete the class of bug the vectors
exist to catch, for the simulation. Not chosen now: two toolchains and an FFI or framework
boundary for a solo developer; revisit once both apps ship and the duplication cost is a
measured number rather than a guessed one.

## Consequences

- **Every behaviour change is a two-codebase change**, forever. The spec's platform-delta table
  is the disclosure mechanism; the vectors are the enforcement.
- **The simulation must become deterministic before porting starts.** Today `ai.js`, `match.js`
  and `season.js` draw from `Math.random()`; vectors are impossible until the web reference draws
  from a seeded generator whose algorithm both apps reproduce bit-for-bit. This is the port's
  first task.
- **The rendering layer is written twice** — the dominant cost of this decision, and the reason
  ADR 0003 is the next one-way door.
- **Purchases are per-store and per-device.** No account, so an entitlement bought on one store
  does not follow a player to the other; the UI never implies otherwise.
- The web build is not wasted: it stays the prototype stage, the parity reference and the vector
  recorder (ADR 0002).
