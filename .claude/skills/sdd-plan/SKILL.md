---
name: sdd-plan
description: Plan the how. Turn a reviewed spec diff into a technical approach + task breakdown — ephemeral, on the Stori item. Lasting/one-way-door choices become ADRs. Use after sdd-spec, before building.
---

# sdd-plan

Lifted from Spec Kit's `/plan` + `/tasks`, kept **ephemeral**. The plan is *how* to get from
as-is to the spec'd to-be; it dies at commit. It never enters `spec/` (that's durable *what*).

## Procedure
1. Take the reviewed `spec/` diff as the target.
2. Produce, on the Stori work item in `SLAP` (body/attachment):
   - **Approach** — architecture, data shapes, interfaces, integration points.
   - **Tasks** — ordered steps, dependencies marked, **riskiest first** (principle 18).
   - **One-way doors** — name foundational, hard-to-reverse choices explicitly (principle 15).
3. **Scope down before over-engineering** (principle 19): sketch the smaller version, ask.
4. Lasting technical decision (engine, storage, IAP model, netcode, a one-way door)? Write an
   ADR: `decisions/NNNN-title.md` — Context · Decision · Consequences. The *why* code can't explain.
5. New UI? Approve a throwaway click-dummy first (AGENTS: click-dummy new UI). *(UI only.)*
6. Feel-dependent mechanic or economy pacing? Plan the `web/` prototype as the first task —
   tune it there, then build the app against the tuned numbers.

## Boundaries
- Plan text lives on Stori, not in `spec/`.
- Only lasting *decisions* graduate to `decisions/`; step-by-step tasks stay ephemeral.
- Prototype code stays in `web/` and never graduates into the app by copy-paste.
