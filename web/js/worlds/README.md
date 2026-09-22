# Worlds

A world is one ES module in this folder that `export default`s a plain object.
The renderer calls it when a match starts. Nothing else in the game needs to
know about a world: it changes the sky, the lighting, the pitch surface, the
boundary wall, the ball, the goals and the scenery around the pitch.

Coordinates: the pitch is centred on the origin, X across (−15…15), Z along
(−30…30), Y up. The user's goal is at Z = −26, the opponent's at Z = +26. The
boundary wall runs at |X| = 15, |Z| = 30 (rounded corners of radius
`ctx.corner`). The camera sits above and behind the user's goal looking
towards +Z, about 36 units high, and for goals it drops to about 4 units high
beside a goal line, so scenery must look good from above and from ground level.
Keep the area inside the wall completely clear.

## Contract

```js
export default {
  id: 'magicwood',
  sport: 'field',                       // 'field' (grass, ball) or 'ice' (ice, puck, rounded boards)
  name: { en: 'Magic Wood', de: 'Zauberwald' },
  tagline: { en: '…', de: '…' },        // one short line for the drill intro

  sky: 'linear-gradient(180deg, #0b1020 0%, #2a1b4d 60%, #6d3b7a 100%)',   // CSS background of the page
  light: {
    hemiSky: 0xbfe3ff, hemiGround: 0x2b3a2b, hemiIntensity: 1.0,
    sun: 0xfff2d6, sunIntensity: 1.8, sunPos: [18, 60, -20],
    fog: { color: 0x1a1030, near: 60, far: 160 },                           // optional
  },
  surface: {
    base: '#3f8f3f',                     // pitch colour
    stripe: '#3a833a',                   // optional mowing-stripe colour (field) / ice tint
    lines: '#ffffff',                    // marking colour
    decorate(ctx, W, H, h) {},           // optional: draw onto the pitch canvas BEFORE the lines.
                                         //   h = { X(x)->px, Z(z)->px, sx, sz, rand } world->canvas helpers
  },
  border: {
    color: 0x7a5230, top: 0x9ad34f,      // wall body colour and top rail colour
    height: 1.1, glass: false,           // glass = translucent panel above the wall (ice rinks)
    base: 0x1e1b4b,                      // slab colour under the pitch
  },
  ball: { color: 0xffffff, emissive: 0x000000 },   // puck colour for ice worlds
  goal: { post: 0xffffff, net: 0xffffff },

  // Build everything around the pitch into `group` (already in the scene).
  // ctx = { THREE, RINK, HW, HL, corner, rand(a,b), pick(arr), lerp, noise(s) }
  // Return { update(dt, time) } for animation (optional). Keep it cheap:
  // InstancedMesh / merged geometry for anything repeated, ≤ ~40k triangles,
  // ≤ ~25 draw calls, no external assets (canvas textures are fine), and
  // castShadow only on a handful of large objects.
  buildScenery(group, ctx) { return { update(dt, time) {} }; },
};
```

Register the world in `index.js` (the five ids are already listed).
Screenshot a world with `node scratchpad/worldshot.mjs <id>` (see the
scratchpad harness) — it prints the triangle count and draw calls and writes
`world_<id>_play.png` (play camera) and `world_<id>_low.png` (goal camera).
