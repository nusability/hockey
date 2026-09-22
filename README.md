# Slapshot League 🏑

A stylised, colourful 3D field-hockey game for phones — one ice world among five — played with
**one touch**: your players run on their own, you decide only when to let go of the ball.

**This repo is the iOS and Android port**, free-to-play with IAP. It holds:

| | |
|---|---|
| **`ios/`** | The product on iOS — Swift, SwiftUI. XcodeGen: `cd ios && xcodegen generate`. |
| **`android/`** | The product on Android — Kotlin, Compose. A second native codebase, not a build target (ADR 0001): `cd android && ./gradlew assembleDebug`. |
| **`shared/`** | What the platforms share, none of it code either links: `data/` (generated tunables, teams, drills, copy, worlds) and `vectors/` (golden vectors recorded from `web/`, replayed by both). |
| **`web/`** | The original web build — the prototype stage, the parity reference, and the playable demo at **https://nusability.github.io/hockey/** (ADR 0002). |

Both apps are empty shells today; the porting plan lives in Stori project **`SLAP`**.

## How we work

Spec-driven, trunk-based, one change in flight. Read these in order:

- **`AGENTS.md`** — the loop and the operating rules. Start here.
- **`principles.md`** — the constitution: north-stars and monetization ethics. Overrides everything.
- **`conventions.md`** — stack-specific standards.
- **`spec/`** — what the system does *right now*. Never reconstruct current state from tickets.
- **`decisions/`** — ADRs; the durable *why*.

Ideas and backlog live in Stori project **`SLAP`** (Now / Next / Later), never in `spec/`.

The golden rule: **behavior change ⇒ spec change in the same commit, on both platforms.** `web/` is exempt — it's the sandbox.
