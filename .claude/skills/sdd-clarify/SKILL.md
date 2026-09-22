---
name: sdd-clarify
description: De-fuzz a change before spec'ing it. Structured, coverage-based questioning that surfaces underspecified areas and folds the answers into the spec. Use BEFORE sdd-spec on any non-trivial add/change/remove, and re-run at each topic switch.
---

# sdd-clarify

Lifted from Spec Kit's `/clarify`. Purpose: kill ambiguity *before* it becomes wrong code.
This is a **gate**, not a document — the resolved spec is the record.

## Procedure
1. Read the as-is `spec/` for the affected area + the Stori work item in `SMASH` (intent).
2. Scan for underspecified areas, by coverage — check each dimension, don't free-associate:
   - **Behavior**: happy path, edge cases, error/empty states.
   - **Terms**: any word that could mean two things → pin it.
   - **Contracts**: inputs, outputs, side effects, idempotency.
   - **Constraints**: limits, security, performance, compatibility (esp. player-data compat — principle 13).
   - **Economy** *(any change touching currency, rewards, pricing, or progression)*: which
     currency, earn rate, sink, cap, and what it does to time-to-unlock. Does it touch a
     competitive surface? If yes, "compared against whom?" (principle 1) is a blocking
     question — purchased advantages must be part of the answer.
   - **Out of scope**: what this change deliberately does NOT do.
3. Ask the highest-impact ambiguities first, as one batch of concrete questions
   (offer a recommended default per question). Not a vibe check — each question must
   change what gets built.
4. **Prefer a prototype to a question when the unknown is feel.** If the answer is "does this
   play well", the honest resolution is a `web/` build to try, not a paragraph. Say so.
5. Record decisions: fold them into the to-be spec wording; drop a short **Clarifications**
   note on the Stori item for provenance.
6. **Stop** when no blocking unknown remains, or the user says stop.

## Gate
Do not proceed to `sdd-spec` while a blocking unknown would force a guess about observable
behavior. A non-blocking unknown → note it and move on.
