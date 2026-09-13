import { teamById } from './teams.js';
import { standings } from './season.js';
import { fmtClock } from './math.js';
import { t, tl, ordinal } from './i18n.js';
import { worldById } from './worlds/index.js';

const $ = (sel) => document.querySelector(sel);

export class UI {
  constructor() {
    this.root = $('#ui');
    this.hud = $('#hud');
    this.banner = $('#banner');
    this.handlers = {};
    this.bannerTimer = null;
  }

  on(name, fn) { this.handlers[name] = fn; }
  fire(name, ...args) { this.handlers[name]?.(...args); }

  show(html) {
    this.root.innerHTML = html;
    this.root.classList.remove('hidden');
    this.root.querySelectorAll('[data-action]').forEach((el) => {
      el.addEventListener('click', (e) => {
        e.preventDefault();
        this.fire(el.dataset.action, el.dataset.arg, el);
      });
    });
  }

  hide() { this.root.classList.add('hidden'); this.root.innerHTML = ''; }

  dot(team) {
    return `<span class="badge" style="--p:${team.primary};--s:${team.secondary}"><i></i></span>`;
  }

  badge(team, size = '') {
    return `<span class="badge ${size}" style="--p:${team.primary};--s:${team.secondary}"><i></i>${team.short}</span>`;
  }

  // ---------------------------------------------------------------- screens
  mainMenu({ hasSeason, trophies }) {
    this.show(`
      <div class="screen center">
        <div class="logo"><span>SLAPSHOT</span><span class="accent">LEAGUE</span></div>
        <p class="tagline">${t('menu.tagline')}</p>
        <div class="stack">
          <button class="btn primary" data-action="training">${t('menu.training')}</button>
          ${hasSeason ? `<button class="btn" data-action="continue">${t('menu.continue')}</button>` : ''}
          <button class="btn" data-action="newSeason">${hasSeason ? t('menu.newSeason2') : t('menu.newSeason')}</button>
          <button class="btn" data-action="quick">${t('menu.quick')}</button>
          <button class="btn" data-action="tactics">${t('menu.coach')}</button>
          <button class="btn" data-action="help">${t('menu.help')}</button>
        </div>
        ${trophies && (trophies.league || trophies.cup) ? `<p class="muted">${t('menu.trophies', { league: trophies.league, cup: trophies.cup })}</p>` : ''}
      </div>`);
  }

  help() {
    this.show(`
      <div class="screen">
        <h2>${t('help.title')}</h2>
        <ul class="help">
          ${[1, 2, 3, 4, 5, 6, 7].map((i) => `<li>${t(`help.${i}`)}</li>`).join('')}
        </ul>
        <button class="btn primary" data-action="menu">${t('menu.back')}</button>
      </div>`);
  }

  training(levels, progress) {
    const items = levels.map((lv, i) => {
      const done = progress.done.includes(lv.id);
      const unlocked = i === 0 || progress.done.includes(levels[i - 1].id);
      const kind = lv.away.length === 0 ? t('training.none') : lv.away.some((a) => a.role === 'D' || a.role === 'F') ? t('training.defenders') : lv.away.some((a) => a.role === 'O') ? t('training.dummies') : t('training.goalie');
      const world = worldById(lv.world);
      return `<button class="level ${done ? 'done' : ''} ${unlocked ? '' : 'locked'}" data-action="${unlocked ? 'startLevel' : 'noop'}" data-arg="${i}">
        <span class="num">${done ? '✓' : unlocked ? i + 1 : '🔒'}</span>
        <span class="txt"><b>${tl(lv.name)}</b><small>${tl(world.name)} · ${kind} · ${lv.goals} 🥅 / ${lv.time}s</small></span>
      </button>`;
    }).join('');
    this.show(`
      <div class="screen">
        <div class="hubhead"><div><h2>${t('training.title')}</h2><small>${t('training.progress', { done: progress.done.length, total: levels.length })}</small></div>
          <button class="btn small" data-action="menu">${t('menu.menu')}</button></div>
        <div class="levels">${items}</div>
      </div>`);
  }

  levelIntro(level, index) {
    const world = worldById(level.world);
    this.show(`
      <div class="screen center">
        <p class="muted">${t('training.drill', { n: index + 1 })} · ${tl(world.name)}</p>
        <h2>${tl(level.name)}</h2>
        <p class="hint">${tl(level.hint)}</p>
        <p class="muted">${t('training.goalsIn', { goals: level.goals, time: level.time })}</p>
        <p class="muted"><i>${tl(world.tagline)}</i></p>
        <button class="btn primary big" data-action="beginLevel">${t('training.start')}</button>
        <button class="btn" data-action="training" style="margin-top:8px">${t('menu.back')}</button>
      </div>`);
  }

  levelResult(match, level, index, hasNext) {
    const won = match.won;
    this.show(`
      <div class="screen center">
        <p class="muted">${t('training.drill', { n: index + 1 })} · ${tl(level.name)}</p>
        <h2 class="result-title">${won ? t('training.done') : t('training.timeUp')}</h2>
        <p>${won ? t('training.nice') : t('training.scored', { n: match.score[0], goals: level.goals })}</p>
        ${won && hasNext ? `<button class="btn primary big" data-action="nextLevel">${t('training.next')}</button>` : ''}
        <button class="btn ${won && hasNext ? '' : 'primary'} big" data-action="retryLevel">${won ? t('training.again') : t('training.retry')}</button>
        <button class="btn" data-action="training" style="margin-top:8px">${t('training.all')}</button>
      </div>`);
  }

  tactics(tactics, settings) {
    const slider = (key, label, hint) => `
      <label class="slider"><span>${label}<small>${hint}</small></span>
        <input type="range" min="0" max="100" value="${Math.round(tactics[key] * 100)}" data-tactic="${key}">
      </label>`;
    this.show(`
      <div class="screen">
        <h2>${t('coach.title')}</h2>
        <p class="muted">${t('coach.intro')}</p>
        ${slider('pressing', t('coach.pressing'), t('coach.pressingHint'))}
        ${slider('covering', t('coach.covering'), t('coach.coveringHint'))}
        ${slider('pushUp', t('coach.pushUp'), t('coach.pushUpHint'))}
        ${slider('passing', t('coach.passing'), t('coach.passingHint'))}
        ${slider('shooting', t('coach.shooting'), t('coach.shootingHint'))}
        <h3>${t('coach.settings')}</h3>
        <label class="slider"><span>${t('coach.period')}<small><span id="plen">${settings.periodSeconds}</span> s</small></span>
          <input type="range" min="60" max="240" step="30" value="${settings.periodSeconds}" data-setting="periodSeconds">
        </label>
        <label class="slider"><span>${t('coach.spin')}<small id="orb">${t('coach.spinHint', { s: settings.orbitPeriod.toFixed(1) })}</small></span>
          <input type="range" min="14" max="32" step="2" value="${Math.round(settings.orbitPeriod * 10)}" data-setting="orbitPeriod10">
        </label>
        <div class="row">
          <button class="btn" data-action="resetTactics">${t('coach.reset')}</button>
          <button class="btn primary" data-action="saveTactics">${t('coach.save')}</button>
        </div>
      </div>`);
    this.root.querySelector('[data-setting="periodSeconds"]').addEventListener('input', (e) => { $('#plen').textContent = e.target.value; });
    this.root.querySelector('[data-setting="orbitPeriod10"]').addEventListener('input', (e) => { $('#orb').textContent = t('coach.spinHint', { s: (e.target.value / 10).toFixed(1) }); });
  }

  readTactics() {
    const tac = {};
    this.root.querySelectorAll('[data-tactic]').forEach((el) => { tac[el.dataset.tactic] = el.value / 100; });
    const settings = {};
    this.root.querySelectorAll('[data-setting]').forEach((el) => { settings[el.dataset.setting] = +el.value; });
    return { tactics: tac, settings };
  }

  cupRoundName(i) { return [t('season.qf'), t('season.sf'), t('season.f')][i]; }

  seasonHub(state, fx, tab = 'next') {
    const user = teamById(state.userTeamId);
    const tabs = [['next', t('season.next')], ['league', t('season.league')], ['cup', t('season.cup')]]
      .map(([id, label]) => `<button class="tab ${id === tab ? 'on' : ''}" data-action="tab" data-arg="${id}">${label}</button>`).join('');
    let body = '';
    if (tab === 'next') {
      if (state.finished) body = this.seasonSummary(state);
      else if (fx) {
        const label = fx.type === 'league' ? t('season.round', { n: fx.round + 1 }) : t('season.cupRound', { round: this.cupRoundName(fx.round) });
        const world = worldById(fx.home.world);
        body = `
          <p class="muted">${label} · ${tl(world.name)}</p>
          <div class="matchup">
            <div class="side">${this.badge(fx.home, 'big')}<b>${tl(fx.home.name)}</b><small>${t('season.home')} · ${fx.home.rating} OVR</small></div>
            <div class="vs">VS</div>
            <div class="side">${this.badge(fx.away, 'big')}<b>${tl(fx.away.name)}</b><small>${t('season.away')} · ${fx.away.rating} OVR</small></div>
          </div>
          <button class="btn primary big" data-action="playFixture">${t('season.play')}</button>
          ${this.recentResults(state)}`;
      }
    } else if (tab === 'league') {
      const rows = standings(state).map((r, i) => `
        <tr class="${r.id === state.userTeamId ? 'me' : ''}"><td>${i + 1}</td><td class="name">${this.dot(r.team)} ${tl(r.team.name)}</td>
        <td>${r.p}</td><td>${r.w}</td><td>${r.d}</td><td>${r.l}</td><td>${r.gd > 0 ? '+' : ''}${r.gd}</td><td><b>${r.pts}</b></td></tr>`).join('');
      body = `<div class="tablewrap"><table class="table"><thead><tr><th>#</th><th>${t('table.team')}</th><th>${t('table.p')}</th><th>${t('table.w')}</th><th>${t('table.d')}</th><th>${t('table.l')}</th><th>${t('table.gd')}</th><th>${t('table.pts')}</th></tr></thead><tbody>${rows}</tbody></table></div>
        <p class="muted">${t('season.matchday', { n: state.seasonNumber, m: Math.min(state.matchday + 1, state.plan.length), total: state.plan.length })}</p>`;
    } else {
      body = `<div class="bracket">${state.cup.rounds.map((round, i) => `
        <div class="round"><h4>${this.cupRoundName(i)}</h4>${round.length ? round.map((f) => {
          const h = teamById(f.home), a = teamById(f.away);
          const res = f.result ? `${f.result[0]}–${f.result[1]}${f.overtime ? ' <small>OT</small>' : ''}` : 'vs';
          return `<div class="tie ${(f.home === state.userTeamId || f.away === state.userTeamId) ? 'me' : ''}">
            <span class="${f.winner === f.home ? 'w' : ''}">${this.badge(h)}</span><b>${res}</b><span class="${f.winner === f.away ? 'w' : ''}">${this.badge(a)}</span></div>`;
        }).join('') : `<p class="muted">${t('season.tbd')}</p>`}</div>`).join('')}</div>`;
    }
    this.show(`
      <div class="screen">
        <div class="hubhead">${this.badge(user, 'big')}<div><h2>${tl(user.name)}</h2><small>${t('season.season', { n: state.seasonNumber })}</small></div>
          <button class="btn small" data-action="menu">${t('menu.menu')}</button></div>
        <div class="tabs">${tabs}</div>
        ${body}
      </div>`);
  }

  recentResults(state) {
    const last = state.history.slice(-3).reverse();
    if (!last.length) return '';
    return `<h3>${t('season.recent')}</h3><ul class="results">${last.map((h) => {
      const a = teamById(h.home), b = teamById(h.away);
      return `<li>${this.badge(a)} <b>${h.score[0]}–${h.score[1]}${h.overtime ? ' OT' : ''}</b> ${this.badge(b)} <small>${h.type === 'league' ? t('season.league') : t('season.cup')}</small></li>`;
    }).join('')}</ul>`;
  }

  seasonSummary(state) {
    const s = state.summary;
    const ch = teamById(s.champion), cw = s.cupWinner ? teamById(s.cupWinner) : null;
    const isChamp = s.champion === state.userTeamId, isCup = s.cupWinner === state.userTeamId;
    return `
      <div class="summary">
        <h3>${t('season.over', { n: state.seasonNumber })}</h3>
        <p>${t('season.champion')} ${this.badge(ch)} <b>${tl(ch.name)}</b>${isChamp ? t('season.you') : ''}</p>
        ${cw ? `<p>${t('season.cupWinner')} ${this.badge(cw)} <b>${tl(cw.name)}</b>${isCup ? t('season.you') : ''}</p>` : ''}
        <p>${t('season.finished', { pos: ordinal(s.position) })}</p>
        <button class="btn primary big" data-action="newSeason">${t('season.nextSeason')}</button>
      </div>`;
  }

  matchResult(match, ctx) {
    const [h, a] = match.teams;
    const userWon = match.score[0] > match.score[1];
    const draw = match.score[0] === match.score[1];
    this.show(`
      <div class="screen center">
        <p class="muted">${ctx.label || t('season.friendly')}</p>
        <h2 class="result-title">${draw ? t('result.draw') : userWon ? t('result.win') : t('result.loss')}</h2>
        <div class="scoreline">${this.badge(h, 'big')}<b>${match.score[0]}</b><span>–</span><b>${match.score[1]}</b>${this.badge(a, 'big')}</div>
        ${match.isOvertime ? `<p class="muted">${t('result.ot')}</p>` : ''}
        <table class="stats"><tr><td>${match.stats.shots[0]}</td><th>${t('result.shots')}</th><td>${match.stats.shots[1]}</td></tr>
          <tr><td>${match.stats.passes[0]}</td><th>${t('result.passes')}</th><td>${match.stats.passes[1]}</td></tr>
          <tr><td>${match.stats.steals[0]}</td><th>${t('result.steals')}</th><td>${match.stats.steals[1]}</td></tr></table>
        <button class="btn primary big" data-action="afterMatch">${t('result.continue')}</button>
      </div>`);
  }

  pause() {
    this.show(`
      <div class="screen center">
        <h2>${t('pause.title')}</h2>
        <div class="stack">
          <button class="btn primary" data-action="resume">${t('pause.resume')}</button>
          <button class="btn" data-action="quitMatch">${t('pause.quit')}</button>
        </div>
      </div>`);
  }

  // ---------------------------------------------------------------- HUD
  showHud(match) {
    const [h, a] = match.teams;
    this.hud.innerHTML = match.training ? `
      <div class="score">
        <span class="obj">${t('hud.goals')}</span><b id="s0">0</b><span class="clock"><em id="period">${t('hud.of', { n: match.goalsToWin })}</em><i id="clock">0:00</i></span>
      </div>
      <button id="pauseBtn" class="pausebtn" aria-label="Pause">II</button>` : `
      <div class="score">
        ${this.badge(h)}<b id="s0">0</b><span class="clock"><em id="period">P1</em><i id="clock">0:00</i></span><b id="s1">0</b>${this.badge(a)}
      </div>
      <button id="pauseBtn" class="pausebtn" aria-label="Pause">II</button>`;
    this.hud.classList.remove('hidden');
    $('#pauseBtn').addEventListener('click', () => this.fire('pause'));
    this.hudEls = { s0: $('#s0'), s1: $('#s1'), clock: $('#clock'), period: $('#period') };
    const pw = document.querySelector('#power span');
    if (pw) pw.textContent = t('hud.power');
  }

  hideHud() { this.hud.classList.add('hidden'); this.hideBanner(); }

  updateHud(match) {
    if (!this.hudEls) return;
    this.hudEls.s0.textContent = match.score[0];
    if (this.hudEls.s1) this.hudEls.s1.textContent = match.score[1];
    this.hudEls.clock.textContent = match.isOvertime ? 'OT' : fmtClock(match.clock);
    if (!match.training) this.hudEls.period.textContent = match.isOvertime ? 'OT' : `P${match.period}`;
  }

  /** Show an engine message key (translated) as a banner. */
  showBanner(text, cls = '', ms = 1600, params) {
    this.banner.textContent = t(text, params);
    this.banner.className = `banner ${cls}`;
    clearTimeout(this.bannerTimer);
    if (ms > 0) this.bannerTimer = setTimeout(() => this.hideBanner(), ms);
  }

  hideBanner() { this.banner.className = 'banner hidden'; }
}
