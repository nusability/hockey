# Conventions

Stack-specific coding standards. Unlike `principles.md` (universal values), these are tied
to the tech in use and change with it.

The stack is **two stand-alone native implementations** (ADR 0001): Swift on iOS, Kotlin on
Android. **What draws the 3D scene and the 3D UI on each is ADR 0005** — until it is accepted,
entries about rendering are marked *(pending 0005)*.

## Greenfield — until the first store submission
Nothing has shipped, so **principle 13's exception is asleep**: there is no player whose record
could be broken, and our own save shapes may change freely without migrations.

It expires at the **first submission to either store**. From that build on, the exception wakes
up and a real player's record becomes untouchable: persistence is migrated, never assumed; a
record that fails to decode is preserved, never silently replaced. **Whoever ships first deletes
this section.**

What does *not* sleep: the rule against fabricating entitlements, and the fail-loud config rule.
Those apply from the first line.

## The web prototype (`web/`)
- **It is a gameplay prototype and nothing else** (ADR 0002). Read it for *what* the game does
  and *which numbers* it uses — once those are in the spec, the spec is the authority.
- **It is never a technical foundation.** Don't mirror its module layout, its class split, its
  world construction, its UI or its look. Design each app natively.
- **It stays no-build, vanilla JS + Three.js.** If a change wants a bundler or a package, that is
  the signal it belongs in the apps.
- **Never copy-paste or transliterate web code into an app.**

## Game loop & feel
- **The simulation steps at a fixed 1/120 s**, decoupled from the display, on both platforms
  (the prototype's step; its tuning depends on it). Rendering interpolates or simply draws the latest
  state; it never advances the simulation by the frame's delta.
- **Frame-rate independence is a correctness property.** A match plays identically at 60 and
  120 Hz; a test asserts it.
- **Determinism is seeded, never ambient.** Anything on the simulation path — AI decisions, shot
  aim noise, season results — draws from a seeded generator whose algorithm the spec names. No
  wall-clock, no unseeded random, no device-dependent branch. Same seed + same inputs ⇒ same
  match on iOS and Android.
- **Simulation and rendering are separate layers.** The simulation knows nothing of the scene;
  the scene reads simulation state and events. This is what lets the vectors test one without
  the other.
- **Input latency is sacred.** Hold is registered on touch-down and release on touch-up, in the
  same frame. Never gate input behind an animation, a transition, or a network call.
- **Nothing blocks the next match.** No load, fetch, ad or dialog between a result and the next
  face-off (principle A2).

## Rendering *(pending 0005)*
- **Shared assets where one file serves both** (`shared/assets/`: models, textures, sounds);
  the scene code that places and animates them is each platform's own.
- **"The same game to a player's eye" is checked, not hoped for.** A parity rig renders the same
  scene state on both platforms side by side.
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

## UI — it is made of 3D *(engine pending 0005)*
- **Menus, scoreboards and the HUD are objects in the 3D world**, built from primitives, so they
  can bounce, flip, squash, stretch and tumble. Goofy and whimsical is the brief; a standard
  widget look is a miss. Native widget toolkits are used only where the system requires them
  (purchase sheets, share sheets, the accessibility layer).
- **One small UI kit per platform, built once and reused.** A button, a panel, a scoreboard
  digit, a slider, a list — each a reusable 3D component with its animations, driven by the same
  **motion vocabulary** (named springs, durations, easings) declared in `shared/data/` so both
  platforms move the same way. No screen hand-rolls its own button.
- **Design tokens, not raw values.** Colours, sizes, motion curves and type come from one token
  vocabulary in `shared/data/`, generated into both platforms.
- **The HUD never occludes the play.** It lives at the edges; the pitch stays readable at every
  supported aspect ratio.
- **Accessibility is not optional because the UI is 3D.** Every interactive 3D element exposes
  an accessibility element (label, trait, frame) to VoiceOver / TalkBack; text scales with the
  system setting within a stated range; Reduce Motion replaces the whimsical motion with plain
  fades and tames the goal camera and shake.
- **Respect the system.** Safe areas, the silent switch / media volume.
- **Interactive elements — 3D ones included — carry stable accessibility identifiers**, the same
  id on both platforms. Tests target ids, never visible text. Naming:
  `<surface>_<field>_field` / `<surface>_<action>_button` (e.g. `season_play_button`).

## Copy
- **The copy is declared once** in `shared/data/` and generated into `Localizable.xcstrings` and
  Android's `strings.xml`. Neither platform's resource file is edited by hand.
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
  SMASH_PRODUCT_COINS to ios/Config.xcconfig"`, not `"config error"`.
- **A default that exists to make tests pass is a broken test.** Give the test its own config.

## Technical
- **LOC limit.** 500 lines of code is the maximum for app source files on either platform;
  test files may exceed it. More than that and we refactor.
- **iOS:** Swift 6, strict concurrency complete. The Xcode project is generated by XcodeGen from
  `ios/project.yml` and never committed.
- **Android:** Kotlin, Gradle Kotlin DSL with a version catalog, AGP's current stable line.
- **Identifiers are one-way doors at registration.** The bundle id / application id is chosen
  deliberately before the first App Store Connect / Play Console registration and never changed.
  Decided 2026-09-22: **`in.nann.smashhockey`** on both stores; display name **Smash Hockey 3D**.
