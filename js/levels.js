import { TRAINING_KEY } from './config.js';

// Training drills. Positions are for the user's team attacking +Z (the far
// goal). `away` entries with role 'O' are dummies: static or patrolling disks
// that block the puck but never take it. `behavior: 'active'` with a low
// `speed` gives slow, forgiving defenders.
const G = (opts = {}) => ({ role: 'G', x: 0, z: 24.6, behavior: 'active', ...opts });

export const LEVELS = [
  {
    id: 'shot', world: 'magicwood', goals: 3, time: 60,
    name: { en: 'First shot', de: 'Erster Schuss' },
    hint: { en: 'Touch and hold anywhere: the ball circles your player. Lift your finger when the arrow points at the goal.',
            de: 'Irgendwo tippen und halten: Der Ball kreist um deinen Spieler. Hebe den Finger, wenn der Pfeil aufs Tor zeigt.' },
    home: [{ role: 'F', x: 0, z: -2 }],
    away: [],
  },
  {
    id: 'pass', world: 'oasis', goals: 3, time: 90, requireAssist: true,
    name: { en: 'Give and go', de: 'Doppelpass' },
    hint: { en: 'Lift when the arrow points at your team-mate to pass. Goals only count after a pass.',
            de: 'Hebe den Finger, wenn der Pfeil auf deinen Mitspieler zeigt, um zu passen. Tore zählen nur nach einem Pass.' },
    home: [{ role: 'F', x: -7, z: -6 }, { role: 'F', x: 7, z: 4 }],
    away: [],
  },
  {
    id: 'goalie', world: 'ocean', goals: 3, time: 90,
    name: { en: 'Beat the goalie', de: 'Torwart überwinden' },
    hint: { en: 'The goalie follows the ball. Shoot early, or pass across to pull the goalie out of position.',
            de: 'Der Torwart folgt dem Ball. Schieße früh oder spiele quer, um den Torwart aus der Position zu locken.' },
    home: [{ role: 'F', x: -6, z: -4 }, { role: 'F', x: 6, z: 6 }],
    away: [G({ speed: 0.6 })],
  },
  {
    id: 'cones', world: 'space', goals: 3, time: 90,
    name: { en: 'Cones', de: 'Hütchen' },
    hint: { en: 'Dummies block passes and shots. Move the ball around them.',
            de: 'Dummys blocken Pässe und Schüsse. Spiele den Ball um sie herum.' },
    home: [{ role: 'F', x: -8, z: -8 }, { role: 'F', x: 8, z: -2 }, { role: 'F', x: -6, z: 10 }],
    away: [G({ speed: 0.65 }), { role: 'O', x: 0, z: 6 }, { role: 'O', x: -5, z: 14 }, { role: 'O', x: 5, z: 14 }, { role: 'O', x: 0, z: 19 }],
  },
  {
    id: 'moving', world: 'himalaya', goals: 3, time: 90,
    name: { en: 'Moving cones', de: 'Wandernde Hütchen' },
    hint: { en: 'The dummies slide back and forth. Time your passes through the gaps.',
            de: 'Die Dummys gleiten hin und her. Passe im richtigen Moment durch die Lücken.' },
    home: [{ role: 'F', x: -8, z: -8 }, { role: 'F', x: 8, z: -2 }, { role: 'F', x: 0, z: 10 }],
    away: [G({ speed: 0.7 }), { role: 'O', x: -8, z: 8, patrol: { x: 8, z: 8, speed: 1.1 } }, { role: 'O', x: 8, z: 15, patrol: { x: -8, z: 15, speed: 0.9, phase: 1.5 } }, { role: 'O', x: -4, z: 20, patrol: { x: 4, z: 20, speed: 1.6 } }],
  },
  {
    id: 'sleepy', world: 'magicwood', goals: 3, time: 100,
    name: { en: 'Sleepy defenders', de: 'Schläfrige Verteidiger' },
    hint: { en: 'These defenders chase the ball, slowly. If one reaches your carrier they steal it, so keep passing.',
            de: 'Diese Verteidiger jagen den Ball, aber langsam. Erreicht einer deinen Ballführer, klaut er ihn – also weiterpassen.' },
    home: [{ role: 'F', x: -8, z: -6 }, { role: 'F', x: 8, z: -2 }, { role: 'F', x: 0, z: 8 }],
    away: [G({ speed: 0.75 }), { role: 'D', x: -5, z: 12, speed: 0.45 }, { role: 'D', x: 5, z: 12, speed: 0.45 }],
  },
  {
    id: 'press', world: 'oasis', goals: 3, time: 110,
    name: { en: 'Under pressure', de: 'Unter Druck' },
    hint: { en: 'Three real defenders at three-quarter speed. Quick passes beat pressure.',
            de: 'Drei echte Verteidiger mit Dreivierteltempo. Schnelle Pässe schlagen jedes Pressing.' },
    home: [{ role: 'F', x: -8, z: -6 }, { role: 'F', x: 8, z: -2 }, { role: 'F', x: 0, z: 8 }, { role: 'D', x: 0, z: -14 }],
    away: [G(), { role: 'D', x: -6, z: 14, speed: 0.75 }, { role: 'D', x: 6, z: 14, speed: 0.75 }, { role: 'F', x: 0, z: 4, speed: 0.75 }],
  },
  {
    id: 'scrimmage', world: 'space', goals: 3, time: 150,
    name: { en: 'Scrimmage', de: 'Trainingsspiel' },
    hint: { en: 'A real game: they attack too. Score three before the clock runs out and you are ready for the league.',
            de: 'Ein echtes Spiel: Die anderen greifen auch an. Erziele drei Tore, bevor die Zeit abläuft, und du bist bereit für die Liga.' },
    home: [{ role: 'F', x: -9, z: -5 }, { role: 'F', x: 0, z: -3 }, { role: 'F', x: 9, z: -5 }, { role: 'D', x: -6.5, z: -17 }, { role: 'D', x: 6.5, z: -17 }, { role: 'G', x: 0, z: -24.6 }],
    away: [G({ speed: 0.7 }), { role: 'D', x: -6.5, z: 17, speed: 0.85 }, { role: 'D', x: 6.5, z: 17, speed: 0.85 }, { role: 'F', x: -9, z: 5, speed: 0.85 }, { role: 'F', x: 0, z: 3, speed: 0.85 }, { role: 'F', x: 9, z: 5, speed: 0.85 }],
    puckTo: 1, freePlay: true,
  },
];

export function loadTraining() {
  try {
    const s = JSON.parse(localStorage.getItem(TRAINING_KEY) || 'null');
    if (s && Array.isArray(s.done)) return s;
  } catch (e) { /* ignore */ }
  return { done: [] };
}

export function saveTraining(state) {
  try { localStorage.setItem(TRAINING_KEY, JSON.stringify(state)); } catch (e) { /* ignore */ }
}

export function isUnlocked(state, index) {
  return index === 0 || state.done.includes(LEVELS[index - 1].id);
}
