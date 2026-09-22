# `shared/`

What the two stand-alone implementations may share (`decisions/0001-*.md`): config, some assets,
and the simulation's golden vectors. None of it is code either platform links.

## `data/` — one declaration, generated into both apps

| File | Holds (spec) |
|---|---|
| `rules.toml` | the simulation's numbers: time step, pitch, players, orbit and release, ball, automatic play, match, slow motion, training, season; the two sports and the matchday plan (§1, §3–§8, §10, §11) |
| `teams.toml` | worlds, formations, default tactics, the coach's board, the eight clubs, the career (§2, §3, §12, §13) |
| `drills.toml` | the eight drills with lineups, dummies, patrols and rules (§10) |
| `math.toml` | the deterministic math's constants, as exact IEEE-754 bit patterns (§4.3–§4.4) |
| `copy.toml` | every user-facing string, English and German (§14); club, world, formation and drill names live next to what they name |
| `save.toml` | the save records — career, season in progress (seed and stream position), training, coach's board — with a `version`; generated into types plus a canonical JSON encoder and a strict decoder, so both platforms write the same bytes (§15) |
| `motion.json` | the UI's motion tokens (ADR 0005) — also loaded by the apps at runtime |

**TOML**, because every number sits next to a comment naming its spec section, and Python reads it
with the standard library (`tomllib`). A float is written `3.0`, an integer `3`; the generator
rejects a quantity written as an integer.

`python3 tools/generate-data.py` (Python 3.11+, stdlib only, deterministic) validates the
declarations — fail loud, naming the file and key — and writes:

- `ios/SmashCore/Sources/SmashCore/Generated/*.swift` — `Tuning.*`, `Sport`, `World`,
  `Formation`, `Club`, `Career`, `Drill`, `Season.plan`, `CopyKey`, `MathConstants`;
- `android/core/src/main/kotlin/in/nann/smashhockey/core/generated/*.kt` — the same, idiomatic
  Kotlin (enum entries in UPPER_SNAKE, `of(key)` throws for an undeclared key);
- `ios/Sources/Localizable.xcstrings` and `android/app/src/main/res/values{,-de}/strings.xml`
  (Android names are the keys with `.` → `_`; `{name}` placeholders become positional string
  arguments, `%1$@` / `%1$s`);
- a table of every generated double with its exact bits, which both test suites assert — a
  toolchain that parsed a literal differently turns a suite red instead of drifting the game.

Generated files are committed, so a clone builds without the generator. **They are never edited
by hand:** `python3 tools/generate-data.py --check` exits 1 when any of them differs from what
the declarations would produce (or when a stale file sits in a generated directory).

## `vectors/` — what both suites replay

Golden vectors: inputs and expected outputs as the hex of IEEE-754 bits, compared **bit for bit**
— never with a tolerance. Recorded by the first platform to land a rule, replayed by both. A
mismatch is a red build on whichever platform moved. Re-recording a vector requires a spec change
in the same commit — a red vector fixed by regenerating the file is drift laundered through the
gate built to stop it.

Live today — `vectors/math/` (§4.3–§4.4), recorded by iOS (`cd ios/SmashCore && swift run
RecordVectors`, macOS arm64; it refuses to overwrite a differing file without `--rerecord`):

| File | Rows | Pins |
|---|---|---|
| `splitmix64.txt` | 3,000 | the first 1,000 outputs of seeds 0, 42, 0xDEADBEEFCAFEF00D |
| `uniform.txt`, `noise.txt` | 1,000 · 600 | `uniform()` and `noise(s)` for s = 1.6, 0.8, 0.5 |
| `sin.txt`, `cos.txt` | 2,693 each | [−4π, 4π], ±300, ±1e6, and both sides of every reduction boundary |
| `atan2.txt` | 3,021 | ±50 on both axes, magnitudes 2^−60…2^60, zeros and axes |
| `exp.txt` | 2,294 | [−50, 5], multiples of ln 2, overflow and underflow |
| `length.txt` | 505 | `sqrt(x² + z²)` |

Live too — `vectors/season/` (§2.2, §11, §15), recorded by iOS (`swift run
RecordSeasonVectors`): two whole seasons (a picked club; a created team) with every fixture,
result, table and bracket, 486 simulated results, the created-team rules, quick-match draws, and
save files byte for byte — including 21 malformed saves and the typed error each must raise.

Replayed by `ios/SmashCore` (`swift test`, and in the app scheme's `xcodebuild test`) and by
`android/core` (`./gradlew :core:test`). Match vectors (§4.7) arrive with the simulation.

## The deterministic math

`DetMath` (Swift, Kotlin): `sin`/`cos` reduce by k = ⌊x·2/π + ½⌋ with a three-part Cody–Waite
π/2 (exact for |x| ≤ 1e6; beyond, or non-finite, fails loud), then fdlibm's degree-13 sine and
degree-14 cosine minimax polynomials; `atan2` reduces to atan on [0, 1], split at 7/16 and 11/16
around 0, ½ and 1, with fdlibm's 11-term series; `exp` reduces by k = ⌊x/ln 2 + ½⌋ with a
two-part ln 2 and fdlibm's five-term Remez polynomial in r² inside its rational form, scaled by
2^k built from bits.
Measured max absolute error against the platform's libm: sin/cos 2.2e-16, atan2 4.4e-16, exp
2.8e-14 on [−50, 5] (1 ulp of e^5) — the spec's bound is 1e-9.

Only `+ − × ÷`, `sqrt` and exact floor are used, each written as its own step in the same order
on both platforms. No fused multiply-add: Swift emits no FP-contraction flag, and the arm64
assembly of SmashCore's math has zero `fmadd`/`fmsub`/`fnmadd`/`fnmsub` at `-Onone`, `-O` and
`-Osize`; Java/Kotlin floating point is strict (JEP 306) and HotSpot/ART only fuse on an explicit
`Math.fma`.

## `assets/`

Models, textures, fonts and sounds both apps load, where one file serves both.
