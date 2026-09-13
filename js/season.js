import { TEAMS, USER_TEAM_ID, teamById } from './teams.js';
import { SAVE_KEY } from './config.js';
import { rand, pick } from './math.js';

// ------------------------------------------------------------------ fixtures
/** Double round robin with the circle method: 8 teams -> 14 rounds. */
function leagueRounds(ids) {
  const n = ids.length;
  const arr = [...ids];
  const rounds = [];
  for (let r = 0; r < n - 1; r++) {
    const round = [];
    for (let i = 0; i < n / 2; i++) {
      const a = arr[i], b = arr[n - 1 - i];
      round.push(r % 2 === 0 ? { home: a, away: b, result: null } : { home: b, away: a, result: null });
    }
    rounds.push(round);
    arr.splice(1, 0, arr.pop()); // rotate all but the first
  }
  const second = rounds.map((round) => round.map((f) => ({ home: f.away, away: f.home, result: null })));
  return [...rounds, ...second];
}

function shuffle(a) { const b = [...a]; for (let i = b.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [b[i], b[j]] = [b[j], b[i]]; } return b; }

export function newSeason(prev) {
  const ids = TEAMS.map((t) => t.id);
  const league = leagueRounds(shuffle(ids));
  const cupIds = shuffle(ids);
  const qf = [];
  for (let i = 0; i < 8; i += 2) qf.push({ home: cupIds[i], away: cupIds[i + 1], result: null, winner: null });
  // matchday plan: L1-4, QF, L5-9, SF, L10-14, F
  const plan = [];
  for (let i = 0; i < 14; i++) {
    plan.push({ type: 'league', round: i });
    if (i === 3) plan.push({ type: 'cup', round: 0 });
    if (i === 8) plan.push({ type: 'cup', round: 1 });
  }
  plan.push({ type: 'cup', round: 2 });
  const table = {};
  for (const id of ids) table[id] = { p: 0, w: 0, d: 0, l: 0, gf: 0, ga: 0, pts: 0 };
  return {
    version: 1,
    seasonNumber: (prev?.seasonNumber || 0) + 1,
    userTeamId: USER_TEAM_ID,
    matchday: 0,
    plan,
    league: { rounds: league, table },
    cup: { rounds: [qf, [], []], names: ['Quarter-final', 'Semi-final', 'Final'] },
    history: [],
    trophies: prev?.trophies || { league: 0, cup: 0 },
    finished: false,
    summary: null,
  };
}

// ------------------------------------------------------------------ simulation
function poisson(lambda) {
  const L = Math.exp(-lambda);
  let k = 0, p = 1;
  do { k++; p *= Math.random(); } while (p > L);
  return k - 1;
}

export function simulateScore(homeId, awayId, opts = {}) {
  const h = teamById(homeId).rating, a = teamById(awayId).rating;
  const lh = 2.3 * Math.exp((h - a) / 22) + 0.15;
  const la = 2.3 * Math.exp((a - h) / 22);
  let gh = poisson(lh), ga = poisson(la);
  let overtime = false;
  if (opts.noDraw && gh === ga) {
    overtime = true;
    const pHome = lh / (lh + la);
    if (Math.random() < pHome) gh++; else ga++;
  }
  return { score: [gh, ga], overtime };
}

function applyLeagueResult(state, f, score) {
  f.result = score;
  const th = state.league.table[f.home], ta = state.league.table[f.away];
  th.p++; ta.p++;
  th.gf += score[0]; th.ga += score[1];
  ta.gf += score[1]; ta.ga += score[0];
  if (score[0] > score[1]) { th.w++; ta.l++; th.pts += 3; }
  else if (score[0] < score[1]) { ta.w++; th.l++; ta.pts += 3; }
  else { th.d++; ta.d++; th.pts++; ta.pts++; }
}

function applyCupResult(state, roundIdx, f, score, overtime) {
  f.result = score;
  f.overtime = !!overtime;
  f.winner = score[0] > score[1] ? f.home : f.away;
  const round = state.cup.rounds[roundIdx];
  if (round.every((x) => x.winner) && roundIdx < 2) {
    const winners = round.map((x) => x.winner);
    const next = [];
    for (let i = 0; i < winners.length; i += 2) next.push({ home: winners[i], away: winners[i + 1], result: null, winner: null });
    state.cup.rounds[roundIdx + 1] = next;
  }
}

/** The user's fixture on the current matchday, or null if none (e.g. knocked out of the cup). */
export function userFixture(state) {
  const md = state.plan[state.matchday];
  if (!md) return null;
  const fixtures = md.type === 'league' ? state.league.rounds[md.round] : state.cup.rounds[md.round];
  const f = fixtures.find((x) => (x.home === state.userTeamId || x.away === state.userTeamId) && !x.result);
  if (!f) return null;
  return { type: md.type, round: md.round, fixture: f, home: teamById(f.home), away: teamById(f.away),
    userIsHome: f.home === state.userTeamId, label: md.type === 'league' ? `League · Round ${md.round + 1}` : `Cup · ${state.cup.names[md.round]}` };
}

/** Simulate every other match of the matchday and advance. */
export function finishMatchday(state) {
  const md = state.plan[state.matchday];
  if (!md) return;
  const fixtures = md.type === 'league' ? state.league.rounds[md.round] : state.cup.rounds[md.round];
  for (const f of fixtures) {
    if (f.result) continue;
    const r = simulateScore(f.home, f.away, { noDraw: md.type === 'cup' });
    if (md.type === 'league') applyLeagueResult(state, f, r.score);
    else applyCupResult(state, md.round, f, r.score, r.overtime);
  }
  state.matchday++;
  if (state.matchday >= state.plan.length) endSeason(state);
}

/** Skip forward over matchdays where the user has nothing to play. */
export function advanceToUserFixture(state) {
  while (!state.finished && !userFixture(state)) finishMatchday(state);
  return userFixture(state);
}

/** Record the user's played match. */
export function recordUserResult(state, fx, score, overtime) {
  const md = state.plan[state.matchday];
  if (md.type === 'league') applyLeagueResult(state, fx.fixture, score);
  else applyCupResult(state, md.round, fx.fixture, score, overtime);
  state.history.push({ type: md.type, round: md.round, home: fx.fixture.home, away: fx.fixture.away, score, overtime: !!overtime });
  finishMatchday(state);
}

export function standings(state) {
  return Object.entries(state.league.table)
    .map(([id, s]) => ({ id, team: teamById(id), ...s, gd: s.gf - s.ga }))
    .sort((a, b) => b.pts - a.pts || b.gd - a.gd || b.gf - a.gf || a.team.name.localeCompare(b.team.name));
}

function endSeason(state) {
  state.finished = true;
  const st = standings(state);
  const champion = st[0].id;
  const finalF = state.cup.rounds[2][0];
  const cupWinner = finalF?.winner || null;
  if (champion === state.userTeamId) state.trophies.league++;
  if (cupWinner === state.userTeamId) state.trophies.cup++;
  state.summary = { champion, cupWinner, position: st.findIndex((r) => r.id === state.userTeamId) + 1 };
}

// ------------------------------------------------------------------ persistence
export function saveSeason(state) {
  try { localStorage.setItem(SAVE_KEY, JSON.stringify(state)); } catch (e) { /* storage may be unavailable */ }
}

export function loadSeason() {
  try {
    const raw = localStorage.getItem(SAVE_KEY);
    if (!raw) return null;
    const s = JSON.parse(raw);
    if (s.version !== 1) return null;
    return s;
  } catch (e) { return null; }
}

export function clearSeason() {
  try { localStorage.removeItem(SAVE_KEY); } catch (e) { /* ignore */ }
}

export function randomOpponent(excludeId) {
  return pick(TEAMS.filter((t) => t.id !== excludeId));
}
