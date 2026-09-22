<!--
This spec covers ONLY what we are building now. It is not a roadmap — everything not yet in
scope lives in Stori project SMASH as ideas/tasks. When we pick one up, we edit this file first;
the diff is the work (AGENTS.md).

Split axis (declared): CAPABILITY. When this file grows, split into spec/<capability>.md
(≤3 levels) + spec/cross-cutting/ for concerns spanning capabilities. Single file for now.

Rules: principles.md. Stack standards: conventions.md. Decisions: decisions/.
-->

Spec-Version: 0.3.0
Status: as-is — **the whole game's rules, written down; neither app plays them yet.** Both apps
are empty shells (see the platform-delta table). What this file now holds is the complete
gameplay contract taken from the web prototype — the pitch, the one-touch control, the ball, the
automatic play, the match, the drills, the season and the coach's board, with every number the
prototype was tuned to — plus the one thing the prototype never had: **a career**, in which the
player picks a club or creates their own team, once. From this version on the prototype is not
consulted for rules or numbers; this file is.

# Smash Hockey 3D (iOS · Android) — Specification

## Overview
Smash Hockey 3D is a stylised, colourful 3D field-hockey game for phones — with one ice-hockey
world — played with **one touch**. Your players run on their own; you decide only **when to let
go of the ball**. A career with one club, a season of league and cup matches, eight training
drills that teach the control, and five worlds to play them in. The menus and scoreboards are
part of the 3D world too.

## What the web prototype contributed
`web/` explored **gameplay** and nothing else (ADR 0002). Its rules and tuned numbers are in this
file (§1–§13); from `spec-v0.3.0` on, this file is their only authority and the prototype is not
read for them. A change to any rule or number here is a spec change, not a tuning session — and
where it touches the simulation, it moves a golden vector (§4).

Nothing else carries over: the apps' worlds, look, UI, camera choreography and sound are designed
for the apps. **The UI is part of the 3D world** — menus, scoreboards and the HUD are animated
objects in the scene, playful rather than standard; each screen is specified here when it is
designed.

## Platforms & scope
The game ships on **two platforms**, and **everything below binds both unless the
platform-delta table says otherwise**. There is one specification, not two; a platform is not
free to be different, only to be *late*, and lateness has to be written down.

- **iPhone**, portrait. **Android phone**, portrait. Minimum OS: **iOS 18**, **Android API 26**
  (proposed by the renderer decision, ADR 0005; confirmed when it is accepted).
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
| 2026-09-22 | **temporary** | **Neither app implements §1–§15 yet.** Both are empty shells that launch. Each section's implementation deletes its part of this row, on both platforms in the same commit, or splits it into a per-platform row naming the one that is behind. Closed by the items in Stori `SMASH` (SMASH-2, SMASH-7 onward). |
| 2026-09-22 | **permanent** | **Purchases are per-store and per-device.** There is no account, so an entitlement bought on one store does not follow the player to the other. The game never implies otherwise: no affordance offers a cross-platform restore (ADR 0001). |

**The golden vectors** (`shared/vectors/`) are the one place the two simulations are checked
against each other rather than merely written to the same text (§4.7). None exist yet; the first
platform to implement the simulation records them.

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
| Goal mouth width × depth | 6.0 × 1.6 — the net occupies the box behind the line (for the ball, the net's frame is 0.15 larger on every outer side: 6.3 × 1.75) |
| Goal crease radius (keep-out, §7) | 3.2 |
| Boundary | a rounded rectangle at the half-extents, corner radius per sport |

| Sport | Corner radius | Ball friction (m/s²) | Ball drag (1/s) | Wall restitution | Ball |
|---|---|---|---|---|---|
| **Field hockey** (default) | 2.0 | 0.9 | 0.3 | 0.6 | a ball, radius 0.36 |
| **Ice hockey** (Himalaya) | 8.5 | 0.45 | 0.2 | 0.72 | a puck, radius 0.36 |

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

Names are localized (English/German, §14). Each club has a primary and secondary kit colour.

**A rating is the team's skill.** It sets outfield top speed (§3) and `skill = clamp((rating −
60) / 30, 0, 1)`, which scales AI release accuracy, shot power and goalie play (§7), and it
drives simulated results (§11).

#### 2.2 The career — one team, for good
The player's first act is to choose their team, **once**:

- **Pick a club** — any of the eight. Its name, kit, home world and rating become the player's.
  The coach's board (§12) starts from that club's tactics.
- **Create a team** — the player enters:
  - a **name**, 2–16 characters;
  - a **short code**, 3 letters, derived from the name and editable, and never equal to a club's;
  - a **kit**: a primary and secondary colour, each chosen from a curated palette. No palette
    primary equals a club's primary, so a created team never clashes with an opponent;
  - a **home world**, one of the five (§13).

  A created team's **rating is fixed at 77**, the league average (the mean of the eight clubs'
  ratings, rounded). Its tactics start from the defaults (§12). **It replaces the weakest club,
  Glacier Wolves, in the league and cup**, which keep eight teams. Glacier Wolves still exist as
  an opponent outside the season (quick match, §11.5).

The choice holds for every season that follows. There is no switching: **starting over** is a
deliberate, confirmed act that ends the career, its season and its trophies. Training progress
(§10) survives it, because it records the player's skill rather than the team's.

Choosing a team or confirming a created one is the step before the first season; the rest of the
game (training, quick match) is available before it.

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
match is advanced in **ticks of 1/120 s**, two steps each; input is applied at tick boundaries.
**Match time** advances by one step at the start of each step. The match clock, every timer and
every rule below is measured in match time.

#### 4.2 Presentation time
Real time drives the simulation through a **time scale** that only presentation sets (§8.6's
slow motion). The time scale changes how many ticks run per real second, never what a tick does:
a match is the same sequence of ticks at any time scale and any display rate. Real-time gaps
longer than 0.1 s are clamped to 0.1 s.

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
  a team, players in roster order.
- `noise(s)` is `(u₁ + u₂ + u₃ − 1.5) × s` from three consecutive draws.
- Presentation (camera shake, particles, scenery) never draws from these streams.

#### 4.4 Arithmetic
The two platforms compute the same match to the last bit, so the simulation uses only operations
IEEE-754 double precision defines exactly — `+ − × ÷` and `sqrt` — evaluated in the order this
spec writes them, **never fused** into a multiply-add. Lengths are `sqrt(x² + z²)`, never a
library `hypot`. `sin`, `cos`, `atan2` and `exp` are **not** the platform's: each is a fixed
approximation (range reduction plus polynomial, absolute error ≤ 1e-9 on the simulation's input
ranges) whose constants are declared once in `shared/data/` and implemented identically on both
platforms. The declaration is recorded with the first golden vector.

#### 4.5 What a step does, in order
1. Match time advances.
2. The state machine (§8.1): timers count down; a face-off that expires starts play with its
   drop draw; any other expired state moves on.
3. In play: the clock counts down; at zero the period, match or drill ends (§8.3, §8.4, §10) —
   the rest of this step still runs as in play.
4. In play: team 0's automatic play, then team 1's (§7).
5. Every player moves (§3), in roster order.
6. Player–player contact (§3), then each player is kept inside the boundary and out of the nets.
7. The ball: in play it moves (§6); otherwise a carried ball follows its carrier (orbiting only
   during a drill's "get ready"), a ball in the net after a goal rolls on (§8.1), and a loose ball
   stays put.
8. In play: the dead-ball timer (§6.5).

#### 4.6 What a restart resets
Every face-off and drill reset clears: the ball's carrier, velocity, last touches, assist and
pending release; and for every player, velocity, target, pickup cooldown, hold time, decision,
mark, expected pass, steal contact, challenge commitment, and the loose-ball timer (§7.1). Think
timers (§7) are not reset.

#### 4.7 Golden vectors
A **vector** is `(seed, sport, teams and ratings, tactics and formations, the player's input as
(tick, hold | release) events, and the sampled state)`: for every sampled tick, the match state
(§8), clock, score, each player's position and velocity, and the ball's position, velocity,
carrier and orbit angle. Both platforms replay every vector and must reproduce every sample
exactly. A vector is recorded by the first platform to implement a rule, checked against this
spec and by playing it, and **re-recording one requires a spec change in the same commit**.

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
  orbit angle, the closest in angle winning;
- **to a shot** when the goal centre lies within the goal window of the orbit angle — **0.40 rad,
  widened by up to 0.30 as the carrier closes from 14 to 0 away**. The goal wins over a pass when
  its angle is less than 0.9 × the pass's, or the carrier is within 9 of goal.

The aim line shows the direction and what it would snap to — **pass** and **shot** each with their
own colour.

#### 5.3 The player's release
The ball circles by itself; **touching and holding anywhere** is the player saying "not yet", and
**lifting the last finger** releases it. Only the player's outfield carriers wait for the player;
the player's goalie plays by itself (§7.8). A release only counts during play (§8).

When the finger lifts:

1. If the ball would snap to something **now**, it goes there.
2. Otherwise, if it **would have** snapped at any of the four instants 0.0625, 0.125, 0.1875,
   0.25 s ago (the late grace, 0.25 s), it goes to the first of those it finds.
3. Otherwise, if it **will** snap within 0.05, 0.10, 0.15, 0.20 or 0.25 s from now, the release is
   **held pending**: it fires the moment the ball snaps, or — if nothing snaps — unassisted 0.06 s
   after that instant. A pending release is cancelled only if the player loses the ball; a new
   touch does not cancel it.
4. Otherwise it leaves unassisted along the orbit direction.

#### 5.4 How the ball leaves
Every release leaves **from the orbit point**; the direction of an aimed release is measured
**from the carrier's position** to its aim point.

- **A pass** travels at `clamp(14 + 0.85 × distance, 14, 30)` toward the receiver's lead position
  (as in §5.2, at that speed), plus `noise(1.6 × (1.15 − accuracy))` on each axis. The receiver
  re-thinks at once and **expects the pass**: an expectation of 1.6 that drops by 0.2 at each of
  their re-thinks (§7).
- **A shot** travels at **30** toward the far side of the goal from the goalie — `±(3.0 − 0.85)`
  in x: −x when the goalie's x > 0, else +x (a random side if there is no goalie) — pulled to 30 %
  of that on a 25 % draw, plus `noise(1.5 × (1.2 − accuracy))`.
- **An unassisted release** travels at **24** along the orbit direction.
- The player's own releases have accuracy 1. The ball also inherits 20 % of the carrier's
  velocity.
- A release point with `|z| > 25.7` and `|x| < 3.6` (at either goal) is moved back to the
  carrier's x and z, z kept within 25.5.
- The releaser cannot take the ball back for 0.45 s.

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
  within `3.0 − 0.3r` of the centre, crosses the goal line by more than half its radius. From any
  other side the net (§1) is solid and reflects it with the wall restitution. A goal ends the
  step's ball update. Nets come first, then posts, then the boundary.
- **Players**, in roster order, deflect it when it overlaps them — pushed out to touching, and
  its velocity relative to them reflected with restitution 0.85 (a goalie smothers it with 0.35,
  which is a save; a dummy's touch is a block).

#### 6.3 Picking it up
After all deflections, of the players who may pick up (not dummies), the nearest within reach
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
of its speed, and after **1.4 s** play restarts with a face-off at the nearest of the nine spots.
In a drill, the drill resets instead.

### 7. Automatic play
Everyone except the player's release decision is automatic, and both teams run the same rules
with their own tactics (§12) and rating. Outfield players re-think every **0.12 + 0.1u** s
(u a draw; each player's first re-think falls at `0.2u`, drawn in roster order when the match
is set up); carriers and goalies think every step.

#### 7.1 Loose ball
- A player **expecting a pass** heads for the point on the ball's line of travel nearest them,
  ahead of the ball only (the ball itself when it is slower than 2).
- Otherwise the outfield players ranked by distance to the ball — the pass receiver counts in
  the ranking — chase where the ball will be: its position plus `0.7 × velocity × t`, `t =
  clamp(distance / max(top speed, 1), 0, 1.2)`. One chases; **two** when pressing > 0.75, the
  nearest is more than 9 away, or the ball has been loose for more than 1.5 s of play (the
  loose-ball timer runs only in play, resets whenever someone carries and at restarts, §4.6).
- Everyone else takes a support position (§7.4).
- A chase target less than 0.4 in front of a goal line (or behind it) and within 4.6 of the
  centre, while the chaser is more than 0.4 in front of that line, is replaced by the net's
  corner waypoint `(±4.6, 0.6 in front of the line)` on the chaser's side of x.

#### 7.2 The other team has it — challengers
Up to **2** players go in for the ball — **3** when pressing > 0.75. Candidates are those already
committed (a challenger stays committed for 0.7 s); a player **goal-side** of the carrier
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
Six **support slots** relative to the ball (or its carrier), for a team attacking +Z. A
*mirror* slot's x is absolute, measured from the pitch's centre line, and multiplied by −1 when
the ball's x ≥ 0 — so positive-x mirror slots land on the far side of the ball and negative-x
ones on its side. The others are x-offsets from the ball. Every slot's z is an offset from the
ball:

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
attack is moved sideways to `|x| ≥ 7`; then it is pushed 7.5 from the ball. Team-mates take slots **greedily in roster order**, each
the nearest free slot, a role mismatch counting as 8 extra metres. A player whose slot has an
opponent within 3.4 shifts 3.5 across and 1.5 along, away from them.

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
- then **6 from every outfield team-mate's current position** (the carrier included) when in
  possession, 3.5 otherwise,
- then out of their own **crease** — at least `3.2 + 1.2` from their goal centre, and never
  closer than 2.2 to their own goal line,
- and finally — for chasers too — clamped to `|x| ≤ 13.8`, `|z| ≤ 28.8`.

#### 7.6 An AI carrier's decision
An AI carrier decides after holding for 0.15 s, re-thinking every `0.2 + 0.15u` s until it has a
decision (the think timer keeps being drawn every period, decision or not). A **threat** is the
nearest opponent who can steal, goalies excluded. The carrier is **forced** when a threat is
within 2.6 or it has held for 3.5 s.

- **Shoot** when within `11 + 11 × shooting` of goal, `|x| < 11`, and no non-goalie opponent
  (dummies included) is within 1.3 of the line to the goal centre and nearer than the goal — or
  within 6 — with probability `0.35 + 0.5 × shooting`, or
  always when forced.
- Else **pass** to the best team-mate between 3 and 26 away, scored by
  `1.2 × openness (≤ 6) + 0.35 × progress − 6 if the lane is blocked (1.4 wide) − 10 if the ball
  would cross within 5 of their own goal + 0.3 × (progress + 6) when more than 6 backward −
  0.4 × (distance − 18) beyond 18 + noise(0.8)`, if that best score exceeds 3.5, with probability
  `0.3 × passing + 0.45 if threatened within 4 + 0.3 if held over 2 s`, or always when forced.
- **Forced**: pass to the best-scoring team-mate between 3 and 26 away whatever the score; with
  none in range, **shoot** within 24 of goal, else **clear** (release unassisted).

It then **waits for the orbit to line up** with its aim — the goal centre for a shot or a
clear; for a pass the receiver's lead position with `t = distance / clamp(11 + 0.55 × distance,
14, 24)` — within `0.22 + 0.12 × (1 − skill)` (+0.5 when an opponent is within 2.2). The AI
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
  kind, a ball (loose or carried) moving toward the goal faster than 4 sets the goalie's x to 0.9
  × an aim x: the predicted crossing x (lead factor `0.75 + 0.25 × skill`) when it arrives within
  2.5 s, else the ball's current x.
- **Smothering:** a loose, slow ball (under 7) within 3.5, `|x| < 6` and within 5 of the line
  draws the goalie straight onto it.
- **With the ball:** it stands still. After 0.4 s it picks the most open outfield team-mate
  (openness ≤ 8, −5 for a blocked lane, +1 for a defender, `noise(0.5)`). It releases when the
  orbit is within 0.35 of that team-mate's current position (no lead), or after 2.5 s
  regardless, passing at accuracy 0.9 — or, with nobody to pass to, clearing unassisted once the
  orbit points up the pitch.

### 8. The match

#### 8.1 States
`face-off → play → (goal | whistle | period end) → … → ended`, plus `ready` and `lost` in
drills (§10). Only in **play** does the clock run, the AI think, the ball move freely and a release
count. Outside play, players ease to a stop: their velocity blends toward zero as in §3, then ×
0.8, each step. Patrolling dummies and pickup cooldowns run in every state.

#### 8.2 Face-offs
A face-off lasts **1.3 s**, with the ball on the spot and each team lined up by **roster slot**
(not role) relative to it, "back" meaning toward their own goal and sides mirrored for team 1:

- slot 0 (goalie): x = 0, 1.3 out from their goal line;
- slots 1 and 2: 4.5 to the left and right, 8 back;
- slots 3 and 5: 5.5 to the left and right, 1.4 back;
- slot 4: level with the spot, 1.5 back.

Everyone is clamped to `|x| ≤ 13`, `|z| ≤ 28`, and outfield players kept at least 3 off their own
goal line. Everyone faces up the pitch. Play starts with the ball's velocity `(3 cos a, 3 sin
a)` in (x, z), `a = 2πu`.

#### 8.3 Periods and the clock
**Three periods**, each of the chosen **period length** (default 120 s, §12). A period ends with
the clock; a 2.5 s pause follows before the next face-off at centre. After a goal, play restarts
at centre after a **3.0 s** celebration.

#### 8.4 The end
After the third period the match ends — a win, a loss or a **draw**. In a **cup** match level
after three periods, **sudden-death overtime** follows a 2.5 s pause: the clock stops mattering
and the next goal ends it.

#### 8.5 Goals and scorers
A goal counts for the team attacking that net. The scorer is the last player to touch the ball,
unless that was an opponent and the last release was by the scoring team, in which case the
releaser scores. The assist is the team-mate whose touch set the scorer up. A goal into your own
net is an own goal. The last 5 seconds of every period are counted down audibly.

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
- **Reduce Motion** keeps the slow motion and tames the camera.

#### 8.7 Quitting
A match can be paused (automatically when the app leaves the foreground) and quit from the pause.
Quitting a **season** match forfeits it as a **0–3** loss. Quitting anything else just leaves.

### 9. The demo match
A match plays behind the menus so the title screen is alive: the player's team (Moss Foxes
before a career exists) against a random club, both sides fully automatic, in the five worlds in
turn. It never affects progress.

### 10. Training
Eight drills, unlocked in order: a drill is open once the one before it has been won. Each has a
world, a goal target and a time limit.

- **Setup:** fixed lineups. The ball starts with the player's first player (or the one the drill
  names), orbiting from behind them, after a 1.4 s "get ready".
- **Win:** reach the goal target before the clock runs out. **Fail:** time runs out.
- **Reset:** after each goal (1.6 s), or when the drill is interrupted (1.2 s), everyone returns to
  their start and a new 1.4 s "get ready" begins (the clock does not run). A drill is interrupted when:
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
velocity being its displacement over the step divided by the step (zero across a reset). Dummies
have radius 0.9.

In **free play** (Scrimmage) the opponents may take the ball and score; every goal, either way,
resets the drill. Drill opponents play the default tactics with pressing 0.7. Completion is saved
on the device.

### 11. The season

#### 11.1 Fixtures
The career's league — the eight clubs, or seven plus the created team (§2.2) — plays a **double
round-robin**: 14 rounds.

- The team order is shuffled (Fisher–Yates from the last position down, `j = floor(u × (i + 1))`)
  from the season stream; the cup order is shuffled the same way, after it.
- Round r (0-based, r < 7) pairs order[i] with order[7 − i] for i = 0…3; order[i] is at home when
  r is even, order[7 − i] when r is odd. The order is then rotated with position 0 fixed (the
  last moves to position 1).
- Rounds 8–14 repeat 1–7 with home and away swapped.
- The **cup** quarter-finals pair cup-order positions (0, 1), (2, 3), (4, 5), (6, 7), the first
  at home; each later round pairs the winners of consecutive ties the same way.
The **matchday plan**:

> league rounds 1–4 · cup quarter-finals · league rounds 5–9 · cup semi-finals · league rounds 10–14 · cup final

League matches are played in the **home team's world**; cup matches likewise.

#### 11.2 Playing a matchday
The player plays their fixture of the matchday. Every other fixture is **simulated** when the
matchday closes. Matchdays on which the player has no fixture — after a cup exit — are simulated
straight through.

#### 11.3 Simulated results
Each side's goals are Poisson-distributed:

- home mean `2.3 × exp((home − away) / 22) + 0.15`;
- away mean `2.3 × exp((away − home) / 22)`.

Goals are drawn by Knuth's method from the season stream. A level cup match goes to the home
side with probability `home mean / (home mean + away mean)`, else the away side, by one goal in
overtime.

#### 11.4 The table, the cup, the end
- **Table:** 3 points for a win, 1 for a draw. Ranked by points, then goal difference, then goals
  for, then short code alphabetically.
- **Cup:** winners advance in bracket order.
- **The end:** after the final, the table's top team is **league champion** and the final's
  winner **cup winner**. The player's trophy counts (league titles, cups) grow when it is them,
  and a new season can start, keeping the career and its trophies.

#### 11.5 Quick match
A friendly against a random club other than the player's, in a random world, outside the
season.

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

Passing and shooting (§7.6) are tactics of the clubs only: on the player's team every outfield
release is the player's, so the board does not offer them. "Reset" restores the defaults — or,
with a picked club, that club's tactics. The ball-spin setting sets the orbit period for every
carrier in the player's matches (§5.1), so it slows the opponents' releases too.

### 13. Worlds
Five worlds, each with its own scenery, sky, light, pitch surface, boundary and ball, designed
for the apps: **Magic Wood**, **Deep Space**, **Desert Oasis**, **Himalaya** (ice hockey, §1),
**Ocean World**. The other four play field hockey. Nothing in a world intrudes inside the
boundary.

### 14. Language
German on devices set to German, English otherwise. Every user-facing string, club name, world
name and drill text exists in both.

### 15. What is kept on the device
- **The career:** the chosen club, or the created team's name, short code, kit and home world;
  and the trophy counts.
- **The season in progress:** its seed and stream position, fixtures, results, table, cup and
  matchday.
- **Training:** which drills are won.
- **The coach's board** (§12).

Nothing leaves the device. Until the first store submission, these shapes may change without
migration (`conventions.md`, greenfield); from then on they are migrated, never reset.

---

## Out of scope
- Steering players, aiming by drag, charging a shot: the player's only input is hold and release.
- Offside and icing.
- More than eight teams in a season; switching teams within a career.
- A created team's rating changing over time.
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
