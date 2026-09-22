# `shared/`

The two anti-drift mechanisms from `decisions/0001-*.md`. Neither contains executable code that
either platform links; both are read by generators and by tests.

- **`data/`** — platform-neutral declarations, **generated** into each platform's own form:
  teams, drills, formations, tactics defaults, physics and AI constants, world declarations,
  design tokens, and the copy (starting from `web/js/i18n.js`, German + English). A hand-edited
  constant on either side is the bug this directory exists to make impossible. Generated files
  are committed, so a clone builds without the generator.
- **`vectors/`** — golden vectors: *(seed, scenario, input tape, sampled expected state)*,
  **recorded from `web/`** (ADR 0002) and replayed by both platforms' test suites. A mismatch is
  a red build on whichever platform moved. Re-recording a vector requires a spec change in the
  same commit — a red vector fixed by regenerating the file is drift laundered through the gate
  built to stop it.

Both are empty today. The first entries arrive with the port's first tasks (Stori `SLAP`):
seeding the web simulation, then the first recorded match.
