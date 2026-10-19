# 0011 — §7's written rules stay; the learned policy is parked

Date: 2026-10-19 · Status: **accepted** · Reverses the premise of ADR `0010`, which stated that
"§7's automatic play is being replaced by a trained neural policy" and that the decision was "not
revisited here". It is revisited here, and reversed. ADR `0010`'s *technical* content — where a
forward pass sits relative to §4.4's determinism contract — stands unchanged and still governs any
future attempt. Closes SMASH-72.

## Context

Two days, two training methods, five seeds, roughly 20,000 simulated matches across two Macs. The
aim was never a stronger opponent; the owner's words were "a realistic feeling opponent, with a
realistic feeling team", judged by him on his phone. Learning was chosen because it looked like the
best chance of getting there, on the AlphaGo analogy: make the constraints faithful enough and
human-like play should emerge.

It did not. What follows is what was actually measured, because the reasons matter more than the
verdict.

**Nothing learned ever beat the hand-written rules.** On 24 seeds no run was ever scored against,
with stamina, against §7:

| | goals | possession | spacing | nearest to ball | balls won–lost |
|---|---|---|---|---|---|
| evolution strategies + league of 16, 1,500 iterations | 0.08–0.96 | **0.264** | **6.7 m** | 6.5 m | 0.1–7.5 |
| PPO, 950 iterations | 0.25–1.62 | 0.155 | 6.0 m | 9.9 m | 0.3–5.0 |
| §7's written rules | **0.79–0.33** | 0.274 | 6.7 m | **4.2 m** | **2.2–3.7** |

The league run matched §7's possession and its spacing *exactly* — the best shape anything learned
in this project has reached — and scored 0.08 goals a match while being robbed 7.5 times. It looked
like a team and could not play like one.

**"Plays well" would not hold still as a number.** Every measure written into a reward was satisfied
without the behaviour it stood for:

- Paid to stand near the ball, a side stood near the ball and never took it: 0.4 steals a match
  against §7's 2.2.
- Paid for spacing, it filed down the middle *perfectly spaced* — 1.2 m of lateral width against
  §7's 6.8, because spacing measures the distance to your nearest team-mate and a queue satisfies
  it completely.
- Paid for width, an arm reached 5.0 m, which on inspection was four players central and two
  standing within half a metre of each other on one flank. A standard deviation cannot tell a team
  using the pitch from a file with a clump bolted to one side.
- Paid for winning the ball *symmetrically* — winner paid, loser charged — mutual idleness became
  free, because a zero-sum term cannot distinguish "both of us contest every ball" from "neither of
  us bothers". Loose-ball collection fell from 19 a match to 9 against §7's ~90.

Each of those was a reward written in good faith, gamed within hours. That is the finding: the
objective is the hard part, and this project has no way to write it down.

**Self-play's own scoreboard reports progress that is not there.** PPO's self-play numbers improved
all night — more steals, more goals — while the same checkpoints got *worse* against §7: goals
0.50–1.67 → 0.25–1.62, nearest-to-ball 7.9 → 9.9 m. Two sides co-evolve into a style that works on
each other and does not transfer, and nothing inside self-play can see it happening.

**The AlphaGo analogy does not carry the part it was being asked to carry.** That line of work
produces *strength*, not human-likeness — famously the opposite; its celebrated moves are the ones
no human would play. And AlphaZero's engine was self-play **plus tree search**, which supplies a
better target than the raw network each step. This game has no equivalent: continuous actions,
eleven simultaneous actors, 240 Hz, and a reward that arrives a goal at a time.

**Resources are a real constraint, not an excuse.** Two 16 GB laptops, one shared with another
project. The owner's own estimate — "a couple of million more matches" — is probably the right
order of magnitude, and it is two orders beyond what is available here.

## Decision

**§7's written rules remain the automatic play.** The effort goes into refining them instead.

The learned-policy work is **parked, not deleted**: `experiments/learned-team-ai/` keeps the
checkpoints and the full record, `TrainTeamAI` keeps both trainers, and `Match.policyHook`,
`Match.installPolicies` and ADR `0010`'s determinism finding stay in place. Anyone resuming starts
from measurements rather than from scratch.

**No learned policy ships.** `shared/assets/policy/` and `shared/data/policy.toml`, which ADR `0010`
anticipated, are not created. The app never calls `installPolicies`; the match the golden vectors
pin is the match that ships.

## Alternatives considered

**More compute.** Honest about the order of magnitude required and unavailable. It also would not
have addressed the objective problem: a million matches optimising a gameable measure buys a better
exploit of that measure.

**Imitate the human instead of §7.** The strongest untried idea, and the one worth resuming first:
record the owner playing and learn his release timing, which is the one thing self-play cannot
invent. Not pursued because it needs a recording harness, a phone build, and the same objective
problem returns the moment it goes beyond timing.

**Learned constants inside §7's written rules.** Keeps the structure legible and the search narrow.
Still open, and much cheaper than a learned policy — but it is a refinement of §7, which is what
this ADR chooses.

## Consequences

- §7 is the opponent, and its known faults are now the work: SMASH-54 (matches are not close),
  SMASH-55 (a carrier shoots from range instead of passing), SMASH-56 (from behind the goal it
  shoots instead of passing back). Each is something a player notices, and each is hours rather
  than nights.
- §6.3.1 — a pass arriving from behind a team-mate is no longer reliably collected — was built for
  this effort but does not depend on it. It is a rule of the pitch, it applies to the human, and §7
  plays under it without trouble. Whether it ships is a product decision, not a casualty of this
  one.
- ADR `0010` is not withdrawn. Its question — where a forward pass sits relative to §4.4 — was
  answered correctly and would be answered the same way again.
- The five traps recorded in `experiments/learned-team-ai/README.md` are the durable yield: the
  metric that cannot see a column, the unrecorded invocation, the two ladders that fight, the
  symmetric reward, and self-play's flattering scoreboard. They cost a day and a half between them.
