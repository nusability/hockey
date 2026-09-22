# Conventions

Stack-specific coding standards. Unlike `principles.md` (universal values), these are tied
to the tech in use and change with it.

The stack is **two native codebases** (ADR 0001): Swift + SwiftUI on iOS, Kotlin + Jetpack
Compose on Android. **What draws the 3D scene on each is ADR 0003** — until it is accepted,
entries about rendering are marked *(pending 0003)*.

## Greenfield — until the first store submission
Nothing has shipped, so **principle 13's exception is asleep**: there is no player whose record
could be broken, and our own save shapes may change freely without migrations.

It expires at the **first submission to either store**. From that build on, the exception wakes
up and a real player's record becomes untouchable: persistence is migrated, never assumed; a
record that fails to decode is preserved, never silently replaced. **Whoever ships first deletes
this section.**

What does *not* sleep: the rule against fabricating entitlements, and the fail-loud config rule.
Those apply from the first line.

## The web build (`web/`)
- **It is the prototype stage and the parity reference** (ADR 0002). Tune feel, AI and balance
  there; port the *tuned numbers* and the proven behaviour into the apps.
- **It stays no-build, vanilla JS + Three.js.** If a change wants a bundler or a package, that is
  the signal it belongs in the apps.
- **Its simulation is the vector oracle.** Once seeded (see the porting plan), the simulation
  path (`match.js`, `ai.js`, `season.js`, `levels.js`, `math.js`) draws only from the seeded
  generator. `Math.random()` is allowed only in rendering and audio.
- **Never copy-paste web code into an app.** Port the numbers and the behaviour; write the
  implementation properly on the other side.

## Game loop & feel
- **The simulation steps at a fixed 1/120 s**, decoupled from the display, on both platforms and
  in `web/` — exactly the reference's step. Rendering interpolates or simply draws the latest
  state; it never advances the simulation by the frame's delta.
- **Frame-rate independence is a correctness property.** A match plays identically at 60 and
  120 Hz; a test asserts it.
- **Determinism is seeded, never ambient.** Anything on the simulation path — AI decisions, shot
  aim noise, season results — draws from a seeded generator with the reference's algorithm. No
  wall-clock, no unseeded random, no device-dependent branch. Same seed + same inputs ⇒ same
  match on web, iOS and Android.
- **Simulation and rendering are separate layers.** The simulation knows nothing of the scene;
  the scene reads simulation state and events. This is what lets the vectors test one without
  the other.
- **Input latency is sacred.** Hold is registered on touch-down and release on touch-up, in the
  same frame. Never gate input behind an animation, a transition, or a network call.
- **Nothing blocks the next match.** No load, fetch, ad or dialog between a result and the next
  face-off (principle A2).

## Rendering *(pending 0003)*
- **One scene description per world, declared once.** A world's layout (what is placed where,
  its palette, its light and fog) is data in `shared/data/`, generated into both platforms; only
  the *drawing* of it is written twice.
- **Identical visuals are checked, not hoped for.** A parity rig renders the same scene state on
  both platforms side by side against the `web/` reference.
- **Assets are budgeted.** Draw calls, triangle counts, texture memory and audio banks have a
  stated ceiling per world; additions state their cost.

## Economy
- **One earn path, one spend path.** A single place computes what a match pays out and a single
  place debits a balance. No feature grants currency on the side (principle 14).
- **Balances are integers.** No floats for currency, anywhere, ever.
- **Every mutation is idempotent under retry.** A purchase or reward that replays must not
  double-apply; key it and check.
- **Tunable numbers live in one table, not in the code that reads them** — in `shared/data/`,
  generated into both apps.

## Payments
- **IAP through one chokepoint per platform.** Every purchase, restore and entitlement check
  resolves through a single wrapper — StoreKit 2 on iOS, Play Billing on Android — with
  on-device verification at minimum. No ad-hoc entitlement reads scattered through gameplay.
- **Purchases are per-store.** There is no account; the UI never implies a cross-platform restore.

## UI
- **SwiftUI and Compose for chrome**, over the 3D scene. The component foundation (tokens,
  primitives) is a pending `/architecture` decision — **decide it before the first menu screen
  is ported**, not after three have been hand-rolled.
- **Design tokens, not raw values.** Colours, spacing, radii and type sizes come from one token
  vocabulary declared in `shared/data/` and generated into both platforms.
- **The HUD never occludes the play.** Chrome lives at the edges; the rink stays readable at
  every supported aspect ratio.
- **Respect the system.** Safe areas, Reduce Motion (tames the goal camera and shake), the
  silent switch / media volume, and Dynamic Type / font scale in menus.
- **Interactive elements carry stable accessibility identifiers**, the same id on both
  platforms. Tests target ids, never visible text. Naming:
  `<surface>_<field>_field` / `<surface>_<action>_button` (e.g. `season_play_button`).

## Copy
- **The copy is declared once** in `shared/data/` and generated into `Localizable.xcstrings` and
  Android's `strings.xml`. Neither platform's resource file is edited by hand. The web build's
  `i18n.js` (German + English) is the starting corpus.
- **Terse, confident, sporty copy.** Short, loud, no hype-speak, no ticket numbers in
  user-facing text.
- **Prices and contents are legible before the tap** (principle 3).
- No emojis in the UI chrome or store metadata.

## Configuration
- **Never silently default a missing config value. Fail loud.** No `?? 100`, no `?: "id"`,
  no `|| fallback` for anything resolved from outside the source file that reads it —
  endpoints, product identifiers, secrets, signing keys, tunables, feature flags, level data.
- **What may have a default:** genuine optional behaviour (absence is a specified state), obvious
  test dummies in test code, and values derived from already-resolved config.
- **The failure says what is missing and where it comes from.** `"product id not set — add
  SLAP_PRODUCT_COINS to ios/Config.xcconfig"`, not `"config error"`.
- **A default that exists to make tests pass is a broken test.** Give the test its own config.

## Technical
- **LOC limit.** 500 lines of code is the maximum for app source files on either platform;
  test files may exceed it. More than that and we refactor.
- **iOS:** Swift 6, strict concurrency complete. The Xcode project is generated by XcodeGen from
  `ios/project.yml` and never committed.
- **Android:** Kotlin, Gradle Kotlin DSL with a version catalog, AGP's current stable line.
- **Identifiers are one-way doors at registration.** The bundle id / application id is chosen
  deliberately before the first App Store Connect / Play Console registration and never changed.
