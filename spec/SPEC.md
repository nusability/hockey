<!--
This spec covers ONLY what we are building now. It is not a roadmap — everything not yet in
scope lives in Stori project SMASH as ideas/tasks. When we pick one up, we edit this file first;
the diff is the work (AGENTS.md).

Split axis (declared): CAPABILITY. When this file grows, split into spec/<capability>.md
(≤3 levels) + spec/cross-cutting/ for concerns spanning capabilities. Single file for now.

Rules: principles.md. Stack standards: conventions.md. Decisions: decisions/.
-->

Spec-Version: 0.18.0
Status: as-is — **the whole game, playable on both platforms.** The match, the drills, the
season, the career and the save (§1–§12, §15) run in each platform's core and agree to the last
bit, pinned by golden vectors; both apps put them on screen through the screens of §16 and keep
the save on the device (see the platform-delta table for what still differs). What this file holds is the complete
gameplay contract taken from the web prototype — the pitch, the one-touch control, the ball, the
automatic play, the match, the drills, the season and the coach's board, with every number the
prototype was tuned to — plus the one thing the prototype never had: **a career**, in which the
player creates their own team, once. From this version on the prototype is not
consulted for rules or numbers; this file is.

# Smash Hockey 3D (iOS · Android) — Specification

## Overview
Smash Hockey 3D is a stylised, colourful 3D field-hockey game for phones — with one ice-hockey
world — played with **one touch**. Your players run on their own; you decide only **when to let
go of the ball**. A career with a team of your own, a season of league and cup matches, eight training
drills that teach the control, and five worlds to play them in. The menus and scoreboards are
part of the 3D world too.

## What the web prototype contributed
`web/` explored **gameplay** and nothing else (ADR 0002). Its rules and tuned numbers are in this
file (§1–§13); from `spec-v0.3.0` on, this file is their only authority and the prototype is not
read for them. A change to any rule or number here is a spec change, not a tuning session — and
where it touches the simulation, it moves a golden vector (§4).

**Its art direction carries over too** (ADR 0006): the apps match the prototype's look — flat,
saturated Lambert/toon shading under a hemisphere light and a sun, no fog, players drawn as the
prototype's disks, and its five worlds re-authored to match. Its code does not carry over. The
UI, camera choreography and sound are designed for the apps. **The UI is part of the 3D world** — menus, scoreboards and the HUD are animated
objects in the scene, playful rather than standard; each screen is specified here when it is
designed.

## Platforms & scope
The game ships on **two platforms**, and **everything below binds both unless the
platform-delta table says otherwise**. There is one specification, not two; a platform is not
free to be different, only to be *late*, and lateness has to be written down.

- **iPhone**, portrait. **Android phone**, portrait. Minimum OS: **iOS 18**, **Android API 26**
  (set by the renderer decision, ADR 0005).
- **iPad, tablets and landscape are out of scope.**
- **Two languages**, German and English, chosen by the device, never by a menu (§14).
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
| 2026-09-22 | **permanent** | **The two look the same to a player's eye, not to the pixel.** Geometry, textures, text, layout, motion and — since ADR 0006 — the shading itself are identical by construction: both platforms compute the same flat Lambert/toon formula in their own unlit materials, with no engine lighting or tone mapping. What remains different is how two engines rasterise and anti-alias. A difference a player would notice is still a bug. |
| 2026-09-22 | **permanent** | **iOS renders at 60 Hz on ProMotion iPhones, Android at the display's rate up to what it holds.** RealityKit's view offers no frame-rate control (ADR 0005). The simulation is unaffected — it runs in fixed steps (§4). |
| 2026-09-22 | **permanent** | **Purchases are per-store and per-device.** There is no account, so an entitlement bought on one store does not follow the player to the other. The game never implies otherwise: no affordance offers a cross-platform restore (ADR 0001). |

**The golden vectors** (`shared/vectors/`) are the one place the two simulations are checked
against each other rather than merely written to the same text (§4.7). Live: the math (§4.3–§4.4), the
match — drills, full matches on both sports, a scripted player tape, a cup match into sudden-death
(§4–§8, §10) — and the season, career and save (§2.2, §11, §15). iOS recorded all of them; Android
replays every one exactly.

---

## Behavior / Capabilities

Units are metres and seconds; angles are radians. The pitch lies in the X–Z plane, **Z along the
pitch, X across it**. An angle `a` names the direction `(sin a, cos a)` in (x, z), so `0` points
down +Z. "Team 0" is the player's team, which **always defends the near goal (−Z) and attacks
+Z**, home or away; "team 1" is the opponent.

### 1. The pitch and the two sports
One engine plays two sports on one pitch.

| Pitch | Value |
|---|---|
| Length × width | 60 × 30 (half-extents 30 × 15) |
| Goal lines | z = ±26 |
| Blue lines (the ice sport only, §8.9) | z = ±9.5 — a team's **attacking zone** is beyond the blue line it attacks |
| Goal mouth width × depth | 6.0 × 1.6 — the net occupies the box behind the line (for the ball, the net's frame is 0.15 larger on every outer side: 6.3 × 1.75) |
| Goal crease radius (keep-out, §7) | 3.2 |
| Boundary | a rounded rectangle at the half-extents, corner radius per sport |

| Sport | Corner radius | Ball friction (m/s²) | Ball drag (1/s) | Wall restitution | Ball | Offside |
|---|---|---|---|---|---|---|
| **Field hockey** (default) | 2.0 | 0.9 | 0.3 | 0.6 | a ball, radius 0.36 | no |
| **Ice hockey** (Himalaya) | 8.5 | 0.45 | 0.2 | 0.72 | a puck, radius 0.36 | **yes** (§8.9) |

**Offside is the one rule the two sports do not share.** Field hockey has had none since 1998, so
the four field worlds play without it; the ice world plays with it (§8.9). Everything else in this
specification is the same game on both.

Each side has **six players**: a goalie and five outfield players. Face-off spots: the centre
(0, 0); four neutral spots (±7, ±7); four end spots (±7, ±20).

### 2. Teams and the career

#### 2.1 The clubs
Eight fictional clubs, each with a home world, a rating and its own tactics (§12).

| Club | Short | Home world | Rating | Tactics (differences from the defaults) |
|---|---|---|---|---|
| Moss Foxes | MOS | Magic Wood | 76 | — |
| Glow Owls | GLO | Magic Wood | 80 | pressing 0.65, covering 0.65 |
| Nebula Narwhals | NEB | Deep Space | 82 | passing 0.8, push up 0.7 |
| Rocket Lynx | ROC | Deep Space | 85 | shooting 0.85, push up 0.75, pressing 0.7 |
| Dune Scorpions | DUN | Desert Oasis | 78 | pressing 0.8, shooting 0.7 |
| Mirage Falcons | MIR | Desert Oasis | 72 | passing 0.4, shooting 0.4, covering 0.7 |
| Glacier Wolves | GLW | Himalaya | 70 | covering 0.85, push up 0.3, pressing 0.3 |
| Coral Kraken | COR | Ocean World | 75 | passing 0.7, covering 0.4 |

Names are localized (English/German, §14). Each club has a primary and secondary kit colour. The
clubs are the career's opponents: the player never plays as one of them (§2.2).

**A rating is the team's skill.** It sets outfield top speed (§3) and `skill = clamp((rating −
60) / 30, 0, 1)`, which scales AI release accuracy, shot power and goalie play (§7), and it
drives simulated results (§11).

#### 2.2 The career — the player's own team, for good
The player's first act is to **create their team**, once. The eight clubs are opponents only:
picking one of them would be no choice at all, because one of them is always the strongest.

The player enters:

- a **name**, 2–16 characters, counted as Unicode code points once leading and trailing spaces
  are dropped (the name is kept without them);
- a **short code**, three capital letters A–Z, never equal to a club's (Glacier Wolves'
  included). It is derived from the name and editable. The derivation takes the name's letters
  A–Z (accents dropped, case ignored, anything else skipped): the first, the second and the first
  later letter that makes a code no club has; failing that, the first two letters — as many as
  there are — padded with X (no club's code has one);
- a **kit**: a primary and secondary colour from a curated palette of twelve pairs
  (`shared/data/`) — the primary chosen from the pairs' primaries, the secondary from their
  secondaries. No palette primary equals a club's primary, so the player's team never clashes with
  an opponent;
- a **home world**, one of the five (§13).

A draft that breaks any of these rules cannot be confirmed; every rule it breaks is named.

The team's **rating is fixed at 77**, the league average (the mean of the eight clubs' ratings,
rounded). Its tactics are the defaults (§12): creating the team sets the coach's board's pressing,
covering, push up and discipline to the default values — formation, period length and ball spin
stay as the player set them — and "Reset" there restores the defaults. **It replaces the weakest club, Glacier Wolves, in the
league and cup**, which keep eight teams. Glacier Wolves still exist as an opponent outside the
season (quick match, §11.5).

**The team can be changed, but never swapped.** Its name, short code, kit and home world are
editable for as long as the career lasts (§16.1), under exactly the rules above — a change that
breaks one of them cannot be confirmed. What a change never touches is *which* team it is: the
season's fixtures, results, table and cup name the team, not its name or its colours, so renaming
or re-kitting mid-season moves nothing in it, and the trophy counts stay. A new kit is worn at
once wherever the team is drawn — the table row's chip, the fixture card, the result, the players
on the pitch — and a new home world is where its next home fixture is played. Its rating does not
change (it never does, §"Out of scope").

The team holds for every season that follows. There is no switching and no second team:
**starting over** is a deliberate, confirmed act that ends the career, its season and its
trophies. Training progress (§10) survives it, because it records the player's skill rather than
the team's.

Creating the team is the step before the first season; the rest of the game (training, quick
match) is available before it.

### 3. Players and formations
| Player | Value |
|---|---|
| Outfield radius | 0.8 |
| Goalie radius | 1.0 |
| Outfield top speed | `6.2 + (rating − 60) × 0.045`, times the drill's speed factor (§10) |
| Goalie top speed | 4.8, times the drill's speed factor |
| Acceleration | velocity approaches the wanted velocity by `1 − exp(−(38/8)·dt)` per step |
| Wanted speed toward a target at distance d | `min(top speed, 6·d)`; none within 0.02 |
| Turning | facing turns toward the velocity by `angleDiff × min(1, 14·dt)` above 0.6 m/s; goalies always face up the pitch |
| Player–player contact | one pass over every pair (i, j > i) in roster order, positions updated in place: overlapping players are separated (split evenly, or wholly onto the active one if the other is a dummy), and each active one gets half the pair's closing speed along the contact normal removed |
| Boundary | players stay inside the boundary and outside both nets; they may walk round and behind a net |

A lineup has roles: **G** goalie, **D** defender, **F** forward, and in drills **O** — a static
or patrolling dummy that blocks but never takes the ball.

**Formations** (the player's team uses the coach's choice; every AI team plays *balanced*). Home
spots are for a team attacking +Z; team 1's are mirrored in both X and Z. The goalie is at
(0, −25) in every formation.

| Formation | Defenders (x, z) | Forwards (x, z) |
|---|---|---|
| **2-3 Balanced** (default) | (−6.5, −17) (6.5, −17) | (−9, −5) (0, −3) (9, −5) |
| **3-2 Defensive** | (−8.5, −17) (0, −20) (8.5, −17) | (−6, −3) (6, −3) |
| **1-4 Attacking** | (0, −18) | (−11, −6) (−4, 0) (4, 0) (11, −6) |
| **2-1-2 Diamond** | (−6, −17) (6, −17) | (0, −9) (−8, −1) (8, −1) |
| **2-3 Wide** | (−7, −17) (7, −17) | (−12.5, −4) (0, −7) (12.5, −4) |

The **roster order** is goalie, then the formation's players in the order listed: team 0's roster
first, then team 1's. Every "for each player" in this spec runs in roster order.

### 4. Time and determinism

#### 4.1 The step
The simulation advances in **fixed steps of 1/240 s**, never by the display's frame time. A
match is advanced in **ticks of 1/120 s**, two steps each; input is applied at tick boundaries:
every finger edge since the last tick is applied, in order, before the tick's first step — so a
tap shorter than a tick still lifts. **Match time** advances by one step at the start of each
step. The match clock, every timer and every rule below is measured in match time.

#### 4.2 Presentation time
Real time drives the simulation through a **time scale** that only presentation sets (§8.6's
slow motion). The time scale changes how many ticks run per real second, never what a tick does:
a match is the same sequence of ticks at any time scale and any display rate. Real-time gaps
longer than 0.1 s are clamped to 0.1 s. Real time × time scale is counted in whole units of
1/(120 × 10⁹) s, so frames of 1/60 s and pairs of 1/120 s add up to exactly the same ticks.

#### 4.3 Randomness
Every random draw on the simulation path comes from a **seeded SplitMix64 stream**:

```
state ← state + 0x9E3779B97F4A7C15            (mod 2^64)
z ← state
z ← (z xor (z >> 30)) × 0xBF58476D1CE4E5B9     (mod 2^64)
z ← (z xor (z >> 27)) × 0x94D049BB133111EB     (mod 2^64)
out ← z xor (z >> 31)
uniform ← (out >> 11) × 2^−53                  a double in [0, 1)
```

- **Each match has its own stream**, seeded when it starts. **Each season has its own stream**,
  seeded when it is created and stored with it (§15), which schedules fixtures and simulates
  results (§11).
- Draws happen in the order the rules are evaluated: per step, team 0's AI then team 1's; within
  a team, players in roster order. The draw sites, each where its rule runs: **the match's
  temperament** (§7.10, three draws, at setup, before anything else — a drill draws none); an
  outfield player's
  first re-think (§7, at setup) and each re-think period; a face-off's drop (§8.2); an AI
  carrier's re-think period, shot chance, `noise(0.8)` per pass candidate in roster order, pass
  chance and shot power (§7.6); a defender's marking chance (§7.3, drawn only when there is
  someone to mark); a goalie's `noise(0.5)` per team-mate (§7.8); a pass's aim noise, x then z;
  a shot's side (only with no goalie), then its 25 % pull, then its aim noise (§5.4); and
  **the referee's eye** (§8.9, the ice sport only), one draw at the moment a zone entry is found
  offside, after both teams' play that step — it is the only draw offside adds, and the only one
  that is not made where a player is thinking.
- `noise(s)` is `(u₁ + u₂ + u₃ − 1.5) × s` from three consecutive draws.
- Presentation (camera shake, particles, scenery) never draws from these streams.

#### 4.4 Arithmetic
The two platforms compute the same match to the last bit, so the simulation uses only operations
IEEE-754 double precision defines exactly — `+ − × ÷` and `sqrt` — evaluated in the order this
spec writes them, **never fused** into a multiply-add. Lengths are `sqrt(x² + z²)`, never a
library `hypot`. `sin`, `cos`, `atan2` and `exp` are **not** the platform's: each is a fixed
approximation (range reduction plus polynomial, absolute error ≤ 1e-9 on the simulation's input
ranges) whose constants are declared once in `shared/data/` and implemented identically on both
platforms, and pinned bit-for-bit by golden vectors (`shared/vectors/math/`). Edge cases are part of
the contract: `atan2(±0, +x) = ±0`, `atan2(0, 0) = 0`, `atan2(−0, −x) = +π`; `sin` and `cos` accept
arguments up to ±1e6 (a patrolling dummy's phase grows with match time) and fail loudly beyond.
`min`, `max` and `clamp` return their first argument on a tie (so a signed zero is the same on
both platforms). Three numerical guards, declared with the rules (`shared/data/rules.toml`
`[sim]`), are part of the arithmetic: two bodies closer than 1e-4 are not pushed apart (they have
no contact normal); a vector shorter than 1e-6 has no direction (a release along it does
nothing); a target within 1e-3 of what it keeps clear of is pushed along +x.

#### 4.5 What a step does, in order
1. Match time advances.
2. The state machine (§8.1): timers count down; a face-off that expires starts play with its
   drop draw; any other expired state moves on.
3. In play: the clock counts down; at zero the period, match or drill ends (§8.3, §8.4, §10) —
   the rest of this step still runs as in play, but a goal, a whistle or a drill's interruption
   only happens while the state is play, so none does in that step.
4. In play: the match's tilt (§7.10), then the alert window (§7.9), then the loose-ball timer
   (§7.1), then team 0's automatic play, then team 1's (§7).
5. Every player moves (§3), in roster order; pickup cooldowns count down here, in every state.
6. Player–player contact (§3), then each player but a dummy is kept inside the boundary and out
   of the nets.
7. The ball: in play it moves (§6); otherwise a carried ball follows its carrier (orbiting only
   during a drill's "get ready"), a ball in the net after a goal rolls on (§8.1), and a loose ball
   stays put.
8. In play: offside (§8.9, the ice sport only), then the dead-ball timer (§6.5).

#### 4.6 What a restart resets
Every face-off and drill reset clears: the ball's carrier, velocity, last touches, assist and
pending release; and for every player, velocity, target, pickup cooldown, hold time, decision,
mark, expected pass, steal contact, challenge commitment, the loose-ball, dead-ball and alert
timers, the crossing being watched and both teams' zone state (§7.1, §6.5, §7.9, §8.9). Think timers (§7), the orbit angle and
the time of the last release (§7.8) are not reset.

#### 4.7 Golden vectors
A **vector** is `(seed, sport, teams and ratings, tactics and formations, the player's input as
(tick, hold | release) events, and the sampled state)`: for every sampled tick, the match state
(§8), period, overtime, clock, score, the match stream's position, each player's position,
velocity and facing, and the ball's position, velocity, carrier, orbit angle and direction — and
every event (§8, §10) with the tick it happened in. An input's tick is the number of ticks run
when it is applied. Every double is written as the hex of its bits. Both platforms replay every
vector and must reproduce every sample and every event exactly. A vector is recorded by the first
platform to implement a rule, checked against this spec and by playing it, and **re-recording one
requires a spec change in the same commit**. The corpus is `shared/vectors/match/`.

### 5. One-touch control

#### 5.1 The orbit
While a player holds the ball it **circles them** at radius 1.5, one revolution per **orbit
period**, in either direction. The ball's position is `carrier + 1.5 × (sin orbit, cos orbit)`,
its velocity is the carrier's, and the orbit angle is kept in (−π, π]. The orbit period is one
value per match, the same for **every** carrier and for the challengers' lead (§7.2): the
player's ball-spin setting (§12) in matches they play, 2.0 s in the demo.

When a player wins the ball, the orbit angle starts where the ball was, and the direction is
chosen so the ball **turns toward the most useful target first**:

- the goal, when the carrier is within 24 of the goal they attack and `|x| < 13`;
- otherwise the best team-mate — outfield, at least 3 away — scoring highest on
  `openness + 0.4 × progress − 0.5 × max(0, distance − 18)`, where `openness` is the distance to
  their nearest opponent (capped at 9) and `progress` is how far up the pitch they are from the
  carrier.

The ball turns the shorter way toward that target: the positive (increasing-angle) direction
when the target is at a non-negative angle difference, or when there is no target.

#### 5.2 What a release would snap to
At any orbit angle, a release **snaps**:

- **to a pass** to the outfield team-mate whose lead position — their position plus `0.8 × velocity
  × t`, with `t = distance / max(14, 11 + 0.55 × distance)` — lies within **0.36 rad** of the
  orbit angle, the closest in angle winning. **A team-mate who is offside is not a candidate**
  (§8.9, the ice sport only): the arrow simply does not go green for them, and the release that
  would have been a pass to them is free instead. The arrow never promises a ball that the whistle
  would take back (A0), and the apps mark the team-mate so the player can see why (§8.9, §16.4);
- **to a shot** when the goal centre lies within the goal window of the orbit angle — **0.40 rad,
  widened by up to 0.30 as the carrier closes from 14 to 0 away**. The goal wins over a pass when
  its angle is less than 0.9 × the pass's, or the carrier is within 9 of goal.

**The aim arrow** shows the direction and what a release now would snap to — the prototype's arrow,
and only round **the player's own carrier** (with the white ring the ball circles on). It stands on
the carrier's centre and points along the orbit angle, out through the ball — never at the target —
so what it shows is where the ball is going round, and its colour says what letting go now would do:
**yellow** free, **green** a pass, **pink** a shot. It is a tapered ribbon printed with chevrons that
scroll outward, over a soft glow, ending in a notched arrowhead; snapped, it pulses. Its length says
how far the release would carry: free, 16; a pass, to just short of the receiver; a shot, to just
short of the goal — always stopping short of the boards (1.2 and the orbit radius before them) and
never shorter than 2.5. When a snap begins a **lock-on marker** fades in within 0.08 s: for a pass the
receiver's pulsing ring and a faint dotted line in the pass colour from the arrowhead to where the
pass would go (§5.4's lead point); for a shot a pink glow across the goal mouth. A snap **begins**
whenever what a release would snap to changes, and whenever the ball changes hands — a new carrier
is a new snap even when it aims at the same place. The arrow and its marker are shown only while
the player's own carrier has the ball in play or at the ready, and they come back, fading in from
nothing, the moment that is true again after a whistle, a goal or a face-off. Every measure and
colour is declared once for both apps (`shared/data/presentation.toml` `[aim]`).

#### 5.3 The player's release
The ball circles by itself; **touching and holding anywhere** is the player saying "not yet", and
**lifting the last finger** releases it. Only the player's outfield carriers wait for the player;
the player's goalie plays by itself (§7.8). A release only counts during play (§8).

When the finger lifts:

1. If the ball would snap to something **now**, it goes there.
2. Otherwise, if it **would have** snapped at any of the four instants 0.0625, 0.125, 0.1875,
   0.25 s ago (the late grace, 0.25 s), it goes to the first of those it finds. "Would have" winds
   the orbit angle back to that instant; everyone else is taken where they are now.
3. Otherwise, if it **will** snap within 0.05, 0.10, 0.15, 0.20 or 0.25 s from now (the orbit
   wound forward the same way), the release is **held pending**: it fires the moment the ball
   snaps, or — if nothing snaps — unassisted 0.06 s after that instant. It is checked each step,
   after the orbit moves and before the steal check (§6.1). A pending release is cancelled only
   if the player loses the ball; a new touch does not cancel it, and a new lift is judged afresh.
4. Otherwise it leaves unassisted along the orbit direction.

#### 5.4 How the ball leaves
Every release leaves **from the orbit point**; the direction of an aimed release is measured
**from the carrier's position** to its aim point.

- **A pass** travels at `clamp(14 + 0.85 × distance, 14, 30)` toward the receiver's lead position
  (as in §5.2, at that speed), plus `noise(1.6 × (1.15 − accuracy))` on each axis. The receiver
  re-thinks at once and **expects the pass**: an expectation of 1.6 that drops by 0.2 at each of
  their re-thinks (§7).
- **A shot** travels at **30** toward the far side of the goal from the goalie — `±(3.0 − 0.85)`
  in x: −x when the goalie's x > 0, else +x (a random side if there is no goalie: −x on a draw
  below 0.5) — pulled to 30 % of that on a 25 % draw, plus `noise(1.5 × (1.2 − accuracy))`, at
  the goal line it attacks. **Against a defence on alert (§7.9) the corner goes away with
  distance**: before the draws, the `±(3.0 − 0.85)` is multiplied by
  `clamp((20 − d) / 10, 0, 1)`, `d` the carrier's distance to the goal centre — a shot from 20 out goes straight down the middle at the keeper, one from 10 in still
  picks its side in full. Nothing else about the shot changes: not its speed, not its noise, and
  not what the aim arrow (§5.2) showed — the arrow never promised a corner.
- **An unassisted release** travels at **24** along the orbit direction.
- The player's own releases have accuracy 1. The ball also inherits 20 % of the carrier's
  velocity.
- A release point with `|z| > 25.7` and `|x| < 3.6` (at either goal) is moved back to the
  carrier's x and z, z kept within 25.5.
- The releaser cannot take the ball back for 0.45 s. A release makes the releaser the ball's last
  touch and last releaser (§8.5).

### 6. The ball

#### 6.1 Carried
A carried ball sits on the orbit (§5.1) and moves with the carrier. A steal check runs every
step it is carried (§6.4).

#### 6.2 Loose
A loose ball, each step, in this order:

- **Slowing:** with `v` the speed before slowing, the speed drops by `min(v, friction·dt +
  v·drag·dt)` (§1); then, if `v > 30`, the velocity is also scaled by `30 / v`.
- **Moving:** position += velocity · dt.
- **The boundary** reflects it with the sport's wall restitution; an impact faster than 4 m/s is
  a board hit.
- **The posts** (at x = ±3.0 on each goal line, radius 0.18) reflect it with a lively 0.8 restitution.
- **A goal** is scored when the ball, having been in front of the line (by at least −r/2) and
  within `3.0 − 0.3r` of the centre, crosses the goal line by more than half its radius — both
  judged on its position before and after this step's move, while it is inside the net's frame.
  From any other side the net (§1) is solid: the ball is pushed out through whichever is nearer,
  its side or its back, and that velocity component reflected with the wall restitution. A goal
  ends the step's ball update. After moving, the ball meets the nets first (team 0's, then team
  1's), then the posts, then the boundary, then the players.
- **Players**, in roster order, deflect it when it overlaps them — pushed out to touching, and
  its velocity relative to them, when closing, reflected with restitution 0.85 (a goalie smothers
  it with 0.35, which is a save; a dummy's touch is a block). A deflection is not a touch.

#### 6.3 Picking it up
After all deflections, of the players who may pick up (not dummies), the nearest (the first in
roster order on a tie) within reach
— **1.45** for an outfield player, `radius + ball radius + 0.35` for a goalie — with no pickup
cooldown takes it, **if** the ball's speed relative to them, measured after the deflections, is
below a limit: **9** for a goalie; **27** when their own team touched the ball last; **17**
otherwise. A faster ball becomes theirs as the last touch without being taken — so on the next
step, still in reach, their limit is 27.

#### 6.4 Stealing it
A carrier is safe for **0.45 s** after winning the ball. After that, each opponent in roster
order who can steal (not a dummy) and has no pickup cooldown — others neither gain nor lose
contact — builds contact time while within reach of the **ball** (0.9 for an outfield player,
`radius + 0.3` for a goalie), and loses it twice as fast out of reach. The first to reach
**0.18 s** takes it. A carrier who loses the ball cannot take it back for 0.6 s.

A goalie carrying the ball cannot be stolen from.

#### 6.5 A ball nobody collects
If the ball is loose and slower than 2.5 for **8 s**, play is whistled dead: the ball slows to 20 %
of its speed, and after **1.4 s** play restarts with a face-off at the spot nearest the ball when
the whistle went (centre, then neutral, then end spots on a tie). In a drill, the drill is
interrupted instead (§10), the ball left as it is.

### 7. Automatic play
Everyone except the player's release decision is automatic, and both teams run the same rules
with their own tactics (§12) and rating. Wherever a rule below reads a tactic it reads the team's
**effective** tactic — the board's number with §7.10's tilt applied, which is the board's number
exactly whenever the score is level or within one goal. Outfield players re-think every **0.12 + 0.1u** s
(u a draw; each outfield player's first re-think falls at `0.2u`, drawn in roster order when the
match is set up); carriers and goalies think every step. Every player's think timer counts down
each step in play; a carrier keeps its own (§7.6). Dummies do not think. Wherever §5–§7 pick
the nearest, best, lowest or most of something, a tie goes to the first in roster order (or in
slot order, §7.4). An opponent means anyone on the other team — goalie and dummies included —
unless a rule says otherwise.

#### 7.1 Loose ball
- A player **expecting a pass** heads for the point on the ball's line of travel nearest them,
  ahead of the ball only (the ball itself when it is slower than 2). The expectation drops by 0.2
  at the start of each re-think, before it is looked at; while it stays above zero the player is
  a chaser (§7.5), whatever their rank.
- Otherwise the outfield players ranked by distance to the ball — the pass receiver counts in
  the ranking — chase where the ball will be: its position plus `0.7 × velocity × t`, `t =
  clamp(distance / max(top speed, 1), 0, 1.2)`. One chases; **two** when pressing > 0.75, the
  nearest is more than 9 away, or the ball has been loose for more than 1.5 s of play (the
  loose-ball timer runs only in play, resets whenever someone carries and at restarts, §4.6).
- Everyone else takes a support position (§7.4).
- A chase target less than 0.4 in front of a goal line (or behind it) and within 4.6 of the
  centre, while the chaser is more than 0.4 in front of that line, is replaced by the net's
  corner waypoint `(±4.6, 0.6 in front of the line)` on the chaser's side of x (+ at x = 0).
  Team 0's goal line is checked first. This applies to both kinds of loose-ball chase above.

#### 7.2 The other team has it — challengers
Up to **2** players go in for the ball — **3** when pressing > 0.75. Candidates are those already
committed (a challenger stays committed for 0.7 s, renewed each step it is chosen); a player **goal-side** of the carrier
(at least 0.5 nearer their own goal than the carrier, within 7 of the carrier's route to it) within **10** of
the ball; and anyone else within the press range `(10 + 22 × pressing) × (1 − 0.35 × discipline)`
of it. Committed players come first,
then goal-side ones, then the nearest. A challenger heads for **where the ball will be 0.3 s
ahead on its orbit** plus the carrier's travel, not for the carrier.

#### 7.3 The other team has it — defending
Everyone else picks the most dangerous opponent outfield player, other than the carrier, that no
team-mate is currently marking (lowest `distance − 0.6 × depth toward their own goal`). With
probability `0.35 + 0.6 × covering` they **mark** them, standing `1.4 + 3 × (1 − covering)`
toward their own goal from them; otherwise they clear their mark and hold their formation spot
(§7.5, k = 0.35), moved to 1.5 goal-side of the ball when it is less than 1 goal-side of it. A
player's mark is also cleared whenever they are not defending (chasing, challenging, supporting).

#### 7.4 Support — own ball, or loose and not chasing
Six **support slots** relative to the ball (or its carrier — the *reference*), for a team
attacking +Z. A *mirror* slot's x is absolute, measured from the pitch's centre line, and
multiplied by −1 when the reference's x ≥ 0 — so positive-x mirror slots land on the far side of
the ball and negative-x ones on its side. The others are x-offsets from the reference, the same
for both teams. Every slot's z is an offset from the reference, toward the goal the team attacks:

| Slot | x | z | Role | Mirror |
|---|---|---|---|---|
| far post / far side, ahead | 10 | 6 | F | yes |
| near-side width, level | −9 | 2 | F | yes |
| highest player, beyond the defence | 2 | 14 | F | no |
| wide outlet behind | −9 | −8 | D | yes |
| opposite outlet | 9 | −9 | D | yes |
| back of the defence | 0 | −15 | D | no |

Slot depth is scaled by `0.8 + 0.4 × push up`. Slots are kept 2.5 inside the sidelines, between 3
short of their own goal line and 5 short of the opponent's; a slot within 7 of the goal they
attack is moved sideways to `|x| ≥ 7`; then it is pushed 7.5 from the ball. The team's outfield
players other than the carrier — chasers included — take slots **greedily in roster order**, each
the nearest free slot, a role mismatch counting as 8 extra metres. A player whose slot has an
opponent within 3.4 shifts 3.5 across and 1.5 along, away from the nearest one (the unit vector
from them, its x scaled by 3.5 and its z by 1.5).

**The offer.** A team that carries the ball inside **26** of the goal it attacks (carrier to goal
centre) has one team-mate stop holding shape and **stand to receive**, so the carrier is never
alone in front of goal. The *highest player* slot becomes the **offer**, and it is given to one
named player rather than shared out:

- **Who.** The **forward nearest the goal the team attacks**, other than the carrier — its other
  outfield players when it has no second forward. It is chosen before the greedy pass and takes
  the offer whatever the greedy cost would have said; the other five slots are then shared out as
  above among the rest.
- **Where.** `x = 7.0` on **the offer-taker's own side** of the pitch (`+7.0` at `x ≥ 0`, else
  `−7.0`) — their own side, never the carrier's, so the spot cannot change sides under them as the
  carrier weaves — and **9 short of the goal line they attack**. That is 11.4 from the goal centre:
  a shooting position, clearly wide of the goalie's cover (§7.8 keeps a goalie within ±3.4 in x),
  and not on the goal line.
- **The band.** The spot is then brought onto the **8–15** band from the carrier along the line
  from the carrier to it (a vector shorter than the clear epsilon points along +x, §4.4): far
  enough that the pass is a real one, near enough that the receiver can shoot after it. Finally it
  is kept 2.5 inside the sidelines.
- **It keeps its shape.** The offer is not moved sideways out of the goal zone, not pushed 7.5 from
  the ball, and its taker's target does not go through §7.5 — like a chaser's, it is only clamped
  to `|x| ≤ 13.8`, `|z| ≤ 28.8`. Standing to receive *is* the shape.

**Holding the line** (the ice sport only, §8.9). Before any of §7.5's shaping, a player who is not
the carrier has their target pulled back to **0.8 short of the blue line they attack** whenever the
target lies beyond that point and the ball is **still 0.2 short of the line**. It applies to
supporters, to the offer-taker and to chasers alike, and only while the team is not
defending — a defender in their own half is never at risk. This is the whole of the AI's respect
for the rule in its movement, and it is deliberately *not* a guarantee: a target held 0.8 short of
the line does not stop a skater at speed from carrying 0.6 past it, a chaser committed to a loose
ball that is already in the zone is never held at all, and a ball that leaves the zone and is sent
straight back in finds whoever was still deep. **The stray run falls out of that slack**; no draw
is made for it, and none is declared in §4.3.

#### 7.5 Shape, spacing and discipline
For every player not chasing:
- **Formation spot** (used when marking is skipped): home spot moved toward the ball by
  `(D 0.35 | F 0.55) × (0.6 + 0.8 × push up) × 2 × k` along the pitch (at most 0.9 of the way;
  k = 0.35 defending, 0.7 supporting) and `(D 0.3 | F 0.4)` across. A defender never ends up
  more than 2 ahead of the ball in their own half.
- **Discipline** blends the target toward the player's **zone** by `discipline` (0 free, 1
  strict): the zone is the home spot moved toward the ball by `(D 0.35 | F 0.5) × (0.7 + 0.6 ×
  push up)` along the pitch and 0.22 across.
- Then the target is pushed **7.5 from the ball** (5.5 when defending),
- then **6 from every outfield team-mate's current position** (the carrier included), each in
  turn in roster order, when in possession, 3.5 otherwise,
- then out of their own **crease** — first moved to at least 2.2 in front of their own goal line,
  then out to at least `3.2 + 1.2` from their goal centre (along the line from it),
- and finally — for chasers too — clamped to `|x| ≤ 13.8`, `|z| ≤ 28.8`.

#### 7.6 An AI carrier's decision
An AI carrier decides after holding for 0.15 s, re-thinking every `0.2 + 0.15u` s until it has a
decision (the think timer keeps being drawn every period, decision or not). A **threat** is the
nearest opponent who can steal, goalies excluded (with none, no threat condition below holds).
The carrier is **forced** when a threat is within 2.6 or it has held for 3.5 s.

- **Shoot** when within `11 + 11 × shooting` of goal, `|x| < 11`, and no non-goalie opponent
  (dummies included) is within 1.3 of the line to the goal centre and nearer than the goal — or
  within 6 — with probability `0.35 + 0.5 × shooting`, or
  always when forced.
- Else **pass** to the best team-mate between 3 and 26 away, scored by
  `1.2 × openness (≤ 6) + 0.35 × progress − 6 if the lane is blocked (1.4 wide) − 10 if the ball
  would cross within 5 of their own goal + 0.3 × (progress + 6) when more than 6 backward −
  0.4 × (distance − 18) beyond 18 − 8 if they are offside (§8.9, the ice sport only) +
  noise(0.8)`, if that best score exceeds 3.5, with probability
  `0.3 × passing + 0.45 if threatened within 4 + 0.3 if held over 2 s`, or always when forced.
- **Forced**: pass to the best-scoring team-mate between 3 and 26 away whatever the score; with
  none in range, **shoot** within 24 of goal, else **clear** (release unassisted).

It then **waits for the orbit to line up** with its aim — the goal centre for a shot or a
clear; for a pass the receiver's lead position with `t = distance / clamp(11 + 0.55 × distance,
14, 24)` — within `0.22 + 0.12 × (1 − skill)` (+0.5 when the threat is within 2.2). The AI
never releases through the player's snap-and-grace rules (§5.3). A pass uses accuracy `0.55 + 0.5 × skill`;
a shot uses the same accuracy and power `20 + 6 × skill + 2u`.

#### 7.7 Every carrier's movement
Every carrier — the player's too — skates at a point 6 ahead toward the goal they attack. It
swerves 5 to the side away from the nearest opponent who can steal, and 2 straight away from
them, when that opponent is within 6. It steers `1.5 × (4.5 − d)` away from any dummy within 4.5.
Within 8.5 of goal it ignores the swerve and dummies and aims instead at `x + 4 × s` (s = toward
the centre when `|x| > 6`, else away from it) and `z − (8.5 − d) × 1.2 × (goal direction's z)`.
It keeps out of its own crease and within the §7.5 clamp.

#### 7.8 Goalies
- **Positioning:** on the line from the goal centre toward the ball, `(1.2 + 0.5 × skill)` out,
  x scaled by 1.6. It stays within `±(3.0 + 0.4)` in x and `0.6–2.4` in front of the line.
- **Reading a shot:** once `0.16 + 0.2 × (1 − skill)` s have passed since the last release of any
  kind, a ball (loose or carried) whose velocity toward the goal line (its z-component) exceeds 4
  sets the goalie's x to 0.9 × an aim x: the predicted crossing x (lead factor `0.75 + 0.25 × skill`) when it arrives within
  2.5 s, else the ball's current x.
- **Smothering:** a loose, slow ball (under 7) within 3.5, `|x| < 6` and within 5 of the line
  draws the goalie straight onto it.
- **With the ball:** it stands still. After 0.4 s it picks the most open outfield team-mate
  (openness ≤ 8, −5 for a blocked lane, +1 for a defender, `noise(0.5)`). It releases when the
  orbit is within 0.35 of that team-mate's current position (no lead), or after 2.5 s
  regardless, passing at accuracy 0.9 — or, with nobody to pass to, clearing unassisted once the
  orbit points (within 0.35) straight up the pitch, or after 2.5 s regardless. Its target while it
  holds the ball is where it stands.

#### 7.9 The alert window — crossing the line
A ball carried over the centre line is an attack starting; for the next moments the defence is at
its sharpest. The window exists to make the **long solo goal** — win it deep, run, shoot from 20 —
cost something, without touching the close-range play or the build-up. **Both teams live under it
identically**; it is not a tactic and nothing on the coach's board (§12) changes it.

**The trigger.** While an outfield player carries the ball, the same player carried it at the
previous step, `direction × z` was `≤ 0` then and is `> 0` now — the carrying player's z crossing
the centre line toward the goal they attack — the **other** team goes on alert for **3.0 s** of
match time — longer when that team is behind (§7.10). A fresh crossing restarts it. A loose ball crossing the line triggers nothing.

**The window closes** early when the alerted team wins the ball (whoever carries clears their own
team's alert), when the carrier comes within **14** of the goal they attack — from there the attack
is in on goal and §7.8's ordinary keeper takes it — and at every restart (§4.6).

While a team is alerted, three things change for it, all of them defence doing its job better:

- **The goalie reads sooner and commits fully** (§7.8): its reading delay is **half** of
  `0.16 + 0.2 × (1 − skill)`, it predicts the crossing x with a **full** lead of 1.0 rather than
  `0.75 + 0.25 × skill`, and it goes to the **whole** predicted x rather than 0.9 of it. It is not
  made faster — a keeper who is early is legible; one who teleports is not (A0).
- **One player steps into the shooting lane.** Among the team's outfield players that are not
  already challengers (§7.2), the one **nearest the spot** takes it instead of defending (§7.3),
  and their mark is cleared: the point on the line from the carrier to the goal this team defends,
  `min(4.5, 0.35 × d)` in front of the carrier, `d` being the carrier's distance to that goal.
  Their target does not go through §7.5 — like a challenger's, it is only clamped to
  `|x| ≤ 13.8`, `|z| ≤ 28.8`. An AI carrier reads that body in the lane as §7.6 already says it does
  and looks for the pass instead.
- **A shot from range loses its corner** (§5.4).

Which side is defending on alert is state the core exposes for presentation to read; like everything
in §8.8 it never changes a tick (§4.2).

#### 7.10 The balance of a match — the rubberband
A match that runs away from one side is not worth watching and not worth finishing: a 12–2 is
neither a story nor a test, in either direction. So from a **two-goal** lead on, the match tilts
gently back — the side in front settles, the side behind commits — and the tilt grows with the
size of the lead and with the clock. **It is symmetric**: it helps whoever is behind, the player
included when the player is behind, and the AI when the player is running away with it. A two- to
four-goal win stays entirely ordinary; what becomes rare is the rout.

**Everything here is a nudge to the odds**, never to the ball. Nothing in this section touches
the ball's physics, anyone's accuracy or power, or a goal that has already been struck — and
**nothing at all reaches the player's own release**, which is theirs alone (§5.3, A0).

**The temperament.** Each match draws a **temperament** once, at set-up, before every other draw
(§4.3): `temperament = clamp(1.05 + noise(0.8), 0, 1.8)`, from three draws. It never changes, and
nothing shows it. Most matches land near 1.05 and rubberband normally; about one in nine draws
below 0.55 and barely rubberbands at all — that is where a 7–1 still comes from, and why it feels
like something happened; about one in nine draws above 1.55 and tilts from the first sign of a
gap. **A drill has no temperament and no rubberband** (§10), and draws none.

**The tilt.** At the start of §4.5's step 4, in play, both teams' tilt is recomputed from the
score and the clock:

```
lead     = this team's score − the other's
excess   = max(|lead| − 1, 0)                        a one-goal lead is not a lead
band     = min(excess / 2, 1)                        full from three clear
elapsed  = (period − 1) × period length + (period length − clock)
progress = clamp(elapsed / (3 × period length), 0, 1)
ramp     = 0.45 + 0.55 × progress
r        = min(temperament × band × ramp, 1)
```

`r` is one number for the match; the side **behind** uses it as **chase** and the side **ahead**
as **hold**, and at a level score or a one-goal game both are zero. In overtime the score is level
by definition, so nothing tilts. The tilt is weather, not an event: at 2–0 halfway through the
first period it is about 0.3, at 4–1 in the third about 1.0. Between goals it only drifts with the
clock — about 0.05 a period — and the one time it steps is when a goal changes the band, which is
always followed by a 3.0 s celebration and a face-off (§8.3), so no player ever sees it move
during play.

**What the tilt changes.** The effective tactics (§12) both teams' rules read:

| Tactic | The side ahead (hold `h`) | The side behind (chase `c`) |
|---|---|---|
| Pressing (§7.1, §7.2) | `× (1 − 0.6 h)` | `+ (1 − pressing) × 0.6 c` |
| Push up (§7.4, §7.5) | `× (1 − 0.8 h)` | `+ (1 − push up) × 0.6 c` |
| Discipline (§7.5) | `+ (1 − discipline) × 0.4 h` | unchanged |
| Shooting (§7.6) | `× (1 − 0.85 h)` | unchanged |
| Covering (§7.3) | unchanged | `+ (1 − covering) × 0.45 c` |

and two things for the side behind alone:

- **its goalie reads sooner** — the reading delay it would otherwise use (§7.8's, already halved
  if it is alerted, §7.9) is multiplied by `1 − 0.6 × chase`;
- **its alert window lasts longer** — §7.9's 3.0 s becomes `3.0 × (1 + chase)` s.

So the side in front sits deeper, presses less, holds its shape, and its AI carriers take the
safe ball instead of the speculative shot — a side managing a lead, which is a thing a player can
watch happening. The side behind pushes up, presses, marks tighter, and defends the counter it is
now exposed to.

**Only ever sharper, never softer.** A defence and a goalie are made *keener* when their side is
behind; **no defence and no goalie is ever dulled because its side is ahead.** A rubberband that
softened the leader's keeper would hand out goals nobody earned, and a goal you were given is the
one thing A0 cannot survive. What the leader loses is appetite, never competence.

**The board is untouched** (§12): the player's settings mean exactly what they say, and the tilt
is applied on top of them, identically for both sides. Passing and shooting are club tactics only,
so the shooting nudge never reaches the player's team — every outfield release on their side is
still the player's own, at the player's own accuracy. Nothing on the coach's board changes the
rubberband, and nothing sold ever will (monetization ethics 2: the difficulty serves the match,
not the shop).

**§11.3's simulated results are not affected.** A match the player does not play is still two
Poisson draws.

### 8. The match

#### 8.1 States
`face-off → play → (goal | whistle | period end) → … → ended`, plus `ready` and `lost` in
drills (§10). Only in **play** does the clock run, the AI think, the ball move freely and a release
count. Outside play, players ease to a stop: their velocity blends toward zero as in §3, then ×
0.8, each step. Patrolling dummies and pickup cooldowns run in every state. A carried ball keeps
its carrier outside play, and moves with them. After a goal the ball rolls on inside the net: it
moves by its velocity, slows by `exp(−4·dt)` each step, and bounces off the net's back (at the
net's depth less its radius) and sides (`±(3.0 − r)`) keeping 20 % of its speed. `ended` is
outside play like any pause, and lasts.

#### 8.2 Face-offs
A face-off lasts **1.3 s**, with the ball on the spot and each team lined up by **roster slot**
(not role) relative to it, "back" meaning toward their own goal and sides mirrored for team 1:

- slot 0 (goalie): x = 0, 1.3 out from their goal line;
- slots 1 and 2: 4.5 to the left and right, 8 back;
- slots 3 and 5: 5.5 to the left and right, 1.4 back;
- slot 4: level with the spot, 1.5 back.

Everyone is clamped to `|x| ≤ 13`, `|z| ≤ 28`, and outfield players kept at least 3 in front of
their own goal line. Everyone faces up the pitch. Play starts with the ball's velocity `(3 cos a, 3 sin
a)` in (x, z), `a = 2πu`.

#### 8.3 Periods and the clock
**Three periods**, each of the chosen **period length** (default 120 s, §12). A period ends with
the clock; a 2.5 s pause follows before the next face-off at centre. After a goal, play restarts
at centre after a **3.0 s** celebration. A face-off, a drill's "get ready" and each of these
pauses count down in match time; when one runs out, the state it leads to begins in the same
step.

#### 8.4 The end
After the third period the match ends — a win, a loss or a **draw**. In a **cup** match level
after three periods, **sudden-death overtime** follows a 2.5 s pause: the clock stops mattering
(it shows 0 and stands still) and the next goal ends it, when its 3.0 s celebration is over.

#### 8.5 Goals and scorers
A goal counts for the team attacking that net. The scorer is the last player to touch the ball,
unless that was an opponent and the last release was by the scoring team, in which case the
releaser scores. The assist is the team-mate whose touch set the scorer up: the last touch before
the scorer won the ball, when that was a team-mate of theirs. A goal into your own net is an own
goal, and has no assist. The last 5 seconds of every period are counted down audibly — and that
countdown is the **only** audible count of time. Nothing else in the game marks a passing second:
the clock's split-flap cards change every second and do so silently, while the score's cards clack
as they flip. Overtime is never counted down (§8.4).

#### 8.6 Slow motion
Presentation sets the time scale (§4.2); the camera choreography around it is designed for the
apps.

The "shot distance" below is the distance to goal of the last shot-type release — aimed shots,
unassisted releases and clears, never passes.

- **A shot about to score:** when the loose ball is moving faster than 8 toward a goal mouth
  (within 0.8 of the posts) and will cross the line within 0.6 s, time slows to **0.45** —
  unless the shot was taken from further than **13**, which stays at full speed.
- **A goal:** time drops to **0.18** for 1.3 s, then eases back to 1 over the next 1.3 s. A goal
  from further than 13 plays at full speed.
- Time-scale changes ease at rate 4/s (8/s during a goal). Leaving a goal, the scale starts from
  at least 0.6.
- **Reduce Motion** keeps the slow motion and tames the camera and the shake (§8.8).

**The camera is never jumpy.** Wherever the ball is — in a corner, in a goal mouth or rattling
around well behind a net — the camera moves smoothly: it may travel fast, and it may turn around
once when a shot stops being a shot, but it never steps one way and back again frame after frame.
Two rules keep it so, and both apps are tested against a ball walked over the whole pitch and past
both goal lines:

- A shot's build-up frames **the goal the ball is heading into and is still in front of**. A ball
  already behind a goal line is not a shot about to score, whichever way its velocity happens to
  point, and nothing frames it as one.
- Once a build-up has chosen its goal it **keeps it** until the blend back to the play camera has
  run out. Changing the framed goal while the dramatic camera still carries weight is a cut.

#### 8.7 Quitting
A match can be paused (automatically when the app leaves the foreground) and quit from the pause.
Quitting a **season** match forfeits it as a **0–3** loss. Quitting anything else just leaves.

#### 8.8 What a match looks, sounds and feels like
Everything here is presentation: it reads the match and never changes a tick (§4.2). What each event
sets off is decided once for both apps (the cores' `Feel`), every number is declared once
(`shared/data/presentation.toml`), the sounds are the bank's (`shared/data/sounds.toml`) and the
looping crowd and music — every gain, every attack and release, and what each event pushes into the
crowd — are `shared/data/atmosphere.toml`'s. The
player's own matches and drills get all of it; the demo behind the menus (§9) only what is seen —
never a banner, a sound or a haptic.

- **The ball.** A field ball rolls along its travel; a puck spins. A loose ball faster than 6 draws
  a tapered, fading ribbon behind it in the ball's yellow, through where it was over the last 0.16 s.
- **The flat marks are drawn everywhere.** The discs under the players and the ball, the ring the
  ball circles on, the pops, the offside rings (§16.4) and the aim's own marks (§5.2) lie on the
  pitch and are drawn over it wherever the play is, in one stated order that never depends on where
  the play or the camera has got to. Half the pitch is not a place where a mark stops being drawn.
- **The nets are cloth, and the apps own them.** A world carries the goal *frame* — the two posts
  and the crossbar — and nothing else; everything laced to it, the cords and the film under them, is
  drawn by the apps, so the whole net moves and not a film behind it. Each goal is four sheets: the
  back, the roof and the two sides, each a cord grid over a translucent film in the world's own net
  colour. They hang **still** until the ball strikes them: a net that billows on
  its own reads as wind on a pitch that has none, and it pulls the eye away from the play. The
  cloth's only motion is the ball's (below).
- **The net answers the ball, not the referee.** Every time the ball meets the cloth it dents where
  it struck and the dent spreads outward across that goal's sheets and dies away — a goal, the ball
  rebounding off the back from inside the net, a shot into the side netting from behind the goal, a
  ball driven into the side of the net in open play. It is the **contact** that ripples the net, not
  the whistle, so it happens on every one of them and never on a goal that has not reached the cloth
  yet. How deep the dent is follows the ball's speed **into** that sheet: a hard shot punches the
  net about a third of the goal's depth, a dribbled ball nudges it, and a ball merely leaning on it
  does nothing. The dent is bound by the same bell as the breath, so the laced edges stay still and
  the four sheets hold together as one skin; Reduce Motion keeps the same calmed share of it.
- **Goals.** Confetti bursts from the scored-in net at real speed — 160 cards in the scoring side's
  primary, secondary and white, thrown sideways and high, falling, bouncing and tumbling; the net
  ripples as the ball reaches its cloth, like any other contact (above); the camera shakes (a kick
  of 1.2 falling off by 2.5 a second); the scorers hop (§16.4's banner, the horn and the crowd for a goal of ours, a sigh for one
  against).
- **Knocks.** A post shakes the camera (0.5) and rings; the boards only sound. A save, a steal or a
  block pops a quick ring at the spot. Reduce Motion keeps a fifth of every shake.
- **The stadium.** Under every match of the player's — never the demo — a crowd of two, one behind
  each goal, and drums. Both are loops that start when the match does and never restart: only their
  level, their place across the stereo field and their rate ever move, so the room never seams. The
  **home** end is the player's team's support and the **away** end the other team's; the same murmur
  carries both, the away end a little detuned and quieter, and the two are spread apart so a player
  can hear which end is up. Over them a **swell** — the same crowd on its feet — that rises with the
  situation and leans toward the end being attacked: they groan at their own goal while we roar at
  theirs. What moves them: how near the ball is to one goal or the other (its share of the way there,
  weighted so only the final third really lifts it); a shot §8.6 says is about to score, which grips
  both ends; the last 30 s of a period, and all of overtime; and a push from each event — kick-off,
  a save at that end, a post, a steal, a stoppage, a period's end, and a goal, which takes the
  scoring side's end to the top and the conceding side's below its own floor. Each end rises faster
  than it falls. The goal horn, the goal cheer and the sigh (below) still play on top of all of it.
- **The drums.** One loop under a match and a calmer one under the menus — **percussion only, no
  melody**, and low by design: the match's sits about 18 dB under a struck ball at its loudest, quieter still in
  open play and lifting a little on an attack and in the last seconds; the menus' never lifts. The
  music (never the crowd) steps back a few dB under the horn, the whistles, the post and the result
  stings, and comes back when they are gone. Only one of the two ever plays. Both stop with the app.
  The crowd and the drums have a volume each, declared with the rest of the mapping; 0 is off, and
  the apps carry it as a setting from the first frame. Where the player turns it is not yet settled
  — the coach's board (§12, §16.7) is the obvious home, on the stepped slider it already draws — so
  for now both play at their declared default.
- **Sound.** Every event of the prototype has its sound — the shot (soft, medium or hard by its
  speed), the pass, the player's side taking the ball, the boards, a dummy, the post, the save, the
  steal, the face-off drop, the whistles (a stoppage, a goal, a drill interrupted; a period's end and
  full time), the goal horn with the crowd, the goal against, the last five seconds of a period or a
  drill ticking, and 1.3 s after the end the result's sting (a win or a draw, a loss or time up). The
  3D UI kit sounds too: a press, a refusal, a flip digit turning, a panel landing, the camera's
  whoosh, a slider's step. A sound made on the pitch pans with where it happened and follows the
  time scale (§8.6); the rest play at real speed, centred. The crowd and the match's drums follow
  that time scale too — floored, so a goal's 0.18 slurs rather than falls apart — and hold where they
  are while the match is paused; the menus' drums never slow. Sound follows the silent switch on iOS
  and the media volume on Android.
- **Haptics**, on the system's haptics setting: a light tick when the player's carrier's aim enters a
  pass or shot window (§5.2), an impact on the player's release scaled by its speed, a sharp tap for a
  steal, a save or a post, three pulses with the horn for a goal of ours (one soft one for a goal
  against), and a soft tick with each second of the countdown.

#### 8.9 Offside — the ice sport only
The one rule the two sports do not share (§1). **A player of the attacking side may not be in the
zone before the puck is.** It exists in the ice world and nowhere else: the four field worlds play
without it, and **a drill is never whistled offside** (§10) — a drill is a lesson in one thing, and
a whistle it did not teach is a whistle that only confuses.

**The zone.** A team's attacking zone is everything beyond the blue line it attacks — `z > 9.5` for
team 0, `z < −9.5` for team 1 (§1).

**When the line counts as crossed.** On the **puck's centre**, not its edge. A player can read the
call off where the puck is, which is the only thing they can see; a rule judged on a trailing edge
they cannot see is a rule they cannot learn (A0). The same centre decides the zone for everything
below.

**The entry.** Each step in play, team 0 then team 1: the puck **enters** the zone a team attacks
when its centre is inside, it was not last step, and **that team touched it last** — the attack
put it in. A puck the defence sends into its own end is not an entry and is never offside.

**Once entered, the zone stays entered** until the puck is **4.0 clear of the line** again. A puck
rattling on the line is one entry, not twenty, and the rule is judged once per real attack — which
is what "the zone is not clear until the puck is out" means in the sport it comes from.

**Who is offside.** At the moment of the entry, any of that team's **outfield** players standing
more than **0.6** beyond the line is offside. The 0.6 is the difference between standing *on* the
line and being *in* the zone; a player on the line is onside. Two are exempt, and only two:

- **the carrier** — carrying it in is how a zone is entered;
- **the player who touched the puck last** — the one who sent it in, who cannot be ahead of their
  own pass.

Goalies and drill dummies are never offside. If more than one player is offside, the **first in
roster order** is the one the whistle names.

**The referee misses some.** When an entry is found offside, **one draw** is made from the match
stream (§4.3): on a draw below **0.10** the referee does not see it and **play goes on**, with
nothing emitted and nothing shown. The entry still counts as made, so the same puck is not judged
again a step later. About one offside in ten goes unpunished — rare enough that the player learns
the rule as a consistent one, and often enough that a referee is a person.

**The whistle.** Otherwise play stops **at once** — there is no delayed call. A delayed offside is
a rule about a thing that has not happened yet, and A0 will not carry it: the player would be
watching a play that is already void without being told. Play stops exactly as a dead ball does
(§6.5): the puck's carrier is cleared, its speed drops to 20 %, and after **1.4 s** a face-off
restarts play.

**Where the face-off is.** At the **neutral-zone** spot (§1) nearest the point `(the puck's x when
the whistle went, direction × 7.0)` — that is, one of the two neutral spots on the side of centre
the puck entered, the one on the puck's side of the pitch; the first of §1's four on a tie. The
attack comes out of the zone and starts again, which is the rule's whole cost: **no penalty, no
possession handed over, and never a goal given or taken away.** A goal struck before the whistle
stands, because the whistle can only come at an entry, and at an entry the puck is only just in.

**What it is worth.** Measured over 400 automatic ice matches: about **5 %** of the zone entries an
attack makes are offside — one stray run in twenty — of which about **10 %** go unseen, leaving
about **1.7 whistles a match**. Ice matches score about **10.5** goals to the field's **12.4**: the
ice world is the tighter, more structured of the two sports, which is what it is in life.

**What the core exposes.** For every player, whether they are offside *now* — who the whistle would
name if the puck entered this instant, by exactly the test above — so the apps can mark them
(§16.4); and, at the whistle, the event carrying the offending team and the player named. Both are
presentation reading the match; neither changes a tick (§4.2).

### 9. The demo match
A match plays behind the menus so the title screen is alive: the player's team (Moss Foxes
before a career exists) against a random club, both sides fully automatic, in the five worlds in
turn. It never affects progress.

### 10. Training
Eight drills, unlocked in order: a drill is open once the one before it has been won. Each has a
world, a goal target and a time limit.

- **No rubberband:** a drill is not a match between two scores, so §7.10 never tilts one and a
  drill draws no temperament.
- **No offside:** §8.9 never fires in a drill, on ice or anywhere else, and the drill's players
  never hold the blue line. Drill 5 (Moving cones) is played on the Himalaya ice and is unchanged
  by the rule: it teaches one thing, and a whistle it did not teach is a whistle that confuses.
- **Setup:** fixed lineups. The ball starts with the player's first player (or the one the drill
  names), orbiting from behind them (the orbit angle π, turning as §5.1 chooses), after a 1.4 s
  "get ready". The drill's clock is its time limit.
- **Win:** reach the goal target before the clock runs out — the drill ends, won, when that goal's
  1.6 s reset is over. **Fail:** time runs out.
- **Reset:** after each goal (1.6 s), or when the drill is interrupted (1.2 s), everyone returns to
  their start and a new 1.4 s "get ready" begins (the clock does not run). A drill is interrupted,
  during play, when:
  - the defence takes the ball — "saved" by the goalie, "stolen" by anyone else;
  - the ball goes into the wrong net;
  - a drill that requires an assist sees a goal scored without one;
  - the ball goes dead (§6.5).
- **Ratings:** in drills the player's side is rated **76** and a drill's opponents **74** — **70**
  when they include real defenders or forwards — regardless of the career team, so a drill is
  the same drill for everyone. The coach's tactics still apply.
- **Retry:** a drill is retried in one tap.

| # | Drill | World | Goals / time | Player's side (x, z) | Opponents | Rule |
|---|---|---|---|---|---|---|
| 1 | First shot | Magic Wood | 3 / 60 s | F (0, −2) | none | — |
| 2 | Give and go | Desert Oasis | 3 / 90 s | F (−7, −6), F (7, 4) | none | goals count only after a pass |
| 3 | Beat the goalie | Ocean World | 3 / 90 s | F (−6, −4), F (6, 6) | G at speed 0.6 | — |
| 4 | Cones | Deep Space | 3 / 90 s | F (−8, −8), F (8, −2), F (−6, 10) | G 0.65; static dummies at (0, 6), (−5, 14), (5, 14), (0, 19) | — |
| 5 | Moving cones | Himalaya | 3 / 90 s | F (−8, −8), F (8, −2), F (0, 10) | G 0.7; dummies patrolling (−8, 8)↔(8, 8) at 1.1, (8, 15)↔(−8, 15) at 0.9 phase 1.5, (−4, 20)↔(4, 20) at 1.6 | — |
| 6 | Sleepy defenders | Magic Wood | 3 / 100 s | F (−8, −6), F (8, −2), F (0, 8) | G 0.75; D (−5, 12), D (5, 12) at 0.45 | — |
| 7 | Under pressure | Desert Oasis | 3 / 110 s | F (−8, −6), F (8, −2), F (0, 8), D (0, −14) | G 1.0; D (−6, 14), D (6, 14), F (0, 4) at 0.75 | — |
| 8 | Scrimmage | Deep Space | 3 / 150 s | F (−9, −5), F (0, −3), F (9, −5), D (−6.5, −17), D (6.5, −17), G (0, −24.6) | G 0.7; D (−6.5, 17), D (6.5, 17), F (−9, 5), F (0, 3), F (9, 5) at 0.85 | the ball starts with the second player; free play |

The opposing goalie stands at (0, 24.6). "Speed" multiplies top speed. A patrolling dummy slides
between its start and its second point as `k = 0.5 + 0.5·sin(match time × speed + phase)`, its
velocity being its displacement over the step divided by the step (zero across a reset: a reset
returns it to its start, and its first step after the drill's setup or a reset reports zero).
Dummies have radius 0.9.

In **free play** (Scrimmage) the opponents may take the ball and score; every goal, either way,
resets the drill. Drill opponents play the default tactics with pressing 0.7. Completion is saved
on the device.

### 11. The season

#### 11.1 Fixtures
The career's league — seven clubs and the player's own team in the eighth place (§2.2) — plays a **double
round-robin**: 14 rounds.

- The league's teams in their canonical order — the clubs as §2.1 lists them, the player's team
  in the place of the club it replaces — are shuffled from the season stream (Fisher–Yates from
  the last position down to position 1: for i = 7 … 1, `j = floor(u × (i + 1))`, swap i and j).
  The cup order is shuffled the same way, from the same canonical order, after it.
- Round r (0-based, r < 7) pairs order[i] with order[7 − i] for i = 0…3; order[i] is at home when
  r is even, order[7 − i] when r is odd. The order is then rotated with position 0 fixed (the
  last moves to position 1).
- Rounds 8–14 repeat 1–7 with home and away swapped.
- The **cup** quarter-finals pair cup-order positions (0, 1), (2, 3), (4, 5), (6, 7), the first
  at home; each later round pairs the winners of consecutive ties the same way, and is drawn when
  the round before it closes.

A matchday's fixtures keep this order — a round's pairs by i, a cup round's ties in bracket order.
The **matchday plan**:

> league rounds 1–4 · cup quarter-finals · league rounds 5–9 · cup semi-finals · league rounds 10–14 · cup final

League matches are played in the **home team's world**; cup matches likewise.

#### 11.2 Playing a matchday
The player plays their fixture of the matchday; its result (or a forfeit, §8.7) is recorded and
the matchday closes. Every other fixture is **simulated** when the matchday closes. Matchdays on
which the player has no fixture — after a cup exit — are simulated straight through, as soon as
the matchday before them closes.

#### 11.3 Simulated results
Each side's goals are Poisson-distributed:

- home mean `2.3 × exp((home − away) / 22) + 0.15`;
- away mean `2.3 × exp((away − home) / 22)`.

Goals are drawn by Knuth's method from the season stream: `k = 0, p = 1`; repeat `k += 1, p ×= u`
while `p > exp(−mean)`; the goals are `k − 1` (`exp` is §4.4's). A level cup match goes to the
home side when one more draw `u < home mean / (home mean + away mean)`, else to the away side, by
one goal in overtime. A matchday's fixtures are simulated in their order (§11.1), each drawing
the home side's goals, then the away side's, then — only if it is a level cup match — the
overtime draw.

#### 11.4 The table, the cup, the end
- **Table:** 3 points for a win, 1 for a draw. Ranked by points, then goal difference, then goals
  for, then short code alphabetically.
- **Cup:** winners advance in bracket order.
- **The end:** after the final, the table's top team is **league champion** and the final's
  winner **cup winner**. The player's trophy counts (league titles, cups) grow when it is them,
  and a new season can start, keeping the career and its trophies.

#### 11.5 Quick match
A friendly against a random club, in a random world, outside the season. Both are drawn from a
stream of the quick match's own, seeded when it is chosen — never the season's, whose position a
friendly does not move: first the opponent, `floor(u × n)` into the clubs in §2.1's order less the
player's side's own club, if it is one — so all eight clubs are drawn for the player's created
team, Glacier Wolves included. Then the world, `floor(u × 5)` into §13's order. Before a career
exists the player's side is the Moss Foxes, as in the demo (§9).

### 12. The coach's board
The player tunes their own team's automatic play. It applies to every match they play, drills
included, and is saved on the device.

| Setting | Range | Default | What it does |
|---|---|---|---|
| Pressing | 0–1 | 0.55 | how many go in for the ball and from how far (§7.1, §7.2) |
| Covering | 0–1 | 0.55 | how often and how tightly opponents are marked (§7.3) |
| Push up | 0–1 | 0.55 | how high the team plays (§7.4, §7.5) |
| Formation | §3 | Balanced | where the players line up |
| Discipline | 0–1 | 0 | how strictly the formation is held (§7.5) |
| Period length | 60–240 s, steps of 30 | 120 s | §8.3 |
| Ball spin | 1.4–3.2 s per turn, steps of 0.2 | 2.0 s | the orbit period (§5.1): slower is easier |

Every setting here is read through §7.10's tilt: the board says what a team does at a level
score, and the rubberband bends it from a two-goal gap on, the same way for the player's side and
the opponent's. The board cannot turn the rubberband off or up.

Passing and shooting (§7.6) are tactics of the clubs only: on the player's team every outfield
release is the player's, so the board does not offer them. "Reset" restores the defaults. The ball-spin setting sets the orbit period for every
carrier in the player's matches (§5.1), so it slows the opponents' releases too.

### 13. Worlds
Five worlds, each with its own scenery, sky, light, pitch surface, boundary and ball, designed
for the apps: **Magic Wood**, **Deep Space**, **Desert Oasis**, **Himalaya** (ice hockey, §1),
**Ocean World**. The other four play field hockey. Nothing in a world intrudes inside the
boundary.

**The worlds are alive** (ADR 0007), as the prototype's were — ambient life that never touches
play: nothing that moves ever crosses inside the boundary (only falling snow drifts over the
rink), nothing takes randomness from the match, and it runs on real time, unaffected by pause or
slow motion. What lives, the same on both platforms:

- **Magic Wood** — the lantern mushrooms' caps breathe, all together, and so do the warm pools
  of light beneath them and two broad warm spills beside the pitch; the violet crystals glow up
  and down; the altar gem floats, bobs, turns and pulses over its cyan halo; glints run down the
  stream; fireflies drift and blink round the clearing and in the canopies; lavender mist drifts
  and breathes over the forest floor.
- **Deep Space** — stars twinkle; nebula clouds breathe; the neon strips, pod rings and
  floodlights pulse; a wave of light chases round the rim's studs; the thruster flames, exhaust
  glows and floodlight glows flicker; the holographic boards bob and flicker; the two dashed halo
  rings turn (the outer one backwards); the comet laps the low sky; two satellites orbit the arena.
- **Desert Oasis** — palm crowns, grass, reeds and bunting sway in one breeze; the pools glitter;
  the campfire's flame licks and its glow flickers; dust blows along the dunes.
- **Himalaya** — the prayer flags flutter, a wave running down each string; soft cloud drifts over
  the sea of cloud, round the far peaks and over the lake; snow falls, over the rink too.
- **Ocean World** — kelp, sea grass, anemones and sea fans sway in the current; four schools of
  fish circle the reef, each at its own pace and some the other way, bobbing as they go; two manta
  rays glide round it high up; the jellyfish drift, bob and pulse; bubble streams rise wobbling
  from the reef; motes drift up; shafts of sunlight shimmer.

With the system's Reduce Motion (iOS) or removed animations (Android) on, the same life is calmer
— smaller movements, slower rhythms — never gone. Read when a world loads.

### 14. Language
German on devices set to German, English otherwise. Every user-facing string, club name, world
name and drill text exists in both.

### 15. What is kept on the device
- **The career:** the player's team — its name, short code, kit and home world — and the trophy
  counts.
- **The season in progress:** its number in the career (the first is 1, each next one more;
  starting over begins again at 1), its seed and stream position, its teams, every fixture drawn so
  far with its result, and the matchday. The table and the cup bracket follow from the results.
  A season read back from the device continues with exactly the draws it would have made.
- **Training:** which drills are won.
- **The coach's board** (§12).

The record's shape is declared once (`shared/data/save.toml`) and written as canonical JSON: the
same state writes the same bytes on both platforms. It carries a format **version**. A record
that is not well-formed, breaks a rule of this spec, or has another version is refused with a
typed error — never read as an empty save.

**When it is written:** after every recorded result (a played match, a forfeit, a won drill),
every career change, and every change on the coach's board — before the next screen appears.
**When a record is refused** on launch, the game says so on a screen of its own, keeps the file
untouched beside a new one, and offers exactly one way on: start over. It never opens as if the
player were new.

Nothing leaves the device. Until the first store submission, these shapes may change without
migration (`conventions.md`, greenfield); from then on they are migrated, never reset.

### 16. The screens
Every screen is built from the 3D UI kit (ADR 0005, `conventions.md` UI): blocks, flip digits,
panels and lettering in the world, moving on the shared motion tokens, reached by camera moves
rather than cuts, with the demo match (§9) playing behind every menu. Every control has a stable
accessibility identifier, the same on both platforms (`<screen>_<control>_button`), and every word
comes from the declared copy (§14).

**The look.** Panels, slabs, cards and rows are **white**; everything that reads as lettering, a
digit or an accent is a saturated colour from the game's own set — the sun yellow, the pink, the
green and the deep navy. Anything text-like clears **4.5:1** against what it sits on; the pairs the
UI puts lettering on are declared alongside the palette and the ratio is **checked when the tokens
are generated**, so a palette tweak cannot quietly make a caption unreadable. The whole palette, the
design frame's sizes and the UI's own light are declared once in `shared/data/design.json` and
generated into both apps; no screen or component spells a colour or a size of its own.

**The UI has its own light**, not the light of the world standing behind it: the kit's blocks are
toon-shaded (ADR 0006) under one neutral rig — bright from the front, a little less from above, less
again from the sides — so a white slab reads white and a menu looks the same in every world. **The
rig is read in the UI's own frame**, so the face the player is looking at is the fully lit one on
every screen and on the HUD, whichever way that screen stands and wherever the match camera has
moved to: the front face keeps the palette's colour as it was authored, and no screen sits in its
own shadow. How
much of the key a face turned away from it keeps is part of a light (`shade`): a world keeps the
prototype's value, and the **UI's own light drops much lower**, because an extruded letter is only
legible when its sides read as a bevel rather than as more of the front's colour. The shading is
there to make a block feel like an object, never to colour it.

**Lettering is measured from the font, not from the mesh.** Both apps extrude the same outlines
from the same font file, but each does it with its own engine, and the box an engine reports around
the result is its own. So how wide a string is, where its line sits, how far a long word shrinks to
fit a slab, how a piece of lettering is placed against the point it is aligned to, and where running
text breaks are **one computation over the font's own metrics**, shared by both platforms. Two
consequences a player can see: a caption's line does not move with the characters in it — a German
word with an umlaut sits on its slab exactly where an all-caps English one does — and the same
screen is laid out identically on both phones.

**A caption that does not fit wraps before it shrinks.** Lettering wider than the room it is given
breaks into **at most two centred lines**, split where the two lines come out evenest and never
through a word, and the slab it sits on **grows in height** to hold them. Only lettering with
nowhere to break — a single long word — still shrinks to fit, as it always did. Both platforms
break a string in the same place, so a banner that needs two lines in English and one in German
reads the same way on both phones.

**A transition finishes.** An element that arrives ends on its exact pose; an element that leaves
ends hidden, and is only then taken off the screen. This holds however the motion is being played —
the whimsical springs, or Reduce Motion's plain fades — including when the system's Reduce Motion
setting changes in the middle of one, and when a screen is entered again while its last arrival is
still in the air. Nothing is ever left part-way, hanging where it should not be.

**What the player touches is what the player sees.** An element's hit target and its accessibility
frame are read from the pose it is actually drawn at — never from the pose it was meant to land on.
An element the player can see is one they can reach; one that is still on its way is neither.

#### 16.1 First launch — creating the team
With no career saved, the game opens here, once (§2.2): the create form, and nothing else to
choose from. Name (the system keyboard; 2–16 characters), short code (derived, editable, refused
when it equals a club's), kit (primary and secondary from the 12 palette pairs), home world (the
five). A live preview disk wears the kit; every rule the draft breaks is named under it, and the
confirm button can only be tapped when there is none. Confirming starts the career and its first
season; Glacier Wolves are replaced (§2.2).

Training and quick match are reachable from here too (§2.2) before the team exists.

**Changing it later.** The same screen, with the team's own name, code, kit and world already in
it, is how the team is changed once it exists (§2.2). It is reached from the **coach's board**
(§16.7) — the one place the player's own team is set up, one tap from the title — and from the
player's own row in the league table (§16.3a), where a player looking at their team already is.
The heading says it is a change rather than a creation and the confirm button reads **Save**; the
short code no longer follows the name, because the team already has one. The same rules are
named the same way, and **Back** leaves without changing anything. Saving writes the record (§15)
and returns to where the player came from — the season, or the title when there is no season.

#### 16.2 The title
The logo, and: **Season** (continue, or start the next one — §11.4), **Training**, **Quick match**,
**Coach**, **How to play**. The trophy counts are shown when there are any. Settings live on the
coach's board; there is no other settings screen.

#### 16.3 The season hub
- **Which season:** "Season n" (§15) heads the hub, with the matchday.
- **Next fixture:** both teams' kits, **both clubs' full names** under their codes, league round or
  cup round, the world it is played in, and **Play**, which starts the match in one tap (A2).
- **League table** (§11.4), the player's row marked; **the cup** bracket with results so far. A
  table row is tappable and opens its team's detail (§16.3a).
- **Season over:** champion, cup winner, the player's place and trophies, and **Next season**.

#### 16.3a The team detail
Tapping a row of the league table tips a panel up in front of it, the way a drill's intro card
does (§16.6), and **Back** dismisses it the same way; while it stands, the rows behind it take no
taps. It is about the row's team and shows, read off the season's fixtures (§15):

- the team's **full name** beside its kit and short code — the player's own in the accent colour;
- where it stands: its **place** in the table and its **points**;
- **played**, **won**, **drawn**, **lost**, **goals for and against** and **goal difference** —
  the league only, counted exactly as the table counts them (§11.4);
- its **last three matches**, most recent first — won, drawn or lost as a coloured badge, whether
  it was at home or away, the opponent's full name, the score, and a mark when it was a cup tie or
  went to overtime. Early in a season there are fewer, and before a team has played, the panel
  says so. A forfeit (§8.7) is one of these like any other result: a 0–3 loss.
- the **fixture it plays next**, league or cup, with where and against whom; once it has none
  left, that the season is over for it.

The panel is the same for every team, and **the player's own team gets one thing more**: the way
to change its name, code, kit and home world (§16.1).

Played, won, drawn, lost, the last three and the next fixture are **one computation in the core**,
the same on both platforms, from the season record alone — no screen counts them itself.

#### 16.4 The match
The HUD: both teams' short codes on their kit colours, the score and the clock as flip digits, the
period as three pips, and a pause button in a corner, clear of the pitch (§8.6's slow motion leaves
the HUD at real speed). In overtime **OT** takes the clock's place. Goals flip the score and wobble
the board. The board holds **two cards a side**, the tens card blank below ten, so a side may reach
99 without the board changing shape or running into the short codes: the tenth goal flips the tens
card from blank to 1 like any other change, and every card stands in the same place at 0:0 and at
12:11. The result slab (§16.5) counts up on the same two cards a side. The pause panel: **Resume** and **Quit** — quitting a season match says it forfeits 0–3
before it does (§8.7).

**The offside mark** (the ice sport only, §8.9). A player the core reports offside wears a **faded
ring** on the pitch, in their kit's primary colour — the same ring the aim's lock-on marker draws
around a pass receiver (§5.2), but pale, unpulsed and drawn under the player rather than over them.
It appears and fades over 0.12 s as the core's answer changes, and it is the whole of the warning:
a player who is about to be whistled is visibly marked before it happens, and the aim arrow is
already refusing to go green for them. Nothing else on the HUD changes.

In a drill the HUD shows goals scored of the target and the clock — the target sets the width, so a
target of ten or more gets two cards a side — and the drill's hint is the intro card before
"get ready" (§10).

**Banners** — the prototype's, built from the kit's lettering in the middle of the screen, each for
its time in real seconds and then gone (a new one replaces the last). A banner too wide for the
frame wraps to two centred lines rather than shrinking (§16): "END OF PERIOD 1" and its German
"ENDE 1. DRITTEL" both break after their first half and stay full size.

| When | Banner | Style | Seconds |
|---|---|---|---|
| a match (not a drill) starts | "*Home* VS *Away*" (the teams' names) | info | 2.2 |
| a face-off after a period's end | PERIOD *n*, or SUDDEN DEATH into overtime | info | 1.5 |
| a period ends (not the last) | END OF PERIOD *n* | info | 2.4 |
| the last period ends level in the cup | OVERTIME | info | 2.4 |
| a drill's get ready | GET READY; AGAIN! after an interruption; NICE! AGAIN after a goal | info | 0.9 |
| a dead ball in a match (§6.5) | RESET | warn | 1.8 |
| an offside in an ice match (§8.9) | OFFSIDE | warn | 1.8 |
| a drill interrupted (§10) | SAVED! · STOLEN! · WRONG GOAL! · PASS FIRST! · RESET | bad | 1.2 |
| a goal | GOAL! (ours) · GOAL AGAINST | good · bad | 2.4 |
| the end | FINAL (a match) · DRILL DONE! / TIME'S UP (a drill) | good, or bad for a loss | 1.5 |

Good is the sun yellow and pops in big; bad the pink; warn orange; info cyan.

#### 16.5 The result
The final score, **both sides by their full names** under their codes and kits (a drill has
neither), win/draw/loss, overtime if it happened, and the way on: back to the hub (season);
after a failed drill **Again** (one tap — A2) and **Training** (back to the drills); **Next drill**
when won; back to the title (quick match).

#### 16.6 Training
The eight drills as cards in order: name, world, goals/time, what opposes (none, goalie, dummies,
defenders), won or locked (§10). A locked card does not start. Choosing an open one shows its
intro (the hint) and **Start**; while the intro stands, the cards behind it take no taps.

#### 16.7 The coach's board
Sliders for pressing, covering, push up and discipline (§12), the five formations as a picker
drawn as disks on a small pitch, period length and ball spin as stepped sliders, and **Reset**
(§12). Changes save as they are made (§15). **Edit team** stands beside them: the board is where
the player's own team is set up, so it is also where its name, code, kit and home world are
changed (§16.1). It is there only once a team exists.

#### 16.8 How to play
The prototype's six lessons (the copy's `help.*`), each a card, the one-touch control shown by a
disk with a ball circling it and an aim line.

---

## Out of scope
- Steering players, aiming by drag, charging a shot: the player's only input is hold and release.
- Icing. (Offside is in scope, on the ice sport only — §8.9.)
- More than eight teams in a season; playing as one of the eight clubs; switching teams within a
  career.
- The player's team's rating changing over time.
- Online play, accounts, leaderboards.

## Constraints & invariants
- **A0 before everything:** nothing may add latency between a finger and the ball, or make the
  aim line disagree with where the ball goes.
- **Nothing blocks the next match** (principle A2): no load, fetch, ad or dialog between a result
  and the next face-off, or between a failed drill and its retry.
- **Frame-rate independence:** a match is the same sequence of ticks at 60 Hz, 120 Hz and any time
  scale (§4).
- **Determinism:** same seed, teams, settings and input ⇒ the same match, bit for bit, on both
  platforms (§4.3–§4.7).
- **Player data is local and sacred once shipped** (principle 13, and `conventions.md`'s
  greenfield section until the first store submission).
