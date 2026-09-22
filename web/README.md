# Slapshot League 🏑

The **web build** of Slapshot League: a stylised, colourful 3D field hockey game
for phones, built with plain JavaScript and [Three.js](https://threejs.org). No
build step: this folder is the website. It is the prototype stage and the parity
reference for the iOS and Android apps (see `../AGENTS.md`, ADR 0002). The interface is in German or English, chosen automatically from
the browser language.

**Play it:** https://nusability.github.io/hockey/ — every push to `main` that
touches `web/` redeploys it (`.github/workflows/pages.yml` publishes this folder
only).

## How it plays

- Your players skate on their own. You only decide **when to let go of the
  puck**.
- When one of your players has the puck it **circles around them**, and a
  line shows where it would go. **Touch and hold anywhere** to keep it; **lift
  your finger** to send it. Releasing near a team-mate snaps into a pass,
  releasing near the goal snaps into a shot (the arrow turns green or pink), so
  timing does not have to be exact. The puck spins towards the most useful
  target first. Drag the finger away from where it landed while holding to
  charge a harder shot.
- Defenders who reach your carrier steal the puck. Keep it moving: pass, get
  open, shoot.
- The camera looks down the rink's long axis from behind your goal and slides
  so the goal the play is heading for stays in view.

## Training

Eight drills that unlock one after another, saved in the browser:

1. **First shot** – you alone, an empty net.
2. **Give and go** – two players, goals only count after a pass.
3. **Beat the goalie** – a slow goalie appears.
4. **Cones** – static dummies block passes and shots.
5. **Moving cones** – the dummies patrol.
6. **Sleepy defenders** – defenders that chase and steal, at half speed.
7. **Under pressure** – three defenders at three-quarter speed.
8. **Scrimmage** – a real game against a full team.

## Worlds

Matches are played in five worlds, each with its own scenery, light and
surface. Four are field hockey on grass; the Himalaya plays ice hockey with a
puck and boards.

- **Magic Wood** (Zauberwald) – an enchanted forest clearing at dusk
- **Deep Space** (Weltraum) – a floating arena among the stars
- **Desert Oasis** (Wüstenoase) – green turf between dunes and palms
- **Himalaya** – an ice rink high among the peaks
- **Ocean World** (Ozeanwelt) – a reef platform beneath the waves

League matches take place in the home team's world; drills each have their own.
A world is a single module in `js/worlds/` (see the README there for the
contract) so new ones can be added without touching the rest of the game.

## Season

Eight fictional teams play a double round-robin **league** (3 points for a win,
1 for a draw) interleaved with a knockout **cup** (quarter-final, semi-final,
final). Matches you don't play are simulated from team ratings. Progress is
saved in the browser.

## Coach's board

Team behaviour is driven by five strategy variables that can be tuned from the
menu (Coach & settings): *pressing*, *covering*, *push up*, *passing* and
*shooting*. Each AI team has its own defaults in `js/teams.js`.

## Project layout

```
index.html          page shell
css/style.css       HUD and menus
js/config.js        rink dimensions, physics constants, default tactics
js/teams.js         the eight fictional teams and their home worlds
js/i18n.js          German/English strings
js/worlds/          the five worlds and the world contract
js/director.js      goal camera and slow motion
js/match.js         match engine: physics, possession, rules, face-offs
js/ai.js            automatic player behaviour driven by the tactics variables
js/input.js         one-touch hold/release control
js/levels.js        training drills and progress
js/render.js        Three.js scene: rink, stands, players, effects, camera
js/season.js        league table, cup bracket, simulation, save/load
js/ui.js            menus, season hub, HUD
js/audio.js         synthesised sound effects
js/main.js          game loop and screen flow
vendor/             Three.js (MIT)
.github/workflows   GitHub Pages deployment
```

Run locally with any static server from this folder, e.g.
`cd web && python3 -m http.server` and open `http://localhost:8000`.
