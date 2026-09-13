// Himalaya — placeholder world. Replace buildScenery (and anything else) with the
// real design; see README.md in this folder for the contract.
export default {
  id: 'himalaya',
  sport: 'ice',
  name: { en: 'Himalaya', de: 'Himalaya' },
  tagline: { en: 'An ice rink high among the peaks.', de: 'Eine Eisfläche hoch zwischen den Gipfeln.' },
  sky: 'linear-gradient(180deg, #7dd3fc 0%, #bae6fd 50%, #e0f2fe 100%)',
  light: { hemiSky: 0xe0f2fe, hemiGround: 0x475569, hemiIntensity: 1.1, sun: 0xfff2d6, sunIntensity: 1.9, sunPos: [18, 60, -20] },
  surface: { base: '#eef8ff', stripe: '#e2f0fb', lines: '#1d4ed8' },
  border: { color: 0xf8fafc, top: 0x0ea5e9, height: 1.1, glass: true, base: 0x1e1b4b },
  ball: { color: 0x0f172a },
  goal: { post: 0xef4444, net: 0xffffff },
  buildScenery(group, ctx) {
    return { update() {} };
  },
};
