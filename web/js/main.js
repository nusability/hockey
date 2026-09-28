import { Match } from './match.js';
import { Renderer } from './render.js';
import { Input, DRAG } from './input.js';
import { UI } from './ui.js';
import { Sfx } from './audio.js';
import { Director } from './director.js';
import { TEAMS, teamById, USER_TEAM_ID } from './teams.js';
import { DEFAULT_TACTICS, SETTINGS_KEY, RULES, ORBIT } from './config.js';
import { newSeason, loadSeason, saveSeason, advanceToUserFixture, recordUserResult, randomOpponent } from './season.js';
import { LEVELS, loadTraining, saveTraining, isUnlocked } from './levels.js';
import { t, tl, LANG } from './i18n.js';
import { worldById, WORLD_IDS } from './worlds/index.js';
import { checkForUpdate } from './update.js';
import { DEFAULT_FORMATION } from './formations.js';

const canvas = document.getElementById('game');
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
ui.onClick = () => sfx.click();
const director = new Director();
for (const ev of ['pointerdown', 'touchstart', 'click', 'keydown']) {
  window.addEventListener(ev, () => sfx.unlock(), { passive: true });
}
document.addEventListener('visibilitychange', () => { if (!document.hidden) sfx.unlock(); });

// The training opponents: a neutral gray side used for drills.
const DRILL_TEAM = { id: 'drill', name: { en: 'Training', de: 'Training' }, short: 'TRN', world: 'magicwood', primary: '#94a3b8', secondary: '#f97316', rating: 74, tactics: { ...DEFAULT_TACTICS, pressing: 0.7 } };
document.documentElement.lang = LANG;

// ------------------------------------------------------------------ settings
function loadSettings() {
  const base = { tactics: { ...DEFAULT_TACTICS }, periodSeconds: RULES.periodSeconds, orbitPeriod: ORBIT.period, formation: DEFAULT_FORMATION };
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
    formations: [settings.formation, DEFAULT_FORMATION],
    sport: world.sport,
    onEvent: onMatchEvent,
  });
  // control hands over without a lift: the finger re-centres where it already is
  match.onHandover = () => input.recentre();
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
      if (e.team === 0) sfx.goal(); else sfx.goalAgainst();
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
    case 'save': sfx.save(); break;
    case 'possess': if (e.by.team === 0) sfx.receive(); break;
    case 'shot': director.onShot(match, e); sfx.shot(e.speed); break;
    case 'pass': sfx.pass(); break;
    case 'steal': sfx.steal(); break;
    case 'end':
      ui.showBanner(match.message, e.won === false ? 'bad' : 'goal', 1500, match.messageParams);
      sfx.whistle();
      setTimeout(() => { (match.won === false ? sfx.fail() : sfx.success()); finishMatch(); }, 1300);
      break;
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
  // a new build may have gone live while this tab was open; reload if so
  checkForUpdate();
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
ui.on('pickFormation', (id) => {
  // keep whatever the sliders are showing, then redraw with the new shape
  const r = ui.readTactics();
  settings.tactics = { ...settings.tactics, ...r.tactics };
  if (r.settings.periodSeconds) settings.periodSeconds = r.settings.periodSeconds;
  if (r.settings.orbitPeriod10) settings.orbitPeriod = r.settings.orbitPeriod10 / 10;
  settings.formation = id;
  saveSettings();
  ui.tactics(settings.tactics, settings);
});
ui.on('resetTactics', () => { settings = { tactics: { ...DEFAULT_TACTICS }, periodSeconds: RULES.periodSeconds, orbitPeriod: ORBIT.period, formation: DEFAULT_FORMATION }; saveSettings(); ui.tactics(settings.tactics, settings); });
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
let lastTick = -1;
let acc = 0;
const STEP = 1 / 120;
function frame(now) {
  requestAnimationFrame(frame);
  let dt = (now - last) / 1000;
  last = now;
  if (dt > 0.1) dt = 0.1;
  if (match) director.update(dt, match);
  if (match && running && !paused) {
    acc += dt * director.timeScale;
    // the finger's order is read fresh for the frame, not queued: nothing sits between the
    // pointer event and the step that acts on it (A0)
    match.setSteer(input.steer);
    match.armed = input.armed;      // past the third ring: a lift shoots, and the pitch says so
    while (acc >= STEP) { match.update(STEP); acc -= STEP; }
    ui.updateHud(match);
    // count down the last five seconds
    if (match.state === 'play' && !match.isOvertime) {
      const secs = Math.ceil(match.clock);
      if (secs !== lastTick && secs <= 5 && secs > 0) { lastTick = secs; sfx.tick(); }
      if (secs > 5) lastTick = -1;
    }
  } else if (match && !running && matchCtx == null && !match.ended) {
    match.update(dt * director.timeScale); // demo behind the menus
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

// Which control scheme this build is playing, stated on screen. Both schemes live in one build
// behind `?control=` and they are told apart only by how the game answers your finger — which is
// exactly the thing being judged, so it must never be the thing you have to guess. Prototype
// furniture; it costs nothing to delete with the rest of the experiment.
{
  const scheme = new URLSearchParams(location.search).get('control') || 'touch';
  if (scheme !== 'touch') {
    // The build id stays. A stale tab spent a round of this experiment masquerading as an
    // inverted control, and one line on screen is cheaper than finding that out twice.
    const build = document.querySelector('meta[name="build"]')?.content || 'dev';
    const tag = document.createElement('div');
    tag.textContent = `${scheme}  ${build.slice(0, 7)}`;
    tag.style.cssText = 'position:fixed;left:8px;bottom:8px;z-index:50;font:600 11px/1 ui-monospace,monospace;'
      + 'letter-spacing:.06em;color:#38bdf8;background:rgba(2,6,23,.55);padding:5px 8px;border-radius:5px;'
      + 'pointer-events:none';
    document.body.appendChild(tag);

    // The dial under the thumb.
    //
    // Two rings — the deadzone edge and the full-speed edge — and a triangle riding the outer
    // one at the angle the thumb is pointing. The triangle is the part that matters: a thumb
    // cannot judge its own angle anywhere near the precision a goal mouth asks for, so after a
    // flick the triangle stays behind at the angle that was actually flicked, holds, and fades.
    // That is the only way to learn the gesture — you find out what you did while you can still
    // remember doing it.
    //
    // SVG so the shapes stay crisp at any density and can carry a glow. Screen furniture on
    // purpose: in the apps this belongs in the 3D scene with the rest of the UI (conventions),
    // and none of it is meant to outlive the experiment.
    const NS = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(NS, 'svg');
    svg.style.cssText = 'position:fixed;inset:0;width:100vw;height:100vh;pointer-events:none;z-index:40';
    svg.innerHTML = `<defs>
      <filter id="sg" x="-80%" y="-80%" width="260%" height="260%">
        <feGaussianBlur stdDeviation="5" result="b"/>
        <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
      </filter>
    </defs>`;
    document.body.appendChild(svg);

    // pointing up the screen; rotated into place. A notched head, like the aim arrow's.
    const HEAD = 'M 0,-15 L 10,7 L 0,1.5 L -10,7 Z';
    const mk = (tag, attrs) => {
      const el = document.createElementNS(NS, tag);
      for (const k in attrs) el.setAttribute(k, attrs[k]);
      svg.appendChild(el);
      return el;
    };
    const gDead = mk('circle', { r: DRAG.deadzone, fill: 'none', stroke: '#38bdf8', 'stroke-width': 1.5 });
    const gFull = mk('circle', { r: DRAG.full, fill: 'none', stroke: '#38bdf8', 'stroke-width': 2.5 });
    // the third ring: cross it and a lift becomes an aimed shot
    const gShoot = mk('circle', { r: DRAG.shoot, fill: 'none', stroke: '#f472b6',
      'stroke-width': 3, 'stroke-dasharray': '10 8' });
    const gLive = mk('path', { d: HEAD, fill: '#7dd3fc', filter: 'url(#sg)' });

    // screen angle, not the world one: this sits under the thumb, so it follows the thumb. (The
    // world vector is the mirror of it — see Input#steer.)
    const place = (el, cx, cy, dx, dy, r, scale) => {
      const deg = Math.atan2(dx, -dy) * 180 / Math.PI;
      el.setAttribute('transform', `translate(${cx} ${cy}) rotate(${deg}) translate(0 ${-r}) scale(${scale})`);
    };
    const set = (el, o) => { el.style.opacity = o; };

    const paint = () => {
      requestAnimationFrame(paint);
      const held = input.steerId !== null;

      for (const el of [gDead, gFull, gShoot, gLive]) set(el, held ? 1 : 0);
      if (held) {
        const cx = input.originX, cy = input.originY;
        for (const el of [gDead, gFull, gShoot]) { el.setAttribute('cx', cx); el.setAttribute('cy', cy); }
        const dx = input.curX - cx, dy = input.curY - cy;
        const d = Math.hypot(dx, dy);
        const past = d >= DRAG.deadzone;
        const armed = d >= DRAG.shoot;
        gDead.style.stroke = past ? 'rgba(56,189,248,.95)' : 'rgba(56,189,248,.4)';
        gFull.style.stroke = d >= DRAG.full ? 'rgba(125,211,252,1)' : 'rgba(56,189,248,.3)';
        // the shot ring only really shows once the thumb is on its way out to it, so it does not
        // clutter an ordinary steer, and it lights when crossed
        set(gShoot, armed ? 1 : Math.max(0, (d - DRAG.full) / Math.max(1, DRAG.shoot - DRAG.full)) * 0.75);
        gShoot.style.stroke = armed ? 'rgba(244,114,182,1)' : 'rgba(244,114,182,.5)';
        set(gLive, past ? 1 : 0);
        if (past) {
          // rides the outer ring whatever the drag length, so the angle is always read off the
          // same circle — that is what makes two gestures comparable to the eye. Armed, it moves
          // out to the shot ring and turns the shot's colour: the triangle is then the aim.
          const t = Math.min(1, (d - DRAG.deadzone) / Math.max(1, DRAG.full - DRAG.deadzone));
          gLive.style.fill = armed ? '#f9a8d4' : '#7dd3fc';
          place(gLive, cx, cy, dx, dy, armed ? DRAG.shoot : DRAG.full, armed ? 1.5 : 0.8 + t * 0.45);
        }
      }

    };
    requestAnimationFrame(paint);
  }
}

// expose for debugging / automated tests
window.__game = { get match() { return match; }, renderer, ui, input, director, sfx, startMatch, userTeam, TEAMS, LEVELS, worldById, WORLD_IDS, get season() { return season; }, get ctx() { return matchCtx; } };
