import { Match } from './match.js';
import { Renderer } from './render.js';
import { Input } from './input.js';
import { UI } from './ui.js';
import { Sfx } from './audio.js';
import { Director } from './director.js';
import { TEAMS, teamById, USER_TEAM_ID } from './teams.js';
import { DEFAULT_TACTICS, SETTINGS_KEY, RULES, ORBIT } from './config.js';
import { newSeason, loadSeason, saveSeason, advanceToUserFixture, recordUserResult, randomOpponent } from './season.js';
import { LEVELS, loadTraining, saveTraining, isUnlocked } from './levels.js';
import { t, tl, LANG } from './i18n.js';
import { worldById, WORLD_IDS } from './worlds/index.js';

const canvas = document.getElementById('game');
const powerEl = document.getElementById('power');
const powerFill = powerEl.querySelector('i');
const ui = new UI();
const renderer = new Renderer(canvas);
let match = null;
let matchCtx = null;      // { type:'quick'|'season'|'training', ... }
let season = loadSeason();
let training = loadTraining();
let paused = false;
let running = false;
const input = new Input(canvas, () => (running && !paused ? match : null));
const sfx = new Sfx();
const director = new Director();
window.addEventListener('pointerdown', () => sfx.unlock(), { passive: true });

// The training opponents: a neutral gray side used for drills.
const DRILL_TEAM = { id: 'drill', name: { en: 'Training', de: 'Training' }, short: 'TRN', world: 'magicwood', primary: '#94a3b8', secondary: '#f97316', rating: 74, tactics: { ...DEFAULT_TACTICS, pressing: 0.7 } };
document.documentElement.lang = LANG;

// ------------------------------------------------------------------ settings
function loadSettings() {
  const base = { tactics: { ...DEFAULT_TACTICS }, periodSeconds: RULES.periodSeconds, orbitPeriod: ORBIT.period };
  try {
    const s = JSON.parse(localStorage.getItem(SETTINGS_KEY) || 'null');
    if (s) return { ...base, ...s, tactics: { ...DEFAULT_TACTICS, ...(s.tactics || {}) } };
  } catch (e) { /* ignore */ }
  return base;
}
function saveSettings() { try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings)); } catch (e) { /* ignore */ } }
let settings = loadSettings();
const userTeam = () => ({ ...teamById(USER_TEAM_ID), tactics: settings.tactics });

// ------------------------------------------------------------------ match flow
function startMatch(home, away, ctx) {
  matchCtx = ctx;
  const world = worldById(ctx.world || home.world);
  match = new Match({
    home, away,
    tactics: [home.tactics, away.tactics],
    periodSeconds: settings.periodSeconds,
    orbitPeriod: settings.orbitPeriod,
    overtime: ctx.type === 'season' && ctx.fx.type === 'cup',
    scenario: ctx.scenario || null,
    sport: world.sport,
    onEvent: onMatchEvent,
  });
  renderer.setWorld(world);
  renderer.buildPlayers(match);
  renderer.focusZ = 0;
  ui.hide();
  ui.showHud(match);
  if (!ctx.scenario) ui.showBanner('hud.vs', 'info', 2200, { a: tl(home.name), b: tl(away.name) });
  paused = false;
  running = true;
}

function onMatchEvent(e) {
  switch (e.type) {
    case 'goal': {
      const t = match.teams[e.team];
      director.onGoal(match, e);
      renderer.celebrate(e.team, [t.primary, t.secondary, '#ffffff'], match.attackGoalZ(e.team));
      ui.showBanner(e.team === 0 ? 'GOAL!' : 'GOAL AGAINST', e.team === 0 ? 'goal' : 'bad', 2400);
      sfx.horn();
      break;
    }
    case 'whistle': ui.showBanner(e.text, 'warn', 1800); sfx.whistle(); break;
    case 'lost': ui.showBanner(e.text, 'bad', 1200); sfx.whistle(); break;
    case 'drill': ui.showBanner(e.text, 'info', 900); break;
    case 'faceoff': if (e.text && e.text !== 'FACE-OFF') ui.showBanner(e.text, 'info', 1500, e.params); break;
    case 'drop': case 'go': sfx.drop(); break;
    case 'periodEnd': ui.showBanner(match.message, 'info', 2400, match.messageParams); sfx.whistle(); break;
    case 'post': renderer.shake = Math.max(renderer.shake, 0.5); sfx.post(); break;
    case 'board': sfx.board(); break;
    case 'block': sfx.board(); break;
    case 'shot': sfx.shot(); break;
    case 'pass': sfx.pass(); break;
    case 'steal': if (e.by.team === 0) sfx.steal(); break;
    case 'end': ui.showBanner(match.message, e.won === false ? 'bad' : 'goal', 1500, match.messageParams); sfx.whistle(); setTimeout(() => finishMatch(), 1300); break;
  }
}

function finishMatch() {
  running = false;
  input.clear();
  ui.hideHud();
  if (matchCtx.type === 'season' && season) {
    const fx = matchCtx.fx;
    const score = fx.userIsHome ? [match.score[0], match.score[1]] : [match.score[1], match.score[0]];
    recordUserResult(season, fx, score, match.isOvertime);
    saveSeason(season);
  }
  if (matchCtx.type === 'training') {
    const lv = LEVELS[matchCtx.level];
    if (match.won && !training.done.includes(lv.id)) { training.done.push(lv.id); saveTraining(training); }
    ui.levelResult(match, lv, matchCtx.level, matchCtx.level + 1 < LEVELS.length);
    return;
  }
  ui.matchResult(match, matchCtx);
}

function quitMatch() {
  running = false;
  paused = false;
  input.clear();
  ui.hideHud();
  if (matchCtx.type === 'season' && season) {
    const fx = matchCtx.fx;
    const score = fx.userIsHome ? [0, 3] : [3, 0];
    recordUserResult(season, fx, score, false);
    saveSeason(season);
    showHub();
  } else if (matchCtx.type === 'training') showTraining();
  else showMenu();
}

// ------------------------------------------------------------------ screens
function showMenu() {
  running = false;
  startDemo();
  ui.mainMenu({ hasSeason: !!season && !season.finished, trophies: season?.trophies });
}

function showHub(tab = 'next') {
  if (!season) { season = newSeason(null); }
  const fx = season.finished ? null : advanceToUserFixture(season);
  saveSeason(season);
  ui.seasonHub(season, fx, tab);
}

function showTraining() { ui.training(LEVELS, training); }

let pendingLevel = 0;
function introLevel(i) {
  if (!isUnlocked(training, i)) return;
  pendingLevel = i;
  ui.levelIntro(LEVELS[i], i);
}

function beginLevel() {
  const lv = LEVELS[pendingLevel];
  const away = lv.away.some((a) => a.role === 'D' || a.role === 'F') ? { ...TEAMS[6], tactics: { ...DEFAULT_TACTICS, pressing: 0.7 } } : DRILL_TEAM;
  startMatch(userTeam(), away, { type: 'training', level: pendingLevel, label: tl(lv.name), scenario: lv, world: lv.world });
}

ui.on('menu', showMenu);
ui.on('help', () => ui.help());
ui.on('noop', () => {});
ui.on('training', showTraining);
ui.on('startLevel', (i) => introLevel(+i));
ui.on('beginLevel', beginLevel);
ui.on('retryLevel', () => { introLevel(pendingLevel); beginLevel(); });
ui.on('nextLevel', () => { pendingLevel = Math.min(pendingLevel + 1, LEVELS.length - 1); introLevel(pendingLevel); });
ui.on('continue', () => showHub());
ui.on('newSeason', () => { season = newSeason(season); saveSeason(season); showHub(); });
ui.on('tab', (tab) => showHub(tab));
ui.on('quick', () => {
  const opp = randomOpponent(USER_TEAM_ID);
  const world = WORLD_IDS[Math.floor(Math.random() * WORLD_IDS.length)];
  startMatch(userTeam(), opp, { type: 'quick', label: t('season.friendlyVs', { team: tl(opp.name) }), world });
});
ui.on('playFixture', () => {
  const fx = advanceToUserFixture(season);
  if (!fx) return showHub();
  const opp = fx.userIsHome ? fx.away : fx.home;
  const label = fx.type === 'league' ? t('season.round', { n: fx.round + 1 }) : t('season.cupRound', { round: ui.cupRoundName(fx.round) });
  // played in the home team's world
  startMatch(userTeam(), opp, { type: 'season', fx, label, world: fx.home.world });
});
ui.on('afterMatch', () => { if (matchCtx?.type === 'season') showHub(); else showMenu(); });
ui.on('tactics', () => ui.tactics(settings.tactics, settings));
ui.on('resetTactics', () => { settings = { tactics: { ...DEFAULT_TACTICS }, periodSeconds: RULES.periodSeconds, orbitPeriod: ORBIT.period }; saveSettings(); ui.tactics(settings.tactics, settings); });
ui.on('saveTactics', () => {
  const r = ui.readTactics();
  settings.tactics = { ...settings.tactics, ...r.tactics };
  if (r.settings.periodSeconds) settings.periodSeconds = r.settings.periodSeconds;
  if (r.settings.orbitPeriod10) settings.orbitPeriod = r.settings.orbitPeriod10 / 10;
  saveSettings();
  showMenu();
});
ui.on('pause', () => { if (!running) return; paused = true; input.clear(); ui.pause(); });
ui.on('resume', () => { paused = false; ui.hide(); });
ui.on('quitMatch', quitMatch);

// ------------------------------------------------------------------ loop
let last = performance.now();
let acc = 0;
const STEP = 1 / 120;
function frame(now) {
  requestAnimationFrame(frame);
  let dt = (now - last) / 1000;
  last = now;
  if (dt > 0.1) dt = 0.1;
  if (match) director.update(dt, match);
  if (match && running && !paused) {
    match.userPower = input.isHolding ? input.power : ORBIT.powerDefault;
    acc += dt * director.timeScale;
    while (acc >= STEP) { match.update(STEP); acc -= STEP; }
    ui.updateHud(match);
    const c = match.puck.carrier;
    const showPower = input.isHolding && c && match.isUserCarrier(c);
    powerEl.classList.toggle('hidden', !showPower);
    if (showPower) powerFill.style.height = `${Math.round(input.power * 100)}%`;
  } else {
    powerEl.classList.add('hidden');
    if (match && !running && matchCtx == null && !match.ended) match.update(dt * director.timeScale); // demo behind the menus
  }
  renderer.update(match, dt, director.override());
}
requestAnimationFrame(frame);

document.addEventListener('visibilitychange', () => { if (document.hidden && running && !paused) ui.fire('pause'); });

// A fully automatic demo match plays behind the menu so the title screen is alive.
let demoIndex = Math.floor(Math.random() * WORLD_IDS.length);
function startDemo() {
  if (match && matchCtx == null && !match.ended) return;
  matchCtx = null;
  const world = worldById(WORLD_IDS[demoIndex++ % WORLD_IDS.length]);
  match = new Match({ home: userTeam(), away: TEAMS[3], periodSeconds: 999, autoUser: true, sport: world.sport, onEvent: (e) => { if (e.type === 'goal') director.onGoal(match, e); } });
  renderer.setWorld(world);
  renderer.buildPlayers(match);
}
showMenu();

// expose for debugging / automated tests
window.__game = { get match() { return match; }, renderer, ui, input, director, startMatch, userTeam, TEAMS, LEVELS, worldById, WORLD_IDS, get season() { return season; }, get ctx() { return matchCtx; } };
