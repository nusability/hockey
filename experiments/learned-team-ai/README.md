# Learned team AI — the experiment's artifacts (SMASH-72)

Five policy checkpoints from the night of 2026-10-15/16, and what they measure. Together they are
a **measured trade-off curve** between playing like §7 and beating §7 — which is a better thing to
choose from than one recommendation.

**Nothing here ships.** The shipped path for weights is `shared/assets/policy/` with a declaration
in `shared/data/policy.toml` and a spec change (ADR `0010`). These are experiment outputs, kept
because they cost hours of compute and because the numbers below only mean anything next to the
weights that produced them.

Four are `107 → 32 → 32 → 2` (4,578 parameters); `faithful.txt` is `107 → 128 → 128 → 2`
(30,594), so it needs `--hidden 128`. One hex IEEE-754 double per line, in
`PolicyNet.parameters` order.

```
cd ios/SmashCore
swift run -c release TrainTeamAI --evaluate experiments/learned-team-ai/balanced.txt \
    --matches 120 --eval-offset 5000 --period 40 --hidden 32
swift run -c release TrainTeamAI --analyse  experiments/learned-team-ai/balanced.txt \
    --matches 32  --eval-offset 5000 --period 40 --hidden 32
swift run -c release TrainTeamAI --replay   experiments/learned-team-ai/balanced.txt \
    --period 40 --hidden 32 --replay-seed 5000
```

**`--eval-offset` is not optional.** The search selects its best on seeds `0..<24`, so a number
measured there is a number it was allowed to fit — a mistake made twice in one night, both times
producing a claim that had to be retracted. Every figure below is on seeds `5000+`, which no run
was ever scored against.

## The four

| File | Trained on | What it is |
|---|---|---|
| `clone.txt` | Imitating §7 (Adam) + 3 DAgger rounds | The faithful copy. The control. |
| `winner.txt` | Goals + shape proxies, **maximised** | Wins; worst to watch |
| `balanced.txt` | Beat §7 on goals, **match** §7's shape | **The recommendation** |
| `stronger.txt` | Same objective, 200 iterations later | Wins most; spent the depth to do it |
| `faithful.txt` | 128 units, shape charged 4× dearer | Looks most like §7; wins nothing |

## Results — 120 unseen seeds

§7's own goal difference on these seeds is **−0.08**. It is not symmetric: the two sides are
different clubs with different ratings, so the baseline is not zero.

| | goals | goal difference | gap to §7 |
|---|---|---|---|
| `clone.txt` | 0.40–1.21 | −0.81 | **−0.73** |
| `winner.txt` | 0.76–0.38 | +0.38 | **+0.46** |
| `balanced.txt` | 0.79–0.44 | +0.35 | **+0.43** |
| `stronger.txt` | 0.82–0.36 | +0.46 | **+0.54** |
| §7 rules | 0.80–0.88 | −0.08 | — |

**All three searched policies beat the hand-written AI, and all of them do it by defending.** None
scores more than §7's 0.80; they concede 0.36–0.44 where §7 concedes 0.88.

The clone is the measurement that makes the rest meaningful: imitating §7 as closely as regression
allows lands **0.73 goals a match behind** it, scoring half as often (0.40 against 0.80). Imitation
reproduces §7's *habits* and loses its *results* — small errors compound in a closed loop. Every
gain above comes from the search, not the imitation; the bootstrap only supplies a starting point
that is not noise.

## The curve

Every row measured on unseen seeds. Read down it: **shape fidelity and goal advantage trade off
monotonically, and the end points are both useless.**

| | units | shape weight | gap to §7 | width | spacing | goal-side | depth |
|---|---|---|---|---|---|---|---|
| `clone.txt` | 32 | imitation only | **−0.73** | 4.9 m | 4.9 m | 71 % | +4.98 m |
| `winner.txt` | 32 | maximised | +0.46 | 4.2 m | 6.2 m | 64 % | +4.24 m |
| `stronger.txt` | 32 | 0.15 | **+0.54** | 5.1 m | 6.8 m | 62 % | +2.35 m |
| `balanced.txt` | 32 | 0.15 | +0.43 | 4.6 m | 6.6 m | **71 %** | +4.89 m |
| `faithful.txt` | 128 | 0.60 | +0.02 | **5.9 m** | **7.0 m** | **73 %** | +4.25 m |
| §7 rules | — | — | 0 | 6.5 m | 7.0 m | 72 % | +5.45 m |

The two ends teach the same lesson from opposite directions. **Imitation alone loses** (−0.73):
copying §7's habits does not reproduce its results, because small errors compound in a closed
loop. **Constraint alone wins nothing** (+0.02): told firmly enough to match §7 on six statistics,
the optimum is to *be* §7 — you cannot beat a thing while being required to resemble it closely.

`faithful.txt` is the best-looking policy here by a clear margin — width 5.9 m against every other
run's 4.2–5.1, spacing exactly §7's 7.0, goal-side discipline 73 %. It is also the only one with no
advantage over §7 whatsoever. If the goal is "§7 but learned", it is done. If the goal is "better
than §7", it is the wrong end of the curve.

**The choice this frames:** `balanced.txt` for +0.43 goals a match with most of §7's shape, or
`faithful.txt` for §7's shape almost exactly and no gain, or somewhere between at a shape weight
of roughly 0.3 — the obvious untried experiment, and the one I would run next.

## Shape — 32 unseen seeds

Only `width` and (in later runs) `depth` are trained on. `swarm`, `churn` and `goal-side` are
deliberately left out of every reward so they stay honest checks.

| | swarm | churn/min | depth | goal-side | width | spacing |
|---|---|---|---|---|---|---|
| `clone.txt` | 9.46 m | 60.7 | +4.98 m | 71 % | 4.9 m | 4.9 m |
| `winner.txt` | 10.17 m | 48.6 | +4.24 m | 64 % | 4.2 m | 6.2 m |
| `balanced.txt` | 10.13 m | **49.6** | +4.89 m | **71 %** | 4.6 m | **6.6 m** |
| `stronger.txt` | 9.97 m | **50.4** | +2.35 m | 62 % | 5.1 m | **6.8 m** |
| `faithful.txt` | 9.92 m | 53.4 | +4.25 m | **73 %** | **5.9 m** | **7.0 m** |
| §7 rules | 11.02 m | 52.2 | +5.45 m | 72 % | **6.5 m** | 7.0 m |

Read as: *swarm* = mean distance from the ball to **every** outfielder (higher is less of a pack);
*churn* = how often the nearest pair to the ball changes (lower is more legible); *depth* = how far
the deepest defender sits behind the ball; *goal-side* = share of play with that defender actually
goal-side; *width* = standard deviation of outfield x; *spacing* = distance to the nearest
team-mate.

**`balanced.txt` is the recommendation.** It matches §7 on goal-side discipline, beats it on role
churn, and comes within 0.4 m on spacing and 0.6 m on depth — while beating it by +0.43 goals a
match, within a rounding error of what the entirely shape-blind `winner.txt` manages. Asking for
both cost almost nothing; asking only for results was the expensive mistake.

**`stronger.txt` is the cautionary one.** Same objective, 200 iterations further on, and the best
record here (+0.54, better than `winner.txt`) — bought by letting **depth collapse from +5.70 m to
+2.35 m** and goal-side discipline fall to 62 %. Depth was not in that run's reward; it was added
afterwards, for exactly this reason. What the search found is a side defending from a high line: a
style, not better hockey, and not something anyone asked for. **An untrained measure is a measure
the search will spend.**

## Width: a capacity limit, not an architectural one

Width is short in every policy above, and the explanation that cost most of a night was wrong.

The tempting story: width needs players to occupy **different** lateral lanes, which needs knowing
which lanes are taken; §7 gets that from §7.4's greedy "nearest free slot" assignment and §7.5's
pairwise push, both team-level by construction; one net run per player cannot ask the question. It
is tidy and it is **false** — each player's observation already carries all ten team-mates'
positions and its own formation spot, so the information is present and the symmetry is broken.

The measurement that settles it, the same clone at 128 hidden units (30,338 parameters):

| | swarm | churn/min | depth | goal-side | width | spacing |
|---|---|---|---|---|---|---|
| clone @ 32 | 9.46 m | 60.7 | +4.98 m | 71 % | 4.9 m | 4.9 m |
| clone @ 128 | 12.29 m | 56.6 | +2.13 m | 66 % | **6.5 m** | **7.3 m** |
| §7 rules | 11.02 m | 52.2 | +5.45 m | 72 % | 6.5 m | 7.0 m |

**Width lands exactly on §7's 6.5 m.** The small net is spending a capacity budget: at 32 units it
buys depth and goal-side discipline and gives up width and spacing; at 128 it buys width and
spacing and gives up depth. No mechanism is missing.

## Next, in order

1. **A shape weight near 0.3, at 128 units.** The curve above has been measured at both ends and
   not in the middle. 0.15 at 128 units sells the shape (spacing 7.3 → 5.5 m inside forty
   iterations); 0.60 holds it exactly and wins nothing. The interesting region is between, and
   nothing has looked there. Capacity is affordable — ADR `0010` measured a 9,472-MAC pass at
   3.73 µs on an M1 and ~2 % of a 16.7 ms frame on the OnePlus.
2. **Start from a plain clone, not a DAgger'd one, when shape matters.** DAgger reliably collapses
   it: spacing 7.3 → 5.1 m at 96 units, 6.6 → 3.9 m at 32. It labels the states the policy drifts
   into, so clustered states come to dominate the data. It buys possession and spends shape.
3. **Only then** consider the architecture: net outputs a preference over §7.4's slots, resolved by
   a deterministic greedy assignment in roster order. §4.4-safe (comparisons and ordering only),
   roster-agnostic, and it would restore the explainability ADR `0010` names as the main cost of
   going learned — you could see which slot each player was given.

## Three things that cost time, recorded so they don't again

- **Cloning loss is not evidence of a good policy.** The best loss of the night, 0.0012, came from
  the worst team: given its own previous target as an input, the net learned to repeat itself, which
  is near-optimal on the objective and a fixed point at rollout. Players froze; possession fell to
  0.21. Hiding the memory on half of samples fixes it.
- **A proxy only constrains what it names.** `spread` is the distance to your *nearest* team-mate,
  which a single file down the centre satisfies perfectly. Hours went into rewards that could not
  tell a hockey shape from a queue.
- **Monotone shape terms are the wrong shape of objective.** Realism is a range, not an extreme.
  Maximising a proxy walks out of the range that made it a good proxy; matching §7's measured value
  is what works.

## What is still §7's

The goalie (§7.8) is still the written rules. `strength` and the per-club style vector have been in
the observation since the first commit but are held fixed — there is no ladder to distil yet.

## Where this got to, 2026-10-18

Both arms climbed **every rung** — our ball at 6, 14, 24 m, a loose ball at 18 and 30 m, their ball
24 m from our own goal — with no forced promotions, and reached the real game. Measured on 60 seeds
neither arm was ever scored against, in the shipped game (keepers on, no stamina, ordinary
face-offs):

| | goals | poss | att |
|---|---|---|---|
| learned (`nightA`) | **4.57–0.32** | 0.211 | 0.062 |
| §7 rules | 0.92–1.05 | 0.361 | 0.101 |

**Five times §7's scoring rate**, with *less* of the ball and *less* time in the attacking third —
a shape suspicious enough to be worth watching rather than reporting. The owner watched two unseen
seeds and found no exploit: it simply plays well.

By then the carrier was learned too — the net's one decision is release or keep hold, with §5.2's
auto-aim deciding what that hits, which is the player's own path rather than §7.6's
pick-a-target-then-wait.

### The open question: the single file

It still strings out down the middle. The owner's reading is the best explanation offered, and it
is about the **engine**, not the AI: *in this game you can run forward and collect a pass from
behind at no cost.* In a real sport you must turn, slow or take a touch, which is exactly why real
teams offer themselves laterally. While a trailing pass is free, the file is genuinely the
strongest shape available, and no reward or architecture will talk a search out of a correct
answer. **Width is not missing because the policy failed to find it; it is missing because it does
not pay.**

### The change to make next

A ball arriving from **behind** the receiver should often fail to be collected.

- **Where:** the pickup loop in `Match/BallPhysics.swift` (~line 176–194), before `takeBall`.
- **How:** compare the player's `facing` against the heading the ball arrives *from*
  (`Pitch.heading(-ball.vel.x, -ball.vel.z)`); the wider that angle, the likelier the ball runs on.
  Scale with the ball's speed, so a slow roll stays collectable.
- The engine already turns players gradually (`Tuning.Player.turnRate`), so the "turning time" half
  of the idea exists.
- **Symmetric — it applies to the human player too**, which is the test of whether a rule is fair
  or an AI handicap in disguise.

This is a behaviour change, not an experiment patch: spec diff in the same commit (§6 pickup),
every vector in `shared/vectors/match/` re-recorded, and the constants declared in `shared/data/`
rather than written as literals. Through the loop.
