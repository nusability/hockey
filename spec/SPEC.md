<!--
This spec covers ONLY what we are building now. It is not a roadmap — everything not yet in
scope lives in Stori project SLAP as ideas/tasks. When we pick one up, we edit this file first;
the diff is the work (AGENTS.md).

Split axis (declared): CAPABILITY. When this file grows, split into spec/<capability>.md
(≤3 levels) + spec/cross-cutting/ for concerns spanning capabilities. Single file for now.

Rules: principles.md. Stack standards: conventions.md. Decisions: decisions/.
-->

Spec-Version: 0.2.0
Status: as-is — **the harness and the shape of the product, not yet a product.** Neither app
exists beyond an empty shell; the only playable version is the web **gameplay prototype** in
`web/` (ADR 0002), where the rules and numbers below were proven. The sections below state the game at
the level of its **capabilities** — what the player can do and what the game promises — and are
deepened section by section as each one is ported: a section is fleshed out to its full
contract (numbers, edge cases, invariants) in the same commit that ports it, and its delta row
is deleted in that commit.

# Smash Hockey 3D (iOS · Android) — Specification

## Overview
Smash Hockey 3D is a stylised, colourful 3D field-hockey game for phones — with one ice-hockey
world — played with **one touch**. Your players run on their own; you decide only **when to let
go of the ball**. A season of league and cup matches, eight training drills that teach the
control, and five worlds to play them in.

## What the web prototype contributes
`web/` explored **gameplay** and nothing else (ADR 0002). Binding rules:

- **The rules and the numbers carry over.** Physics constants, the orbit, pass and shot
  assistance, possession and stealing, AI behaviour, the tactics' effect, the drills and the
  season format are taken from the prototype **into this spec**, section by section, and from
  then on this spec is their only authority. A change to any of them is a spec change, not a
  tuning session.
- **Nothing else carries over.** The apps' worlds, look, UI, camera choreography and sound are
  designed for the apps and may depart from the prototype freely.
- **The UI is part of the 3D world** — menus, scoreboards and the HUD are animated objects in
  the scene, playful rather than standard. Specified per screen as each is designed.

## Platforms & scope
The game ships on **two platforms**, and **everything below binds both unless the
platform-delta table says otherwise**. There is one specification, not two; a platform is not
free to be different, only to be *late*, and lateness has to be written down.

- **iPhone**, portrait. **Android phone**, portrait. Minimum OS: **iOS 18**, **Android API 26**
  (proposed by the renderer decision, ADR 0005; confirmed when it is accepted).
- **iPad, tablets and landscape are out of scope.**
- **Two languages**, German and English, chosen by the device, never by a menu (§9).
- The two builds are **stand-alone implementations** sharing no executable code of ours — only
  config, some assets, and golden vectors both replay (ADR 0001).
- **Free-to-play with in-app purchases**, bound by the monetization ethics in `principles.md`.
  What is sold is not yet specified; nothing may be sold until it is.

### Platform deltas
The complete list of places the two platforms do not agree. **If a difference is not in this
table, it is a bug on whichever platform is wrong.** Each row is dated and is **permanent** (a
decision; changing it revisits an ADR) or **temporary** (a schedule fact naming the item that
deletes it — the goal for these is zero).

| Since | Kind | Delta |
|---|---|---|
| 2026-09-22 | **temporary** | **Neither app implements §1–§9 yet.** Both are empty shells that launch; the game is playable only in the `web/` prototype. Each section's port deletes its part of this row, on both platforms in the same commit, or splits it into a per-platform row naming the one that is behind. Closed by the porting items in Stori `SLAP`. |
| 2026-09-22 | **permanent** | **Purchases are per-store and per-device.** There is no account, so an entitlement bought on one store does not follow the player to the other. The game never implies otherwise: no affordance offers a cross-platform restore (ADR 0001). |

**The golden vectors** (`shared/vectors/`) are the one place the two simulations are checked
against each other, rather than merely written to the same text. None exist yet; they require
§4.

---

## Behavior / Capabilities

### 1. The pitch and the two sports
One engine plays two sports. **Field hockey** — grass, a ball, a near-square-cornered pitch — is
the default. **Ice hockey** — ice, a puck, rounded boards — is played in the Himalaya world. The
pitch is 60 m long and 30 m wide with a goal at each end; the player's team defends the near
goal and attacks the far one. Six a side: a goalie and five outfield players.

### 2. One-touch control
The whole of the player's input is **hold and release**.
- When one of the player's team has the ball, it **circles the carrier**, and an aim line shows
  where it would go if released now.
- **Touch and hold anywhere** keeps it circling; **lifting the last finger** sends it along the
  line from the carrier through the ball.
- Releasing near a team-mate **snaps to a pass**; near the goal, **snaps to a shot**. The aim line
  shows which (pass and shot colours). A release slightly after a target has passed still counts
  (a late-press grace), so timing does not have to be exact.
- The ball spins toward the most useful target first.
- A shot on goal always leaves at full power; a pass is faster the further it travels.
- Input is registered on touch-down and touch-up in the same frame; nothing gates it.

### 3. Automatic play
Everyone else — the player's other five, and the opponents — plays on their own: carriers run,
team-mates spread into support positions, defenders press and mark, goalies track the ball.
A defender who reaches the carrier **steals the ball** after a short contact. Behaviour is driven
by each team's **tactics** (§7) and rating.

### 4. The match
Three periods on a clock, face-offs at the start and after each goal, a goal celebration with a
**goal camera and slow motion**. Cup matches that end level go to sudden-death overtime. The
camera looks down the pitch from behind the player's goal and slides so the goal the play is
heading for stays in view.

**Determinism** *(to be specified in full with the first port task)*: a match is a pure function
of its seed, its teams and tactics, and the player's input tape, stepped at a fixed 1/120 s. Same
inputs ⇒ same match, on iOS and Android.

### 5. Training
Eight drills, unlocked one after another, each with its own world, a goal target and a time
limit: *First shot*, *Give and go*, *Beat the goalie*, *Cones*, *Moving cones*,
*Sleepy defenders*, *Under pressure*, *Scrimmage*. A drill is retried in one tap. Completion is
saved on the device.

### 6. The season
Eight fictional teams, each with a home world, play a **double round-robin league** (3 points
for a win, 1 for a draw) interleaved with a **knockout cup** (quarter-final, semi-final, final).
League matches are played in the home team's world. Matches the player's team is not in are
**simulated from team ratings**. A season ends with a champion and a cup winner; trophies carry
over into the next season. Quitting a season match forfeits it. Progress is saved on the device.
A **quick match** plays a friendly against a random opponent in a random world.

### 7. The coach's board
The player tunes their team's automatic play: *pressing*, *covering*, *push up*, *passing*,
*shooting*, a **formation** (balanced, defensive, attacking, …) and how strictly it is held
(*discipline*), plus period length and ball-spin speed. Each AI team has its own tactics.
Settings are saved on the device.

### 8. Worlds
Five worlds, each with its own scenery, sky, light, pitch surface, boundary and ball: **Magic
Wood**, **Deep Space**, **Desert Oasis**, **Himalaya** (ice), **Ocean World**. A demo match plays
behind the menus so the title screen is alive.

### 9. Language
German on devices set to German, English otherwise. Every user-facing string exists in both.

---

## Constraints & invariants
- **A0 before everything:** nothing may add latency between a finger and the ball, or make the
  aim line disagree with where the ball goes.
- **Nothing blocks the next match** (principle A2): no load, fetch, ad or dialog between a result
  and the next face-off, or between a failed drill and its retry.
- **Frame-rate independence:** a match plays identically at 60 and 120 Hz.
- **Player data is local and sacred once shipped** (principle 13, and `conventions.md`'s
  greenfield section until the first store submission).
