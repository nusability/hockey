---
name: sdd-verify
description: Verify code conforms to the spec for a change, and cross-check spec ↔ code ↔ tests before committing. Reports conformance gaps with file:line. Use after building, before the spec+code commit. Best run in fresh context.
---

# sdd-verify

Lifted from Spec Kit's `/analyze` (cross-artifact consistency) + the implement verification
step. Purpose: prove the change satisfies its spec diff — conformance, not vibes.

## Procedure
1. Take the `spec/` diff (the to-be) as the contract.
2. **Coverage** — every behavior/contract in the diff is implemented and reachable **on both
   platforms**, or has a dated delta row. Name the
   spec line ↔ the code that satisfies it. Missing → gap.
3. **Reality** — verify against the real thing, not assumptions. Run it: iOS on a device
   or simulator **and** Android on a device or emulator; `web/` in a browser with the console
   open. A rendering change is measured on the low-end Android device. A gameplay change is
   verified by playing it; confirm visibility, not view-tree presence.
4. **Economy** — for any change touching currency, rewards, or pricing: state the resulting
   earn rate, sink, and time-to-unlock, and check them against the spec's invariants.
   If a competitive surface is in reach, check principle 1 explicitly: ranked players must be
   compared against others with the same purchased advantages, never pooled across them.
5. **Vectors** — the simulation suites on both platforms replay `shared/vectors/` green. A
   vector re-recorded in this change has a spec diff that explains why.
6. **Tests** — each new contract has a test: contract → failing → green; reverting the fix
   fails the test. Every test sits on the path to production. Full suite green after any dep change.
7. **Consistency** — spec ↔ code ↔ tests agree. If reality forced a change, fix the spec
   (PATCH) so it stays honest — don't leave it lying.
8. **Gates & secrets** — paywalls and IAP flows exercised by clicking through; no fabricated
   entitlements; no hardcoded infra config; no echoed secrets.

## Output
`pass` / `fail` with a list of gaps as `file:line → spec line it violates`. On `pass`, the
change is ready for the spec+code commit + `spec-vX.Y.Z` tag.

## Note
Prefer a fresh context (or a subagent) so verification isn't biased by the build session.
