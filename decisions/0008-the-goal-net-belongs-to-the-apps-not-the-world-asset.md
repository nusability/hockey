# 0008 — The goal net belongs to the apps, not the world asset
Date: 2026-09-23 · Status: **accepted** · Narrows ADR 0007 (what a world's asset may carry) and ADR 0005 (the asset contract)

## Context

The net was owned twice. Each world's `scenery` mesh carried the prototype's cord grid — a box of
0.05 m bars over the goal's 1.6 m depth, baked by `tools/worldkit.py` — while both apps drew a
translucent film in the same planes and swayed it (`[net.sway]`, 0.06 m) and rippled it on a goal.

The owner played both phones on 2026-09-23 and reported the nets as visibly static, and they were:
what the eye reads as "the net" is the opaque cord grid, which is baked into the scenery and can
never move, and the animated film is 22 % opaque and was swaying 6 cm — about three pixels from the
play camera, which stands 36 m up and 20 m back (§8.6). Two owners, one of them frozen, is the bug.

ADR 0007 offered the other way out: make the net an effect mesh (`fx_net`) and move it on the GPU.

## Decision

**The asset carries the goal frame; the apps carry the net.** `goal_frame` in `worldkit.py` writes
the two posts and the crossbar and nothing else. Both apps build the whole net — cords and film —
from one shared description (`SmashCore/Feel/GoalNet.swift`, `core/feel/GoalNet.kt`): four sheets a
goal (back, roof, two sides), each a grid of `[net] columns × rows × depth` cells, laced along every
edge, drawn as a cord ribbon grid standing `cord_lift` off a translucent film. Every node of every
sheet — cords and film together — moves along its sheet's outward normal by the sway, with a goal's
ripple added on top; Reduce Motion calms the sway once, in that one formula. The cords take the
world's own colour (`teams.toml [[world]] net`), which is all that is left of the net in the asset's
data. Both nets are two meshes per app (every film, every cord), written in the pitch's frame on
entities that never move, bounded by `GoalNet.extent` — a box a test walks every vertex of every
frame of the sway and of a goal against (SMASH-33's lesson).

## Why not the effects layer (ADR 0007)

An `fx_` mesh is closed-form in the renderer's clock alone: no per-frame CPU work, nothing from the
match's clock, nothing from an event (ADR 0007 §3). A goal's ripple is exactly an event — a moment
and a place, from the ball — so a net baked as an effect could breathe but could never answer a
goal. Keeping the ripple would have meant owning the net twice over again, which is the bug.

## Consequences

- The scenery meshes lose ~860 triangles a world; the apps gain ~2,000 triangles and two draw calls
  each, rewritten per frame (≈2,000 vertices, a few ALU ops each) — the same shape of work the ball's
  trail already does, and well inside the 765G's budget.
- The net is the same cloth on both platforms by construction: one description, one formula, one set
  of numbers, two thin mesh builders.
- The sway is now 0.18 m — chosen to be seen from the play camera (~9 px at the far goal), still an
  eighth of the goal's depth.
- A world script no longer chooses how a net is built. Its only say is the colour of the cords.
