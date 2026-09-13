import { RINK, PLAYER } from './config.js';
import { clamp, dist, norm, pointSegDist, rand, noise } from './math.js';

const HW = RINK.width / 2;
const HL = RINK.length / 2;

/**
 * Drives every player of `team` that is not controlled by the user.
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
  const players = match.teamPlayers(team);
  const carrier = puck.carrier;
  const possession = carrier ? (carrier.team === team ? 'own' : 'their') : 'loose';
  const rating = match.teams[team].rating;
  const skill = clamp((rating - 60) / 30, 0, 1); // 0..1 across the league

  // Which of our skaters are nearest to the puck (for chasing / pressing)?
  const skaters = players.filter((p) => p.role !== 'G');
  const byPuckDist = [...skaters].sort((a, b) => dist(a, puck) - dist(b, puck));

  for (const p of players) {
    if (p.controlled != null) continue;
    p.ai.timer -= dt;
    if (p.role === 'G') { goalieAI(match, p, dt); continue; }
    if (carrier === p) { p.ai.holdTime += dt; carrierAI(match, p, dt, T, skill); continue; }
    if (p.ai.timer > 0) continue;               // re-decide a few times a second
    p.ai.timer = 0.12 + Math.random() * 0.1;

    const rank = byPuckDist.indexOf(p);          // 0 = closest to the puck
    let target;
    if (p.ai.expectPass > 0) p.ai.expectPass -= 0.2;
    if (possession === 'loose' && p.ai.expectPass > 0) {
      target = interceptPoint(match, p);
    } else if (possession === 'loose') {
      const chasers = 1 + (T.pressing > 0.5 ? 1 : 0);
      if (rank < chasers) target = predictPuck(match, p);
      else target = formationTarget(match, p, T, 0.5);
    } else if (possession === 'their') {
      const pressers = 1 + Math.round(T.pressing * 1.6);
      const pressRange = 10 + T.pressing * 22;
      const dToCarrier = dist(p, carrier);
      if (rank < pressers && dToCarrier < pressRange) {
        // go for the puck itself (it sits in front of the carrier), with a little lead
        const cp = match.carryPoint(carrier);
        target = { x: cp.x + carrier.vx * 0.15, z: cp.z + carrier.vz * 0.15 };
      } else {
        target = defendTarget(match, p, T);
      }
    } else {
      target = supportTarget(match, p, T);
    }
    // Offside discipline: don't cross the blue line before the puck.
    if (possession !== 'their') {
      const puckZone = dir * puck.z;
      if (puckZone < RINK.blueLineZ - 0.2 && dir * target.z > RINK.blueLineZ - 0.8 && carrier !== p) {
        target.z = dir * (RINK.blueLineZ - 0.8);
      }
    }
    // spacing from team-mates
    for (const q of skaters) {
      if (q === p) continue;
      const d = dist(q, target);
      if (d < 3 && d > 1e-3) {
        const n = norm(target.x - q.x, target.z - q.z);
        target.x += n.x * (3 - d); target.z += n.z * (3 - d);
      }
    }
    keepOutOfOwnCrease(match, p, target);
    target.x = clamp(target.x, -HW + 1.2, HW - 1.2);
    target.z = clamp(target.z, -HL + 1.2, HL - 1.2);
    p.target = target;
  }
}

/** Skaters stay out of their own crease and in front of their own goal line. */
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

/** Move to the point on the puck's path that is closest to us. */
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

/** Home position shifted towards the puck depending on pushUp and role. */
function formationTarget(match, p, T, k) {
  const puck = match.puck;
  const dir = match.dirOf(p.team);
  const zK = (p.role === 'D' ? 0.35 : 0.55) * (0.6 + T.pushUp * 0.8) * k * 2;
  const xK = p.role === 'D' ? 0.3 : 0.4;
  let z = p.home.z + (puck.z - p.home.z) * clamp(zK, 0, 0.9);
  let x = p.home.x + (puck.x - p.home.x) * xK;
  // defenders never wander in front of the puck when it is deep in our zone
  if (p.role === 'D' && dir * z > dir * puck.z + 2 && dir * puck.z < 0) z = puck.z - dir * 2;
  return { x, z };
}

/** Defensive shape: cover an opponent or hold a formation position. */
function defendTarget(match, p, T) {
  const dir = match.dirOf(p.team);
  const ownGoal = { x: 0, z: match.ownGoalZ(p.team) };
  const opps = match.skaters(1 - p.team).filter((o) => o !== match.puck.carrier);
  // choose a mark: nearest unmarked opponent on our half or near the puck
  const taken = new Set(match.teamPlayers(p.team).filter((q) => q !== p && q.ai.mark).map((q) => q.ai.mark));
  let mark = null, best = Infinity;
  for (const o of opps) {
    if (taken.has(o)) continue;
    const danger = -dir * o.z; // more positive = deeper in our zone
    const d = dist(p, o) - danger * 0.6;
    if (d < best) { best = d; mark = o; }
  }
  const covering = T.covering;
  if (mark && Math.random() < 0.35 + covering * 0.6) {
    p.ai.mark = mark;
    // stand between the opponent and our goal, tighter with more covering
    const n = norm(ownGoal.x - mark.x, ownGoal.z - mark.z);
    const gap = 1.4 + (1 - covering) * 3;
    return { x: mark.x + n.x * gap, z: mark.z + n.z * gap };
  }
  p.ai.mark = null;
  const f = formationTarget(match, p, T, 0.35);
  // stay goal-side of the puck when defending
  if (dir * f.z > dir * match.puck.z - 1) f.z = match.puck.z - dir * 1.5;
  return f;
}

/** Attacking shape: get open in a useful position. */
function supportTarget(match, p, T) {
  const dir = match.dirOf(p.team);
  const puck = match.puck;
  const f = formationTarget(match, p, T, 0.7);
  // forwards look for space ahead of the puck, defenders trail behind it
  if (p.role === 'F') {
    f.z = Math.max(dir * f.z, dir * puck.z + 3) * dir;
    f.z = clamp(dir * f.z, -HL + 3, RINK.goalLineZ - 4) * dir;
  } else {
    f.z = Math.min(dir * f.z, dir * puck.z - 4) * dir;
  }
  // escape a marker: shift sideways away from the nearest opponent
  const opp = nearest(match.opponents(p.team), f);
  if (opp && dist(opp, f) < 3.2) {
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

/** Decisions for the AI player holding the puck. */
function carrierAI(match, p, dt, T, skill) {
  const puck = match.puck;
  const dir = match.dirOf(p.team);
  const goal = { x: 0, z: match.attackGoalZ(p.team) };
  const opps = match.opponents(p.team);
  const threat = nearest(opps.filter((o) => o.role !== 'G'), puck);
  const threatD = threat ? dist(threat, puck) : 99;
  const dGoal = dist(p, goal);
  const userTeam = p.team === match.userTeam;
  // give the human a moment to grab an AI team-mate before it acts on its own
  const holdMin = userTeam ? 0.6 : 0.15;
  const canAct = p.ai.holdTime > holdMin || threatD < 2.2;

  if (p.ai.timer <= 0 && canAct) {
    p.ai.timer = 0.15 + Math.random() * 0.15;
    const accuracy = 0.55 + skill * 0.5;
    // 1. shoot?
    const laneClear = shotLaneClear(match, p, goal);
    const shootRange = 11 + T.shooting * 11;
    const wantShot = dGoal < shootRange && (laneClear || dGoal < 6) && Math.abs(p.x) < 11;
    const forced = threatD < 2.2 || p.ai.holdTime > 3.5;
    if (wantShot && (Math.random() < 0.35 + T.shooting * 0.5 || forced)) {
      match.shootAtGoal(p, { accuracy, power: 20 + skill * 6 + Math.random() * 2 });
      return;
    }
    // 2. pass?
    const mates = match.teamPlayers(p.team).filter((m) => m !== p && m.role !== 'G');
    let best = null, bestScore = -Infinity;
    for (const m of mates) {
      const d = dist(p, m);
      if (d < 3 || d > 26) continue;
      const progress = dir * (m.z - p.z);
      const oppNear = nearest(opps, m);
      const openness = oppNear ? clamp(dist(oppNear, m), 0, 6) : 6;
      const lane = passLaneBlocked(match, p, m) ? -6 : 0;
      const offside = dir * m.z > RINK.blueLineZ && dir * puck.z < RINK.blueLineZ ? -8 : 0;
      const ownGoal = { x: 0, z: match.ownGoalZ(p.team) };
      const danger = pointSegDist(ownGoal, p, m) < 5 ? -10 : 0;
      const backward = progress < -6 ? (progress + 6) * 0.3 : 0;
      const score = openness * 1.2 + progress * 0.35 + lane + offside + danger + backward - (d > 18 ? (d - 18) * 0.4 : 0) + noise(0.8);
      if (score > bestScore) { bestScore = score; best = m; }
    }
    const passUrge = T.passing * 0.3 + (threatD < 4 ? 0.45 : 0) + (p.ai.holdTime > 2 ? 0.3 : 0);
    if (best && bestScore > 3.5 && (Math.random() < passUrge || forced)) {
      match.passTo(p, best, { accuracy });
      return;
    }
    if (forced && best) { match.passTo(p, best, { accuracy }); return; }
    if (forced && dGoal < 22) { match.shootAtGoal(p, { accuracy: accuracy * 0.8, power: 22 }); return; }
  }

  // 3. skate with the puck: head for the goal, swerving around the nearest threat
  let dx = goal.x - p.x, dz = goal.z - p.z;
  const n = norm(dx, dz);
  let tx = p.x + n.x * 6, tz = p.z + n.z * 6;
  if (threat && threatD < 6) {
    const away = norm(puck.x - threat.x, puck.z - threat.z);
    // pick the side that still goes forward
    const side = { x: -n.z, z: n.x };
    const s = (away.x * side.x + away.z * side.z) >= 0 ? 1 : -1;
    tx += side.x * s * 5 + away.x * 2; tz += side.z * s * 5 + away.z * 2;
  }
  // don't skate into the goalie / the goal crease
  if (dGoal < 5) { tx = p.x + (p.x >= 0 ? 4 : -4); tz = p.z; }
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

/** Goalie: stay on the arc between the goal centre and the puck, react to shots. */
function goalieAI(match, g, dt) {
  const puck = match.puck;
  const dir = match.dirOf(g.team);
  const gz = match.ownGoalZ(g.team);
  const skill = clamp((match.teams[g.team].rating - 60) / 30, 0, 1);

  if (puck.carrier === g) {
    g.ai.holdTime += dt;
    if (g.ai.holdTime > 0.7) {
      // clear to the most open team-mate, preferring defenders
      const mates = match.skaters(g.team);
      let best = null, bs = -Infinity;
      for (const m of mates) {
        const o = nearest(match.opponents(g.team), m);
        const s = (o ? clamp(dist(o, m), 0, 8) : 8) - (passLaneBlocked(match, g, m) ? 5 : 0) + (m.role === 'D' ? 1 : 0) + noise(0.5);
        if (s > bs) { bs = s; best = m; }
      }
      if (best) match.passTo(g, best, { accuracy: 0.9 });
      g.ai.holdTime = 0;
    }
    g.target = { x: g.x, z: g.z };
    return;
  }

  // Predict where the puck would cross the goal line if it is moving at us
  let aimX = puck.x;
  const towards = dir * puck.vz < -4;
  if (towards) {
    const t = (gz - puck.z) / puck.vz;
    if (t > 0 && t < 2.5) aimX = puck.x + puck.vx * t * (0.75 + skill * 0.25);
  }
  // arc positioning
  const toPuck = norm(puck.x - 0, puck.z - gz);
  const out = 1.2 + skill * 0.5;
  let x = toPuck.x * out * 1.6, z = gz + toPuck.z * out;
  if (towards) x = aimX * 0.9;
  x = clamp(x, -RINK.goalWidth / 2 - 0.4, RINK.goalWidth / 2 + 0.4);
  z = clamp(dir * (z - gz), 0.6, 2.4) * dir + gz;
  // come out to grab a slow loose puck nearby
  const dp = dist(g, puck);
  const psp = Math.hypot(puck.vx, puck.vz);
  if (!puck.carrier && dp < 3.5 && psp < 7 && Math.abs(puck.x) < 6 && dir * (puck.z - gz) < 5) {
    x = puck.x; z = puck.z;
  }
  g.target = { x, z };
}
