# 0010 — The learned policy sits inside the determinism contract
Date: 2026-10-15 · Status: **accepted** · Applies ADR 0001 (what the two platforms may share) and
§4.4 to a new concern; narrows nothing. Supersedes no ADR. Implemented against SMASH-72.

## Context

§7's automatic play is being replaced by a trained neural policy: one shared net run per player,
full team state in the observation, a continuous `strength` scalar and a per-club style vector.
That decision — a learned policy rather than hand-written rules with learned constants — was put to
the owner as a one-way door and taken knowingly. It is not revisited here.

What *is* a decision is where the forward pass sits relative to the two contracts the simulation
already lives under.

**§4.4 is stricter than most numerical code ever has to be**: only `+ − × ÷ sqrt`, evaluated in the
order the spec writes them, never fused into a multiply-add, with `sin`/`cos`/`atan2`/`exp` replaced
by our own approximations pinned bit-for-bit by `shared/vectors/math/`. **§4.7 is stricter still**:
both platforms replay every match vector and reproduce every sample exactly — "a single differing
bit is a red build", with no tolerance on either suite.

And the reason for that strictness is not merely porting hygiene, which is what the spec's own text
might suggest. The owner's reasons, recorded here because they are the thing that settles this ADR:
**replays stored as nothing but the ticks the finger moved**, and **cross-platform multiplayer**.
Both are impossible to retrofit if determinism is ever relaxed. Any argument for loosening §4.4 for
local convenience is an argument for giving up two unshipped features.

Against that, a policy forward pass is a few thousand multiply-accumulates in a loop — and a dot
product is the canonical shape a compiler contracts into FMA or reassociates under vectorisation.
`DetMath.swift:6-9` records that its no-fusion property was established by *inspecting arm64
assembly*, for seven-term polynomials. The worry was that this does not scale to a dot product, and
that ART's re-JITting at different tiers could make the same APK fuse on one handset and not
another.

**That worry does not survive checking, and the checking is what made this decision cheap.**

* **iOS.** Three dot-product forms compiled with `swiftc -O -target arm64-apple-ios18` emit zero
  `fmadd`/`fmla`. LLVM vectorises the multiplies and then extracts lanes to keep the serial add
  chain in written order — bit-identical to the scalar loop. This is semantic, not incidental: LLVM
  contracts only under its `contract` flag and reassociates only under `reassoc`, and Swift emits
  neither at any optimisation level.
* **Android.** Two independent locks, read in AOSP rather than inferred. ART's
  `TryCombineMultiplyAccumulate` (`instruction_simplifier_shared.cc`) bails unless the type
  `IsIntOrLongType`, so a floating-point multiply-accumulate is never formed; and its SIMD
  vectoriser (`loop_optimization.cc`) sets `kNoReduction` for `kFloat32` and `kFloat64` on both
  arm64 paths, so a `double` accumulator loop is never vectorised, let alone reassociated. Above
  both sits JLS strict floating point.

A dot product is not a special case. It is the same contract the cores already keep across 2,666
lines of `Match/`.

## The question

Does the forward pass live inside §4.4 and §4.7 unchanged, or does the contract change shape for
the policy — a separate numeric type, a looser provenance, its own platform-delta row?

## Decision

**Inside, unchanged, on the numerics. What changes is only the weights' channel, and the provenance
gains a corpus rather than trading one away.**

**The kernel.** `DetPolicy` in Swift and Kotlin, beside `DetMath`, same house style: no
`Accelerate`, no SIMD by hand, no `@inlinable`, nothing from `kotlin.math` but `sqrt`. One numeric
type, `Double`. The accumulation order is declared in §4.4 as a rule, the way the existing
polynomials are described by formula rather than enumerated:

> For each layer, for output `o` ascending: `s ← bias[o]`, then for input `i` ascending,
> `s ← s + weight[o · nIn + i] · x[i]`. No accumulation tree, no pairwise summation, no `fma`.

Hidden layers are ReLU **written as a comparison**, `s > 0.0 ? s : 0.0`, not `max`, so §4.4's
first-argument-on-a-tie rule never has to arbitrate a signed zero. Outputs pass through
`x / (1 + |x|)` — bounded, exact under §4.4, and chosen over a clamp because a clamp is not merely
inelegant but untrainable: past ±1 every perturbation produces the identical pinned action and the
search has nothing left to climb.

**The net draws nothing.** Every random draw stays at the sites §4.3 enumerates, so the draw list
shrinks and never grows. Discrete choices are `argmax` with the first index winning a tie.

**The weights.** Declared in `shared/data/policy.toml` — version, observation layout, layer shapes,
activation, output decode, parameter count, and the blob's SHA-256 — and baked into
`shared/assets/policy/policy-v<N>.bin` as little-endian float64 in the declared order. Both cores
verify the digest and **fail loud**; there is no fallback and no default weights. This follows ADR
0007's pattern (declared in `shared/data/`, baked into an asset, identical by construction) rather
than inventing one.

Not flat `doubles` in `shared/data/`, and the reason is a measured mechanism failure rather than
taste: `javac` compiles an 8,000-element `double[]` initialiser and fails `code too large` at
12,000 — the JVM's 64 KB limit on `<clinit>`. A 3k-parameter net fits; one widening of a hidden
layer does not. A 32-byte digest is also a stronger pin than 3,000 more rows in
`GeneratedConstantBits`.

**The vectors.** Add `shared/vectors/policy/`, recorded by iOS beside the four existing recorders
and replayed by both suites, pinning per row: the match state, **the observation vector**, every
hidden activation, the outputs, and the decoded action, every double as hex.

The observation is the load-bearing half. The dot product is the part that is safe; the observation
builder is ~100 values assembled from match state by hand and then assembled again by hand in
Kotlin — relative frames, mirroring, which player occupies which slot, what a dummy contributes,
normalising constants. That is where two stand-alone ports diverge in a way that compiles and
passes each side's own tests. It is written to sort nothing: every player is read in roster order,
the order §3 already imposes, so there is no tiebreak to get wrong.

**`shared/vectors/match/` keeps covering the policy implicitly, as it covers every other rule.** A
retrain re-records all 8 files and is a spec change under §4.7. That churn is not a cost to be
engineered away — it is the truth: a retrain changes how the AI plays in every match, which is a
behaviour change whatever the mechanism produced it. What the policy corpus buys is *feedback
latency* — a sub-second red/green on the kernel and the observation without replaying 2.6 MB of
match tape — not an exemption.

**No platform-delta row.** The match corpus makes simultaneity compulsory: a policy shipped on one
platform turns the other's suite red.

## Alternatives considered

**The policy outside the match contract**, verified only against synthetic observations. Buys
retraining without touching the match corpus. Forecloses the only check that proves the two
implementations agree *in situ* — and since the policy decides nearly everything a player sees,
that is precisely the guarantee ADR 0001 is survivable on. Rejected on merit.

**A shared third-party inference runtime** (TFLite/XNNPACK, ONNX Runtime, Core ML + NNAPI).
Legitimate on the ADR-0001 axis, since it is not our code. It fails the one property required: none
promise bit-reproducibility across platforms and several explicitly do the opposite — float32, FMA,
NEON reductions, device-dependent kernel selection, thread-count-dependent accumulation order. It
would put the simulation's output behind a kernel chosen at runtime by the handset, which costs the
replays and the multiplayer. Rejected on merit.

**Int64 / fixed-point accumulation.** Immune by construction to anything a compiler could ever do
with floating point. Costs quantisation-aware training, overflow reasoning, a second numeric
contract in §4.4, and a new class of bug at every boundary. Rejected on price — and retained as the
fallback if the on-device experiment below fails.

**Float32.** Halves the blob and is equally safe on both runtimes. Costs a second numeric type in
the one place the contract must be unambiguous, for a saving the binary channel already makes
irrelevant. Rejected weakly.

**Performance never entered it.** A 72→64→64→12 net (9,472 MACs) runs in 3.73 µs scalar-double on an
M1; ~12–15 µs on the OnePlus Nord's 765G. A worst-case 60 Hz frame is ~22 passes ≈ 0.3 ms of
16.7 ms, about 2 %, against ADR 0005's measured p95 of 16.69 ms. Budget: ≤10k MACs per pass needs no
thought; past ~30k, measure on the Nord first.

## Consequences

- **§7 stops being adjudicable prose.** Today it is ~250 lines of rules backed by
  `MatchContractTests`, `ChallengeTests`, `GoalieReadTests`, `ShotAimTests` and `FeelTests`. After
  the switch, "is this a bug?" cannot be answered from the spec — only from the corpus (do the two
  agree?) and from measured envelopes (`MeasureMatches`). **We lose the ability to say why a player
  did something.** This is the expensive half of the work, and it is larger than the kernel.
- **Every retrain is a spec event** that re-records all 8 match vectors.
- **Both platforms must land together**, enforced mechanically rather than by discipline.
- `§4.3`'s draw-site enumeration shrinks: §7.6's per-candidate `noise(0.8)`, §7.3's marking chance
  and §7.8's goalie `noise(0.5)` go; the re-think draw in `thinkTeam` stays.
- The coach's board (§12) goes inert, since the policy reads a learned style vector instead of the
  six tactic sliders. §7.10's rubberband currently tilts the match *by moving board numbers*, so
  what feeds `strength` is an open product question, not a technical one — the owner has said it
  should be adapted during the match.
- `DetPolicy`'s loop must not be "optimised". The toolchain guarantees are about that shape of loop.

## What must be true, and the experiment that falsifies it early

The guarantee rests on both toolchains, and only one of them was checked on a real device. **Before
any trained weights are relied on**: write `DetPolicy` twice at final shape, weights from a fixed
`SplitMix64` seed, 1,000 observations, dump every hidden activation and output as hex and hash the
dump. Run Swift on the Mac; run Kotlin under `./gradlew :core:test` **and on the OnePlus Nord** —
the JVM run proves nothing ART does not, so the device run is the experiment. Include three loop
forms (plain, `+=`, hand-unrolled-by-4) and require an identical hash from all three.

If the device disagrees with the Mac on any form, the kernel moves to int64 fixed point and §4.4
grows a second numeric contract — at the cost of a day, not three weeks.

Separately, and **before** §7 is rewritten: confirm the match corpus actually bites, by flipping the
last bit of one `Tuning.AI` constant and checking all 8 files go red on both platforms. The rewrite
re-records them, and from that commit the old behaviour exists only in git history.
*(Done, 2026-10-15, in the weaker direction: adding the policy hook with `policy` unset leaves all
225 tests and all 8 match vectors green, so the hook provably changes no tick.)*
