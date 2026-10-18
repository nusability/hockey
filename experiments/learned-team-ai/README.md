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

> **The five original checkpoints no longer load.** The observation and the output grew with the
> carrier decision (commit `95af629`): the shape is now `122 → h → h → 3`, so `--hidden 32` wants
> **5,091** parameters and `--hidden 128` wants **32,643**. `clone/winner/balanced/stronger/
> faithful.txt` hold 4,578 or 30,594 and are refused with a parameter-count error. They are kept
> for the record below, not for replay. **`curriculum.txt` and `curriculum-seed777.txt` are the
> current shape** (`--hidden 128`); they are the two arms of the night of 2026-10-17.

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

## Compare width within an objective, not across the whole table

The widths this project has measured only mean something sorted by **what the run was paid for**.
Pooling them hides the entire effect:

| policy | width | objective |
|---|---|---|
| `curriculum.txt` (nightA, old engine) | **1.2 m** | victory only |
| `curriculum-seed777.txt` (nightB, old engine) | **1.3 m** | victory only |
| arm A, 2026-10-18, iter 369, still training | **4.3 m** | victory only, **§6.3.1 + ease ladder** |
| `winner.txt` | 4.2 m | shaped — pays for `spread` |
| `balanced.txt` | 4.6 m | shaped |
| `clone.txt` | 4.9 m | imitation of §7 |
| `stronger.txt` | 5.1 m | shaped |
| `faithful.txt` | 5.9 m | shaped, shape charged 4× |
| §7 rules | **6.8 m** | — |

**Every victory-only run on the old engine collapsed to a 1.2–1.3 m column — both seeds.** The
4.2–5.9 m band belongs to runs that were *paid* for shape, or that copied §7. So a 4–5 m width is
only unremarkable for a shaped run; for a victory-only one it had never happened.

**The controlled comparison.** Same seed (777), same objective (goal difference alone), same spawn
curriculum, same stamina, one variable — §6.3.1 plus the ease ladder:

| | width | depth | goal-side |
|---|---|---|---|
| `curriculum-seed777.txt` — without | 1.3 m | +11.35 m | 94 % |
| arm A — with | **4.3 m** | **+4.06 m** | **60 %** |
| §7 | 6.8 m | +5.57 m | 72 % |

3.3× the width, with depth and goal-side far closer to §7 as well. **§6.3.1 plus the ladder buys
with a pure goal-difference objective roughly what previously required paying for shape outright.**

**What is not settled.** Arm A was at iteration 369 of 1000 and its width was *eroding* — 5.5 m at
its peak, 4.2–4.3 m a hundred iterations later — while its results climbed to 2.92–0.46. Width is
still not in the objective, so the search still spends it; the ladder may only be delaying the
collapse. `nightB`'s 1.3 m is a finished 708-iteration policy, so the endpoints are not comparable
until arm A finishes. Arm B, converted to the rule rather than raised under it, creeps 1.2 → 1.6 m
over 330 iterations: real but an order of magnitude too slow to matter.

## Does width emerge once the trailing pass costs something? No — measured 2026-10-18

The whole point of §6.3.1 was that width would pay once a pass into a team-mate's back stopped
being free. It does not. `curriculum.txt` continued for 190 iterations on goal difference alone
under the full rule, both rows on **48 unseen seeds**, measured identically:

| | swarm | churn/min | depth | goal-side | **width** | spacing |
|---|---|---|---|---|---|---|
| `curriculum.txt`, before | 10.84 m | 44.9 | +8.84 m | 89 % | **1.2 m** | 4.6 m |
| 190 iterations later | 11.78 m | 43.6 | **+7.23 m** | **85 %** | **1.3 m** | 4.2 m |
| §7 rules | 11.62 m | 49.6 | +5.57 m | 72 % | **6.8 m** | 7.2 m |

**Width 1.2 → 1.3 m is no movement.** Depth and goal-side did move, toward §7, so the policy is
adapting to the rule — just never laterally. Swarm rose to §7's own value, so this is a coherent
side throughout and not a scattered one.

**The rule removed the reason the file was optimal; it did not create a reason for width to be.**
The diagnosis behind the rule was right — the trailing pass *was* free and the policy's whole game
rested on it, which is why removing it took 4.57–0.32 down to 0.94–0.54 on unseen seeds. But the
answer the search found was to stop passing, not to spread out: it holds the ball 0.10 of the time
against §7's 0.28 and wins by standing in a column in front of its own goal. Nothing in a
victory-only objective pays for occupying lateral space, and a column concedes perfectly well.

**Next, in order.** Pay for possession — run the same checkpoint on the shaped reward and see
whether width moves when the objective values holding the ball; that tells you whether the rule is
a necessary precondition or a dead end. Then **watch a `learned v itself` replay** before trusting
any of the above, which is six numbers. The collection constants are the *last* lever, not the
first: harsher collection makes passing worse, which makes not-passing better, which is the wrong
direction.

**A caution for anyone reading a width number here.** An arm mid-curriculum measured 6.0 m wide,
almost exactly §7's 6.8, which is the result this experiment was looking for. It was a side that
had stopped contesting the ball: `press` 12.6 m against §7's 4.2, depth **−12.08 m** (upfield of
the ball), goal-side 28 %, losing 0.31–1.06 in a real match. Scattered players have high lateral
variance for the same reason dropped marbles do. **Width is only meaningful next to `press`,
`depth` and a scoreline.**

## The single file is a column — 1.2 m, measured 2026-10-18

The shape tables above are **stale and far too kind**. They document 4.2–5.9 m of width for the
2026-10-15/16 policies. `curriculum.txt`, the current one, measured under §6.3.1 on 16 unseen
seeds:

| | swarm | churn/min | depth | goal-side | **width** | spacing |
|---|---|---|---|---|---|---|
| `curriculum.txt` | 10.91 m | 44.0 | **+8.53 m** | **88 %** | **1.2 m** | 4.6 m |
| §7 rules, same rule | 11.81 m | 50.4 | +5.55 m | 72 % | **6.8 m** | 7.2 m |

**1.2 m is a column, not a file** — a quarter of the narrowest policy in the tables above, and a
fifth of §7's. With depth +8.53 m and 88 % goal-side it is a deep narrow bus that defends with
everybody and counter-attacks, which is precisely the shape the victory-only fitness comment says
league points were adopted to prevent. Before §6.3.1 it counter-attacked lethally (4.57–0.32) on
free trailing passes; under the rule it is 1.50–0.79 and still winning.

**Nothing in the training log would ever have told you.** The log's `spread` column is the mean
distance to the *nearest* team-mate (`main.swift:234`) and reads a comfortable 4.5 m, because a
column is perfectly spaced — the trap this file already records two sections down, re-sprung on
the person who wrote it down. **Width lives only in `--analyse`** (`Analyse.swift:33`, the standard
deviation of outfield x). Judge shape with `--analyse`; the log cannot tell a hockey shape from a
queue.

`--analyse` needs `--out` pointed somewhere writable even though it writes no checkpoints: it
creates the output directory before dispatching to the analyse branch, so on a machine where the
default path does not exist it dies with a permissions error from `NSCocoaErrorDomain`.

## What the 2026-10-17 arms were actually run with

Nothing recorded it, and reconstructing it cost most of a morning and five restarted runs. Both
arms were (recovered from `nightB.log`'s header and by probing §7's baseline):

```
swift run -c release TrainTeamAI --open-nets --hidden 128 --reward victory \
    --matches 20 --period 40 --stamina --replay-every 100 [--seed 777]
```

- **`--reward victory` is not the default.** The default is the shaped reward, whose terms include
  `spread` — so a run left on the default cannot answer any question about shape emerging on its
  own, because shape is being paid for.
- **`--matches 20` is not the default** either (it is 4). At 4 a victory-only fitness is mostly
  draw noise, since there is no dense term to lean on.
- **`--stamina` is not the default and does not appear in the log header.** It is recoverable only
  by probing: §7's own baseline at seed 777 is `spread 5.9 m, recv 0.73, terr +0.38, att 0.249`
  with it and `5.8 / 0.68 / +0.43 / 0.268` without, and the header reads the first set. Five
  metrics to the last digit. Continuing a stamina-trained checkpoint without it silently changes
  the game under the policy.
- Seed `777` is arm B; arm A used the default `0xA11CE`. **`nightA`'s log was not kept**, so the
  arm whose checkpoint became `curriculum.txt` has no surviving trajectory to compare against.
- The default seed is a poor choice for a fresh run: 93 iterations without once improving on its
  random initialisation, with the pickup rule eased off entirely. Seed 777 clears rung 0 by
  iteration 34. **Seed variance dominates anything measured over a hundred iterations.**

`retrain.sh` now holds all of this, so the next run is a command rather than an excavation.

## The two ladders judge different things and can fight

The spawn ladder promotes on `centre.goalsFor >= rungBar`. The pull-back reverts `theta` to
`bestTheta` when `fitness` has not improved for `patience` iterations, and victory-only fitness is
`wins·3 + 0.15·(for − against) − 0.12·press`. **Goals are not fitness**, so a run can climb toward
a rung bar and be reverted by a mechanism that cannot see it.

Watched happening: an arm improved its centre from 2.12 to **3.17** goals over 39 iterations, past
the 3.0 bar, while `press` drifted 9.3 → 11.0 m. The press penalty and the lost wins outweighed
the better goal difference, so fitness never beat the value recorded at **iteration 2**, nothing
was ever written as a new best, and the pull-back reverted forty iterations of exactly the drift
the rung ladder was about to reward. The other arm of the same seed escaped it only because its
fitness happened to improve at iteration 30.

Consequences worth knowing before reading a short run: an early *lucky* centre estimate is worse
than an early poor one, because nothing can beat it; and a rung reached by `rungPatience` forcing
it is much weaker evidence than one that was earned. If this bites, the dials are `--centre-matches`
(a less noisy estimate, so early luck is rarer) and `--patience`, not the ladder.

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

### The change that was made, 2026-10-18 — §6.3.1

**A ball arriving from behind an outfield player is no longer reliably collected** (spec §6.3.1,
`Spec-Version` 0.34.0). Within 60° of the player's facing nothing changed; past that the pressure
climbs with the angle and with the ball's speed *relative* to them, and at the extreme — fast and
straight from behind — the ball is gathered 8 % of the time, ricochets off them 37 %, and runs on
past them 55 %. A slow roll (under 4 relative) is always collectable, so a gentle trailing pass
still works. Goalies are exempt: §3 pins their facing. The human is not.

**What makes it non-gameable is that facing is not a choice.** §3 derives it from the direction a
player is actually moving, and only while they are moving — there is no aim for a net to spend. To
meet a ball coming up behind you, you have to run back at it and give up the ground you were
making. That is the cost, and it is the same cost for the human.

**The measurement that says it bit.** `curriculum.txt` is the policy trained *before* this rule,
on 48 seeds it was never scored against (`--eval-offset 5000`), in the shipped game:

| | goals | poss | att |
|---|---|---|---|
| `curriculum.txt` **before** the rule (60 seeds) | 4.57–0.32 | 0.211 | 0.062 |
| `curriculum.txt` **after** the rule (48 seeds) | **0.94–0.54** | **0.090** | **0.019** |
| §7 rules, after the rule | 0.96–0.67 | 0.278 | 0.139 |

Its whole game was free trailing passes: five times §7's scoring rate collapses to parity, and
possession more than halves. §7 itself is barely touched (0.92–1.05 before, 0.96–0.67 after), which
is the check that the rule taxed an exploit rather than breaking the sport. **This is not a verdict
on the rule's feel** — it is an out-of-distribution policy meeting an engine it never trained in.
It is only evidence that the thing the file depended on is gone.

Fumbles in the re-recorded corpus, as a sense of rate: 24–33 ricochets and 33–48 run-ons per full
match (~45,000 ticks, 22 players), 0 in `drill1-first-shot.txt`, which is why that one vector did
not change.

### The replay now shows the policy against itself

`--replay` writes **three** pitches from one seed, not two: `learned v §7`, **`learned v itself`**,
and `§7 v §7`. The middle one is the one to watch for shape — against §7 you are watching a policy
exploit a known opponent, which says little about whether it plays hockey; against itself there is
nobody to exploit, so what is left is what it believes a team should look like. `--versus B.txt`
replaces the middle pitch with a head-to-head. Training-loop replays (`--replay-every`) get it too.

### The change to make next

**Retrain from scratch under §6.3.1 and see whether width emerges on its own.** Nothing about the
reward or the architecture changes — the point of fixing the engine rather than the AI is that the
search should now find width because width pays, not because it was told to. Two arms, as before,
one per Mac, `--open-nets --hidden 128`, the curriculum unchanged.

What to look at, in this order:

1. **Watch the `learned v itself` pitch before reading any number.** Most of the impressive results
   of 2026-10-15/16 were bugs, and two were caught only by looking. A policy that has learned to
   stand still 1.4 m behind a team-mate and let the ball hit them is a new exploit, not width.
2. **`width` and `spacing` in `--analyse`**, against §7's 6.5 m and 7.0 m. §7's own numbers move
   under this rule too, so re-measure the §7 baseline rather than comparing against the table above.
3. **Whether the fumble rate is sane.** A side fumbling constantly has not learned the rule; a side
   that never fumbles may have learned to stop passing, which is worse than a single file.
