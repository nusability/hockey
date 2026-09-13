// Desert Oasis — placeholder world. Replace buildScenery (and anything else) with the
// real design; see README.md in this folder for the contract.
export default {
  id: 'oasis',
  sport: 'field',
  name: { en: 'Desert Oasis', de: 'Wüstenoase' },
  tagline: { en: 'Green turf between dunes and palms.', de: 'Grüner Rasen zwischen Dünen und Palmen.' },
  sky: 'linear-gradient(180deg, #f7b267 0%, #f4845f 45%, #7a3e8f 100%)',
  light: { hemiSky: 0xffe9c7, hemiGround: 0x8a5a2b, hemiIntensity: 1.1, sun: 0xfff2d6, sunIntensity: 1.9, sunPos: [18, 60, -20] },
  surface: { base: '#4c9a3f', stripe: '#458f39', lines: '#fff7e6' },
  border: { color: 0xd9a066, top: 0xf59e0b, height: 1.1, glass: false, base: 0x1e1b4b },
  ball: { color: 0xffffff },
  goal: { post: 0xef4444, net: 0xffffff },
  buildScenery(group, ctx) {
    return { update() {} };
  },
};
