# `shared/`

What the two stand-alone implementations may share (`decisions/0001-*.md`): config, some assets,
and the simulation's golden vectors. None of it is code either platform links.

- **`data/`** — platform-neutral declarations, **generated** into each platform's own form:
  teams, drills, formations, tactics defaults, physics and AI constants, design tokens, and the
  copy (German + English). A hand-edited
  constant on either side is the bug this directory exists to make impossible. Generated files
  are committed, so a clone builds without the generator.
- **`assets/`** — models, textures and sounds both apps load, where one file serves both.
- **`vectors/`** — golden vectors of the simulation: *(seed, scenario, input tape, sampled
  expected state)*, recorded by the first platform to land a rule and replayed by both suites. A mismatch is
  a red build on whichever platform moved. Re-recording a vector requires a spec change in the
  same commit — a red vector fixed by regenerating the file is drift laundered through the gate
  built to stop it.

All are empty today. The first entries arrive with the port's first tasks (Stori `SMASH`).
