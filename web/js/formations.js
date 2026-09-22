/**
 * Formations the coach can prescribe. Each lists the five outfield players
 * plus a goalie, in the frame of a team attacking +Z (mirrored for the other
 * side by the match). `x` is the player's lane across the pitch, `z` their
 * depth; both are also the zone they hold when discipline is high.
 *
 * `balanced` is the shape the game has always used, so it is the default.
 */
const G = { role: 'G', x: 0, z: -25 };

export const FORMATIONS = [
  {
    id: 'balanced',
    name: { en: '2-3 Balanced', de: '2-3 Ausgeglichen' },
    blurb: { en: 'Two at the back, three up front. The all-round shape.',
             de: 'Zwei hinten, drei vorne. Die Allrounder-Aufstellung.' },
    players: [G,
      { role: 'D', x: -6.5, z: -17 }, { role: 'D', x: 6.5, z: -17 },
      { role: 'F', x: -9, z: -5 }, { role: 'F', x: 0, z: -3 }, { role: 'F', x: 9, z: -5 }],
  },
  {
    id: 'defensive',
    name: { en: '3-2 Defensive', de: '3-2 Defensiv' },
    blurb: { en: 'Three at the back. Hard to break down, slower to attack.',
             de: 'Drei hinten. Schwer zu knacken, langsamer im Angriff.' },
    players: [G,
      { role: 'D', x: -8.5, z: -17 }, { role: 'D', x: 0, z: -20 }, { role: 'D', x: 8.5, z: -17 },
      { role: 'F', x: -6, z: -3 }, { role: 'F', x: 6, z: -3 }],
  },
  {
    id: 'attacking',
    name: { en: '1-4 Attacking', de: '1-4 Offensiv' },
    blurb: { en: 'One sweeper, four forwards. Constant pressure, open at the back.',
             de: 'Ein Ausputzer, vier Stürmer. Dauerdruck, hinten offen.' },
    players: [G,
      { role: 'D', x: 0, z: -18 },
      { role: 'F', x: -11, z: -6 }, { role: 'F', x: -4, z: 0 }, { role: 'F', x: 4, z: 0 }, { role: 'F', x: 11, z: -6 }],
  },
  {
    id: 'diamond',
    name: { en: '2-1-2 Diamond', de: '2-1-2 Raute' },
    blurb: { en: 'A link player between the lines. Good for combinations.',
             de: 'Ein Verbindungsspieler zwischen den Linien. Gut für Kombinationen.' },
    players: [G,
      { role: 'D', x: -6, z: -17 }, { role: 'D', x: 6, z: -17 },
      { role: 'F', x: 0, z: -9 },
      { role: 'F', x: -8, z: -1 }, { role: 'F', x: 8, z: -1 }],
  },
  {
    id: 'wide',
    name: { en: '2-3 Wide', de: '2-3 Breit' },
    blurb: { en: 'Wingers hug the sidelines. Stretches the pitch for long balls.',
             de: 'Flügel kleben an den Seitenlinien. Zieht das Feld für lange Bälle auseinander.' },
    players: [G,
      { role: 'D', x: -7, z: -17 }, { role: 'D', x: 7, z: -17 },
      { role: 'F', x: -12.5, z: -4 }, { role: 'F', x: 0, z: -7 }, { role: 'F', x: 12.5, z: -4 }],
  },
];

export const DEFAULT_FORMATION = 'balanced';
export const formationById = (id) => FORMATIONS.find((f) => f.id === id) || FORMATIONS[0];
