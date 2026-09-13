import magicwood from './magicwood.js';
import space from './space.js';
import oasis from './oasis.js';
import himalaya from './himalaya.js';
import ocean from './ocean.js';

export const WORLDS = { magicwood, space, oasis, himalaya, ocean };
export const WORLD_IDS = Object.keys(WORLDS);
export const worldById = (id) => WORLDS[id] || WORLDS.magicwood;
