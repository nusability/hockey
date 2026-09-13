import { DEFAULT_TACTICS } from './config.js';

// Fictional teams. `rating` drives AI speed and accuracy and the results of
// simulated matches. Tactics are the strategy variables a coach can tune.
export const TEAMS = [
  { id: 'wolves',   name: 'Glacier Wolves',  short: 'GLW', primary: '#3b82f6', secondary: '#f8fafc', rating: 76,
    tactics: { ...DEFAULT_TACTICS } },
  { id: 'narwhals', name: 'Neon Narwhals',   short: 'NEO', primary: '#a855f7', secondary: '#22d3ee', rating: 82,
    tactics: { ...DEFAULT_TACTICS, passing: 0.8, pushUp: 0.7 } },
  { id: 'foxes',    name: 'Ember Foxes',     short: 'EMB', primary: '#f97316', secondary: '#1e293b', rating: 78,
    tactics: { ...DEFAULT_TACTICS, pressing: 0.8, shooting: 0.7 } },
  { id: 'titans',   name: 'Tundra Titans',   short: 'TUN', primary: '#94a3b8', secondary: '#fde047', rating: 70,
    tactics: { ...DEFAULT_TACTICS, covering: 0.85, pushUp: 0.3, pressing: 0.3 } },
  { id: 'kraken',   name: 'Coral Kraken',    short: 'COR', primary: '#f43f5e', secondary: '#fbcfe8', rating: 75,
    tactics: { ...DEFAULT_TACTICS, passing: 0.7, covering: 0.4 } },
  { id: 'owls',     name: 'Storm Owls',      short: 'STO', primary: '#0ea5e9', secondary: '#0f172a', rating: 80,
    tactics: { ...DEFAULT_TACTICS, pressing: 0.65, covering: 0.65 } },
  { id: 'lynx',     name: 'Lava Lynx',       short: 'LAV', primary: '#ef4444', secondary: '#facc15', rating: 85,
    tactics: { ...DEFAULT_TACTICS, shooting: 0.85, pushUp: 0.75, pressing: 0.7 } },
  { id: 'falcons',  name: 'Frost Falcons',   short: 'FRO', primary: '#14b8a6', secondary: '#ecfeff', rating: 72,
    tactics: { ...DEFAULT_TACTICS, passing: 0.4, shooting: 0.4, covering: 0.7 } },
];

export const teamById = (id) => TEAMS.find((t) => t.id === id);
export const USER_TEAM_ID = 'wolves';
