import { TRAINING_KEY } from './config.js';

// Training drills. Positions are for the user's team attacking +Z (the far
// goal). `away` entries with role 'O' are dummies: static or patrolling disks
// that block the puck but never take it. `behavior: 'active'` with a low
// `speed` gives slow, forgiving defenders.
const G = (opts = {}) => ({ role: 'G', x: 0, z: 24.6, behavior: 'active', ...opts });

export const LEVELS = [
  {
    id: 'shot', name: 'First shot', goals: 3, time: 60,
    hint: 'Touch and hold anywhere: the puck circles your player. Lift your finger when the line points at the goal.',
    home: [{ role: 'F', x: 0, z: -2 }],
    away: [],
  },
  {
    id: 'pass', name: 'Give and go', goals: 3, time: 90, requireAssist: true,
    hint: 'Lift when the line points at your team-mate to pass. Goals only count after a pass.',
    home: [{ role: 'F', x: -7, z: -6 }, { role: 'F', x: 7, z: 4 }],
    away: [],
  },
  {
    id: 'goalie', name: 'Beat the goalie', goals: 3, time: 90,
    hint: 'The goalie follows the puck. Shoot early, or pass across to pull the goalie out of position.',
    home: [{ role: 'F', x: -6, z: -4 }, { role: 'F', x: 6, z: 6 }],
    away: [G({ speed: 0.6 })],
  },
  {
    id: 'cones', name: 'Cones', goals: 3, time: 90,
    hint: 'Dummies block passes and shots. Move the puck around them.',
    home: [{ role: 'F', x: -8, z: -8 }, { role: 'F', x: 8, z: -2 }, { role: 'F', x: -6, z: 10 }],
    away: [G({ speed: 0.65 }), { role: 'O', x: 0, z: 6 }, { role: 'O', x: -5, z: 14 }, { role: 'O', x: 5, z: 14 }, { role: 'O', x: 0, z: 19 }],
  },
  {
    id: 'moving', name: 'Moving cones', goals: 3, time: 90,
    hint: 'The dummies slide back and forth. Time your passes through the gaps.',
    home: [{ role: 'F', x: -8, z: -8 }, { role: 'F', x: 8, z: -2 }, { role: 'F', x: 0, z: 10 }],
    away: [G({ speed: 0.7 }), { role: 'O', x: -8, z: 8, patrol: { x: 8, z: 8, speed: 1.1 } }, { role: 'O', x: 8, z: 15, patrol: { x: -8, z: 15, speed: 0.9, phase: 1.5 } }, { role: 'O', x: -4, z: 20, patrol: { x: 4, z: 20, speed: 1.6 } }],
  },
  {
    id: 'sleepy', name: 'Sleepy defenders', goals: 3, time: 100,
    hint: 'These defenders chase the puck, slowly. If one reaches your carrier they steal it, so keep passing.',
    home: [{ role: 'F', x: -8, z: -6 }, { role: 'F', x: 8, z: -2 }, { role: 'F', x: 0, z: 8 }],
    away: [G({ speed: 0.75 }), { role: 'D', x: -5, z: 12, speed: 0.45 }, { role: 'D', x: 5, z: 12, speed: 0.45 }],
  },
  {
    id: 'press', name: 'Under pressure', goals: 3, time: 110,
    hint: 'Three real defenders at three-quarter speed. Quick passes beat pressure.',
    home: [{ role: 'F', x: -8, z: -6 }, { role: 'F', x: 8, z: -2 }, { role: 'F', x: 0, z: 8 }, { role: 'D', x: 0, z: -14 }],
    away: [G(), { role: 'D', x: -6, z: 14, speed: 0.75 }, { role: 'D', x: 6, z: 14, speed: 0.75 }, { role: 'F', x: 0, z: 4, speed: 0.75 }],
  },
  {
    id: 'scrimmage', name: 'Scrimmage', goals: 3, time: 150,
    hint: 'A real game: they attack too. Score three before the clock runs out and you are ready for the league.',
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
