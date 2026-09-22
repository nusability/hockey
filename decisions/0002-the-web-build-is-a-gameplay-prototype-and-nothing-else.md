# 0002 — The web build is a gameplay prototype and nothing else
Date: 2026-09-22 · Status: **accepted** (revised the same day — see *History*)

## Context

The game was built as a web page (vanilla JS + Three.js) and it is the only playable version.
ADR 0001 builds the product as two stand-alone native implementations. The question is what
the web build is to them.

## Decision

`web/` is a **gameplay prototype**. It explored the rules, the feel, the AI and the tuning, and
that is the whole of what it contributes:

- **What crosses into the apps is behaviour and numbers, through the spec.** The spec states the
  rules and the tuned constants the web build proved (orbit, pass/shot assistance, possession,
  AI and tactics, drills, season format). The apps implement the spec, not the web code.
- **It is not a technical foundation.** Not its code, not its structure (module layout, the
  `Match`/`Renderer` split), not its assets, not its worlds' construction, not its DOM UI, not
  its look. The apps' worlds, UI and presentation are designed natively and may depart from it
  freely.
- **It is not the vector oracle.** Golden vectors are recorded by the apps' own simulations
  against the spec (ADR 0001).
- **It remains the prototype stage.** A feel-dependent mechanic or a balance change can be tried
  there first because it is fast to change; what survives is written into the spec.
- **It stays published** on GitHub Pages as a playable demo; the workflow publishes `web/` only.

It stays no-build, vanilla JS + Three.js. Nothing in it is bound by the spec.

## Consequences

- Reading `web/` is how one learns *what* the game does and *what numbers it uses*; it is never
  how one learns how an app should be built.
- Extracting the gameplay spec from `web/` — rules and numbers, section by section — is the
  port's first real task, because afterwards the web code is no longer consulted for them.
- When the apps ship, revisit whether `web/` is frozen, retired, or rebuilt as a store-page demo.

## History

- First version (same day) made `web/` also the parity reference for look, the recorder of the
  golden vectors, and the source of the worlds (ADR 0004). The owner narrowed it: the web build
  explored gameplay, nothing else. ADR 0004 is withdrawn with it.
