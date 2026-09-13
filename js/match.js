import { RINK, PLAYER, PUCK, RULES, FACEOFF_SPOTS } from './config.js';
import { clamp, dist, norm, sdRoundRect, roundRectNormal, rand, noise } from './math.js';
import { updateTeamAI } from './ai.js';

const HW = RINK.width / 2;
const HL = RINK.length / 2;

// Formation home positions for a team attacking +Z. Mirrored for team 1.
const FORMATION = [
  { role: 'G', x: 0, z: -25 },
  { role: 'D', x: -6.5, z: -17 },
  { role: 'D', x: 6.5, z: -17 },
  { role: 'F', x: -9, z: -5 },
  { role: 'F', x: 0, z: -3 },
  { role: 'F', x: 9, z: -5 },
];

let nextPlayerId = 1;

export class Match {
  /**
   * @param {object} opts { home, away, tactics:[t0,t1], periodSeconds, overtime, onEvent }
   */
  constructor(opts) {
    this.teams = [opts.home, opts.away];
    this.tactics = [opts.tactics?.[0] ?? opts.home.tactics, opts.tactics?.[1] ?? opts.away.tactics];
    this.periodSeconds = opts.periodSeconds ?? RULES.periodSeconds;
    this.overtime = !!opts.overtime; // sudden death if tied after regulation
    this.onEvent = opts.onEvent || (() => {});
    this.userTeam = 0;

    this.players = [];
    for (let t = 0; t < 2; t++) {
      const dir = t === 0 ? 1 : -1;
      FORMATION.forEach((f, i) => {
        const rating = this.teams[t].rating;
        const p = {
          id: nextPlayerId++, team: t, role: f.role, idx: i,
          home: { x: f.x * (t === 0 ? 1 : -1), z: f.z * dir },
          x: 0, z: 0, vx: 0, vz: 0,
          r: f.role === 'G' ? PLAYER.goalieRadius : PLAYER.radius,
          facing: dir > 0 ? 0 : Math.PI, // angle in XZ plane; 0 => +Z
          maxSpeed: f.role === 'G' ? PLAYER.goalieSpeed : PLAYER.aiSpeedBase + (rating - 60) * 0.045,
          controlled: null,         // pointer id when the user drags this player
          target: null,             // where the player wants to be
          pickupCooldown: 0,        // can't pick up the puck while > 0
          ai: { timer: Math.random() * 0.2, holdTime: 0, decision: null, mark: null },
        };
        this.players.push(p);
      });
    }
    this.puck = { x: 0, z: 0, vx: 0, vz: 0, r: PUCK.radius, carrier: null,
      lastTouch: null, lastTouchTeam: -1, lastShooter: null, releaseZ: 0, releaseTeam: -1, untouched: false,
      trail: [] };

    this.score = [0, 0];
    this.period = 1;
    this.clock = this.periodSeconds;
    this.state = 'faceoff';
    this.stateTimer = 0;
    this.inZone = [false, false];
    this.message = '';
    this.events = [];
    this.stats = { shots: [0, 0], passes: [0, 0], steals: [0, 0] };
    this.time = 0;
    this.ended = false;
    this.isOvertime = false;
    this.pendingFaceoff = FACEOFF_SPOTS.center;
    this.pendingText = 'FACE-OFF';

    this.setupFaceoff(FACEOFF_SPOTS.center, 'PERIOD 1');
  }

  // ---------------------------------------------------------------- helpers
  dirOf(team) { return team === 0 ? 1 : -1; }
  ownGoalZ(team) { return -this.dirOf(team) * RINK.goalLineZ; }
  attackGoalZ(team) { return this.dirOf(team) * RINK.goalLineZ; }
  skaters(team) { return this.players.filter((p) => p.team === team && p.role !== 'G'); }
  goalie(team) { return this.players.find((p) => p.team === team && p.role === 'G'); }
  teamPlayers(team) { return this.players.filter((p) => p.team === team); }
  opponents(team) { return this.players.filter((p) => p.team !== team); }
  carrierTeam() { return this.puck.carrier ? this.puck.carrier.team : -1; }

  emit(type, data = {}) {
    const e = { type, time: this.time, ...data };
    this.events.push(e);
    this.onEvent(e);
  }

  // Where the puck sits when a player carries it.
  carryPoint(p) {
    return { x: p.x + Math.sin(p.facing) * PLAYER.carryOffset, z: p.z + Math.cos(p.facing) * PLAYER.carryOffset };
  }

  // ---------------------------------------------------------------- faceoffs
  setupFaceoff(spot, text) {
    this.state = 'faceoff';
    this.stateTimer = RULES.faceoffDelay;
    this.message = text || 'FACE-OFF';
    const puck = this.puck;
    puck.carrier = null;
    puck.x = spot.x; puck.z = spot.z; puck.vx = 0; puck.vz = 0;
    puck.lastTouch = null; puck.lastTouchTeam = -1; puck.untouched = false; puck.trail.length = 0;
    this.inZone = [false, false];
    for (const p of this.players) {
      p.vx = p.vz = 0; p.target = null; p.controlled = null; p.pickupCooldown = 0;
      p.ai.holdTime = 0; p.ai.decision = null; p.ai.mark = null;
      const dir = this.dirOf(p.team);
      const side = p.team === 0 ? 1 : -1;
      let x, z;
      switch (p.idx) {
        case 0: x = 0; z = this.ownGoalZ(p.team) + dir * 1.3; break;               // goalie
        case 1: x = spot.x - 4.5 * side; z = spot.z - dir * 8; break;               // D
        case 2: x = spot.x + 4.5 * side; z = spot.z - dir * 8; break;               // D
        case 3: x = spot.x - 5.5 * side; z = spot.z - dir * 1.4; break;             // LW
        case 4: x = spot.x; z = spot.z - dir * 1.5; break;                          // C
        case 5: x = spot.x + 5.5 * side; z = spot.z - dir * 1.4; break;             // RW
      }
      // keep everyone on their own side of the spot and inside the rink
      p.x = clamp(x, -HW + 2, HW - 2);
      p.z = clamp(z, -HL + 2, HL - 2);
      if (p.role !== 'G' && Math.abs(p.z - this.ownGoalZ(p.team)) < 3) p.z = this.ownGoalZ(p.team) + dir * 3;
      p.facing = dir > 0 ? 0 : Math.PI;
    }
    this.emit('faceoff', { spot, text: this.message });
  }

  nearestFaceoffSpot(list, x, z) {
    let best = list[0], bd = Infinity;
    for (const s of list) { const d = Math.hypot(s.x - x, s.z - z); if (d < bd) { bd = d; best = s; } }
    return best;
  }

  whistle(text, spot) {
    if (this.state !== 'play') return;
    this.state = 'whistle';
    this.stateTimer = RULES.whistleDelay;
    this.message = text;
    this.pendingFaceoff = spot;
    this.pendingText = 'FACE-OFF';
    this.puck.carrier = null;
    this.puck.vx *= 0.2; this.puck.vz *= 0.2;
    for (const p of this.players) { p.controlled = null; p.target = null; }
    this.emit('whistle', { text });
  }

  // ---------------------------------------------------------------- actions
  /** Give the puck to a player. */
  possess(p) {
    const puck = this.puck;
    if (puck.carrier === p) return;
    const prev = puck.carrier;
    if (prev && prev.team !== p.team) { this.stats.steals[p.team]++; prev.pickupCooldown = 0.6; this.emit('steal', { by: p, from: prev }); }
    if (puck.lastTouchTeam !== -1 && puck.lastTouchTeam !== p.team && !prev) this.emit('intercept', { by: p });
    puck.carrier = p;
    puck.vx = puck.vz = 0;
    puck.lastTouch = p; puck.lastTouchTeam = p.team; puck.untouched = false;
    p.ai.holdTime = 0;
    p.ai.decision = null;
  }

  /** Shoot/pass the puck from its carrier in direction (dx,dz) with a speed. */
  release(p, dx, dz, speed, kind = 'shot') {
    const puck = this.puck;
    if (puck.carrier !== p) return false;
    const n = norm(dx, dz);
    if (n.x === 0 && n.z === 0) return false;
    const cp = this.carryPoint(p);
    // never start the puck behind a goal line (inside a net); use the body position instead
    if (Math.abs(cp.z) > RINK.goalLineZ - 0.3 && Math.abs(cp.x) < RINK.goalWidth / 2 + 0.6) {
      cp.x = p.x; cp.z = clamp(p.z, -(RINK.goalLineZ - 0.5), RINK.goalLineZ - 0.5);
    }
    puck.carrier = null;
    puck.x = cp.x; puck.z = cp.z;
    puck.lastShooter = p;
    puck.vx = n.x * speed + p.vx * 0.25;
    puck.vz = n.z * speed + p.vz * 0.25;
    puck.lastTouch = p; puck.lastTouchTeam = p.team;
    puck.releaseZ = puck.z; puck.releaseTeam = p.team; puck.untouched = true;
    p.pickupCooldown = 0.45;
    p.facing = Math.atan2(n.x, n.z);
    if (kind === 'shot') this.stats.shots[p.team]++; else this.stats.passes[p.team]++;
    this.emit(kind, { by: p, speed });
    return true;
  }

  /** Pass with lead so the puck arrives where the receiver will be. */
  passTo(p, receiver, opts = {}) {
    const acc = opts.accuracy ?? 1;
    const dx0 = receiver.x - p.x, dz0 = receiver.z - p.z;
    const d = Math.hypot(dx0, dz0);
    const speed = clamp(11 + d * 0.55, 12, 24);
    const t = d / speed;
    let tx = receiver.x + receiver.vx * t * 0.8;
    let tz = receiver.z + receiver.vz * t * 0.8;
    tx += noise(1.6 * (1.15 - acc)); tz += noise(1.6 * (1.15 - acc));
    const ok = this.release(p, tx - p.x, tz - p.z, speed, 'pass');
    if (ok) { receiver.ai.expectPass = 1.6; receiver.ai.timer = 0; }
    return ok;
  }

  /** Shoot at the opponent's goal, aiming away from the goalie. */
  shootAtGoal(p, opts = {}) {
    const acc = opts.accuracy ?? 1;
    const power = opts.power ?? 24;
    const gz = this.attackGoalZ(p.team);
    const goalie = this.goalie(1 - p.team);
    const half = RINK.goalWidth / 2 - 0.45;
    let aimX = goalie ? (goalie.x > 0 ? -half : half) : (Math.random() < 0.5 ? -half : half);
    if (Math.random() < 0.25) aimX *= 0.3;
    aimX += noise(1.5 * (1.2 - acc));
    return this.release(p, aimX - p.x, gz - p.z, power, 'shot');
  }

  // ---------------------------------------------------------------- update
  update(dt) {
    if (this.ended) return;
    this.time += dt;
    // sub-step physics for stability
    const steps = 2;
    const h = dt / steps;
    for (let i = 0; i < steps; i++) this.step(h);
  }

  step(dt) {
    const puck = this.puck;
    switch (this.state) {
      case 'faceoff':
        this.stateTimer -= dt;
        if (this.stateTimer <= 0) {
          this.state = 'play';
          this.message = '';
          const a = rand(0, Math.PI * 2);
          puck.vx = Math.cos(a) * 3; puck.vz = Math.sin(a) * 3;
          this.emit('drop');
        }
        break;
      case 'whistle':
        this.stateTimer -= dt;
        if (this.stateTimer <= 0) this.setupFaceoff(this.pendingFaceoff, this.pendingText);
        break;
      case 'goal':
        this.stateTimer -= dt;
        if (this.stateTimer <= 0) {
          if (this.isOvertime) { this.finish(); break; }
          this.setupFaceoff(FACEOFF_SPOTS.center, 'FACE-OFF');
        }
        break;
      case 'periodEnd':
        this.stateTimer -= dt;
        if (this.stateTimer <= 0) this.nextPeriod();
        break;
      case 'ended':
        return;
    }
    const live = this.state === 'play';
    if (live) {
      this.clock -= dt;
      if (this.clock <= 0) { this.clock = 0; this.endPeriod(); }
    }

    // AI decisions for both teams (also for the user's uncontrolled players)
    if (live) { updateTeamAI(this, 0, dt); updateTeamAI(this, 1, dt); }

    // Player motion
    for (const p of this.players) this.movePlayer(p, dt, live);
    this.collidePlayers();
    for (const p of this.players) this.constrainPlayer(p);

    // Puck
    if (live) this.updatePuck(dt);
    else if (puck.carrier) { const cp = this.carryPoint(puck.carrier); puck.x = cp.x; puck.z = cp.z; }

    if (live) this.checkRules();
  }

  movePlayer(p, dt, live) {
    if (p.pickupCooldown > 0) p.pickupCooldown -= dt;
    let dvx = 0, dvz = 0;
    if (live && p.target) {
      const dx = p.target.x - p.x, dz = p.target.z - p.z;
      const d = Math.hypot(dx, dz);
      const speed = p.controlled != null ? PLAYER.humanSpeed : p.maxSpeed;
      // arrive: slow down near the target
      const want = Math.min(speed, d * (p.controlled != null ? 14 : 6));
      if (d > 0.02) { dvx = (dx / d) * want; dvz = (dz / d) * want; }
    }
    const k = 1 - Math.exp(-PLAYER.accel / 8 * dt);
    p.vx += (dvx - p.vx) * k;
    p.vz += (dvz - p.vz) * k;
    if (!live) { p.vx *= 0.8; p.vz *= 0.8; }
    p.x += p.vx * dt;
    p.z += p.vz * dt;
    const sp = Math.hypot(p.vx, p.vz);
    if (p.role === 'G') { p.facing = this.dirOf(p.team) > 0 ? 0 : Math.PI; return; }
    if (sp > 0.6) {
      const want = Math.atan2(p.vx, p.vz);
      let d = want - p.facing;
      while (d > Math.PI) d -= Math.PI * 2;
      while (d < -Math.PI) d += Math.PI * 2;
      p.facing += d * Math.min(1, dt * 14);
    }
  }

  collidePlayers() {
    const ps = this.players;
    for (let i = 0; i < ps.length; i++) {
      for (let j = i + 1; j < ps.length; j++) {
        const a = ps[i], b = ps[j];
        const dx = b.x - a.x, dz = b.z - a.z;
        const d = Math.hypot(dx, dz);
        const min = a.r + b.r;
        if (d < min && d > 1e-4) {
          const push = (min - d) / 2;
          const nx = dx / d, nz = dz / d;
          a.x -= nx * push; a.z -= nz * push;
          b.x += nx * push; b.z += nz * push;
          // bump velocities apart a little
          const rel = (b.vx - a.vx) * nx + (b.vz - a.vz) * nz;
          if (rel < 0) {
            a.vx += nx * rel * 0.5; a.vz += nz * rel * 0.5;
            b.vx -= nx * rel * 0.5; b.vz -= nz * rel * 0.5;
          }
        }
      }
    }
  }

  constrainPlayer(p) {
    // boards
    const sd = sdRoundRect(p.x, p.z, HW, HL, RINK.corner);
    if (sd > -p.r) {
      const n = roundRectNormal(p.x, p.z, HW, HL, RINK.corner);
      const pen = sd + p.r;
      p.x -= n.x * pen; p.z -= n.z * pen;
      const vn = p.vx * n.x + p.vz * n.z;
      if (vn > 0) { p.vx -= n.x * vn; p.vz -= n.z * vn; }
    }
    // keep skaters out of both nets (goalies included)
    for (const t of [0, 1]) {
      const gz = this.ownGoalZ(t);
      const dir = this.dirOf(t); // net extends from gz towards -dir
      const zMin = Math.min(gz, gz - dir * RINK.goalDepth) - p.r;
      const zMax = Math.max(gz, gz - dir * RINK.goalDepth) + p.r;
      const hx = RINK.goalWidth / 2 + p.r;
      if (Math.abs(p.x) < hx && p.z > zMin && p.z < zMax) {
        // push out along the axis of least penetration
        const px = hx - Math.abs(p.x);
        const pzFront = dir > 0 ? (zMax - p.z) : (p.z - zMin);
        if (px < pzFront) p.x += (p.x >= 0 ? 1 : -1) * px;
        else p.z += dir * pzFront;
      }
    }
  }

  updatePuck(dt) {
    const puck = this.puck;
    if (puck.carrier) {
      const c = puck.carrier;
      const cp = this.carryPoint(c);
      if (Math.abs(cp.z) > RINK.goalLineZ - 0.4 && Math.abs(cp.x) < RINK.goalWidth / 2 + 0.6) {
        const lim = RINK.goalLineZ - 0.4 - PLAYER.carryOffset;
        c.z = clamp(c.z, -lim, lim);
        const cp2 = this.carryPoint(c); cp.x = cp2.x; cp.z = cp2.z;
      }
      puck.x = cp.x; puck.z = cp.z; puck.vx = c.vx; puck.vz = c.vz;
      if (c.role !== 'G') this.checkSteal(c);
      return;
    }
    // free puck physics
    const sp = Math.hypot(puck.vx, puck.vz);
    if (sp > 0) {
      const dec = Math.min(sp, PUCK.friction * dt + sp * PUCK.drag * dt);
      const f = (sp - dec) / sp;
      puck.vx *= f; puck.vz *= f;
      if (sp > PUCK.maxSpeed) { puck.vx *= PUCK.maxSpeed / sp; puck.vz *= PUCK.maxSpeed / sp; }
    }
    const prevX = puck.x, prevZ = puck.z;
    puck.x += puck.vx * dt;
    puck.z += puck.vz * dt;

    // Nets: a puck crossing the goal line between the posts from the front is a
    // goal; from any other side the net frame is a solid box.
    for (const t of [0, 1]) {
      const gz = this.ownGoalZ(t); // goal defended by team t
      const dir = this.dirOf(t);
      const hw = RINK.goalWidth / 2 + 0.15;
      const zFront = gz, zBack = gz - dir * (RINK.goalDepth + 0.15);
      const zMin = Math.min(zFront, zBack) - puck.r, zMax = Math.max(zFront, zBack) + puck.r;
      if (Math.abs(puck.x) < hw + puck.r && puck.z > zMin && puck.z < zMax) {
        const wasInFront = dir * (prevZ - gz) >= -puck.r * 0.5;
        const crossedLine = dir * (puck.z - gz) < -puck.r * 0.5;
        if (wasInFront && Math.abs(prevX) < RINK.goalWidth / 2 - puck.r * 0.3) {
          if (crossedLine) { this.goalScored(1 - t); return; }
          continue; // still in front of the line, nothing to do
        }
        if (wasInFront) continue; // heading at a post; the post circles handle it
        // came from behind or the side: push out of the box and bounce
        const pushSide = hw + puck.r - Math.abs(puck.x);
        const pushBack = dir > 0 ? (puck.z - zMin) : (zMax - puck.z);
        if (pushSide < pushBack) {
          puck.x += (puck.x >= 0 ? 1 : -1) * pushSide;
          puck.vx = -puck.vx * PUCK.boardRestitution;
        } else {
          puck.z += dir > 0 ? -pushBack : pushBack;
          puck.vz = -puck.vz * PUCK.boardRestitution;
        }
      }
    }
    // posts
    for (const t of [0, 1]) {
      const gz = this.ownGoalZ(t);
      for (const sx of [-1, 1]) {
        const px = sx * RINK.goalWidth / 2, pz = gz;
        const dx = puck.x - px, dz = puck.z - pz;
        const d = Math.hypot(dx, dz);
        const min = puck.r + 0.18;
        if (d < min && d > 1e-4) {
          const nx = dx / d, nz = dz / d;
          puck.x = px + nx * min; puck.z = pz + nz * min;
          const vn = puck.vx * nx + puck.vz * nz;
          if (vn < 0) { puck.vx -= (1 + 0.8) * vn * nx; puck.vz -= (1 + 0.8) * vn * nz; }
          this.emit('post');
        }
      }
    }
    // boards
    const sd = sdRoundRect(puck.x, puck.z, HW, HL, RINK.corner);
    if (sd > -puck.r) {
      const n = roundRectNormal(puck.x, puck.z, HW, HL, RINK.corner);
      const pen = sd + puck.r;
      puck.x -= n.x * pen; puck.z -= n.z * pen;
      const vn = puck.vx * n.x + puck.vz * n.z;
      if (vn > 0) {
        puck.vx -= (1 + PUCK.boardRestitution) * vn * n.x;
        puck.vz -= (1 + PUCK.boardRestitution) * vn * n.z;
        if (vn > 4) this.emit('board', { speed: vn });
      }
    }
    // players: pickup or bounce
    let best = null, bestD = Infinity;
    for (const p of this.players) {
      const dx = puck.x - p.x, dz = puck.z - p.z;
      const d = Math.hypot(dx, dz);
      const reach = p.role === 'G' ? p.r + puck.r + 0.35 : PLAYER.reach;
      if (d < reach && p.pickupCooldown <= 0 && d < bestD) { best = p; bestD = d; }
      // physical bounce off the body
      const min = p.r + puck.r;
      if (d < min && d > 1e-4) {
        const nx = dx / d, nz = dz / d;
        puck.x = p.x + nx * min; puck.z = p.z + nz * min;
        const rvx = puck.vx - p.vx, rvz = puck.vz - p.vz;
        const vn = rvx * nx + rvz * nz;
        if (vn < 0) {
          puck.vx -= (1 + PUCK.playerRestitution) * vn * nx;
          puck.vz -= (1 + PUCK.playerRestitution) * vn * nz;
          puck.untouched = false;
          if (p.role === 'G') this.emit('save', { by: p });
        }
      }
    }
    if (best) {
      const sp2 = Math.hypot(puck.vx - best.vx, puck.vz - best.vz);
      // goalies "catch" only slow pucks; skaters take anything reasonably slow or
      // anything passed by a teammate.
      const limit = best.role === 'G' ? 9 : (puck.lastTouchTeam === best.team ? 26 : 17);
      if (sp2 < limit) this.possess(best);
      else { puck.untouched = false; puck.lastTouch = best; puck.lastTouchTeam = best.team; }
    }
    // trail for rendering
    const tr = puck.trail;
    tr.push({ x: puck.x, z: puck.z });
    if (tr.length > 14) tr.shift();
  }

  checkSteal(carrier) {
    const puck = this.puck;
    for (const p of this.players) {
      if (p.team === carrier.team || p.pickupCooldown > 0) continue;
      const d = Math.hypot(puck.x - p.x, puck.z - p.z);
      const reach = p.role === 'G' ? p.r + 0.3 : PLAYER.stealReach;
      if (d < reach) { this.possess(p); return; }
    }
  }

  // ---------------------------------------------------------------- rules
  checkRules() {
    const puck = this.puck;
    // Offside: the puck enters the attacking zone while a team-mate of the
    // player who moved it in is already in the zone.
    for (const t of [0, 1]) {
      const dir = this.dirOf(t);
      const inZone = dir * puck.z > RINK.blueLineZ;
      if (inZone && !this.inZone[t]) {
        if (puck.lastTouchTeam === t) {
          const offender = this.skaters(t).find((p) => p !== puck.carrier && p !== puck.lastTouch && dir * p.z > RINK.blueLineZ + 0.6);
          if (offender) {
            const spot = this.nearestFaceoffSpot(FACEOFF_SPOTS.neutral, puck.x, dir * 7);
            this.whistle('OFFSIDE', spot);
            return;
          }
        }
      }
      this.inZone[t] = inZone;
    }
    // Icing: released from the defensive half, crossed the far goal line untouched.
    if (!puck.carrier && puck.untouched && puck.releaseTeam >= 0) {
      const t = puck.releaseTeam;
      const dir = this.dirOf(t);
      if (dir * puck.releaseZ < -0.5 && dir * puck.z > RINK.goalLineZ && Math.abs(puck.x) > RINK.goalWidth / 2) {
        const spot = this.nearestFaceoffSpot(FACEOFF_SPOTS.end.filter((s) => Math.sign(s.z) === -dir), puck.x, -dir * 20);
        this.whistle('ICING', spot);
        return;
      }
    }
  }

  goalScored(team) {
    if (this.state !== 'play') return;
    this.score[team]++;
    this.state = 'goal';
    this.stateTimer = RULES.goalCelebration;
    this.message = 'GOAL!';
    const puck = this.puck;
    let scorer = puck.lastTouch;
    if (scorer && scorer.team !== team && puck.lastShooter && puck.lastShooter.team === team) scorer = puck.lastShooter;
    puck.carrier = null;
    puck.vx *= 0.15; puck.vz *= 0.15;
    for (const p of this.players) { p.controlled = null; p.target = null; }
    this.emit('goal', { team, scorer, ownGoal: scorer && scorer.team !== team });
  }

  endPeriod() {
    if (this.isOvertime) { this.state = 'periodEnd'; this.stateTimer = 2; this.message = 'OVERTIME CONTINUES'; return; }
    if (this.period >= RULES.periods) {
      if (this.score[0] === this.score[1] && this.overtime) {
        this.state = 'periodEnd'; this.stateTimer = 2.5; this.message = 'OVERTIME';
        this.emit('periodEnd', { period: this.period });
        return;
      }
      this.finish();
      return;
    }
    this.state = 'periodEnd';
    this.stateTimer = 2.5;
    this.message = `END OF PERIOD ${this.period}`;
    this.puck.carrier = null;
    for (const p of this.players) { p.controlled = null; p.target = null; }
    this.emit('periodEnd', { period: this.period });
  }

  nextPeriod() {
    if (this.period >= RULES.periods && !this.isOvertime) {
      this.isOvertime = true;
      this.clock = 999; // sudden death, clock shows nothing meaningful
      this.setupFaceoff(FACEOFF_SPOTS.center, 'SUDDEN DEATH');
      return;
    }
    if (this.isOvertime) { this.clock = 999; this.setupFaceoff(FACEOFF_SPOTS.center, 'SUDDEN DEATH'); return; }
    this.period++;
    this.clock = this.periodSeconds;
    this.setupFaceoff(FACEOFF_SPOTS.center, `PERIOD ${this.period}`);
  }

  finish() {
    this.state = 'ended';
    this.ended = true;
    this.message = 'FINAL';
    this.puck.carrier = null;
    for (const p of this.players) { p.controlled = null; p.target = null; }
    this.emit('end', { score: [...this.score] });
  }

  // ---------------------------------------------------------------- input API (used by input.js)
  /** Nearest free skater of the user's team to a world point. */
  pickPlayer(x, z) {
    const free = this.skaters(this.userTeam).filter((p) => p.controlled == null);
    if (!free.length) return null;
    let best = null, bd = Infinity;
    for (const p of free) { const d = Math.hypot(p.x - x, p.z - z); if (d < bd) { bd = d; best = p; } }
    if (bd < 5.5) return best;
    // Far from everyone: take the most relevant player instead.
    const carrier = this.puck.carrier;
    if (carrier && carrier.team === this.userTeam && carrier.controlled == null && carrier.role !== 'G') return carrier;
    let nb = null, nd = Infinity;
    for (const p of free) { const d = Math.hypot(p.x - this.puck.x, p.z - this.puck.z); if (d < nd) { nd = d; nb = p; } }
    return nb;
  }

  /** The user tapped at a world point: pass to the team-mate there or shoot. */
  userTap(x, z) {
    const carrier = this.puck.carrier;
    if (!carrier || carrier.team !== this.userTeam || this.state !== 'play') return false;
    const gz = this.attackGoalZ(this.userTeam);
    const dGoal = Math.hypot(x, z - gz);
    let mate = null, md = Infinity;
    for (const p of this.teamPlayers(this.userTeam)) {
      if (p === carrier || p.role === 'G') continue;
      const d = Math.hypot(p.x - x, p.z - z);
      if (d < md) { md = d; mate = p; }
    }
    if (dGoal < 7.5 && dGoal < md) {
      const half = RINK.goalWidth / 2 - 0.5;
      const aimX = clamp(x, -half, half);
      return this.release(carrier, aimX - carrier.x, gz - carrier.z, 25, 'shot');
    }
    if (mate) return this.passTo(carrier, mate, { accuracy: 1 });
    return false;
  }

  /** The user flicked while dragging a player: shoot in that direction. */
  userFlick(p, dx, dz, strength) {
    if (this.puck.carrier !== p || this.state !== 'play') return false;
    const power = clamp(strength, 13, 27);
    return this.release(p, dx, dz, power, 'shot');
  }
}
