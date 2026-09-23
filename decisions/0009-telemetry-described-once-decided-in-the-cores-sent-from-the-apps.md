# 0009 — Telemetry described once, decided in the cores, sent from the apps
Date: 2026-09-23 · Status: **accepted** · Applies ADR 0001 (what the two platforms may share) to a
new concern; narrows nothing

## Context

Two things arrive together before the first store submission (SMASH-50, SMASH-51): anonymous
product analytics, and a love dialog that asks "Enjoying Smash Hockey?" at a moment the player is
happy. They look like separate features and are not: the dialog's answers are four of the events,
and both need the same thing the game has never had — **a durable record outside the save, and a
decision that depends on the wall clock.**

Three forces make this a decision rather than a coding task.

**Everything here is a one-way door.** Event names, the payload shape, the persistence keys and the
install id's existence are fixed the moment a build ships: a renamed key resets every player's
cooldown and re-asks people who already said yes; a renamed column silently splits a metric in two.

**The two platforms must not be able to disagree.** `../flashybird` kept its collector's column list
by hand and quietly dropped fields for months. A spelling is exactly the kind of thing two
stand-alone implementations (ADR 0001) get wrong in a way that compiles, passes both suites and is
invisible until the dashboard is wrong.

**The decision is time-dependent, which is where correctness usually goes to die.** "One showing per
90 days" straddles DST, a clock corrected backwards, a timezone flight, a restored backup. Proving
it on a phone takes ninety days. Proving it wrong takes one released build.

And the constraints already on the books bind: **A0** (nothing between finger and ball), **A2** and
the spec's own invariant (nothing between a result and the next face-off), **§4 determinism** (the
simulation is seeded, never ambient), and **principle 13** (player data is sacred).

## The question

Where does each part live — the wire shape, the decision, the queue, the storage — given that the
only things the two apps may share are descriptions, never code (ADR 0001)?

## Decision

**Share the description of everything, the implementation of nothing, and pin the agreement with a
corpus.** The same shape `shared/data/save.toml` already has, applied to a second concern.

### The wire shape is declared once

`shared/data/telemetry.toml`, declared exactly as `save.toml` is: a `[format]` version, then one
`[record.*]` per record, fields as `name = "type"` over the same base-type vocabulary.
`tools/datagen/telemetry.py` emits `Generated/TelemetryRecords.swift` and
`generated/TelemetryRecords.kt`, reusing the existing canonical JSON writer (`SaveJSON` /
`SaveJson`) rather than a second one.

The generator that reads both declarations is one module (`tools/datagen/records.py`); `save.py` and
`telemetry.py` are the two declarations of it. One record engine, two tables — principle 14, and the
reason a field added to either declaration cannot be spelled differently on the two platforms:
**neither platform spells it.** `python3 tools/generate-data.py --check` fails on a hand-edit, which
is the guard, and it is proven to fail rather than assumed to.

When the collector is built, the same generator emits its column contract from the same
declaration. That artifact — and nothing else — crosses to the server. A hand-kept column list is
the failure we are buying our way out of.

### The decision logic lives in both cores, hand-written twice, pinned by one corpus

In `ios/SmashCore/Sources/SmashCore/Telemetry/` and `android/core/.../core/telemetry/`:

- **`LoveMatch` / `LoveFacts`** — values. Counts, and instants as `Int64` **epoch milliseconds**;
  never `Date`, never `Instant`. SmashCore contains no use of `Date` today and this keeps it that
  way.
- **`LovePolicy.trigger(_:)`** — does this finished match arm the prompt? Pure, from the match's own
  goal tape.
- **`LovePolicy.decide(_:now:)`** — may we show it, right now? Pure, total: no clock, no storage, no
  UI. Elapsed time is integer milliseconds throughout — never calendar days, never a `Double` — so a
  golden vector pins it bit-exactly instead of within a tolerance.
- **`DeviceRecord`** — the durable counters, a generated record whose transitions are **values**:
  `record.recordingPresentation(at:)` returns a new record. Not a side effect.
- **No `URLSession`, no OkHttp, no `UserDefaults`, no `SharedPreferences`, no wall clock in the
  core.** The clock is an argument.

**§4 determinism is untouched by construction, not by test.** Telemetry reads `MatchSnapshot` /
`MatchEvent` values after the fact and draws from no seeded stream; there is no path from a
telemetry value into the simulation. Nothing to defend, so nothing is defended with a test.

### The corpus is the point

`shared/vectors/telemetry/love.txt`, in the style of `shared/vectors/season/`: a script of steps
carrying the clock — `launch`, `match`, `settle`, `answer`, `bytes` — with the expected trigger, the
expected verdict and the resulting record after **every** step, and the record's canonical JSON
bytes pinned at chosen ones. Both suites replay it.

A clock moved backwards, a cooldown straddling a DST boundary, a restored backup, an absent
record — each is a line in the script, not a three-day wait on a phone. This is the whole bet, and
it is taken first, before any UI or network exists: **if a time-dependent policy cannot be pinned
headlessly by a corpus, the design collapses back to platform-layer twins, and we want to know that
in an afternoon rather than after the client is built on top of it.**

### The queue lives in the platform layer and nothing about it enters the core

An in-memory array, appended on the main actor — no I/O, no request construction. Flushed on
background and on arrival at the hub; **never on the result screen, never on any input path, never
between a result and the next face-off** (A0, A2). Fire-and-forget on a utility queue /
`Dispatchers.IO`, bounded backlog, oldest dropped first, a failed send dropped rather than retried.

**Not persisted across launches.** That would be a second persisted shape and a second write path
near the frame, bought for events whose loss changes no decision we will make.

### Persistence: a second file beside the save

`device.json`, in the same directory as `save.json` (Application Support / `filesDir`), declared in
`telemetry.toml` with its own `[format]` version and written atomically by a `DeviceStore` twinned
on the existing `SaveStore`. **Not `UserDefaults` / `SharedPreferences`:** two hand-kept key lists
with two coercions and two backup behaviours is exactly the duplication the declaration exists to
kill, and only a file can have its bytes pinned by a vector.

Three rules, and they are the whole reason it is a separate file rather than a branch of the save:

1. **A refused save must not be able to reach it.** The refusal screen (§15) moves `save.json`
   aside, and "start over" wipes the career; `device.json` is outside both blast radii. The
   constraint "answering yes must survive starting over" is then satisfied *literally*, not by
   discipline.
2. **A refused `device.json` is never a refusal screen** — telemetry may not block the game. It is
   moved aside and replaced, and the replacement is stamped **as if the prompt had just been
   shown** (`installed_at = now`, `last_asked_at = now`). A lost record must read as brand new and
   serving a full cooldown, never as long-ago-and-eligible; otherwise one corrupt byte re-arms the
   prompt for someone who already said yes.
3. **Excluded from backup on both platforms** (`isExcludedFromBackup` on iOS, out of
   `dataExtractionRules` on Android). An install id restored onto a new phone is one install counted
   as two, forever. `save.json` stays backed up — player data is sacred (principle 13).

## Alternatives considered

**Put the counters in the save record.** One file, one store, no new shape — and wrong on both
rules above: the refusal screen and "start over" would each re-arm a prompt the player has already
answered, and the save is backed up, so an install id in it would ride to a new phone.

**`UserDefaults` / `SharedPreferences`, as `../vidi` does.** Cheapest to write and what the model
implementation uses. Rejected because it is precisely two hand-kept key lists — one per platform —
with two coercions, two absent-value behaviours and two backup behaviours, none of which a vector
can see. Vidi has one platform; we have two, and the whole design here exists to stop them drifting.

**Share the policy as a real shared artifact** — a small interpreted rule table in `shared/data/`,
or a cross-compiled core. Tempting for a rule this fiddly. Rejected: ADR 0001 is the standing
decision that the platforms share no executable code, and a rule engine is executable code wearing a
data hat. The corpus buys the same guarantee — agreement, checked — without the door it would open.

**Write the policy once in the platform layer on each side** (the `../vidi` shape, twice). This is
the fallback if the bet above fails. It costs the headless corpus: the rationing could then only be
observed by running an app with a moved clock, on two platforms, by hand.

**Per-tap event tape, as `../flashybird` collects.** Rejected in SMASH-50: we have no difficulty
heatmap to fill, and the volume would make the queue a real system rather than an array.

## Consequences

- **A new declaration file and a second generated record family.** The record engine is now shared
  by two tables, so `save.toml`'s emitted bytes are load-bearing regression coverage for
  `telemetry.toml`'s and vice versa.
- **A new base type, `i64`,** for epoch milliseconds — a plain JSON integer, exact below 2⁵³, with
  its own strict decode. `int` stays 32-bit on both platforms and could not hold an instant.
- **Two files in the save directory, with different rules.** `save.json` is backed up and its
  refusal stops the game; `device.json` is not backed up and its refusal is silent. Anyone touching
  either has to know which is which — written here, and in §15.
- **The love dialog's timing is provable in an afternoon** and re-provable on every commit, on both
  platforms, for as long as the corpus is replayed.
- **The clock is an argument everywhere in the core.** A call site that wants "now" has to have been
  given it, which is what makes the corpus possible and what keeps §4's ban on ambient time honest.
- **What this does not settle:** the collector. It is taken on trust here that the server will
  accept a flat column set per event kind. If it turns out to want nested per-event payloads, the
  generated-record path costs a small schema language instead of a second declaration, and the
  honest answer flips to one flat generated envelope carrying a typed, generated property map.
  **Settle that when the collector is built, not before.**
