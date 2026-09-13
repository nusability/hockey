// Magic Wood — placeholder world. Replace buildScenery (and anything else) with the
// real design; see README.md in this folder for the contract.
export default {
  id: 'magicwood',
  sport: 'field',
  name: { en: 'Magic Wood', de: 'Zauberwald' },
  tagline: { en: 'A pitch deep in an enchanted forest.', de: 'Ein Spielfeld tief im verzauberten Wald.' },
  sky: 'linear-gradient(180deg, #0b1020 0%, #1e2a4a 55%, #3b6a4a 100%)',
  light: { hemiSky: 0xbfe3ff, hemiGround: 0x2b3a2b, hemiIntensity: 1.1, sun: 0xfff2d6, sunIntensity: 1.9, sunPos: [18, 60, -20] },
  surface: { base: '#3f8f3f', stripe: '#39843a', lines: '#f8fafc' },
  border: { color: 0x5b3a1e, top: 0x9ad34f, height: 1.1, glass: false, base: 0x1e1b4b },
  ball: { color: 0xffffff },
  goal: { post: 0xef4444, net: 0xffffff },
  buildScenery(group, ctx) {
    return { update() {} };
  },
};
