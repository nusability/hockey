---
name: architecture
description: Consult the architect on a one-way door. Hands a foundational native-mobile choice — render layering, clocks, thread and state ownership, persistence shape, module boundaries, what the two platforms may share — to the `mobile-architect` subagent, which reasons in its own context and returns a decision with the honest cost of each path. Use when a choice will calcify, or when sdd-plan hits one.
---

# architecture

Step 4 of the loop calls for naming one-way doors (`sdd-plan`, principle 15). This is who you
call when naming one is not enough and it has to be **decided**. The architect runs as a
subagent in its own context — so it starts with nothing you know, and the brief is the work.

## Procedure
1. **Write the brief before you invoke.** In the `Agent` prompt, with `subagent_type: mobile-architect`:
   - **The question**, as a decision to be taken — not "how should we do X" but "X can be A or B".
   - **What is already settled and must not be reopened**, with the ADR or spec line that settles
     it. An architect who re-litigates a decided thing has spent its context on the wrong argument.
   - **The constraints** — the spec sections that bind, the platform-delta rows in play, the
     surfaces and files it should start from, and the deadline or scope pressure if there is one.
   - **What you already know is wrong** with the obvious answer, and why. Prior failures are the
     most valuable thing in the brief and the thing the subagent cannot discover.
   - Name the pointers; do **not** paste the files. It reads.
2. **Do not pre-answer it.** State the options neutrally. A brief arguing for one path gets that
   path back, which is an expensive way to hear yourself.
3. **Relay the recommendation to the user in full** — the subagent's report is not shown to them.
   Lead with the decision and the cost of the path not taken.
4. **Lasting? Write the ADR.** `decisions/NNNN-title.md` — Context · The question · Decision ·
   Alternatives considered · Consequences. The answer is already most of it. Record it as *your*
   decision with the reasoning, never as "the architect said so".
5. Behaviour changes with it? Back to `sdd-spec` — the spec diff is still the scope.

## Boundaries
- **It advises; you build.** It has no write tools and no authority over the tree.
- **The user owns product forks.** A choice between two things the player would feel differently
  is escalated to them, not delegated to an agent (principle 15).
- One question per consultation. Two bundled questions get one blurred answer.
- Don't consult it on the reversible. Most decisions are; those get the elegant default and no
  ceremony (principle 19).
