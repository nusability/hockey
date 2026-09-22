---
name: sdd-spec
description: Author the to-be. Edit spec/ in the working tree to describe the DESIRED end state — behavior and why, not implementation. The resulting git diff IS the scope of work. Use after sdd-clarify, before sdd-plan.
---

# sdd-spec

Lifted from Spec Kit's `/specify`. Purpose: describe *what* the system should do, so the
diff against the last committed spec becomes the exact scope.

## Procedure
1. Read the as-is `spec/` + the clarified decisions from `sdd-clarify`.
2. Edit `spec/` (working tree) to the desired end state. For each affected area capture:
   - **Behavior / capabilities** — observable, what it does.
   - **Contracts & interfaces** — the promises kept.
   - **Constraints & invariants** — what must always hold.
   - **Out of scope** — what it deliberately doesn't do.
3. Rules:
   - Behavior, not implementation (principle 8). No file names, no code structure.
   - One canonical shape per concern (principle 14). Don't fork state across docs.
   - Respect the declared split axis (see the spec header) — new capability = a new/edited step.
   - Never park future/maybe functionality here — that's Stori.
   - The spec covers **both apps** (iOS and Android, one text + the dated platform-delta
     table) and, once it exists, the **release toolchain**. `web/` appears only as the gameplay prototype the rules and numbers were
     proven in, never as a second system to keep in sync.
   - **Both platforms.** A behaviour change is a two-codebase change; if one platform will
     land later, add its dated temporary delta row in this same diff.
   - Economy numbers that must hold (rates, caps, prices, drop odds) are **invariants** and
     belong in the spec. "Tuned in the web build" is not a spec entry.
4. Bump `Spec-Version` per SemVer: MAJOR remove/break · MINOR add · PATCH clarify.
5. **Review the diff** (`git diff -- spec/`) — that is the scope handed to `sdd-plan`. Do not
   write code in this step.

## Output
An uncommitted `spec/` diff = the authoritative to-be.
