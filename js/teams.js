import { DEFAULT_TACTICS } from './config.js';

// Fictional teams, each with a home world. `rating` drives AI speed and
// accuracy and the results of simulated matches. Names are localised.
export const TEAMS = [
  { id: 'mossfoxes', name: { en: 'Moss Foxes', de: 'Moosfüchse' }, short: 'MOS', world: 'magicwood', primary: '#2563eb', secondary: '#fb923c', rating: 76,
    tactics: { ...DEFAULT_TACTICS } },
  { id: 'glowowls', name: { en: 'Glow Owls', de: 'Leuchteulen' }, short: 'GLO', world: 'magicwood', primary: '#a855f7', secondary: '#fde68a', rating: 80,
    tactics: { ...DEFAULT_TACTICS, pressing: 0.65, covering: 0.65 } },
  { id: 'nebula', name: { en: 'Nebula Narwhals', de: 'Nebelnarwale' }, short: 'NEB', world: 'space', primary: '#22d3ee', secondary: '#1e1b4b', rating: 82,
    tactics: { ...DEFAULT_TACTICS, passing: 0.8, pushUp: 0.7 } },
  { id: 'rocketlynx', name: { en: 'Rocket Lynx', de: 'Raketenluchse' }, short: 'ROC', world: 'space', primary: '#ef4444', secondary: '#facc15', rating: 85,
    tactics: { ...DEFAULT_TACTICS, shooting: 0.85, pushUp: 0.75, pressing: 0.7 } },
  { id: 'scorpions', name: { en: 'Dune Scorpions', de: 'Dünenskorpione' }, short: 'DUN', world: 'oasis', primary: '#f59e0b', secondary: '#7c2d12', rating: 78,
    tactics: { ...DEFAULT_TACTICS, pressing: 0.8, shooting: 0.7 } },
  { id: 'falcons', name: { en: 'Mirage Falcons', de: 'Wüstenfalken' }, short: 'MIR', world: 'oasis', primary: '#14b8a6', secondary: '#fef3c7', rating: 72,
    tactics: { ...DEFAULT_TACTICS, passing: 0.4, shooting: 0.4, covering: 0.7 } },
  { id: 'wolves', name: { en: 'Glacier Wolves', de: 'Gletscherwölfe' }, short: 'GLW', world: 'himalaya', primary: '#3b82f6', secondary: '#f8fafc', rating: 70,
    tactics: { ...DEFAULT_TACTICS, covering: 0.85, pushUp: 0.3, pressing: 0.3 } },
  { id: 'kraken', name: { en: 'Coral Kraken', de: 'Korallenkraken' }, short: 'COR', world: 'ocean', primary: '#f43f5e', secondary: '#fbcfe8', rating: 75,
    tactics: { ...DEFAULT_TACTICS, passing: 0.7, covering: 0.4 } },
];

export const teamById = (id) => TEAMS.find((t) => t.id === id);
export const USER_TEAM_ID = 'mossfoxes';
