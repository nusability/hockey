import { Match } from './match.js';
import { Renderer } from './render.js';
import { Input } from './input.js';
import { UI } from './ui.js';
import { Sfx } from './audio.js';
import { TEAMS, teamById, USER_TEAM_ID } from './teams.js';
import { DEFAULT_TACTICS, SETTINGS_KEY, RULES } from './config.js';
import { newSeason, loadSeason, saveSeason, advanceToUserFixture, recordUserResult, randomOpponent } from './season.js';

const canvas = document.getElementById('game');
const ui = new UI();
const renderer = new Renderer(canvas);
let match = null;
let matchCtx = null;      // { type:'quick'|'season', fx, label }
let season = loadSeason();
let paused = false;
let running = false;
const input = new Input(canvas, renderer, () => (running && !paused ? match : null));
const sfx = new Sfx();
window.addEventListener('pointerdown', () => sfx.unlock(), { passive: true });

// ------------------------------------------------------------------ settings
function loadSettings() {
  try {
    const s = JSON.parse(localStorage.getItem(SETTINGS_KEY) || 'null');
    if (s) return { tactics: { ...DEFAULT_TACTICS, ...s.tactics }, periodSeconds: s.periodSeconds || RULES.periodSeconds };
  } catch (e) { /* ignore */ }
  return { tactics: { ...DEFAULT_TACTICS }, periodSeconds: RULES.periodSeconds };
}
function saveSettings() { try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings)); } catch (e) { /* ignore */ } }
let settings = loadSettings();
const userTeam = () => ({ ...teamById(USER_TEAM_ID), tactics: settings.tactics });

// ------------------------------------------------------------------ match flow
function startMatch(home, away, ctx) {
  matchCtx = ctx;
  match = new Match({
    home, away,
    tactics: [home.tactics, away.tactics],
    periodSeconds: settings.periodSeconds,
    overtime: ctx.type === 'season' && ctx.fx.type === 'cup',
    onEvent: onMatchEvent,
  });
  // the user always plays as team 0 (defending the bottom goal)
  renderer.buildPlayers(match);
  renderer.focusZ = 0;
  ui.hide();
  ui.showHud(match);
  ui.showBanner(`${home.name} vs ${away.name}`, 'info', 2200);
  paused = false;
  running = true;
}

function onMatchEvent(e) {
  switch (e.type) {
    case 'goal': {
      const t = match.teams[e.team];
      renderer.celebrate(e.team, [t.primary, t.secondary, '#ffffff'], match.attackGoalZ(e.team));
      ui.showBanner(e.team === 0 ? 'GOAL!' : 'GOAL AGAINST', e.team === 0 ? 'goal' : 'bad', 2600);
      sfx.horn();
      break;
    }
    case 'whistle': ui.showBanner(e.text, 'warn', 1800); sfx.whistle(); break;
    case 'faceoff': if (e.text && e.text !== 'FACE-OFF') ui.showBanner(e.text, 'info', 1500); break;
    case 'drop': sfx.drop(); break;
    case 'periodEnd': ui.showBanner(match.message, 'info', 2400); sfx.whistle(); break;
    case 'post': renderer.shake = Math.max(renderer.shake, 0.5); sfx.post(); break;
    case 'board': sfx.board(); break;
    case 'shot': sfx.shot(); break;
    case 'pass': sfx.pass(); break;
    case 'steal': if (e.by.team === 0) sfx.steal(); break;
    case 'end': sfx.whistle(); setTimeout(() => finishMatch(), 900); break;
  }
}

function finishMatch() {
  running = false;
  input.releaseAll();
  ui.hideHud();
  if (matchCtx.type === 'season' && season) {
    // the user is always team 0 in the engine; map the score back to home/away
    const fx = matchCtx.fx;
    const score = fx.userIsHome ? [match.score[0], match.score[1]] : [match.score[1], match.score[0]];
    recordUserResult(season, fx, score, match.isOvertime);
    saveSeason(season);
  }
  ui.matchResult(match, matchCtx);
}

function quitMatch() {
  running = false;
  paused = false;
  input.releaseAll();
  ui.hideHud();
  if (matchCtx.type === 'season' && season) {
    // forfeit: recorded as a 0-3 loss
    const fx = matchCtx.fx;
    const score = fx.userIsHome ? [0, 3] : [3, 0];
    recordUserResult(season, fx, score, false);
    saveSeason(season);
    showHub();
  } else showMenu();
}

// ------------------------------------------------------------------ screens
function showMenu() {
  running = false;
  ui.mainMenu({ hasSeason: !!season && !season.finished, trophies: season?.trophies });
}

function showHub(tab = 'next') {
  if (!season) { season = newSeason(null); }
  const fx = season.finished ? null : advanceToUserFixture(season);
  saveSeason(season);
  ui.seasonHub(season, fx, tab);
}

ui.on('menu', showMenu);
ui.on('help', () => ui.help());
ui.on('continue', () => showHub());
ui.on('newSeason', () => { season = newSeason(season); saveSeason(season); showHub(); });
ui.on('tab', (tab) => showHub(tab));
ui.on('quick', () => {
  const opp = randomOpponent(USER_TEAM_ID);
  startMatch(userTeam(), opp, { type: 'quick', label: `Friendly vs ${opp.name}` });
});
ui.on('playFixture', () => {
  const fx = advanceToUserFixture(season);
  if (!fx) return showHub();
  const opp = fx.userIsHome ? fx.away : fx.home;
  startMatch(userTeam(), opp, { type: 'season', fx, label: fx.label });
});
ui.on('afterMatch', () => { if (matchCtx?.type === 'season') showHub(); else showMenu(); });
ui.on('tactics', () => ui.tactics(settings.tactics, settings));
ui.on('resetTactics', () => { settings = { tactics: { ...DEFAULT_TACTICS }, periodSeconds: RULES.periodSeconds }; saveSettings(); ui.tactics(settings.tactics, settings); });
ui.on('saveTactics', () => {
  const r = ui.readTactics();
  settings.tactics = { ...settings.tactics, ...r.tactics };
  if (r.settings.periodSeconds) settings.periodSeconds = r.settings.periodSeconds;
  saveSettings();
  showMenu();
});
ui.on('pause', () => { if (!running) return; paused = true; input.releaseAll(); ui.pause(); });
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
  if (match && running && !paused) {
    acc += dt;
    while (acc >= STEP) { match.update(STEP); acc -= STEP; }
    ui.updateHud(match);
  }
  renderer.update(match, dt);
}
requestAnimationFrame(frame);

document.addEventListener('visibilitychange', () => { if (document.hidden && running && !paused) ui.fire('pause'); });

// Warm up the arena with a demo match behind the menu so the title screen is alive.
const demoHome = userTeam();
match = new Match({ home: demoHome, away: TEAMS[6], periodSeconds: 999, onEvent: () => {} });
renderer.buildPlayers(match);
showMenu();

// demo runs the AI on both teams while no real match is running
(function demoLoop() {
  let lastT = performance.now();
  function tick(now) {
    requestAnimationFrame(tick);
    if (running) return;
    let dt = Math.min(0.1, (now - lastT) / 1000);
    lastT = now;
    if (match && !match.ended && matchCtx == null) match.update(dt);
  }
  requestAnimationFrame(tick);
})();

// expose for debugging / automated tests
window.__game = { get match() { return match; }, renderer, ui, startMatch, userTeam, TEAMS, get season() { return season; } };
