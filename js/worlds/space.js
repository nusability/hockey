// Deep Space — placeholder world. Replace buildScenery (and anything else) with the
// real design; see README.md in this folder for the contract.
export default {
  id: 'space',
  sport: 'field',
  name: { en: 'Deep Space', de: 'Weltraum' },
  tagline: { en: 'A floating arena among the stars.', de: 'Eine schwebende Arena zwischen den Sternen.' },
  sky: 'linear-gradient(180deg, #02030a 0%, #0b1030 60%, #1c1150 100%)',
  light: { hemiSky: 0x9fd4ff, hemiGround: 0x10102a, hemiIntensity: 1.1, sun: 0xfff2d6, sunIntensity: 1.9, sunPos: [18, 60, -20] },
  surface: { base: '#1c2541', stripe: '#182038', lines: '#7df9ff' },
  border: { color: 0x0ea5e9, top: 0xf0abfc, height: 1.1, glass: false, base: 0x1e1b4b },
  ball: { color: 0xfef08a },
  goal: { post: 0xef4444, net: 0xffffff },
  buildScenery(group, ctx) {
    return { update() {} };
  },
};
