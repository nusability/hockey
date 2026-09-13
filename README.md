# Slapshot League 🏒

A stylised, colourful 3D hockey game for phones, built with plain JavaScript and
[Three.js](https://threejs.org). No build step: the repository is the website.

**Play it:** once GitHub Pages is enabled for this repository (Settings → Pages →
Source: *GitHub Actions*), the game is served from
`https://<owner>.github.io/<repo>/`.

## How it plays

- The camera looks down the rink's long axis from behind your goal. It slides
  along the rink so that the goal the play is heading for stays in view.
- **Drag** with one finger to grab the nearest skater and steer them. A **second
  finger** steers a second player at the same time. All other players (and the
  goalie) follow the team's tactics automatically.
- **Tap** a team-mate while your team has the puck to **pass**; passes lead the
  receiver into space. **Tap the goal** or **flick** the carrier's finger to
  **shoot**. Chain passes to pull the goalie out, then slam it in.
- Loose pucks are collected by skating into them; defenders steal the puck when
  they reach it, so keep it moving.
- Rules: three periods, face-offs, offside at the blue lines, icing. Cup ties
  go to sudden-death overtime.

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
js/teams.js         the eight fictional teams
js/match.js         match engine: physics, possession, rules, face-offs
js/ai.js            automatic player behaviour driven by the tactics variables
js/input.js         one/two-finger controls, tap-to-pass, flick-to-shoot
js/render.js        Three.js scene: rink, stands, players, effects, camera
js/season.js        league table, cup bracket, simulation, save/load
js/ui.js            menus, season hub, HUD
js/audio.js         synthesised sound effects
js/main.js          game loop and screen flow
vendor/             Three.js (MIT)
.github/workflows   GitHub Pages deployment
```

Run locally with any static server, e.g. `python3 -m http.server` and open
`http://localhost:8000`.
