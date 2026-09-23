# Principles (Constitution)

Durable values. Change rarely, only by deliberate amendment (see bottom). Everything —
the as-is spec, the code, the backlog, `AGENTS.md`, `conventions.md` — complies with these.
On conflict, this document wins.

## Product north-stars (Smash Hockey 3D)
The reason the port exists. Every feature and trade-off serves these; when a call is
ambiguous, pick the option that advances them.
- **A0. One touch, total control.** The player makes one decision — *when to let go* — and
  that decision is honoured exactly. Hold keeps the ball, lift sends it, and the aim line never
  lies about where it goes. A lost ball or a missed shot is always legible: the player can see
  what they did and what the defender did. Everything else in the product is decoration on
  this; a change that muddies the release loses, whatever it earns.
- **A1. A toy box of worlds.** Stylised, colourful, alive — the enchanted wood, the station
  among the stars, the oasis, the Himalaya ice, the reef. The game should be a pleasure to
  watch before it is a pleasure to win; the goal camera and the slow motion are the payoff.
- **A2. A match is always worth starting and never worth quitting.** From the menu to the
  face-off is one tap. No interstitial between the player and the next match or the next drill
  attempt, ever — nothing loads, fetches, sells or asks in that gap. A retry of a drill is one tap.
  **The one thing the game may ask for itself** is whether the player is enjoying it (spec §17), and
  this principle binds that question rather than excusing it: it is *armed* at the moment it is
  earned and *put* only on a screen the player has already come to rest on — never on the way from a
  result to the next face-off, never over a retry, and never more than one tap to be rid of. A
  question that costs a player a match they wanted to start has already lost, whatever it earns us.
- **A3. A season to come back to.** The league, the cup, the drills, and whatever renewable
  content follows — the game must have a reason to open it tomorrow.

## Monetization ethics
Non-negotiable. The port is free-to-play with IAP; these bound what that may mean.
1. **Compare like with like.** If a competitive surface ever exists (a ranking, a shared
   challenge, a head-to-head), a player is ranked against others with the same purchased
   advantages. What we refuse is the undifferentiated board that ranks spending and calls it
   skill.
2. **Never sell the fix to a problem we manufactured.** No artificial friction introduced so
   it can be removed for money. Difficulty serves the match, not the shop; the AI does not get
   harder to sell an upgrade.
3. **No dark patterns.** No countdown pressure on a purchase, no confusable currencies at the
   point of sale, no accidental-tap buys, no ads dressed as gameplay. Price and contents are
   legible before the tap.
4. **The free game is a whole game.** A player who never spends gets the full match loop, the
   training drills, a whole season, and a real earn path. Paying buys pace and cosmetics, not
   entry.
5. **Never spend a player's hard currency implicitly.** Premium currency leaves the balance
   only on a deliberate, confirmed act.

## Spec & source of truth
6. **One as-is spec.** `spec/` describes the system *as it exists now*; read it to know current
   state — never reconstruct from work items or PRs.
7. **Spec and code never diverge.** A behavior change updates the spec in the same commit.
8. **Spec is behavior, not implementation.** Specify what and why; how lives in code, and
   survives refactors.
9. **Change is specified before it is built.** Author the to-be by editing the spec; the diff
   against the last version *is* the work.
10. **Ideas are cheap and tracked; specs are earned.** Raw ideas live in the backlog, not the
    spec. The spec is never a wishlist.
11. **The spec is versioned.** SemVer + git tag on every behavioral change; any past state is
    recoverable.

## Decisions & architecture
12. **No prototype mindset — in the product.** Both apps are built prod-grade; no vaporware, UI
    ships only when wired to real functionality. **`web/` is the sanctioned exception**: it is
    the prototype stage, and a mechanic proves itself there before it earns a spec entry. The
    exemption is a location, not an attitude — it never leaks into the apps.
13. **No backwards compatibility for our own shapes — but never break player data.** When the
    spec changes, drop the old shape; no compat shims. Exception: **player progress, balances,
    and purchases are sacred** — never reset, never devalue, never strand an entitlement.
14. **No duplication.** One canonical shape, pattern, and write-path per concern. In
    particular: one earn path, one spend path, one place that decides what a match is worth.
    Across the two apps, share the *description* (spec, generated data, vectors), never
    hand-copy a value.
15. **Own engineering calls, flag one-way doors.** Pick the elegant default and state it; name
    foundational, hard-to-reverse choices and escalate product forks.
16. **Elegant and bold.** Don't fear sweeping changes; a sharp line beats a safe one.
17. **Take the SOTA dependency.** Adopt best-in-class libraries over hand-rolling; record each
    adoption as an ADR.
18. **Riskiest first.** De-risk the foundation before polishing what depends on it.
19. **Scope down before over-engineering.** Sketch the smaller version and ask; prefer small,
    reversible steps.
20. **Don't fret the cost.** Don't shy away from solutions that are costly in time to invest.
    It typically takes much less time than expected. **Be bold and elegant.**

---

### Amending this document
Requires a commit whose message begins `constitution:` and a one-line rationale.
Principles are versioned with the repo, not with the spec.
