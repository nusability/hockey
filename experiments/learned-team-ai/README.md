# Learned team AI — the experiment's artifacts (SMASH-72)

Three policy checkpoints and what they measure. **Nothing here ships.** The shipped path for
weights is `shared/assets/policy/` with a declaration in `shared/data/policy.toml` and a spec
change (ADR `0010`); these are experiment outputs kept because they cost hours of compute and
because the numbers below are only meaningful next to the weights that produced them.

All three are `107 → 32 → 32 → 2`, 4,578 parameters, one hex IEEE-754 double per line in
`PolicyNet.parameters` order. Load one with:

```
cd ios/SmashCore
swift run -c release TrainTeamAI --evaluate experiments/learned-team-ai/balanced.txt \
    --matches 120 --eval-offset 5000 --period 40 --hidden 32
swift run -c release TrainTeamAI --analyse  experiments/learned-team-ai/balanced.txt \
    --matches 24  --eval-offset 5000 --period 40 --hidden 32
swift run -c release TrainTeamAI --replay   experiments/learned-team-ai/balanced.txt \
    --period 40 --hidden 32 --replay-seed 5000
```

`--eval-offset` matters. The search selects its best on seeds `0..<24`, so a number measured
there is a number it was allowed to fit. Every figure below is on seeds `5000+`, which it has
never been scored against.

## What each one is

| File | Trained on | What it is |
|---|---|---|
| `clone.txt` | Imitation of §7 (Adam) + 3 DAgger rounds | The faithful copy. The control. |
| `winner.txt` | Maximise goals + shape proxies | Best at the game, worst to watch |
| `balanced.txt` | Beat §7 on goals, **match** §7's shape | The recommended one |

## Results, on 120 unseen seeds

§7's own goal difference on these seeds is **−0.08** (it is not symmetric — the two sides are
different clubs with different ratings).

| | goals | goal difference | gap to §7 |
|---|---|---|---|
| `winner.txt` | 0.76–0.38 | **+0.38** | **+0.46** |
| `balanced.txt` | 0.79–0.44 | **+0.35** | **+0.43** |
| §7 rules | 0.80–0.88 | −0.08 | — |

Both beat the hand-written AI, and both do it **by defending**: §7 concedes 0.88 a match, the
learned sides 0.38 and 0.44. They score no more than §7 does; they let in half as much.

## Shape, on 24 unseen seeds — and the one that will not come

None of these are trained on except width, deliberately, so that most of them stay honest checks.

| | swarm | churn/min | depth | goal-side | **width** | spacing |
|---|---|---|---|---|---|---|
| `clone.txt` | 9.46 m | 60.7 | +4.98 m | 71 % | 4.9 m | 4.9 m |
| `winner.txt` | 10.17 m | 48.6 | +4.24 m | 64 % | 4.2 m | 6.2 m |
| `balanced.txt` | 10.13 m | **49.6** | +4.89 m | **71 %** | 4.6 m | **6.6 m** |
| §7 rules | 11.02 m | 52.2 | +5.45 m | 72 % | **6.5 m** | 7.0 m |

`balanced.txt` matches §7 on goal-side discipline and beats it on role churn, and comes within
0.4 m on spacing and 0.6 m on depth — while beating it by **+0.43 goals a match**, within a
rounding error of what the shape-blind `winner.txt` manages. The trade-off that looked real an
hour earlier (0.15 goals for the shape) largely dissolved as the search continued: it learned to
do both. An earlier checkpoint of the same run read depth +5.70 m, goal-side 73 %, width 4.8 m at
a gap of +0.31; the differences in shape between the two are inside what 24 seeds can resolve,
and the difference in goals is not.
**Width is the exception, in every policy, including the faithful clone.**

That is not a tuning failure, it is the architecture. Depth, goal-side position and
nearest-team-mate spacing are all decidable from one player's own view — *am I behind the ball,
is anyone close to me* — so a per-player net learns them. Width needs players to occupy
**different** lateral lanes, which needs knowing which lanes are taken. §7 gets that from §7.4's
greedy "nearest free slot" assignment and §7.5's pairwise push, both team-level by construction.
One shared net run per player has no way to ask the question, and **no reward can supply
information that is absent from the observation.**

## The recommended next step

Have the net output a **preference over §7.4's slots** instead of a point, and resolve conflicts
with a deterministic greedy assignment in roster order — §7.4's own mechanism, with the spec's
existing tie rule. Coordination becomes structural; roster-agnosticism survives (preferences stay
per-player, so five formations and drill dummies are fine); it is §4.4-safe, being comparisons and
ordering only; and it restores the explainability ADR `0010` names as the main cost of going
learned — you could see which slot each player was given, and say *why* one moved.

Do that before spending more compute on rewards. Five reward variants were tried in one night and
none of them bought the width back.

## What is still §7's

Only off-ball movement (§7.1–§7.5) is learned. The carrier's decisions (§7.6) and the goalie
(§7.8) are still the written rules. `strength` and the per-club style vector are in the
observation from the first commit but held at fixed values — there is no ladder to distil yet.
