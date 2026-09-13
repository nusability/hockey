import { RINK, ORBIT, PLAYER } from './config.js';
import { clamp, dist, norm, pointSegDist, noise } from './math.js';
import { angleDiff } from './match.js';

const HW = RINK.width / 2;
const HL = RINK.length / 2;

/**
 * Drives every player of `team`. Movement is automatic for everyone; only the
 * moment of release is decided by the user for their own skaters. AI carriers
 * wait until the circling puck points at their chosen target, so they play by
 * the same rules as the user.
 *
 * Strategy variables (0..1) come from match.tactics[team]:
 *   pressing  - how many players chase an opposing carrier and from how far
 *   covering  - how tightly free players mark opponents when defending
 *   pushUp    - how far the whole formation shifts towards the puck
 *   passing   - willingness of the carrier to pass rather than carry
 *   shooting  - willingness to shoot from distance
 */
export function updateTeamAI(match, team, dt) {
  const T = match.tactics[team];
  const puck = match.puck;
  const dir = match.dirOf(team);
  const players = match.teamPlayers(team).filter((p) => p.behavior === 'active');
  const carrier = puck.carrier;
  const possession = carrier ? (carrier.team === team ? 'own' : 'their') : 'loose';
  const rating = match.teams[team].rating;
  const skill = clamp((rating - 60) / 30, 0, 1);

  const skaters = players.filter((p) => p.role !== 'G');
  const byPuckDist = [...skaters].sort((a, b) => dist(a, puck) - dist(b, puck));
  // how long the ball has been free, so a stubborn loose ball draws help
  if (carrier) match.looseFor = 0;
  else if (team === 0) match.looseFor = (match.looseFor || 0) + dt;
  const looseFor = match.looseFor || 0;

  for (const p of players) {
    p.ai.timer -= dt;
    if (p.role === 'G') { goalieAI(match, p, dt); continue; }
    if (carrier === p) { p.ai.holdTime += dt; carrierAI(match, p, dt, T, skill); continue; }
    if (p.ai.timer > 0) continue;
    p.ai.timer = 0.12 + Math.random() * 0.1;

    const rank = byPuckDist.indexOf(p);
    let target;
    let chase = false;
    if (p.ai.expectPass > 0) p.ai.expectPass -= 0.2;
    if (possession === 'loose' && p.ai.expectPass > 0) {
      target = routeAroundNet(match, p, interceptPoint(match, p)); chase = true;
    } else if (possession === 'loose') {
      // One player goes for a loose ball. A second joins only when the first
      // is not getting there: the ball is far away, or it has been sitting
      // free for a while (e.g. stuck in an awkward spot behind the net).
      const nearest0 = byPuckDist[0] ? dist(byPuckDist[0], puck) : 99;
      const chasers = (T.pressing > 0.75 || nearest0 > 9 || looseFor > 1.5) ? 2 : 1;
      if (rank < chasers) { target = routeAroundNet(match, p, predictPuck(match, p)); chase = true; }
      else target = supportTarget(match, p, T);
    } else if (possession === 'their') {
      const pressers = T.pressing > 0.75 ? 2 : 1;
      const pressRange = 10 + T.pressing * 22;
      const dToCarrier = dist(p, carrier);
      if (rank < pressers && dToCarrier < pressRange) {
        // go for the carrier's body: the puck circles around it
        target = { x: carrier.x + carrier.vx * 0.2, z: carrier.z + carrier.vz * 0.2 };
      } else {
        target = defendTarget(match, p, T);
      }
    } else {
      target = supportTarget(match, p, T);
    }
    if (match.rules.offside && possession !== 'their') {
      const puckZone = dir * puck.z;
      if (puckZone < RINK.blueLineZ - 0.2 && dir * target.z > RINK.blueLineZ - 0.8 && carrier !== p) {
        target.z = dir * (RINK.blueLineZ - 0.8);
      }
    }
    if (!chase) {
      // never crowd the ball: that is the chaser's job, not everyone's
      keepClearOfBall(match, target, possession === 'their' ? 5.5 : CLEAR_OF_BALL);
      // keep a passing distance from every team-mate (including the carrier)
      const minGap = possession === 'own' ? 6 : 3.5;
      for (const q of players) {
        if (q === p || q.role === 'G') continue;
        const d = dist(q, target);
        if (d < minGap && d > 1e-3) {
          const n = norm(target.x - q.x, target.z - q.z);
          target.x += n.x * (minGap - d); target.z += n.z * (minGap - d);
        }
      }
      keepOutOfOwnCrease(match, p, target);
    }
    target.x = clamp(target.x, -HW + 1.2, HW - 1.2);
    target.z = clamp(target.z, -HL + 1.2, HL - 1.2);
    p.target = target;
  }
}

function keepOutOfOwnCrease(match, p, target) {
  const dir = match.dirOf(p.team);
  const gz = match.ownGoalZ(p.team);
  const minZ = -(RINK.goalLineZ - 2.2);
  if (dir * target.z < minZ) target.z = dir * minZ;
  const dx = target.x, dz = target.z - gz;
  const d = Math.hypot(dx, dz);
  const keep = RINK.creaseRadius + 1.2;
  if (d < keep) {
    const n = norm(dx === 0 && dz === 0 ? 1 : dx, dz);
    target.x = n.x * keep; target.z = gz + Math.abs(n.z) * keep * dir;
  }
}

/**
 * Players cannot walk through a net, and the AI has no pathfinder, so a chase
 * target behind a goal line gets a waypoint at the side of the net first.
 */
function routeAroundNet(match, p, target) {
  for (const t of [0, 1]) {
    const gz = match.ownGoalZ(t);
    const dir = match.dirOf(t);
    const behind = (z) => dir * (z - gz) < 0.4;      // at or past this goal line
    if (!behind(target.z)) continue;
    const hx = RINK.goalWidth / 2 + 1.6;
    // only a problem when the target sits behind the net mouth
    if (Math.abs(target.x) > hx) continue;
    if (!behind(p.x === target.x && p.z === target.z ? p.z : p.z) || dir * (p.z - gz) > 0.4) {
      // we are still in front of the line: aim for the corner of the net first
      const side = p.x >= 0 ? 1 : -1;
      return { x: side * hx, z: gz + dir * 0.6 };
    }
  }
  return target;
}

function interceptPoint(match, p) {
  const puck = match.puck;
  const sp = Math.hypot(puck.vx, puck.vz);
  if (sp < 2) return { x: puck.x, z: puck.z };
  const vx = puck.vx / sp, vz = puck.vz / sp;
  const t = Math.max(0, (p.x - puck.x) * vx + (p.z - puck.z) * vz);
  return { x: puck.x + vx * t, z: puck.z + vz * t };
}

function predictPuck(match, p) {
  const puck = match.puck;
  const d = dist(p, puck);
  const t = clamp(d / Math.max(p.maxSpeed, 1), 0, 1.2);
  return { x: puck.x + puck.vx * t * 0.7, z: puck.z + puck.vz * t * 0.7 };
}

function formationTarget(match, p, T, k) {
  const puck = match.puck;
  const dir = match.dirOf(p.team);
  const zK = (p.role === 'D' ? 0.35 : 0.55) * (0.6 + T.pushUp * 0.8) * k * 2;
  const xK = p.role === 'D' ? 0.3 : 0.4;
  let z = p.home.z + (puck.z - p.home.z) * clamp(zK, 0, 0.9);
  let x = p.home.x + (puck.x - p.home.x) * xK;
  if (p.role === 'D' && dir * z > dir * puck.z + 2 && dir * puck.z < 0) z = puck.z - dir * 2;
  return { x, z };
}

function defendTarget(match, p, T) {
  const dir = match.dirOf(p.team);
  const ownGoal = { x: 0, z: match.ownGoalZ(p.team) };
  const opps = match.skaters(1 - p.team).filter((o) => o !== match.puck.carrier);
  const taken = new Set(match.teamPlayers(p.team).filter((q) => q !== p && q.ai.mark).map((q) => q.ai.mark));
  let mark = null, best = Infinity;
  for (const o of opps) {
    if (taken.has(o)) continue;
    const danger = -dir * o.z;
    const d = dist(p, o) - danger * 0.6;
    if (d < best) { best = d; mark = o; }
  }
  const covering = T.covering;
  if (mark && Math.random() < 0.35 + covering * 0.6) {
    p.ai.mark = mark;
    const n = norm(ownGoal.x - mark.x, ownGoal.z - mark.z);
    const gap = 1.4 + (1 - covering) * 3;
    return { x: mark.x + n.x * gap, z: mark.z + n.z * gap };
  }
  p.ai.mark = null;
  const f = formationTarget(match, p, T, 0.35);
  if (dir * f.z > dir * match.puck.z - 1) f.z = match.puck.z - dir * 1.5;
  return f;
}

/**
 * Attacking shape: team-mates spread into support slots around the carrier
 * (wings ahead, a deep option, safety valves behind) so there is always a
 * clean passing lane and nobody crowds the puck.
 */
/**
 * Off-ball shape, expressed relative to the ball. Forwards look for the far
 * post and the width; defenders hold the back of the defence. `mirror` slots
 * are flipped to the side of the pitch away from the ball, so there is always
 * an option on the far side of the goal.
 */
const SLOTS = [
  { x: 10, z: 6, role: 'F', mirror: true },   // far post / far side, ahead
  { x: -9, z: 2, role: 'F', mirror: true },   // near side width, level
  { x: 2, z: 14, role: 'F' },                 // highest man, beyond the defence
  { x: -9, z: -8, role: 'D', mirror: true },  // wide outlet behind the ball
  { x: 9, z: -9, role: 'D', mirror: true },   // opposite outlet
  { x: 0, z: -15, role: 'D' },                // back of the defence
];

/** Non-chasers never stand on top of the ball. */
const CLEAR_OF_BALL = 7.5;

function keepClearOfBall(match, target, minDist = CLEAR_OF_BALL) {
  const b = match.puck;
  const dx = target.x - b.x, dz = target.z - b.z;
  const d = Math.hypot(dx, dz);
  if (d >= minDist) return target;
  const n = d > 1e-3 ? { x: dx / d, z: dz / d } : { x: 1, z: 0 };
  target.x = b.x + n.x * minDist;
  target.z = b.z + n.z * minDist;
  return target;
}

function supportTarget(match, p, T) {
  const dir = match.dirOf(p.team);
  const c = match.puck.carrier || match.puck;
  const mates = match.teamPlayers(p.team).filter((m) => m !== c && m.role !== 'G' && m.role !== 'O' && m.behavior === 'active');
  const gz = match.attackGoalZ(p.team);
  // world position of each slot, kept on the ice and out of the goal mouth
  // a slot marked `mirror` sits on the side of the pitch away from the ball
  const ballSide = c.x >= 0 ? 1 : -1;
  const world = SLOTS.map((sl) => {
    const sx = sl.mirror ? sl.x * -ballSide : sl.x;
    // width is measured from the middle of the pitch, not from the carrier, so
    // team-mates spread across the pitch instead of orbiting the ball
    let x = sl.mirror ? sx : c.x + sx;
    let z = c.z + dir * sl.z * (0.8 + T.pushUp * 0.4);
    x = clamp(x, -HW + 2.5, HW - 2.5);
    z = clamp(dir * z, -(RINK.goalLineZ - 3), RINK.goalLineZ - 5) * dir;
    if (Math.hypot(x, gz - z) < 7) { x = x >= 0 ? Math.max(x, 7) : Math.min(x, -7); }
    const slot = keepClearOfBall(match, { x, z });
    return { x: slot.x, z: slot.z, role: sl.role };
  });
  // greedy assignment: every team-mate takes the nearest matching free slot,
  // in a stable order so players don't swap slots every tick
  const order = [...mates].sort((a, b) => a.id - b.id);
  const taken = new Set();
  let mine = null;
  for (const m of order) {
    let best = -1, bd = Infinity;
    for (let i = 0; i < world.length; i++) {
      if (taken.has(i)) continue;
      const rolePenalty = world[i].role === (m.role === 'D' ? 'D' : 'F') ? 0 : 8;
      const d = dist(m, world[i]) + rolePenalty;
      if (d < bd) { bd = d; best = i; }
    }
    if (best >= 0) { taken.add(best); if (m === p) mine = world[best]; }
  }
  const f = mine ? { x: mine.x, z: mine.z } : formationTarget(match, p, T, 0.7);
  // get open: shift away from the nearest opponent (including obstacles)
  const opp = nearest(match.opponents(p.team), f);
  if (opp && dist(opp, f) < 3.4) {
    const n = norm(f.x - opp.x, f.z - opp.z);
    f.x += n.x * 3.5; f.z += n.z * 1.5;
  }
  return f;
}

function nearest(list, pt) {
  let b = null, bd = Infinity;
  for (const o of list) { const d = dist(o, pt); if (d < bd) { bd = d; b = o; } }
  return b;
}

/** Pick what an AI carrier wants to do with the puck. */
function chooseAction(match, p, T, skill, threatD) {
  const puck = match.puck;
  const dir = match.dirOf(p.team);
  const goal = { x: 0, z: match.attackGoalZ(p.team) };
  const opps = match.opponents(p.team);
  const dGoal = dist(p, goal);
  const forced = threatD < 2.6 || p.ai.holdTime > 3.5;
  const laneClear = shotLaneClear(match, p, goal);
  const shootRange = 11 + T.shooting * 11;
  const wantShot = dGoal < shootRange && (laneClear || dGoal < 6) && Math.abs(p.x) < 11;
  if (wantShot && (Math.random() < 0.35 + T.shooting * 0.5 || forced)) return { kind: 'shoot' };

  const mates = match.teamPlayers(p.team).filter((m) => m !== p && m.role !== 'G' && m.role !== 'O');
  let best = null, bestScore = -Infinity;
  for (const m of mates) {
    const d = dist(p, m);
    if (d < 3 || d > 26) continue;
    const progress = dir * (m.z - p.z);
    const oppNear = nearest(opps, m);
    const openness = oppNear ? clamp(dist(oppNear, m), 0, 6) : 6;
    const lane = passLaneBlocked(match, p, m) ? -6 : 0;
    const offside = match.rules.offside && dir * m.z > RINK.blueLineZ && dir * puck.z < RINK.blueLineZ ? -8 : 0;
    const ownGoal = { x: 0, z: match.ownGoalZ(p.team) };
    const danger = pointSegDist(ownGoal, p, m) < 5 ? -10 : 0;
    const backward = progress < -6 ? (progress + 6) * 0.3 : 0;
    const score = openness * 1.2 + progress * 0.35 + lane + offside + danger + backward - (d > 18 ? (d - 18) * 0.4 : 0) + noise(0.8);
    if (score > bestScore) { bestScore = score; best = m; }
  }
  const passUrge = T.passing * 0.3 + (threatD < 4 ? 0.45 : 0) + (p.ai.holdTime > 2 ? 0.3 : 0);
  if (best && bestScore > 3.5 && (Math.random() < passUrge || forced)) return { kind: 'pass', target: best };
  if (forced && best) return { kind: 'pass', target: best };
  if (forced && dGoal < 24) return { kind: 'shoot' };
  if (forced) return { kind: 'clear' };
  return null;
}

/** Movement for every carrier; release timing for AI carriers only. */
function carrierAI(match, p, dt, T, skill) {
  const puck = match.puck;
  const goal = { x: 0, z: match.attackGoalZ(p.team) };
  const opps = match.opponents(p.team);
  const threat = nearest(opps.filter((o) => o.role !== 'G' && o.canSteal), p);
  const threatD = threat ? dist(threat, p) : 99;
  const dGoal = dist(p, goal);

  if (!match.isUserCarrier(p)) {
    if (p.ai.timer <= 0 && p.ai.holdTime > 0.15) {
      p.ai.timer = 0.2 + Math.random() * 0.15;
      if (!p.ai.decision) p.ai.decision = chooseAction(match, p, T, skill, threatD);
    }
    const d = p.ai.decision;
    if (d) {
      const accuracy = 0.55 + skill * 0.5;
      let aim;
      if (d.kind === 'shoot') aim = Math.atan2(0 - p.x, goal.z - p.z);
      else if (d.kind === 'pass') {
        const dd = dist(p, d.target);
        const t = dd / clamp(11 + dd * 0.55, ORBIT.passSpeedMin, 24);
        aim = Math.atan2(d.target.x + d.target.vx * t * 0.8 - p.x, d.target.z + d.target.vz * t * 0.8 - p.z);
      } else aim = Math.atan2(0 - p.x, goal.z - p.z);
      const tol = 0.22 + (1 - skill) * 0.12 + (threatD < 2.2 ? 0.5 : 0);
      if (Math.abs(angleDiff(aim, puck.orbit)) < tol) {
        if (d.kind === 'shoot') match.shootAtGoal(p, { accuracy, power: 20 + skill * 6 + Math.random() * 2 });
        else if (d.kind === 'pass') match.passTo(p, d.target, { accuracy });
        else match.releaseAimed(p, { assist: false });
        p.ai.decision = null;
        return;
      }
    }
  }

  // skate with the puck: head for the goal, swerving around the nearest threat
  let dx = goal.x - p.x, dz = goal.z - p.z;
  const n = norm(dx, dz);
  let tx = p.x + n.x * 6, tz = p.z + n.z * 6;
  if (threat && threatD < 6) {
    const away = norm(p.x - threat.x, p.z - threat.z);
    const side = { x: -n.z, z: n.x };
    const s = (away.x * side.x + away.z * side.z) >= 0 ? 1 : -1;
    tx += side.x * s * 5 + away.x * 2; tz += side.z * s * 5 + away.z * 2;
  }
  // obstacles: steer around anything static in the way
  for (const o of opps) {
    if (o.behavior === 'active') continue;
    const d = dist(o, p);
    if (d < 4.5) { const a = norm(p.x - o.x, p.z - o.z); tx += a.x * (4.5 - d) * 1.5; tz += a.z * (4.5 - d) * 1.5; }
  }
  // hold a shooting distance: drift across the slot instead of running into the goalie
  if (dGoal < 8.5) {
    const side = p.x >= 0 ? 1 : -1;
    const drift = Math.abs(p.x) > 6 ? -side : side;
    tx = p.x + drift * 4; tz = p.z - n.z * (8.5 - dGoal) * 1.2;
  }
  const target = { x: tx, z: tz };
  keepOutOfOwnCrease(match, p, target);
  p.target = { x: clamp(target.x, -HW + 1.2, HW - 1.2), z: clamp(target.z, -HL + 1.2, HL - 1.2) };
}

function shotLaneClear(match, p, goal) {
  for (const o of match.opponents(p.team)) {
    if (o.role === 'G') continue;
    if (pointSegDist(o, p, goal) < 1.3 && dist(o, p) < dist(p, goal)) return false;
  }
  return true;
}

function passLaneBlocked(match, p, m) {
  for (const o of match.opponents(p.team)) {
    if (pointSegDist(o, p, m) < 1.4) return true;
  }
  return false;
}

function goalieAI(match, g, dt) {
  const puck = match.puck;
  const dir = match.dirOf(g.team);
  const gz = match.ownGoalZ(g.team);
  const skill = clamp((match.teams[g.team].rating - 60) / 30, 0, 1);

  if (puck.carrier === g) {
    g.ai.holdTime += dt;
    if (!g.ai.decision && g.ai.holdTime > 0.4) {
      const mates = match.skaters(g.team);
      let best = null, bs = -Infinity;
      for (const m of mates) {
        const o = nearest(match.opponents(g.team), m);
        const s = (o ? clamp(dist(o, m), 0, 8) : 8) - (passLaneBlocked(match, g, m) ? 5 : 0) + (m.role === 'D' ? 1 : 0) + noise(0.5);
        if (s > bs) { bs = s; best = m; }
      }
      g.ai.decision = { kind: best ? 'pass' : 'clear', target: best };
    }
    const d = g.ai.decision;
    if (d) {
      const aim = d.target ? Math.atan2(d.target.x - g.x, d.target.z - g.z) : (dir > 0 ? 0 : Math.PI);
      if (Math.abs(angleDiff(aim, puck.orbit)) < 0.35 || g.ai.holdTime > 2.5) {
        if (d.target) match.passTo(g, d.target, { accuracy: 0.9 }); else match.releaseAimed(g, { assist: false });
        g.ai.decision = null; g.ai.holdTime = 0;
      }
    }
    g.target = { x: g.x, z: g.z };
    return;
  }

  let aimX = puck.x;
  const reacted = match.time - puck.shotTime > PLAYER.goalieReaction + (1 - skill) * 0.2;
  const towards = dir * puck.vz < -4 && reacted;
  if (towards) {
    const t = (gz - puck.z) / puck.vz;
    if (t > 0 && t < 2.5) aimX = puck.x + puck.vx * t * (0.75 + skill * 0.25);
  }
  const toPuck = norm(puck.x - 0, puck.z - gz);
  const out = 1.2 + skill * 0.5;
  let x = toPuck.x * out * 1.6, z = gz + toPuck.z * out;
  if (towards) x = aimX * 0.9;
  x = clamp(x, -RINK.goalWidth / 2 - 0.4, RINK.goalWidth / 2 + 0.4);
  z = clamp(dir * (z - gz), 0.6, 2.4) * dir + gz;
  const dp = dist(g, puck);
  const psp = Math.hypot(puck.vx, puck.vz);
  if (!puck.carrier && dp < 3.5 && psp < 7 && Math.abs(puck.x) < 6 && dir * (puck.z - gz) < 5) { x = puck.x; z = puck.z; }
  g.target = { x, z };
}
