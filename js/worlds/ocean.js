// Ocean World — placeholder world. Replace buildScenery (and anything else) with the
// real design; see README.md in this folder for the contract.
export default {
  id: 'ocean',
  sport: 'field',
  name: { en: 'Ocean World', de: 'Ozeanwelt' },
  tagline: { en: 'A pitch on a reef beneath the waves.', de: 'Ein Spielfeld auf einem Riff unter den Wellen.' },
  sky: 'linear-gradient(180deg, #0c4a6e 0%, #0e7490 55%, #14b8a6 100%)',
  light: { hemiSky: 0x99f6e4, hemiGround: 0x134e4a, hemiIntensity: 1.1, sun: 0xfff2d6, sunIntensity: 1.9, sunPos: [18, 60, -20] },
  surface: { base: '#2f9e8f', stripe: '#2a9384', lines: '#f0fdfa' },
  border: { color: 0xf472b6, top: 0xfde68a, height: 1.1, glass: false, base: 0x1e1b4b },
  ball: { color: 0xfff7ed },
  goal: { post: 0xef4444, net: 0xffffff },
  buildScenery(group, ctx) {
    return { update() {} };
  },
};
