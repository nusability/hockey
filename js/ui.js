import { TEAMS, teamById } from './teams.js';
import { standings } from './season.js';
import { fmtClock } from './math.js';

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
        <p class="tagline">Two thumbs. Six skaters. One net.</p>
        <div class="stack">
          ${hasSeason ? '<button class="btn primary" data-action="continue">Continue season</button>' : ''}
          <button class="btn ${hasSeason ? '' : 'primary'}" data-action="newSeason">${hasSeason ? 'Start a new season' : 'Start season'}</button>
          <button class="btn" data-action="quick">Quick match</button>
          <button class="btn" data-action="tactics">Coach &amp; settings</button>
          <button class="btn" data-action="help">How to play</button>
        </div>
        ${trophies && (trophies.league || trophies.cup) ? `<p class="muted">🏆 League titles: ${trophies.league} · 🏅 Cups: ${trophies.cup}</p>` : ''}
      </div>`);
  }

  help() {
    this.show(`
      <div class="screen">
        <h2>How to play</h2>
        <ul class="help">
          <li><b>Drag</b> anywhere to grab the nearest skater and steer them. Use a <b>second finger</b> to move a second player at the same time.</li>
          <li><b>Tap</b> a team-mate while you have the puck to <b>pass</b> to them. The pass leads them into space.</li>
          <li><b>Tap the goal</b> (or flick the finger that holds the carrier) to <b>shoot</b>. Faster flicks hit harder.</li>
          <li>Skate into loose pucks to collect them. Defenders steal the puck when they reach it, so keep it moving: pass, get open, one-timer, slam it in.</li>
          <li>Offside and icing are called. Three periods; cup ties go to sudden-death overtime.</li>
          <li>Your other four skaters and the goalie play on their own, following the team's tactics: pressing, covering, push-up, passing and shooting appetite.</li>
        </ul>
        <button class="btn primary" data-action="menu">Back</button>
      </div>`);
  }

  tactics(tactics, settings) {
    const slider = (key, label, hint) => `
      <label class="slider"><span>${label}<small>${hint}</small></span>
        <input type="range" min="0" max="100" value="${Math.round(tactics[key] * 100)}" data-tactic="${key}">
      </label>`;
    this.show(`
      <div class="screen">
        <h2>Coach's board</h2>
        <p class="muted">Tactics shape how your automatic players behave.</p>
        ${slider('pressing', 'Pressing', 'chase the puck carrier')}
        ${slider('covering', 'Covering', 'mark opponents tightly')}
        ${slider('pushUp', 'Push up', 'how high the team plays')}
        ${slider('passing', 'Passing', 'team-mates pass rather than carry')}
        ${slider('shooting', 'Shooting', 'shoot from distance')}
        <h3>Settings</h3>
        <label class="slider"><span>Period length<small><span id="plen">${settings.periodSeconds}</span> s</small></span>
          <input type="range" min="60" max="240" step="30" value="${settings.periodSeconds}" data-setting="periodSeconds">
        </label>
        <div class="row">
          <button class="btn" data-action="resetTactics">Reset</button>
          <button class="btn primary" data-action="saveTactics">Save</button>
        </div>
      </div>`);
    this.root.querySelector('[data-setting="periodSeconds"]').addEventListener('input', (e) => { $('#plen').textContent = e.target.value; });
  }

  readTactics() {
    const t = {};
    this.root.querySelectorAll('[data-tactic]').forEach((el) => { t[el.dataset.tactic] = el.value / 100; });
    const settings = {};
    this.root.querySelectorAll('[data-setting]').forEach((el) => { settings[el.dataset.setting] = +el.value; });
    return { tactics: t, settings };
  }

  seasonHub(state, fx, tab = 'next') {
    const user = teamById(state.userTeamId);
    const tabs = ['next', 'league', 'cup'].map((t) => `<button class="tab ${t === tab ? 'on' : ''}" data-action="tab" data-arg="${t}">${t === 'next' ? 'Next match' : t === 'league' ? 'League' : 'Cup'}</button>`).join('');
    let body = '';
    if (tab === 'next') {
      if (state.finished) body = this.seasonSummary(state);
      else if (fx) {
        body = `
          <p class="muted">${fx.label}</p>
          <div class="matchup">
            <div class="side">${this.badge(fx.home, 'big')}<b>${fx.home.name}</b><small>Home · ${fx.home.rating} OVR</small></div>
            <div class="vs">VS</div>
            <div class="side">${this.badge(fx.away, 'big')}<b>${fx.away.name}</b><small>Away · ${fx.away.rating} OVR</small></div>
          </div>
          <button class="btn primary big" data-action="playFixture">Play match</button>
          ${this.recentResults(state)}`;
      }
    } else if (tab === 'league') {
      const rows = standings(state).map((r, i) => `
        <tr class="${r.id === state.userTeamId ? 'me' : ''}"><td>${i + 1}</td><td class="name">${this.dot(r.team)} ${r.team.name}</td>
        <td>${r.p}</td><td>${r.w}</td><td>${r.d}</td><td>${r.l}</td><td>${r.gd > 0 ? '+' : ''}${r.gd}</td><td><b>${r.pts}</b></td></tr>`).join('');
      body = `<div class="tablewrap"><table class="table"><thead><tr><th>#</th><th>Team</th><th>P</th><th>W</th><th>D</th><th>L</th><th>GD</th><th>Pts</th></tr></thead><tbody>${rows}</tbody></table></div>
        <p class="muted">Season ${state.seasonNumber} · Matchday ${Math.min(state.matchday + 1, state.plan.length)} of ${state.plan.length}</p>`;
    } else {
      body = `<div class="bracket">${state.cup.rounds.map((round, i) => `
        <div class="round"><h4>${state.cup.names[i]}</h4>${round.length ? round.map((f) => {
          const h = teamById(f.home), a = teamById(f.away);
          const res = f.result ? `${f.result[0]}–${f.result[1]}${f.overtime ? ' <small>OT</small>' : ''}` : 'vs';
          return `<div class="tie ${(f.home === state.userTeamId || f.away === state.userTeamId) ? 'me' : ''}">
            <span class="${f.winner === f.home ? 'w' : ''}">${this.badge(h)}</span><b>${res}</b><span class="${f.winner === f.away ? 'w' : ''}">${this.badge(a)}</span></div>`;
        }).join('') : '<p class="muted">To be decided</p>'}</div>`).join('')}</div>`;
    }
    this.show(`
      <div class="screen">
        <div class="hubhead">${this.badge(user, 'big')}<div><h2>${user.name}</h2><small>Season ${state.seasonNumber}</small></div>
          <button class="btn small" data-action="menu">Menu</button></div>
        <div class="tabs">${tabs}</div>
        ${body}
      </div>`);
  }

  recentResults(state) {
    const last = state.history.slice(-3).reverse();
    if (!last.length) return '';
    return `<h3>Recent results</h3><ul class="results">${last.map((h) => {
      const a = teamById(h.home), b = teamById(h.away);
      return `<li>${this.badge(a)} ${a.short} <b>${h.score[0]}–${h.score[1]}${h.overtime ? ' OT' : ''}</b> ${b.short} ${this.badge(b)} <small>${h.type === 'league' ? 'League' : 'Cup'}</small></li>`;
    }).join('')}</ul>`;
  }

  seasonSummary(state) {
    const s = state.summary;
    const ch = teamById(s.champion), cw = s.cupWinner ? teamById(s.cupWinner) : null;
    const isChamp = s.champion === state.userTeamId, isCup = s.cupWinner === state.userTeamId;
    return `
      <div class="summary">
        <h3>Season ${state.seasonNumber} is over</h3>
        <p>🏆 League champion: ${this.badge(ch)} <b>${ch.name}</b>${isChamp ? ' — that\'s you!' : ''}</p>
        ${cw ? `<p>🏅 Cup winner: ${this.badge(cw)} <b>${cw.name}</b>${isCup ? ' — that\'s you!' : ''}</p>` : ''}
        <p>You finished <b>${s.position}${['st', 'nd', 'rd'][s.position - 1] || 'th'}</b> in the league.</p>
        <button class="btn primary big" data-action="newSeason">Start next season</button>
      </div>`;
  }

  matchResult(match, ctx) {
    const [h, a] = match.teams;
    const userWon = match.score[0] > match.score[1];
    const draw = match.score[0] === match.score[1];
    this.show(`
      <div class="screen center">
        <p class="muted">${ctx.label || 'Friendly'}</p>
        <h2 class="result-title">${draw ? 'DRAW' : userWon ? 'VICTORY!' : 'DEFEAT'}</h2>
        <div class="scoreline">${this.badge(h, 'big')}<b>${match.score[0]}</b><span>–</span><b>${match.score[1]}</b>${this.badge(a, 'big')}</div>
        ${match.isOvertime ? '<p class="muted">Decided in overtime</p>' : ''}
        <table class="stats"><tr><td>${match.stats.shots[0]}</td><th>Shots</th><td>${match.stats.shots[1]}</td></tr>
          <tr><td>${match.stats.passes[0]}</td><th>Passes</th><td>${match.stats.passes[1]}</td></tr>
          <tr><td>${match.stats.steals[0]}</td><th>Steals</th><td>${match.stats.steals[1]}</td></tr></table>
        <button class="btn primary big" data-action="afterMatch">Continue</button>
      </div>`);
  }

  pause() {
    this.show(`
      <div class="screen center">
        <h2>Paused</h2>
        <div class="stack">
          <button class="btn primary" data-action="resume">Resume</button>
          <button class="btn" data-action="quitMatch">Quit match</button>
        </div>
      </div>`);
  }

  // ---------------------------------------------------------------- HUD
  showHud(match) {
    const [h, a] = match.teams;
    this.hud.innerHTML = `
      <div class="score">
        ${this.badge(h)}<b id="s0">0</b><span class="clock"><em id="period">P1</em><i id="clock">0:00</i></span><b id="s1">0</b>${this.badge(a)}
      </div>
      <button id="pauseBtn" class="pausebtn" aria-label="Pause">II</button>`;
    this.hud.classList.remove('hidden');
    $('#pauseBtn').addEventListener('click', () => this.fire('pause'));
    this.hudEls = { s0: $('#s0'), s1: $('#s1'), clock: $('#clock'), period: $('#period') };
  }

  hideHud() { this.hud.classList.add('hidden'); this.hideBanner(); }

  updateHud(match) {
    if (!this.hudEls) return;
    this.hudEls.s0.textContent = match.score[0];
    this.hudEls.s1.textContent = match.score[1];
    this.hudEls.clock.textContent = match.isOvertime ? 'OT' : fmtClock(match.clock);
    this.hudEls.period.textContent = match.isOvertime ? 'OT' : `P${match.period}`;
  }

  showBanner(text, cls = '', ms = 1600) {
    this.banner.textContent = text;
    this.banner.className = `banner ${cls}`;
    clearTimeout(this.bannerTimer);
    if (ms > 0) this.bannerTimer = setTimeout(() => this.hideBanner(), ms);
  }

  hideBanner() { this.banner.className = 'banner hidden'; }
}
