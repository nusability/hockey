# AGENTS.md

Operating rules for agents and humans. Terse by design. Values & rationale: `principles.md`.
Stack-specific standards: `conventions.md`.

## What this repo is
**Slapshot League** — a stylised 3D field-hockey game (and one ice world) with one-touch
control — on its way to the **App Store and Google Play**, free-to-play with IAP. Five surfaces
live here:

- **iOS app** (`ios/`) — the product on iOS. Swift + SwiftUI. Built to `spec/`, prod-grade,
  no prototype mindset.
- **Android app** (`android/`) — the same product on Android, held to the same bar. Kotlin +
  Compose. A **second native codebase**, not a build target: it shares no executable code of
  ours with `ios/` (ADR `0001`). Both are built **in parallel** from the first commit — there
  is no "iOS first, Android later".
- **`shared/`** — the only things the platforms share, and neither is code either links:
  `data/` (declarations generated into both builds — tunables, teams, drills, copy) and
  `vectors/` (seeded golden vectors **both suites replay**, recorded from the web reference).
- **`web/`** — the original web build (vanilla JS + Three.js, no build step), served on GitHub
  Pages. It is the **prototype stage** — where feel, AI tuning and balance are tried cheaply
  before they earn a spec entry — and **the parity reference** the ports are measured against
  (ADR `0002`). Not a shipping target for the stores.
- **`spec/`, `decisions/`** — the as-is spec and the ADRs.

`web/` is a **sandbox and a reference**, never a store target. Nothing in it is bound by the
spec; nothing in either app is exempt from it.

## The port — both platforms move together
There is no product on either store yet. The standing goal is **port the game to both
platforms at once, to the spec, at parity with `web/`**, and then keep them in step. The plan
lives on Stori (`SLAP`); the what lives in `spec/`.

- **Every change is a two-codebase change.** A change that lands on one platform and not the
  other needs a dated delta row in the spec on the day, naming the item that closes it.
- **A thing that is hard to change twice is the wrong thing.** The cost is paid on every
  future change, not once.
- **Identical visuals.** A costume that is nearly right on one platform is a bug, not a
  platform characteristic. Exceptions are written rows in the delta table.
- **Each platform gets its own best answer** to how it is built, never a transliteration of the
  other. `/architecture` decides where that calcifies.
- **Payments stay each store's own** — Play Billing on Android, StoreKit on iOS, never a
  translation layer over the other's shape.
- **The vectors are what make this survivable.** The simulation is deterministic and seeded;
  `web/` records the corpus, both apps replay it, a drift turns a suite red.

## Sources of truth
- **Current state** → `spec/` (as-is spec). Read first, always.
- **Values/rules** → `principles.md` (constitution). Overrides everything.
- **Stack standards** → `conventions.md`.
- **Durable technical why** → `decisions/` (ADRs).
- **Ideas / not-yet-built changes / the porting plan** → Stori project `SLAP` (Now / Next / Later).

## Golden rule
Behavior change ⇒ spec change **in the same commit**. New public surface ⇒ its spec entry,
same commit. No spec-only or code-only commits for behavioral changes.

**And on both platforms.** A behavior change lands on iOS *and* Android in that same commit —
or it adds a **dated platform-delta row** to the spec naming which platform is behind and why.
There is no third option: **a platform silently behind is the failure this rule exists to
prevent**, and it will not announce itself, because the build that is behind still compiles
and still passes its own tests.

> **During the port** the delta table carries one temporary row per spec section a platform
> has not reached yet. A section is ported by deleting its row(s) in the same commit as the
> code. The goal for temporary rows stays zero.

**`web/` is exempt** — commits there need no spec diff. The moment a prototyped mechanic is
adopted for the apps, it goes through the loop below like anything else. *Exception:* a change
to `web/`'s simulation that moves a recorded vector is a spec change (the vectors are the
contract, ADR `0002`).

## The loop — branchless, trunk-based
As-is = the last commit (HEAD). To-be = your uncommitted edits to the spec.
Steps 2–4 and 6 are skills — invoke them; they carry the detailed procedure.
1. **Capture** the idea → Stori work item in `SLAP`; bucket Now / Next / Later; → In Progress.
2. **`/sdd-clarify`** — resolve unknowns before non-trivial work; fold answers into the spec. Re-run at each topic switch; honor a stop.
3. **`/sdd-spec`** — edit `spec/` (working tree) to the *desired* state. `git diff` = scope. Review it before coding.
4. **`/sdd-plan`** — technical approach + tasks on the Stori item (ephemeral). Lasting choice? → `decisions/NNNN-*.md` (ADR). One-way door you cannot settle? **`/architecture`** — it briefs the `mobile-architect` subagent, which decides in its own context and hands back the ADR's substance.
5. **Build** code until behavior matches the spec — on both platforms.
6. **`/sdd-verify`** — code == spec (conformance); fix the spec if reality forced changes.
7. **Bump** `Spec-Version` per SemVer (below).
8. **Commit** spec + code **together** — that commit is the new as-is. **Ship to main, no PRs** (branch only when asked; the gate is the reviewed to-be diff, not a PR).
9. **Tag** `spec-vX.Y.Z` (annotated). Close the Stori item; link the commit.

One change in flight at a time (the uncommitted diff is your only to-be).
Skills lifted in spirit from GitHub Spec Kit (`/clarify` · `/specify` · `/plan` · `/analyze`).

## Workflow rules
- **Prototype in `web/` before spec'ing a feel-dependent mechanic.** Game feel, AI behaviour,
  difficulty and economy pacing are cheaper to judge in the web build than to argue about in
  prose. Play it, then spec what survived. *(Mechanics & economy — not a licence to prototype in
  the apps.)*
- **Click-dummy new UI first.** Approve a throwaway prototype before it touches the apps. *(UI only.)*
- **Press on when told.** Ship the next item; no recaps, no "good place to stop."
- **Rollback is a real option.** Offer discarding the work *when the work is in doubt* — not as
  a routine menu at the end of something that worked.
- **Pause before promoting half-working features.** Push to main, hold the store submit.
- **Ask only what changes what gets built.** A question earns its place when two readings lead
  to materially different work, or when a player would feel the difference. Commit
  granularity, the order of items, which small adjacent bug rides along, whether to file or
  fold — **decide those and say what you decided.**
- **Technical one-way doors go to `/architecture`, not to a menu.** Product forks — two things a
  player would feel differently — are the escalation that survives.

## Verification
- **Verify against reality, not assumptions.** Check the real thing, not what you expect.
- **Verify anything web in a browser.** Read the console; confirm visibility, not DOM presence.
- **Verify each app on a device or its emulator** — iOS on a device or simulator, Android on a
  device or emulator. A gameplay change is verified by **playing it, on both**.
- **The vectors and the hands are both required.** Golden vectors prove the numbers agree
  across `web/`, iOS and Android; only a person holding the phone proves it feels right.
  Neither alone verifies a gameplay change.
- **Performance is verified on the low end.** A rendering change is measured on the weakest
  supported Android device we have, not only on a flagship.
- **Economy and monetization changes are verified against the numbers.** State the resulting
  earn/spend rates and time-to-unlock; "feels right" is not a result.
- **TDD:** contract → failing test → green. Reverting the fix must fail the test.
- **Every test sits on the path to production for its change.** A test in no pipeline gets removed.
- **Don't bypass blocking gates in tests.** Exercise paywalls, IAP, and consent flows by
  clicking through them, not by seeding entitlements.
- **Run the full test suite after a dependency change.** Pin runtime-critical deps exact.
- **Pre-existing failures get filed, not dismissed.** File a Stori bug and carry on; never
  note-and-move-on an unrelated FAIL.

## Safety
- **Never echo or inline secrets.** Move them via file or secret store. This includes App Store
  Connect keys, Play service-account JSON, signing certs, upload keystores and their passwords.
- **No hardcoded fallbacks for infra config — fail loud.** Resolve required infra config
  (endpoints, product ids, secrets) or abort; never `?? "<literal>"` a real resource.
- **Never fabricate an entitlement client-side.** Purchases and currency balances resolve
  through one verified path; no debug switch that grants currency ships.

## Versioning & deploys
- **Spec is the only SemVer line.** Header `Spec-Version:` is authoritative; git tag `spec-vX.Y.Z` on the commit.
  - **MAJOR** — removed or breaking behavior. **MINOR** — new, backward-compatible. **PATCH** — clarification, no behavior change.
- **`Spec-Version` covers both platforms.** One SemVer line for one specification.
- **Each app ships build numbers, not product SemVer.** A release is a submitted build of a
  commit SHA, to one store; the marketing version is a store field, not an engineering
  contract.
- **`web/` deploys itself.** A push to `main` touching `web/**` publishes it to GitHub Pages
  (`.github/workflows/pages.yml`); nothing else in the repo is ever published there.
- **Conformance is proven by tests, not a number.** A bug (impl ≠ spec) is a conformance gap,
  not a spec-version event.
- **Spec tags are annotated (`git tag -a`), never lightweight.** `git describe` ignores
  lightweight tags, so a lightweight `spec-v*` silently reports the previous version as current.
- Scope `git describe --match 'spec-v*'` so the spec tags aren't confused with any other tags.

## Spec hygiene
- Describe behavior & contracts, not implementation.
- One system, one spec. Don't fork state across work items.
- Spec lying about the code? Fix it (PATCH) — always in scope, no ticket needed.
- **The spec covers both apps and, once it exists, the release toolchain.** It is written once
  for both platforms with a **dated platform-delta table** for every place they are allowed to
  disagree.
- **The spec does not cover `web/`.** It names it only as the parity reference, and names the
  vectors recorded from it.

## Stori usage
- Idea / intent / priority / discussion / ephemeral plan → work item. NOT the authoritative "what to build".
- The authoritative to-be is the **uncommitted spec diff**. The work item points to it.

## Do NOT
- ...piece current state together from work items. Read the spec.
- ...commit behavior code without a matching spec diff in the same commit.
- ...park future functionality inside `spec/`. That's Stori's job.
- ...ship `web/` to a store or copy-paste its code into an app. Port the tuned numbers and the
  proven behaviour; write the implementation properly on the other side.
