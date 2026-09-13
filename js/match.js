import { RINK, PLAYER, PUCK, RULES, ORBIT, FACEOFF_SPOTS } from './config.js';
import { clamp, norm, sdRoundRect, roundRectNormal, rand, noise } from './math.js';
import { updateTeamAI } from './ai.js';

const HW = RINK.width / 2;
const HL = RINK.length / 2;

// Formation home positions for a full team attacking +Z. Mirrored for team 1.
const FORMATION = [
  { role: 'G', x: 0, z: -25 },
  { role: 'D', x: -6.5, z: -17 },
  { role: 'D', x: 6.5, z: -17 },
  { role: 'F', x: -9, z: -5 },
  { role: 'F', x: 0, z: -3 },
  { role: 'F', x: 9, z: -5 },
];

let nextPlayerId = 1;

export function angleDiff(a, b) {
  let d = a - b;
  while (d > Math.PI) d -= Math.PI * 2;
  while (d < -Math.PI) d += Math.PI * 2;
  return d;
}

/**
 * The match engine. The user never steers anyone: every player skates on
 * its own. When a player of the user's team holds the puck, it circles the
 * player and is released (pass or shot) when the user lifts their finger.
 *
 * opts: { home, away, tactics, periodSeconds, overtime, onEvent, rules,
 *         autoUser (AI releases for the user's team too, used by the demo),
 *         scenario (training drill, see levels.js), orbitPeriod }
 */
export class Match {
  constructor(opts) {
    this.teams = [opts.home, opts.away];
    this.tactics = [opts.tactics?.[0] ?? opts.home.tactics, opts.tactics?.[1] ?? opts.away.tactics];
    this.periodSeconds = opts.periodSeconds ?? RULES.periodSeconds;
    this.overtime = !!opts.overtime;
    this.onEvent = opts.onEvent || (() => {});
    this.userTeam = 0;
    this.autoUser = !!opts.autoUser;
    this.scenario = opts.scenario || null;
    this.training = !!this.scenario;
    this.rules = { offside: RULES.offside, icing: RULES.icing, ...(opts.rules || {}), ...(this.scenario?.rules || {}) };
    this.orbitSpeed = (Math.PI * 2) / (opts.orbitPeriod || ORBIT.period);
    this.userPower = ORBIT.powerDefault;

    this.players = [];
    if (this.scenario) {
      this.scenario.home.forEach((spec) => this.addPlayer(0, spec));
      this.scenario.away.forEach((spec) => this.addPlayer(1, spec));
    } else {
      for (let t = 0; t < 2; t++) {
        const dir = t === 0 ? 1 : -1;
        FORMATION.forEach((f) => this.addPlayer(t, { role: f.role, x: f.x * (t === 0 ? 1 : -1), z: f.z * dir }));
      }
    }

    this.puck = { x: 0, z: 0, vx: 0, vz: 0, r: PUCK.radius, carrier: null, orbit: 0, orbitDir: 1,
      lastTouch: null, lastTouchTeam: -1, lastShooter: null, assist: null,
      releaseZ: 0, releaseTeam: -1, untouched: false, shotTime: -9, trail: [] };

    this.score = [0, 0];
    this.period = 1;
    this.clock = this.training ? (this.scenario.time || 60) : this.periodSeconds;
    this.goalsToWin = this.training ? (this.scenario.goals || 3) : 0;
    this.state = 'faceoff';
    this.stateTimer = 0;
    this.inZone = [false, false];
    this.message = '';
    this.events = [];
    this.stats = { shots: [0, 0], passes: [0, 0], steals: [0, 0] };
    this.time = 0;
    this.ended = false;
    this.won = null;
    this.isOvertime = false;
    this.pendingFaceoff = FACEOFF_SPOTS.center;
    this.pendingText = 'FACE-OFF';
    this.pendingRelease = null;

    if (this.training) this.setupDrill('GET READY');
    else this.setupFaceoff(FACEOFF_SPOTS.center, 'PERIOD 1');
  }

  addPlayer(team, spec) {
    const rating = this.teams[team].rating;
    const role = spec.role || 'F';
    const behavior = spec.behavior || (role === 'O' ? 'static' : 'active');
    const speed = spec.speed ?? 1;
    const p = {
      id: nextPlayerId++, team, role, idx: this.players.filter((q) => q.team === team).length,
      home: { x: spec.x, z: spec.z }, start: { x: spec.x, z: spec.z },
      x: spec.x, z: spec.z, vx: 0, vz: 0,
      r: role === 'G' ? PLAYER.goalieRadius : role === 'O' ? spec.r || 0.9 : PLAYER.radius,
      facing: team === 0 ? 0 : Math.PI,
      maxSpeed: (role === 'G' ? PLAYER.goalieSpeed : PLAYER.aiSpeedBase + (rating - 60) * 0.045) * speed,
      behavior,                                   // 'active' | 'static' | 'patrol'
      canPickup: behavior === 'active' && (spec.canPickup ?? true),
      canSteal: behavior === 'active' && (spec.canSteal ?? true),
      patrol: spec.patrol ? { x: spec.patrol.x, z: spec.patrol.z, speed: spec.patrol.speed || 1, phase: spec.patrol.phase || 0 } : null,
      target: null,
      pickupCooldown: 0,
      ai: { timer: Math.random() * 0.2, holdTime: 0, decision: null, mark: null, expectPass: 0 },
    };
    this.players.push(p);
    return p;
  }

  // ---------------------------------------------------------------- helpers
  dirOf(team) { return team === 0 ? 1 : -1; }
  ownGoalZ(team) { return -this.dirOf(team) * RINK.goalLineZ; }
  attackGoalZ(team) { return this.dirOf(team) * RINK.goalLineZ; }
  skaters(team) { return this.players.filter((p) => p.team === team && p.role !== 'G' && p.role !== 'O'); }
  goalie(team) { return this.players.find((p) => p.team === team && p.role === 'G'); }
  teamPlayers(team) { return this.players.filter((p) => p.team === team); }
  opponents(team) { return this.players.filter((p) => p.team !== team); }
  carrierTeam() { return this.puck.carrier ? this.puck.carrier.team : -1; }
  isUserCarrier(p) { return p.team === this.userTeam && p.role !== 'G' && !this.autoUser; }

  emit(type, data = {}) {
    const e = { type, time: this.time, ...data };
    this.events.push(e);
    this.onEvent(e);
  }

  /** Where the puck sits while it circles the carrier. */
  carryPoint(p) {
    const a = this.puck.carrier === p ? this.puck.orbit : p.facing;
    return { x: p.x + Math.sin(a) * ORBIT.radius, z: p.z + Math.cos(a) * ORBIT.radius };
  }

  /**
   * Spin the puck towards the most likely target so the player never waits
   * for the long way round: the goal when in range, else the best team-mate.
   */
  chooseOrbitDir(p) {
    const gz = this.attackGoalZ(p.team);
    const dir = this.dirOf(p.team);
    const dGoal = Math.hypot(p.x, gz - p.z);
    let aim = null;
    if (dGoal < 24 && Math.abs(p.x) < 13) aim = Math.atan2(0 - p.x, gz - p.z);
    else {
      let best = null, bs = -Infinity;
      for (const m of this.teamPlayers(p.team)) {
        if (m === p || m.role === 'G' || m.role === 'O') continue;
        const d = Math.hypot(m.x - p.x, m.z - p.z);
        if (d < 3) continue;
        let open = 9;
        for (const o of this.opponents(p.team)) open = Math.min(open, Math.hypot(o.x - m.x, o.z - m.z));
        const score = open + dir * (m.z - p.z) * 0.4 - Math.max(0, d - 18) * 0.5;
        if (score > bs) { bs = score; best = m; }
      }
      if (best) aim = Math.atan2(best.x - p.x, best.z - p.z);
    }
    if (aim == null) return 1;
    return angleDiff(aim, this.puck.orbit) >= 0 ? 1 : -1;
  }

  /** Unit vector the puck would be released along right now. */
  aimDirection() { return { x: Math.sin(this.puck.orbit), z: Math.cos(this.puck.orbit) }; }

  /**
   * What a release from p would snap to at the current orbit angle:
   * { kind: 'pass', target } | { kind: 'goal' } | null.
   */
  aimTarget(p) {
    const a = this.puck.orbit;
    let best = null, bestDiff = Infinity;
    for (const m of this.teamPlayers(p.team)) {
      if (m === p || m.role === 'G' || m.role === 'O') continue;
      const d = Math.hypot(m.x - p.x, m.z - p.z);
      const t = d / Math.max(ORBIT.passSpeedMin, 11 + d * 0.55);
      const ang = Math.atan2(m.x + m.vx * t * 0.8 - p.x, m.z + m.vz * t * 0.8 - p.z);
      const diff = Math.abs(angleDiff(ang, a));
      if (diff < ORBIT.assistPass && diff < bestDiff) { bestDiff = diff; best = { kind: 'pass', target: m, diff }; }
    }
    const gz = this.attackGoalZ(p.team);
    const gAng = Math.atan2(0 - p.x, gz - p.z);
    const gDiff = Math.abs(angleDiff(gAng, a));
    const dGoal = Math.hypot(p.x, gz - p.z);
    // the goal mouth is wide up close: widen the snap window with proximity
    const goalWindow = ORBIT.assistGoal + clamp((14 - dGoal) / 14, 0, 1) * 0.3;
    if (gDiff < goalWindow && (!best || gDiff < bestDiff * 0.9 || dGoal < 9)) best = { kind: 'goal', diff: gDiff };
    return best;
  }

  // ---------------------------------------------------------------- faceoffs / drills
  resetPuckState() {
    const puck = this.puck;
    this.pendingRelease = null;
    puck.carrier = null; puck.vx = 0; puck.vz = 0;
    puck.lastTouch = null; puck.lastTouchTeam = -1; puck.lastShooter = null; puck.assist = null;
    puck.untouched = false; puck.trail.length = 0;
    this.inZone = [false, false];
    for (const p of this.players) {
      p.vx = p.vz = 0; p.target = null; p.pickupCooldown = 0;
      p.ai.holdTime = 0; p.ai.decision = null; p.ai.mark = null; p.ai.expectPass = 0;
    }
  }

  setupFaceoff(spot, text) {
    this.state = 'faceoff';
    this.stateTimer = RULES.faceoffDelay;
    this.message = text || 'FACE-OFF';
    this.resetPuckState();
    this.puck.x = spot.x; this.puck.z = spot.z;
    for (const p of this.players) {
      const dir = this.dirOf(p.team);
      const side = p.team === 0 ? 1 : -1;
      let x, z;
      switch (p.idx) {
        case 0: x = 0; z = this.ownGoalZ(p.team) + dir * 1.3; break;               // goalie
        case 1: x = spot.x - 4.5 * side; z = spot.z - dir * 8; break;               // D
        case 2: x = spot.x + 4.5 * side; z = spot.z - dir * 8; break;               // D
        case 3: x = spot.x - 5.5 * side; z = spot.z - dir * 1.4; break;             // LW
        case 4: x = spot.x; z = spot.z - dir * 1.5; break;                          // C
        default: x = spot.x + 5.5 * side; z = spot.z - dir * 1.4; break;            // RW
      }
      p.x = clamp(x, -HW + 2, HW - 2);
      p.z = clamp(z, -HL + 2, HL - 2);
      if (p.role !== 'G' && Math.abs(p.z - this.ownGoalZ(p.team)) < 3) p.z = this.ownGoalZ(p.team) + dir * 3;
      p.facing = dir > 0 ? 0 : Math.PI;
    }
    this.emit('faceoff', { spot, text: this.message });
  }

  /** Training: everyone back to their start spot, puck to the chosen player. */
  setupDrill(text) {
    this.state = 'ready';
    this.stateTimer = RULES.drillReady;
    this.message = text;
    this.resetPuckState();
    for (const p of this.players) {
      p.x = p.start.x; p.z = p.start.z;
      p.facing = p.team === 0 ? 0 : Math.PI;
    }
    const holder = this.teamPlayers(0)[this.scenario.puckTo || 0] || this.teamPlayers(0)[0];
    if (holder) {
      this.puck.orbit = holder.facing + Math.PI; // start behind the player
      this.possess(holder, true);
    } else { this.puck.x = 0; this.puck.z = 0; }
    this.emit('drill', { text });
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
    this.emit('whistle', { text });
  }

  /** Training: the other side got the puck. */
  lostPuck(text) {
    if (this.state !== 'play') return;
    this.state = 'lost';
    this.stateTimer = RULES.drillLost;
    this.message = text;
    this.emit('lost', { text });
  }

  // ---------------------------------------------------------------- actions
  possess(p, silent = false) {
    const puck = this.puck;
    if (puck.carrier === p) return;
    const prev = puck.carrier;
    if (prev && prev.team !== p.team) { this.stats.steals[p.team]++; prev.pickupCooldown = 0.6; if (!silent) this.emit('steal', { by: p, from: prev }); }
    if (puck.lastTouchTeam !== -1 && puck.lastTouchTeam !== p.team && !prev && !silent) this.emit('intercept', { by: p });
    // remember who set this player up (for assists / give-and-go drills)
    puck.assist = puck.lastTouch && puck.lastTouch !== p && puck.lastTouch.team === p.team ? puck.lastTouch : null;
    puck.carrier = p;
    puck.vx = puck.vz = 0;
    if (!silent) puck.orbit = Math.atan2(puck.x - p.x, puck.z - p.z);
    puck.orbitDir = this.chooseOrbitDir(p);
    const cp = this.carryPoint(p);
    puck.x = cp.x; puck.z = cp.z;
    puck.lastTouch = p; puck.lastTouchTeam = p.team; puck.untouched = false;
    p.ai.holdTime = 0;
    p.ai.decision = null;
    if (!silent) this.emit('possess', { by: p });
    // training: the defence has it -> drill over
    if (this.training && !this.scenario.freePlay && p.team === 1 && this.state === 'play') {
      this.lostPuck(p.role === 'G' ? 'SAVED!' : 'STOLEN!');
    }
  }

  release(p, dx, dz, speed, kind = 'shot') {
    const puck = this.puck;
    if (puck.carrier !== p) return false;
    const n = norm(dx, dz);
    if (n.x === 0 && n.z === 0) return false;
    const cp = this.carryPoint(p);
    if (Math.abs(cp.z) > RINK.goalLineZ - 0.3 && Math.abs(cp.x) < RINK.goalWidth / 2 + 0.6) {
      cp.x = p.x; cp.z = clamp(p.z, -(RINK.goalLineZ - 0.5), RINK.goalLineZ - 0.5);
    }
    puck.carrier = null;
    puck.x = cp.x; puck.z = cp.z;
    puck.lastShooter = p;
    puck.vx = n.x * speed + p.vx * 0.2;
    puck.vz = n.z * speed + p.vz * 0.2;
    puck.lastTouch = p; puck.lastTouchTeam = p.team;
    puck.releaseZ = puck.z; puck.releaseTeam = p.team; puck.untouched = true; puck.shotTime = this.time;
    p.pickupCooldown = 0.45;
    p.facing = Math.atan2(n.x, n.z);
    if (kind === 'shot') this.stats.shots[p.team]++; else this.stats.passes[p.team]++;
    this.emit(kind, { by: p, speed });
    return true;
  }

  passTo(p, receiver, opts = {}) {
    const acc = opts.accuracy ?? 1;
    const dx0 = receiver.x - p.x, dz0 = receiver.z - p.z;
    const d = Math.hypot(dx0, dz0);
    const speed = clamp(11 + d * 0.55, ORBIT.passSpeedMin, 24) * (opts.speedScale ?? 1);
    const t = d / speed;
    let tx = receiver.x + receiver.vx * t * 0.8;
    let tz = receiver.z + receiver.vz * t * 0.8;
    tx += noise(1.6 * (1.15 - acc)); tz += noise(1.6 * (1.15 - acc));
    const ok = this.release(p, tx - p.x, tz - p.z, speed, 'pass');
    if (ok) { receiver.ai.expectPass = 1.6; receiver.ai.timer = 0; }
    return ok;
  }

  shootAtGoal(p, opts = {}) {
    const acc = opts.accuracy ?? 1;
    const power = opts.power ?? ORBIT.shotSpeed;
    const gz = this.attackGoalZ(p.team);
    const goalie = this.goalie(1 - p.team);
    const half = RINK.goalWidth / 2 - 0.85;
    let aimX = goalie ? (goalie.x > 0 ? -half : half) : (Math.random() < 0.5 ? -half : half);
    if (Math.random() < 0.25) aimX *= 0.3;
    aimX += noise(1.5 * (1.2 - acc));
    return this.release(p, aimX - p.x, gz - p.z, power, 'shot');
  }

  /** Release along the current orbit direction, snapping to a team-mate or the goal. */
  releaseAimed(p, opts = {}) {
    if (this.puck.carrier !== p) return false;
    const snap = opts.assist === false ? null : this.aimTarget(p);
    const acc = opts.accuracy ?? 1;
    const pw = opts.power; // 0..1 from the drag gesture, undefined for AI
    if (snap?.kind === 'pass') {
      const scale = pw == null ? 1 : ORBIT.passScaleMin + pw * (ORBIT.passScaleMax - ORBIT.passScaleMin);
      return this.passTo(p, snap.target, { accuracy: acc, speedScale: scale });
    }
    const speed = pw == null ? ORBIT.shotSpeed : ORBIT.shotSpeedMin + pw * (ORBIT.shotSpeedMax - ORBIT.shotSpeedMin);
    if (snap?.kind === 'goal') return this.shootAtGoal(p, { accuracy: acc, power: speed });
    const d = this.aimDirection();
    return this.release(p, d.x, d.z, pw == null ? ORBIT.freeSpeed : speed * 0.85, 'shot');
  }

  /**
   * The user lifted their finger. If the line is about to reach a target
   * within a fraction of a second, wait for it (forgives early taps).
   */
  userRelease(power) {
    const c = this.puck.carrier;
    if (power != null) this.userPower = power;
    if (!c || !this.isUserCarrier(c) || this.state !== 'play') return false;
    if (this.aimTarget(c)) return this.releaseAimed(c, { assist: true, accuracy: 1, power: this.userPower });
    const saved = this.puck.orbit;
    for (const t of [0.05, 0.1, 0.15, 0.2, 0.25]) {
      this.puck.orbit = saved + this.orbitSpeed * t * this.puck.orbitDir;
      const hit = this.aimTarget(c);
      this.puck.orbit = saved;
      if (hit) { this.pendingRelease = { player: c, until: this.time + t + 0.06 }; return true; }
    }
    return this.releaseAimed(c, { assist: true, accuracy: 1, power: this.userPower });
  }

  // ---------------------------------------------------------------- update
  update(dt) {
    if (this.ended) return;
    this.time += dt;
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
      case 'ready':
        this.stateTimer -= dt;
        if (this.stateTimer <= 0) { this.state = 'play'; this.message = ''; this.emit('go'); }
        break;
      case 'whistle':
        this.stateTimer -= dt;
        if (this.stateTimer <= 0) this.setupFaceoff(this.pendingFaceoff, this.pendingText);
        break;
      case 'lost':
        this.stateTimer -= dt;
        if (this.stateTimer <= 0) this.setupDrill('AGAIN!');
        break;
      case 'goal':
        this.stateTimer -= dt;
        // let the puck ripple into the mesh instead of freezing on the line
        if (this.goalInfo) {
          const g = this.goalInfo;
          puck.x += puck.vx * dt; puck.z += puck.vz * dt;
          const f = Math.exp(-4 * dt); puck.vx *= f; puck.vz *= f;
          const back = g.goalZ - g.dir * (RINK.goalDepth - puck.r);
          if (g.dir > 0 ? puck.z < back : puck.z > back) { puck.z = back; puck.vz = -puck.vz * 0.2; }
          const hw = RINK.goalWidth / 2 - puck.r;
          if (Math.abs(puck.x) > hw) { puck.x = Math.sign(puck.x) * hw; puck.vx = -puck.vx * 0.2; }
        }
        if (this.stateTimer <= 0) {
          if (this.training) {
            if (this.score[0] >= this.goalsToWin) { this.finish(true); break; }
            this.setupDrill('NICE! AGAIN');
            break;
          }
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
      if (this.clock <= 0) { this.clock = 0; this.training ? this.finish(false) : this.endPeriod(); }
    }
    const moving = live || this.state === 'ready';
    if (live) { updateTeamAI(this, 0, dt); updateTeamAI(this, 1, dt); }
    for (const p of this.players) this.movePlayer(p, dt, live);
    this.collidePlayers();
    for (const p of this.players) this.constrainPlayer(p);
    if (live) this.updatePuck(dt);
    else if (puck.carrier) {
      if (this.state === 'ready') puck.orbit += this.orbitSpeed * dt * puck.orbitDir;
      const cp = this.carryPoint(puck.carrier); puck.x = cp.x; puck.z = cp.z;
    }
    if (live) this.checkRules();
    // training: a puck nobody can reach resets the drill
    if (live && this.training) {
      this.looseTimer = puck.carrier ? 0 : (this.looseTimer || 0) + dt;
      if (this.looseTimer > 10) { this.looseTimer = 0; this.lostPuck("RESET"); }
    }
    void moving;
  }

  movePlayer(p, dt, live) {
    if (p.pickupCooldown > 0) p.pickupCooldown -= dt;
    if (p.behavior === 'static') { p.vx = p.vz = 0; return; }
    if (p.behavior === 'patrol') {
      const k = 0.5 + 0.5 * Math.sin(this.time * p.patrol.speed + p.patrol.phase);
      const nx = p.start.x + (p.patrol.x - p.start.x) * k;
      const nz = p.start.z + (p.patrol.z - p.start.z) * k;
      p.vx = (nx - p.x) / dt; p.vz = (nz - p.z) / dt;
      p.x = nx; p.z = nz;
      return;
    }
    let dvx = 0, dvz = 0;
    if (live && p.target) {
      const dx = p.target.x - p.x, dz = p.target.z - p.z;
      const d = Math.hypot(dx, dz);
      const want = Math.min(p.maxSpeed, d * 6);
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
      p.facing += angleDiff(want, p.facing) * Math.min(1, dt * 14);
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
          const nx = dx / d, nz = dz / d;
          const aFixed = a.behavior !== 'active', bFixed = b.behavior !== 'active';
          const pa = aFixed ? 0 : bFixed ? min - d : (min - d) / 2;
          const pb = bFixed ? 0 : aFixed ? min - d : (min - d) / 2;
          a.x -= nx * pa; a.z -= nz * pa;
          b.x += nx * pb; b.z += nz * pb;
          const rel = (b.vx - a.vx) * nx + (b.vz - a.vz) * nz;
          if (rel < 0) {
            if (!aFixed) { a.vx += nx * rel * 0.5; a.vz += nz * rel * 0.5; }
            if (!bFixed) { b.vx -= nx * rel * 0.5; b.vz -= nz * rel * 0.5; }
          }
        }
      }
    }
  }

  constrainPlayer(p) {
    if (p.behavior !== 'active') return;
    const sd = sdRoundRect(p.x, p.z, HW, HL, RINK.corner);
    if (sd > -p.r) {
      const n = roundRectNormal(p.x, p.z, HW, HL, RINK.corner);
      const pen = sd + p.r;
      p.x -= n.x * pen; p.z -= n.z * pen;
      const vn = p.vx * n.x + p.vz * n.z;
      if (vn > 0) { p.vx -= n.x * vn; p.vz -= n.z * vn; }
    }
    for (const t of [0, 1]) {
      const gz = this.ownGoalZ(t);
      const dir = this.dirOf(t);
      const zMin = Math.min(gz, gz - dir * RINK.goalDepth) - p.r;
      const zMax = Math.max(gz, gz - dir * RINK.goalDepth) + p.r;
      const hx = RINK.goalWidth / 2 + p.r;
      if (Math.abs(p.x) < hx && p.z > zMin && p.z < zMax) {
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
      puck.orbit += this.orbitSpeed * dt * puck.orbitDir;
      if (puck.orbit > Math.PI) puck.orbit -= Math.PI * 2;
      if (puck.orbit < -Math.PI) puck.orbit += Math.PI * 2;
      const cp = this.carryPoint(c);
      puck.x = cp.x; puck.z = cp.z; puck.vx = c.vx; puck.vz = c.vz;
      const pr = this.pendingRelease;
      if (pr) {
        if (pr.player !== c) this.pendingRelease = null;
        else if (this.aimTarget(c) || this.time >= pr.until) { this.pendingRelease = null; this.releaseAimed(c, { assist: true, accuracy: 1, power: this.userPower }); return; }
      }
      if (c.role !== 'G') this.checkSteal(c, dt);
      return;
    }
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
      const gz = this.ownGoalZ(t);
      const dir = this.dirOf(t);
      const hw = RINK.goalWidth / 2 + 0.15;
      const zFront = gz, zBack = gz - dir * (RINK.goalDepth + 0.15);
      const zMin = Math.min(zFront, zBack) - puck.r, zMax = Math.max(zFront, zBack) + puck.r;
      if (Math.abs(puck.x) < hw + puck.r && puck.z > zMin && puck.z < zMax) {
        const wasInFront = dir * (prevZ - gz) >= -puck.r * 0.5;
        const crossedLine = dir * (puck.z - gz) < -puck.r * 0.5;
        if (wasInFront && Math.abs(prevX) < RINK.goalWidth / 2 - puck.r * 0.3) {
          if (crossedLine) { this.goalScored(1 - t); return; }
          continue;
        }
        if (wasInFront) continue;
        const pushSide = hw + puck.r - Math.abs(puck.x);
        const pushBack = dir > 0 ? (puck.z - zMin) : (zMax - puck.z);
        if (pushSide < pushBack) { puck.x += (puck.x >= 0 ? 1 : -1) * pushSide; puck.vx = -puck.vx * PUCK.boardRestitution; }
        else { puck.z += dir > 0 ? -pushBack : pushBack; puck.vz = -puck.vz * PUCK.boardRestitution; }
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
          if (vn < 0) { puck.vx -= 1.8 * vn * nx; puck.vz -= 1.8 * vn * nz; }
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
      if (p.canPickup && d < reach && p.pickupCooldown <= 0 && d < bestD) { best = p; bestD = d; }
      const min = p.r + puck.r;
      if (d < min && d > 1e-4) {
        const nx = dx / d, nz = dz / d;
        puck.x = p.x + nx * min; puck.z = p.z + nz * min;
        const rvx = puck.vx - p.vx, rvz = puck.vz - p.vz;
        const vn = rvx * nx + rvz * nz;
        if (vn < 0) {
          const rest = p.role === 'G' ? 0.35 : PUCK.playerRestitution; // goalies smother rebounds
          puck.vx -= (1 + rest) * vn * nx;
          puck.vz -= (1 + rest) * vn * nz;
          puck.untouched = false;
          if (p.role === 'G') this.emit('save', { by: p });
          else if (p.role === 'O') this.emit('block', { by: p });
        }
      }
    }
    if (best) {
      const sp2 = Math.hypot(puck.vx - best.vx, puck.vz - best.vz);
      const limit = best.role === 'G' ? 9 : (puck.lastTouchTeam === best.team ? 27 : 17);
      if (sp2 < limit) this.possess(best);
      else { puck.untouched = false; puck.lastTouch = best; puck.lastTouchTeam = best.team; }
    }
    const tr = puck.trail;
    tr.push({ x: puck.x, z: puck.z });
    if (tr.length > 14) tr.shift();
  }

  checkSteal(carrier, dt) {
    const puck = this.puck;
    for (const p of this.players) {
      if (p.team === carrier.team || p.pickupCooldown > 0 || !p.canSteal) continue;
      const d = Math.hypot(puck.x - p.x, puck.z - p.z);
      const reach = p.role === 'G' ? p.r + 0.3 : PLAYER.stealReach;
      // a steal needs a moment of contact, so the circling puck can slip past
      if (d < reach) p.ai.stealCharge = (p.ai.stealCharge || 0) + dt;
      else p.ai.stealCharge = Math.max(0, (p.ai.stealCharge || 0) - dt * 2);
      if (p.ai.stealCharge >= PLAYER.stealTime) { p.ai.stealCharge = 0; this.possess(p); return; }
    }
  }

  // ---------------------------------------------------------------- rules
  checkRules() {
    const puck = this.puck;
    if (this.rules.offside) {
      for (const t of [0, 1]) {
        const dir = this.dirOf(t);
        const inZone = dir * puck.z > RINK.blueLineZ;
        if (inZone && !this.inZone[t] && puck.lastTouchTeam === t) {
          const offender = this.skaters(t).find((p) => p !== puck.carrier && p !== puck.lastTouch && dir * p.z > RINK.blueLineZ + 0.6);
          if (offender) {
            const spot = this.nearestFaceoffSpot(FACEOFF_SPOTS.neutral, puck.x, dir * 7);
            this.whistle('OFFSIDE', spot);
            return;
          }
        }
        this.inZone[t] = inZone;
      }
    }
    if (this.rules.icing && !puck.carrier && puck.untouched && puck.releaseTeam >= 0) {
      const t = puck.releaseTeam;
      const dir = this.dirOf(t);
      if (dir * puck.releaseZ < -0.5 && dir * puck.z > RINK.goalLineZ && Math.abs(puck.x) > RINK.goalWidth / 2) {
        const spot = this.nearestFaceoffSpot(FACEOFF_SPOTS.end.filter((s) => Math.sign(s.z) === -dir), puck.x, -dir * 20);
        this.whistle('ICING', spot);
      }
    }
  }

  goalScored(team) {
    if (this.state !== 'play') return;
    const puck = this.puck;
    let scorer = puck.lastTouch;
    if (scorer && scorer.team !== team && puck.lastShooter && puck.lastShooter.team === team) scorer = puck.lastShooter;
    if (this.training && team === 1 && !this.scenario.freePlay) {
      this.state = 'lost'; this.stateTimer = RULES.drillLost; this.message = 'WRONG NET!';
      puck.carrier = null; puck.vx *= 0.1; puck.vz *= 0.1;
      this.emit('lost', { text: 'WRONG NET!' });
      return;
    }
    // training drills can demand a pass before the goal
    if (this.training && team === 0 && this.scenario.requireAssist && !(puck.lastShooter && puck.assist)) {
      this.state = 'lost'; this.stateTimer = RULES.drillLost; this.message = 'PASS FIRST!';
      puck.carrier = null; puck.vx *= 0.1; puck.vz *= 0.1;
      this.emit('lost', { text: 'PASS FIRST!' });
      return;
    }
    this.score[team]++;
    this.state = 'goal';
    this.stateTimer = this.training ? RULES.drillGoal : RULES.goalCelebration;
    this.message = 'GOAL!';
    puck.carrier = null;
    this.goalInfo = { team, goalZ: this.ownGoalZ(1 - team), dir: this.dirOf(1 - team), x: puck.x, z: puck.z };
    this.emit('goal', { team, scorer, assist: puck.assist, ownGoal: scorer && scorer.team !== team, goalZ: this.goalInfo.goalZ });
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
    this.emit('periodEnd', { period: this.period });
  }

  nextPeriod() {
    if (this.period >= RULES.periods) {
      this.isOvertime = true;
      this.clock = 999;
      this.setupFaceoff(FACEOFF_SPOTS.center, 'SUDDEN DEATH');
      return;
    }
    this.period++;
    this.clock = this.periodSeconds;
    this.setupFaceoff(FACEOFF_SPOTS.center, `PERIOD ${this.period}`);
  }

  finish(won) {
    this.state = 'ended';
    this.ended = true;
    this.won = won ?? (this.score[0] > this.score[1] ? true : this.score[0] < this.score[1] ? false : null);
    this.message = this.training ? (won ? 'LEVEL COMPLETE!' : "TIME'S UP") : 'FINAL';
    this.puck.carrier = null;
    this.emit('end', { score: [...this.score], won: this.won });
  }
}
